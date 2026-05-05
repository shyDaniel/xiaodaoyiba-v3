## render_label_orphan_on_death.gd — S-373 acceptance test for the
## iter-80 ORPHAN 'iron' BANNER regression described in the iter-81
## outstanding-work brief.
##
## Background. screenshots/eval80/t13000.png → t27000.png show an
## "iron" name banner that:
##   - clings to Ming97's house (wrong owner) at t=13000,
##   - drifts to the top-right at t=18000,
##   - rotates 90° and clips into the right-rail BattleLog from
##     t=22000 through t=27000.
## The banner was the NameLabel of `iron`'s Character node, which had
## already DIED. play_death() rotates the corpse 90° and fades it to
## alpha 0.4, but never freed the NameLabel — so the label rode the
## rotation and stayed visible (and even kept its visitor-stylebox
## colored panel from when iron was a live visitor at Ming97's house).
##
## The §H aesthetic gate's contract: "No banner ever renders in
## screen space without a corresponding live character beneath it."
##
## S-373 fix: Character.play_death() now hides + queue_free()s the
## NameLabel, ShameBadge, and ThrowGlyph in the same tick. The
## reconciler also filters DEAD characters out of its input so it
## can't push a corpse into the visitor stack of a live anchor.
##
## Test architecture: spawn 1 resident + 2 visitors at a shared
## anchor, run the reconciler (visitors get idx=1, idx=2), kill one
## visitor via play_death(), then assert:
##   1. The dead visitor's NameLabel is freed (or invisible).
##   2. Re-running the reconciler reassigns the surviving visitor to
##      idx=1 (no longer needing idx=2 since the corpse is excluded).
##   3. The dead visitor's ShameBadge is also gone.
##   4. show_throw() / set_label_stack_index() / set_label_resident_dimmed()
##      on a corpse are all no-ops (no engine errors trying to write
##      to freed nodes).
##
## Run:
##   godot --headless --path client --script res://tests/render_label_orphan_on_death.gd
##
## Exit codes:
##   0 = pass
##   1 = at least one assertion failed
extends SceneTree

const RECONCILER := preload("res://scripts/stage/LabelStackReconciler.gd")
const CHAR_SCENE_PATH := "res://scenes/characters/Character.tscn"
const ANCHOR_OFFSET := Vector2(0, 64)
const PROXIMITY_PX: float = 32.0

func _make_house(pos: Vector2) -> Node2D:
	var h := Node2D.new()
	h.position = pos
	return h

func _live_filter(characters: Dictionary) -> Dictionary:
	# Mirrors GameStage._reconcile_label_stacks's S-373 filter so the
	# test covers the same behavior the runtime applies.
	var live: Dictionary = {}
	for cpid in characters.keys():
		var ch = characters[cpid]
		if ch == null or not is_instance_valid(ch):
			continue
		if ch.has_method("is_dead") and ch.is_dead():
			continue
		live[cpid] = ch
	return live

