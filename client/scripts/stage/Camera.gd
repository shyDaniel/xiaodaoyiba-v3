# Camera.gd — cinematic Camera2D controller for the iso stage.
#
# FINAL_GOAL §C2:
#   Pre-PULL_PANTS: zoom 1.0 → 1.6 over 600ms (TRANS_QUART EASE_OUT),
#                   position lerps to (actor + target) / 2.
#   Hold at 1.6× for 800ms (the shame frame).
#   Post-IMPACT:    zoom 1.6 → 1.0 over 400ms (EASE_IN), recenter.
#
# Driven by EffectPlayer; this script just exposes one API call:
#   cinematic_focus(world_pos: Vector2, zoom_in_ms, hold_ms, zoom_out_ms)
# which returns immediately and runs the choreography on its own Tween.

class_name CinematicCamera
extends Camera2D

@export var rest_zoom: float = 1.0
@export var rest_position: Vector2 = Vector2.ZERO

var _seq: Tween = null

func _ready() -> void:
	zoom = Vector2(rest_zoom, rest_zoom)
	if rest_position == Vector2.ZERO:
		rest_position = position

func cinematic_focus(world_pos: Vector2,
		zoom_in_ms: int = 600,
		hold_ms: int = 800,
		zoom_out_ms: int = 400,
		zoom_target: float = 1.6) -> void:
	if _seq != null and _seq.is_valid():
		_seq.kill()
	_seq = create_tween()
	# Phase 1: zoom in + pan, parallel.
	var zin := _seq.parallel()
	zin.tween_property(self, "zoom", Vector2(zoom_target, zoom_target), float(zoom_in_ms) / 1000.0)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	zin.tween_property(self, "position", world_pos, float(zoom_in_ms) / 1000.0)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	# Phase 2: hold.
	_seq.tween_interval(float(hold_ms) / 1000.0)
	# Phase 3: zoom out + recenter.
	var zout := _seq.parallel()
	zout.tween_property(self, "zoom", Vector2(rest_zoom, rest_zoom), float(zoom_out_ms) / 1000.0)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	zout.tween_property(self, "position", rest_position, float(zoom_out_ms) / 1000.0)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func reset_to_rest(dur_ms: int = 300) -> void:
	if _seq != null and _seq.is_valid():
		_seq.kill()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "zoom", Vector2(rest_zoom, rest_zoom), float(dur_ms) / 1000.0)
	tw.tween_property(self, "position", rest_position, float(dur_ms) / 1000.0)

# Brief screen-shake for IMPACT phase. Layered on top of the cinematic
# tween — uses offset rather than position so the zoom-out tween isn't
# clobbered.
func shake(duration_ms: int = 240, magnitude: float = 12.0) -> void:
	var t := 0.0
	var dur := float(duration_ms) / 1000.0
	while t < dur:
		await get_tree().process_frame
		t += get_process_delta_time()
		var falloff := 1.0 - (t / dur)
		offset = Vector2(randf_range(-magnitude, magnitude), randf_range(-magnitude, magnitude)) * falloff
	offset = Vector2.ZERO
