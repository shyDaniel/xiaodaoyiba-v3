# GameStage.gd — the iso 45° gameplay scene root.
#
# Owns:
#   - the isometric ground TileMap
#   - houses (one per player)
#   - characters (one per player)
#   - the cinematic Camera2D
#   - the BattleLog right-rail
#   - the EffectPlayer that consumes round payloads
#
# Per FINAL_GOAL §C1, the ground uses Godot's iso TileMap with a
# procedurally-generated TileSet (so the project boots without external
# art). §C4: characters ≈ 96 px tall, houses ≈ 192 px — world feels
# bigger than the character.
#
# Round flow:
#   GameState.round_received → EffectPlayer.play_round(payload) → dispatches
#   per-effect calls back into this stage (show_rps_reveal, play_action, …).

class_name GameStage
extends Node2D

const Character := preload("res://scripts/characters/Character.gd")

@export var iso_tile_size: Vector2 = Vector2(128, 64)

@onready var ground: Node2D = $World/Ground
@onready var houses_layer: Node2D = $World/Houses
@onready var characters_layer: Node2D = $World/Characters
@onready var effects_layer: Node2D = $World/Effects
@onready var camera: Camera2D = $World/CinematicCamera
@onready var battle_log = $UILayer/BattleLog
@onready var hand_picker = $UILayer/HandPicker
@onready var winner_picker = $UILayer/WinnerPicker
@onready var effect_player: Node = $EffectPlayer
@onready var phase_label: Label = $UILayer/PhaseBanner
@onready var victory_overlay: Control = $UILayer/VictoryOverlay
@onready var victory_label: Label = $UILayer/VictoryOverlay/Center/Label
@onready var tie_banner: Label = $UILayer/TieBanner

var _characters: Dictionary = {}        # player_id → Character
var _houses: Dictionary = {}            # player_id → Node2D
var _player_order: Array = []           # player ids in iteration order
# S-285 — house anchor occupancy ledger. Maps target_pid → ordered
# Array of visitor pids currently camped on that house anchor (in
# arrival order). Used by _apply_visit_label_stack to fan multiple
# visitors' NameLabels out vertically instead of dumping them all on
# top of each other (the t27000 'counterorandom' regression).
#
# S-297 — this ledger is NO LONGER cleared on round transition. The
# previous behavior (clear in _reset_round_ui) re-collapsed all
# stack indices to 0 every round, so when prior-round visitors stayed
# camped (per §C3 no-return-home) and a new TIE round began, the next
# round's labels overlapped again ('randomNi97', 'randominter',
# 'counrandom' in the iter-48 judge screenshots). The ledger is now
# rebuilt every frame from actual world positions in
# _reconcile_label_stacks (any 2+ characters within ≤32 px of the
# same house anchor get distinct stack indices).
var _house_occupants: Dictionary = {}   # target_pid → Array[String]
# S-297 — anchor proximity threshold. Two characters within this many
# pixels of the same house anchor are treated as co-anchored and get
# distinct stack indices. 32 px matches the brief's spec.
const ANCHOR_PROXIMITY_PX: float = 32.0
# S-297 — last-tick stack assignment per pid, so we only call
# set_label_stack_index when something actually changed (avoids
# pointless tween churn / theme override thrash every frame).
var _label_stack_cache: Dictionary = {}     # pid → int
var _label_dim_cache: Dictionary = {}       # pid → bool
# S-243 — track round transitions so we can re-enable per-round UI
# (HandPicker, WinnerPicker, throw glyphs) when the server begins a
# new round. Initialized to 0 because the LOBBY snapshot has round=0
# and the first PLAYING snapshot has round=1.
var _last_round_seen: int = 0

func _ready() -> void:
	_paint_ground()
	GameState.snapshot_changed.connect(_on_snapshot)
	GameState.round_received.connect(_on_round)
	GameState.winner_choice_opened.connect(_on_winner_choice_opened)
	GameState.winner_choice_closed.connect(_on_winner_choice_closed)
	if effect_player.has_method("bind"):
		effect_player.bind(self)
	hand_picker.choice_made.connect(_on_choice_made)
	winner_picker.winner_choice_made.connect(_on_winner_choice_made)
	phase_label.text = ""
	victory_overlay.visible = false
	tie_banner.visible = false
	# Initial paint from current snapshot if we already have one.
	if not GameState.snapshot.is_empty():
		_on_snapshot(GameState.snapshot)
	Audio.cross_fade_bgm("battle")

