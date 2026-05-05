# Net.gd — autoload — minimal Socket.IO v4 client over Godot WebSocketPeer.
#
# Implements just enough of the Engine.IO v4 + Socket.IO v4 framing protocol
# to talk to the v2-compatible TS server in server/src/index.ts:
#
#   Engine.IO packet types (first char of the frame):
#     0  OPEN       server → client, with JSON {sid,upgrades,pingInterval,pingTimeout}
#     1  CLOSE
#     2  PING       server → client (heartbeat)
#     3  PONG       client → server (response to PING)
#     4  MESSAGE    payload is a Socket.IO packet (see below)
#
#   Socket.IO packet types (first char AFTER the leading 4):
#     0  CONNECT    we send "40" right after Engine.IO OPEN
#     1  DISCONNECT
#     2  EVENT      "42" + JSON-encoded ["event", arg1, arg2, ...]
#     3  ACK
#     4  CONNECT_ERROR
#
# The TS server (Socket.IO 4.x) honors all of the above. We don't implement
# binary attachments (5/6) — every event in the v3 wire protocol is JSON.
#
# Public API:
#   Net.connect_to_server(url := "")          # url defaults from window.location
#   Net.emit(event_name: String, args: Array) # fire-and-forget
#   signal connected(), disconnected(), event(name: String, args: Array), error(msg)
#
# Higher-level adapters (GameState.gd) listen to `event` and route per
# event name. Net.gd does not own room state — only the wire.

extends Node

signal connected
signal disconnected
signal event(name: String, args: Array)
signal connection_error(message: String)

var _socket: WebSocketPeer = WebSocketPeer.new()
var _state: int = WebSocketPeer.STATE_CLOSED
var _last_state: int = -1
var _eio_open: bool = false      # received Engine.IO OPEN ("0{...}")
var _sio_open: bool = false      # received Socket.IO CONNECT ("40")
var _url: String = ""
var _ping_interval_ms: int = 25000
var _last_ping_ms: int = 0

# Default URL: same-origin in the browser (replaces 5173 with 3000),
# localhost:3000 on desktop. Browsers serve the HTML5 build at 5173 (see
# scripts/serve-html5.sh) but the Socket.IO server lives on 3000. The
# Engine.IO query-string is mandatory: ?EIO=4&transport=websocket.
func _default_url() -> String:
	# OS.has_feature("web") is the canonical Godot 4 web check.
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var loc: Variant = JavaScriptBridge.eval("window.location.host", true)
		if typeof(loc) == TYPE_STRING and (loc as String).length() > 0:
			var s: String = loc as String
			# 5173 (vite-style serve) → 3000 (server)
			s = s.replace(":5173", ":3000")
			var proto: Variant = JavaScriptBridge.eval("window.location.protocol", true)
			var ws_proto: String = "ws"
			if typeof(proto) == TYPE_STRING and (proto as String).begins_with("https"):
				ws_proto = "wss"
			return "%s://%s/socket.io/?EIO=4&transport=websocket" % [ws_proto, s]
	return "ws://localhost:3000/socket.io/?EIO=4&transport=websocket"

func _ready() -> void:
	set_process(true)

func connect_to_server(url := "") -> void:
	_url = url if url.length() > 0 else _default_url()
	_eio_open = false
	_sio_open = false
	var err := _socket.connect_to_url(_url)
	if err != OK:
		connection_error.emit("connect_to_url failed: %d" % err)

func is_open() -> bool:
	return _sio_open

func emit(event_name: String, args: Array = []) -> void:
	if not _sio_open:
		push_warning("Net.emit before SIO open: %s" % event_name)
		return
	var payload := [event_name]
	payload.append_array(args)
	var frame := "42" + JSON.stringify(payload)
	_socket.send_text(frame)

func _process(_delta: float) -> void:
	_socket.poll()
	_state = _socket.get_ready_state()
	if _state != _last_state:
		_last_state = _state
		if _state == WebSocketPeer.STATE_CLOSED:
			_eio_open = false
			_sio_open = false
			disconnected.emit()
	if _state != WebSocketPeer.STATE_OPEN:
		return
	# Drain pending packets.
	while _socket.get_available_packet_count() > 0:
		var pkt := _socket.get_packet()
		var msg := pkt.get_string_from_utf8()
		_handle_message(msg)
	# Lazy heartbeat — server sends PING ("2") which we PONG ("3");
	# the protocol does not require client-initiated pings unless the
	# socket goes idle for > pingInterval.
	if _eio_open:
		var now_ms := Time.get_ticks_msec()
		if _last_ping_ms == 0:
			_last_ping_ms = now_ms

func _handle_message(msg: String) -> void:
	if msg.length() == 0:
		return
	var head := msg[0]
	match head:
		"0":
			# Engine.IO OPEN handshake. Body is JSON with timeouts.
			_eio_open = true
			var body := msg.substr(1)
			var parsed = JSON.parse_string(body)
			if typeof(parsed) == TYPE_DICTIONARY:
				_ping_interval_ms = int(parsed.get("pingInterval", 25000))
			# Send Socket.IO CONNECT (default namespace).
			_socket.send_text("40")
		"1":
			# Engine.IO CLOSE
			_socket.close()
		"2":
			# Engine.IO PING (server → client). Reply PONG.
			_socket.send_text("3")
		"3":
			pass # Engine.IO PONG (we never send PINGs in this client)
		"4":
			# Engine.IO MESSAGE — wraps a Socket.IO packet.
			_handle_sio_packet(msg.substr(1))
		_:
			pass

func _handle_sio_packet(pkt: String) -> void:
	if pkt.length() == 0:
		return
	var t := pkt[0]
	match t:
		"0":
			# Socket.IO CONNECT (default namespace handshake done).
			_sio_open = true
			connected.emit()
		"1":
			_sio_open = false
			disconnected.emit()
		"2":
			# Socket.IO EVENT — payload is a JSON array.
			# Optional ack id between "2" and "[" — strip digits.
			var rest := pkt.substr(1)
			var i := 0
			while i < rest.length() and (rest[i] >= "0" and rest[i] <= "9"):
				i += 1
			rest = rest.substr(i)
			var arr = JSON.parse_string(rest)
			if typeof(arr) == TYPE_ARRAY and (arr as Array).size() >= 1:
				var name := str(arr[0])
				var args: Array = (arr as Array).slice(1)
				event.emit(name, args)
		"4":
			# Socket.IO CONNECT_ERROR
			connection_error.emit(pkt.substr(1))
		_:
			pass

func disconnect_socket() -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close()
