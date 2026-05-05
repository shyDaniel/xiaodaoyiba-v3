## render_label_collision_persist.gd — S-297 acceptance test for the
## §C8 NAME-LABEL FAN-OUT INCOMPLETE regression described in the
## iter-65 outstanding-work brief.
##
## Background. S-285 fixed the 3-actor pile-up case by walking
## _house_occupants inside play_action's PULL_PANTS / CHOP branches,
## but the live-runtime screenshots (t10000.png 'randomNi97',
## t22000.png 'randominter', t27000.png 'counrandom') showed the bug
## STILL appearing on TIE / spectator rounds where:
##   1. Visitors from a prior round stay camped at the resident's
##      house (per FINAL_GOAL §C3 "no return-home phase"), then
##   2. The next round transitions WITHOUT calling play_action
##      (TIE-only round, dead-human spectator round), so
##   3. _reset_round_ui clears _house_occupants and resets every
##      character to stack-index 0 — collapsing all the camped labels
##      back on top of each other.
##
## The S-297 fix moves stack-index assignment OUT of the one-shot
## play_action hook and INTO the LabelStackReconciler.compute()
## algorithm driven by ACTUAL world positions: any 2+ characters
## within ANCHOR_PROXIMITY_PX of the same house anchor get distinct
## stack indices, regardless of round/phase. GameStage._process now
## calls into LabelStackReconciler every frame.
##
## Acceptance (verbatim from the iter-65 brief):
##   "Add a runtime test that spawns 3 characters at a shared anchor,
##    advances 5 simulated round transitions WITHOUT any
##    PULL_PANTS/CHOP call, and asserts pairwise label rect
##    intersection area = 0 at every transition."
##
## Test architecture: we drive LabelStackReconciler.compute() directly
## (the pure algorithm, extracted from GameStage so it has no
## GameState/Audio/Timing autoload dependencies). The simulated
## "round transition" simply re-invokes the reconciler. Per S-297 the
## reconciler MUST keep the visitors fanned out across every
## reconcile call regardless of how many "rounds" pass — there is no
## clearing step.
##
## Run:
##   godot --headless --path client --script res://tests/render_label_collision_persist.gd
##
## Exit codes:
##   0 = pass
##   1 = at least one assertion failed
extends SceneTree

const RECONCILER := preload("res://scripts/stage/LabelStackReconciler.gd")
const CHAR_SCENE_PATH := "res://scenes/characters/Character.tscn"
const ANCHOR_OFFSET := Vector2(0, 64)
const PROXIMITY_PX: float = 32.0

# Minimal house stand-in: a Node2D that just provides a position
# anchor for the reconciler to compare distances against.
func _make_house(pos: Vector2) -> Node2D:
	var h := Node2D.new()
	h.position = pos
	return h

# Apply a reconciler result to live characters — exactly what
# GameStage._reconcile_label_stacks does internally. Cache passed by
# ref so cross-call no-op detection works (matches production).
func _apply_result(result: Dictionary, characters: Dictionary,
		stack_cache: Dictionary, dim_cache: Dictionary) -> void:
	var desired_idx: Dictionary = result.get("idx", {})
	var desired_dim: Dictionary = result.get("dim", {})
	for cpid in desired_idx.keys():
		var pid: String = String(cpid)
		if not characters.has(pid):
			continue
		var ch = characters[pid]
		if ch == null:
			continue
		var want_idx: int = int(desired_idx[pid])
		var want_dim: bool = bool(desired_dim[pid])
		var prev_idx: int = int(stack_cache.get(pid, -1))
		var prev_dim: bool = bool(dim_cache.get(pid, false))
		if want_idx != prev_idx and ch.has_method("set_label_stack_index"):
			ch.set_label_stack_index(want_idx)
			stack_cache[pid] = want_idx
		if want_dim != prev_dim and ch.has_method("set_label_resident_dimmed"):
			ch.set_label_resident_dimmed(want_dim)
			dim_cache[pid] = want_dim

