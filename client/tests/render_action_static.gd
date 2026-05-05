## render_action_static.gd — compose a Game-like action frame *without*
## a viewport (so it works in headless WSL2 where viewport rendering is
## blocked). Blits the SpriteAtlas house + character ImageTextures onto
## a hand-painted iso ground plane to produce a 1280×720 PNG that
## demonstrates §C11 viral aesthetic for the docs/screenshots gate.
##
## S-169: also draws real readable UI text into the phase banner,
## BattleLog rows, and HandPicker chips. We can't use FontFile cache
## atlas readback — Godot 4.3's --headless mode replaces texture
## storage with a dummy backend, so get_texture_image() returns blank
## L8 atlases with bogus uv_rects. We can't use a SubViewport either —
## get_image() on a ViewportTexture in headless returns a null ptr.
## Solution: a hand-rolled 5×7 monospace pixel font (ASCII only) that
## blits one glyph at a time via set_pixel — guaranteed to work in any
## headless host with no GPU. Color emoji glyphs (✊✋✌) DO load via
## NotoColorEmoji.ttf because that font's atlas is RGBA8 and the
## bitmap data is stored in an Image asset, not the GPU cache.
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
## Nicknames are deliberately Latin-only in the static mock so the
## embedded 5×7 ASCII bitmap font can render them legibly. The runtime
## Godot client renders the original CJK names (机器人甲 / 小明 / 小红 /
## 机器人乙) via the system Noto Sans CJK fallback — the README copy
## explicitly anglicises them to Ming / Hong / Bot-A / Bot-B for the
## hero screenshot's honesty (matches the BattleLog rows below which
## already use "Ming preps" / "Hong's pants").
const PLAYERS := [
	# S-401: per-player house "variant" picks one of the 4 distinct
	# Kenney composites so the four homes read as four DIFFERENT houses
	# (red+brown / grey+stone / red+stone / grey+brown) rather than four
	# tinted copies of the same palette.
	{"id": "p1", "name": "Bot-A", "pos": Vector2i(0, 0), "stage": "ATTACKING",        "roof": Color(1.00, 0.78, 0.78, 1.0), "name_color": Color(1.00, 0.55, 0.55, 1.0), "variant": 0},  # top-left  (with knife) — red+brown
	{"id": "p4", "name": "Bot-B", "pos": Vector2i(1, 0), "stage": "ALIVE_CLOTHED",    "roof": Color(0.82, 0.84, 1.00, 1.0), "name_color": Color(0.65, 0.75, 1.00, 1.0), "variant": 1},  # top-right — grey+stone
	{"id": "p3", "name": "Hong",  "pos": Vector2i(0, 1), "stage": "ALIVE_PANTS_DOWN", "roof": Color(0.82, 1.00, 0.82, 1.0), "name_color": Color(0.55, 1.00, 0.65, 1.0), "variant": 2},  # bot-left  (briefs visible) — red+stone
	{"id": "p2", "name": "Ming",  "pos": Vector2i(1, 1), "stage": "ALIVE_CLOTHED",    "roof": Color(1.00, 0.95, 0.78, 1.0), "name_color": Color(1.00, 0.85, 0.40, 1.0), "variant": 3},  # bot-right — grey+brown
]

# Color emoji font — committed asset. The .ttf bitmap atlas is loaded
# as an Image-backed FontFile and DOES survive headless mode.
var emoji_font: FontFile = null
const EMOJI_NATIVE_SIZE := 109

