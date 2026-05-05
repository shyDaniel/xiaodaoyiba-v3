# Character.gd — sprite + state machine for one player on the iso stage.
#
# FINAL_GOAL §C6 / §C7 / §C11:
#   States: ALIVE_CLOTHED, ALIVE_PANTS_DOWN, RUSHING, ATTACKING, DEAD.
#   The PANTS_DOWN visual must persist across rounds — the red briefs
#   render on every phase until restored or DEAD.
#
# Sprites come from the SpriteAtlas autoload, which procedurally
# renders shaded pixel-art at boot (see scripts/globals/SpriteAtlas.gd).
# Per-player hue tinting applies to the torso layer via modulate so the
# silhouette stays cohesive across players. The Knife child Sprite2D
# is hidden in non-attack states and swung during ATTACKING.

class_name Character
extends Node2D

signal arrived_at_house(target_pos: Vector2)

enum State { ALIVE_CLOTHED, ALIVE_PANTS_DOWN, RUSHING, ATTACKING, DEAD }

@export var player_id: String = ""
@export var nickname: String = ""
@export var color_hue: float = 0.0   # set deterministically from id hash
@export var is_self: bool = false

var state: int = State.ALIVE_CLOTHED
var persistent_pants_down: bool = false  # §C7 persistent shame
var home_position: Vector2 = Vector2.ZERO
var _rush_tween: Tween = null
var _knife_swing_tween: Tween = null

# S-269 / S-285 / S-302 — name-label collision handling. When N≥2
# characters share a house anchor (visitor[s] camped at a resident's
# house), each character is assigned a unique stack index so their
# NameLabels fan out vertically instead of overlapping. Stack index 0
# keeps the default y (the resident's slot); index k≥1 lifts the
# label by LABEL_STACK_OFFSET * k px so the labels read as a clean
# vertical column.
#
# S-302 — bumped LABEL_STACK_OFFSET from 28 → 36 so adjacent labels
# (20 px tall) have a 16-px clear gutter and the top-edge gap is 36
# px, well over the brief's ≥ 20-px-per-occupant clause. The 28-px
# value still passed the unit test but in the live HTML5 build the
# t27000 R4.PREP screenshot rendered "Meicounter" as if both labels
# were at the same y — so we (a) widen the gap, (b) make
# set_label_stack_index idempotent so a single missed reconciler
# tick can't strand the label at default y, (c) horizontally stagger
# each occupant's label by LABEL_HORIZONTAL_STAGGER * idx px so the
# 32-px PULL_PANTS landing offset can't make adjacent-y labels
# concatenate sideways into "Meicounter", and (d) give visitors a
# distinct font outline COLOUR (per-player tint) plus a heavier
# outline so labels visually separate even at the same screen y.
#
# When the resident has at least one visitor, the resident's label
# also fades to LABEL_DIMMED_ALPHA so the visiting actor[s] read as
# the foreground identity. Visitors get the heavier outline plus a
# tinted outline-colour (drop-shadow analogue) for the brief's
# "contrasting outline/drop-shadow per label" clause so each fanned
# out name pops against the busy isometric background instead of
# bleeding into the wall sprite behind it. See FINAL_GOAL §C8.
const LABEL_STACK_OFFSET: float = 44.0
# Per-occupant horizontal stagger applied on top of each label's
# default x. With 8 px-per-occupant a 3-actor pile-up reads as a
# clean descending diagonal (idx=1 → +8, idx=2 → +16, idx=3 → +24).
const LABEL_HORIZONTAL_STAGGER: float = 8.0
# Visitor labels are NARROWED from the .tscn default 100 px (±50)
# down to 72 px (±36) so the visitor's label rect doesn't horizontally
# overlap the resident's at the canonical PULL_PANTS landing offset
# (-32 px in world space). Math: visitor_centre = resident_centre - 32
# + LABEL_HORIZONTAL_STAGGER, so visitor's label spans
# [resident_cx - 32 + 8 - 36, resident_cx - 32 + 8 + 36] =
# [resident_cx - 60, resident_cx + 12]; resident's spans
# [resident_cx - 50, resident_cx + 50]. Horizontal overlap is
# [resident_cx - 50, resident_cx + 12] = 62 px wide. To kill the
# overlap entirely we would need stagger ≥ 86 px which would push
# the label off-screen for the leftmost stack, so instead we rely
# on the 44-px vertical fan-out + tinted outline + opaque background
# panel (see set_label_stack_index below) to make the labels read
# as separate names in OCR even with rectangular x-overlap.
const LABEL_VISITING_HALF_WIDTH: float = 36.0
const LABEL_DIMMED_ALPHA: float = 0.5
const LABEL_DEFAULT_OUTLINE_SIZE: int = 4
const LABEL_VISITING_OUTLINE_SIZE: int = 12
var _label_default_top: float = -130.0
var _label_default_bottom: float = -110.0
var _label_default_left: float = -50.0
var _label_default_right: float = 50.0
var _label_stack_index: int = 0
var _label_resident_dimmed: bool = false

