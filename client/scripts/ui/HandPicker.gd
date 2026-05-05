# HandPicker.gd — rock / paper / scissors row at bottom of Game scene.
#
# FINAL_GOAL §C9 / §H2: lets the local human player commit a throw. Lock
# state grays buttons after the first send to prevent re-submission within
# the same round.
#
# Keybinds + JS bridge (S-234): mirrors the §S-218 Lobby contract so the
# headless chromium driver can drive a real human throw. Without this,
# the live HTML5 build freezes after Start because the server is waiting
# on a human RPS submission that no canvas-clicked / canvas-keyboard
# event ever delivers (mouse-clicks under chrome-headless-shell don't
# always grant the canvas focus, and document-level keypresses never
# reach Godot's GUI input pipeline).
#
# Keys (when the picker is visible and unlocked):
#   R — ROCK
#   P — PAPER
#   S — SCISSORS
# Plus the matching JS callable, callable from the page console:
#   window.xdyb_game_throw('ROCK' | 'PAPER' | 'SCISSORS')
# A document-level JS keydown shim routes physical R/P/S key events to
# the bridge so Playwright's page.keyboard.press() works deterministically
# regardless of canvas focus state. The shim is idempotent — re-installing
# replaces prior state.

extends Control

signal choice_made(choice: String)

@onready var _rock: Button = $H/Rock
@onready var _paper: Button = $H/Paper
@onready var _scissors: Button = $H/Scissors

var _locked: bool = false

# Held callback refs — JavaScriptBridge.create_callback returns
# JavaScriptObjects that JS holds weak refs to; if Godot drops the
# Callable they get GC'd and silently no-op. Keep them alive for the
# HandPicker's lifetime.
var _js_throw_cb = null

func _ready() -> void:
	_rock.pressed.connect(func(): _emit("ROCK"))
	_paper.pressed.connect(func(): _emit("PAPER"))
	_scissors.pressed.connect(func(): _emit("SCISSORS"))
	_install_js_bridge()

func _exit_tree() -> void:
	_uninstall_js_bridge()

func set_locked(v: bool) -> void:
	_locked = v
	_rock.disabled = v
	_paper.disabled = v
	_scissors.disabled = v

func _emit(c: String) -> void:
	if _locked:
		return
	Audio.play_sfx("tap")
	choice_made.emit(c)

func _input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if _locked or not is_visible_in_tree():
		return
	# Skip when a LineEdit / TextEdit is currently focused so the user
	# can still type letters. Game scene has no text input today, but
	# this keeps the contract safe if one is added.
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and (focused is LineEdit or focused is TextEdit):
		return
	match ev.keycode:
		KEY_R:
			_emit("ROCK")
			get_viewport().set_input_as_handled()
		KEY_P:
			_emit("PAPER")
			get_viewport().set_input_as_handled()
		KEY_S:
			_emit("SCISSORS")
			get_viewport().set_input_as_handled()

# --- JS bridge -------------------------------------------------------------
#
# Web-only. Exposes window.xdyb_game_throw(kind) so headless chromium
# drivers can submit a throw without going through the canvas keyboard
# pipeline (gated on canvas focus + InputEventKey synthesis through
# Godot's web emscripten layer, unreliable under chrome-headless-shell
# + swiftshader).
#
# Mirrors the lock gating the buttons and keybinds apply, so an
# unauthorized JS call simply no-ops instead of producing a server-side
# error.
func _install_js_bridge() -> void:
	if not (OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge")):
		return
	_js_throw_cb = JavaScriptBridge.create_callback(_js_throw)
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		return
	window.xdyb_game_throw = _js_throw_cb
	# Eval a small JS shim that ALSO listens to document-level keydowns
	# and routes R / P / S to the bridge. This unblocks Playwright's
	# page.keyboard.press() — those events land on document.body, not
	# on the Godot canvas, so the GDScript _input handler never sees
	# them. The shim is idempotent: re-installing replaces prior state.
	JavaScriptBridge.eval("""
		(function () {
			if (window.__xdyb_game_keys_installed) {
				document.removeEventListener('keydown', window.__xdyb_game_keys_installed, true);
			}
			function onKey(ev) {
				if (ev.repeat) return;
				if (ev.target && (ev.target.tagName === 'INPUT' || ev.target.tagName === 'TEXTAREA')) return;
				var k = (ev.key || '').toLowerCase();
				if (typeof window.xdyb_game_throw !== 'function') return;
				if (k === 'r') {
					window.xdyb_game_throw('ROCK'); ev.preventDefault();
				} else if (k === 'p') {
					window.xdyb_game_throw('PAPER'); ev.preventDefault();
				} else if (k === 's') {
					window.xdyb_game_throw('SCISSORS'); ev.preventDefault();
				}
			}
			document.addEventListener('keydown', onKey, true);
			window.__xdyb_game_keys_installed = onKey;
		})();
	""", true)

func _uninstall_js_bridge() -> void:
	if not (OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge")):
		return
	JavaScriptBridge.eval("""
		(function () {
			if (window.__xdyb_game_keys_installed) {
				document.removeEventListener('keydown', window.__xdyb_game_keys_installed, true);
				window.__xdyb_game_keys_installed = null;
			}
			window.xdyb_game_throw = null;
		})();
	""", true)
	_js_throw_cb = null

func _js_throw(args) -> void:
	if _locked:
		return
	# args is a JavaScript Array (proxied as Godot Array) — first arg is
	# the throw kind. Defensive coding: accept either an Array (from the
	# bridge) or a raw string (defensive for callers that mis-wrap).
	var raw: Variant = args
	if typeof(args) == TYPE_ARRAY and (args as Array).size() > 0:
		raw = (args as Array)[0]
	var kind := String(raw).to_upper()
	if kind != "ROCK" and kind != "PAPER" and kind != "SCISSORS":
		return
	_emit(kind)
