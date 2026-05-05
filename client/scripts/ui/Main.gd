# Main.gd — top-level router. Swaps between Landing / Lobby / Game scenes.
#
# Holds a reference to the current child via `current_scene` and listens
# to GameState for transitions:
#   - join/create from Landing → Lobby
#   - room snapshot phase=lobby → Lobby
#   - room snapshot phase=playing → Game
#   - leave → Landing

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
	var p := String(snap.get("phase", ""))
	if p == _phase or p == "":
		return
	_phase = p
	if p == "playing":
		_show(GAME)
	elif p == "lobby":
		_show(LOBBY)
