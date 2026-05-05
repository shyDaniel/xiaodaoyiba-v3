# Landing.gd — title screen, nickname entry, create-room / join-room.
#
# FINAL_GOAL §title: the game's CN name is 小刀一把冲到你家 ("knife to your
# door"). Visible UI strings are Latin so the live HTML5 build is legible
# in any browser without a CJK system font (S-192 regression — without a
# bundled CJK FontFile, the engine has no glyph data for these codepoints
# and renders missing-glyph tofu). The hero illustration is procedural
# (knife + house + character silhouette) so the project ships without
# uploaded art per §G.

extends Control

@onready var _nick_input: LineEdit = $V/Nick
@onready var _code_input: LineEdit = $V/JoinRow/Code
@onready var _create_btn: Button = $V/CreateRow/Create
@onready var _join_btn: Button = $V/JoinRow/Join
@onready var _status: Label = $V/Status
@onready var _server_input: LineEdit = $V/ServerRow/Server

func _ready() -> void:
	_nick_input.text = _gen_nick()
	_create_btn.pressed.connect(_on_create)
	_join_btn.pressed.connect(_on_join)
	GameState.error_changed.connect(_on_error)
	GameState.connection_status_changed.connect(_on_status)
	# Default server URL hint visible in the UI.
	_server_input.placeholder_text = "default ws://localhost:3000"
	_status.text = "Disconnected - enter a nickname, then Create Room or Join Room"
	Audio.cross_fade_bgm("lobby")

func _gen_nick() -> String:
	# Latin nick pool keeps every visible label legible in browsers without
	# a CJK system font (Landing/Lobby/iso roof labels all render this).
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
	_status.text = "Connecting to server..."
	return false

func _on_create() -> void:
	var nick := _nick_input.text.strip_edges()
	if nick.length() == 0:
		_status.text = "Please enter a nickname first"
		return
	if not _ensure_connected():
		await Net.connected
	GameState.create_room(nick)

func _on_join() -> void:
	var nick := _nick_input.text.strip_edges()
	var code := _code_input.text.strip_edges().to_upper()
	if nick.length() == 0 or code.length() == 0:
		_status.text = "Please enter a nickname and a room code"
		return
	if not _ensure_connected():
		await Net.connected
	GameState.join_room(code, nick)

func _on_error(msg: String) -> void:
	if msg.length() > 0:
		_status.text = "x " + msg

func _on_status(c: bool) -> void:
	if c:
		_status.text = "Connected to server"
	else:
		_status.text = "Disconnected"
