## check_action_coverage.gd — S-393 acceptance test for the brief.
##
## Loads docs/screenshots/action.png and verifies that each of the 4
## player anchors has measurable non-background coverage in:
##   1. a 192×192 house bounding box, AND
##   2. a 96×128 character bounding box (the brief's spec — the actual
##      character is rendered at 72×96 inside that box, so we sample the
##      enclosing brief-spec rectangle).
##
## "Non-background" means the pixel is NOT in the sky/grass/iso-tile
## palette (R, G, B all in the green/sky band). Threshold: ≥ 30% of
## pixels in the box are non-background per the brief.
##
## Run with:
##   godot --headless --path client --script res://tests/check_action_coverage.gd
extends SceneTree

const W := 1280
const H := 720

# Anchors match render_action_static.gd:
#   origin_x = W/2 = 640, origin_y = H/2 + 40 = 400.
#   Top-left  = (origin_x - 260, origin_y - 160) = (380, 240)
#   Top-right = (origin_x + 120, origin_y - 160) = (760, 240)
#   Bot-left  = (origin_x - 260, origin_y + 160) = (380, 560)
#   Bot-right = (origin_x + 120, origin_y + 160) = (760, 560)
const ANCHORS: Array = [
	Vector2i(380, 240),
	Vector2i(760, 240),
	Vector2i(380, 560),
	Vector2i(760, 560),
]

func _is_background(c: Color) -> bool:
	# Sky band: R 0.45..0.65, G 0.65..0.85, B 0.85..1.0 (cool blues).
	# Grass / iso tile band: R 0.25..0.55, G 0.45..0.65, B 0.20..0.40
	#   (warm greens) — green channel dominant.
	# Horizon: lerp between sky and grass — green still ≥ red, blue varies.
	# We use a simple "green is meaningfully > red AND green > blue/2"
	# test which catches every shade in the procedural sky → grass
	# gradient + iso diamond tiles.
	if c.g > c.r + 0.04 and c.g > 0.30 and c.r < 0.60:
		return true
	# Sky pixels: blue dominates AND not too red. R < G+0.05 and B > G.
	if c.b > c.g - 0.05 and c.b > 0.65 and c.r < 0.65:
		return true
	# Mountain greys mid-image: R≈G≈B around 0.40..0.55, slight blue tint.
	# These are also "scenery" for our purposes.
	if abs(c.r - c.g) < 0.06 and abs(c.g - c.b) < 0.10 and c.r > 0.35 and c.r < 0.60:
		return true
	return false

func _coverage(img: Image, x0: int, y0: int, x1: int, y1: int) -> float:
	var iw := img.get_width()
	var ih := img.get_height()
	var n := 0
	var fg := 0
	for y in range(maxi(y0, 0), mini(y1, ih)):
		for x in range(maxi(x0, 0), mini(x1, iw)):
			var c: Color = img.get_pixel(x, y)
			n += 1
			if not _is_background(c):
				fg += 1
	if n == 0:
		return 0.0
	return float(fg) / float(n)

func _init() -> void:
	await process_frame
	var path := "res://../docs/screenshots/action.png"
	var abs_path := ProjectSettings.globalize_path("res://").path_join("../docs/screenshots/action.png").simplify_path()
	var img := Image.new()
	var err := img.load(abs_path)
	if err != OK:
		push_error("[check_action_coverage] failed to load %s err=%d" % [abs_path, err])
		quit(1)
		return
	print("[check_action_coverage] loaded ", abs_path, " size=", img.get_size())

	var all_ok := true
	for i in range(ANCHORS.size()):
		var a: Vector2i = ANCHORS[i]
		# House bbox: 192×192 centered horizontally on anchor.x, bottom at anchor.y.
		var hx0 := a.x - 96
		var hy0 := a.y - 192
		var hx1 := a.x + 96
		var hy1 := a.y
		var house_cov := _coverage(img, hx0, hy0, hx1, hy1)

		# Character bbox: 96×128 placed to right of house. The renderer
		# blits at top_left = (anchor.x + 100, anchor.y + 30 - draw_h)
		# with draw_h=96 (after 0.75× scale). The brief asks for a
		# 96×128 box — we use the full unscaled bbox there so any
		# reasonable placement of the character (even at a different
		# scale) shows up.
		var cx0 := a.x + 100 - 12   # tolerance
		var cy0 := a.y + 30 - 128
		var cx1 := cx0 + 96
		var cy1 := cy0 + 128
		var char_cov := _coverage(img, cx0, cy0, cx1, cy1)

		var house_pass := house_cov >= 0.30
		var char_pass := char_cov >= 0.30
		var status := "PASS" if (house_pass and char_pass) else "FAIL"
		print("[check_action_coverage] anchor %d (%d,%d): house cov=%.1f%% (%s), char cov=%.1f%% (%s) — %s" % [
			i, a.x, a.y,
			house_cov * 100.0, "ok" if house_pass else "low",
			char_cov * 100.0, "ok" if char_pass else "low",
			status
		])
		if not (house_pass and char_pass):
			all_ok = false

	if all_ok:
		print("[check_action_coverage] PASS — all 4 anchors have ≥ 30%% non-bg coverage in both house and character bboxes.")
		quit(0)
	else:
		push_error("[check_action_coverage] FAIL — one or more anchors below 30%% non-bg coverage.")
		quit(1)
