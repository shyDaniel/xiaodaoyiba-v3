## smoke_lobby.gd — verifies Lobby.tscn instantiates without onready
## errors and that all @onready node references resolve.
##
## Failure of this gate was the iter-7 bug: Lobby.gd queried $V/...
## but Lobby.tscn nests under Card/V/..., so every @onready var was
## null after _ready() and clicking 创建房间 dropped users into a
## dead screen.
##
## Run with:
##   godot --headless --path client --script res://tests/smoke_lobby.gd
##
## Exit codes:
##   0 = pass
##   1 = at least one assertion failed
extends SceneTree

func _init() -> void:
	var failures: Array[String] = []

	# Wait one frame so SceneTree autoloads (Net, GameState, Audio) are
	# registered under /root before we touch them.
	await process_frame

	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		push_error("GameState autoload not found at /root/GameState")
		quit(1)
		return

	# Inject mock GameState data BEFORE instantiating the lobby so
	# _render() in _ready() has something to draw.
	gs.room_code = "ABCD"
	gs.snapshot = {
		"youAreHost": true,
		"players": [
			{"id": "p1", "nickname": "alice", "isBot": false, "isHost": true},
			{"id": "p2", "nickname": "bob",   "isBot": false, "isHost": false},
			{"id": "p3", "nickname": "carol", "isBot": true,  "isHost": false},
		]
	}

	var scene: PackedScene = load("res://scenes/Lobby.tscn")
	if scene == null:
		push_error("Lobby.tscn failed to load")
		quit(1)
		return

	var lobby: Node = scene.instantiate()
	if lobby == null:
		push_error("Lobby.tscn failed to instantiate")
		quit(1)
		return

	root.add_child(lobby)

	# Let _ready() and the deferred render run.
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	await process_frame

	# Assert all @onready vars resolved.
	var checks := [
		["_code_label", lobby.get("_code_label")],
		["_members",    lobby.get("_members")],
		["_add_bot",    lobby.get("_add_bot")],
		["_start",      lobby.get("_start")],
		["_leave",      lobby.get("_leave")],
	]
	for c in checks:
		var name: String = c[0]
		var ref = c[1]
		if ref == null:
			failures.append("@onready var %s is null after _ready()" % name)
		elif not is_instance_valid(ref):
			failures.append("@onready var %s holds an invalid instance" % name)

	# Assert the room code populated from GameState.
	var code_lbl = lobby.get("_code_label")
	if code_lbl != null and is_instance_valid(code_lbl):
		var txt: String = String(code_lbl.text)
		if not txt.contains("ABCD"):
			failures.append("Code label text %q does not contain room code 'ABCD'" % txt)

	# Assert member rows rendered for the 3 mock players.
	var members = lobby.get("_members")
	if members != null and is_instance_valid(members):
		var row_count: int = members.get_child_count()
		if row_count != 3:
			failures.append("Members list has %d rows, expected 3" % row_count)

	# Assert host gating: youAreHost=true, n=3 → AddBot enabled, Start enabled.
	var add_bot = lobby.get("_add_bot")
	if add_bot != null and is_instance_valid(add_bot):
		if add_bot.disabled:
			failures.append("AddBot disabled but youAreHost=true")
	var start_btn = lobby.get("_start")
	if start_btn != null and is_instance_valid(start_btn):
		if start_btn.disabled:
			failures.append("Start disabled but youAreHost=true and n=3")

	if failures.is_empty():
		print("[smoke_lobby] PASS — Lobby instantiated cleanly, all @onready vars bound, 3 rows rendered, host buttons enabled.")
		quit(0)
	else:
		print("[smoke_lobby] FAIL:")
		for f in failures:
			print("  - %s" % f)
		quit(1)
