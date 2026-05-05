# Audio.gd — autoload — SFX bus + BGM cross-fade + mute toggle.
#
# FINAL_GOAL §D1/§D2/§D3:
#   - 8 SFX slots (tap/reveal/pull/chop/dodge/thud/victory/defeat).
#   - 3 BGM variants (lobby/battle/victory) with cross-fade on phase change.
#   - Mute toggle persisted to user://settings.cfg.
#
# Asset files live in res://assets/audio/{sfx,bgm}/. Until real WAVs land
# (D-track work), we synthesize procedural placeholders at startup so the
# bus has SOMETHING to play; this is the §G fallback path.

extends Node

const SETTINGS_PATH := "user://settings.cfg"
const SFX_NAMES := ["tap", "reveal", "pull", "chop", "dodge", "thud", "victory", "defeat", "hover", "click"]
const BGM_NAMES := ["lobby", "battle", "victory"]
# S-370 §H2.7 — buttons that have been auto-wired (so we don't double-bind).
var _wired_buttons: Dictionary = {}

var muted: bool = false
var _sfx_players: Dictionary = {}      # name → AudioStreamPlayer
var _bgm_players: Dictionary = {}      # name → AudioStreamPlayer
var _current_bgm: String = ""

func _ready() -> void:
	_load_settings()
	for sfx_name in SFX_NAMES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -6.0
		add_child(p)
		_sfx_players[sfx_name] = p
		var stream := _try_load_sfx(sfx_name)
		if stream != null:
			p.stream = stream
	for bgm_name in BGM_NAMES:
		var bp := AudioStreamPlayer.new()
		bp.bus = "Master"
		bp.volume_db = -80.0   # silent until cross-faded in
		add_child(bp)
		_bgm_players[bgm_name] = bp
		var bs := _try_load_bgm(bgm_name)
		if bs != null:
			bp.stream = bs
	_apply_mute()

func play_sfx(slot: String) -> void:
	if muted:
		return
	if not _sfx_players.has(slot):
		return
	var p: AudioStreamPlayer = _sfx_players[slot]
	if p.stream == null:
		return
	p.play()

func cross_fade_bgm(target: String, dur_ms: int = 800) -> void:
	if target == _current_bgm:
		return
	_current_bgm = target
	var dur := float(dur_ms) / 1000.0
	for bgm_name in _bgm_players.keys():
		var bp: AudioStreamPlayer = _bgm_players[bgm_name]
		if bp.stream == null:
			continue
		var target_db := -6.0 if bgm_name == target else -80.0
		if bgm_name == target and not bp.playing and not muted:
			bp.play()
		var tween := create_tween()
		tween.tween_property(bp, "volume_db", target_db, dur)

func toggle_mute() -> void:
	muted = not muted
	_apply_mute()
	_save_settings()

func _apply_mute() -> void:
	for bp in _bgm_players.values():
		if muted:
			bp.stream_paused = true
		else:
			bp.stream_paused = false
	AudioServer.set_bus_mute(0, muted)

func _try_load_sfx(slot: String) -> AudioStream:
	var path := "res://assets/audio/sfx/%s.wav" % slot
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _try_load_bgm(slot: String) -> AudioStream:
	var path := "res://assets/audio/bgm/%s.ogg" % slot
	if ResourceLoader.exists(path):
		return load(path)
	var path2 := "res://assets/audio/bgm/%s.wav" % slot
	if ResourceLoader.exists(path2):
		return load(path2)
	return null

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		muted = bool(cfg.get_value("audio", "muted", false))

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "muted", muted)
	cfg.save(SETTINGS_PATH)

# S-370 §H2.7 — auto-wire hover.wav on mouse_entered + click.wav on pressed
# for every Button under `root`. Idempotent: a button only gets bound once
# even across multiple wire_tree calls. Stardew-style tactile UI feedback.
func wire_tree(root: Node) -> void:
	if root == null:
		return
	for n in _walk(root):
		if n is BaseButton:
			wire_button(n as BaseButton)

func wire_button(b: BaseButton) -> void:
	if b == null or _wired_buttons.has(b.get_instance_id()):
		return
	_wired_buttons[b.get_instance_id()] = true
	if not b.mouse_entered.is_connected(_on_btn_hover):
		b.mouse_entered.connect(_on_btn_hover)
	if not b.pressed.is_connected(_on_btn_click):
		b.pressed.connect(_on_btn_click)

func _on_btn_hover() -> void:
	play_sfx("hover")

func _on_btn_click() -> void:
	play_sfx("click")

func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
