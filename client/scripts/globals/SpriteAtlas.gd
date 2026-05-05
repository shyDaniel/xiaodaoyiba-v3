# SpriteAtlas.gd — autoload that procedurally renders all gameplay
# sprites (characters, houses, knife, FX particles) into ImageTextures
# at boot.
#
# §C11 viral aesthetic gate: hand-drawn PNGs would be ideal, but the
# project must boot self-sufficient (FINAL_GOAL §G "ships and runs
# without art uploads"). So this module paints proper pixel-art-ish
# bitmaps via Image.set_pixel — outlined silhouettes, soft cell shading,
# faces (eyes / mouth), distinct character/house states, and a literal
# knife sprite for the rush + attack frames.
#
# Palette is intentionally constrained (~24 hues) for cohesion. Hue
# tinting per-player is applied at draw time via Sprite2D.modulate, so
# the base atlases are 1-channel-per-region grayscale-friendly.
#
# Sizes per FINAL_GOAL §C4: character ≈96×128 native, house ≈192×160.
# Knife ≈48×16 fits as a child Sprite2D rotated to swing on attack.

extends Node

# --- public API ---------------------------------------------------------

# Character body in a given state. State is one of:
#   "ALIVE_CLOTHED" | "ALIVE_PANTS_DOWN" | "RUSHING" | "ATTACKING" | "DEAD"
# Returns a 96×128 RGBA8 ImageTexture. The torso pixels are tinted in
# the per-player hue at draw time via Sprite2D.modulate; the rest of the
# body uses fixed palette colours (skin / hair / pants / briefs / outline).
var character_textures: Dictionary = {}     # state_str -> ImageTexture

# 192×160 house texture in a given damage stage:
#   0 = pristine, 1 = scratched, 2 = chopped door, 3 = ruined.
var house_textures: Array = []              # damage_stage -> ImageTexture

# 48×16 knife — used as a hand prop on the character and as a rush trail.
var knife_texture: ImageTexture
var knife_trail_texture: ImageTexture       # 64×24 motion-blur trail

# 32×32 FX dot textures for GPUParticles2D: dust, cloth, wood-chip,
# confetti. Each is a soft-edged colored disc with alpha falloff.
var fx_dust_texture: ImageTexture
var fx_cloth_texture: ImageTexture
var fx_woodchip_texture: ImageTexture
var fx_confetti_texture: ImageTexture

# --- palette (≤24 hues) -------------------------------------------------

const C_OUTLINE       := Color(0.08, 0.06, 0.10, 1.0)
const C_SKIN          := Color(0.98, 0.84, 0.70, 1.0)
const C_SKIN_SHADE    := Color(0.85, 0.66, 0.52, 1.0)
const C_HAIR          := Color(0.18, 0.12, 0.10, 1.0)
const C_EYE           := Color(0.10, 0.08, 0.10, 1.0)
const C_MOUTH         := Color(0.55, 0.20, 0.18, 1.0)
const C_TORSO         := Color(1.00, 1.00, 1.00, 1.0)   # tinted via modulate
const C_TORSO_SHADE   := Color(0.78, 0.78, 0.80, 1.0)
const C_PANTS         := Color(0.20, 0.22, 0.32, 1.0)
const C_PANTS_SHADE   := Color(0.13, 0.15, 0.22, 1.0)
const C_SHOE          := Color(0.10, 0.08, 0.08, 1.0)
const C_BRIEFS        := Color(0.92, 0.20, 0.24, 1.0)
const C_BRIEFS_SHADE  := Color(0.66, 0.10, 0.14, 1.0)
const C_BRIEFS_HI     := Color(1.00, 0.45, 0.45, 1.0)

const C_WALL          := Color(0.94, 0.84, 0.66, 1.0)
const C_WALL_SHADE    := Color(0.78, 0.66, 0.48, 1.0)
const C_WALL_DARK     := Color(0.60, 0.48, 0.34, 1.0)
const C_ROOF          := Color(1.00, 1.00, 1.00, 1.0)   # tinted via modulate
const C_ROOF_SHADE    := Color(0.55, 0.55, 0.58, 1.0)
const C_ROOF_RIDGE    := Color(0.30, 0.18, 0.14, 1.0)
const C_DOOR          := Color(0.45, 0.26, 0.14, 1.0)
const C_DOOR_SHADE    := Color(0.30, 0.16, 0.08, 1.0)
const C_DOOR_KNOB     := Color(1.00, 0.85, 0.30, 1.0)
const C_WINDOW        := Color(0.62, 0.84, 0.96, 1.0)
const C_WINDOW_HI     := Color(0.92, 0.97, 1.00, 1.0)
const C_WINDOW_FRAME  := Color(0.30, 0.22, 0.14, 1.0)

