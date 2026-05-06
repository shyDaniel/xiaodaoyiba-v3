# SpriteAtlas.gd — thin loader that resolves (kind, variant) tuples to
# pre-built PNG textures from CC0 packs under
# `client/assets/sprites/3rd-party/composites/`.
#
# Pre-S-386 this module procedurally rendered all entity art via
# per-pixel writes / Bresenham line strokes. §I.0 HARD BAN forbids that
# pattern for entity art. The composites are stitched at build time by
# `scripts/gen-3rd-party-composites.mjs` from Kenney CC0 source tiles
# (Tiny Town + Tiny Dungeon) — pure pixel copies + nearest-neighbour
# scale, zero procedural shape drawing.
#
# Public API preserved verbatim so all downstream consumers (Character,
# House, GameStage, LandingHero, Lobby) keep working unchanged:
#   character_textures: Dictionary  state_str -> Texture2D
#   house_textures:     Array       damage_stage -> Texture2D
#   knife_texture:      Texture2D
#   knife_trail_texture: Texture2D
#   fx_*_texture:       Texture2D   (proxied to Fx autoload)
#
# Stable typed contract (S-393): every entity texture exposed by this
# autoload is a `Texture2D`. The concrete subclass at runtime is
# CompositedTexture2D (returned by `load("res://...png")` on imported
# PNG resources). Consumers MUST annotate as `Texture2D`, not
# `ImageTexture` — the latter is a sibling subclass and a typed
# assignment will raise 'Trying to assign value of type
# CompressedTexture2D to a variable of type ImageTexture' and abort
# the per-frame blit (visible regression: empty iso stage in
# docs/screenshots/action.png at iter 83). All `Image.get_image()`
# calls on these textures must also tolerate a null return for the
# headless dummy renderer; check before reading pixels.
#
# Particle dot textures (alpha-falloff dots used by GPUParticles2D)
# remain procedural per §I.0 carve-out, but live under
# `client/scripts/particles/Fx.gd` so the path-based grep filter
# excludes them from the procedural-art ban check.

extends Node

# --- public API ---------------------------------------------------------

var character_textures: Dictionary = {}     # state_str -> Texture2D (variant 0, back-compat)
# S-424 — per-variant character textures. Indexed by variant int 0..N-1
# then by state_str. Built at _ready alongside character_textures so
# every consumer (Character.gd via character_texture_for, LandingHero
# via character_textures) keeps a Texture2D handle even if the per-
# variant PNG is missing on disk.
var character_textures_by_variant: Array = []  # [variant][state_str] -> Texture2D
var house_textures: Array = []              # damage_stage -> Texture2D
var knife_texture: Texture2D
var knife_trail_texture: Texture2D

# FX particle dots — physically owned by the Fx autoload, but exposed
# here so existing GameStage code (`atlas.fx_dust_texture`) keeps working.
var fx_dust_texture: Texture2D
var fx_cloth_texture: Texture2D
var fx_woodchip_texture: Texture2D
var fx_confetti_texture: Texture2D

# --- character / house states ------------------------------------------

const CHARACTER_STATES := [
	"ALIVE_CLOTHED",
	"ALIVE_PANTS_DOWN",
	"RUSHING",
	"ATTACKING",
	"DEAD",
]
# S-424 — number of per-player character silhouette variants, mirroring
# HOUSE_VARIANTS so the same hash-mod-N pattern produces a unique
# (house, character) pair per playerId.
const CHARACTER_VARIANTS := 4
const HOUSE_VARIANTS := 4   # 4 visual variants per damage stage in pack
const HOUSE_DAMAGE_STAGES := 4

# --- composite paths ---------------------------------------------------

const COMPOSITES := "res://assets/sprites/3rd-party/composites"

func _ready() -> void:
	_load_characters()
	_load_houses()
	_load_knife()
	_proxy_fx()