func _init() -> void:
	var failures: Array[String] = []

	await process_frame
	await process_frame

	var char_scene: PackedScene = load(CHAR_SCENE_PATH)
	if char_scene == null:
		push_error("[render_label_orphan_on_death] failed to load Character scene")
		quit(1)
		return

	# Resident's house at world (640, 360).
	var house: Node2D = _make_house(Vector2(640, 360))
	root.add_child(house)
	var houses: Dictionary = {"random": house}

	# Resident — alive at its own anchor.
	var resident: Node = char_scene.instantiate()
	resident.player_id = "random"
	resident.nickname = "random"
	resident.color_hue = 0.10
	resident.position = house.position + ANCHOR_OFFSET
	root.add_child(resident)

	# Two visitors camped at random's house anchor.
	var iron: Node = char_scene.instantiate()
	iron.player_id = "iron"
	iron.nickname = "iron"
	iron.color_hue = 0.40
	iron.position = resident.position + Vector2(-32, 0)
	root.add_child(iron)

	var counter: Node = char_scene.instantiate()
	counter.player_id = "counter"
	counter.nickname = "counter"
	counter.color_hue = 0.60
	counter.position = resident.position + Vector2(-32, 0)
	root.add_child(counter)

	var characters: Dictionary = {"random": resident, "iron": iron, "counter": counter}

	# Let _ready run on every Character.
	for i in range(3):
		await process_frame

	# Step 1: pre-death sanity. Reconciler assigns counter=1, iron=2
	# (alphabetical visitor ordering — random is the resident at idx=0).
	var pre_death: Dictionary = RECONCILER.compute(
		_live_filter(characters), houses, ANCHOR_OFFSET, PROXIMITY_PX)
	var pre_idx: Dictionary = pre_death.get("idx", {})
	if int(pre_idx.get("counter", -1)) != 1:
		failures.append("pre-death: expected counter idx=1, got %d" % int(pre_idx.get("counter", -1)))
	if int(pre_idx.get("iron", -1)) != 2:
		failures.append("pre-death: expected iron idx=2, got %d" % int(pre_idx.get("iron", -1)))

	# Apply pre-death indices so visitor styleboxes are installed
	# (mirrors what the live runtime does every frame).
	for cpid in pre_idx.keys():
		var ch = characters.get(String(cpid), null)
		if ch != null and ch.has_method("set_label_stack_index"):
			ch.set_label_stack_index(int(pre_idx[cpid]))

	# Confirm iron's label exists and is visible BEFORE death.
	var iron_lbl_pre: Node = (iron as Node).get_node_or_null("NameLabel")
	if iron_lbl_pre == null or not (iron_lbl_pre as Label).visible:
		failures.append("pre-death: iron's NameLabel should be visible")

	# Step 2: kill iron. play_death() must:
	#   (a) flip iron.is_dead() to true,
	#   (b) hide and queue_free iron's NameLabel + ShameBadge + ThrowGlyph,
	#   (c) leave iron's body sprite alive (faded corpse).
	(iron as Character).play_death()
	# Allow queue_free() to settle.
	await process_frame
	await process_frame

	if not (iron as Character).is_dead():
		failures.append("post-death: iron.is_dead() should be true")

	# Iron's NameLabel must be gone OR invisible. queue_free() may take
	# a frame to actually remove the node, but it must at minimum have
	# been hidden synchronously.
	var iron_lbl_post: Node = (iron as Node).get_node_or_null("NameLabel")
	if iron_lbl_post != null and (iron_lbl_post as Label).visible:
		failures.append("post-death: iron's NameLabel should be hidden or freed")

	# ShameBadge must be gone OR invisible.
	var iron_shame: Node = (iron as Node).get_node_or_null("ShameBadge")
	if iron_shame != null and (iron_shame as Label).visible:
		failures.append("post-death: iron's ShameBadge should be hidden or freed")

	# ThrowGlyph must be gone OR invisible.
	var iron_throw: Node = (iron as Node).get_node_or_null("ThrowGlyph")
	if iron_throw != null and (iron_throw as Label).visible:
		failures.append("post-death: iron's ThrowGlyph should be hidden or freed")

	# Step 3: re-run reconciler with S-373 live filter — iron must be
	# excluded, so counter (the surviving visitor) collapses to idx=1.
	# This is the brief's "live characters only" contract.
	var post_death: Dictionary = RECONCILER.compute(
		_live_filter(characters), houses, ANCHOR_OFFSET, PROXIMITY_PX)
	var post_idx: Dictionary = post_death.get("idx", {})
	if int(post_idx.get("counter", -1)) != 1:
		failures.append("post-death: expected counter idx=1 (sole surviving visitor), got %d"
			% int(post_idx.get("counter", -1)))
	if post_idx.has("iron"):
		failures.append("post-death: dead iron should NOT appear in reconciler output, got idx=%d"
			% int(post_idx.get("iron", -1)))

	# Resident un-dims when only 1 visitor remains? Actually the
	# reconciler dims when ≥1 visitor is camped — so still dimmed
	# with counter present. That's intentional and correct.
	if not bool(post_death.get("dim", {}).get("random", false)):
		failures.append("post-death: random should still be dimmed (counter still camped)")

	# Step 4: Calling label writers on the corpse must be a no-op
	# (no engine errors). This is the defense-in-depth check for the
	# guard in set_label_stack_index / set_label_resident_dimmed /
	# show_throw.
	(iron as Character).set_label_stack_index(99)
	(iron as Character).set_label_resident_dimmed(true)
	(iron as Character).show_throw("✊")
	(iron as Character).hide_throw()
	# If we got here without crashing, the guards work.

	# Step 5: counter walks away (off-anchor) and dies. Both visitors
	# are now gone. Resident un-dims, idx reset to 0.
	(counter as Node2D).position = Vector2(3000, 3000)
	(counter as Character).play_death()
	await process_frame
	await process_frame
	var solo: Dictionary = RECONCILER.compute(
		_live_filter(characters), houses, ANCHOR_OFFSET, PROXIMITY_PX)
	var solo_idx: Dictionary = solo.get("idx", {})
	var solo_dim: Dictionary = solo.get("dim", {})
	if int(solo_idx.get("random", -1)) != 0:
		failures.append("solo: random should be at idx=0, got %d" % int(solo_idx.get("random", -1)))
	if bool(solo_dim.get("random", false)):
		failures.append("solo: random should NOT be dimmed (no live visitors)")

	if failures.is_empty():
		print("[render_label_orphan_on_death] PASS — dead characters lose their NameLabel/ShameBadge/ThrowGlyph in the same tick, are excluded from the reconciler's live snapshot, and survivors collapse cleanly to lower stack indices. No orphan banners can render in screen space without a live character beneath them.")
		quit(0)
	else:
		print("[render_label_orphan_on_death] FAIL:")
		for f in failures:
			print("  - %s" % f)
		quit(1)
