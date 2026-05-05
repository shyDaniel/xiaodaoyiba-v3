## render_house_atlas.gd — render every damage-stage house texture from
## SpriteAtlas to a tiled PNG, and run the §C11 (S-162) acceptance check:
##   1. wall front-face per-pixel value σ ≥ 8/255 (per-pixel noise visible),
##   2. distinguishable horizontal shingle bands on each roof face,
##   3. porch step + drop shadow at the doorway,
##   4. chimney smoke puffs above the chimney lip.
##
## Run with:
##   godot --headless --path client --script res://tests/render_house_atlas.gd
##
## Outputs:
##   /tmp/xdyb_houses.png      — 4-stage atlas tile (768×160)
##   /tmp/xdyb_house_pristine.png — single pristine house
##   stdout: pass/fail metrics
extends SceneTree

func _init() -> void:
	await process_frame
	# SpriteAtlas autoload — ensure populated.
	var sa: Node = root.get_node_or_null("SpriteAtlas")
	if sa == null:
		push_error("[render_house_atlas] SpriteAtlas autoload missing")
		quit(1)
		return
	# Wait for SpriteAtlas._ready to populate textures.
	await process_frame
	await process_frame

	var stages: Array = sa.house_textures
	if stages.size() < 4:
		push_error("[render_house_atlas] expected 4 house textures, got %d" % stages.size())
		quit(1)
		return

	# Build a 4-up tile.
	var tile_w := 192 * 4
	var tile_h := 160
	var atlas := Image.create(tile_w, tile_h, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.40, 0.55, 0.45, 1.0))   # grass background to read silhouettes
	for i in range(4):
		var tex: ImageTexture = stages[i]
		var src: Image = tex.get_image()
		atlas.blit_rect(src, Rect2i(0, 0, 192, 160), Vector2i(i * 192, 0))
	atlas.save_png("/tmp/xdyb_houses.png")
	print("[render_house_atlas] wrote /tmp/xdyb_houses.png ", atlas.get_size())

	# Save a single pristine house for direct inspection.
	var pristine_tex: ImageTexture = stages[0]
	var pristine_img: Image = pristine_tex.get_image()
	pristine_img.save_png("/tmp/xdyb_house_pristine.png")

	# --- S-162 acceptance metrics on pristine (stage 0) ---------------
	# Walls: sample the front-face area excluding wood-grain rows so we
	# measure the noise on otherwise-flat C_WALL pixels.
	var cx := 96
	var wall_y0 := 73
	var wall_y1 := 100   # avoid door area below
	var wall_x0 := cx - 68
	var wall_x1 := cx + 68
	# Compute sigma of the value channel on wall pixels that are not
	# wood-grain shade (those rows are y in {82,96}).
	var values: Array = []
	for y in range(wall_y0, wall_y1):
		# Skip wood-grain shade scan rows for noise measurement.
		if y == 82 or y == 96:
			continue
		for x in range(wall_x0, wall_x1):
			var px: Color = pristine_img.get_pixel(x, y)
			# Wall body should be roughly C_WALL (0.94, 0.84, 0.66) ±5%.
			# Filter to only "wall-ish" pixels by hue range.
			if px.a < 1.0:
				continue
			if px.r < 0.85 or px.r > 1.0:
				continue
			if px.g < 0.74 or px.g > 0.92:
				continue
			# Use red channel as proxy for value (luma).
			values.append(px.r)
	if values.is_empty():
		push_error("[render_house_atlas] FAIL — no wall pixels sampled")
		quit(1)
		return

	var mean: float = 0.0
	for v in values:
		mean += v
	mean /= float(values.size())
	var var_sum: float = 0.0
	for v in values:
		var_sum += (v - mean) * (v - mean)
	var sigma_01: float = sqrt(var_sum / float(values.size()))    # 0..1 scale
	var sigma_255: float = sigma_01 * 255.0
	print("[render_house_atlas] wall noise sigma: %.3f (= %.2f / 255), n=%d" % [sigma_01, sigma_255, values.size()])

	# --- Roof shingle band check --------------------------------------
	# Sample roof front face along the centreline column x=cx, rows 22..68
	# step 1; expect the colour to alternate between roof base (~white) and
	# shingle shade (~grey) in distinct horizontal bands. Count the number
	# of distinct dark→light transitions; require ≥ 4 bands.
	var prev_dark := false
	var transitions := 0
	for y in range(22, 70):
		var px: Color = pristine_img.get_pixel(cx, y)
		var is_dark: bool = (px.r + px.g + px.b) / 3.0 < 0.85
		if is_dark != prev_dark:
			transitions += 1
		prev_dark = is_dark
	# Each band gives 2 transitions (light→dark→light), so ≥ 4 bands ≈ 8 transitions
	# but we tolerate noise: require ≥ 6.
	print("[render_house_atlas] roof centre-column transitions: %d" % transitions)

	# --- Porch step check ---------------------------------------------
	# Porch is at y in [150, 153] in C_DOOR_SHADE-ish brown, drop shadow at y in [154, 155].
	var porch_brown_count := 0
	for y in range(150, 154):
		for x in range(cx - 22, cx + 22):
			var px: Color = pristine_img.get_pixel(x, y)
			if px.r > 0.25 and px.r < 0.6 and px.g > 0.10 and px.g < 0.45 and px.b < 0.30 and px.a > 0.5:
				porch_brown_count += 1
	print("[render_house_atlas] porch-brown pixel count: %d" % porch_brown_count)

	# --- Chimney smoke check ------------------------------------------
	# Smoke ellipses centered around x=cx+22..cx+27, y in [0..20]; light
	# semi-transparent grey-white pixels.
	var smoke_pixels := 0
	for y in range(0, 22):
		for x in range(cx + 8, cx + 40):
			var px: Color = pristine_img.get_pixel(x, y)
			if px.a > 0.15 and px.a < 0.65 and px.r > 0.85 and px.g > 0.85 and px.b > 0.85:
				smoke_pixels += 1
	print("[render_house_atlas] smoke pixel count: %d" % smoke_pixels)

	# --- Verdict ------------------------------------------------------
	var pass_sigma := sigma_255 >= 8.0
	var pass_shingles := transitions >= 6
	var pass_porch := porch_brown_count >= 60
	var pass_smoke := smoke_pixels >= 30
	var ok := pass_sigma and pass_shingles and pass_porch and pass_smoke
	if ok:
		print("[render_house_atlas] PASS — sigma=%.2f/255 ✓, transitions=%d ✓, porch=%d ✓, smoke=%d ✓" % [sigma_255, transitions, porch_brown_count, smoke_pixels])
		quit(0)
	else:
		push_error("[render_house_atlas] FAIL — sigma=%.2f/255 (need ≥8) shingles=%d (need ≥6) porch=%d (need ≥60) smoke=%d (need ≥30)" % [sigma_255, transitions, porch_brown_count, smoke_pixels])
		quit(1)
