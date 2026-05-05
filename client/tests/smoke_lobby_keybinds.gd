## smoke_lobby_keybinds.gd — verifies the S-205 lobby keybinds wire to
## GameState the same way the Buttons do.
##
## Background. In the live HTML5 build, headless chromium drivers
## (Playwright / chrome-devtools MCP) cannot reliably synthesize a
## click that the Godot Button.pressed signal accepts: the focus ring
## renders (mouse-over works) but `pressed` never fires. To unblock
## agent-driven Definition-of-Done validation, the lobby accepts
## A / S / L key presses as equivalents for Add Bot / Start / Leave.
##
## This test fakes InputEventKey objects and feeds them through the
## handler, asserting that:
##   - 'A' (when host) calls Net.emit("room:addBot", ...)
##   - 'S' (when host AND n>=2) calls Net.emit("room:start", ...)
##   - 'L' calls Net.emit("room:leave", ...)
##   - 'A' is ignored when not host (no Net.emit fires)
##
## Implementation note. Net.emit silently skips when not connected
## (push_warning + early return), so we can't observe by sniffing the
## socket. Instead we hot-swap the Net autoload's script with a thin
## recorder subclass that overrides emit() to log into a buffer. This
## preserves the autoload's node identity so GameState's `Net` ref
## remains valid.
##
## Run with:
##   godot --headless --path client --script res://tests/smoke_lobby_keybinds.gd
##
## Exit codes:
##   0 = pass
##   1 = at least one assertion failed
extends SceneTree

const NET_SPY_SOURCE := """extends \"res://scripts/globals/Net.gd\"

var emit_log: Array = []

func emit(event_name: String, args: Array = []) -> void:
	emit_log.append(event_name)
"""

func _init() -> void:
	var failures: Array[String] = []

	await process_frame

	var net: Node = root.get_node_or_null("Net")
	var gs: Node = root.get_node_or_null("GameState")
	if net == null or gs == null:
		push_error("Net or GameState autoload missing")
		quit(1)
		return

	# Hot-swap Net's script with a recorder. Preserves node identity.
	var spy_script := GDScript.new()
	spy_script.source_code = NET_SPY_SOURCE
	var err := spy_script.reload()
	if err != OK:
		push_error("spy script reload failed: %d" % err)
		quit(1)
		return
	net.set_script(spy_script)
	net.set("emit_log", [])

	# Mock GameState for host gating: youAreHost=true, 2 players.
	gs.room_code = "TEST"
	gs.snapshot = {
		"youAreHost": true,
		"players": [
			{"id": "p1", "nickname": "alice", "isBot": false, "isHost": true},
			{"id": "p2", "nickname": "bob",   "isBot": false, "isHost": false},
		]
	}

	var scene: PackedScene = load("res://scenes/Lobby.tscn")
	if scene == null:
		push_error("Lobby.tscn failed to load")
		quit(1)
		return

	var lobby: Node = scene.instantiate()
	root.add_child(lobby)
	for i in range(5):
		await process_frame

	# Sanity: cached gating state should reflect the snapshot.
	if not bool(lobby.get("_is_host")):
		failures.append("_is_host did not propagate from snapshot (got false, expected true)")
	if int(lobby.get("_player_count")) != 2:
		failures.append("_player_count did not propagate (got %d, expected 2)" % int(lobby.get("_player_count")))

	# 'A' as host → expect room:addBot recorded.
	net.set("emit_log", [])
	_send_key(lobby, KEY_A)
	await process_frame
	if not _saw_emit(net, "room:addBot"):
		failures.append("'A' as host did not record Net.emit('room:addBot'). Log: %s" % str(net.get("emit_log")))

	# 'S' as host with 2 players → expect room:start.
	net.set("emit_log", [])
	_send_key(lobby, KEY_S)
	await process_frame
	if not _saw_emit(net, "room:start"):
		failures.append("'S' as host did not record Net.emit('room:start'). Log: %s" % str(net.get("emit_log")))

	# 'L' → expect room:leave.
	net.set("emit_log", [])
	_send_key(lobby, KEY_L)
	await process_frame
	if not _saw_emit(net, "room:leave"):
		failures.append("'L' did not record Net.emit('room:leave'). Log: %s" % str(net.get("emit_log")))

	# 'A' as NON-host → expect NO room:addBot.
	gs.room_code = "TEST2"
	gs.snapshot = {
		"youAreHost": false,
		"players": [
			{"id": "p1", "nickname": "alice", "isBot": false, "isHost": true},
			{"id": "p2", "nickname": "bob",   "isBot": false, "isHost": false},
		]
	}
	lobby.queue_free()
	await process_frame
	var lobby2: Node = scene.instantiate()
	root.add_child(lobby2)
	for i in range(5):
		await process_frame
	net.set("emit_log", [])
	_send_key(lobby2, KEY_A)
	await process_frame
	if _saw_emit(net, "room:addBot"):
		failures.append("'A' as non-host wrongly recorded Net.emit('room:addBot'). Log: %s" % str(net.get("emit_log")))

	# 'S' as non-host (player_count=2, host=false) → expect NO room:start.
	net.set("emit_log", [])
	_send_key(lobby2, KEY_S)
	await process_frame
	if _saw_emit(net, "room:start"):
		failures.append("'S' as non-host wrongly recorded Net.emit('room:start'). Log: %s" % str(net.get("emit_log")))

	# 'S' as host with only 1 player → expect NO room:start.
	gs.snapshot = {
		"youAreHost": true,
		"players": [
			{"id": "p1", "nickname": "alice", "isBot": false, "isHost": true},
		]
	}
	lobby2.queue_free()
	await process_frame
	var lobby3: Node = scene.instantiate()
	root.add_child(lobby3)
	for i in range(5):
		await process_frame
	net.set("emit_log", [])
	_send_key(lobby3, KEY_S)
	await process_frame
	if _saw_emit(net, "room:start"):
		failures.append("'S' as host with only 1 player wrongly recorded Net.emit('room:start'). Log: %s" % str(net.get("emit_log")))

	if failures.is_empty():
		print("[smoke_lobby_keybinds] PASS — A/S/L keybinds dispatch the right Net events with correct host + player-count gating.")
		quit(0)
	else:
		print("[smoke_lobby_keybinds] FAIL:")
		for f in failures:
			print("  - %s" % f)
		quit(1)


func _send_key(lobby: Node, keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.echo = false
	# Call the handler directly. Going through Input.parse_input_event
	# would require the test viewport to have focus, which adds flake;
	# direct dispatch is the contract we're verifying. (S-218: handler
	# moved from _unhandled_key_input to _input so it fires before
	# Button focus consumes the event under WASM canvas focus.)
	lobby._input(ev)


func _saw_emit(net: Node, name: String) -> bool:
	var log: Array = net.get("emit_log")
	for entry in log:
		if String(entry) == name:
			return true
	return false
