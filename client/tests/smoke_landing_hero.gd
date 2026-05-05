## smoke_landing_hero.gd — sanity check that the LandingHero IsoPreview
## actually instances 4 house Sprite2D + 4 character Sprite2D children
## when added to a SceneTree. Verifies the §C11 acceptance bullets (a-d)
## by counting the rendered children.
##
## Run:
##   godot --headless --path client --script res://tests/smoke_landing_hero.gd
extends SceneTree

func _init() -> void:
	await process_frame
	var sa := root.get_node_or_null("SpriteAtlas")
	if sa == null:
		push_error("[smoke_landing_hero] SpriteAtlas autoload missing")
		quit(2)
		return
	# Wait one more frame so SpriteAtlas._ready() finishes its texture build.
	await process_frame
	print("[smoke_landing_hero] house_textures.size=", sa.house_textures.size(),
		"  character_textures.size=", sa.character_textures.size())
	if sa.house_textures.is_empty():
		push_error("[smoke_landing_hero] FAIL: house_textures empty")
		quit(3)
		return
	var scene: PackedScene = load("res://scenes/Landing.tscn")
	var landing: Node = scene.instantiate()
	root.add_child(landing)
	# LandingHero awaits one process_frame then builds children.
	for i in range(6):
		await process_frame
	var hero: Node = landing.get_node_or_null("IsoPreview")
	if hero == null:
		push_error("[smoke_landing_hero] FAIL: IsoPreview missing from Landing.tscn")
		quit(4)
		return
	var house_count := 0
	var char_count := 0
	var pill_count := 0
	for c in hero.get_children():
		if c is Sprite2D:
			var sprite := c as Sprite2D
			var tex := sprite.texture
			if tex != null:
				var tw := tex.get_width()
				var th := tex.get_height()
				if tw == 192 and th == 160:
					house_count += 1
					print("  HOUSE @ ", sprite.position, " modulate=", sprite.modulate)
				elif tw == 96 and th == 128:
					char_count += 1
					print("  CHAR  @ ", sprite.position, " scale=", sprite.scale)
		elif c is Control:
			pill_count += 1
	print("[smoke_landing_hero] house_count=", house_count,
		"  char_count=", char_count, "  control_count=", pill_count)
	if house_count < 4:
		push_error("[smoke_landing_hero] FAIL: expected 4 houses, got ", house_count)
		quit(5)
		return
	if char_count < 4:
		push_error("[smoke_landing_hero] FAIL: expected 4 characters, got ", char_count)
		quit(6)
		return
	if pill_count < 4:
		push_error("[smoke_landing_hero] FAIL: expected ≥4 nickname pills, got ", pill_count)
		quit(7)
		return
	print("[smoke_landing_hero] PASS")
	quit(0)