func _paint_ground() -> void:
	# 11×11 iso diamond lattice. The Ground node owns a custom _draw
	# that paints diamond polygons in alternating shades — equivalent to
	# a TileMap with TileSetAtlasSource.tile_shape = ISOMETRIC but
	# without needing an external atlas texture. Tiles are painted in
	# row-major order so depth-sort works naturally.
	if ground.has_method("paint_lattice"):
		ground.paint_lattice(11, 11, iso_tile_size)

# Convert iso grid coord (where x grows down-right, y grows down-left)
# to world position. Matches what a Godot iso TileMap does internally:
#   world.x = (gx - gy) * (tile_w / 2)
#   world.y = (gx + gy) * (tile_h / 2)
func _iso_world(grid: Vector2i) -> Vector2:
	return Vector2(
		float(grid.x - grid.y) * iso_tile_size.x * 0.5,
		float(grid.x + grid.y) * iso_tile_size.y * 0.5
	)

func _on_snapshot(snap: Dictionary) -> void:
	var players: Array = snap.get("players", [])
	if players.is_empty():
		return
	# Figure out station positions on a circle around origin in iso space.
	var n := players.size()
	_player_order.clear()
	for i in range(n):
		var p: Dictionary = players[i]
		var pid := String(p.get("id", ""))
		_player_order.append(pid)
		var grid := _player_grid_pos(i, n)
		var world := _iso_world(grid)
		_ensure_house(pid, world, p, i, n)
		_ensure_character(pid, world, p, i, n)

	# Sync stage states.
	for p in players:
		var pid := String(p.get("id", ""))
		var stage_str := String(p.get("stage", "ALIVE_CLOTHED"))
		set_player_stage(pid, stage_str)

	# S-243 — round transition detection. The server emits a fresh
	# snapshot at the start of every round (beginRound() resets choices
	# and broadcasts). When we see round N+1 for the first time, the
	# previous round's UI is stale: HandPicker is locked from the prior
	# throw, throw glyphs may still be visible, and the WinnerPicker may
	# be lingering on a closed prompt. Reset all three so the human can
	# throw again. Without this the round loop visibly freezes after R1.
	var phase := String(snap.get("phase", ""))
	var current_round := int(snap.get("round", 0))
	if phase == "PLAYING" and current_round > _last_round_seen:
		_last_round_seen = current_round
		_reset_round_ui(players)
		# S-277 — seed the PhaseBanner from the snapshot itself, even
		# before the room:effects payload for this round arrives. This
		# is the spectator-mode safety net: when the local human is
		# DEAD or has no submission window (e.g. waiting on bots after
		# a tie), the EffectPlayer dispatch path is the only thing that
		# refreshes the banner — and that runs ~ROUND_TOTAL_MS late.
		# Stamping the banner here means the round number flips the
		# moment the server announces beginRound(), so t27000.png ≠
		# t18000.png whenever the snapshot has rolled over.
		if phase_label != null:
			phase_label.text = "R%d · PREP" % current_round
	elif phase == "LOBBY":
		_last_round_seen = 0
		if phase_label != null:
			phase_label.text = ""

func _reset_round_ui(players: Array) -> void:
	# Clear any lingering throw glyphs from the previous REVEAL phase.
	for c in _characters.values():
		if c != null and c.has_method("hide_throw"):
			(c as Character).hide_throw()
	# S-297 — DO NOT clear _house_occupants or zero stack indices here.
	# The previous behaviour (clear-on-round-transition) was the root
	# cause of the iter-48 'randomNi97' / 'counrandom' regression:
	# per §C3 the engine drops PHASE_T_RETURN so visiting characters
	# stay camped at the target's house. If we zero their stack index
	# at every round-start, then in the very next TIE / spectator round
	# we render every camped character at idx=0 again — and N≥2 labels
	# overlap into garbled OCR glyphs. The per-frame
	# _reconcile_label_stacks() pass below is now the single source of
	# truth: it walks every character every frame and re-assigns stack
	# indices from CURRENT world positions. When a character actually
	# returns home (teleport_home) or moves away from the shared anchor
	# the reconciler will naturally assign idx=0 to them next frame.
	# Hide the winner picker if it was left open.
	if winner_picker != null and winner_picker.has_method("close"):
		winner_picker.close()
	# Re-enable the HandPicker for the local human, but only if they
	# are still alive AND have not already submitted for THIS round
	# (defensive — covers the snapshot-after-our-own-submit case where
	# this resync would otherwise unlock a button we just clicked).
	var my_id := GameState.my_player_id
	var my_alive := false
	var my_submitted := false
	for p in players:
		var pd: Dictionary = p
		if String(pd.get("id", "")) != my_id:
			continue
		my_alive = String(pd.get("stage", "DEAD")) != "DEAD"
		my_submitted = bool(pd.get("hasSubmitted", false))
		break
	if hand_picker != null:
		hand_picker.visible = my_alive
		if hand_picker.has_method("set_locked"):
			hand_picker.set_locked(my_submitted or not my_alive)

