# Lobby.gd — pre-game room screen.
#
# Shows:
#   - the room code (so other humans can join)
#   - the current member list (humans + bots)
#   - host-only controls: Add Bot / Start
#   - leave button
#
# All visible strings are Latin so the live HTML5 build stays legible
# without a CJK system font (S-192).
#
# Keybinds (S-205): the live HTML5 build sometimes loses synthetic mouse
# clicks against Godot Buttons when driven by headless chromium —
# Playwright's mouse.down/up reaches the canvas but the engine's
# focus-grab + Button.pressed pipeline can swallow the event. To make
# the lobby reachable from headless drivers (and incidentally to give
# keyboard users a fast path), we accept:
#   A — add bot   (host-only, same gating as the button)
#   S — start     (host-only, requires ≥ 2 players)
#   L — leave
# These are wired in _input (S-218: previously _unhandled_key_input)
# so they fire BEFORE the focused Button consumes them — under WASM
# canvas focus, KEY_A pressed while the AddBot button is focused was
# being interpreted as a button-shortcut probe and swallowed.
#
# JS bridge (S-218): pure-keyboard dispatch is fragile under headless
# chromium because page.keyboard.press() targets the document's active
# element, which isn't the Godot canvas unless we explicitly
# focus()'d it (and synthetic mouse-clicks don't always grant focus
# under chrome-headless-shell + swiftshader). We additionally expose
# window.xdyb_lobby_addBot() / start() / leave() via JavaScriptBridge
# so external drivers can dispatch lobby actions deterministically
# regardless of canvas focus state. This is the canonical autopilot
# path now — see scripts/validate-browser.sh's lobby-keybind variant.

extends Control

@onready var _code_label: Label = $Card/V/Code
@onready var _members: VBoxContainer = $Card/V/Members/List
@onready var _add_bot: Button = $Card/V/Buttons/AddBot
@onready var _start: Button = $Card/V/Buttons/Start
@onready var _leave: Button = $Card/V/Buttons/Leave

# Cached host/member state so the keybind handler can apply the same
# gating the buttons use without re-reading the snapshot every key.
var _is_host: bool = false
var _player_count: int = 0

# Held references — JavaScriptBridge.create_callback() returns
# JavaScriptObjects that JS holds weak refs to; if Godot drops the
# Callable they get GC'd and silently no-op. Keep them alive for the
# Lobby's lifetime. (S-218)
var _js_addbot_cb = null
var _js_start_cb = null
var _js_leave_cb = null

func _ready() -> void:
	_add_bot.pressed.connect(GameState.add_bot)
	_start.pressed.connect(GameState.start_game)
	_leave.pressed.connect(GameState.leave_room)
	GameState.snapshot_changed.connect(_render)
	_render(GameState.snapshot)
	_install_js_bridge()

func _exit_tree() -> void:
	_uninstall_js_bridge()

func _input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	# Only act while the Lobby is actually visible. Main swaps scenes by
	# visibility, so a hidden lobby's keybinds shouldn't fire.
	if not is_visible_in_tree():
		return
	# Skip when a LineEdit / TextEdit is currently focused so the user
	# can still type letters. The Lobby has no text input today, but
	# this keeps the contract safe if one is added.
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and (focused is LineEdit or focused is TextEdit):
		return
	match ev.keycode:
		KEY_A:
			if _is_host:
				GameState.add_bot()
				get_viewport().set_input_as_handled()
		KEY_S:
			if _is_host and _player_count >= 2:
				GameState.start_game()
				get_viewport().set_input_as_handled()
		KEY_L:
			GameState.leave_room()
			get_viewport().set_input_as_handled()

