## render_winner_picker.gd — render WinnerPicker.tscn with a synthetic
## prompt so the S-345 Chinese localization can be eyeballed in a PNG
## without having to drive a multi-client session and force a human
## win in the live HTML5 build.
##
## Run with:
##   godot --path client --script res://tests/render_winner_picker.gd
##
## Asserts that the rendered scene contains the §C10 / S-345 Chinese
## strings ("你赢了"/"扒裤衩"/"咔嚓"/"穿好裤衩"/"秒后") and does NOT
## contain the pre-S-345 English strings ("Pick a target"/"Pull pants"
## /"CHOP"/"auto-pick").
##
## Output: /tmp/xdyb_winner_picker.png — 1280x720 viewport.
extends SceneTree

func _init() -> void:
	await process_frame
	var scene: PackedScene = load("res://scenes/ui/WinnerPicker.tscn")
	var wp: Control = scene.instantiate()
	root.add_child(wp)
	# Synthetic prompt: 2 candidate targets, one clothed one pants-down,
	# self-restore allowed so the third action chip is visible too.
	wp.call("open", {
		"candidates": [
			{"id": "p2", "nickname": "小明", "stage": "ALIVE_CLOTHED"},
			{"id": "p3", "nickname": "小红", "stage": "ALIVE_PANTS_DOWN"},
		],
		"canSelfRestore": true,
	})
	# Let the fade-in tween + layout settle.
	for i in range(12):
		await process_frame
	# In --headless mode the dummy rasterizer returns a null viewport
	# texture; skip the PNG dump in that case so this test runs both in
	# CI (headless) and in the editor (rendered).
	var vt = root.get_viewport().get_texture()
	var img: Image = null
	if vt != null:
		img = vt.get_image()
	if img != null:
		var path := "/tmp/xdyb_winner_picker.png"
		img.save_png(path)
		print("[render_winner_picker] wrote ", path, " size=", img.get_size())
	else:
		print("[render_winner_picker] no rasterized viewport (headless dummy renderer)")

	# --- Text assertions (introspect the live scene tree, not the PNG):
	var failures: Array = []
	var title: Label = wp.get_node("Center/Panel/V/Title") as Label
	if not (title.text.find("你赢了") >= 0):
		failures.append("Title missing 你赢了 — got %s" % title.text)
	var hdr: Label = wp.get_node("Center/Panel/V/Targets/Header") as Label
	if not (hdr.text.find("目标") >= 0):
		failures.append("Targets header missing 目标 — got %s" % hdr.text)
	var pull: Button = wp.get_node("Center/Panel/V/Actions/Pull") as Button
	if pull.text != "扒裤衩":
		failures.append("Pull button text != 扒裤衩 — got %s" % pull.text)
	var chop: Button = wp.get_node("Center/Panel/V/Actions/Chop") as Button
	if chop.text != "咔嚓":
		failures.append("Chop button text != 咔嚓 — got %s" % chop.text)
	var self_btn: Button = wp.get_node("Center/Panel/V/Actions/Self") as Button
	if self_btn.text != "穿好裤衩":
		failures.append("Self button text != 穿好裤衩 — got %s" % self_btn.text)
	var countdown: Label = wp.get_node("Center/Panel/V/Countdown") as Label
	if countdown.text.find("秒后") < 0:
		failures.append("Countdown missing 秒后 — got %s" % countdown.text)
	# Per-target chip labels — clothed/pants-down annotation.
	var list: VBoxContainer = wp.get_node("Center/Panel/V/Targets/List") as VBoxContainer
	var saw_clothed := false
	var saw_pantsdown := false
	for c in list.get_children():
		if c is Button:
			var t: String = (c as Button).text
			if t.find("穿着") >= 0:
				saw_clothed = true
			if t.find("光屁股") >= 0:
				saw_pantsdown = true
	if not saw_clothed:
		failures.append("No target chip annotated 穿着")
	if not saw_pantsdown:
		failures.append("No target chip annotated 光屁股")

	# Negative assertions — pre-S-345 English MUST be gone.
	var bad: Array = ["Pull pants", "CHOP", "Pick a target", "auto-pick", "(clothed)", "(pants down)"]
	var all_text: String = "%s | %s | %s | %s | %s | %s" % [
		title.text, hdr.text, pull.text, chop.text, self_btn.text, countdown.text,
	]
	for c in list.get_children():
		if c is Button:
			all_text += " | %s" % (c as Button).text
	for s in bad:
		if all_text.find(s) >= 0:
			failures.append("Pre-S-345 English string still present: %s" % s)

	if failures.is_empty():
		print("[render_winner_picker] PASS (S-345 Chinese strings verified)")
		quit(0)
	else:
		print("[render_winner_picker] FAIL")
		for f in failures:
			print("  - ", f)
		quit(1)