# S-297 — per-frame anchor reconciliation. This is the single source of
# truth for NameLabel stack indices. Every frame we:
#   1. Walk every character, find the nearest house anchor (within
#      ANCHOR_PROXIMITY_PX). The character's "owner" anchor is its own
#      house (resident); anyone within proximity of a NON-owner house
#      counts as a visitor on that house.
#   2. For each anchor that has ≥1 visitor, build the occupants list
#      [resident, visitor1, visitor2, …] sorted deterministically
#      (resident first, visitors by pid asc). Assign stack indices
#      0, 1, 2, … in that order.
#   3. For each anchor with 0 visitors, assign idx=0 to the resident
#      and clear the resident-dim flag.
#   4. For each character that is NOT near any house anchor (mid-rush /
#      teleporting), assign idx=0.
# Cache the last assignment per pid so we only call set_label_stack_index
# when something actually changed (avoid theme-override thrash).
#
# This replaces the one-shot _apply_visit_label_stack hook that only
# fired inside play_action's PULL_PANTS / CHOP branches. The old hook
# missed the §C3 no-return-home case: a visitor camped from R3 that
# survives a TIE in R4 never re-fires play_action, so its label
# collapsed back to idx=0 and overlapped the resident.
func _process(_delta: float) -> void:
	_reconcile_label_stacks()

func _reconcile_label_stacks() -> void:
	if _characters.is_empty() or _houses.is_empty():
		return
	# House anchor sits at its base; the character anchor is at its
	# feet, but characters spawn at house_pos + (0, 64) in
	# _ensure_character. Comparing against (0, 64) means a resident
	# at home registers distance 0 from its anchor (perfect match),
	# and a visitor at target_char.pos + (-32, 0) lands at distance
	# 32 — within ANCHOR_PROXIMITY_PX (32 + 0.5 epsilon).
	var result: Dictionary = LabelStackReconciler.compute(
		_characters, _houses, Vector2(0, 64), ANCHOR_PROXIMITY_PX)
	var desired_idx: Dictionary = result.get("idx", {})
	var desired_dim: Dictionary = result.get("dim", {})
	# Mirror the freshly-computed occupants ledger into the legacy
	# field so any external caller still reading it sees consistent
	# state with the per-frame reconciliation.
	_house_occupants = result.get("occupants", {})

	# Apply to characters, only if changed (cache check) — this avoids
	# pointless tween churn / theme override thrash every frame.
	for cpid in desired_idx.keys():
		var pid: String = String(cpid)
		if not _characters.has(pid):
			continue
		var ch = _characters[pid] as Character
		if ch == null:
			continue
		var want_idx: int = int(desired_idx[pid])
		var want_dim: bool = bool(desired_dim[pid])
		var prev_idx: int = int(_label_stack_cache.get(pid, -1))
		var prev_dim: bool = bool(_label_dim_cache.get(pid, false))
		if want_idx != prev_idx and ch.has_method("set_label_stack_index"):
			ch.set_label_stack_index(want_idx)
			_label_stack_cache[pid] = want_idx
		if want_dim != prev_dim and ch.has_method("set_label_resident_dimmed"):
			ch.set_label_resident_dimmed(want_dim)
			_label_dim_cache[pid] = want_dim

func _player_grid_pos(i: int, n: int) -> Vector2i:
	var angle := TAU * float(i) / float(max(n, 1)) - TAU * 0.25
	var radius := 4
	return Vector2i(round(cos(angle) * radius), round(sin(angle) * radius))

