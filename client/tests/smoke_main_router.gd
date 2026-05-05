## smoke_main_router.gd — verifies Main.gd's phase router maps the
## server's UPPERCASE phase strings ("LOBBY" | "PLAYING" | "ENDED") to
## the right Godot scene swap (Lobby.tscn / Game.tscn).
##
## Background. The TS server (server/src/rooms/Room.ts:56) declares
## `phase: 'LOBBY' | 'PLAYING' | 'ENDED'` and emits those literals on
## the wire. Iter-39's Main.gd compared the incoming phase against
## lowercase string literals (`"playing"` / `"lobby"`) — so in the
## live HTML5 build the router silently never matched, the lobby
## panel never tore down, and Game.tscn was never instantiated. A
## first-time user pressed Start and the screen froze on the lobby.
##
## This test re-runs that exact protocol shape — `_on_snapshot({phase:
## "PLAYING"})` then `_on_snapshot({phase: "LOBBY"})` — against the
## live Main.gd handler and asserts that `Main`'s `_current` child
## resolves to the right `.tscn` after each transition.
##
## We instantiate Main.tscn (not just Main.gd) so the `$SceneSlot`
## @onready ref resolves; the router writes the new scene under
## `_slot` as a child node, and the test reads back `_current
## .scene_file_path`.
##
## Run with:
##   godot --headless --path client --script res://tests/smoke_main_router.gd
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

	# Reset GameState in case earlier autoload connected anything.
	gs.room_code = ""
	gs.snapshot = {}
	gs.rounds = []
	gs.winner_choice = null

	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	if main_scene == null:
		push_error("Main.tscn failed to load")
		quit(1)
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame

	# Initial state: _show(LANDING) was called in _ready().
	var initial_path := _current_scene_file_path(main)
	if initial_path != "res://scenes/Landing.tscn":
		failures.append(
			"After _ready() expected current scene = Landing.tscn but got %q" % initial_path
		)

	# --- Test 1: PLAYING (uppercase, the actual server emit) → Game.
	# Going via the GameState signal exercises the same path the live
	# build uses (Net → GameState._on_net_event → snapshot_changed
	# emit → Main._on_snapshot).
	gs.snapshot = {"phase": "PLAYING"}
	gs.snapshot_changed.emit(gs.snapshot)
	for i in range(3):
		await process_frame

	var after_playing := _current_scene_file_path(main)
	if after_playing != "res://scenes/Game.tscn":
		failures.append(
			"After snapshot phase=PLAYING expected Game.tscn but got %q (router casing bug?)"
				% after_playing
		)

	# --- Test 2: LOBBY (uppercase) → Lobby.
	gs.snapshot = {"phase": "LOBBY"}
	gs.snapshot_changed.emit(gs.snapshot)
	for i in range(3):
		await process_frame

	var after_lobby := _current_scene_file_path(main)
	if after_lobby != "res://scenes/Lobby.tscn":
		failures.append(
			"After snapshot phase=LOBBY expected Lobby.tscn but got %q" % after_lobby
		)

	# --- Test 3: lowercase still works (defensive — if the wire
	# protocol ever switches we don't regress the autopilot loop).
	gs.snapshot = {"phase": "playing"}
	gs.snapshot_changed.emit(gs.snapshot)
	for i in range(3):
		await process_frame

	var after_lower_playing := _current_scene_file_path(main)
	if after_lower_playing != "res://scenes/Game.tscn":
		failures.append(
			"After lowercase phase=playing expected Game.tscn but got %q"
				% after_lower_playing
		)

	# --- Test 4: PLAYING → ENDED → falls back to Lobby (rematch staging).
	gs.snapshot = {"phase": "ENDED"}
	gs.snapshot_changed.emit(gs.snapshot)
	for i in range(3):
		await process_frame

	var after_ended := _current_scene_file_path(main)
	if after_ended != "res://scenes/Lobby.tscn":
		failures.append(
			"After snapshot phase=ENDED expected Lobby.tscn (rematch staging) but got %q"
				% after_ended
		)

	if failures.is_empty():
		print("[smoke_main_router] PASS — Main.gd routes uppercase server phases (LOBBY/PLAYING/ENDED) to the right scene.")
		quit(0)
	else:
		print("[smoke_main_router] FAIL:")
		for f in failures:
			print("  - %s" % f)
		quit(1)


func _current_scene_file_path(main: Node) -> String:
	# Main.gd exposes `_current` as the last instantiated scene root.
	var current = main.get("_current")
	if current == null or not is_instance_valid(current):
		return "<null>"
	return String(current.scene_file_path)
