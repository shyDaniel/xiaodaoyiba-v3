# Palette.gd — Endesga-32 palette accessor (S-370 §H2.6).
#
# Wraps assets/palette.tres so any script that wants a coherent color can
# call Palette.sample(idx) instead of typing arbitrary hex codes. Falls
# back to a hard-coded literal if the resource fails to load (so the
# palette is never the cause of a black screen).

extends Node

const FALLBACK_HEX := [
	"#be4a2f", "#d77643", "#ead4aa", "#e4a672", "#b86f50", "#733e39",
	"#3e2731", "#a22633", "#e43b44", "#f77622", "#feae34", "#fee761",
	"#63c74d", "#3e8948", "#265c42", "#193c3e", "#124e89", "#0099db",
	"#2ce8f5", "#ffffff", "#c0cbdc", "#8b9bb4", "#5a6988", "#3a4466",
	"#262b44", "#181425", "#ff0044", "#68386c", "#b55088", "#f6757a",
	"#e8b796", "#c28569"
]

# Common semantic aliases — names → indices into the palette so the rest of
# the codebase reads as words ("Palette.skin()") instead of numbers.
enum {
	BRICK_RED = 0,
	RUST = 1,
	CREAM = 2,
	SKIN_HI = 3,
	SKIN_LO = 4,
	HAIR_BROWN = 5,
	OUTLINE = 6,
	BLOOD_RED = 7,
	BRIGHT_RED = 8,
	PUMPKIN = 9,
	AMBER = 10,
	BUTTERCUP = 11,
	LEAF = 12,
	GRASS = 13,
	PINE = 14,
	DARK_TEAL = 15,
	NAVY = 16,
	SKY = 17,
	CYAN = 18,
	WHITE = 19,
	PALE_STEEL = 20,
	STEEL = 21,
	SLATE = 22,
	DEEP_SLATE = 23,
	MIDNIGHT = 24,
	OBSIDIAN = 25,
	PINK_RED = 26,
	PLUM = 27,
	ROSE = 28,
	SALMON = 29,
	SHELL = 30,
	BRICK_BROWN = 31
}

var _colors: PackedColorArray = PackedColorArray()

func _ready() -> void:
	_load()

func _load() -> void:
	var path := "res://assets/palette.tres"
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res != null and res.has_meta("colors"):
			var pc = res.get_meta("colors")
			if pc is PackedColorArray:
				_colors = pc
				return
	# Fallback: parse hex literals.
	_colors = PackedColorArray()
	for hex in FALLBACK_HEX:
		_colors.append(Color(hex))

func sample(idx: int) -> Color:
	if _colors.is_empty():
		_load()
	if _colors.is_empty():
		return Color(1, 0, 1, 1)  # magenta — obvious miss
	var i := wrapi(idx, 0, _colors.size())
	return _colors[i]

func size() -> int:
	if _colors.is_empty():
		_load()
	return _colors.size()

# Lighten / darken helpers that stay within Endesga's perceptual range.
func tint(idx: int, t: float, target: Color = Color(1, 1, 1, 1)) -> Color:
	return sample(idx).lerp(target, clampf(t, 0.0, 1.0))

func shade(idx: int, t: float) -> Color:
	return sample(idx).lerp(Color(0, 0, 0, 1), clampf(t, 0.0, 1.0))
