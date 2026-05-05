## render_label_collision_3actor.gd — S-285 acceptance test for the
## 3-actor name-label pile-up regression described in the iter-48
## outstanding-work brief and FINAL_GOAL §C8.
##
## Background. S-269 fixed the 2-actor visiting overlay ('Baorandom'),
## but the spectator round at t27000.png showed THREE bots camped at
## one resident's anchor with all four NameLabels colliding into
## 'counterorandom'. The S-285 fix in Character.gd + GameStage.gd
## generalises the binary "is visiting" flag into a stack-index API
## (set_label_stack_index) and walks the per-house occupants list
## assigning unique slots so labels fan out vertically.
##
## Acceptance (verbatim from the iter-48 brief):
##   "Add a GUT/headless test that spawns 3 characters at the same
##    anchor and asserts pairwise label rect intersection area = 0."
##
## Run:
##   godot --headless --path client --script res://tests/render_label_collision_3actor.gd
##
## Exit codes:
##   0 = pass
##   1 = at least one assertion failed
extends SceneTree

const CHAR_SCENE_PATH := "res://scenes/characters/Character.tscn"

func _init() -> void:
	var failures: Array[String] = []

	# Wait for autoloads to settle before instancing Character.tscn —
	# Character._ready() reads /root/SpriteAtlas.
	await process_frame
	await process_frame

	var scene: PackedScene = load(CHAR_SCENE_PATH)
	if scene == null:
		push_error("[render_label_collision_3actor] %s failed to load" % CHAR_SCENE_PATH)
		quit(1)
		return

	# 4 characters at one shared anchor: 1 resident + 3 visitors.
	# This reproduces the t27000.png 'counterorandom' pile-up where
	# 'random' is the resident and 'counter', 'iron', 'mirror' have
	# all camped at random's house post-PULL_PANTS in the spectator
	# round. With S-269's binary visiting flag, all three visitors
	# would land on the same y. With S-285's stack-index API, they
	# fan out 1/2/3.
	var anchor := Node2D.new()
	anchor.position = Vector2(640, 360)
	root.add_child(anchor)

	var nicknames := ["random", "counter", "iron", "mirror"]
	var chars: Array = []
	for nick in nicknames:
		var c: Node = scene.instantiate()
		c.player_id = nick
		c.nickname = nick
		c.color_hue = float(nicknames.find(nick)) / float(nicknames.size())
		c.position = Vector2.ZERO  # all share the anchor's global pos
		anchor.add_child(c)
		chars.append(c)
	for i in range(3):
		await process_frame

	# Apply stack indices: resident=0, visitors=1, 2, 3. This is what
	# GameStage._apply_visit_label_stack(actor=*, target=random) does
	# after counter, iron, and mirror have each visited random's house.
	chars[0].set_label_stack_index(0)
	chars[0].set_label_resident_dimmed(true)
	for i in range(1, chars.size()):
		chars[i].set_label_stack_index(i)
	await process_frame

	# Compute each label's GLOBAL rect (anchor.position + char.position
	# + label.offset). Intersection area pairwise must be zero.
	var rects: Array[Rect2] = []
	for c in chars:
		var local: Rect2 = c.get_name_label_rect()
		var world_pos: Vector2 = (c as Node2D).global_position
		var r := Rect2(world_pos + local.position, local.size)
		rects.append(r)
		print("[render_label_collision_3actor] %s rect=%s" % [c.nickname, r])

	# Pairwise intersection area must equal 0 — labels must not overlap.
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			var inter: Rect2 = rects[i].intersection(rects[j])
			var area: float = inter.size.x * inter.size.y
			if area > 0.001:
				failures.append("labels %d and %d overlap: rect[i]=%s rect[j]=%s intersection=%s area=%.3f"
					% [i, j, rects[i], rects[j], inter, area])

	# Each adjacent pair (sorted by y) must be ≥ 20 px apart per the
	# brief's ≥20-px-gap-per-occupant clause. We sort by rect.y because
	# stack indices are 0/1/2/3 but their rendered y is descending
	# (idx=3 has the LOWEST y since it sits on top of the stack).
	var ys: Array[float] = []
	for r in rects:
		ys.append(r.position.y)
	ys.sort()
	for k in range(ys.size() - 1):
		var gap := ys[k + 1] - ys[k]
		if gap < 20.0:
			failures.append("adjacent labels gap=%.2f < 20px (brief requires ≥20px per occupant)" % gap)

	# Sanity: every nickname must still parse as a distinct string —
	# the OCR-style acceptance from the brief. We can't run real OCR
	# in headless Godot, but we can assert each label still carries
	# its own unique text and is rendered with the visiting outline.
	var seen_text: Dictionary = {}
	for c in chars:
		var lbl: Label = c.get_node("NameLabel")
		if lbl == null:
			failures.append("%s NameLabel missing" % c.nickname)
			continue
		var t := lbl.text
		if t == "" or seen_text.has(t):
			failures.append("nickname text collision or empty: %s" % t)
		seen_text[t] = true

	# Visitors (idx ≥ 1) must have the heavier outline so the floating
	# label pops against the iso-stage background. Resident keeps the
	# default outline. Brief calls this "contrasting drop-shadow".
	for i in range(chars.size()):
		var lbl: Label = chars[i].get_node("NameLabel")
		if lbl == null:
			continue
		var outline: int = lbl.get_theme_constant("outline_size")
		if i == 0:
			# Resident — default outline (4 px in the .tscn).
			if outline > 5:
				failures.append("resident outline=%d should remain ≤ 5 px" % outline)
		else:
			# Visitor — must be ≥ 6 px (drop-shadow contrast clause).
			if outline < 6:
				failures.append("visitor[%d] outline=%d < 6 px (no drop-shadow)" % [i, outline])

	# Resident alpha must be dimmed; visitors stay full-alpha.
	var resident_lbl: Label = chars[0].get_node("NameLabel")
	if resident_lbl != null and abs(resident_lbl.modulate.a - 0.5) > 0.01:
		failures.append("resident alpha=%f, expected 0.5 with 3 visitors present" % resident_lbl.modulate.a)
	for i in range(1, chars.size()):
		var vlbl: Label = chars[i].get_node("NameLabel")
		if vlbl != null and abs(vlbl.modulate.a - 1.0) > 0.01:
			failures.append("visitor[%d] alpha=%f, expected 1.0" % [i, vlbl.modulate.a])

	if failures.is_empty():
		print("[render_label_collision_3actor] PASS — 4 labels fan out with 0 pairwise overlap area, ≥20px gap per occupant, visitors get drop-shadow outline, resident dims to 50%% alpha.")
		quit(0)
	else:
		print("[render_label_collision_3actor] FAIL:")
		for f in failures:
			print("  - %s" % f)
		quit(1)