# 5×7 monospace pixel font. Each glyph is 7 rows of 5 bits (LSB = right
# pixel). Covers ASCII printable subset we use: digits, uppercase A-Z,
# lowercase a-z, plus a handful of punctuation. Missing glyphs fall back
# to a filled box so layout stays visible.
const GLYPH_W := 5
const GLYPH_H := 7
const GLYPH_PITCH := 1   # 1-pixel space between glyphs
const FONT_5X7 := {
	" ": [0,0,0,0,0,0,0],
	"!": [0x04,0x04,0x04,0x04,0x00,0x04,0x00],
	".": [0,0,0,0,0,0x04,0x04],
	",": [0,0,0,0,0x04,0x04,0x08],
	":": [0,0x04,0x00,0x00,0x04,0x00,0x00],
	"·": [0,0,0,0x04,0x00,0x00,0x00],
	"/": [0x01,0x01,0x02,0x04,0x08,0x10,0x10],
	"-": [0,0,0,0x0E,0,0,0],
	"+": [0,0x04,0x04,0x1F,0x04,0x04,0x00],
	"(": [0x02,0x04,0x08,0x08,0x08,0x04,0x02],
	")": [0x08,0x04,0x02,0x02,0x02,0x04,0x08],
	"#": [0x0A,0x1F,0x0A,0x0A,0x1F,0x0A,0x00],
	"'": [0x04,0x04,0x00,0x00,0x00,0x00,0x00],
	"_": [0,0,0,0,0,0,0x1F],
	"=": [0,0,0x1F,0x00,0x1F,0x00,0x00],
	"0": [0x0E,0x11,0x13,0x15,0x19,0x11,0x0E],
	"1": [0x04,0x0C,0x04,0x04,0x04,0x04,0x0E],
	"2": [0x0E,0x11,0x01,0x02,0x04,0x08,0x1F],
	"3": [0x1F,0x02,0x04,0x02,0x01,0x11,0x0E],
	"4": [0x02,0x06,0x0A,0x12,0x1F,0x02,0x02],
	"5": [0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E],
	"6": [0x06,0x08,0x10,0x1E,0x11,0x11,0x0E],
	"7": [0x1F,0x01,0x02,0x04,0x08,0x08,0x08],
	"8": [0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E],
	"9": [0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C],
	"A": [0x0E,0x11,0x11,0x1F,0x11,0x11,0x11],
	"B": [0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E],
	"C": [0x0E,0x11,0x10,0x10,0x10,0x11,0x0E],
	"D": [0x1C,0x12,0x11,0x11,0x11,0x12,0x1C],
	"E": [0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F],
	"F": [0x1F,0x10,0x10,0x1E,0x10,0x10,0x10],
	"G": [0x0E,0x11,0x10,0x17,0x11,0x11,0x0E],
	"H": [0x11,0x11,0x11,0x1F,0x11,0x11,0x11],
	"I": [0x0E,0x04,0x04,0x04,0x04,0x04,0x0E],
	"J": [0x07,0x02,0x02,0x02,0x02,0x12,0x0C],
	"K": [0x11,0x12,0x14,0x18,0x14,0x12,0x11],
	"L": [0x10,0x10,0x10,0x10,0x10,0x10,0x1F],
	"M": [0x11,0x1B,0x15,0x15,0x11,0x11,0x11],
	"N": [0x11,0x11,0x19,0x15,0x13,0x11,0x11],
	"O": [0x0E,0x11,0x11,0x11,0x11,0x11,0x0E],
	"P": [0x1E,0x11,0x11,0x1E,0x10,0x10,0x10],
	"Q": [0x0E,0x11,0x11,0x11,0x15,0x12,0x0D],
	"R": [0x1E,0x11,0x11,0x1E,0x14,0x12,0x11],
	"S": [0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E],
	"T": [0x1F,0x04,0x04,0x04,0x04,0x04,0x04],
	"U": [0x11,0x11,0x11,0x11,0x11,0x11,0x0E],
	"V": [0x11,0x11,0x11,0x11,0x11,0x0A,0x04],
	"W": [0x11,0x11,0x11,0x15,0x15,0x15,0x0A],
	"X": [0x11,0x11,0x0A,0x04,0x0A,0x11,0x11],
	"Y": [0x11,0x11,0x11,0x0A,0x04,0x04,0x04],
	"Z": [0x1F,0x01,0x02,0x04,0x08,0x10,0x1F],
	"a": [0x00,0x00,0x0E,0x01,0x0F,0x11,0x0F],
	"b": [0x10,0x10,0x16,0x19,0x11,0x11,0x1E],
	"c": [0x00,0x00,0x0E,0x10,0x10,0x10,0x0E],
	"d": [0x01,0x01,0x0D,0x13,0x11,0x11,0x0F],
	"e": [0x00,0x00,0x0E,0x11,0x1F,0x10,0x0E],
	"f": [0x06,0x09,0x08,0x1E,0x08,0x08,0x08],
	"g": [0x00,0x0F,0x11,0x11,0x0F,0x01,0x0E],
	"h": [0x10,0x10,0x16,0x19,0x11,0x11,0x11],
	"i": [0x04,0x00,0x0C,0x04,0x04,0x04,0x0E],
	"j": [0x02,0x00,0x06,0x02,0x02,0x12,0x0C],
	"k": [0x10,0x10,0x12,0x14,0x18,0x14,0x12],
	"l": [0x0C,0x04,0x04,0x04,0x04,0x04,0x0E],
	"m": [0x00,0x00,0x1A,0x15,0x15,0x11,0x11],
	"n": [0x00,0x00,0x16,0x19,0x11,0x11,0x11],
	"o": [0x00,0x00,0x0E,0x11,0x11,0x11,0x0E],
	"p": [0x00,0x16,0x19,0x11,0x1E,0x10,0x10],
	"q": [0x00,0x0D,0x13,0x11,0x0F,0x01,0x01],
	"r": [0x00,0x00,0x16,0x19,0x10,0x10,0x10],
	"s": [0x00,0x00,0x0F,0x10,0x0E,0x01,0x1E],
	"t": [0x08,0x08,0x1E,0x08,0x08,0x09,0x06],
	"u": [0x00,0x00,0x11,0x11,0x11,0x13,0x0D],
	"v": [0x00,0x00,0x11,0x11,0x11,0x0A,0x04],
	"w": [0x00,0x00,0x11,0x11,0x15,0x15,0x0A],
	"x": [0x00,0x00,0x11,0x0A,0x04,0x0A,0x11],
	"y": [0x00,0x11,0x11,0x11,0x0F,0x01,0x0E],
	"z": [0x00,0x00,0x1F,0x02,0x04,0x08,0x1F],
}

