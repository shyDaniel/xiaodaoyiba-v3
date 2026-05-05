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

const _BattleLog := preload("res://scripts/ui/BattleLog.gd")

func _dispatch(e: Dictionary) -> void:
	var t := String(e.get("type", ""))
	match t:
		"ROUND_START":
			# Wipe per-round action context so stale FX never leak forward.
			_cur_actor = ""
			_cur_target = ""
			_cur_kind = ""
			stage.battle_log.add_row(int(e.get("round", 0)), "round",
				"Round %d - fight!" % int(e.get("round", 0)), "")
			Audio.play_sfx("tap")
		"RPS_REVEAL":
			var throws: Array = e.get("throws", [])
			stage.show_rps_reveal(throws)
			Audio.play_sfx("reveal")
		"RPS_RESOLVED":
			var winners: Array = e.get("winners", [])
			var losers: Array = e.get("losers", [])
			stage.battle_log.add_row(int(e.get("round", 0)), "rps",
				"%d win / %d lose" % [winners.size(), losers.size()], "")
		"TIE_NARRATION":
			# Server text is CN; render a Latin tie line in the live build
			# so the log stays legible without a CJK system font (S-192).
			stage.battle_log.add_row(int(e.get("round", 0)), "tie",
				"Standoff - nobody moved", "TIE")
			stage.show_tie_banner("TIE")
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
			# Shared/server narration text is CN; reconstruct a Latin
			# sentence on the client from {actor, target, verb} so the
			# log stays legible without a CJK system font (S-192). The
			# verb tag itself is also translated CN -> Latin for the badge.
			var cn_verb := String(e.get("verb", ""))
			var latin_verb := String(_BattleLog.CN_TO_LATIN_VERB.get(cn_verb, cn_verb))
			var actor_nick := _nick_for(String(e.get("actor", "")))
			var target_nick := _nick_for(String(e.get("target", "")))
			var line := _latin_narration(latin_verb, actor_nick, target_nick)
			stage.battle_log.add_row(int(e.get("round", 0)), "narr",
				line, latin_verb)
		"GAME_OVER":
			stage.battle_log.add_row(int(e.get("round", 0)), "end",
				"Game over", "DEAD")
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

# Compose a Latin narration sentence for the right-rail log from a Latin
# verb tag and the actor/target nicknames. Mirrors the shape of the
# shared/narrative/lines.ts CN templates so a HN reader sees the same
# beats (PULL pants, CHOP door, RESTORE pants).
func _latin_narration(verb: String, actor_nick: String, target_nick: String) -> String:
	match verb:
		"PULL": return "%s pulled down %s's pants" % [actor_nick, target_nick]
		"CHOP": return "%s chopped %s's door" % [actor_nick, target_nick]
		"DODGE": return "%s dodged %s's swing" % [target_nick, actor_nick]
		"DEAD": return "%s went down" % target_nick
		"RESTORE": return "%s pulled their pants back up" % actor_nick
		"TIE": return "Standoff - nobody moved"
		_: return "%s -> %s" % [actor_nick, target_nick]
