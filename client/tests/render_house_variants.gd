## render_house_variants.gd — S-417 acceptance: House.gd is wired to
## per-player variant selection. Instantiates 4 House nodes with the
## same playerIds the live drive seeds and asserts:
##   1. set_player_id() picks distinct variants for ≥3 of the 4 pids
##      (the 4th may legitimately collide modulo 4 — that's fine, the
##      live drive uses 3-bot rooms so 3 distinct variants is enough),
##   2. _body.texture pointer differs from the variant-0 fallback for
##      at least 1 player,
##   3. Image.get_size() is non-zero (texture actually loaded).
##
## Run with:
##   godot --headless --path client --script res://tests/render_house_variants.gd
extends SceneTree

func _init() -> void:
	await process_frame
	await process_frame
	var sa: Node = root.get_node_or_null("SpriteAtlas")
	if sa == null:
		push_error("[render_house_variants] SpriteAtlas autoload missing")
		quit(1)
		return

	var house_scene: PackedScene = load("res://scenes/stage/House.tscn")
	if house_scene == null:
		push_error("[render_house_variants] House.tscn failed to load")
		quit(1)
		return

	# These are the same pid shapes the server emits — short opaque ids.
	var pids := ["pid-alice-7a3", "pid-bob-9c1", "pid-cara-12d", "pid-dan-44"]
	var variants_seen := {}
	var textures_seen := {}
	var failures := []
	for pid in pids:
		var inst = house_scene.instantiate()
		root.add_child(inst)
		await process_frame  # let _ready fire so onready vars bind
		if not inst.has_method("set_player_id"):
			failures.append("House missing set_player_id() — S-417 not wired")
			break
		inst.set_player_id(pid)
		await process_frame
		var v := int(inst._variant)
		variants_seen[v] = (variants_seen.get(v, 0) as int) + 1
		var body: Sprite2D = inst.get_node_or_null("Body") as Sprite2D
		if body == null or body.texture == null:
			failures.append("House(%s) Body texture is null after set_player_id" % pid)
			continue
		var ptr := str(body.texture.get_instance_id())
		textures_seen[ptr] = (textures_seen.get(ptr, 0) as int) + 1
		var sz := body.texture.get_size()
		if sz.x <= 0 or sz.y <= 0:
			failures.append("House(%s) texture get_size() = %s" % [pid, sz])
		print("[render_house_variants] pid=%s variant=%d tex=%s size=%s" %
			[pid, v, ptr, sz])
		inst.queue_free()

	# Acceptance — distinct variants count.
	var distinct_variants := variants_seen.size()
	var distinct_textures := textures_seen.size()
	print("[render_house_variants] distinct_variants=%d distinct_textures=%d" %
		[distinct_variants, distinct_textures])

	if distinct_variants < 3:
		failures.append("expected ≥3 distinct variants across 4 pids, got %d" % distinct_variants)
	if distinct_textures < 3:
		failures.append("expected ≥3 distinct Texture2D instances, got %d" % distinct_textures)

	if failures.size() > 0:
		for f in failures:
			push_error("[render_house_variants] FAIL: %s" % f)
		quit(1)
		return
	print("[render_house_variants] PASS — variant selection wires through to per-player textures.")
	quit(0)
