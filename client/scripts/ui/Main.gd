# Main.gd — top-level router. Swaps between Landing / Lobby / Game scenes.
#
# Holds a reference to the current child via `current_scene` and listens
# to GameState for transitions:
#   - join/create from Landing → Lobby
#   - room snapshot phase=LOBBY → Lobby
#   - room snapshot phase=PLAYING → Game
#   - room snapshot phase=ENDED  → Lobby (rematch staging)
#   - leave → Landing
#
# S-226: server emits uppercase phase strings ("LOBBY" | "PLAYING" |
# "ENDED" — see server/src/rooms/Room.ts:56 + shared/src/game/types.ts).
# Earlier code compared against lowercase literals, so the router never
# matched and Game.tscn was never instantiated in the live HTML5 build.
# We normalize to lowercase here and treat the local cache as the
# canonical lower-case form so the LOBBY/Lobby distinction collapses.

extends Node

@onready var _slot: Node = $SceneSlot
const LANDING := preload("res://scenes/Landing.tscn")
const LOBBY := preload("res://scenes/Lobby.tscn")
const GAME := preload("res://scenes/Game.tscn")

var _current: Node = null
var _phase: String = ""

func _ready() -> void:
	_show(LANDING)
	GameState.snapshot_changed.connect(_on_snapshot)
	GameState.joined_room.connect(_on_joined)

func _show(packed: PackedScene) -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	_current = packed.instantiate()
	_slot.add_child(_current)

func _on_joined(_code: String) -> void:
	_show(LOBBY)
	_phase = "lobby"

func _on_snapshot(snap: Dictionary) -> void:
	# Server uses 'LOBBY' / 'PLAYING' / 'ENDED' (uppercase). Normalize so
	# the comparisons below are case-insensitive — the wire protocol is
	# the source of truth and we don't mutate it.
	var p := String(snap.get("phase", "")).to_lower()
	if p == _phase or p == "":
		return
	_phase = p
	if p == "playing":
		_show(GAME)
	elif p == "lobby":
		_show(LOBBY)
	elif p == "ended":
		# Rematch / endgame screen — for now drop back to Lobby so the
		# host can press Start again. Future: dedicated EndScreen.tscn.
		_show(LOBBY)
