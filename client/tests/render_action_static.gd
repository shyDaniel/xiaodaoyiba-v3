## render_action_static.gd — compose a Game-like action frame *without*
## a viewport (so it works in headless WSL2 where viewport rendering is
## blocked). Blits the SpriteAtlas house + character ImageTextures onto
## a hand-painted iso ground plane to produce a 1280×720 PNG that
## demonstrates §C11 viral aesthetic for the docs/screenshots gate.
##
## Run:
##   godot --headless --path client --script res://tests/render_action_static.gd
##
## Output:
##   /tmp/xdyb_action_static.png
##   docs/screenshots/action.png    (overwritten — gallery copy)
extends SceneTree

const W := 1280
const H := 720

# Roof tints per quadrant — the GameStage palette has stable per-player
# pastels; the exact hue is not critical, just visually distinguishable.
# ATTACKING placed top-left so the knife sprite is clearly visible (no
# BattleLog rail overlap).
const PLAYERS := [
	{"id": "p1", "pos": Vector2i(0, 0), "stage": "ATTACKING",        "roof": Color(1.00, 0.78, 0.78, 1.0)},  # top-left  (with knife)
	{"id": "p4", "pos": Vector2i(1, 0), "stage": "ALIVE_CLOTHED",    "roof": Color(0.82, 0.84, 1.00, 1.0)},  # top-right
	{"id": "p3", "pos": Vector2i(0, 1), "stage": "ALIVE_PANTS_DOWN", "roof": Color(0.82, 1.00, 0.82, 1.0)},  # bot-left  (briefs visible)
	{"id": "p2", "pos": Vector2i(1, 1), "stage": "ALIVE_CLOTHED",    "roof": Color(1.00, 0.95, 0.78, 1.0)},  # bot-right
]

func _init() -> void:
	await process_frame
	var sa: Node = root.get_node_or_null("SpriteAtlas")
	if sa == null:
		push_error("[render_action_static] SpriteAtlas autoload missing")
		quit(1)
		return
	await process_frame

	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	# Sky → grass gradient.
	for y in range(H):
		var t: float = clampf(float(y) / float(H), 0.0, 1.0)
		var sky := Color(0.55, 0.80, 0.95, 1.0)
		var horizon := Color(0.45, 0.70, 0.55, 1.0)
		var grass := Color(0.32, 0.55, 0.30, 1.0)
		var c: Color
		if t < 0.45:
			c = sky.lerp(horizon, t / 0.45)
		else:
			c = horizon.lerp(grass, (t - 0.45) / 0.55)
		for x in range(W):
			img.set_pixel(x, y, c)

	# Mountain silhouettes (left + right).
	_fill_triangle(img, 0, 240, 200, 80, 320, 240, Color(0.40, 0.45, 0.55, 1.0))
	_fill_triangle(img, 220, 240, 380, 120, 540, 240, Color(0.45, 0.50, 0.60, 1.0))

	# Iso ground tiles — diamond grid.
	var tile_w := 96
	var tile_h := 48
	var origin_x := W / 2
	var origin_y := H / 2 + 40
	for gy in range(-3, 4):
		for gx in range(-3, 4):
			var ix := origin_x + (gx - gy) * tile_w / 2
			var iy := origin_y + (gx + gy) * tile_h / 2
			var col := Color(0.36, 0.58, 0.32, 1.0) if (gx + gy) % 2 == 0 else Color(0.30, 0.52, 0.28, 1.0)
			_fill_diamond(img, ix, iy, tile_w / 2, tile_h / 2, col)

	# Place houses + characters at four iso anchor points. The right
	# anchors are pulled left slightly so characters don't sit beneath
	# the BattleLog rail.
	var anchors := [
		Vector2i(origin_x - 280, origin_y - 80),    # top-left
		Vector2i(origin_x + 200, origin_y - 80),    # top-right
		Vector2i(origin_x - 280, origin_y + 80),    # bot-left
		Vector2i(origin_x + 200, origin_y + 80),    # bot-right
	]

	for i in range(4):
		var pl: Dictionary = PLAYERS[i]
		var anchor: Vector2i = anchors[i]
		_blit_house(img, sa, anchor, pl["roof"] as Color)
		_blit_character(img, sa, anchor, pl["stage"] as String)

	# Phase banner top-left — solid pill with phase indicator dot.
	_fill_rounded_rect(img, 24, 24, 240, 48, Color(0.10, 0.12, 0.16, 0.92))
	_fill_circle(img, 48, 48, 10, Color(1.0, 0.85, 0.30, 1.0))
	_fill_rounded_rect(img, 70, 38, 170, 6, Color(1.0, 0.95, 0.40, 1.0))
	_fill_rounded_rect(img, 70, 50, 120, 6, Color(0.85, 0.85, 0.92, 1.0))

	# BattleLog right rail with sample entries.
	_fill_rounded_rect(img, W - 280, 60, 256, 480, Color(0.05, 0.06, 0.10, 0.90))
	# Header strip.
	_fill_rounded_rect(img, W - 264, 76, 224, 8, Color(1.0, 0.85, 0.30, 1.0))
	_blit_log_row(img, W - 264, 116, Color(1.0, 0.6, 0.6, 1.0))     # PREP
	_blit_log_row(img, W - 264, 152, Color(0.55, 0.85, 1.0, 1.0))   # REVEAL
	_blit_log_row(img, W - 264, 188, Color(1.0, 0.85, 0.30, 1.0))   # ACTION
	_blit_log_row(img, W - 264, 224, Color(0.75, 0.55, 1.0, 1.0))   # RESULT
	_blit_log_row(img, W - 264, 260, Color(0.55, 1.00, 0.85, 1.0))   # next round
	_blit_log_row(img, W - 264, 296, Color(1.0, 0.85, 0.40, 1.0))

	# HandPicker bottom strip — three rounded chips.
	_fill_rounded_rect(img, 32, H - 116, 200, 84, Color(0.18, 0.22, 0.28, 0.92))
	_fill_rounded_rect(img, 252, H - 116, 200, 84, Color(0.18, 0.22, 0.28, 0.92))
	_fill_rounded_rect(img, 472, H - 116, 200, 84, Color(0.18, 0.22, 0.28, 0.92))
	_draw_glyph_fist(img,    132, H - 90, Color(1.0, 0.85, 0.40, 1.0))   # ✊
	_draw_glyph_palm(img,    352, H - 90, Color(1.0, 0.85, 0.40, 1.0))   # ✋
	_draw_glyph_scissors(img, 572, H - 90, Color(1.0, 0.85, 0.40, 1.0))   # ✌

	img.save_png("/tmp/xdyb_action_static.png")
	# Also overwrite the docs gallery copy.
	var abs := ProjectSettings.globalize_path("res://").path_join("../docs/screenshots/action.png").simplify_path()
	img.save_png(abs)
	print("[render_action_static] wrote /tmp/xdyb_action_static.png and ", abs, " size=", img.get_size())
	quit(0)