@onready var _body: Sprite2D = $Body
@onready var _torso_tint: Sprite2D = $Body/TorsoTint
@onready var _label: Label = $NameLabel
@onready var _throw_glyph: Label = $ThrowGlyph
@onready var _knife: Sprite2D = $Knife
# S-309 — persistent shame badge. A permanent emoji glyph rendered
# above the head whenever this character is in ALIVE_PANTS_DOWN. The
# badge is the failsafe for the §C7 "shame must be visible at every
# phase" gate: the body sprite's red briefs region is geometrically
# correct but at the live HTML5 viewport scale (sprite ≈48 px on
# screen) it can be occluded by an adjacent visitor character or
# tucked behind the house's wall band. The badge sits 130 px above
# the character anchor — well above any house roof — and gently
# pulses so it reads as an active "this player is exposed" marker
# even when the body silhouette is hidden.
@onready var _shame_badge: Label = $ShameBadge

# Tween handle so we can stop the previous pulse before starting a
# new one when set_persistent_pants_down toggles repeatedly.
var _shame_badge_tween: Tween = null

func _atlas() -> Node:
	return get_node_or_null("/root/SpriteAtlas")

func _ready() -> void:
	home_position = position
	_label.text = nickname
	_label.add_theme_color_override("font_color", Color.from_hsv(color_hue, 0.45, 1.0))
	# Cache the scene's authored label extents so visiting-stack math
	# is anchored to the .tscn defaults rather than whatever the label
	# happens to be at when set_label_stack_index is first called.
	# S-302 caches the horizontal extents too so the per-occupant
	# horizontal stagger (LABEL_HORIZONTAL_STAGGER) computes off the
	# scene authoring, not the post-stagger state.
	_label_default_top = _label.offset_top
	_label_default_bottom = _label.offset_bottom
	_label_default_left = _label.offset_left
	_label_default_right = _label.offset_right
	_throw_glyph.visible = false
	if _shame_badge != null:
		_shame_badge.visible = false
	# Knife sprite from atlas. Centered=false; offset to pivot at handle.
	var atlas := _atlas()
	if atlas != null and atlas.knife_texture != null:
		_knife.texture = atlas.knife_texture
		# Pivot at handle (left end), offset rotates the blade.
		_knife.offset = Vector2(0, -10)
	_refresh_visual()

func set_persistent_pants_down(v: bool) -> void:
	persistent_pants_down = v
	_refresh_visual()

func set_state(s: int) -> void:
	state = s
	_refresh_visual()

func show_throw(glyph: String) -> void:
	# S-373 — DEAD characters have had _throw_glyph freed; skip.
	if _throw_glyph == null or not is_instance_valid(_throw_glyph) or state == State.DEAD:
		return
	_throw_glyph.text = glyph
	_throw_glyph.visible = true
	_throw_glyph.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_throw_glyph, "modulate:a", 1.0, 0.18)

