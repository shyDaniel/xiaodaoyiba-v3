# HandPicker.gd — rock / paper / scissors row at bottom of Game scene.
#
# FINAL_GOAL §C9 / §H2: lets the local human player commit a throw. Lock
# state grays buttons after the first send to prevent re-submission within
# the same round.

extends Control

signal choice_made(choice: String)

@onready var _rock: Button = $H/Rock
@onready var _paper: Button = $H/Paper
@onready var _scissors: Button = $H/Scissors

var _locked: bool = false

func _ready() -> void:
	_rock.pressed.connect(func(): _emit("ROCK"))
	_paper.pressed.connect(func(): _emit("PAPER"))
	_scissors.pressed.connect(func(): _emit("SCISSORS"))

func set_locked(v: bool) -> void:
	_locked = v
	_rock.disabled = v
	_paper.disabled = v
	_scissors.disabled = v

func _emit(c: String) -> void:
	if _locked:
		return
	Audio.play_sfx("tap")
	choice_made.emit(c)