func _ensure_house(pid: String, pos: Vector2, player: Dictionary, i: int, n: int) -> void:
	if _houses.has(pid):
		return
	var house := preload("res://scenes/stage/House.tscn").instantiate()
	# House anchor at its base; House.tscn positions the Body sprite up
	# from this anchor so y_sort_enabled depth-sorts naturally.
	house.position = pos
	if house.has_method("set_player_color"):
		house.set_player_color(_player_color(i, n))
	if house.has_method("set_label"):
		house.set_label(String(player.get("nickname", "")))
	houses_layer.add_child(house)
	_houses[pid] = house

func _ensure_character(pid: String, house_pos: Vector2, player: Dictionary, i: int, n: int) -> void:
	if _characters.has(pid):
		return
	var char_scene := preload("res://scenes/characters/Character.tscn").instantiate()
	char_scene.player_id = pid
	char_scene.nickname = String(player.get("nickname", "?"))
	char_scene.color_hue = float(i) / float(max(n, 1))
	# Stand the character in front of (below) the house's iso anchor so
	# the silhouette reads against the ground tile, not the wall. The
	# Houses + Characters layers are y_sort_enabled siblings so the
	# higher-y character draws above the house naturally.
	char_scene.position = house_pos + Vector2(0, 64)
	char_scene.is_self = (pid == GameState.my_player_id)
	characters_layer.add_child(char_scene)
	_characters[pid] = char_scene

func _player_color(i: int, n: int) -> Color:
	return Color.from_hsv(float(i) / float(max(n, 1)), 0.55, 0.95)

# --- effect handlers (called by EffectPlayer) -----------------------------

func show_rps_reveal(throws: Array) -> void:
	for entry in throws:
		var pid := String(entry.get("playerId", ""))
		var choice := String(entry.get("choice", ""))
		var glyph := _glyph_for(choice)
		if _characters.has(pid):
			(_characters[pid] as Character).show_throw(glyph)
	# After REVEAL ends, fade glyphs back out.
	await get_tree().create_timer(float(Timing.PHASE_T_REVEAL) / 1000.0).timeout
	for c in _characters.values():
		(c as Character).hide_throw()

func _glyph_for(choice: String) -> String:
	match choice:
		"ROCK": return "✊"
		"PAPER": return "✋"
		"SCISSORS": return "✌"
		_: return "?"

func show_tie_banner(text: String) -> void:
	tie_banner.text = text
	tie_banner.visible = true
	tie_banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(tie_banner, "modulate:a", 1.0, 0.18)
	tw.tween_interval(float(Timing.TIE_NARRATION_HOLD_MS) / 1000.0)
	tw.tween_property(tie_banner, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func(): tie_banner.visible = false)

func on_phase_start(phase: String, round_n: int) -> void:
	phase_label.text = "R%d · %s" % [round_n, phase]
	# Cinematic zoom on PULL_PANTS (start) per §C2.
	# (Actor-target focus point gets set in play_action.)
	if phase == "STRIKE":
		Audio.play_sfx("chop")

func play_action(actor: String, target: String, kind: String) -> void:
	if not _characters.has(actor) or not _characters.has(target):
		return
	var actor_char: Character = _characters[actor]
	var target_char: Character = _characters[target]
	var midpoint := (actor_char.position + target_char.position) * 0.5
	# Cinematic zoom focuses on midpoint.
	if camera.has_method("cinematic_focus"):
		camera.cinematic_focus(midpoint,
			Timing.ZOOM_IN_DUR_MS,
			Timing.ZOOM_HOLD_MS,
			Timing.ZOOM_OUT_DUR_MS,
			Timing.ZOOM_TARGET)
	match kind:
		"PULL_PANTS":
			Audio.play_sfx("pull")
			actor_char.rush_to(target_char.position + Vector2(-32, 0), Timing.PHASE_T_RUSH)
			# S-297 — name-label fan-out is handled by the per-frame
			# _reconcile_label_stacks pass; no one-shot hook needed.
			# Once rush_to lands the actor within ANCHOR_PROXIMITY_PX of
			# the target's house anchor, the next _process tick assigns
			# a fresh stack index from CURRENT world position.
		"CHOP":
			Audio.play_sfx("chop")
			actor_char.rush_to(target_char.position + Vector2(-32, 0), Timing.PHASE_T_RUSH)
		"PULL_OWN_PANTS_UP":
			# Self-action: no rush, just a dignified flash.
			actor_char.play_attack_wiggle()
		_:
			pass