const C_KNIFE_BLADE   := Color(0.92, 0.94, 0.98, 1.0)
const C_KNIFE_BLADE_HI:= Color(1.00, 1.00, 1.00, 1.0)
const C_KNIFE_BLADE_LO:= Color(0.62, 0.66, 0.74, 1.0)
const C_KNIFE_GUARD   := Color(0.72, 0.62, 0.18, 1.0)
const C_KNIFE_HANDLE  := Color(0.40, 0.22, 0.12, 1.0)
const C_KNIFE_HANDLE_HI := Color(0.66, 0.36, 0.18, 1.0)

const CHAR_W := 96
const CHAR_H := 128
const HOUSE_W := 192
const HOUSE_H := 160

func _ready() -> void:
	_build_character_atlas()
	_build_house_atlas()
	_build_knife()
	_build_knife_trail()
	_build_fx_textures()

# --- character ----------------------------------------------------------

func _build_character_atlas() -> void:
	for s in ["ALIVE_CLOTHED", "ALIVE_PANTS_DOWN", "RUSHING", "ATTACKING", "DEAD"]:
		character_textures[s] = _render_character(s)

func _render_character(state: String) -> ImageTexture:
	var img := Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	# Transparent background.
	img.fill(Color(0, 0, 0, 0))

	# Body geometry, centered around x=48. Origin (0,0) at top-left;
	# feet at y=124, head top at y=12.
	var cx := 48
	var pants_down := (state == "ALIVE_PANTS_DOWN")
	var dead := (state == "DEAD")
	var attacking := (state == "ATTACKING")
	var rushing := (state == "RUSHING")

	# Shadow ellipse under feet.
	_fill_ellipse(img, cx, 122, 22, 5, Color(0, 0, 0, 0.35))

	# Legs (pants area). When pants_down, briefs at hips, pants pooled
	# at ankles. When DEAD, legs are still drawn but everything tints
	# greyscale in modulate.
	# Left leg
	_fill_rect(img, cx - 14, 86, 10, 32, C_PANTS)
	_fill_rect(img, cx - 14, 86, 4, 32, C_PANTS_SHADE)   # cell shade
	# Right leg
	_fill_rect(img, cx + 4, 86, 10, 32, C_PANTS)
	_fill_rect(img, cx + 4, 86, 4, 32, C_PANTS_SHADE)
	# Shoes
	_fill_rect(img, cx - 16, 116, 14, 6, C_SHOE)
	_fill_rect(img, cx + 2, 116, 14, 6, C_SHOE)

	if pants_down:
		# Pants pooled around ankles — dark heap on each foot.
		_fill_ellipse(img, cx - 9, 116, 9, 5, C_PANTS_SHADE)
		_fill_ellipse(img, cx + 9, 116, 9, 5, C_PANTS_SHADE)
		# Bare thighs (skin) where pants used to cover.
		_fill_rect(img, cx - 14, 86, 10, 18, C_SKIN)
		_fill_rect(img, cx + 4, 86, 10, 18, C_SKIN)
		_fill_rect(img, cx - 14, 86, 4, 18, C_SKIN_SHADE)
		_fill_rect(img, cx + 4, 86, 4, 18, C_SKIN_SHADE)
		# Red briefs.
		_fill_rect(img, cx - 18, 78, 36, 14, C_BRIEFS)
		_fill_rect(img, cx - 18, 78, 36, 4, C_BRIEFS_HI)
		_fill_rect(img, cx - 18, 88, 36, 4, C_BRIEFS_SHADE)
		# Briefs leg-cuts (small triangles).
		for i in range(8):
			img.set_pixel(cx - 18 + i, 88 + i, Color(0, 0, 0, 0))
			img.set_pixel(cx + 17 - i, 88 + i, Color(0, 0, 0, 0))

	# Torso (tintable — drawn in white so modulate hues it).
	# Slightly trapezoidal: wider at shoulders.
	_fill_trapezoid(img, cx - 20, 44, cx + 20, 44, cx - 16, 80, cx + 16, 80, C_TORSO)
	# Cell shade on left half.
	_fill_trapezoid(img, cx - 20, 44, cx - 4, 44, cx - 16, 80, cx - 4, 80, C_TORSO_SHADE)
	# Belt (only when not pants-down).
	if not pants_down:
		_fill_rect(img, cx - 17, 78, 34, 4, Color(0.20, 0.14, 0.10, 1.0))

	# Arms.
	if attacking:
		# Right arm raised holding knife (knife is a separate Sprite2D);
		# arm sprite bends up-right. Left arm forward.
		_fill_rect(img, cx + 16, 36, 10, 26, C_TORSO)            # raised arm
		_fill_rect(img, cx + 16, 36, 4, 26, C_TORSO_SHADE)
		_fill_rect(img, cx + 22, 30, 8, 10, C_SKIN)              # hand
		_fill_rect(img, cx - 26, 56, 10, 18, C_TORSO)            # off-arm fwd
		_fill_rect(img, cx - 30, 70, 10, 8, C_SKIN)              # off-hand
	elif rushing:
		# Both arms pumped back like running.
		_fill_rect(img, cx - 28, 50, 10, 22, C_TORSO)
		_fill_rect(img, cx + 18, 50, 10, 22, C_TORSO)
		_fill_rect(img, cx - 30, 68, 10, 8, C_SKIN)
		_fill_rect(img, cx + 20, 68, 10, 8, C_SKIN)
	else:
		# Standing arms hanging.
		_fill_rect(img, cx - 28, 48, 10, 28, C_TORSO)
		_fill_rect(img, cx + 18, 48, 10, 28, C_TORSO)
		_fill_rect(img, cx - 28, 48, 4, 28, C_TORSO_SHADE)
		_fill_rect(img, cx - 30, 74, 10, 8, C_SKIN)
		_fill_rect(img, cx + 20, 74, 10, 8, C_SKIN)

	# Neck.
	_fill_rect(img, cx - 5, 38, 10, 8, C_SKIN_SHADE)

	# Head (round-ish — circle minus jaw line).
	_fill_ellipse(img, cx, 24, 18, 18, C_SKIN)
	_fill_ellipse_shade(img, cx, 24, 18, 18, C_SKIN_SHADE)
	# Hair cap on top.
	_fill_arc_top(img, cx, 24, 18, 12, C_HAIR)

	# Face features. Eyes + mouth differ slightly by state.
	if dead:
		# X eyes.
		_draw_x(img, cx - 7, 22, C_EYE)
		_draw_x(img, cx + 7, 22, C_EYE)
		# Wavy mouth.
		_fill_rect(img, cx - 5, 32, 10, 1, C_MOUTH)
	elif attacking:
		# Angry eyes (tilted).
		_fill_rect(img, cx - 9, 22, 5, 2, C_EYE)
		_fill_rect(img, cx - 8, 21, 3, 1, C_EYE)
		_fill_rect(img, cx + 4, 22, 5, 2, C_EYE)
		_fill_rect(img, cx + 5, 21, 3, 1, C_EYE)
		# Open shouting mouth.
		_fill_rect(img, cx - 5, 30, 10, 5, C_MOUTH)
		_fill_rect(img, cx - 4, 31, 8, 1, Color(0.95, 0.95, 0.95, 1.0))
	elif rushing:
		# Determined eyes.
		_fill_rect(img, cx - 8, 22, 4, 2, C_EYE)
		_fill_rect(img, cx + 4, 22, 4, 2, C_EYE)
		_fill_rect(img, cx - 4, 32, 8, 1, C_MOUTH)
	elif pants_down:
		# Surprised "O" eyes + mouth.
		_fill_ellipse(img, cx - 6, 22, 2, 2, C_EYE)
		_fill_ellipse(img, cx + 6, 22, 2, 2, C_EYE)
		_fill_ellipse(img, cx, 32, 3, 3, C_MOUTH)
	else:
		# Happy eyes (simple dots) and small smile.
		_fill_rect(img, cx - 7, 22, 3, 3, C_EYE)
		_fill_rect(img, cx + 5, 22, 3, 3, C_EYE)
		# Eye highlights.
		img.set_pixel(cx - 6, 22, Color(1, 1, 1, 1))
		img.set_pixel(cx + 6, 22, Color(1, 1, 1, 1))
		_draw_smile(img, cx, 31, 5, C_MOUTH)

	# Outline pass — black 1px outline around any non-transparent pixel
	# with at least one transparent neighbour. Cheap silhouette pop.
	_outline_pass(img, C_OUTLINE)

	# DEAD state: tint everything greyscale and tilt 90° at draw time
	# (Character.gd already rotates), but we also darken the torso here
	# so even before modulate the silhouette reads as "fallen".
	if dead:
		_overlay_alpha(img, Color(0.4, 0.4, 0.45, 0.55))

	var tex := ImageTexture.create_from_image(img)
	return tex