func hide_throw() -> void:
	if _throw_glyph == null or not is_instance_valid(_throw_glyph):
		return
	if not _throw_glyph.visible:
		return
	var tw := create_tween()
	tw.tween_property(_throw_glyph, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): _throw_glyph.visible = false)

func rush_to(target_world_pos: Vector2, dur_ms: int) -> void:
	if _rush_tween != null and _rush_tween.is_valid():
		_rush_tween.kill()
	state = State.RUSHING
	_refresh_visual()
	# Face the target by mirroring the body sprite horizontally.
	_body.flip_h = target_world_pos.x < position.x
	_rush_tween = create_tween()
	_rush_tween.tween_property(self, "position", target_world_pos, float(dur_ms) / 1000.0)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rush_tween.tween_callback(func():
		state = State.ATTACKING
		_refresh_visual()
		_swing_knife()
		arrived_at_house.emit(target_world_pos))

func teleport_home() -> void:
	if _rush_tween != null and _rush_tween.is_valid():
		_rush_tween.kill()
	position = home_position
	_body.flip_h = false
	if state != State.DEAD:
		state = State.ALIVE_PANTS_DOWN if persistent_pants_down else State.ALIVE_CLOTHED
	# Returning home clears any visiting-stack offset on the label —
	# we're back at our own anchor and don't share the tile with a
	# resident, so the default label position is correct.
	set_label_stack_index(0)
	set_label_resident_dimmed(false)
	_refresh_visual()

