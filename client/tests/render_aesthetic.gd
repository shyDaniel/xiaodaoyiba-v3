## render_aesthetic.gd — verifies S-370 §H aesthetic gate deliverables.
##
## Background. FINAL_GOAL §H demands a Stardew-quality painted product
## surface, not the default Godot dark-rounded-rectangle look. This test
## asserts the seven §H deltas have been wired through to disk + scene
## root nodes:
##   §H2.1 — ground_atlas.png exists and is at least 4×64 px wide
##   §H2.4 — BattleLog/HandPicker/PhaseBanner/WinnerPicker root panels
##           use StyleBoxTexture (not StyleBoxFlat) for the "panel" style
##           override; HandPicker buttons use StyleBoxTexture for normal
##   §H2.5 — House.tscn has a CPUParticles2D chimney node, Background
##           has a Clouds layer with the Clouds.gd script attached
##   §H2.6 — palette.tres exists and exposes ≥16 colors via PackedColorArray
##   §H2.7 — hover.wav and click.wav exist under audio/sfx/
##
## A failure here means the §H product surface has regressed and the
## screenshots will go back to looking "amateur web prototype 2015".
##
## Run with:
##   godot --headless --path client --script res://tests/render_aesthetic.gd
##
## Exit codes:
##   0 = pass
##   1 = at least one assertion failed
extends SceneTree

func _init() -> void:
	var failures: Array[String] = []

	# Let SceneTree initialize autoloads (Audio, Palette, GameState, …)
	# before instantiating any scene that references them.
	await process_frame
	await process_frame

	# §H2.6 — palette.tres exists and has ≥16 colors.
	var palette_res: Resource = load("res://assets/palette.tres")
	if palette_res == null:
		failures.append("palette.tres failed to load")
	else:
		var colors: Variant = palette_res.get_meta("colors", null)
		if colors == null:
			failures.append("palette.tres has no metadata/colors")
		elif not (colors is PackedColorArray):
			failures.append("palette.tres metadata/colors is not PackedColorArray (got %s)"
				% str(typeof(colors)))
		elif (colors as PackedColorArray).size() < 16:
			failures.append("palette.tres has only %d colors (need ≥16)"
				% (colors as PackedColorArray).size())

	# §H2.7 — hover.wav + click.wav exist on disk.
	for sfx in ["hover", "click"]:
		var sfx_path := "res://assets/audio/sfx/%s.wav" % sfx
		if not ResourceLoader.exists(sfx_path):
			failures.append("missing %s" % sfx_path)

	# §H2.1 — ground_atlas.png exists and is wide enough for ≥4 64-px tiles.
	var ground_tex: Texture2D = load("res://assets/sprites/tiles/ground_atlas.png")
	if ground_tex == null:
		failures.append("ground_atlas.png failed to load")
	elif ground_tex.get_width() < 256 or ground_tex.get_height() < 64:
		failures.append("ground_atlas.png too small (%dx%d, expected ≥256×64)"
			% [ground_tex.get_width(), ground_tex.get_height()])

	# §H2.4 — panel-style scenes use StyleBoxTexture (carved-wood) for
	# their root panel theme override.
	var panel_checks := {
		"BattleLog": "res://scenes/ui/BattleLog.tscn",
		"PhaseBanner": "res://scenes/ui/PhaseBanner.tscn",
		"WinnerPicker": "res://scenes/ui/WinnerPicker.tscn",
	}
	for name in panel_checks.keys():
		var path: String = panel_checks[name]
		var pscene: PackedScene = load(path)
		if pscene == null:
			failures.append("%s scene failed to load: %s" % [name, path])
			continue
		var inst: Node = pscene.instantiate()
		var panel: Control = _find_styled_panel(inst)
		if panel == null:
			failures.append("%s: no Control with theme override 'panel' found" % name)
			inst.queue_free()
			continue
		var sb: StyleBox = panel.get_theme_stylebox("panel")
		if sb == null:
			failures.append("%s: theme stylebox 'panel' is null" % name)
		elif sb is StyleBoxFlat:
			failures.append("%s: still uses StyleBoxFlat (need StyleBoxTexture for §H2.4)" % name)
		elif not (sb is StyleBoxTexture):
			failures.append("%s: stylebox is %s (need StyleBoxTexture)"
				% [name, sb.get_class()])
		inst.queue_free()

	# §H2.4 — HandPicker is a button-array scene (no root PanelContainer);
	# assert each Button uses StyleBoxTexture for its 'normal' state.
	var hp_scene: PackedScene = load("res://scenes/ui/HandPicker.tscn")
	if hp_scene == null:
		failures.append("HandPicker.tscn failed to load")
	else:
		var hp_inst: Node = hp_scene.instantiate()
		var saw_button := false
		for btn in _walk(hp_inst):
			if btn is Button:
				saw_button = true
				var bsb: StyleBox = (btn as Button).get_theme_stylebox("normal")
				if bsb == null:
					failures.append("HandPicker button %s has null normal stylebox"
						% (btn as Button).name)
				elif bsb is StyleBoxFlat:
					failures.append("HandPicker button %s still uses StyleBoxFlat"
						% (btn as Button).name)
				elif not (bsb is StyleBoxTexture):
					failures.append("HandPicker button %s normal is %s (need StyleBoxTexture)"
						% [(btn as Button).name, bsb.get_class()])
		if not saw_button:
			failures.append("HandPicker.tscn has no Button children")
		hp_inst.queue_free()

	# §H2.5 — House.tscn has a chimney smoke CPUParticles2D, and
	# Background.tscn has a Clouds layer driven by Clouds.gd.
	var house_scene: PackedScene = load("res://scenes/stage/House.tscn")
	if house_scene == null:
		failures.append("House.tscn failed to load")
	else:
		var hi: Node = house_scene.instantiate()
		var has_smoke := false
		for n in _walk(hi):
			if n is CPUParticles2D:
				has_smoke = true
				break
		if not has_smoke:
			failures.append("House.tscn has no CPUParticles2D (chimney smoke missing)")
		hi.queue_free()

	var bg_scene: PackedScene = load("res://scenes/stage/Background.tscn")
	if bg_scene == null:
		failures.append("Background.tscn failed to load")
	else:
		var bi: Node = bg_scene.instantiate()
		var has_clouds := false
		for n in _walk(bi):
			if n.get_script() != null:
				var s: Script = n.get_script()
				if s.resource_path.ends_with("Clouds.gd"):
					has_clouds = true
					break
		if not has_clouds:
			failures.append("Background.tscn has no Clouds.gd-scripted node")
		bi.queue_free()

	if failures.is_empty():
		print("[render_aesthetic] PASS — §H aesthetic gate deliverables present.")
		quit(0)
	else:
		print("[render_aesthetic] FAIL:")
		for f in failures:
			print("  - %s" % f)
		quit(1)

# Find the first Control descendant (including root) that has a 'panel'
# theme stylebox override — this is the carved-wood frame for the UI.
func _find_styled_panel(n: Node) -> Control:
	if n is Control:
		var c: Control = n as Control
		if c.has_theme_stylebox_override("panel"):
			return c
	for child in n.get_children():
		var found := _find_styled_panel(child)
		if found != null:
			return found
	return null

func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
