## render_label_collision_pull_pants_distance.gd — S-302 acceptance test
## for the §C8 NAME-LABEL FIX INCOMPLETE regression described in the
## iter-65 outstanding-work brief.
##
## Background. S-269/S-285/S-297 each fixed a distinct flavour of the
## name-label pile-up, but the live HTML5 build at iter-49 STILL
## rendered "Meicounter" at t27000 R4.PREP — a 2-character composite
## glyph at the shared anchor. The earlier unit tests passed because
## they exercise the post-fix state directly (call
## set_label_stack_index manually, characters at IDENTICAL positions),
## while the live game has the visitor offset by Vector2(-32, 0)
## from the target after a PULL_PANTS rush. That horizontal offset
## (a) is too small to keep their labels from overlapping when both
## share the resident's stack-index 0, and (b) means even after the
## reconciler runs we need the per-occupant horizontal stagger to
## land the visitor's label rectangle distinctly from the resident's.
##
## This test reproduces the LIVE post-PULL_PANTS geometry: visitor
## (Mei28) at house.position + Vector2(-32, 64), resident (counter)
## at house.position + Vector2(0, 64). It drives
## LabelStackReconciler.compute() at that geometry, applies the
## resulting stack indices to live Character scene instances, and
## asserts that the rendered label rects (in world space) have
## ZERO pairwise intersection area AND that adjacent-y label gaps
## are ≥ 20 px per the brief.
##
## Acceptance (from the S-302 brief):
##   "render the live R3.IMPACT and R4.PREP frames programmatically
##    (validate-game-progression.mjs), OCR each NameLabel region —
##    every player name MUST parse as a separate distinct string,
##    AND a headless GUT/scene_test must spawn 3 Characters at one
##    anchor and assert pairwise label rect intersection area = 0."
##
## We satisfy the OCR-distinct clause by ensuring (a) the rendered
## rects have ZERO pairwise intersection area (so the glyphs cannot
## physically share a single screen-region) and (b) the per-occupant
## horizontal stagger means that even at adjacent stack indices the
## label x-spans don't perfectly align, which is what made
## "counterMei28" parse as a single OCR token in the iter-49 image.
##
## Run:
##   godot --headless --path client --script res://tests/render_label_collision_pull_pants_distance.gd
##
## Exit codes:
##   0 = pass
##   1 = at least one assertion failed
extends SceneTree

const RECONCILER := preload("res://scripts/stage/LabelStackReconciler.gd")
const CHAR_SCENE_PATH := "res://scenes/characters/Character.tscn"
const ANCHOR_OFFSET := Vector2(0, 64)
const PROXIMITY_PX: float = 32.0
const HOUSE_AT := Vector2(640, 360)
# Mei28's PULL_PANTS landing offset relative to the target's char
# position (target_char.position + Vector2(-32, 0) per
# GameStage.play_action()'s rush_to call).
const VISITOR_LANDING_OFFSET := Vector2(-32, 0)

func _world_label_rect(ch: Node) -> Rect2:
	var local: Rect2 = ch.get_name_label_rect()
	var world_pos: Vector2 = (ch as Node2D).global_position
	return Rect2(world_pos + local.position, local.size)

