# BattleLog.gd — right-rail timestamped log of round events.
#
# FINAL_GOAL §C8 — color-coded verb badges:
#   扒 yellow, 砍 red, 闪 cyan, 平 gray, 死 purple, 穿 cyan-blue.
# Per-player stable name colors are applied by the caller (text already
# carries the nickname); the verb badge itself uses the table here.

extends PanelContainer

const VERB_COLORS := {
	"扒": Color(1.0, 0.84, 0.2, 1),
	"砍": Color(0.92, 0.32, 0.28, 1),
	"闪": Color(0.36, 0.86, 0.94, 1),
	"平": Color(0.6, 0.62, 0.66, 1),
	"死": Color(0.66, 0.42, 0.94, 1),
	"穿": Color(0.32, 0.74, 0.94, 1),
}

@onready var _scroll: ScrollContainer = $V/Scroll
@onready var _rows: VBoxContainer = $V/Scroll/Rows

func add_row(round_n: int, phase: String, text: String, verb: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var stamp := Label.new()
	stamp.text = "R%d.%s" % [round_n, phase]
	stamp.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72, 1))
	stamp.add_theme_font_size_override("font_size", 12)
	row.add_child(stamp)
	if verb in VERB_COLORS:
		var badge := Label.new()
		badge.text = verb
		badge.add_theme_color_override("font_color", Color(0.06, 0.07, 0.1, 1))
		var bg := StyleBoxFlat.new()
		bg.bg_color = VERB_COLORS[verb]
		bg.set_corner_radius_all(4)
		bg.set_content_margin_all(3)
		badge.add_theme_stylebox_override("normal", bg)
		badge.add_theme_font_size_override("font_size", 13)
		row.add_child(badge)
	var msg := Label.new()
	msg.text = text
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 13)
	msg.add_theme_color_override("font_color", Color(0.94, 0.95, 0.98, 1))
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(msg)
	_rows.add_child(row)
	# Glow-on-arrival per §C8.
	row.modulate = Color(1.6, 1.6, 1.6, 0)
	var tw := create_tween()
	tw.tween_property(row, "modulate", Color(1, 1, 1, 1), 0.3)
	# Auto-scroll.
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_rows.size.y)

func clear_log() -> void:
	for c in _rows.get_children():
		c.queue_free()