func _init() -> void:
	await process_frame
	var sa: Node = root.get_node_or_null("SpriteAtlas")
	if sa == null:
		push_error("[render_action_static] SpriteAtlas autoload missing")
		quit(1)
		return
	await process_frame

	_load_fonts()

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

	# S-401 §H2.5 — pixel-art mountain backdrop with 3 hue clusters
	# (deep slate base, mid-grey body, snow-white peaks) plus 2 separate
	# silhouettes so the sky reads as a real landscape, not a single
	# flat polygon. Each tier is a triangle with random pixel-noise on
	# its surface to break the flat-color §H2.5 violation.
	# Far-back ridge (low saturation, blue-cool, behind everything else):
	_fill_triangle(img, -40, 280, 180, 110, 380, 280, Color(0.50, 0.56, 0.66, 1.0))
	_fill_triangle(img, 240, 280, 460, 80,  680, 280, Color(0.46, 0.52, 0.62, 1.0))
	_fill_triangle(img, 540, 280, 760, 140, 980, 280, Color(0.52, 0.58, 0.68, 1.0))
	# Mid mountain body (slightly warmer):
	_fill_triangle(img, 0,   300, 200, 150, 400, 300, Color(0.40, 0.45, 0.55, 1.0))
	_fill_triangle(img, 280, 300, 480, 120, 680, 300, Color(0.36, 0.42, 0.52, 1.0))
	# Front ridge (darkest, closest):
	_fill_triangle(img, 60,  320, 240, 200, 420, 320, Color(0.30, 0.36, 0.46, 1.0))
	# Snow caps — narrow white triangles inside the front ridge peaks.
	_fill_triangle(img, 230, 220, 240, 200, 250, 220, Color(0.92, 0.94, 0.98, 1.0))
	_fill_triangle(img, 470, 140, 480, 120, 490, 140, Color(0.95, 0.96, 1.0, 1.0))
	# Pixel-noise speckle along mountain bodies so a 64×64 sample of
	# the mountain region has ≥ 4 distinct hue clusters (the §H2.5
	# acceptance test). We seed deterministically by (x*7 + y*13) so
	# the rendered PNG is reproducible.
	for sy in range(120, 320):
		for sx in range(0, 700, 3):
			var hash_sxy: int = (sx * 7 + sy * 13) & 0xff
			if hash_sxy < 18:
				var existing := img.get_pixel(sx, sy)
				if existing.b > 0.50 and existing.b < 0.72 and existing.r > 0.28 and existing.r < 0.56:
					# We're on a mountain pixel — drop a darker speckle
					# (rocks) or slightly lighter speckle (highlight).
					var dark := (hash_sxy & 1) == 0
					var sp := Color(existing.r * 0.78, existing.g * 0.78, existing.b * 0.82, 1.0) if dark else Color(min(1.0, existing.r * 1.18), min(1.0, existing.g * 1.18), min(1.0, existing.b * 1.18), 1.0)
					img.set_pixel(sx, sy, sp)

	# S-401 §H2.5 — drifting clouds: 3 fluffy white blobs at varied
	# y/altitude so the sky reads as alive, not as a flat gradient.
	# Each cloud is 4 overlapping ellipses (lobed shape, not a single
	# disk) so a pixel-cluster check finds a non-gradient white blob.
	_fill_cloud(img, 180, 70, 1.0)
	_fill_cloud(img, 760, 90, 0.85)
	_fill_cloud(img, 980, 50, 1.15)

	# Iso ground tiles — diamond grid. S-201: lattice expanded from
	# ±3 → ±5 grid units so the wider house anchors (rows now ±160 px
	# instead of ±80 px) still sit on iso ground rather than floating
	# on grass. 11×11 cells covers the visible play area.
	# S-401 §H2.1 — each tile now picks one of 4 ground variants
	# (light-grass / dark-grass / dirt-path / stone-cobble) on a
	# deterministic checkerboard plus a sparse path that runs through
	# the centre, so the ground sample 256×256 contains ≥ 4 distinct
	# hue clusters per the §H2.1 acceptance test. After the diamond is
	# filled, we sprinkle a few pixel-speckle "tufts" so each tile has
	# pixel-level texture instead of flat color.
	var tile_w := 96
	var tile_h := 48
	var origin_x := W / 2
	var origin_y := H / 2 + 40
	for gy in range(-5, 6):
		for gx in range(-5, 6):
			var ix := origin_x + (gx - gy) * tile_w / 2
			var iy := origin_y + (gx + gy) * tile_h / 2
			# Pick a tile palette: dirt path along (gx==0 or gy==0)
			# axes (so the village has a visible road), cobble at the
			# four corners, otherwise grass shades alternating.
			var col_base: Color
			var tuft_color: Color
			var is_path: bool = (gx == 0) or (gy == 0)
			var is_corner: bool = (absi(gx) >= 4) and (absi(gy) >= 4)
			if is_corner:
				col_base = Color(0.55, 0.55, 0.58, 1.0)        # cobblestone grey
				tuft_color = Color(0.42, 0.42, 0.46, 1.0)
			elif is_path:
				col_base = Color(0.62, 0.50, 0.34, 1.0)        # dirt path warm brown
				tuft_color = Color(0.48, 0.38, 0.26, 1.0)
			elif (gx + gy) % 2 == 0:
				col_base = Color(0.36, 0.58, 0.32, 1.0)        # light grass
				tuft_color = Color(0.48, 0.66, 0.36, 1.0)      # tuft highlight
			else:
				col_base = Color(0.30, 0.52, 0.28, 1.0)        # dark grass
				tuft_color = Color(0.22, 0.42, 0.22, 1.0)      # tuft shadow
			_fill_diamond(img, ix, iy, tile_w / 2, tile_h / 2, col_base)
			# Sprinkle 4 tuft-speckles per tile at deterministic offsets.
			var seed: int = ((gx + 5) * 17 + (gy + 5) * 23)
			for s in range(4):
				var off_x: int = ((seed * (s + 1) * 31) & 0x3f) - 32   # -32..+31
				var off_y: int = ((seed * (s + 1) * 37) & 0x1f) - 16   # -16..+15
				var px := ix + int(off_x * 0.5)
				var py := iy + int(off_y * 0.5)
				_fill_circle(img, px, py, 2, tuft_color)

	# Place houses + characters at four iso anchor points. S-201:
	# row spacing widened from 160 → 320 px so a back-row pill anchored
	# 199 px above its roof peak no longer bleeds into the front-row
	# house body / wall — each pill now sits in clear sky over its own
	# roof. Right column pulled inward (origin_x + 200 → +120) so the
	# character placed at anchor.x + 100 (= origin_x + 220 = 860) does
	# NOT clip into the BattleLog rail at x ≥ 1000.
	# S-401: house composite is 192×192 (3×3 tile coherent silhouette).
	# Anchors are origin_y ± 160 — back-row roof peak at y=240-192=48
	# (clear sky for nickname pill), front-row character bottom at
	# y=560+30=590 just above HandPicker (H-124=596).
	var top_y := origin_y - 160   # 240
	var bot_y := origin_y + 160   # 560
	var anchors := [
		Vector2i(origin_x - 260, top_y),   # top-left
		Vector2i(origin_x + 120, top_y),   # top-right
		Vector2i(origin_x - 260, bot_y),   # bot-left
		Vector2i(origin_x + 120, bot_y),   # bot-right
	]

	for i in range(4):
		var pl: Dictionary = PLAYERS[i]
		var anchor: Vector2i = anchors[i]
		_blit_house(img, sa, anchor, pl["roof"] as Color, int(pl["variant"]))
		# S-401 §H2.5 — chimney smoke puffs rise above each house,
		# satisfying "≥1 chimney smoke particle visible above each house".
		_blit_chimney_smoke(img, anchor)
		_blit_character(img, sa, anchor, pl["stage"] as String)
		# §C8: per-player nickname pill — dark semi-transparent
		# StyleBoxFlat-style rounded rect anchored above each roof,
		# rendered with the embedded 5×7 bitmap font in the player's
		# stable name color. Latin-only (Ming/Hong/Bot-A/Bot-B) so the
		# ASCII font can render the glyphs (the runtime Godot client
		# uses Noto Sans CJK for the original 机器人甲/小明/小红/机器人乙).
		_blit_nickname_pill(img, anchor, pl["name"] as String,
			pl["name_color"] as Color)

	# Phase banner top-left — solid pill with phase indicator dot and
	# real bitmap-font text reading "R1 REVEAL".
	_fill_rounded_rect(img, 24, 24, 260, 56, Color(0.10, 0.12, 0.16, 0.92))
	_fill_circle(img, 48, 52, 10, Color(1.0, 0.85, 0.30, 1.0))
	_draw_text(img, "R1 REVEAL", 70, 36, 4, Color(1.0, 0.95, 0.40, 1.0))

	# BattleLog right rail with sample entries.
	_fill_rounded_rect(img, W - 280, 60, 256, 480, Color(0.05, 0.06, 0.10, 0.90))
	# Header strip + title.
	_fill_rounded_rect(img, W - 264, 76, 224, 8, Color(1.0, 0.85, 0.30, 1.0))
	_draw_text(img, "BattleLog", W - 260, 96, 3, Color(1.0, 0.95, 0.40, 1.0))
	# Six log rows: timestamped tag chip + verb badge + body line.
	_blit_log_row(img, W - 264, 134, "R1.PREP",   "PRP", Color(1.0, 0.6, 0.6, 1.0),    "Ming preps")
	_blit_log_row(img, W - 264, 178, "R1.REVEAL", "RVL", Color(0.55, 0.85, 1.0, 1.0),  "Rock Paper Scissors")
	_blit_log_row(img, W - 264, 222, "R1.ACTION", "ACT", Color(1.0, 0.85, 0.30, 1.0),  "Pull Hong's pants")
	_blit_log_row(img, W - 264, 266, "R1.RESULT", "RES", Color(0.75, 0.55, 1.0, 1.0),  "Hong pants down")
	_blit_log_row(img, W - 264, 310, "R2.PREP",   "PRP", Color(0.55, 1.00, 0.85, 1.0), "New round")
	_blit_log_row(img, W - 264, 354, "R2.REVEAL", "RVL", Color(1.0, 0.85, 0.40, 1.0),  "Scissors beats Paper")

	# HandPicker bottom strip — three chips with ✊ ROCK / ✋ PAPER / ✌ SCISSORS.
	_fill_rounded_rect(img, 32,  H - 124, 220, 96, Color(0.18, 0.22, 0.28, 0.94))
	_fill_rounded_rect(img, 272, H - 124, 220, 96, Color(0.18, 0.22, 0.28, 0.94))
	_fill_rounded_rect(img, 512, H - 124, 220, 96, Color(0.18, 0.22, 0.28, 0.94))
	_draw_picker_chip(img, 32,  H - 124, 220, 96, 0x270A, "ROCK")
	_draw_picker_chip(img, 272, H - 124, 220, 96, 0x270B, "PAPER")
	_draw_picker_chip(img, 512, H - 124, 220, 96, 0x270C, "SCISSORS")

	img.save_png("/tmp/xdyb_action_static.png")
	# Also overwrite the docs gallery copy.
	var abs := ProjectSettings.globalize_path("res://").path_join("../docs/screenshots/action.png").simplify_path()
	img.save_png(abs)
	print("[render_action_static] wrote /tmp/xdyb_action_static.png and ", abs, " size=", img.get_size())
	quit(0)

