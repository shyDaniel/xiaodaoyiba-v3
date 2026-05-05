# Landing.gd — title screen, nickname entry, create-room / join-room.
#
# FINAL_GOAL §title: the game name is "小刀一把冲到你家". The landing must
# advertise that name PROMINENTLY and visually echo the four nouns from
# the rhyme: 小刀 / 家 / 裤衩 / 咔嚓. The hero illustration is procedural
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
	_server_input.placeholder_text = "默认 ws://localhost:3000"
	_status.text = "未连接 · 输入昵称后点 创建房间 或 加入房间"
	Audio.cross_fade_bgm("lobby")

func _gen_nick() -> String:
	var pool := ["小白", "小李", "小张", "小陈", "小刘", "小赵"]
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
	_status.text = "正在连接服务器..."
	return false

func _on_create() -> void:
	var nick := _nick_input.text.strip_edges()
	if nick.length() == 0:
		_status.text = "请先填昵称"
		return
	if not _ensure_connected():
		await Net.connected
	GameState.create_room(nick)

func _on_join() -> void:
	var nick := _nick_input.text.strip_edges()
	var code := _code_input.text.strip_edges().to_upper()
	if nick.length() == 0 or code.length() == 0:
		_status.text = "请先填昵称和房号"
		return
	if not _ensure_connected():
		await Net.connected
	GameState.join_room(code, nick)

func _on_error(msg: String) -> void:
	if msg.length() > 0:
		_status.text = "× " + msg

func _on_status(c: bool) -> void:
	if c:
		_status.text = "已连接服务器"
	else:
		_status.text = "未连接"
