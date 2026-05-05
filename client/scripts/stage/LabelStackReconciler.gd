# LabelStackReconciler.gd — pure algorithm for assigning per-character
# NameLabel stack indices and resident-dim flags from current world
# positions. Extracted from GameStage so the headless test
# (render_label_collision_persist.gd) can drive it without dragging in
# the GameState/Audio/Timing autoload chain.
#
# Single entry point: `compute(characters, houses, anchor_offset,
# proximity_px)` → Dictionary with two sub-dicts:
#   { "idx": { pid → int }, "dim": { pid → bool }, "occupants": { house_pid → [pids] } }
#
# Algorithm (S-297):
#   1. For each character, find the nearest house anchor within
#      `proximity_px`. The canonical anchor is `house.position +
#      anchor_offset` (typically (0, 64) so the resident's character
#      at its own house anchor is at distance 0).
#   2. Group characters by anchor; each group becomes
#      [resident, visitor1, visitor2, …] where the resident is the
#      character whose pid matches the house pid (if present), and
#      visitors are sorted by pid ascending for determinism.
#   3. Assign idx 0, 1, 2, … in that order; the resident gets dim=true
#      if there's ≥1 visitor.
#   4. Characters with no nearby house get idx=0, dim=false.
#
# This file deliberately has zero references to GameState, Audio,
# Timing, or any other autoload — it must be safe to load and parse
# from any context (incl. headless test runners that haven't yet
# spun up the SceneTree's autoload chain).

class_name LabelStackReconciler

# `characters` is a Dictionary[String → Node2D] (pid → character node).
# `houses` is a Dictionary[String → Node2D] (pid → house node).
# `anchor_offset` is the Vector2 offset added to house.position to get
#   the canonical anchor against which character positions are compared.
# `proximity_px` is the max distance for a character to count as
#   anchored at a given house. We add a +0.5 epsilon so the
#   PULL_PANTS landing position (target_char.pos + (-32, 0)) at
#   exactly proximity_px from the anchor still counts.
static func compute(characters: Dictionary, houses: Dictionary,
		anchor_offset: Vector2, proximity_px: float) -> Dictionary:
	var pid_at: Dictionary = {}        # house_pid → Array[String]
	var unanchored: Array = []
	var bound: float = proximity_px + 0.5

	for cpid in characters.keys():
		var ch = characters[cpid]
		if ch == null:
			continue
		var ch_pos: Vector2 = (ch as Node2D).position
		var best_house: String = ""
		var best_dist: float = bound
		for hpid in houses.keys():
			var house = houses[hpid]
			if house == null:
				continue
			var anchor_pos: Vector2 = (house as Node2D).position + anchor_offset
			var d: float = anchor_pos.distance_to(ch_pos)
			if d < best_dist:
				best_dist = d
				best_house = String(hpid)
		if best_house == "":
			unanchored.append(String(cpid))
			continue
		var lst: Array = pid_at.get(best_house, [])
		lst.append(String(cpid))
		pid_at[best_house] = lst

	var idx: Dictionary = {}
	var dim: Dictionary = {}
	var occupants_out: Dictionary = {}
	for hpid in pid_at.keys():
		var occupants: Array = pid_at[hpid]
		var resident_pid: String = String(hpid)
		var visitors: Array = []
		var resident_present: bool = false
		for occ in occupants:
			if String(occ) == resident_pid:
				resident_present = true
			else:
				visitors.append(String(occ))
		visitors.sort()
		if resident_present:
			idx[resident_pid] = 0
			dim[resident_pid] = visitors.size() >= 1
		for i in range(visitors.size()):
			# When the resident is at home, visitors get idx=1, 2, 3, …
			# When the resident is away (rare — mid-rush), the first
			# visitor takes idx=0 so labels still don't pile up.
			var slot: int = i + (1 if resident_present else 0)
			idx[visitors[i]] = slot
			dim[visitors[i]] = false
		if visitors.size() > 0:
			occupants_out[resident_pid] = visitors

	for pid in unanchored:
		idx[pid] = 0
		dim[pid] = false
	for cpid in characters.keys():
		var spid: String = String(cpid)
		if not idx.has(spid):
			idx[spid] = 0
			dim[spid] = false

	return { "idx": idx, "dim": dim, "occupants": occupants_out }
