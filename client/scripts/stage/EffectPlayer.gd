# EffectPlayer.gd — consumes a server-side Effect[] and dispatches scene
# tree calls at the right times.
#
# Wire protocol — see shared/src/game/effects.ts. Per FINAL_GOAL §A4 / §B4
# the v3 Godot client and the v2 PixiJS client read the SAME Effect union;
# nothing about the schema is Godot-specific.
#
# Usage:
#   var ep := EffectPlayer.new()
#   ep.bind(stage)         # GameStage that owns characters/houses/camera/log
#   ep.play_round(payload) # payload from room:effects
#
# Each Effect carries `atMs` (offset from round t=0); we use a master
# Tween with tween_interval(...) gates so the choreography matches the
# server's timeline 1:1. Phases:
#   ROUND_START                 atMs=0
#   RPS_REVEAL                  atMs=0, durationMs=1500   (show every glyph)
#   RPS_RESOLVED / TIE_NARRATION
#   PHASE_START × 6 (REVEAL, PREP, RUSH, PULL_PANTS, STRIKE, IMPACT)
#   ACTION                      atMs=2400 (start of PULL_PANTS)
#   SET_STAGE                   varies
#   NARRATION                   varies
#   GAME_OVER                   end of last round

class_name EffectPlayer
extends Node

signal round_finished

var stage = null # GameStage (typed via duck-call to keep cyclic deps simple)
var _master: Tween = null

# S-261 — track the current round's action so PHASE_START dispatch can
# spawn the right particle FX without duplicating actor/target lookup
# logic. The server emits a single ACTION effect per round at PREP start;
# subsequent PHASE_START(RUSH) / PHASE_START(PULL_PANTS) /
# PHASE_START(STRIKE|IMPACT) all reference that same actor/target pair.
# Reset to "" each ROUND_START so a stale action from the previous round
# can never leak forward.
var _cur_actor: String = ""
var _cur_target: String = ""
var _cur_kind: String = ""

func bind(s) -> void:
	stage = s

func play_round(payload: Dictionary) -> void:
	if stage == null:
		push_warning("EffectPlayer.play_round called with no bound stage")
		return
	var effects: Array = payload.get("effects", [])
	var narration := String(payload.get("narration", ""))
	var is_game_over := bool(payload.get("isGameOver", false))
	var winner_id = payload.get("winnerId", null)

	if _master != null and _master.is_valid():
		_master.kill()
	_master = create_tween()

	# Bucket effects by atMs for scheduling.
	var sorted := effects.duplicate()
	sorted.sort_custom(func(a, b): return int(a.get("atMs", 0)) < int(b.get("atMs", 0)))
	var prev_at := 0
	for e in sorted:
		var at: int = int(e.get("atMs", 0))
		var delta: int = at - prev_at
		if delta > 0:
			_master.tween_interval(float(delta) / 1000.0)
		prev_at = at
		var captured: Dictionary = e
		_master.tween_callback(func(): _dispatch(captured))

	# Tail: emit round_finished after a small grace period.
	_master.tween_interval(0.05)
	_master.tween_callback(func():
		if is_game_over:
			stage.show_victory(winner_id)
		round_finished.emit())

func _dispatch(e: Dictionary) -> void:
	var t := String(e.get("type", ""))
	match t:
		"ROUND_START":
			# Wipe per-round action context so stale FX never leak forward.
			_cur_actor = ""
			_cur_target = ""
			_cur_kind = ""
			var rs_round := int(e.get("round", 0))
			# S-338 — Chinese-rhyme product, Chinese log. The English
			# 'Round %d - fight!' that this used to emit is the exact
			# stuff that contradicted FINAL_GOAL §C8 in iter-71's judge
			# screenshots ('Jia36 pulled down counter's pants' etc.).
			stage.battle_log.add_row(rs_round, "回合",
				"第 %d 回合，开打！" % rs_round, "")
			# S-277 — kick the PhaseBanner over to the new round IMMEDIATELY
			# even before any PHASE_START arrives. Tie-only rounds emit
			# zero PHASE_START effects, so without this seed the banner
			# stays frozen on the previous round's IMPACT label and the
			# spectator (dead-or-pants-down human) sees nothing change.
			# We set a "START" placeholder; subsequent PHASE_START effects
			# overwrite it within ~0–1500ms.
			if stage.has_method("on_phase_start"):
				stage.on_phase_start("START", rs_round)
			Audio.play_sfx("tap")
		"RPS_REVEAL":
			var throws: Array = e.get("throws", [])
			stage.show_rps_reveal(throws)
			Audio.play_sfx("reveal")
		"RPS_RESOLVED":
			var winners: Array = e.get("winners", [])
			var losers: Array = e.get("losers", [])
			# S-338 — log line in CN to match the rhyme product surface.
			stage.battle_log.add_row(int(e.get("round", 0)), "拳",
				"%d 胜 / %d 败" % [winners.size(), losers.size()], "")
		"TIE_NARRATION":
			# S-338 — surface the server's CN tie-variant text directly.
			# Server emits one of shared/narrative/lines.ts#tieVariants
			# ('风掠过门前，没人动手', '邻居探头："你们到底打不打？"', …)
			# in `text`; fall back to a plain '齐了！' if absent.
			var tie_round := int(e.get("round", 0))
			var tie_text := String(e.get("text", "齐了！"))
			stage.battle_log.add_row(tie_round, "平",
				tie_text, "平")
			stage.show_tie_banner("平")
			# S-277 — tie rounds emit zero PHASE_START effects, so the
			# only effect that touches phase semantics in the round is
			# this one. Stamp the PhaseBanner so a spectator sees the
			# round number advance (e.g. "R3 · TIE") instead of the
			# stale "R2 · IMPACT".
			if stage.has_method("on_phase_start"):
				stage.on_phase_start("TIE", tie_round)
		"PHASE_START":
			var phase := String(e.get("phase", ""))
			stage.on_phase_start(phase, int(e.get("round", 0)))
			# S-261 / §C5 — fire the appropriate one-shot particle burst
			# at the start of each visible action phase. The actor/target
			# pair came from the ACTION effect at PREP start, so by RUSH
			# (and later) we have everything we need.
			_spawn_phase_fx(phase)
		"ACTION":
			var actor := String(e.get("actor", ""))
			var target := String(e.get("target", ""))
			var kind := String(e.get("kind", ""))
			_cur_actor = actor
			_cur_target = target
			_cur_kind = kind
			stage.play_action(actor, target, kind)
		"SET_STAGE":
			var pid := String(e.get("target", ""))
			var pstage := String(e.get("stage", ""))
			stage.set_player_stage(pid, pstage)
		"NARRATION":
			# S-338 — surface the server's canonical CN narration verbatim.
			# Server emits one of shared/narrative/lines.ts templates:
			#   '{actor}一个箭步上前，扒下了{target}的裤衩'
			#   '{actor}手起刀落，一刀砍向{target}的家门'
			#   '{actor}蹲下身, 把裤衩捡回来穿好了'
			# These already substitute the actor/target nicknames, so the
			# client just renders them. The verb tag (扒/砍/闪/平/死/穿)
			# from the wire goes straight into the BattleLog badge —
			# VERB_COLORS still has the CN keys.
			var cn_verb := String(e.get("verb", ""))
			var server_text := String(e.get("text", ""))
			var line := server_text
			if line.length() == 0:
				# Defensive fallback if a server bug ever ships a NARRATION
				# without text. Compose a CN sentence from actor/target.
				var actor_nick := _nick_for(String(e.get("actor", "")))
				var target_nick := _nick_for(String(e.get("target", "")))
				line = _cn_fallback_narration(cn_verb, actor_nick, target_nick)
			stage.battle_log.add_row(int(e.get("round", 0)), "事",
				line, cn_verb)
		"GAME_OVER":
			stage.battle_log.add_row(int(e.get("round", 0)), "终",
				"游戏结束", "死")
		_:
			pass

