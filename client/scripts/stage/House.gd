# House.gd — small visual controller for one player's house.
#
# Pulls the per-house texture from SpriteAtlas — there are 4 variant
# silhouettes × 4 damage stages baked at build time by
# `scripts/gen-3rd-party-composites.mjs` from the Kenney CC0 packs.
# Variant is picked deterministically from `player_id` so each player's
# house is visually distinct (S-417). Damage stage advances 0→3 on
# show_damage(). set_player_color() applies a low-saturation tint.

extends Node2D

@onready var _body: Sprite2D = $Body
@onready var _roof_tint: Sprite2D = $Body/RoofTint
@onready var _name_label: Label = $NameLabel

var _stage: int = 0          # 0..3 damage
var _variant: int = 0        # 0..HOUSE_VARIANTS-1
var _player_id: String = ""
var _player_color: Color = Color(1, 1, 1, 1)
# S-443 — when ≥1 visitor is camped on this house's anchor, hide the
# house's own NameLabel so the per-character labels (which fan out
# vertically via Character.LABEL_STACK_OFFSET) don't visually
# concatenate with this fixed-position house label. Without this
# guard the resident character's label top edge (world y =
# house_y - 110) abuts the house label's bottom edge (world y =
# house_y - 110) with ZERO gap, producing the t27000.png
# 'random.nter' run where 'counter' (house label) and 'random'
# (visitor label, idx=1) read as a single horizontal text string.
var _label_visited: bool = false

func _atlas() -> Node:
	# get_node_or_null("/root/...") emits a Godot warning if the calling
	# node hasn't been added to the SceneTree yet — before _ready, this
	# House isn't parented. Guard via is_inside_tree() to keep the log
	# clean while still resolving the autoload correctly post-add.
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/SpriteAtlas")

func _ready() -> void:
	# Recompute the variant in case set_player_id() ran before we were
	# in the tree (then HOUSE_VARIANTS lookup fell back to the default).
	if _player_id != "":
		_variant = _variant_for_player_id(_player_id)
	_apply_textures()

# Set the player_id so the house picks a deterministic variant. Safe to
# call before _ready — _apply_textures handles the not-yet-bound case
# and _ready() recomputes the variant once the autoload is reachable.
func set_player_id(pid: String) -> void:
	_player_id = pid
	_variant = _variant_for_player_id(pid)
	_apply_textures()

func _variant_for_player_id(pid: String) -> int:
	var atlas := _atlas()
	var variants := 4
	if atlas != null and "HOUSE_VARIANTS" in atlas:
		variants = max(1, int(atlas.HOUSE_VARIANTS))
	if pid == "":
		return 0
	# Godot's hash() returns a non-negative int; modulo keeps it in
	# [0, variants). Stable across reconnects because pid is the
	# server-assigned playerId string.
	return int(abs(hash(pid))) % variants

func _apply_textures() -> void:
	if _body == null:
		# Called before _ready — onready vars not bound yet. _ready will
		# call _apply_textures after the @onready resolves.
		return
	var atlas := _atlas()
	if atlas == null:
		return
	var tex: Texture2D = null
	if atlas.has_method("texture_for_house"):
		tex = atlas.texture_for_house(_variant, _stage)
	if tex == null and not atlas.house_textures.is_empty():
		# Defensive fallback to the variant-0 sequence if the per-variant
		# composite is missing on disk for any reason.
		var idx: int = clampi(_stage, 0, atlas.house_textures.size() - 1)
		tex = atlas.house_textures[idx]
	if tex == null:
		return
	_body.texture = tex
	# Apply per-player tint as a low-saturation overlay so the wall
	# beige still reads correctly. Roof gets the strong tint via the
	# child overlay sprite.
	_body.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(_player_color, 0.18)
	# We don't have a separate roof-only mask atlas yet, so the roof
	# tint child stays empty for now — the roof colour reads via the
	# body modulate above (palette places it at the top).

func set_player_color(c: Color) -> void:
	_player_color = c
	_apply_textures()

func set_label(s: String) -> void:
	if _name_label != null:
		_name_label.text = s

# S-443 — toggle the visited state of this house. When visited (≥1
# camped visitor character), hide the house's NameLabel so the
# fixed-position house text can't visually concatenate with the
# fan-out character labels. When unvisited, restore the label.
# GameStage._reconcile_label_stacks calls this every frame from the
# reconciler's `occupants` ledger so the toggle tracks live world
# positions.
func set_label_visited(visited: bool) -> void:
	if _label_visited == visited:
		return
	_label_visited = visited
	if _name_label != null:
		_name_label.visible = not visited

func show_damage() -> void:
	# Advance the damage stage (cap at 3 = ruined).
	_stage = min(_stage + 1, 3)
	_apply_textures()