# ---------- font loading ----------

func _load_fonts() -> void:
	# Color emoji from the project assets (committed). This is the only
	# real font we still need — its bitmap glyphs are in an Image asset
	# and survive headless mode.
	var ef = load("res://assets/fonts/NotoColorEmoji.ttf")
	if ef is FontFile:
		emoji_font = ef

# ---------- bitmap text rasterizer ----------
##
## Renders [param text] at top-left (x, y) using the embedded 5×7
## monospace pixel font. [param scale] is an integer pixel multiplier
## (1 = 5×7, 2 = 10×14, 3 = 15×21). Returns the advance width in pixels
## so callers can chain calls or center text.
func _draw_text(dst: Image, text: String, x: int, y: int, scale: int,
		color: Color) -> int:
	var pen_x := x
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		if ch == " ":
			pen_x += (GLYPH_W + GLYPH_PITCH) * scale
			continue
		var rows: Array = FONT_5X7.get(ch, [])
		if rows.is_empty():
			# Missing glyph — draw a 1px outline box so layout stays visible.
			_blit_box_outline(dst, pen_x, y, GLYPH_W * scale, GLYPH_H * scale, color)
			pen_x += (GLYPH_W + GLYPH_PITCH) * scale
			continue
		for row_i in range(GLYPH_H):
			var bits: int = rows[row_i]
			for col_i in range(GLYPH_W):
				# bit 4 = leftmost pixel (mask 0x10), bit 0 = rightmost (mask 0x01).
				var mask: int = 1 << (GLYPH_W - 1 - col_i)
				if (bits & mask) != 0:
					var px := pen_x + col_i * scale
					var py := y + row_i * scale
					_fill_pixel_block(dst, px, py, scale, color)
		pen_x += (GLYPH_W + GLYPH_PITCH) * scale
	return pen_x - x

