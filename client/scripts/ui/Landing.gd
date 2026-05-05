# Landing.gd — title screen, nickname entry, create-room / join-room.
#
# FINAL_GOAL §title: the game's CN name is 小刀一把冲到你家 ("knife to your
# door"). Visible UI strings are CJK to match the in-game scene and the
# nursery-rhyme brand (S-350). NotoSansSC is bundled globally as the
# project's default font (project.godot[gui]theme/custom_font), so the
# HTML5 build always has glyph data for 小刀/裤衩/咔嚓 even on browsers
# without a system CJK fallback (S-332 fixed the missing-glyph tofu that
# blocked S-192). The hero illustration is procedural (knife + house +
# character silhouette) so the project ships without uploaded art per §G.

extends Control

@onready var _nick_input: LineEdit = $V/Nick
@onready var _code_input: LineEdit = $V/JoinRow/Code
@onready var _create_btn: Button = $V/CreateRow/Create
@onready var _join_btn: Button = $V/JoinRow/Join
@onready var _status: Label = $V/Status
@onready var _server_input: LineEdit = $V/ServerRow/Server

# Held callback refs — JavaScriptBridge.create_callback returns
# JavaScriptObjects that JS holds weak refs to; if Godot drops the
# Callable they get GC'd. Keep them alive for the Landing's lifetime.
# (S-218: parallels the Lobby bridge so headless drivers can drive
# Create Room / Join Room without canvas-coord guessing.)
var _js_create_cb = null
var _js_join_cb = null
var _js_setnick_cb = null

func _ready() -> void:
	_nick_input.text = _gen_nick()
	_create_btn.pressed.connect(_on_create)
	_join_btn.pressed.connect(_on_join)
	GameState.error_changed.connect(_on_error)
	GameState.connection_status_changed.connect(_on_status)
	# Default server URL hint visible in the UI.
	_server_input.placeholder_text = "默认 ws://localhost:3000"
	_status.text = "未连接 — 填昵称后点 开个房 或 进房间"
	Audio.cross_fade_bgm("lobby")
	_install_js_bridge()

func _exit_tree() -> void:
	_uninstall_js_bridge()

# --- JS bridge (S-218) -----------------------------------------------------
#
# Web-only. Exposes window.xdyb_landing_create({nickname?})  /
# xdyb_landing_join({code, nickname?}) / xdyb_landing_setNick(name)
# so headless chromium drivers can drive the title screen without
# guessing canvas-pixel coordinates for the Create/Join buttons.
func _install_js_bridge() -> void:
	if not (OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge")):
		return
	_js_create_cb = JavaScriptBridge.create_callback(_js_create)
	_js_join_cb = JavaScriptBridge.create_callback(_js_join)
	_js_setnick_cb = JavaScriptBridge.create_callback(_js_setnick)
	var window = JavaScriptBridge.get_interface("window")
	if window == null:
		return
	window.xdyb_landing_create = _js_create_cb
	window.xdyb_landing_join = _js_join_cb
	window.xdyb_landing_setNick = _js_setnick_cb

func _uninstall_js_bridge() -> void:
	if not (OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge")):
		return
	JavaScriptBridge.eval("""
		(function () {
			window.xdyb_landing_create = null;
			window.xdyb_landing_join = null;
			window.xdyb_landing_setNick = null;
		})();
	""", true)
	_js_create_cb = null
	_js_join_cb = null
	_js_setnick_cb = null

func _js_create(_args) -> void:
	# Use the already-populated _nick_input.text (procedural _gen_nick
	# always produces a non-empty string in _ready). Drivers that want
	# a specific nickname can call xdyb_landing_setNick("Foo") first.
	_on_create()

func _js_join(_args) -> void:
	# Drivers must call xdyb_landing_setNick / set the room code via
	# DOM-injected text first OR use this only when the inputs are
	# already populated. Keeping this thin avoids JavaScriptObject ↔
	# Godot type-coercion edge cases that have bitten previous web
	# bridges.
	_on_join()

func _js_setnick(args) -> void:
	# JavaScript primitives are coerced into native Godot types per
	# the JavaScriptBridge docs; arr[0] should arrive as a String.
	if typeof(args) == TYPE_ARRAY and (args as Array).size() > 0:
		var v = args[0]
		if typeof(v) == TYPE_STRING:
			_nick_input.text = v

func _gen_nick() -> String:
	# Latin nick pool — kept Latin (not CJK) on purpose so south-anchor name
	# labels in Game.tscn fit inside the iso roof callout box (S-302
	# stagger sizing assumes ~6-char Latin width). NotoSansSC still ships
	# in the bundle so users may override with CJK names if desired.
	var pool := ["Ming", "Hong", "Lei", "Mei", "Bao", "Jia"]
	return pool[randi() % pool.size()] + str(randi() % 100)

func _ensure_connected() -> bool:
	if Net.is_open():
		return true
	var url := _server_input.text.strip_edges()
	if url.length() > 0 and not url.contains("/socket.io"):
		url = url.rstrip("/") + "/socket.io/?EIO=4&transport=websocket"
	if url.length() == 0:
		Net.connect_to_server()
	else:
		Net.connect_to_server(url)
	_status.text = "正在连接服务器…"
	return false

func _on_create() -> void:
	var nick := _nick_input.text.strip_edges()
	if nick.length() == 0:
		_status.text = "先填个昵称"
		return
	if not _ensure_connected():
		await Net.connected
	GameState.create_room(nick)

func _on_join() -> void:
	var nick := _nick_input.text.strip_edges()
	var code := _code_input.text.strip_edges().to_upper()
	if nick.length() == 0 or code.length() == 0:
		_status.text = "昵称和房号都要填"
		return
	if not _ensure_connected():
		await Net.connected
	GameState.join_room(code, nick)

func _on_error(msg: String) -> void:
	if msg.length() > 0:
		_status.text = "✗ " + msg

func _on_status(c: bool) -> void:
	if c:
		_status.text = "已连上"
	else:
		_status.text = "未连接"
