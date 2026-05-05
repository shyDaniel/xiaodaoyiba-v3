# Ground.gd — paints an isometric diamond lattice via _draw.
#
# Equivalent to a Godot 4 iso TileMap (TileSetAtlasSource.tile_shape =
# ISOMETRIC), but generated entirely in code so the project ships
# without needing an external atlas texture. FINAL_GOAL §C1's intent —
# "a first-time viewer immediately reads 'this is a top-down game'" —
# is satisfied by the 45° diamond grid.
#
# S-370 §H2.1 — replace the 2-tone solid-green checkerboard with a
# multi-variant ground that breaks the flat read. Each tile picks one
# of four 64×64 tile crops from `assets/sprites/tiles/ground_atlas.png`
# (grass-tuft, dirt-path, cobble, packed-earth) using a deterministic
# hash of (x,y), then we draw the iso diamond with that tile's texture
# clamped via a textured polygon. The diamond geometry is preserved so
# nothing about gameplay positioning changes; only the visual surface.

extends Node2D

const GRASS_LIGHT := Color(0.42, 0.62, 0.32, 1)
const GRASS_DARK := Color(0.32, 0.50, 0.24, 1)
const TILE_BORDER := Color(0.18, 0.26, 0.16, 0.45)
const PATH_TILE := Color(0.78, 0.66, 0.42, 1)

# S-370 §H2.1 — atlas of 4 horizontal 64×64 tile variants.
const _ATLAS := preload("res://assets/sprites/tiles/ground_atlas.png")
const _ATLAS_CELL := 64

var _cols: int = 11
var _rows: int = 11
var _tile_size: Vector2 = Vector2(128, 64)
var _path_radius: int = 0  # 0 → no central path

func paint_lattice(cols: int, rows: int, tile_size: Vector2) -> void:
	_cols = cols
	_rows = rows
	_tile_size = tile_size
	queue_redraw()

# Deterministic 0..3 variant per cell — same noise function family used
# in scripts/gen-ui-art.mjs so the atlas content is reused predictably.
func _variant_for(x: int, y: int) -> int:
	var h: int = ((x + 100) * 73856093) ^ ((y + 100) * 19349663)
	return abs(h) % 4

func _draw() -> void:
	var hw := _tile_size.x * 0.5
	var hh := _tile_size.y * 0.5
	var half_c := _cols / 2
	var half_r := _rows / 2
	# Painter's algorithm: iterate by sum (x+y) so back tiles draw first.
	for s in range(-half_c - half_r, half_c + half_r + 1):
		for x in range(-half_c, half_c + 1):
			var y := s - x
			if y < -half_r or y > half_r:
				continue
			var center := Vector2(float(x - y) * hw, float(x + y) * hh)
			var diamond := PackedVector2Array([
				center + Vector2(0, -hh),
				center + Vector2(hw, 0),
				center + Vector2(0, hh),
				center + Vector2(-hw, 0),
			])
			var col: Color = GRASS_LIGHT if (x + y) % 2 == 0 else GRASS_DARK
			# Soften toward edge so the lattice has a nice falloff.
			var dist: int = max(abs(x), abs(y))
			var falloff: float = clamp(1.0 - float(dist - 3) / 4.0, 0.55, 1.0)
			col = col * Color(falloff, falloff, falloff, 1.0)
			col.a = 1.0
			draw_colored_polygon(diamond, col)
			# S-370 §H2.1 — overlay the chosen 64×64 tile crop on top of
			# the base diamond. UV maps the diamond's 4 corners to the
			# tile's 4 quadrant edges so the painted texture aligns with
			# the iso shape. Modulate-alpha 0.55 keeps the underlying
			# lattice color visible so the lit/shaded falloff still reads.
			var v: int = _variant_for(x, y)
			var u_left := float(v * _ATLAS_CELL) / float(_ATLAS.get_width())
			var u_right := float((v + 1) * _ATLAS_CELL) / float(_ATLAS.get_width())
			var u_mid_x := (u_left + u_right) * 0.5
			var uv := PackedVector2Array([
				Vector2(u_mid_x, 0.0),         # top → tile-top center
				Vector2(u_right, 0.5),         # right → tile-mid right
				Vector2(u_mid_x, 1.0),         # bottom → tile-bottom center
				Vector2(u_left, 0.5),          # left → tile-mid left
			])
			draw_colored_polygon(diamond, Color(1, 1, 1, 0.55), uv, _ATLAS)
			draw_polyline(diamond + PackedVector2Array([diamond[0]]),
				TILE_BORDER, 1.0, true)