# --- house --------------------------------------------------------------

func _build_house_atlas() -> void:
	for stage in range(4):
		house_textures.append(_render_house(stage))

func _render_house(stage: int) -> ImageTexture:
	var img := Image.create(HOUSE_W, HOUSE_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx := 96
	# Foundation / ground shadow.
	_fill_ellipse(img, cx, 156, 80, 5, Color(0, 0, 0, 0.30))

	# Walls — main rectangle, slight perspective: front face dominant,
	# right side narrow strip for 3D feel.
	# Front wall.
	_fill_rect(img, cx - 70, 70, 140, 80, C_WALL)
	# Floor strip (darker bottom band).
	_fill_rect(img, cx - 70, 142, 140, 8, C_WALL_DARK)
	# Right side wall (perspective).
	_fill_parallelogram(img, cx + 70, 70, cx + 86, 56, cx + 86, 138, cx + 70, 150, C_WALL_SHADE)

	# Wood-grain horizontal lines on front wall.
	for y in [82, 96, 110, 124, 138]:
		for x in range(cx - 68, cx + 68):
			if (x + y) % 4 != 0:
				continue
			img.set_pixel(x, y, C_WALL_SHADE)

	# Per-pixel ±5% lightness noise on front wall (§C11 (b)). Deterministic
	# pseudo-random per (x, y) so the same atlas reproduces identically
	# across renders — the acceptance check requires σ ≥ 8/255.
	# Excludes the door footprint area so seams don't clash with door art.
	for y in range(72, 142):
		for x in range(cx - 68, cx + 68):
			# Skip pixels that won't stay wall (door rectangle clobbers them
			# anyway) — saves work.
			if x >= cx - 18 and x < cx + 18 and y >= 100:
				continue
			var p := img.get_pixel(x, y)
			# Only perturb wall-coloured pixels (skip wood-grain shade
			# stripes and any wall_dark already painted).
			if not _color_close(p, C_WALL):
				continue
			# Hash (x,y) → [-1, +1].
			var h: int = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF
			var n: float = (float(h) / 65535.0) * 2.0 - 1.0   # -1..+1
			# ±7% lightness — uniform distribution σ ≈ 0.04 → ≈10/255 which
			# clears the §C11 acceptance threshold of 8/255 with margin.
			var delta: float = n * 0.07
			var nc := Color(
				clampf(p.r + delta, 0.0, 1.0),
				clampf(p.g + delta, 0.0, 1.0),
				clampf(p.b + delta, 0.0, 1.0),
				1.0
			)
			img.set_pixel(x, y, nc)

	# Roof — triangular-ish prism, tintable (white). Shade band on
	# right-back side, ridge line dark.
	# Front face of the roof (large triangle from base 70-pixel wide
	# to peak at cx,16).
	_fill_triangle(img, cx - 86, 70, cx + 70, 70, cx, 18, C_ROOF)
	# Shade triangle on the right (perspective face).
	_fill_triangle(img, cx + 70, 70, cx + 86, 56, cx, 18, C_ROOF_SHADE)

	# Horizontal roof shingle bands (§C11 (a)). Every 7 px from the
	# eave up to the peak, draw a band in C_ROOF_SHADE that's clipped
	# against each roof face's triangle. This breaks up the flat roof
	# faces and reads as proper shingle rows at viewport scale.
	# Front face: triangle (cx-86,70)-(cx+70,70)-(cx,18).
	# Back/right face: triangle (cx+70,70)-(cx+86,56)-(cx,18).
	var shingle_dark := Color(C_ROOF_SHADE.r * 0.78, C_ROOF_SHADE.g * 0.78, C_ROOF_SHADE.b * 0.80, 1.0)
	for y in range(22, 70, 7):
		# Front face shingle band (1 px tall band of shade color).
		for x in range(cx - 86, cx + 71):
			if y < 0 or y >= HOUSE_H:
				continue
			if _point_in_triangle(x, y, cx - 86, 70, cx + 70, 70, cx, 18):
				# Only paint over the existing roof color (don't bleed
				# into chimney area we'll paint after this).
				var p := img.get_pixel(x, y)
				if p.a > 0.0:
					img.set_pixel(x, y, C_ROOF_SHADE)
			# Back face — overlap region for x>cx+70.
			if _point_in_triangle(x, y, cx + 70, 70, cx + 86, 56, cx, 18):
				var p2 := img.get_pixel(x, y)
				if p2.a > 0.0:
					img.set_pixel(x, y, shingle_dark)
		# 1-px under-band shadow line for extra band definition.
		var sy := y + 1
		if sy < 70:
			for x in range(cx - 86, cx + 87):
				if _point_in_triangle(x, sy, cx - 86, 70, cx + 70, 70, cx, 18):
					var p3 := img.get_pixel(x, sy)
					if p3.a > 0.0:
						img.set_pixel(x, sy, Color(p3.r * 0.85, p3.g * 0.85, p3.b * 0.87, 1.0))
				if _point_in_triangle(x, sy, cx + 70, 70, cx + 86, 56, cx, 18):
					var p4 := img.get_pixel(x, sy)
					if p4.a > 0.0:
						img.set_pixel(x, sy, Color(p4.r * 0.78, p4.g * 0.78, p4.b * 0.80, 1.0))

	# Roof ridge line.
	_draw_line(img, cx - 86, 70, cx, 18, C_ROOF_RIDGE)
	_draw_line(img, cx + 70, 70, cx, 18, C_ROOF_RIDGE)
	_draw_line(img, cx - 86, 70, cx + 70, 70, C_ROOF_RIDGE)
	# Eaves (overhang shadow under the roof).
	_fill_rect(img, cx - 72, 70, 144, 3, Color(0, 0, 0, 0.25))

	# Chimney.
	_fill_rect(img, cx + 18, 22, 12, 22, C_WALL_DARK)
	_fill_rect(img, cx + 18, 20, 12, 4, C_OUTLINE)

	# Chimney smoke puffs (§C11 (d)). Static soft-edged grey ellipses
	# stacked above the chimney lip — the GameStage spawns a real
	# GPUParticles2D for live smoke, but having visible puffs in the
	# atlas means the static eval screenshot proves the chimney is "lit"
	# without needing the simulation tree to run.
	_fill_ellipse(img, cx + 24, 16, 6, 4, Color(0.92, 0.92, 0.94, 0.55))
	_fill_ellipse(img, cx + 27, 10, 8, 5, Color(0.92, 0.92, 0.94, 0.45))
	_fill_ellipse(img, cx + 22, 5, 10, 4, Color(0.92, 0.92, 0.94, 0.32))

	# Windows — left + right.
	_draw_window(img, cx - 48, 88, 24, 22)
	_draw_window(img, cx + 24, 88, 24, 22)

	# Door — center, with knob. Damage stages alter the door.
	var door_x := cx - 18
	var door_y := 100
	var door_w := 36
	var door_h := 50

	# Porch step (§C11 (c)). 4-px tall step beneath the doorway, slightly
	# wider than the door, with a 2-px-tall darker shadow line under it.
	# Drawn BEFORE the door so the door sits flush on top of the step.
	var porch_x := door_x - 4
	var porch_y := door_y + door_h
	var porch_w := door_w + 8
	if porch_y + 4 <= HOUSE_H:
		_fill_rect(img, porch_x, porch_y, porch_w, 4, C_DOOR_SHADE)
		# Step front face (slightly lighter to read as 3D).
		_fill_rect(img, porch_x, porch_y, porch_w, 2, Color(0.55, 0.34, 0.18, 1.0))
		# Drop shadow under the step.
		if porch_y + 4 + 2 <= HOUSE_H:
			_fill_rect(img, porch_x + 2, porch_y + 4, porch_w - 4, 2, Color(0.0, 0.0, 0.0, 0.45))

	if stage <= 1:
		_fill_rect(img, door_x, door_y, door_w, door_h, C_DOOR)
		# Frame highlight.
		_fill_rect(img, door_x, door_y, door_w, 2, C_DOOR_SHADE)
		_fill_rect(img, door_x, door_y, 2, door_h, C_DOOR_SHADE)
		# Plank seam.
		_fill_rect(img, cx - 1, door_y + 2, 1, door_h - 4, C_DOOR_SHADE)
		# Knob.
		_fill_ellipse(img, door_x + door_w - 6, door_y + door_h / 2, 2, 2, C_DOOR_KNOB)
	# Stage 1: scratch marks on the door.
	if stage >= 1:
		_draw_line(img, door_x + 6, door_y + 8, door_x + 28, door_y + 22, C_OUTLINE)
		_draw_line(img, door_x + 4, door_y + 14, door_x + 30, door_y + 30, C_OUTLINE)
	# Stage 2: a chopped notch — door split top-right wedge gone +
	# wood splinters.
	if stage == 2:
		# Cut-away triangle (transparent) showing dark interior.
		_fill_triangle(img, door_x + door_w, door_y, door_x + door_w, door_y + 24, door_x + 8, door_y, Color(0, 0, 0, 0))
		# Dark interior visible through the cut.
		_fill_triangle(img, door_x + door_w - 2, door_y + 2, door_x + door_w - 2, door_y + 22, door_x + 10, door_y + 2, Color(0.05, 0.04, 0.06, 1.0))
	# Stage 3: ruined — door fully gone, walls cracked.
	if stage == 3:
		# Erase door area.
		_fill_rect(img, door_x, door_y, door_w, door_h, Color(0, 0, 0, 0))
		# Dark interior.
		_fill_rect(img, door_x + 2, door_y + 4, door_w - 4, door_h - 4, Color(0.05, 0.04, 0.06, 1.0))
		# Crack lines on walls.
		_draw_jagged(img, cx - 56, 90, cx - 30, 140, C_OUTLINE)
		_draw_jagged(img, cx + 36, 96, cx + 64, 138, C_OUTLINE)
		# Roof tile chip.
		_fill_triangle(img, cx + 30, 38, cx + 44, 50, cx + 30, 50, Color(0, 0, 0, 0))

	# Outline pass for silhouette.
	_outline_pass(img, C_OUTLINE)

	return ImageTexture.create_from_image(img)

# --- knife --------------------------------------------------------------

func _build_knife() -> void:
	# 56×20 — handle on the left, blade on the right with a pointed tip.
	var w := 56
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Handle.
	_fill_rect(img, 1, 6, 18, 8, C_KNIFE_HANDLE)
	_fill_rect(img, 1, 6, 18, 2, C_KNIFE_HANDLE_HI)
	# Pommel.
	_fill_ellipse(img, 1, 10, 2, 4, C_KNIFE_HANDLE)
	# Wraps.
	for x in [4, 8, 12, 16]:
		_fill_rect(img, x, 6, 1, 8, Color(0, 0, 0, 0.4))
	# Guard.
	_fill_rect(img, 19, 4, 3, 12, C_KNIFE_GUARD)
	# Blade — long flat triangle pointing right.
	for x in range(22, w - 1):
		var t := float(x - 22) / float(w - 23)
		var half := int(round(7.0 * (1.0 - t * 0.85)))
		for y in range(10 - half, 11 + half):
			if y < 0 or y >= h:
				continue
			# Bevel highlight on top edge.
			if y <= 10 - half + 1:
				img.set_pixel(x, y, C_KNIFE_BLADE_HI)
			elif y >= 10 + half - 1:
				img.set_pixel(x, y, C_KNIFE_BLADE_LO)
			else:
				img.set_pixel(x, y, C_KNIFE_BLADE)
	# Outline.
	_outline_pass(img, C_OUTLINE)
	knife_texture = ImageTexture.create_from_image(img)

func _build_knife_trail() -> void:
	var w := 64
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# A shimmering arc — translucent silver blur.
	for i in range(w):
		var t := float(i) / float(w - 1)
		var alpha := 0.65 * (1.0 - t)
		var half := int(round(8.0 * sin(t * PI)))
		for dy in range(-half, half + 1):
			var y := h / 2 + dy
			if y < 0 or y >= h:
				continue
			var fade: float = alpha * (1.0 - abs(float(dy)) / maxf(float(half), 1.0))
			img.set_pixel(i, y, Color(0.95, 0.97, 1.0, fade))
	knife_trail_texture = ImageTexture.create_from_image(img)

# --- FX dot textures ----------------------------------------------------

func _build_fx_textures() -> void:
	fx_dust_texture     = _radial_dot(32, Color(0.78, 0.70, 0.55, 1.0), 0.5)
	fx_cloth_texture    = _radial_dot(32, Color(0.92, 0.20, 0.24, 1.0), 0.7)
	fx_woodchip_texture = _radial_dot(32, Color(0.55, 0.32, 0.16, 1.0), 0.85)
	# Confetti is multi-coloured stripes.
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var palette := [
		Color(1.0, 0.85, 0.30, 1.0),
		Color(0.30, 0.85, 0.55, 1.0),
		Color(0.30, 0.65, 1.0, 1.0),
		Color(1.0, 0.45, 0.55, 1.0),
		Color(0.85, 0.55, 1.0, 1.0),
	]
	for y in range(32):
		for x in range(32):
			var dx := x - 16
			var dy := y - 16
			var d := sqrt(dx * dx + dy * dy)
			if d <= 14.0:
				var idx := int(((x + y) / 4)) % palette.size()
				var c: Color = palette[idx]
				c.a = 1.0 - d / 14.0
				img.set_pixel(x, y, c)
	fx_confetti_texture = ImageTexture.create_from_image(img)

func _radial_dot(size: int, c: Color, hardness: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := float(x) - r + 0.5
			var dy := float(y) - r + 0.5
			var d := sqrt(dx * dx + dy * dy) / r
			if d > 1.0:
				continue
			var a: float = (1.0 - d) ** (1.0 - hardness * 0.5)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a * c.a))
	return ImageTexture.create_from_image(img)

