# Clouds.gd — S-370 §H2.5 ambient motion.
#
# Drives 3 painted-cloud Polygon2D children left-to-right at a slow
# pan speed so the sky reads as alive instead of flat. Wraps around
# when a cloud passes the right edge so the loop is seamless.
#
# Procedural-only — clouds are stylized lumpy polygons, no image dep.

extends Node2D

const _SPEED := 14.0       # px/sec
const _LEFT := -2200.0
const _RIGHT := 2200.0

func _process(delta: float) -> void:
	for c in get_children():
		if c is Node2D:
			var n: Node2D = c
			n.position.x += _SPEED * delta * n.get_meta("rate", 1.0)
			if n.position.x > _RIGHT:
				n.position.x = _LEFT