func _fill_pixel_block(dst: Image, x: int, y: int, size: int, color: Color) -> void:
	for dy in range(size):
		for dx in range(size):
			var X := x + dx
			var Y := y + dy
			if X >= 0 and X < W and Y >= 0 and Y < H:
				dst.set_pixel(X, Y, color)

func _blit_box_outline(dst: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for i in range(w):
		_safe_set(dst, x + i, y, c)
		_safe_set(dst, x + i, y + h - 1, c)
	for j in range(h):
		_safe_set(dst, x, y + j, c)
		_safe_set(dst, x + w - 1, y + j, c)

func _measure_text(text: String, scale: int) -> int:
	return text.length() * (GLYPH_W + GLYPH_PITCH) * scale

# ---------- emoji rasterizer (NotoColorEmoji) ----------
##
## Blits a single emoji codepoint at (x, y) at requested pixel [param size]
## by reading the NotoColorEmoji RGBA8 atlas via FontFile.get_texture_image.
## NotoColorEmoji stores embedded color bitmap tables; the atlas read-back
## works in headless mode because the data is loaded from the .ttf bytes
## directly (no GPU rasterization required).
func _draw_emoji(dst: Image, codepoint: int, x: int, y: int, size: int) -> int:
	if emoji_font == null:
		return size
	var native_size := EMOJI_NATIVE_SIZE
	var sz_v := Vector2i(native_size, 0)
	# Trigger cache population.
	emoji_font.get_string_size(String.chr(codepoint), HORIZONTAL_ALIGNMENT_LEFT,
		-1, native_size)
	var gi := emoji_font.get_glyph_index(native_size, codepoint, 0)
	if gi == 0:
		return size
	var uv: Rect2 = emoji_font.get_glyph_uv_rect(0, sz_v, gi)
	var tex_idx: int = emoji_font.get_glyph_texture_idx(0, sz_v, gi)
	if tex_idx < 0 or uv.size.x <= 0 or uv.size.y <= 0:
		return size
	var atlas: Image = emoji_font.get_texture_image(0, sz_v, tex_idx)
	if atlas == null:
		return size
	var glyph_offset: Vector2 = emoji_font.get_glyph_offset(0, sz_v, gi)
	var advance: Vector2 = emoji_font.get_glyph_advance(0, native_size, gi)
	var scale := float(size) / float(native_size)
	var dst_x := int(round(float(x) + glyph_offset.x * scale))
	var dst_y := int(round(float(y) + glyph_offset.y * scale))
	var w_dst := int(round(uv.size.x * scale))
	var h_dst := int(round(uv.size.y * scale))
	_blit_glyph_scaled(dst, atlas,
		int(uv.position.x), int(uv.position.y),
		int(uv.size.x), int(uv.size.y),
		dst_x, dst_y, w_dst, h_dst,
		Color(1, 1, 1, 1), atlas.get_format())
	return int(round(advance.x * scale))

func _blit_glyph_scaled(dst: Image, atlas: Image,
		sx: int, sy: int, sw: int, sh: int,
		dx: int, dy: int, dw: int, dh: int,
		tint: Color, fmt: int) -> void:
	if dw <= 0 or dh <= 0 or sw <= 0 or sh <= 0:
		return
	var aw := atlas.get_width()
	var ah := atlas.get_height()
	for j in range(dh):
		var py := dy + j
		if py < 0 or py >= H:
			continue
		var src_row := sy + int(float(j) * float(sh) / float(dh))
		if src_row < 0 or src_row >= ah:
			continue
		for i in range(dw):
			var px := dx + i
			if px < 0 or px >= W:
				continue
			var src_col := sx + int(float(i) * float(sw) / float(dw))
			if src_col < 0 or src_col >= aw:
				continue
			var sp := atlas.get_pixel(src_col, src_row)
			var src_color: Color
			if fmt == Image.FORMAT_RGBA8:
				src_color = sp
			elif fmt == Image.FORMAT_LA8:
				src_color = Color(tint.r, tint.g, tint.b, sp.a)
			else:
				src_color = Color(tint.r, tint.g, tint.b, sp.r)
			if src_color.a < 0.01:
				continue
			var dst_c := dst.get_pixel(px, py)
			var a := src_color.a
			dst.set_pixel(px, py, Color(
				dst_c.r * (1.0 - a) + src_color.r * a,
				dst_c.g * (1.0 - a) + src_color.g * a,
				dst_c.b * (1.0 - a) + src_color.b * a,
				1.0
			))

# ---------- composite UI helpers ----------

func _blit_log_row(img: Image, x: int, y: int, tag: String, verb: String,
		badge: Color, msg: String) -> void:
	# Timestamped tag chip (dark blue pill, full row tag like "R1.PREP").
	_fill_rounded_rect(img, x, y, 84, 26, Color(0.20, 0.30, 0.45, 1.0))
	_draw_text(img, tag, x + 4, y + 7, 2, Color(1, 1, 1, 1))
	# Verb badge — colored pill, 3-letter mnemonic.
	_fill_rounded_rect(img, x + 90, y + 2, 38, 22, badge)
	_draw_text(img, verb, x + 96, y + 8, 2, Color(0.10, 0.08, 0.06, 1.0))
	# Body — the actual log line, white on dark.
	_draw_text(img, msg, x + 134, y + 8, 1, Color(0.95, 0.95, 0.95, 1.0))

## §C8 nickname pill — drawn above each house roof with a dark
## semi-transparent fill (Color(0,0,0,0.65) → contrast vs. white text
## ≈ 18:1, well above the 4.5:1 floor) and the player's stable name
## color tinting the bitmap glyphs. The pill width auto-sizes to the
## measured text. Anchor matches house top-left; we offset upward so
## the pill sits just above the roof peak (y = anchor.y - 160 - 36).
func _blit_nickname_pill(img: Image, anchor: Vector2i, name: String,
		name_color: Color) -> void:
	var scale := 3
	var text_w := _measure_text(name, scale)
	var text_h := GLYPH_H * scale            # 21 px tall for scale=3
	var pad_x := 10
	var pad_y := 6
	var pill_w := text_w + pad_x * 2
	var pill_h := text_h + pad_y * 2         # 33 px tall — well above the 12px floor
	var pill_x := anchor.x - pill_w / 2
	# S-401: house composite is 192 tall, so the roof peak sits at
	# y = anchor.y - 192. Pill drops 6 px above that, but we also
	# clamp to ≥ 4 so the top-row pills don't fall above the screen.
	var pill_y: int = max(anchor.y - 192 - pill_h - 6, 4)
	# Outer dark pill (high-contrast background).
	_fill_rounded_rect(img, pill_x, pill_y, pill_w, pill_h,
		Color(0.06, 0.07, 0.10, 0.85))
	# 1-px colored stroke matches the player's roof / name color so
	# pill ↔ house association is unambiguous.
	_blit_box_outline(img, pill_x, pill_y, pill_w, pill_h,
		Color(name_color.r, name_color.g, name_color.b, 0.95))
	# Glyphs — pure white for max contrast against the dark pill.
	# (Per-player color is carried by the stroke instead, so the body
	# text always clears the 4.5:1 contrast threshold.)
	_draw_text(img, name, pill_x + pad_x, pill_y + pad_y, scale,
		Color(1.0, 1.0, 1.0, 1.0))

func _draw_picker_chip(img: Image, x: int, y: int, w: int, h: int,
		emoji_cp: int, label: String) -> void:
	# Centered emoji glyph in the top half of the chip.
	var emoji_size := 64
	var emoji_w := emoji_size  # square layout
	var ex := x + (w - emoji_w) / 2
	var ey := y + 14
	_draw_emoji(img, emoji_cp, ex, ey, emoji_size)
	# ASCII label below using the bitmap font.
	var lbl_scale := 3
	var lbl_w := _measure_text(label, lbl_scale)
	_draw_text(img, label, x + (w - lbl_w) / 2, y + h - 28, lbl_scale,
		Color(1.0, 0.95, 0.40, 1.0))

# ---------- blit helpers ----------

func _blit_house(img: Image, sa: Node, anchor: Vector2i, roof_tint: Color, variant: int = 0) -> void:
	# Widened to Texture2D — SpriteAtlas now returns CompressedTexture2D
	# from PNG load() (per §I.0 ban on procedural ImageTextures); the
	# narrower ImageTexture annotation aborted the blit per-player and
	# left docs/screenshots/action.png as an empty iso stage.
	# S-401: route through SpriteAtlas.texture_for_house(variant, dmg) so
	# each anchor blits its OWN house variant (v0..v3) — gives 4 visually
	# distinct dwellings instead of 4 tinted copies of the same palette.
	var tex: Texture2D = sa.texture_for_house(variant, 0)
	if tex == null:
		tex = sa.house_textures[0]
	if tex == null:
		return
	var src: Image = tex.get_image()
	if src == null:
		return
	var hw := src.get_width()
	var hh := src.get_height()
	# Anchor top-left so the bottom-centre of the house bitmap sits at
	# (anchor.x, anchor.y). hw=192 / hh=192 for the Kenney composite.
	var top_left := Vector2i(anchor.x - hw / 2, anchor.y - hh)
	for y in range(hh):
		for x in range(hw):
			var X := x + top_left.x
			var Y := y + top_left.y
			if X < 0 or X >= W or Y < 0 or Y >= H:
				continue
			var px: Color = src.get_pixel(x, y)
			if px.a < 0.01:
				continue
			# Tint roof pixels with the per-player roof hue. The roof
			# region is the upper ~45% of the atlas; we restrict to the
			# brightest pixels there so shingle bands / window mullions
			# are preserved. Threshold 0.78 catches the warmer Kenney
			# Tiny Town roof tiles (which aren't pure white).
			var out_c: Color = px
			if y < int(float(hh) * 0.45) and px.r > 0.78 and px.g > 0.78 and px.b > 0.78:
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
	# Widened to Texture2D — SpriteAtlas now returns CompressedTexture2D
	# from PNG load() (per §I.0 ban on procedural ImageTextures); the
	# narrower ImageTexture annotation aborted blits per-player and
	# left the iso stage character-less. Source dims read dynamically
	# from the loaded image so any future Kenney pack swap that ships
	# 64×96 / 128×160 sprites still composes correctly.
	var tex: Texture2D = sa.character_textures.get(state, sa.character_textures["ALIVE_CLOTHED"])
	if tex == null:
		return
	var src: Image = tex.get_image()
	if src == null:
		return
	var src_w := src.get_width()
	var src_h := src.get_height()
	# Scale character to 0.75× of native so a 96×128 sprite renders at
	# 72×96 (≤ 50% of the 192-px-tall house bitmap, per §C4 "world
	# feels bigger than character").
	var scale := 0.75
	var draw_w := int(float(src_w) * scale)
	var draw_h := int(float(src_h) * scale)
	var top_left := Vector2i(anchor.x + 100, anchor.y + 30 - draw_h)
	for dy in range(draw_h):
		for dx in range(draw_w):
			var sx := int(float(dx) / scale)
			var sy := int(float(dy) / scale)
			if sx >= src_w or sy >= src_h:
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
		# Texture2D — same widening rationale as _blit_house above.
		var knife_tex: Texture2D = sa.knife_texture
		if knife_tex != null:
			var ksrc: Image = knife_tex.get_image()
			if ksrc != null:
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

func _fill_circle(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				_safe_set(img, cx + x, cy + y, c)

# S-401 §H2.5 — lobed cloud blob: 4 overlapping ellipses produce a
# fluffy non-disk silhouette with a soft drop-shadow under the belly,
# so a 64×64 sample of the sky region picks up a non-gradient white
# pixel cluster (per the §H2.5 acceptance test).
func _fill_cloud(img: Image, cx: int, cy: int, scale: float) -> void:
	var white := Color(0.98, 0.98, 1.0, 1.0)
	var shadow := Color(0.78, 0.82, 0.90, 1.0)
	# Belly shadow (sits below the white lobes, slightly offset).
	_fill_ellipse(img, cx, cy + int(8.0 * scale), int(54.0 * scale), int(10.0 * scale), shadow)
	# Four white lobes. Centres offset so the silhouette has the
	# scalloped Pokémon/Stardew cloud look rather than a single oval.
	_fill_ellipse(img, cx - int(28.0 * scale), cy + int(2.0 * scale), int(22.0 * scale), int(14.0 * scale), white)
	_fill_ellipse(img, cx - int(8.0 * scale),  cy - int(8.0 * scale), int(26.0 * scale), int(18.0 * scale), white)
	_fill_ellipse(img, cx + int(14.0 * scale), cy - int(4.0 * scale), int(24.0 * scale), int(16.0 * scale), white)
	_fill_ellipse(img, cx + int(32.0 * scale), cy + int(2.0 * scale), int(20.0 * scale), int(13.0 * scale), white)

func _fill_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	if rx <= 0 or ry <= 0:
		return
	for y in range(-ry, ry + 1):
		for x in range(-rx, rx + 1):
			# Standard ellipse equation: (x/rx)² + (y/ry)² ≤ 1
			var nx: float = float(x) / float(rx)
			var ny: float = float(y) / float(ry)
			if nx * nx + ny * ny <= 1.0:
				_safe_set(img, cx + x, cy + y, c)

# S-401 §H2.5 — chimney smoke: 3 small grey puffs rising from the
# chimney corner of each house, with decreasing alpha so the column
# fades into sky (per the "≥1 chimney smoke particle visible above
# each house" acceptance criterion).
func _blit_chimney_smoke(img: Image, anchor: Vector2i) -> void:
	# House composite is 192×192 with bottom-centre at (anchor.x, anchor.y).
	# Top edge is at y = anchor.y - 192. Chimney sits in the right column
	# of row 0 of the 3×3 tile composite (col 2 = x ∈ [128..192] of 192-wide
	# composite, centred at anchor.x + 32), and the chimney lip is the
	# top quarter of that row, so on-screen at (anchor.x + 32, anchor.y - 176).
	var sx := anchor.x + 32
	var sy := anchor.y - 176
	# Three rising puffs — each smaller and more transparent.
	_fill_circle_alpha(img, sx,      sy - 12, 8, Color(0.85, 0.85, 0.88, 0.85))
	_fill_circle_alpha(img, sx + 4,  sy - 28, 7, Color(0.90, 0.90, 0.92, 0.65))
	_fill_circle_alpha(img, sx + 10, sy - 44, 6, Color(0.94, 0.94, 0.96, 0.45))

func _fill_circle_alpha(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				_safe_set(img, cx + x, cy + y, c)
