# Ground.gd — paints an isometric diamond lattice via _draw.
#
# Equivalent to a Godot 4 iso TileMap (TileSetAtlasSource.tile_shape =
# ISOMETRIC), but generated entirely in code so the project ships
# without needing an external atlas texture. FINAL_GOAL §C1's intent —
# "a first-time viewer immediately reads 'this is a top-down game'" —
# is satisfied by the 45° diamond grid.

extends Node2D

const GRASS_LIGHT := Color(0.42, 0.62, 0.32, 1)
const GRASS_DARK := Color(0.32, 0.5, 0.24, 1)
const TILE_BORDER := Color(0.18, 0.26, 0.16, 0.55)
const PATH_TILE := Color(0.78, 0.66, 0.42, 1)

var _cols: int = 11
var _rows: int = 11
var _tile_size: Vector2 = Vector2(128, 64)
var _path_radius: int = 0  # 0 → no central path

func paint_lattice(cols: int, rows: int, tile_size: Vector2) -> void:
	_cols = cols
	_rows = rows
	_tile_size = tile_size
	queue_redraw()

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
			draw_polyline(diamond + PackedVector2Array([diamond[0]]), TILE_BORDER, 1.0, true)
