# client/scripts/particles/Fx.gd — particle dot textures.
#
# §I.0 carve-out: particle textures (small radial-falloff alpha dots fed
# into GPUParticles2D) are exempt from the procedural-art ban because
# they're not entity art — they're per-pixel alpha gradients used as
# point sprites by the GPU. Living under client/scripts/particles/
# matches the §I.0 acceptance grep filter (`grep -v particles/`).
#
# This module replaces the per-particle texture generation that used to
# live in SpriteAtlas.gd before S-386 split entity art (PNG textures
# from CC0 packs) from particle dots (procedural alpha discs).

extends Node

const _DUST_COLOR     := Color(0.78, 0.70, 0.55, 1.0)
const _CLOTH_COLOR    := Color(0.92, 0.20, 0.24, 1.0)
const _WOODCHIP_COLOR := Color(0.55, 0.32, 0.16, 1.0)

var dust_texture: ImageTexture
var cloth_texture: ImageTexture
var woodchip_texture: ImageTexture
var confetti_texture: ImageTexture

func _ready() -> void:
	dust_texture     = _radial_dot(32, _DUST_COLOR, 0.5)
	cloth_texture    = _radial_dot(32, _CLOTH_COLOR, 0.7)
	woodchip_texture = _radial_dot(32, _WOODCHIP_COLOR, 0.85)
	confetti_texture = _build_confetti(32)

# Soft-edged colored disc with alpha falloff. `hardness` 0..1 controls
# how quickly the alpha drops from center → edge.
func _radial_dot(size: int, c: Color, hardness: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := float(x) - r + 0.5
			var dy := float(y) - r + 0.5
			var d := sqrt(dx * dx + dy * dy) / r
			if d > 1.0:
				continue
			var a: float = (1.0 - d) ** (1.0 - hardness * 0.5)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a * c.a))
	return ImageTexture.create_from_image(img)

# Multi-coloured striped confetti dot.
func _build_confetti(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var palette := [
		Color(1.0, 0.85, 0.30, 1.0),
		Color(0.30, 0.85, 0.55, 1.0),
		Color(0.30, 0.65, 1.0, 1.0),
		Color(1.0, 0.45, 0.55, 1.0),
		Color(0.85, 0.55, 1.0, 1.0),
	]
	var half := size / 2
	var radius := float(half) - 2.0
	for y in range(size):
		for x in range(size):
			var dx := x - half
			var dy := y - half
			var d := sqrt(dx * dx + dy * dy)
			if d > radius:
				continue
			var idx := int(((x + y) / 4)) % palette.size()
			var c: Color = palette[idx]
			c.a = 1.0 - d / radius
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
