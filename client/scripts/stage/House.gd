# House.gd — small visual controller for one player's house.
# Exposes set_player_color() to tint the roof and set_label() to write
# the owner's nickname above the roof. The damage marks group is
# revealed when the house's owner is chopped (CHOP/SET_STAGE→DEAD).

extends Node2D

@onready var _roof: Polygon2D = $Roof
@onready var _name_label: Label = $NameLabel
@onready var _damage: Node2D = $DamageMarks

func set_player_color(c: Color) -> void:
	if _roof != null:
		_roof.color = c

func set_label(s: String) -> void:
	if _name_label != null:
		_name_label.text = s

func show_damage() -> void:
	if _damage != null:
		_damage.visible = true