# S-261 / §C5 — particle FX dispatch on PHASE_START.
#
# Phase choreography mapping:
#   RUSH        → DustEmitter at actor feet (kicks up dust on the sprint)
#   PULL_PANTS  → ClothEmitter at target waist (red briefs cloth burst)
#   STRIKE      → WoodChipEmitter at target's house door (knife wind-up
#                 chips fly already, IMPACT amplifies; firing at STRIKE
#                 makes the chip burst lead the impact frame visibly)
#   IMPACT      → WoodChipEmitter again at the door for the actual chop
#                 thud — stacking two bursts reads as a richer hit
#
# Self-actions (PULL_OWN_PANTS_UP) reuse cloth on the actor's own waist
# so the restorative gesture has visible feedback.
func _spawn_phase_fx(phase: String) -> void:
	if stage == null:
		return
	if _cur_actor.length() == 0 and _cur_target.length() == 0:
		return  # tie / no-op round; nothing to dispatch
	match phase:
		"RUSH":
			# Self-action has actor==target; dust at the actor still
			# reads as "winding up" so we don't suppress it.
			if _cur_actor.length() > 0 and stage.has_method("spawn_dust_at"):
				stage.spawn_dust_at(_cur_actor)
		"PULL_PANTS":
			# Cloth burst at target waist — for self-restore the target
			# is the actor themselves so the same call works.
			var who := _cur_target if _cur_target.length() > 0 else _cur_actor
			if stage.has_method("spawn_cloth_at"):
				stage.spawn_cloth_at(who)
		"STRIKE":
			# Wood chips lead the IMPACT frame so the hit reads as built
			# up. Only fire on CHOP-shaped actions (kind=CHOP / blank).
			if _cur_kind == "CHOP" or _cur_kind == "":
				if _cur_target.length() > 0 and stage.has_method("spawn_woodchip_at"):
					stage.spawn_woodchip_at(_cur_target)
		"IMPACT":
			if _cur_kind == "CHOP" or _cur_kind == "":
				if _cur_target.length() > 0 and stage.has_method("spawn_woodchip_at"):
					stage.spawn_woodchip_at(_cur_target)
		_:
			pass

# Look up a Latin nickname for a player id by asking the bound GameStage.
# Falls back to the raw id (or "?" if blank) so a missing/late player
# never produces an empty string in the rail.
func _nick_for(pid: String) -> String:
	if pid.length() == 0:
		return "?"
	if stage != null and stage.has_method("nick_for_player"):
		return String(stage.nick_for_player(pid))
	return pid

# S-338 — compose a CN narration line for the right-rail log when the
# server's NARRATION effect is missing its `text` field (defensive
# fallback only — the canonical path is server-emitted text from
# shared/narrative/lines.ts). Mirrors the shape of the canonical
# templates so a missing-text round still reads on-theme instead of
# falling through to a Latin debug string.
func _cn_fallback_narration(verb: String, actor_nick: String, target_nick: String) -> String:
	match verb:
		"扒": return "%s一个箭步上前，扒下了%s的裤衩" % [actor_nick, target_nick]
		"砍": return "%s手起刀落，一刀砍向%s的家门" % [actor_nick, target_nick]
		"闪": return "%s一个侧身，躲开了%s的刀锋" % [target_nick, actor_nick]
		"死": return "%s应声倒地，再没起来" % target_nick
		"穿": return "%s把裤衩穿了回去" % actor_nick
		"平": return "齐了！"
		_: return "%s → %s" % [actor_nick, target_nick]
