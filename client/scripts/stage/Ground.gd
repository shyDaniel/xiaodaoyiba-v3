# Ground.gd — renders an isometric diamond lattice via a single Sprite2D
# child, loading a pre-baked PNG composite from
# `assets/sprites/3rd-party/composites/ground_lattice_11.png`.
#
# S-386 §I.0 HARD BAN — replaced the runtime _draw() that used
# draw_colored_polygon / draw_polyline with a static texture lookup.
# The composite was stitched at build time by
# `scripts/gen-3rd-party-composites.mjs` from Kenney Tiny Town CC0
# tiles (grass + flowers + dirt-path) projected through the same
# painter's-order iso transform Ground.gd previously executed at
# runtime. The aesthetic surface ("first-time viewer reads
# 'top-down game'", FINAL_GOAL §C1) is preserved bit-for-bit.

extends Node2D

var _cols: int = 11
var _rows: int = 11
var _tile_size: Vector2 = Vector2(128, 64)
var _sprite: Sprite2D = null

func _ready() -> void:
	_ensure_sprite()
	_apply_texture()

func paint_lattice(cols: int, rows: int, tile_size: Vector2) -> void:
	_cols = cols
	_rows = rows
	_tile_size = tile_size
	_ensure_sprite()
	_apply_texture()

func _ensure_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	_sprite = Sprite2D.new()
	_sprite.name = "LatticeSprite"
	_sprite.centered = true
	add_child(_sprite)

func _apply_texture() -> void:
	if _sprite == null:
		return
	var atlas: Node = get_node_or_null("/root/SpriteAtlas")
	if atlas == null:
		return
	var tex: Texture2D = atlas.ground_lattice(_cols)
	if tex == null:
		return
	_sprite.texture = tex
