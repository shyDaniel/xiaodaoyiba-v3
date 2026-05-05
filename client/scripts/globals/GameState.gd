# GameState.gd — autoload — room snapshot + round event log.
#
# Listens to Net.event and translates the wire protocol into an in-memory
# model that scenes can subscribe to via signals. Mirrors the v2 Zustand
# gameStore.ts shape:
#
#   - room_code: String                ("" before joining)
#   - snapshot: Dictionary             RoomSnapshot from server
#   - rounds: Array[Dictionary]        each {round, effects, narration, ...}
#   - winner_choice: Dictionary|null   open agency prompt (server H3)
#   - error: String                    last error message (cleared on next connect)
#
# Scenes connect to:
#   snapshot_changed(snapshot)
#   round_received(round_payload)
#   winner_choice_opened(prompt) / winner_choice_closed
#   error_changed(message)
#   joined_room(code)
#
# This is a passive store; it does not own animation state — that lives
# in stage/EffectPlayer.gd which consumes effects[] in real time.

extends Node

signal snapshot_changed(snapshot: Dictionary)
signal round_received(payload: Dictionary)
signal winner_choice_opened(prompt: Dictionary)
signal winner_choice_closed
signal error_changed(message: String)
signal joined_room(code: String)
signal connection_status_changed(connected: bool)

var room_code: String = ""
var snapshot: Dictionary = {}
var rounds: Array = []
var winner_choice = null # Dictionary or null
var error: String = ""
var nickname: String = ""
var my_player_id: String = ""
var is_connected: bool = false

func _ready() -> void:
	Net.connected.connect(_on_net_connected)
	Net.disconnected.connect(_on_net_disconnected)
	Net.connection_error.connect(_on_net_error)
	Net.event.connect(_on_net_event)

func _on_net_connected() -> void:
	is_connected = true
	error = ""
	error_changed.emit(error)
	connection_status_changed.emit(true)

func _on_net_disconnected() -> void:
	is_connected = false
	connection_status_changed.emit(false)

func _on_net_error(msg: String) -> void:
	error = msg
	error_changed.emit(msg)

func _on_net_event(name: String, args: Array) -> void:
	match name:
		"room:created":
			var p: Dictionary = args[0] if args.size() > 0 else {}
			room_code = String(p.get("code", ""))
			snapshot = p.get("snapshot", {})
			# S-218: server's room:created reply is per-socket (the
			# creator's). hostId in the snapshot IS me, so capture it as
			# my_player_id. Without this, the Lobby's youAreHost gating
			# never returns true and Add Bot / Start are forever disabled.
			if snapshot.has("hostId"):
				my_player_id = str(snapshot["hostId"])
			_set_my_player_id_from_snapshot()
			joined_room.emit(room_code)
			snapshot_changed.emit(snapshot)
		"room:joined":
			var pj: Dictionary = args[0] if args.size() > 0 else {}
			room_code = String(pj.get("code", ""))
			snapshot = pj.get("snapshot", {})
			# S-218: server's room:joined reply is per-socket. The just-
			# joined human is the last entry in members[] (server appends
			# in addHuman). Without this we have no way to learn our own
			# player id, so per-player UI gating (host marker, "your
			# turn") breaks.
			var pl: Array = snapshot.get("players", [])
			if pl.size() > 0:
				my_player_id = str((pl[pl.size() - 1] as Dictionary).get("id", ""))
			_set_my_player_id_from_snapshot()
			joined_room.emit(room_code)
			snapshot_changed.emit(snapshot)
		"room:snapshot":
			snapshot = args[0] if args.size() > 0 else {}
			_set_my_player_id_from_snapshot()
			snapshot_changed.emit(snapshot)
		"room:effects":
			var p2: Dictionary = args[0] if args.size() > 0 else {}
			rounds.append(p2)
			round_received.emit(p2)
		"room:winnerChoice":
			winner_choice = args[0] if args.size() > 0 else {}
			winner_choice_opened.emit(winner_choice)
		"room:error":
			var ep: Dictionary = args[0] if args.size() > 0 else {}
			error = "%s: %s" % [ep.get("code", "?"), ep.get("message", "")]
			error_changed.emit(error)
		_:
			pass

func _set_my_player_id_from_snapshot() -> void:
	# Server snapshots include a `youId` field (see server/Room.ts) when
	# the broadcast is targeted; otherwise we keep whatever we had. The
	# v2 server emits youId only on personalized snapshots, so this is
	# best-effort.
	if snapshot.has("youId"):
		my_player_id = str(snapshot["youId"])

# --- emit shortcuts --------------------------------------------------------

func create_room(nick: String) -> void:
	nickname = nick
	Net.emit("room:create", [{"nickname": nick}])

func join_room(code: String, nick: String) -> void:
	nickname = nick
	Net.emit("room:join", [{"code": code, "nickname": nick}])

func add_bot() -> void:
	Net.emit("room:addBot", [{}])

func start_game() -> void:
	Net.emit("room:start", [{}])

func send_choice(choice: String) -> void:
	Net.emit("room:choice", [{"choice": choice}])

func send_winner_choice(target, action) -> void:
	Net.emit("room:winnerChoice", [{"target": target, "action": action}])
	winner_choice = null
	winner_choice_closed.emit()

func leave_room() -> void:
	Net.emit("room:leave", [{}])
	room_code = ""
	snapshot = {}
	rounds = []
	winner_choice = null

func rematch() -> void:
	Net.emit("room:rematch", [{}])
