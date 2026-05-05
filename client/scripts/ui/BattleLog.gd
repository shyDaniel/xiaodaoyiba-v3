# BattleLog.gd — right-rail timestamped log of round events.
#
# FINAL_GOAL §C8 — color-coded verb badges. The CN verb roster
# (扒/砍/闪/平/死/穿) is rendered as Latin short tags in the live HTML5
# build (S-192) so the log stays legible without a CJK system font:
#   PULL yellow, CHOP red, DODGE cyan, TIE gray, DEAD purple, RESTORE cyan-blue.
# Both the CN single-char keys (in case server NARRATION ever flows
# through to the rail unchanged) and the Latin short tags map to the
# same color, so call sites can pass either.

extends PanelContainer

const VERB_COLORS := {
	# CN keys — kept so server NARRATION verbs still color-badge if they
	# ever flow through to the rail unchanged.
	"扒": Color(1.0, 0.84, 0.2, 1),
	"砍": Color(0.92, 0.32, 0.28, 1),
	"闪": Color(0.36, 0.86, 0.94, 1),
	"平": Color(0.6, 0.62, 0.66, 1),
	"死": Color(0.66, 0.42, 0.94, 1),
	"穿": Color(0.32, 0.74, 0.94, 1),
	# Latin short-tag keys — used by EffectPlayer's Latin log composer.
	"PULL": Color(1.0, 0.84, 0.2, 1),
	"CHOP": Color(0.92, 0.32, 0.28, 1),
	"DODGE": Color(0.36, 0.86, 0.94, 1),
	"TIE": Color(0.6, 0.62, 0.66, 1),
	"DEAD": Color(0.66, 0.42, 0.94, 1),
	"RESTORE": Color(0.32, 0.74, 0.94, 1),
}

# Map CN verb tags emitted by shared/server NARRATION effects to the Latin
# short tags rendered in the live HTML5 log. EffectPlayer.gd uses this to
# translate incoming server narration verbs before painting the badge.
const CN_TO_LATIN_VERB := {
	"扒": "PULL",
	"砍": "CHOP",
	"闪": "DODGE",
	"平": "TIE",
	"死": "DEAD",
	"穿": "RESTORE",
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
