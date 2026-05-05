## smoke_handpicker_keybinds.gd — verifies the S-234 game-throw keybinds
## wire to the `choice_made` signal the same way the Buttons do.
##
## Background. In the live HTML5 build, headless chromium drivers
## (Playwright / chrome-devtools MCP) cannot reliably synthesize a
## click that the Godot Button.pressed signal accepts: the focus ring
## renders (mouse-over works) but `pressed` never fires. Without a
## human-throw path the live game freezes after Start because the
## server is waiting on an RPS submission that never arrives. We accept
## R / P / S key presses as equivalents for ROCK / PAPER / SCISSORS,
## and additionally expose window.xdyb_game_throw(kind) for callers
## that bypass canvas focus entirely (the canonical autopilot path).
##
## This test fakes InputEventKey objects and feeds them through the
## handler, asserting:
##   - 'R' → choice_made.emit("ROCK")
##   - 'P' → choice_made.emit("PAPER")
##   - 'S' → choice_made.emit("SCISSORS")
##   - When locked, no signal fires
##
## Run with:
##   godot --headless --path client --script res://tests/smoke_handpicker_keybinds.gd
##
## Exit codes:
##   0 = pass
##   1 = at least one assertion failed
extends SceneTree

func _init() -> void:
	var failures: Array[String] = []
	await process_frame

	var scene: PackedScene = load("res://scenes/ui/HandPicker.tscn")
	if scene == null:
		push_error("HandPicker.tscn failed to load")
		quit(1)
		return

	var picker: Node = scene.instantiate()
	root.add_child(picker)
	for i in range(5):
		await process_frame

	var captured: Array[String] = []
	picker.choice_made.connect(func(c): captured.append(String(c)))

	# 'R' → ROCK
	captured.clear()
	_send_key(picker, KEY_R)
	await process_frame
	if captured != ["ROCK"]:
		failures.append("'R' did not emit choice_made('ROCK'); got %s" % str(captured))

	# 'P' → PAPER
	captured.clear()
	_send_key(picker, KEY_P)
	await process_frame
	if captured != ["PAPER"]:
		failures.append("'P' did not emit choice_made('PAPER'); got %s" % str(captured))

	# 'S' → SCISSORS
	captured.clear()
	_send_key(picker, KEY_S)
	await process_frame
	if captured != ["SCISSORS"]:
		failures.append("'S' did not emit choice_made('SCISSORS'); got %s" % str(captured))

	# Locked → no emission.
	picker.set_locked(true)
	captured.clear()
	_send_key(picker, KEY_R)
	_send_key(picker, KEY_P)
	_send_key(picker, KEY_S)
	await process_frame
	if not captured.is_empty():
		failures.append("locked picker still emitted choices: %s" % str(captured))

	# Unlock and check the JS-bridge handler shape via direct call. JS
	# dispatch goes through _js_throw(args) where args is an Array (the
	# js shim wraps the kind string). The autoload guard short-circuits
	# the install path under a non-web build, so this is the only thing
	# we can exercise without a real browser.
	picker.set_locked(false)
	captured.clear()
	picker._js_throw(["ROCK"])
	picker._js_throw(["PAPER"])
	picker._js_throw(["SCISSORS"])
	await process_frame
	if captured != ["ROCK", "PAPER", "SCISSORS"]:
		failures.append("_js_throw(Array) did not emit the right sequence; got %s" % str(captured))

	# Bare-string fallback (defensive shape).
	captured.clear()
	picker._js_throw("ROCK")
	await process_frame
	if captured != ["ROCK"]:
		failures.append("_js_throw(String) did not emit ROCK; got %s" % str(captured))

	# Garbage kind → no emission.
	captured.clear()
	picker._js_throw(["GUN"])
	await process_frame
	if not captured.is_empty():
		failures.append("_js_throw('GUN') wrongly emitted: %s" % str(captured))

	if failures.is_empty():
		print("[smoke_handpicker_keybinds] PASS — R/P/S keybinds + xdyb_game_throw bridge dispatch correctly with lock gating.")
		quit(0)
	else:
		print("[smoke_handpicker_keybinds] FAIL:")
		for f in failures:
			print("  - %s" % f)
		quit(1)


func _send_key(picker: Node, keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.echo = false
	picker._input(ev)
