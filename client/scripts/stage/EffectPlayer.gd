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

func _dispatch(e: Dictionary) -> void:
	var t := String(e.get("type", ""))
	match t:
		"ROUND_START":
			stage.battle_log.add_row(int(e.get("round", 0)), "round", "round %d 开打" % int(e.get("round", 0)), "")
			Audio.play_sfx("tap")
		"RPS_REVEAL":
			var throws: Array = e.get("throws", [])
			stage.show_rps_reveal(throws)
			Audio.play_sfx("reveal")
		"RPS_RESOLVED":
			var winners: Array = e.get("winners", [])
			var losers: Array = e.get("losers", [])
			stage.battle_log.add_row(int(e.get("round", 0)), "rps",
				"%d 胜 %d 败" % [winners.size(), losers.size()], "")
		"TIE_NARRATION":
			stage.battle_log.add_row(int(e.get("round", 0)), "tie", String(e.get("text", "平局")), "平")
			stage.show_tie_banner(String(e.get("text", "平局")))
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
			stage.battle_log.add_row(int(e.get("round", 0)), "narr",
				String(e.get("text", "")), String(e.get("verb", "")))
		"GAME_OVER":
			stage.battle_log.add_row(int(e.get("round", 0)), "end",
				"游戏结束", "死")
		_:
			pass
