# Lobby.gd — pre-game room screen.
#
# Shows:
#   - the room code (so other humans can join)
#   - the current member list (humans + bots)
#   - host-only controls: Add Bot / Start
#   - leave button
#
# All visible strings are Latin so the live HTML5 build stays legible
# without a CJK system font (S-192).
#
# Keybinds (S-205): the live HTML5 build sometimes loses synthetic mouse
# clicks against Godot Buttons when driven by headless chromium —
# Playwright's mouse.down/up reaches the canvas but the engine's
# focus-grab + Button.pressed pipeline can swallow the event. To make
# the lobby reachable from headless drivers (and incidentally to give
# keyboard users a fast path), we accept:
#   A — add bot   (host-only, same gating as the button)
#   S — start     (host-only, requires ≥ 2 players)
#   L — leave
# These are wired in _unhandled_key_input so they fire regardless of
# which Control currently holds focus.

extends Control

@onready var _code_label: Label = $Card/V/Code
@onready var _members: VBoxContainer = $Card/V/Members/List
@onready var _add_bot: Button = $Card/V/Buttons/AddBot
@onready var _start: Button = $Card/V/Buttons/Start
@onready var _leave: Button = $Card/V/Buttons/Leave

# Cached host/member state so the keybind handler can apply the same
# gating the buttons use without re-reading the snapshot every key.
var _is_host: bool = false
var _player_count: int = 0

func _ready() -> void:
	_add_bot.pressed.connect(GameState.add_bot)
	_start.pressed.connect(GameState.start_game)
	_leave.pressed.connect(GameState.leave_room)
	GameState.snapshot_changed.connect(_render)
	_render(GameState.snapshot)

func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	# Only act while the Lobby is actually visible. Main swaps scenes by
	# visibility, so a hidden lobby's keybinds shouldn't fire.
	if not is_visible_in_tree():
		return
	match ev.keycode:
		KEY_A:
			if _is_host:
				GameState.add_bot()
				get_viewport().set_input_as_handled()
		KEY_S:
			if _is_host and _player_count >= 2:
				GameState.start_game()
				get_viewport().set_input_as_handled()
		KEY_L:
			GameState.leave_room()
			get_viewport().set_input_as_handled()

func _render(snap: Dictionary) -> void:
	_code_label.text = "Room %s" % GameState.room_code
	for c in _members.get_children():
		c.queue_free()
	var players: Array = snap.get("players", [])
	var n := players.size()
	for i in range(n):
		var p: Dictionary = players[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(20, 20)
		swatch.color = Color.from_hsv(float(i) / float(max(n, 1)), 0.55, 0.95)
		row.add_child(swatch)
		var name := Label.new()
		var tag := " (bot)" if bool(p.get("isBot", false)) else ""
		var host_marker := " ★" if bool(p.get("isHost", false)) else ""
		name.text = "%s%s%s" % [p.get("nickname", "?"), tag, host_marker]
		name.add_theme_font_size_override("font_size", 18)
		row.add_child(name)
		_members.add_child(row)
	# Host gates: only the host can add bots / start the game. Server
	# enforces, but we hide the buttons for clarity.
	var is_host := bool(snap.get("youAreHost", false))
	_add_bot.disabled = not is_host
	_start.disabled = not is_host or n < 2
	# Cache for the keybind handler so it can apply the same gating
	# without re-reading the snapshot.
	_is_host = is_host
	_player_count = n