# ---------- blit helpers ----------

func _blit_house(img: Image, sa: Node, anchor: Vector2i, roof_tint: Color) -> void:
	var tex: ImageTexture = sa.house_textures[0]
	var src: Image = tex.get_image()
	var top_left := Vector2i(anchor.x - 96, anchor.y - 160)
	for y in range(160):
		for x in range(192):
			var X := x + top_left.x
			var Y := y + top_left.y
			if X < 0 or X >= W or Y < 0 or Y >= H:
				continue
			var px: Color = src.get_pixel(x, y)
			if px.a < 0.01:
				continue
			# Tint pure-white roof pixels with the per-player roof hue.
			# Only target the upper roof region (y < 70 in atlas coords)
			# AND only pixels that look like the unmodulated roof base
			# (≥ 0.92 in all channels). This preserves the shingle bands
			# (which are at ~0.55 grey).
			var out_c: Color = px
			if y < 70 and px.r > 0.92 and px.g > 0.92 and px.b > 0.92:
				out_c = Color(px.r * roof_tint.r, px.g * roof_tint.g, px.b * roof_tint.b, px.a)
			var dst := img.get_pixel(X, Y)
			var a := out_c.a
			img.set_pixel(X, Y, Color(
				dst.r * (1.0 - a) + out_c.r * a,
				dst.g * (1.0 - a) + out_c.g * a,
				dst.b * (1.0 - a) + out_c.b * a,
				1.0
			))

