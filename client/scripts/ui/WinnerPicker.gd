# WinnerPicker.gd — agency-aware target+action dialog.
#
# FINAL_GOAL §C10 / §H3 / §K4:
#   - Surfaces when the local human wins AND has agency to make a choice
#     (≥ 2 eligible targets OR meaningful action choice).
#   - Holds for up to 5s (PICKER_AUTO_PICK_MS); on timeout, emits a null
#     pair so server falls back to the engine's auto-pick. Server-side
#     budget is 9s (WINNER_CHOICE_BUDGET_MS); we cap UI hold at 5s so
#     there's a 4s safety margin for in-flight roundtrips.
#   - Three actions: 扒裤衩 (PULL_PANTS), 咔嚓 (CHOP), 穿好裤衩
#     (PULL_OWN_PANTS_UP). S-345: visible labels are CJK now that the
#     bundled NotoSansSC font (S-332) ships with the HTML5 build, so
#     winners read the rhyme in its native script at the most critical
#     interactive moment.

extends Control

signal winner_choice_made(target, action)

@onready var _target_list: VBoxContainer = $Center/Panel/V/Targets/List
@onready var _action_pull: Button = $Center/Panel/V/Actions/Pull
@onready var _action_chop: Button = $Center/Panel/V/Actions/Chop
@onready var _action_self: Button = $Center/Panel/V/Actions/Self
@onready var _countdown: Label = $Center/Panel/V/Countdown
@onready var _title: Label = $Center/Panel/V/Title

var _selected_target = null
var _selected_action: String = ""
var _hold_timer: float = 0.0
var _open: bool = false
var _eligible_targets: Array = []
var _allow_self: bool = false
# pid -> Button mapping so _pick_target can re-style the selected chip
# without rebuilding the whole row. Reset every open().
var _target_buttons: Dictionary = {}
# pid -> display nickname so the title can use the human-readable name
# rather than the opaque pid hash.
var _target_nicks: Dictionary = {}

func _ready() -> void:
	visible = false
	_action_pull.pressed.connect(func(): _pick_action("PULL_PANTS"))
	_action_chop.pressed.connect(func(): _pick_action("CHOP"))
	_action_self.pressed.connect(func(): _pick_action("PULL_OWN_PANTS_UP"))

func open(prompt: Dictionary) -> void:
	# §C10 / S-316: server schema (server/src/rooms/Room.ts:453,
	# WinnerChoicePrompt.candidates) is the canonical field.
	# `eligibleTargets` / `targets` are kept as legacy fallbacks for
	# any in-flight payloads from older builds.
	if prompt.has("candidates"):
		_eligible_targets = prompt["candidates"]
	elif prompt.has("eligibleTargets"):
		_eligible_targets = prompt["eligibleTargets"]
	elif prompt.has("targets"):
		_eligible_targets = prompt["targets"]
	else:
		_eligible_targets = []
	_allow_self = bool(prompt.get("canSelfRestore", false))
	_selected_target = null
	_selected_action = ""
	_title.text = "你赢了！选个倒霉蛋"
	# Refresh target list.
	for c in _target_list.get_children():
		c.queue_free()
	# Track buttons so _pick_target can highlight the active selection.
	_target_buttons.clear()
	_target_nicks.clear()
	for t in _eligible_targets:
		var btn := Button.new()
		var is_dict: bool = typeof(t) == TYPE_DICTIONARY
		var nick: String = str(t.get("nickname", "?")) if is_dict else str(t)
		var pid: String = str(t.get("id", "")) if is_dict else str(t)
		var stage_str: String = str(t.get("stage", "")) if is_dict else ""
		# Annotate stage so the human can read at-a-glance whether the
		# target is clothed (扒裤衩) or already pants-down (咔嚓).
		var label: String = nick
		if stage_str == "ALIVE_PANTS_DOWN":
			label = "%s  (光屁股)" % nick
		elif stage_str == "ALIVE_CLOTHED":
			label = "%s  (穿着)" % nick
		btn.text = label
		btn.custom_minimum_size = Vector2(220, 48)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(func(): _pick_target(pid))
		_target_list.add_child(btn)
		_target_buttons[pid] = btn
		_target_nicks[pid] = nick
	_action_self.visible = _allow_self
	_open = true
	_hold_timer = float(Timing.PICKER_AUTO_PICK_MS) / 1000.0
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	set_process(true)

func close() -> void:
	_open = false
	set_process(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.16)
	tw.tween_callback(func(): visible = false)

func _process(delta: float) -> void:
	if not _open:
		return
	_hold_timer -= delta
	_countdown.text = "%.1f 秒后自动出手" % max(_hold_timer, 0.0)
	if _hold_timer <= 0.0:
		_open = false
		winner_choice_made.emit(null, null)

func _pick_target(pid: String) -> void:
	_selected_target = pid
	# Re-style every button so the active chip is visually distinct
	# from the unselected ones. Highlight = bright yellow border, dim
	# the rest. The user gets unambiguous feedback that their click
	# registered.
	for tpid in _target_buttons.keys():
		var b: Button = _target_buttons[tpid]
		if tpid == pid:
			b.modulate = Color(1.0, 0.95, 0.55, 1.0)
		else:
			b.modulate = Color(1.0, 1.0, 1.0, 0.6)
	var nick: String = _target_nicks.get(pid, pid)
	_title.text = "目标：%s — 选招式" % nick

func _pick_action(action: String) -> void:
	_selected_action = action
	if action == "PULL_OWN_PANTS_UP":
		# Self-action — target must be self; we leave target unset and
		# server treats null target + self-action as the canonical
		# self-restore.
		_open = false
		winner_choice_made.emit(null, action)
		return
	# §C10 / S-316: do NOT auto-resolve when no target is selected.
	# Even with a single candidate, the human must consciously pick so
	# the agency moment is preserved. The 5-second timeout still falls
	# back to the engine auto-pick if they never click anything.
	if _selected_target == null:
		_title.text = "先选个倒霉蛋"
		_title.modulate = Color(1.0, 0.5, 0.5, 1.0)
		var tw := create_tween()
		tw.tween_property(_title, "modulate", Color(1, 0.94, 0.62, 1), 0.6)
		return
	_open = false
	winner_choice_made.emit(_selected_target, action)