func _load_characters() -> void:
	# S-424 — populate both:
	#   character_textures            (variant 0, back-compat for LandingHero)
	#   character_textures_by_variant (per-variant table consumed by
	#                                  Character.character_texture_for)
	# We always fall back to the variant-0 / back-compat alias texture
	# if a per-variant PNG is missing on disk so the renderer never
	# strands on a null Texture2D (the S-393 typed-assignment crash).
	character_textures_by_variant.resize(CHARACTER_VARIANTS)
	# First pass: load the back-compat aliases so character_textures is
	# populated for legacy consumers and as the variant-fallback table.
	for state in CHARACTER_STATES:
		var path := "%s/character_%s.png" % [COMPOSITES, state]
		var tex: Texture2D = load(path)
		if tex != null:
			character_textures[state] = tex
	# Second pass: per-variant. Each slot is its own state_str -> Texture2D
	# dict. Variant N falls back to the back-compat dict when the
	# composite is missing, so a partially-baked asset directory still
	# renders something.
	for v in range(CHARACTER_VARIANTS):
		var per_variant: Dictionary = {}
		for state in CHARACTER_STATES:
			var path := "%s/character_v%d_%s.png" % [COMPOSITES, v, state]
			var tex: Texture2D = load(path)
			if tex == null:
				tex = character_textures.get(state, null)
			if tex != null:
				per_variant[state] = tex
		character_textures_by_variant[v] = per_variant

func _load_houses() -> void:
	# House.gd / LandingHero.gd index by damage_stage only (0..3). We keep
	# variant 0 as the canonical sequence for them; variants 1..3 are
	# available via texture_for_house(variant, dmg) below for future
	# scenes that want per-house diversity.
	for dmg in range(HOUSE_DAMAGE_STAGES):
		var path := "%s/house_v0_d%d.png" % [COMPOSITES, dmg]
		var tex: Texture2D = load(path)
		if tex != null:
			house_textures.append(tex)

func _load_knife() -> void:
	knife_texture = load("%s/knife.png" % COMPOSITES)
	# Trail re-uses the same blade texture; per-particle motion-blur is
	# expressed via Sprite2D.modulate alpha at draw time. A separate trail
	# composite would just be a wider-blur variant of the same blade.
	knife_trail_texture = knife_texture

func _proxy_fx() -> void:
	# Fx autoload owns the particle dot textures (path-excluded from §I.0).
	# We expose them here so GameStage's existing `atlas.fx_*` accessors
	# keep working without scanning a different autoload.
	var fx := get_node_or_null("/root/Fx")
	if fx == null:
		return
	fx_dust_texture     = fx.dust_texture
	fx_cloth_texture    = fx.cloth_texture
	fx_woodchip_texture = fx.woodchip_texture
	fx_confetti_texture = fx.confetti_texture

# --- variant helpers ---------------------------------------------------

# S-424 — Returns the per-variant character texture for a given visual
# state, falling back to the back-compat character_textures dict if a
# per-variant PNG is missing. Variant int is clamped into 0..CHARACTER_
# VARIANTS-1 so callers may pass abs(hash(player_id)) without their own
# modulus.
func character_texture_for(variant: int, state: String) -> Texture2D:
	var v := clampi(variant, 0, CHARACTER_VARIANTS - 1)
	if v < character_textures_by_variant.size():
		var per_variant: Dictionary = character_textures_by_variant[v]
		if per_variant != null and per_variant.has(state):
			return per_variant[state]
	return character_textures.get(state, null)

# Returns the (variant, damage) house texture if available, else null.
# Variant 0..3, damage 0..3.
func texture_for_house(variant: int, damage: int) -> Texture2D:
	var v := clampi(variant, 0, HOUSE_VARIANTS - 1)
	var d := clampi(damage, 0, HOUSE_DAMAGE_STAGES - 1)
	var path := "%s/house_v%d_d%d.png" % [COMPOSITES, v, d]
	return load(path)

# Returns the iso ground lattice baked PNG for the requested cell count
# (9 for LandingHero, 11 for Ground).
func ground_lattice(cells: int) -> Texture2D:
	var n := 11 if cells >= 11 else 9
	return load("%s/ground_lattice_%d.png" % [COMPOSITES, n])
