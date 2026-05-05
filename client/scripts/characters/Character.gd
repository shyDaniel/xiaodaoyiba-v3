# Character.gd — sprite + state machine for one player on the iso stage.
#
# FINAL_GOAL §C6 / §C7:
#   States: ALIVE_CLOTHED, ALIVE_PANTS_DOWN, RUSHING, ATTACKING, DEAD.
#   The PANTS_DOWN visual must persist across rounds — the red briefs
#   sprite stays on every phase until the player is restored or DEAD.
#
# Until hand-drawn PNGs land in assets/sprites/characters/, the body is
# rendered procedurally with simple coloured shapes (a head circle, a torso
# rect, a legs rect, ankle briefs visible in PANTS_DOWN). This keeps the
# whole tree shippable without art uploads (FINAL_GOAL §G).

class_name Character
extends Node2D

signal arrived_at_house(target_pos: Vector2)

enum State { ALIVE_CLOTHED, ALIVE_PANTS_DOWN, RUSHING, ATTACKING, DEAD }

@export var player_id: String = ""
@export var nickname: String = ""
@export var color_hue: float = 0.0   # set deterministically from id hash
@export var is_self: bool = false

var state: int = State.ALIVE_CLOTHED
var persistent_pants_down: bool = false  # §C7 persistent shame
var home_position: Vector2 = Vector2.ZERO
var _rush_tween: Tween = null

@onready var _body: Node2D = $Body
@onready var _label: Label = $NameLabel
@onready var _throw_glyph: Label = $ThrowGlyph
@onready var _shame_indicator: Polygon2D = $Body/ShameBriefs

func _ready() -> void:
	home_position = position
	_label.text = nickname
	_throw_glyph.visible = false
	_apply_color()
	_refresh_visual()

func set_persistent_pants_down(v: bool) -> void:
	persistent_pants_down = v
	_refresh_visual()

func set_state(s: int) -> void:
	state = s
	_refresh_visual()

func show_throw(glyph: String) -> void:
	_throw_glyph.text = glyph
	_throw_glyph.visible = true
	_throw_glyph.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_throw_glyph, "modulate:a", 1.0, 0.18)

func hide_throw() -> void:
	if not _throw_glyph.visible:
		return
	var tw := create_tween()
	tw.tween_property(_throw_glyph, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): _throw_glyph.visible = false)

func rush_to(target_world_pos: Vector2, dur_ms: int) -> void:
	if _rush_tween != null and _rush_tween.is_valid():
		_rush_tween.kill()
	state = State.RUSHING
	_rush_tween = create_tween()
	_rush_tween.tween_property(self, "position", target_world_pos, float(dur_ms) / 1000.0)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rush_tween.tween_callback(func():
		state = State.ATTACKING
		arrived_at_house.emit(target_world_pos)
		_refresh_visual())

func teleport_home() -> void:
	if _rush_tween != null and _rush_tween.is_valid():
		_rush_tween.kill()
	position = home_position
	if state != State.DEAD:
		state = State.ALIVE_PANTS_DOWN if persistent_pants_down else State.ALIVE_CLOTHED
	_refresh_visual()

func play_attack_wiggle() -> void:
	# Quick scale pulse; conveys "winding up to chop".
	var orig := scale
	var tw := create_tween()
	tw.tween_property(self, "scale", orig * 1.15, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", orig, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func play_death() -> void:
	state = State.DEAD
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "rotation_degrees", 90.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.4, 0.6)
	_refresh_visual()

func _apply_color() -> void:
	var c := Color.from_hsv(color_hue, 0.55, 0.95)
	($Body/Torso as Polygon2D).color = c
	($Body/Head as Polygon2D).color = c.lightened(0.25)

func _refresh_visual() -> void:
	# The shame briefs are red ankle-rectangles visible whenever the
	# player is "pants down" (persistently or in the active state),
	# regardless of whether they're rushing/attacking/standing.
	var pants_down := persistent_pants_down or state == State.ALIVE_PANTS_DOWN
	_shame_indicator.visible = pants_down and state != State.DEAD
	if state == State.DEAD:
		modulate = Color(0.5, 0.5, 0.5, 0.5)
	else:
		modulate = Color(1, 1, 1, 1)