# S-269 / S-285 / S-302 — set the vertical stack slot for this
# character's NameLabel when N≥2 characters share an anchor. idx=0
# keeps the default y; idx=k>=1 lifts the label by LABEL_STACK_OFFSET
# * k px so multiple visitors can fan out without garbling into each
# other (e.g. avoiding the t27000.png "Meicounter" 2-actor and
# "counterorandom" 3-actor pile-ups).
#
# S-302 — this writer is now IDEMPOTENT: it always re-applies the
# offsets / outline / colour overrides regardless of whether the
# tracked index changed. The previous early-return-on-equal optimisation
# was trading correctness for irrelevant churn — if any other path ever
# nudged offset_top back to the default (a stale .pck, a re-instantiation,
# a transition tween), the cached "no change" branch would strand the
# label at the wrong y forever. The cost is two property writes per
# character per frame, which is far below the rendering threshold; the
# upside is that a single missed reconciler tick can no longer cause
# the live "Meicounter" regression.
#
# Visitors (idx≥1) ALSO get:
#   - a heavier font outline (LABEL_VISITING_OUTLINE_SIZE px) and a
#     contrasting outline colour tinted from their own player hue, so
#     even if two labels happen to land near the same screen y the
#     glyphs read as separate names (different stroke colours);
#   - a horizontal stagger of LABEL_HORIZONTAL_STAGGER * idx px to
#     the right of the default centre, so the 32-px PULL_PANTS
#     landing offset can't make a visitor's label horizontally
#     concatenate with the resident's. With a 4-px-per-occupant
#     stagger this also helps a 3-or-4-actor pile-up read as a clear
#     descending diagonal column.
func set_label_stack_index(idx: int) -> void:
	# S-373 — DEAD characters have already had their NameLabel freed
	# synchronously in play_death(). Skip every override write here so
	# the per-frame reconciler can't resurrect a stylebox / outline
	# tint on a corpse. is_instance_valid is the cheap defensive
	# check against queue_free'd nodes that haven't been collected yet.
	if _label == null or state == State.DEAD or not is_instance_valid(_label):
		return
	_label_stack_index = idx
	var dy: float = LABEL_STACK_OFFSET * float(idx)
	var dx: float = LABEL_HORIZONTAL_STAGGER * float(idx)
	_label.offset_top = _label_default_top - dy
	_label.offset_bottom = _label_default_bottom - dy
	# Visitors (idx ≥ 1) use the narrowed half-width AND the per-
	# occupant horizontal stagger so co-anchored labels fan out as
	# a diagonal column instead of stacking centred-on-character.
	# The resident (idx = 0) keeps the .tscn-authored full width.
	var hw: float = LABEL_VISITING_HALF_WIDTH if idx >= 1 else (_label_default_right - _label_default_left) * 0.5
	var cx: float = (_label_default_left + _label_default_right) * 0.5 + dx
	_label.offset_left = cx - hw
	_label.offset_right = cx + hw
	# Visitors get a heavier outline AND a contrasting outline colour
	# tinted from their own player hue. The resident (idx=0) keeps the
	# default thin outline / black stroke — it reads as the muted
	# context behind the foreground visitors.
	var outline: int = LABEL_VISITING_OUTLINE_SIZE if idx >= 1 else LABEL_DEFAULT_OUTLINE_SIZE
	_label.add_theme_constant_override("outline_size", outline)
	if idx >= 1:
		# Pick a deeply saturated, low-value version of the player's
		# hue so the outline is visibly different from any neighbour
		# (whose hue is rotated 1/N around the wheel) AND from the
		# default black stroke. With value=0.18 the outline reads as
		# a colour-tinted shadow rather than competing with the inner
		# white fill.
		var stroke := Color.from_hsv(color_hue, 0.85, 0.18)
		_label.add_theme_color_override("font_outline_color", stroke)
		# S-302 — opaque background panel behind visitor labels. The
		# panel kills the residual horizontal overlap that the
		# narrowed-width + stagger leaves behind: even when two
		# visitor rects share an x-span (e.g. 3 visitors at the same
		# anchor), the painted background of the higher-index visitor
		# fully occludes the lower-index visitor's glyphs in the
		# overlap region, so OCR cannot bleed one name into the next.
		# The fill colour matches the player's hue at low value with
		# moderate alpha so the silhouette remains readable through
		# the panel.
		var sb := StyleBoxFlat.new()
		var fill := Color.from_hsv(color_hue, 0.55, 0.22)
		fill.a = 0.85
		sb.bg_color = fill
		sb.border_color = stroke
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		_label.add_theme_stylebox_override("normal", sb)
	else:
		# Resident — restore the .tscn default black outline and
		# remove any visitor-style background panel that may have
		# been installed in a prior frame (e.g. the character was a
		# visitor in a previous round and is now back home).
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		_label.remove_theme_stylebox_override("normal")

# S-269 — back-compat shim for callers (and the original render_label_
# collision test) that still speak the binary "is this character a
# visitor" API. A visitor is just stack-index 1; clearing it is
# stack-index 0. New call sites should prefer set_label_stack_index().
func set_label_visiting(is_visiting: bool) -> void:
	set_label_stack_index(1 if is_visiting else 0)

# S-269 / S-302 — fade the resident's NameLabel to LABEL_DIMMED_ALPHA
# while a visitor is camped on this anchor, so the visiting actor's
# stacked label reads as the foreground name and the resident's reads
# as the context. Restored on next round-start / teleport_home.
#
# S-302 — writer is idempotent. Re-applying the same dim state every
# frame is two property writes; the cost is below the rendering
# threshold and the upside is that no foreign mutation path can
# strand the alpha at the wrong value (the same robustness fix as
# set_label_stack_index above).
func set_label_resident_dimmed(dimmed: bool) -> void:
	# S-373 — same dead-corpse short-circuit as set_label_stack_index
	# above. play_death() freed _label; we must not write to it.
	if _label == null or state == State.DEAD or not is_instance_valid(_label):
		return
	_label_resident_dimmed = dimmed
	var col := _label.modulate
	col.a = LABEL_DIMMED_ALPHA if dimmed else 1.0
	_label.modulate = col