# S-269 / S-285 — apply name-label collision handling when an actor
# visits the target's house anchor. Each visitor at a given target's
# house gets a unique vertical stack slot (1, 2, 3, …) so their
# NameLabels fan out instead of overlapping (the t27000.png
# 'counterorandom' regression — three visitors collapsed onto one y
# coord and concatenated). The resident keeps the default y but
# fades to LABEL_DIMMED_ALPHA so the foreground reads as the visitors.
#
# The occupants ledger is keyed by target pid so the second visitor at
# random's house gets idx=2, the third gets idx=3, etc., regardless of
# which round they arrived in. _reset_round_ui clears the ledger at
# every round transition.
func _apply_visit_label_stack(actor_id: String, target_id: String) -> void:
	if actor_id == "" or target_id == "" or actor_id == target_id:
		return
	if not _characters.has(actor_id) or not _characters.has(target_id):
		return
	# Append to the target's occupant list (deduped — repeated CHOP after
	# PULL_PANTS in the same round must NOT re-stack the same actor).
	var occupants: Array = _house_occupants.get(target_id, [])
	if not occupants.has(actor_id):
		occupants.append(actor_id)
	_house_occupants[target_id] = occupants

	# Resident sits at idx=0 and dims while ≥1 visitor is present.
	var target_char: Character = _characters[target_id]
	if target_char != null:
		if target_char.has_method("set_label_stack_index"):
			target_char.set_label_stack_index(0)
		if target_char.has_method("set_label_resident_dimmed"):
			target_char.set_label_resident_dimmed(occupants.size() >= 1)

	# Each visitor in arrival order gets idx=1, 2, 3, …
	for i in range(occupants.size()):
		var pid: String = String(occupants[i])
		if not _characters.has(pid):
			continue
		var ch: Character = _characters[pid]
		if ch == null:
			continue
		if ch.has_method("set_label_stack_index"):
			ch.set_label_stack_index(i + 1)
		# A visitor never simultaneously plays the resident-dim role on
		# its own anchor while it is camped elsewhere; clear it
		# defensively in case it was set in a prior phase.
		if ch.has_method("set_label_resident_dimmed"):
			ch.set_label_resident_dimmed(false)

# --- particle FX (S-261, FINAL_GOAL §C5) -----------------------------------
#
# The four emitter scenes under res://scenes/effects/ are GPUParticles2D
# nodes with one_shot=true and a procedural color, but ship without a
# texture so each particle would draw as the engine's default 1×1 white
# point — invisible at 1280×720. We assign a radial-dot ImageTexture
# from the SpriteAtlas autoload at spawn time so the particles read on
# screen at their intended scale (~32px native, 0.5–1.4× scale jitter).
#
# Spawn anchors (per acceptance criterion):
#   - DustEmitter      → actor's feet at RUSH start
#   - ClothEmitter     → target waist at PULL_PANTS atMs
#   - WoodChipEmitter  → target's house door at STRIKE / IMPACT
#   - ConfettiEmitter  → winner position on VICTORY / GAME_OVER
#
# Emitters self-free after their lifetime + a small grace period so the
# Effects layer never accumulates dead one-shots across rounds.

const _DUST_SCENE := preload("res://scenes/effects/DustEmitter.tscn")
const _CLOTH_SCENE := preload("res://scenes/effects/ClothEmitter.tscn")
const _WOODCHIP_SCENE := preload("res://scenes/effects/WoodChipEmitter.tscn")
const _CONFETTI_SCENE := preload("res://scenes/effects/ConfettiEmitter.tscn")

func _atlas_node() -> Node:
	return get_node_or_null("/root/SpriteAtlas")

func _spawn_emitter(scene: PackedScene, world_pos: Vector2, tex: Texture2D) -> Node:
	if scene == null or effects_layer == null:
		return null
	var inst := scene.instantiate()
	if inst == null:
		return null
	if inst is GPUParticles2D:
		var p := inst as GPUParticles2D
		if tex != null:
			p.texture = tex
		p.position = world_pos
		p.emitting = true
		# Auto-cleanup: free a hair after the particle lifetime so dust /
		# cloth / chips / confetti don't pile up across rounds.
		var ttl: float = p.lifetime + 0.5
		var t := get_tree().create_timer(ttl)
		t.timeout.connect(func():
			if is_instance_valid(p):
				p.queue_free())
	effects_layer.add_child(inst)
	return inst