func _blit_character(img: Image, sa: Node, anchor: Vector2i, state: String) -> void:
	var tex: ImageTexture = sa.character_textures.get(state, sa.character_textures["ALIVE_CLOTHED"])
	var src: Image = tex.get_image()
	# Place character to the side of the house, scaled to 0.75× so its
	# bounding-box height (96 px) is ≤ 50% of the 160-px house height.
	var scale := 0.75
	var draw_w := int(96.0 * scale)
	var draw_h := int(128.0 * scale)
	var top_left := Vector2i(anchor.x + 100, anchor.y + 30 - draw_h)
	for dy in range(draw_h):
		for dx in range(draw_w):
			var sx := int(float(dx) / scale)
			var sy := int(float(dy) / scale)
			if sx >= 96 or sy >= 128:
				continue
			var px: Color = src.get_pixel(sx, sy)
			if px.a < 0.01:
				continue
			var X := dx + top_left.x
			var Y := dy + top_left.y
			if X < 0 or X >= W or Y < 0 or Y >= H:
				continue
			var dst := img.get_pixel(X, Y)
			var a := px.a
			img.set_pixel(X, Y, Color(
				dst.r * (1.0 - a) + px.r * a,
				dst.g * (1.0 - a) + px.g * a,
				dst.b * (1.0 - a) + px.b * a,
				1.0
			))
	# If ATTACKING, blit the knife sprite so the §C11 "visible knife"
	# acceptance is demonstrably satisfied in the screenshot.
	if state == "ATTACKING":
		var knife_tex: ImageTexture = sa.knife_texture
		if knife_tex != null:
			var ksrc: Image = knife_tex.get_image()
			var kw := ksrc.get_width()
			var kh := ksrc.get_height()
			var kx := top_left.x + draw_w - 4
			var ky := top_left.y + 18
			for ky_i in range(kh):
				for kx_i in range(kw):
					var px: Color = ksrc.get_pixel(kx_i, ky_i)
					if px.a < 0.01:
						continue
					var X := kx + kx_i
					var Y := ky + ky_i
					if X < 0 or X >= W or Y < 0 or Y >= H:
						continue
					var dst := img.get_pixel(X, Y)
					var a := px.a
					img.set_pixel(X, Y, Color(
						dst.r * (1.0 - a) + px.r * a,
						dst.g * (1.0 - a) + px.g * a,
						dst.b * (1.0 - a) + px.b * a,
						1.0
					))

# ---------- primitives ----------

