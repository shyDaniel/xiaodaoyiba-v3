# WinnerPicker.gd — agency-aware target+action dialog.
#
# FINAL_GOAL §C10 / §H3 / §K4:
#   - Surfaces when the local human wins AND has agency to make a choice
#     (≥ 2 eligible targets OR meaningful action choice).
#   - Holds for up to 5s (PICKER_AUTO_PICK_MS); on timeout, emits a null
#     pair so server falls back to the engine's auto-pick. Server-side
#     budget is 9s (WINNER_CHOICE_BUDGET_MS); we cap UI hold at 5s so
#     there's a 4s safety margin for in-flight roundtrips.
#   - Three actions: 扒裤衩 (PULL_PANTS), 咔嚓 (CHOP), 穿好裤衩 (PULL_OWN_PANTS_UP).

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

func _ready() -> void:
	visible = false
	_action_pull.pressed.connect(func(): _pick_action("PULL_PANTS"))
	_action_chop.pressed.connect(func(): _pick_action("CHOP"))
	_action_self.pressed.connect(func(): _pick_action("PULL_OWN_PANTS_UP"))

func open(prompt: Dictionary) -> void:
	_eligible_targets = prompt.get("eligibleTargets", prompt.get("targets", []))
	_allow_self = bool(prompt.get("canSelfRestore", false))
	_selected_target = null
	_selected_action = ""
	_title.text = "你赢了！选个目标吧"
	# Refresh target list.
	for c in _target_list.get_children():
		c.queue_free()
	for t in _eligible_targets:
		var btn := Button.new()
		var nick := str(t.get("nickname", "?")) if typeof(t) == TYPE_DICTIONARY else str(t)
		var pid := str(t.get("id", "")) if typeof(t) == TYPE_DICTIONARY else str(t)
		btn.text = nick
		btn.custom_minimum_size = Vector2(120, 48)
		btn.pressed.connect(func(): _pick_target(pid))
		_target_list.add_child(btn)
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
	_countdown.text = "%.1fs · 不选则自动" % max(_hold_timer, 0.0)
	if _hold_timer <= 0.0:
		_open = false
		winner_choice_made.emit(null, null)

func _pick_target(pid: String) -> void:
	_selected_target = pid
	_title.text = "目标已选：%s · 选个动作" % pid

func _pick_action(action: String) -> void:
	_selected_action = action
	if action == "PULL_OWN_PANTS_UP":
		# Self-action — target must be self; we leave target unset and
		# server treats null target + self-action as the canonical
		# self-restore.
		_open = false
		winner_choice_made.emit(null, action)
		return
	if _selected_target == null and _eligible_targets.size() == 1:
		var t = _eligible_targets[0]
		var pid = str(t.get("id", "")) if typeof(t) == TYPE_DICTIONARY else str(t)
		_selected_target = pid
	if _selected_target == null:
		_title.text = "先选个目标"
		return
	_open = false
	winner_choice_made.emit(_selected_target, action)