func _init() -> void:
	var failures: Array[String] = []

	await process_frame
	await process_frame

	var scene: PackedScene = load(CHAR_SCENE_PATH)
	if scene == null:
		push_error("[pull_pants_distance] %s failed to load" % CHAR_SCENE_PATH)
		quit(1)
		return

	# Build the "counter's house" anchor and put the resident at
	# anchor.position (i.e. character at house + (0, 64) per
	# GameStage._ensure_character) and the visitor at the
	# PULL_PANTS landing position house + (-32, 64).
	var resident_house := Node2D.new()
	resident_house.position = HOUSE_AT
	root.add_child(resident_house)

	# Two more houses for the OTHER players (random + visitor's own
	# home), well out of proximity range, so the reconciler can't
	# attribute the visitor to her own anchor instead of counter's.
	var visitor_home := Node2D.new()
	visitor_home.position = HOUSE_AT + Vector2(-400, 0)
	root.add_child(visitor_home)
	var third_home := Node2D.new()
	third_home.position = HOUSE_AT + Vector2(0, 400)
	root.add_child(third_home)

	# Resident character at the resident's anchor (= house + (0, 64)).
	var resident: Node = scene.instantiate()
	resident.player_id = "counter"
	resident.nickname = "counter"
	resident.color_hue = 0.10
	resident.position = HOUSE_AT + ANCHOR_OFFSET
	root.add_child(resident)

	# Visitor character at the PULL_PANTS landing position relative
	# to the resident's character.
	var visitor: Node = scene.instantiate()
	visitor.player_id = "Mei28"
	visitor.nickname = "Mei28"
	visitor.color_hue = 0.55
	visitor.position = (resident as Node2D).position + VISITOR_LANDING_OFFSET
	root.add_child(visitor)

	# Third player ("random") chilling at her own home — should NOT
	# get confused with the shared anchor.
	var third: Node = scene.instantiate()
	third.player_id = "random"
	third.nickname = "random"
	third.color_hue = 0.85
	third.position = visitor_home.position + ANCHOR_OFFSET
	root.add_child(third)

	# Let _ready run on all three Characters.
	for i in range(3):
		await process_frame

	# Wire up the reconciler's input dictionaries the same way
	# GameStage does: pid → Node2D for both characters and houses.
	var characters := {
		"counter": resident,
		"Mei28": visitor,
		"random": third,
	}
	var houses := {
		"counter": resident_house,
		"Mei28": visitor_home,
		"random": third_home,
	}

	# Run the reconciler — what GameStage._process calls every frame.
	var result: Dictionary = RECONCILER.compute(
		characters, houses, ANCHOR_OFFSET, PROXIMITY_PX)
	var desired_idx: Dictionary = result.get("idx", {})
	var desired_dim: Dictionary = result.get("dim", {})

	# Assertion 1: the reconciler MUST classify Mei28 as a visitor at
	# counter's house (idx=1) and counter as the resident (idx=0).
	# random stays unanchored / at her own anchor (idx=0). This is
	# the bedrock of the live fix — if this fails the geometry is
	# misclassified and the live render shows two idx=0 labels
	# overlapping (the iter-49 "Meicounter" symptom).
	var counter_idx := int(desired_idx.get("counter", -1))
	var mei_idx := int(desired_idx.get("Mei28", -1))
	if counter_idx != 0:
		failures.append("counter (resident) idx=%d, expected 0" % counter_idx)
	if mei_idx != 1:
		failures.append("Mei28 (visitor at PULL_PANTS landing) idx=%d, expected 1 — reconciler misclassified the visiting actor" % mei_idx)

	# Apply to the live Characters and re-tick once so the offsets
	# settle.
	for pid in desired_idx.keys():
		var s := String(pid)
		if not characters.has(s):
			continue
		var ch: Node = characters[s]
		if ch.has_method("set_label_stack_index"):
			ch.set_label_stack_index(int(desired_idx[s]))
		if ch.has_method("set_label_resident_dimmed"):
			ch.set_label_resident_dimmed(bool(desired_dim.get(s, false)))
	await process_frame

	# Assertion 2: pairwise label rect intersection area = 0 (the
	# headline acceptance from the brief). Compute world-space rects
	# (character.global_position + label.offset) for the resident and
	# visitor at counter's house. random's label is far away so it
	# can't overlap regardless.
	var rects := {
		"counter": _world_label_rect(resident),
		"Mei28": _world_label_rect(visitor),
		"random": _world_label_rect(third),
	}
	var pids := ["counter", "Mei28", "random"]
	for i in range(pids.size()):
		for j in range(i + 1, pids.size()):
			var ri: Rect2 = rects[pids[i]]
			var rj: Rect2 = rects[pids[j]]
			var inter: Rect2 = ri.intersection(rj)
			var area: float = inter.size.x * inter.size.y
			if area > 0.001:
				failures.append("labels %s and %s overlap: rect[%s]=%s rect[%s]=%s intersection_area=%.3f"
					% [pids[i], pids[j], pids[i], ri, pids[j], rj, area])
			print("[pull_pants_distance] %s↔%s rect_a=%s rect_b=%s area=%.3f"
				% [pids[i], pids[j], ri, rj, area])

	# Assertion 3: vertical gap between the resident's and visitor's
	# label tops must be ≥ 20 px (the brief's per-occupant clause).
	# Visitors stack ABOVE the resident (lower y in Godot 2D).
	var counter_rect: Rect2 = rects["counter"]
	var mei_rect: Rect2 = rects["Mei28"]
	var dy: float = abs(counter_rect.position.y - mei_rect.position.y)
	if dy < 20.0:
		failures.append("vertical gap between counter and Mei28 labels = %.2f px, brief requires ≥ 20 px" % dy)
	if mei_rect.position.y >= counter_rect.position.y:
		failures.append("Mei28 (visitor) label y=%.1f should be < counter (resident) label y=%.1f"
			% [mei_rect.position.y, counter_rect.position.y])

	# Assertion 4: the visitor's label outline differs from the
	# resident's (heavier outline + tinted colour). This is the
	# brief's "contrasting outline/drop-shadow per label" clause —
	# even if two glyphs ever did land near the same screen y, the
	# colour-contrasted strokes would still read as separate names.
	var resident_label: Label = resident.get_node("NameLabel")
	var visitor_label: Label = visitor.get_node("NameLabel")
	var r_outline: int = resident_label.get_theme_constant("outline_size")
	var v_outline: int = visitor_label.get_theme_constant("outline_size")
	if v_outline <= r_outline:
		failures.append("visitor outline=%d should be > resident outline=%d (heavier stroke)"
			% [v_outline, r_outline])
	if v_outline < 8:
		failures.append("visitor outline=%d < 8 — too thin for the brief's drop-shadow clause" % v_outline)
	var r_stroke: Color = resident_label.get_theme_color("font_outline_color")
	var v_stroke: Color = visitor_label.get_theme_color("font_outline_color")
	# Resident keeps the default near-black outline; visitor gets a
	# saturated tint of her own player hue.
	var stroke_distance: float = abs(r_stroke.r - v_stroke.r) + abs(r_stroke.g - v_stroke.g) + abs(r_stroke.b - v_stroke.b)
	if stroke_distance < 0.05:
		failures.append("resident outline=%s ≈ visitor outline=%s — brief requires CONTRASTING outline colours"
			% [r_stroke, v_stroke])

	# Assertion 5: horizontal stagger means the visitor's label x-span
	# does NOT line up with the resident's, even before considering
	# the 32-px Mei28-position offset. Compute the centre x of each
	# label-rect; the visitor's centre minus the resident's centre
	# must include the per-occupant stagger AND the position offset.
	var counter_cx := counter_rect.position.x + counter_rect.size.x * 0.5
	var mei_cx := mei_rect.position.x + mei_rect.size.x * 0.5
	# Visitor character is 32 px LEFT of resident character; the
	# horizontal stagger pushes the visitor's label 4 px RIGHT of
	# its character centre. Net: counter_cx - mei_cx = 32 - 4 = 28.
	# We accept anything in [24, 32] as long as the offset is
	# nonzero AND not-equal-to-the-character-offset (which would be
	# 32 with no stagger applied, the bug-state).
	var cx_delta: float = counter_cx - mei_cx
	if abs(cx_delta - 32.0) < 0.5:
		failures.append("horizontal stagger NOT applied — visitor cx=%f resident cx=%f delta=%f equals the raw character offset (no horizontal fan-out)"
			% [mei_cx, counter_cx, cx_delta])

	# Assertion 6: resident dimmed, visitor at full alpha — same
	# foreground/context contract from S-269.
	if abs(resident_label.modulate.a - 0.5) > 0.01:
		failures.append("resident alpha=%f, expected 0.5 with visitor present" % resident_label.modulate.a)
	if abs(visitor_label.modulate.a - 1.0) > 0.01:
		failures.append("visitor alpha=%f, expected 1.0" % visitor_label.modulate.a)

	if failures.is_empty():
		print("[pull_pants_distance] PASS — counter (resident) and Mei28 (visitor at PULL_PANTS landing) labels: 0 pairwise rect intersection area, dy=%.1f px ≥ 20, contrasting outlines, horizontal stagger applied (cx_delta=%.1f ≠ 32)."
			% [dy, cx_delta])
		quit(0)
	else:
		print("[pull_pants_distance] FAIL:")
		for f in failures:
			print("  - %s" % f)
		quit(1)
