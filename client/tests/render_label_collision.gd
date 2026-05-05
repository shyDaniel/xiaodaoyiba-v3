## render_label_collision.gd — S-269 acceptance test for the name-label
## collision fix described in the iter-46 outstanding-work brief and
## FINAL_GOAL §C8.
##
## Background. When an actor character rushes to a target's house and
## camps on the same anchor (PULL_PANTS / CHOP), the prior build drew
## both NameLabels at the same y position, producing garbled overlaps
## like "randoming14" or "co…random" in the t13000/t18000/t22000 judge
## screenshots. The fix in Character.gd + GameStage.gd stacks the
## visiting actor's NameLabel LABEL_STACK_OFFSET (16px) above its
## default position, and fades the resident's NameLabel to 50% alpha
## so the two read as foreground / context instead of overlapping.
##
## Acceptance (verbatim from the iter-46 brief):
##   "render test placing 2 characters at the same anchor must assert
##    label_rect.position.y values differ by ≥ label_rect.size.y + 4"
##
## Run:
##   godot --headless --path client --script res://tests/render_label_collision.gd
##
## Exit codes:
##   0 = pass
##   1 = at least one assertion failed
extends SceneTree

const CHAR_SCENE_PATH := "res://scenes/characters/Character.tscn"

func _init() -> void:
	var failures: Array[String] = []

	# Wait for autoloads to settle before instancing Character.tscn —
	# Character._ready() calls _atlas() which expects /root/SpriteAtlas
	# to exist.
	await process_frame
	await process_frame

	var scene: PackedScene = load(CHAR_SCENE_PATH)
	if scene == null:
		push_error("[render_label_collision] %s failed to load" % CHAR_SCENE_PATH)
		quit(1)
		return

	# Two characters parented to a shared anchor. We deliberately give
	# them the same global position so the only thing distinguishing
	# the two NameLabels is the visiting-stack offset on the actor and
	# the alpha fade on the resident.
	var anchor := Node2D.new()
	anchor.position = Vector2(640, 360)
	root.add_child(anchor)

	var resident: Node = scene.instantiate()
	resident.player_id = "ming14"
	resident.nickname = "Ming14"
	resident.color_hue = 0.55
	anchor.add_child(resident)

	var visitor: Node = scene.instantiate()
	visitor.player_id = "random"
	visitor.nickname = "random"
	visitor.color_hue = 0.10
	# Same position as resident — the iter-46 reproducer is exactly
	# "actor visits target's house anchor; both characters share a
	# Vector2 position" and the labels collide.
	visitor.position = resident.position
	anchor.add_child(visitor)

	# Let _ready run and cache _label_default_top / _label_default_bottom.
	for i in range(3):
		await process_frame

	# Pre-condition: BEFORE the visit-stack is applied, the two
	# NameLabel rects should be at the same y — that's the bug.
	var pre_resident_rect: Rect2 = resident.get_name_label_rect()
	var pre_visitor_rect: Rect2 = visitor.get_name_label_rect()
	if not is_equal_approx(pre_resident_rect.position.y, pre_visitor_rect.position.y):
		# Not strictly a failure for this test, but flag it because the
		# collision repro depends on the two labels starting co-located.
		failures.append("pre-condition: resident.label.y=%f != visitor.label.y=%f — characters' default label y diverged"
			% [pre_resident_rect.position.y, pre_visitor_rect.position.y])

	# Apply the fix: visitor stacks above, resident dims.
	visitor.set_label_visiting(true)
	resident.set_label_resident_dimmed(true)
	await process_frame

	# Post-condition (acceptance): the two label rects' top-left y
	# values must differ by ≥ label_rect.size.y + 4 — i.e. there's
	# at least a 4-pixel gap between the bottom of the visitor's
	# label and the top of the resident's label, because the
	# visitor sits LABEL_STACK_OFFSET (16px) above its default and
	# the labels are ~20px tall.
	var resident_rect: Rect2 = resident.get_name_label_rect()
	var visitor_rect: Rect2 = visitor.get_name_label_rect()
	var dy: float = abs(resident_rect.position.y - visitor_rect.position.y)
	var min_gap: float = resident_rect.size.y + 4.0

	print("[render_label_collision] resident.rect=%s visitor.rect=%s dy=%.2f min_gap=%.2f"
		% [resident_rect, visitor_rect, dy, min_gap])

	if dy < min_gap:
		failures.append("label y-delta %f < required %f (resident.size.y=%f + 4)"
			% [dy, min_gap, resident_rect.size.y])

	# The visitor's label should sit ABOVE the resident's (lower y in
	# Godot 2D coordinates), not below — otherwise the dim-resident
	# rule loses its "foreground / context" meaning.
	if visitor_rect.position.y >= resident_rect.position.y:
		failures.append("visitor label y=%f should be < resident label y=%f (visitor must stack ABOVE resident)"
			% [visitor_rect.position.y, resident_rect.position.y])

	# The resident's label should be dimmed to 50% alpha while the
	# visitor is present.
	var resident_label: Label = resident.get_node("NameLabel")
	if resident_label == null:
		failures.append("resident NameLabel node missing")
	else:
		var a := resident_label.modulate.a
		if abs(a - 0.5) > 0.01:
			failures.append("resident NameLabel alpha=%f, expected 0.5 while visitor present" % a)

	# The visitor's label should remain at full alpha (it's the
	# foreground name).
	var visitor_label: Label = visitor.get_node("NameLabel")
	if visitor_label != null and abs(visitor_label.modulate.a - 1.0) > 0.01:
		failures.append("visitor NameLabel alpha=%f, expected 1.0 (foreground)" % visitor_label.modulate.a)

	# Round-trip: clearing visiting-state should restore default y.
	visitor.set_label_visiting(false)
	resident.set_label_resident_dimmed(false)
	await process_frame
	var post_visitor_rect: Rect2 = visitor.get_name_label_rect()
	if not is_equal_approx(post_visitor_rect.position.y, pre_visitor_rect.position.y):
		failures.append("clearing visiting-state should restore label y=%f, got y=%f"
			% [pre_visitor_rect.position.y, post_visitor_rect.position.y])
	if resident_label != null and abs(resident_label.modulate.a - 1.0) > 0.01:
		failures.append("clearing resident-dim should restore alpha=1.0, got %f"
			% resident_label.modulate.a)

	if failures.is_empty():
		print("[render_label_collision] PASS — visitor label stacks ≥ %.0fpx above resident, resident dims to 50%% alpha, clean round-trip."
			% min_gap)
		quit(0)
	else:
		print("[render_label_collision] FAIL:")
		for f in failures:
			print("  - %s" % f)
		quit(1)
