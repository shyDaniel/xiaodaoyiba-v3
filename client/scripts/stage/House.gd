# House.gd — small visual controller for one player's house.
#
# Pulls the house texture from SpriteAtlas (procedurally rendered shaded
# pixel-art bitmap, ~192×160 px). set_player_color() tints the roof.
# show_damage() advances through 3 damage stages — the underlying
# texture itself changes (door scratched → chopped → ruined).

extends Node2D

@onready var _body: Sprite2D = $Body
@onready var _roof_tint: Sprite2D = $Body/RoofTint
@onready var _name_label: Label = $NameLabel

var _stage: int = 0          # 0..3
var _player_color: Color = Color(1, 1, 1, 1)

func _atlas() -> Node:
	return get_node_or_null("/root/SpriteAtlas")

func _ready() -> void:
	_apply_textures()

func _apply_textures() -> void:
	if _body == null:
		# Called before _ready — onready vars not bound yet. _ready will
		# call _apply_textures after the @onready resolves.
		return
	var atlas := _atlas()
	if atlas == null or atlas.house_textures.is_empty():
		return
	var idx: int = clampi(_stage, 0, atlas.house_textures.size() - 1)
	_body.texture = atlas.house_textures[idx]
	# Apply per-player tint as a low-saturation overlay so the wall
	# beige still reads correctly. Roof gets the strong tint via the
	# child overlay sprite.
	_body.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(_player_color, 0.18)
	# We don't have a separate roof-only mask atlas yet, so the roof
	# tint child stays empty for now — the roof colour reads via the
	# body modulate above (palette places it at the top).

func set_player_color(c: Color) -> void:
	_player_color = c
	_apply_textures()

func set_label(s: String) -> void:
	if _name_label != null:
		_name_label.text = s

func show_damage() -> void:
	# Advance the damage stage (cap at 3 = ruined).
	_stage = min(_stage + 1, 3)
	_apply_textures()
