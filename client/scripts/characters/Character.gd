# Character.gd — sprite + state machine for one player on the iso stage.
#
# FINAL_GOAL §C6 / §C7 / §C11:
#   States: ALIVE_CLOTHED, ALIVE_PANTS_DOWN, RUSHING, ATTACKING, DEAD.
#   The PANTS_DOWN visual must persist across rounds — the red briefs
#   render on every phase until restored or DEAD.
#
# Sprites come from the SpriteAtlas autoload, which procedurally
# renders shaded pixel-art at boot (see scripts/globals/SpriteAtlas.gd).
# Per-player hue tinting applies to the torso layer via modulate so the
# silhouette stays cohesive across players. The Knife child Sprite2D
# is hidden in non-attack states and swung during ATTACKING.

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
var _knife_swing_tween: Tween = null

@onready var _body: Sprite2D = $Body
@onready var _torso_tint: Sprite2D = $Body/TorsoTint
@onready var _label: Label = $NameLabel
@onready var _throw_glyph: Label = $ThrowGlyph
@onready var _knife: Sprite2D = $Knife

func _atlas() -> Node:
	return get_node_or_null("/root/SpriteAtlas")

func _ready() -> void:
	home_position = position
	_label.text = nickname
	_label.add_theme_color_override("font_color", Color.from_hsv(color_hue, 0.45, 1.0))
	_throw_glyph.visible = false
	# Knife sprite from atlas. Centered=false; offset to pivot at handle.
	var atlas := _atlas()
	if atlas != null and atlas.knife_texture != null:
		_knife.texture = atlas.knife_texture
		# Pivot at handle (left end), offset rotates the blade.
		_knife.offset = Vector2(0, -10)
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
	_refresh_visual()
	# Face the target by mirroring the body sprite horizontally.
	_body.flip_h = target_world_pos.x < position.x
	_rush_tween = create_tween()
	_rush_tween.tween_property(self, "position", target_world_pos, float(dur_ms) / 1000.0)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rush_tween.tween_callback(func():
		state = State.ATTACKING
		_refresh_visual()
		_swing_knife()
		arrived_at_house.emit(target_world_pos))

func teleport_home() -> void:
	if _rush_tween != null and _rush_tween.is_valid():
		_rush_tween.kill()
	position = home_position
	_body.flip_h = false
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
	_refresh_visual()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "rotation_degrees", 90.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.4, 0.6)

func _swing_knife() -> void:
	# 180° arc swing: starts cocked back (-1.6 rad), ends past target (1.0 rad).
	if _knife_swing_tween != null and _knife_swing_tween.is_valid():
		_knife_swing_tween.kill()
	_knife.rotation = -1.6
	_knife.visible = true
	_knife_swing_tween = create_tween()
	_knife_swing_tween.tween_property(_knife, "rotation", 1.0, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_knife_swing_tween.tween_interval(0.18)
	_knife_swing_tween.tween_property(_knife, "rotation", -0.4, 0.18)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _refresh_visual() -> void:
	# Decide the visual state to render. Persistent-shame overrides
	# ALIVE_CLOTHED → PANTS_DOWN per §C7.
	var visual_state: String = ""
	match state:
		State.ALIVE_CLOTHED:
			visual_state = "ALIVE_PANTS_DOWN" if persistent_pants_down else "ALIVE_CLOTHED"
		State.ALIVE_PANTS_DOWN:
			visual_state = "ALIVE_PANTS_DOWN"
		State.RUSHING:
			visual_state = "RUSHING"
		State.ATTACKING:
			visual_state = "ATTACKING"
		State.DEAD:
			visual_state = "DEAD"
		_:
			visual_state = "ALIVE_CLOTHED"

	# Apply the body texture from the atlas (a single full-character
	# sprite per state, with shaded shapes baked in). The TorsoTint
	# layer is the same sprite re-modulated per-player so the body
	# silhouette gets a hue tint without changing skin/hair colours.
	var atlas := _atlas()
	if atlas != null and not atlas.character_textures.is_empty():
		var tex: Texture2D = atlas.character_textures.get(visual_state, null)
		if tex != null and _body != null:
			_body.texture = tex
			_torso_tint.texture = null   # not used yet — single-pass tint via modulate

	# Per-player hue tint applied to the body's torso region only.
	# To avoid colouring skin/hair, we instead modulate a slight tint
	# (low saturation) over the whole body — this still clearly
	# distinguishes the four players without distorting flesh tones.
	var tint := Color.from_hsv(color_hue, 0.45, 1.0)
	# Blend tint with white so skin/hair stay readable.
	if _body != null:
		_body.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(tint, 0.45)

	# Knife visibility: only shown while ATTACKING.
	if _knife == null:
		return
	_knife.visible = (visual_state == "ATTACKING")
	if _knife.visible:
		# Position knife at the right hand; flip with body.
		var sign := -1.0 if _body.flip_h else 1.0
		_knife.position = Vector2(18 * sign, -78)
		_knife.scale.x = sign

	# DEAD overlay handled by play_death tween.