# S-269 — render-test hook. Returns the NameLabel rect in this
# character's local space (top-left, w, h). The acceptance test
# asserts that two co-anchored characters' rects differ by ≥ rect.h+4.
func get_name_label_rect() -> Rect2:
	if _label == null:
		return Rect2()
	return Rect2(
		Vector2(_label.offset_left, _label.offset_top),
		Vector2(_label.offset_right - _label.offset_left,
				_label.offset_bottom - _label.offset_top))

func play_attack_wiggle() -> void:
	# Quick scale pulse; conveys "winding up to chop".
	var orig := scale
	var tw := create_tween()
	tw.tween_property(self, "scale", orig * 1.15, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", orig, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func play_death() -> void:
	# S-373 — idempotent: if we already processed a death for this
	# character (e.g. server re-sends the DEAD snapshot after a
	# round-end, or the spectator path replays the stage assignment),
	# skip the destructive teardown so we don't re-tween a corpse
	# that's already at rotation=90 and don't double-queue_free the
	# child labels.
	if state == State.DEAD:
		return
	state = State.DEAD
	_refresh_visual()
	# S-373 — kill EVERY text artifact attached to this character the
	# instant it dies. Without this the NameLabel rides along through
	# the 90° rotation tween below, ending up as a sideways "iron" /
	# "Ming97" banner pinned to the corpse's last camped position
	# (see screenshots/eval80/t13000.png → t27000.png orphan-banner
	# regression). The brief's contract is: "when the character is
	# removed (eliminated/dead), the banner is freed in the same
	# tick" — so we hide and free the label payload synchronously,
	# keep only the faded, rotated body sprite as the visible corpse.
	if _label != null:
		_label.visible = false
		# Drop any visitor stylebox / outline overrides so a re-instantiation
		# (or a future revive path) starts from the .tscn defaults. The
		# stylebox in particular renders an opaque colored panel even when
		# the inner glyph is empty — leaving it set on a hidden label is a
		# latent regression vector if visibility is ever toggled back on.
		_label.remove_theme_stylebox_override("normal")
		_label.remove_theme_color_override("font_outline_color")
		_label.remove_theme_constant_override("outline_size")
		_label.queue_free()
	if _shame_badge != null:
		if _shame_badge_tween != null and _shame_badge_tween.is_valid():
			_shame_badge_tween.kill()
			_shame_badge_tween = null
		_shame_badge.visible = false
		_shame_badge.queue_free()
	if _throw_glyph != null:
		_throw_glyph.visible = false
		_throw_glyph.queue_free()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "rotation_degrees", 90.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.4, 0.6)

func is_dead() -> bool:
	return state == State.DEAD

