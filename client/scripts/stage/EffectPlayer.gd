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
		"ACTION":
			var actor := String(e.get("actor", ""))
			var target := String(e.get("target", ""))
			var kind := String(e.get("kind", ""))
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