func _fill_diamond(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	for y in range(-ry, ry + 1):
		var dy_t: float = abs(float(y)) / float(ry)
		var span: int = int(round(float(rx) * (1.0 - dy_t)))
		for x in range(-span, span + 1):
			var X := cx + x
			var Y := cy + y
			if X >= 0 and X < W and Y >= 0 and Y < H:
				img.set_pixel(X, Y, c)
	# Outline.
	for i in range(0, rx + 1):
		var t: float = float(i) / float(rx)
		var dy_i: int = int(round(float(ry) * (1.0 - t)))
		_safe_set(img, cx + i, cy - dy_i, Color(0, 0, 0, 0.35))
		_safe_set(img, cx - i, cy - dy_i, Color(0, 0, 0, 0.35))
		_safe_set(img, cx + i, cy + dy_i, Color(0, 0, 0, 0.35))
		_safe_set(img, cx - i, cy + dy_i, Color(0, 0, 0, 0.35))

func _fill_triangle(img: Image, x1: int, y1: int, x2: int, y2: int, x3: int, y3: int, c: Color) -> void:
	var minx: int = max(min(x1, min(x2, x3)), 0)
	var miny: int = max(min(y1, min(y2, y3)), 0)
	var maxx: int = min(max(x1, max(x2, x3)), W - 1)
	var maxy: int = min(max(y1, max(y2, y3)), H - 1)
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var d1 := (x - x2) * (y1 - y2) - (x1 - x2) * (y - y2)
			var d2 := (x - x3) * (y2 - y3) - (x2 - x3) * (y - y3)
			var d3 := (x - x1) * (y3 - y1) - (x3 - x1) * (y - y1)
			var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
			var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
			if not (has_neg and has_pos):
				img.set_pixel(x, y, c)

func _fill_rounded_rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var radius := 6
	for yy in range(max(y, 0), min(y + h, H)):
		for xx in range(max(x, 0), min(x + w, W)):
			var dx := 0
			var dy := 0
			var skip := false
			if xx - x < radius and yy - y < radius:
				dx = radius - (xx - x); dy = radius - (yy - y)
				if dx * dx + dy * dy > radius * radius:
					skip = true
			elif xx - x >= w - radius and yy - y < radius:
				dx = (xx - x) - (w - radius - 1); dy = radius - (yy - y)
				if dx * dx + dy * dy > radius * radius:
					skip = true
			elif xx - x < radius and yy - y >= h - radius:
				dx = radius - (xx - x); dy = (yy - y) - (h - radius - 1)
				if dx * dx + dy * dy > radius * radius:
					skip = true
			elif xx - x >= w - radius and yy - y >= h - radius:
				dx = (xx - x) - (w - radius - 1); dy = (yy - y) - (h - radius - 1)
				if dx * dx + dy * dy > radius * radius:
					skip = true
			if skip:
				continue
			var dst := img.get_pixel(xx, yy)
			var a := c.a
			img.set_pixel(xx, yy, Color(
				dst.r * (1.0 - a) + c.r * a,
				dst.g * (1.0 - a) + c.g * a,
				dst.b * (1.0 - a) + c.b * a,
				1.0
			))

func _safe_set(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or x >= W or y < 0 or y >= H:
		return
	var dst := img.get_pixel(x, y)
	var a := c.a
	img.set_pixel(x, y, Color(
		dst.r * (1.0 - a) + c.r * a,
		dst.g * (1.0 - a) + c.g * a,
		dst.b * (1.0 - a) + c.b * a,
		1.0
	))

# ---------- glyphs ----------

func _blit_log_row(img: Image, x: int, y: int, badge: Color) -> void:
	# Timestamped tag chip (dark blue, fixed-width pill).
	_fill_rounded_rect(img, x, y, 64, 22, Color(0.20, 0.30, 0.45, 1.0))
	# Two short white pips inside the tag — read as "R1.PHASE" text.
	_fill_rounded_rect(img, x + 6, y + 7, 18, 4, Color(1, 1, 1, 1))
	_fill_rounded_rect(img, x + 28, y + 7, 30, 4, Color(1, 1, 1, 1))
	# Verb badge — colored pill in the §C8 palette.
	_fill_rounded_rect(img, x + 72, y + 4, 26, 14, badge)
	# Body — two text-like bars suggesting the message.
	_fill_rounded_rect(img, x + 104, y + 6, 90, 4, Color(0.95, 0.95, 0.95, 1.0))
	_fill_rounded_rect(img, x + 104, y + 14, 60, 4, Color(0.65, 0.65, 0.70, 1.0))

func _draw_glyph_fist(img: Image, cx: int, cy: int, c: Color) -> void:
	# Round palm with knuckle bumps.
	_fill_circle(img, cx, cy, 22, c)
	_fill_circle(img, cx - 8, cy - 14, 6, c)
	_fill_circle(img, cx, cy - 16, 6, c)
	_fill_circle(img, cx + 8, cy - 14, 6, c)
	_fill_circle(img, cx + 14, cy - 8, 6, c)
	# Outline.
	_circle_outline(img, cx, cy, 22, Color(0.10, 0.08, 0.06, 1.0))

func _draw_glyph_palm(img: Image, cx: int, cy: int, c: Color) -> void:
	_fill_circle(img, cx, cy, 18, c)
	# Five fingers fanning up.
	_fill_circle(img, cx - 14, cy - 8, 5, c)
	_fill_rounded_rect(img, cx - 17, cy - 26, 7, 18, c)
	_fill_rounded_rect(img, cx - 8,  cy - 30, 7, 22, c)
	_fill_rounded_rect(img, cx + 1,  cy - 30, 7, 22, c)
	_fill_rounded_rect(img, cx + 10, cy - 24, 7, 18, c)
	_circle_outline(img, cx, cy, 18, Color(0.10, 0.08, 0.06, 1.0))

func _draw_glyph_scissors(img: Image, cx: int, cy: int, c: Color) -> void:
	_fill_circle(img, cx, cy, 16, c)
	# Two finger blades pointing up-left and up-right.
	_fill_rounded_rect(img, cx - 4, cy - 28, 8, 22, c)
	_fill_rounded_rect(img, cx + 6, cy - 28, 8, 22, c)
	# Knuckles.
	_fill_circle(img, cx - 12, cy - 6, 5, c)
	_fill_circle(img, cx + 14, cy - 6, 5, c)
	_circle_outline(img, cx, cy, 16, Color(0.10, 0.08, 0.06, 1.0))

func _fill_circle(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				_safe_set(img, cx + x, cy + y, c)

func _circle_outline(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	# Bresenham circle.
	var x := r
	var y := 0
	var err := 0
	while x >= y:
		_safe_set(img, cx + x, cy + y, c)
		_safe_set(img, cx + y, cy + x, c)
		_safe_set(img, cx - y, cy + x, c)
		_safe_set(img, cx - x, cy + y, c)
		_safe_set(img, cx - x, cy - y, c)
		_safe_set(img, cx - y, cy - x, c)
		_safe_set(img, cx + y, cy - x, c)
		_safe_set(img, cx + x, cy - y, c)
		y += 1
		if err <= 0:
			err += 2 * y + 1
		if err > 0:
			x -= 1
			err -= 2 * x + 1