func _init() -> void:
	var failures: Array[String] = []

	# Wait for autoloads (SpriteAtlas) to settle before instancing
	# Character.tscn (its _ready calls /root/SpriteAtlas).
	await process_frame
	await process_frame

	var char_scene: PackedScene = load(CHAR_SCENE_PATH)
	if char_scene == null:
		push_error("[render_label_collision_persist] failed to load Character scene")
		quit(1)
		return

	# Build the resident's house at world (640, 360).
	var house: Node2D = _make_house(Vector2(640, 360))
	root.add_child(house)
	var houses: Dictionary = {"random": house}

	# A second house off-screen (sanity — reconciler does best-house
	# lookup; we want to confirm visitors don't get pulled to the
	# wrong house).
	var house2: Node2D = _make_house(Vector2(2000, 2000))
	root.add_child(house2)
	houses["far"] = house2

	# Per _ensure_character convention, the resident's character
	# spawns at house_pos + (0, 64).
	var resident: Node = char_scene.instantiate()
	resident.player_id = "random"
	resident.nickname = "random"
	resident.color_hue = 0.10
	resident.position = house.position + ANCHOR_OFFSET
	root.add_child(resident)
	var characters: Dictionary = {"random": resident}

	# 3 visitors camped at the resident's house anchor — they all sit
	# at the post-PULL_PANTS landing position (resident.pos + (-32, 0)),
	# which is √(32²)=32 px from the canonical anchor. That's < the
	# +0.5-epsilon proximity bound so the reconciler counts them as
	# visiting random's house.
	var visitor_pids := ["counter", "iron", "mirror"]
	var visitor_chars: Array = []
	for i in range(visitor_pids.size()):
		var v: Node = char_scene.instantiate()
		v.player_id = visitor_pids[i]
		v.nickname = visitor_pids[i]
		v.color_hue = float(i + 1) / 4.0
		v.position = resident.position + Vector2(-32, 0)
		root.add_child(v)
		characters[visitor_pids[i]] = v
		visitor_chars.append(v)

	# Let _ready run on every Character so _label_default_top etc cache.
	for i in range(3):
		await process_frame

	# Sanity: every visitor must be within proximity of the resident's
	# anchor. If this fails the test setup is wrong, not the algorithm.
	var anchor_pos: Vector2 = house.position + ANCHOR_OFFSET
	for v in visitor_chars:
		var d := anchor_pos.distance_to((v as Node2D).position)
		if d > PROXIMITY_PX + 0.5:
			failures.append("setup error: visitor %s is %.2f px from anchor, > proximity %.1f"
				% [(v as Character).nickname, d, PROXIMITY_PX])

	# Drive 5 simulated round transitions. At every transition we
	# invoke the reconciler again — exactly what GameStage._process
	# does each frame. Per S-297 there is no clearing step between
	# transitions; the reconciler must keep visitors fanned out
	# across every call.
	# CRUCIALLY we never call play_action() — this is the
	# spectator/TIE round case the brief targets.
	var stack_cache: Dictionary = {}
	var dim_cache: Dictionary = {}
	var all_chars: Array = [resident] + visitor_chars
	for transition in range(5):
		var result: Dictionary = RECONCILER.compute(
			characters, houses, ANCHOR_OFFSET, PROXIMITY_PX)
		_apply_result(result, characters, stack_cache, dim_cache)
		await process_frame
		await process_frame

		# Compute every label's GLOBAL rect (anchor.position +
		# label.offset). Intersection area pairwise must be zero.
		var rects: Array[Rect2] = []
		for c in all_chars:
			var local: Rect2 = (c as Character).get_name_label_rect()
			var world_pos: Vector2 = (c as Node2D).global_position
			var r := Rect2(world_pos + local.position, local.size)
			rects.append(r)

		print("[render_label_collision_persist] transition %d:" % transition)
		for k in range(rects.size()):
			print("  - %s rect=%s" % [(all_chars[k] as Character).nickname, rects[k]])

		# Pairwise intersection area MUST be zero.
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				var inter: Rect2 = rects[i].intersection(rects[j])
				var area: float = inter.size.x * inter.size.y
				if area > 0.001:
					failures.append("transition %d: labels %d and %d overlap area=%.3f rects=%s,%s"
						% [transition, i, j, area, rects[i], rects[j]])

		# Resident must be dimmed; visitors stay full-alpha. The
		# brief's spec is that this state survives across transitions
		# (the iter-48 bug was that _reset_round_ui un-dimmed and
		# zero-indexed everyone, then nothing re-applied until the
		# next play_action — which never came on a tie round).
		var rlbl: Label = resident.get_node("NameLabel")
		if rlbl != null and abs(rlbl.modulate.a - 0.5) > 0.01:
			failures.append("transition %d: resident alpha=%f, expected 0.5 with 3 visitors camped"
				% [transition, rlbl.modulate.a])
		for v in visitor_chars:
			var vlbl: Label = (v as Node).get_node("NameLabel")
			if vlbl != null and abs(vlbl.modulate.a - 1.0) > 0.01:
				failures.append("transition %d: visitor %s alpha=%f, expected 1.0"
					% [transition, (v as Character).nickname, vlbl.modulate.a])

	# Round-trip check: when visitors walk away (set position back to
	# an off-anchor location) and we reconcile, the resident un-dims
	# and visitors get idx=0 + default outline.
	for v in visitor_chars:
		(v as Node2D).position = Vector2(3000, 3000)
	var roundtrip_result: Dictionary = RECONCILER.compute(
		characters, houses, ANCHOR_OFFSET, PROXIMITY_PX)
	_apply_result(roundtrip_result, characters, stack_cache, dim_cache)
	await process_frame
	var resident_lbl: Label = resident.get_node("NameLabel")
	if resident_lbl != null and abs(resident_lbl.modulate.a - 1.0) > 0.01:
		failures.append("after visitors departed, resident alpha=%f, expected 1.0"
			% resident_lbl.modulate.a)
	for v in visitor_chars:
		var vlbl: Label = (v as Node).get_node("NameLabel")
		if vlbl != null:
			var ol: int = vlbl.get_theme_constant("outline_size")
			if ol > 5:
				failures.append("departed visitor %s still has outline=%d (> 5), expected default"
					% [(v as Character).nickname, ol])

	# Verify the reconciler's deterministic ordering: visitors sorted
	# by pid ascending, so counter=1, iron=2, mirror=3. Re-camp the
	# visitors and check.
	for v in visitor_chars:
		(v as Node2D).position = resident.position + Vector2(-32, 0)
	var det_result: Dictionary = RECONCILER.compute(
		characters, houses, ANCHOR_OFFSET, PROXIMITY_PX)
	var idx_map: Dictionary = det_result.get("idx", {})
	if int(idx_map.get("random", -1)) != 0:
		failures.append("expected resident idx=0, got %d" % int(idx_map.get("random", -1)))
	if int(idx_map.get("counter", -1)) != 1:
		failures.append("expected counter idx=1 (alphabetical first), got %d" % int(idx_map.get("counter", -1)))
	if int(idx_map.get("iron", -1)) != 2:
		failures.append("expected iron idx=2 (alphabetical second), got %d" % int(idx_map.get("iron", -1)))
	if int(idx_map.get("mirror", -1)) != 3:
		failures.append("expected mirror idx=3 (alphabetical third), got %d" % int(idx_map.get("mirror", -1)))

	if failures.is_empty():
		print("[render_label_collision_persist] PASS — 4 labels (1 resident + 3 visitors) maintained zero pairwise overlap area across 5 round transitions WITHOUT any play_action call, deterministic ordering verified (resident=0, then visitors by pid asc), round-tripped correctly when visitors walked off.")
		quit(0)
	else:
		print("[render_label_collision_persist] FAIL:")
		for f in failures:
			print("  - %s" % f)
		quit(1)
