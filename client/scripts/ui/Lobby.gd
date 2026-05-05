# Lobby.gd — pre-game room screen.
#
# Shows:
#   - the room code (so other humans can join)
#   - the current member list (humans + bots)
#   - host-only controls: 加机器人 / 开始
#   - leave button

extends Control

@onready var _code_label: Label = $Card/V/Code
@onready var _members: VBoxContainer = $Card/V/Members/List
@onready var _add_bot: Button = $Card/V/Buttons/AddBot
@onready var _start: Button = $Card/V/Buttons/Start
@onready var _leave: Button = $Card/V/Buttons/Leave

func _ready() -> void:
	_add_bot.pressed.connect(GameState.add_bot)
	_start.pressed.connect(GameState.start_game)
	_leave.pressed.connect(GameState.leave_room)
	GameState.snapshot_changed.connect(_render)
	_render(GameState.snapshot)

func _render(snap: Dictionary) -> void:
	_code_label.text = "房号 %s" % GameState.room_code
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
