## smoke_spectator_phase_banner.gd — verifies S-277 spectator-mode
## PhaseBanner refresh, both via the EffectPlayer.ROUND_START /
## TIE_NARRATION dispatch path AND via the GameStage._on_snapshot
## round-rollover path.
##
## Background. With the local human in DEAD or ALIVE_PANTS_DOWN at
## the end of round N, the server still emits beginRound() and a
## room:snapshot with round=N+1 — and, for non-tie rounds, a full
## room:effects payload with PHASE_START × 6. The pre-S-277 client
## only updated phase_label.text on PHASE_START effects, which meant:
##   1. Tie rounds (zero PHASE_START effects) left the banner stuck on
##      the previous round's "R2 · IMPACT".
##   2. Even non-tie rounds didn't update the banner until the
##      EffectPlayer dispatch had walked atMs=0 callbacks (~80–200ms
##      from receipt), and any frame sampled in that gap looked frozen.
## Result: validate-game-progression's t18000 / t22000 / t27000 frames
## were byte-equal because the visible banner never moved.
##
## This test instantiates GameStage.tscn (the full live scene tree)
## and feeds it three things in sequence:
##   (1) An initial snapshot with phase=PLAYING round=2 to seed the
##       round counter to a non-zero baseline.
##   (2) A ROUND_START / PHASE_START(IMPACT) effect pair so the banner
##       lands at "R2 · IMPACT" (the post-S-269 baseline state).
##   (3) A snapshot with round=3 (the spectator-mode "begin next
##       round" message); banner must immediately read "R3 · ..." NOT
##       "R2 · IMPACT".
##   (4) A pure-tie effects payload for round 3 (ROUND_START +
##       RPS_REVEAL + TIE_NARRATION); banner must read "R3 · TIE"
##       (or any text containing "R3").
##
## Run with:
##   godot --headless --path client --script res://tests/smoke_spectator_phase_banner.gd
##
## Exit codes:
##   0 = pass
##   1 = at least one assertion failed
extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	await process_frame
	await process_frame

	var gs_node: Node = root.get_node_or_null("GameState")
	if gs_node == null:
		push_error("GameState autoload not found at /root/GameState")
		quit(1)
		return
	# Reset GameState — the autoload may have been touched by an
	# earlier test in the same headless invocation.
	gs_node.snapshot = {}
	gs_node.rounds = []
	gs_node.winner_choice = null
	gs_node.my_player_id = "p-mei"

	var game_scene: PackedScene = load("res://scenes/Game.tscn")
	if game_scene == null:
		push_error("Game.tscn failed to load")
		quit(1)
		return
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	for i in range(5):
		await process_frame

	# GameStage is the root node of Game.tscn.
	var stage: Node = game
	if not stage.has_method("on_phase_start"):
		# Game.tscn's root may be a parent that holds the stage as its
		# only child — try to descend.
		stage = game.get_child(0)
	if stage == null or not stage.has_method("on_phase_start"):
		push_error("Could not locate GameStage with on_phase_start; root=%s" % str(game))
		quit(1)
		return

	var phase_label: Label = stage.phase_label
	if phase_label == null:
		failures.append("phase_label is null on stage")

	# (1) Seed snapshot at round=2 PLAYING with two players (one human,
	# one bot). _on_snapshot is the live signal handler; we call it
	# directly with the same shape GameState would emit.
	var snap_r2 := {
		"roomId": "TEST",
		"hostId": "p-mei",
		"phase": "PLAYING",
		"round": 2,
		"players": [
			{"id": "p-mei", "nickname": "Mei74", "isBot": false,
				"stage": "ALIVE_PANTS_DOWN", "isHost": true,
				"hasSubmitted": false, "joinOrder": 0},
			{"id": "p-bot", "nickname": "counter", "isBot": true,
				"stage": "ALIVE_PANTS_DOWN", "isHost": false,
				"hasSubmitted": true, "joinOrder": 1},
			{"id": "p-bot2", "nickname": "random", "isBot": true,
				"stage": "ALIVE_CLOTHED", "isHost": false,
				"hasSubmitted": true, "joinOrder": 2},
		],
	}
	stage._on_snapshot(snap_r2)
	await process_frame
	await process_frame

	# After the seed snapshot, the banner should land at "R2 · PREP"
	# because the round rolled over from 0 → 2.
	if phase_label != null and phase_label.text.find("R2") < 0:
		failures.append("after R2 seed snapshot, banner=%s expected to contain R2" % phase_label.text)

	# (2) Drive an IMPACT phase so the banner reads "R2 · IMPACT".
	stage.on_phase_start("IMPACT", 2)
	await process_frame
	if phase_label != null and phase_label.text != "R2 · IMPACT":
		failures.append("after on_phase_start(IMPACT,2), banner=%s expected R2 · IMPACT" % phase_label.text)

	# (3) Spectator-mode round rollover: the server announces R3 via a
	# snapshot. The banner must NOT stay on "R2 · IMPACT".
	var snap_r3 := snap_r2.duplicate(true)
	snap_r3["round"] = 3
	stage._on_snapshot(snap_r3)
	await process_frame
	await process_frame
	if phase_label != null and phase_label.text.find("R3") < 0:
		failures.append("after R3 snapshot rollover, banner=%s expected to contain R3 (NOT stuck on R2)"
			% phase_label.text)
	if phase_label != null and phase_label.text.find("R2") >= 0:
		failures.append("after R3 snapshot rollover, banner still mentions R2: %s" % phase_label.text)

	# (4) Pure-tie effect payload for R3 — feed it to the
	# EffectPlayer (which tween_callback's into _dispatch). Build the
	# minimal payload shape the live server emits for an all-equal tie.
	var ep: Node = stage.effect_player
	if ep == null or not ep.has_method("play_round"):
		failures.append("effect_player not bound or missing play_round")
	else:
		# We bypass the master Tween scheduling and call _dispatch
		# directly so the assertion is deterministic frame-wise. The
		# Tween path is exercised by the existing render_game smoke.
		ep._dispatch({"type": "ROUND_START", "round": 3, "atMs": 0})
		ep._dispatch({
			"type": "TIE_NARRATION",
			"round": 3,
			"atMs": 0,
			"durationMs": 2000,
			"text": "All tied",
			"rpsReason": "all-equal",
		})
		await process_frame
		if phase_label != null and phase_label.text.find("R3") < 0:
			failures.append("after TIE_NARRATION R3, banner=%s expected to contain R3"
				% phase_label.text)

	# (5) Spectator R4 — second consecutive round rollover via
	# snapshot, simulating the validate-game-progression t27000 frame.
	var snap_r4 := snap_r2.duplicate(true)
	snap_r4["round"] = 4
	stage._on_snapshot(snap_r4)
	await process_frame
	if phase_label != null and (phase_label.text.find("R4") < 0):
		failures.append("after R4 snapshot rollover, banner=%s expected to contain R4"
			% phase_label.text)

	if failures.is_empty():
		print("[smoke_spectator_phase_banner] PASS — PhaseBanner refreshes on snapshot rollover and tie rounds.")
		quit(0)
	else:
		print("[smoke_spectator_phase_banner] FAIL:")
		for f in failures:
			print("  - %s" % f)
		quit(1)