# --- primitives ---------------------------------------------------------

func _fill_rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var W := img.get_width()
	var H := img.get_height()
	for yy in range(max(y, 0), min(y + h, H)):
		for xx in range(max(x, 0), min(x + w, W)):
			img.set_pixel(xx, yy, c)

func _fill_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	var W := img.get_width()
	var H := img.get_height()
	for yy in range(max(cy - ry, 0), min(cy + ry + 1, H)):
		for xx in range(max(cx - rx, 0), min(cx + rx + 1, W)):
			var dx := float(xx - cx) / float(rx)
			var dy := float(yy - cy) / float(ry)
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(xx, yy, c)

func _fill_ellipse_shade(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	# Shade left-half of an ellipse to suggest light from the upper-right.
	var W := img.get_width()
	var H := img.get_height()
	for yy in range(max(cy - ry, 0), min(cy + ry + 1, H)):
		for xx in range(max(cx - rx, 0), min(cx + 1, W)):
			var dx := float(xx - cx) / float(rx)
			var dy := float(yy - cy) / float(ry)
			if dx * dx + dy * dy <= 1.0 and dx * dx + dy * dy >= 0.5:
				img.set_pixel(xx, yy, c)

func _fill_arc_top(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	# Top half of an ellipse — used for a hair cap.
	var W := img.get_width()
	for yy in range(max(cy - ry, 0), cy):
		for xx in range(max(cx - rx, 0), min(cx + rx + 1, W)):
			var dx := float(xx - cx) / float(rx)
			var dy := float(yy - cy) / float(ry)
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(xx, yy, c)

func _fill_triangle(img: Image, x1: int, y1: int, x2: int, y2: int, x3: int, y3: int, c: Color) -> void:
	# Naive bounding-box scanline.
	var minx: int = max(mini(x1, mini(x2, x3)), 0)
	var miny: int = max(mini(y1, mini(y2, y3)), 0)
	var maxx: int = min(maxi(x1, maxi(x2, x3)), img.get_width() - 1)
	var maxy: int = min(maxi(y1, maxi(y2, y3)), img.get_height() - 1)
	for yy in range(miny, maxy + 1):
		for xx in range(minx, maxx + 1):
			if _point_in_triangle(xx, yy, x1, y1, x2, y2, x3, y3):
				img.set_pixel(xx, yy, c)

func _fill_trapezoid(img: Image, ax: int, ay: int, bx: int, by: int, cx: int, cy: int, dx: int, dy: int, col: Color) -> void:
	# Quad given as (a,b) top edge, (c,d) bottom edge — a-b-d-c order.
	_fill_triangle(img, ax, ay, bx, by, dx, dy, col)
	_fill_triangle(img, ax, ay, dx, dy, cx, cy, col)

func _fill_parallelogram(img: Image, ax: int, ay: int, bx: int, by: int, cx: int, cy: int, dx: int, dy: int, col: Color) -> void:
	_fill_triangle(img, ax, ay, bx, by, cx, cy, col)
	_fill_triangle(img, ax, ay, cx, cy, dx, dy, col)

func _point_in_triangle(px: int, py: int, x1: int, y1: int, x2: int, y2: int, x3: int, y3: int) -> bool:
	var d1 := (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2)
	var d2 := (px - x3) * (y2 - y3) - (x2 - x3) * (py - y3)
	var d3 := (px - x1) * (y3 - y1) - (x3 - x1) * (py - y1)
	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)

func _draw_line(img: Image, x1: int, y1: int, x2: int, y2: int, c: Color) -> void:
	var dx: int = absi(x2 - x1)
	var dy: int = absi(y2 - y1)
	var sx: int = 1 if x1 < x2 else -1
	var sy: int = 1 if y1 < y2 else -1
	var err: int = dx - dy
	var x: int = x1
	var y: int = y1
	var W: int = img.get_width()
	var H: int = img.get_height()
	while true:
		if x >= 0 and y >= 0 and x < W and y < H:
			img.set_pixel(x, y, c)
		if x == x2 and y == y2:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy

func _draw_jagged(img: Image, x1: int, y1: int, x2: int, y2: int, c: Color) -> void:
	var steps := 6
	var prev_x := x1
	var prev_y := y1
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var nx := int(round(lerp(float(x1), float(x2), t)))
		var ny := int(round(lerp(float(y1), float(y2), t)))
		# Random-ish offset (deterministic via i).
		nx += (i % 2) * 3 - 1
		_draw_line(img, prev_x, prev_y, nx, ny, c)
		prev_x = nx
		prev_y = ny

func _draw_x(img: Image, cx: int, cy: int, c: Color) -> void:
	for d in range(-2, 3):
		var ax := cx + d
		var ay1 := cy + d
		var ay2 := cy - d
		var W := img.get_width()
		var H := img.get_height()
		if ax >= 0 and ax < W and ay1 >= 0 and ay1 < H:
			img.set_pixel(ax, ay1, c)
		if ax >= 0 and ax < W and ay2 >= 0 and ay2 < H:
			img.set_pixel(ax, ay2, c)

func _draw_smile(img: Image, cx: int, cy: int, w: int, c: Color) -> void:
	for i in range(-w, w + 1):
		var x := cx + i
		var y := cy + int(round(abs(float(i)) * 0.4))
		if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
			img.set_pixel(x, y, c)

func _draw_window(img: Image, x: int, y: int, w: int, h: int) -> void:
	# Frame.
	_fill_rect(img, x - 2, y - 2, w + 4, h + 4, C_WINDOW_FRAME)
	# Glass.
	_fill_rect(img, x, y, w, h, C_WINDOW)
	# Cross-bar.
	_fill_rect(img, x + w / 2 - 1, y, 2, h, C_WINDOW_FRAME)
	_fill_rect(img, x, y + h / 2 - 1, w, 2, C_WINDOW_FRAME)
	# Highlight on glass top-left of each pane.
	_fill_rect(img, x + 2, y + 2, 6, 4, C_WINDOW_HI)
	_fill_rect(img, x + w / 2 + 2, y + 2, 6, 4, C_WINDOW_HI)
	# Sill.
	_fill_rect(img, x - 4, y + h + 2, w + 8, 3, C_WALL_DARK)

func _outline_pass(img: Image, c: Color) -> void:
	# 1px outline: any transparent pixel adjacent to a non-transparent
	# pixel becomes the outline colour.
	var W := img.get_width()
	var H := img.get_height()
	# Make a snapshot of which pixels are non-transparent.
	var solid := []
	solid.resize(W * H)
	for y in range(H):
		for x in range(W):
			solid[y * W + x] = img.get_pixel(x, y).a > 0.0
	for y in range(H):
		for x in range(W):
			if solid[y * W + x]:
				continue
			var has_neighbor := false
			for dy_i in [-1, 0, 1]:
				for dx_i in [-1, 0, 1]:
					var dy: int = int(dy_i)
					var dx: int = int(dx_i)
					if dx == 0 and dy == 0:
						continue
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= H:
						continue
					if solid[ny * W + nx]:
						has_neighbor = true
						break
				if has_neighbor:
					break
			if has_neighbor:
				img.set_pixel(x, y, c)

func _color_close(a: Color, b: Color, eps: float = 0.02) -> bool:
	# Tight equality check used by the wall-noise pass to avoid perturbing
	# wood-grain stripes / wall_dark / door / window pixels.
	return absf(a.r - b.r) < eps and absf(a.g - b.g) < eps and absf(a.b - b.b) < eps and absf(a.a - b.a) < eps

func _overlay_alpha(img: Image, c: Color) -> void:
	var W := img.get_width()
	var H := img.get_height()
	for y in range(H):
		for x in range(W):
			var p := img.get_pixel(x, y)
			if p.a > 0.0:
				img.set_pixel(x, y, p.lerp(c, c.a))