# --- JS bridge -------------------------------------------------------------
#
# Web-only. Exposes window.xdyb_lobby_addBot() / start() / leave() so
# headless chromium drivers can trigger lobby actions without going
# through the canvas keyboard pipeline (which is gated on canvas
# focus + InputEventKey synthesis through Godot's web emscripten layer
# and is unreliable under chrome-headless-shell + swiftshader).
#
# We mirror the same host / player-count gating the buttons and
# keybinds apply, so an unauthorized JS call simply no-ops instead of
# producing a server-side error.
func _install_js_bridge() -> void:
	if not (OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge")):
		return
	_js_addbot_cb = JavaScriptBridge.create_callback(_js_addbot)
	_js_start_cb = JavaScriptBridge.create_callback(_js_start)
	_js_leave_cb = JavaScriptBridge.create_callback(_js_leave)
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		return
	window.xdyb_lobby_addBot = _js_addbot_cb
	window.xdyb_lobby_start = _js_start_cb
	window.xdyb_lobby_leave = _js_leave_cb
	# Eval a small JS shim that ALSO listens to document-level keydowns
	# and routes A / S / L to the bridge. This unblocks Playwright's
	# page.keyboard.press() — those events land on document.body, not
	# on the Godot canvas, so the GDScript _input handler never sees
	# them. The shim is idempotent: re-installing replaces prior state.
	JavaScriptBridge.eval("""
		(function () {
			if (window.__xdyb_lobby_keys_installed) {
				document.removeEventListener('keydown', window.__xdyb_lobby_keys_installed, true);
			}
			function onKey(ev) {
				if (ev.repeat) return;
				if (ev.target && (ev.target.tagName === 'INPUT' || ev.target.tagName === 'TEXTAREA')) return;
				var k = (ev.key || '').toLowerCase();
				if (k === 'a' && typeof window.xdyb_lobby_addBot === 'function') {
					window.xdyb_lobby_addBot(); ev.preventDefault();
				} else if (k === 's' && typeof window.xdyb_lobby_start === 'function') {
					window.xdyb_lobby_start(); ev.preventDefault();
				} else if (k === 'l' && typeof window.xdyb_lobby_leave === 'function') {
					window.xdyb_lobby_leave(); ev.preventDefault();
				}
			}
			document.addEventListener('keydown', onKey, true);
			window.__xdyb_lobby_keys_installed = onKey;
		})();
	""", true)

func _uninstall_js_bridge() -> void:
	if not (OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge")):
		return
	JavaScriptBridge.eval("""
		(function () {
			if (window.__xdyb_lobby_keys_installed) {
				document.removeEventListener('keydown', window.__xdyb_lobby_keys_installed, true);
				window.__xdyb_lobby_keys_installed = null;
			}
			window.xdyb_lobby_addBot = null;
			window.xdyb_lobby_start = null;
			window.xdyb_lobby_leave = null;
		})();
	""", true)
	_js_addbot_cb = null
	_js_start_cb = null
	_js_leave_cb = null

func _js_addbot(_args) -> void:
	if _is_host:
		GameState.add_bot()

func _js_start(_args) -> void:
	if _is_host and _player_count >= 2:
		GameState.start_game()

func _js_leave(_args) -> void:
	GameState.leave_room()

func _render(snap: Dictionary) -> void:
	_code_label.text = "Room %s" % GameState.room_code
	for c in _members.get_children():
		c.queue_free()
	var players: Array = snap.get("players", [])
	var n := players.size()
	for i in range(n):
		var p: Dictionary = players[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(20, 20)
		swatch.color = Color.from_hsv(float(i) / float(max(n, 1)), 0.55, 0.95)
		row.add_child(swatch)
		var name := Label.new()
		var tag := " (bot)" if bool(p.get("isBot", false)) else ""
		var host_marker := " ★" if bool(p.get("isHost", false)) else ""
		name.text = "%s%s%s" % [p.get("nickname", "?"), tag, host_marker]
		name.add_theme_font_size_override("font_size", 18)
		row.add_child(name)
		_members.add_child(row)
	# Host gates: only the host can add bots / start the game. Server
	# enforces, but we hide the buttons for clarity.
	#
	# S-218: prefer the snapshot's `youAreHost` if the server emits it
	# (forward-compat), but the actual TS server only sends a
	# room-broadcast snapshot without per-socket fields. Derive locally
	# from hostId == GameState.my_player_id, which we capture on
	# room:created / room:joined. The smoke_lobby_keybinds test stuffs
	# `youAreHost: true` directly so the legacy path stays covered.
	var is_host := bool(snap.get("youAreHost", false))
	if not is_host:
		var host_id := str(snap.get("hostId", ""))
		var me := GameState.my_player_id
		if host_id.length() > 0 and me.length() > 0 and host_id == me:
			is_host = true
	_add_bot.disabled = not is_host
	_start.disabled = not is_host or n < 2
	# Cache for the keybind handler so it can apply the same gating
	# without re-reading the snapshot.
	_is_host = is_host
	_player_count = n