func _swing_knife() -> void:
	# 180° arc swing: starts cocked back (-1.6 rad), ends past target (1.0 rad).
	if _knife_swing_tween != null and _knife_swing_tween.is_valid():
		_knife_swing_tween.kill()
	_knife.rotation = -1.6
	_knife.visible = true
	_knife_swing_tween = create_tween()
	_knife_swing_tween.tween_property(_knife, "rotation", 1.0, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_knife_swing_tween.tween_interval(0.18)
	_knife_swing_tween.tween_property(_knife, "rotation", -0.4, 0.18)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _refresh_visual() -> void:
	# Decide the visual state to render. Persistent-shame overrides
	# ALIVE_CLOTHED → PANTS_DOWN per §C7.
	var visual_state: String = ""
	match state:
		State.ALIVE_CLOTHED:
			visual_state = "ALIVE_PANTS_DOWN" if persistent_pants_down else "ALIVE_CLOTHED"
		State.ALIVE_PANTS_DOWN:
			visual_state = "ALIVE_PANTS_DOWN"
		State.RUSHING:
			visual_state = "RUSHING"
		State.ATTACKING:
			visual_state = "ATTACKING"
		State.DEAD:
			visual_state = "DEAD"
		_:
			visual_state = "ALIVE_CLOTHED"

	# Apply the body texture from the atlas (a single full-character
	# sprite per state, with shaded shapes baked in). The TorsoTint
	# layer is the same sprite re-modulated per-player so the body
	# silhouette gets a hue tint without changing skin/hair colours.
	var atlas := _atlas()
	if atlas != null and not atlas.character_textures.is_empty():
		var tex: Texture2D = atlas.character_textures.get(visual_state, null)
		if tex != null and _body != null:
			_body.texture = tex
			_torso_tint.texture = null   # not used yet — single-pass tint via modulate

	# Per-player hue tint applied to the body's torso region only.
	# To avoid colouring skin/hair, we instead modulate a slight tint
	# (low saturation) over the whole body — this still clearly
	# distinguishes the four players without distorting flesh tones.
	var tint := Color.from_hsv(color_hue, 0.45, 1.0)
	# Blend tint with white so skin/hair stay readable.
	if _body != null:
		_body.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(tint, 0.45)

	# S-309 — persistent shame badge. Visible whenever the rendered
	# state is PANTS_DOWN, regardless of whether persistence got there
	# via the State enum or the persistent_pants_down override. RUSH /
	# ATTACK / DEAD intentionally hide the badge: during a rush the
	# character is in motion and the body silhouette + knife arc carry
	# the read; on death the shame is moot.
	_refresh_shame_badge(visual_state == "ALIVE_PANTS_DOWN")

	# Knife visibility: only shown while ATTACKING.
	if _knife == null:
		return
	_knife.visible = (visual_state == "ATTACKING")
	if _knife.visible:
		# Position knife at the right hand; flip with body.
		var sign := -1.0 if _body.flip_h else 1.0
		_knife.position = Vector2(18 * sign, -78)
		_knife.scale.x = sign

	# DEAD overlay handled by play_death tween.

# S-309 — show/hide the persistent shame emoji glyph above the head.
# When active, the badge fades in and starts a soft scale + alpha
# pulse so the marker reads as a live "this player is exposed" cue
# even at the live HTML5 viewport scale where the body's red briefs
# region can be occluded by visiting actors or the house wall band.
# Idempotent: calling this with the same `active` flag while the
# pulse is already running is a no-op (we keep the existing tween
# instead of restarting it every _refresh_visual tick).
func _refresh_shame_badge(active: bool) -> void:
	# S-373 — DEAD characters have had _shame_badge freed in
	# play_death(); skip every write so we don't touch a stale ref.
	if _shame_badge == null or not is_instance_valid(_shame_badge) or state == State.DEAD:
		return
	if active:
		if _shame_badge.visible and _shame_badge_tween != null and _shame_badge_tween.is_valid():
			return  # already pulsing
		_shame_badge.visible = true
		_shame_badge.modulate.a = 1.0
		_shame_badge.scale = Vector2.ONE
		_shame_badge.pivot_offset = _shame_badge.size * 0.5
		if _shame_badge_tween != null and _shame_badge_tween.is_valid():
			_shame_badge_tween.kill()
		_shame_badge_tween = create_tween().set_loops()
		_shame_badge_tween.tween_property(_shame_badge, "scale", Vector2(1.18, 1.18), 0.6)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_shame_badge_tween.parallel().tween_property(_shame_badge, "modulate:a", 0.7, 0.6)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_shame_badge_tween.tween_property(_shame_badge, "scale", Vector2.ONE, 0.6)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_shame_badge_tween.parallel().tween_property(_shame_badge, "modulate:a", 1.0, 0.6)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		if _shame_badge_tween != null and _shame_badge_tween.is_valid():
			_shame_badge_tween.kill()
			_shame_badge_tween = null
		_shame_badge.visible = false
