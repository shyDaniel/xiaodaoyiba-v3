## render_landing_hero.gd — substring contract on the landing-hero
## right-rail BattleLog (S-367). Walks every Label inside the
## instantiated Landing.tscn and hard-fails if any pre-localization
## English copy ("BattleLog", "R1.PREP"/.../"R1.RESULT", "PRP "/...
## /"RES ", "Ming preps", "Rock Paper Scissors", "Pull Hong",
## "pants down") still leaks through.
##
## Why a separate test from render_landing.gd:
##   render_landing.gd guards the Landing's title couplet, buttons,
##   and connection status (the v3 §C0 surfaces). The hero panel's
##   embedded BattleLog is a SEPARATE first-impression surface that
##   render_landing.gd never inspected — its forbidden-substring set
##   is also disjoint (PRP/RVL/ACT/RES badges, R1.PREP-style tags,
##   nursery-rhyme English narration). Splitting keeps each test
##   focused and the failure messages legible.
##
## Run:
##   godot --headless --path client --script res://tests/render_landing_hero.gd
extends SceneTree

func _walk(n: Node, out: Array) -> void:
	if n is Label:
		out.append({"kind": "Label", "path": str(n.get_path()), "text": (n as Label).text})
	elif n is Button:
		out.append({"kind": "Button", "path": str(n.get_path()), "text": (n as Button).text})
	for c in n.get_children():
		_walk(c, out)

func _init() -> void:
	await process_frame
	# SpriteAtlas autoload must be ready before LandingHero builds its
	# children, otherwise the Hero falls back to a "(SpriteAtlas missing)"
	# placeholder Label that is itself ASCII and would false-positive
	# the substring contract below.
	var sa := root.get_node_or_null("SpriteAtlas")
	if sa == null:
		push_error("[render_landing_hero] SpriteAtlas autoload missing")
		quit(2)
		return
	await process_frame
	var scene: PackedScene = load("res://scenes/Landing.tscn")
	var landing: Node = scene.instantiate()
	root.add_child(landing)
	# LandingHero defers child build by one process_frame; give it a
	# few frames to settle.
	for i in range(8):
		await process_frame

	var hero: Node = landing.get_node_or_null("IsoPreview")
	if hero == null:
		push_error("[render_landing_hero] FAIL: IsoPreview missing from Landing.tscn")
		quit(3)
		return

	var out: Array = []
	_walk(hero, out)
	for row in out:
		print("[render_landing_hero] ", row)

	# Hard-fail substrings — the brief's exact list. Must NOT appear
	# in any Label.text inside the LandingHero subtree.
	var forbidden := [
		"BattleLog",
		"R1.PREP",
		"R1.REVEAL",
		"R1.ACTION",
		"R1.RESULT",
		"PRP ",
		"RVL ",
		"ACT ",
		"RES ",
		"Ming preps",
		"Rock Paper Scissors",
		"Pull Hong",
		"pants down",
	]
	var leaks: Array = []
	for row in out:
		var text: String = row.get("text", "")
		for needle in forbidden:
			if text.find(needle) != -1:
				leaks.append({"needle": needle, "row": row})
	if leaks.size() > 0:
		print("[render_landing_hero] FAIL leaks=", leaks)
		quit(1)
		return

	# Positive contract — the localized header MUST appear, and at
	# least one CJK verb badge from the canonical palette MUST be
	# present. Catches a degenerate "removed everything but added
	# nothing back" regression.
	var saw_header := false
	var saw_badge := false
	var saw_round_tag := false
	var palette := ["平", "拳", "扒", "砍", "穿", "死"]
	for row in out:
		var text: String = row.get("text", "")
		if text == "战报":
			saw_header = true
		if text.find("回合") != -1 or text.find("R1.准备") != -1 or \
				text.find("R1.亮拳") != -1 or text.find("R1.动作") != -1 or \
				text.find("R1.结果") != -1:
			saw_round_tag = true
		for g in palette:
			if text == g:
				saw_badge = true
	if not saw_header:
		print("[render_landing_hero] FAIL: header '战报' not found")
		quit(4)
		return
	if not saw_round_tag:
		print("[render_landing_hero] FAIL: no localized round-phase tag found")
		quit(5)
		return
	if not saw_badge:
		print("[render_landing_hero] FAIL: no canonical CJK verb badge ({平/拳/扒/砍/穿/死}) found")
		quit(6)
		return

	print("[render_landing_hero] PASS — landing-hero BattleLog reads in CJK")
	quit(0)