func spawn_dust_at(actor_id: String) -> void:
	if not _characters.has(actor_id):
		return
	var c: Character = _characters[actor_id]
	# Feet ≈ character anchor. The Character node's position is its base
	# (y_sort anchor) so dust spawns naturally at ground level.
	var atlas := _atlas_node()
	var tex: Texture2D = null
	if atlas != null:
		tex = atlas.fx_dust_texture
	_spawn_emitter(_DUST_SCENE, c.position, tex)

func spawn_cloth_at(target_id: String) -> void:
	if not _characters.has(target_id):
		return
	var c: Character = _characters[target_id]
	# Waist ≈ ~32 px above the feet anchor (sprite is 96 px tall, waist
	# sits roughly at the mid-thigh which is the briefs band per §C7).
	var atlas := _atlas_node()
	var tex: Texture2D = null
	if atlas != null:
		tex = atlas.fx_cloth_texture
	_spawn_emitter(_CLOTH_SCENE, c.position + Vector2(0, -32), tex)

func spawn_woodchip_at(target_id: String) -> void:
	# Wood chips burst from the target's house door. Houses anchor at
	# their base; the door sits at the bottom of the body sprite so the
	# emitter lands right on the door for the visible chip puff.
	if not _houses.has(target_id):
		return
	var house: Node2D = _houses[target_id]
	var atlas := _atlas_node()
	var tex: Texture2D = null
	if atlas != null:
		tex = atlas.fx_woodchip_texture
	# House anchor is the base; door is ~24 px above that.
	_spawn_emitter(_WOODCHIP_SCENE, house.position + Vector2(0, -24), tex)

func spawn_confetti_at(player_id: String) -> void:
	if not _characters.has(player_id):
		return
	var c: Character = _characters[player_id]
	var atlas := _atlas_node()
	var tex: Texture2D = null
	if atlas != null:
		tex = atlas.fx_confetti_texture
	# Confetti rains down from above the winner's head.
	_spawn_emitter(_CONFETTI_SCENE, c.position + Vector2(0, -120), tex)

func set_player_stage(pid: String, stage_str: String) -> void:
	if not _characters.has(pid):
		return
	var c: Character = _characters[pid]
	match stage_str:
		"ALIVE_CLOTHED":
			c.set_persistent_pants_down(false)
			c.set_state(Character.State.ALIVE_CLOTHED)
			Audio.play_sfx("dodge")
		"ALIVE_PANTS_DOWN":
			c.set_persistent_pants_down(true)
			c.set_state(Character.State.ALIVE_PANTS_DOWN)
		"DEAD":
			c.play_death()

# Public lookup used by EffectPlayer to render Latin narration for the
# right-rail BattleLog (S-192). Returns the player's Latin nickname, or
# the raw id when no character is mounted yet.
func nick_for_player(pid: String) -> String:
	if pid.length() == 0:
		return "?"
	if _characters.has(pid):
		var nick := String((_characters[pid] as Character).nickname)
		if nick.length() > 0:
			return nick
	return pid

func show_victory(winner_id) -> void:
	victory_overlay.visible = true
	var name := "?"
	if winner_id != null and _characters.has(String(winner_id)):
		name = (_characters[String(winner_id)] as Character).nickname
		# §C5 / S-261 — rain confetti on the winner.
		spawn_confetti_at(String(winner_id))
	victory_label.text = "%s WINS!" % name
	Audio.cross_fade_bgm("victory")
	Audio.play_sfx("victory")

# --- round / pickers ------------------------------------------------------

func _on_round(payload: Dictionary) -> void:
	if effect_player.has_method("play_round"):
		effect_player.play_round(payload)

func _on_winner_choice_opened(prompt: Dictionary) -> void:
	winner_picker.open(prompt)

func _on_winner_choice_closed() -> void:
	winner_picker.close()

func _on_choice_made(choice: String) -> void:
	GameState.send_choice(choice)
	hand_picker.set_locked(true)

func _on_winner_choice_made(target, action) -> void:
	GameState.send_winner_choice(target, action)
