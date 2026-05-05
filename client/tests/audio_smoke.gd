# client/tests/audio_smoke.gd — smoke-test the audio asset pipeline.
#
# Run via:
#   godot --headless --path client --script tests/audio_smoke.gd --quit
#
# Asserts that every named SFX slot and BGM variant resolves to a non-null
# AudioStreamWAV via the same ResourceLoader path Audio.gd uses, and that
# BGM streams come back with loop_mode == 1 (forward loop).

extends SceneTree

const SFX_NAMES := ["tap", "reveal", "pull", "chop", "dodge", "thud", "victory", "defeat"]
const BGM_NAMES := ["lobby", "battle", "victory"]

func _init() -> void:
	var failures: Array[String] = []

	for sfx_name in SFX_NAMES:
		var path := "res://assets/audio/sfx/%s.wav" % sfx_name
		if not ResourceLoader.exists(path):
			failures.append("SFX missing: %s" % path)
			continue
		var stream: AudioStream = load(path)
		if stream == null:
			failures.append("SFX null stream: %s" % path)
			continue
		print("  ok sfx %s  -> %s  length=%.3fs" % [
			sfx_name, stream.get_class(), stream.get_length()
		])

	for bgm_name in BGM_NAMES:
		var path := "res://assets/audio/bgm/%s.wav" % bgm_name
		if not ResourceLoader.exists(path):
			failures.append("BGM missing: %s" % path)
			continue
		var stream: AudioStream = load(path)
		if stream == null:
			failures.append("BGM null stream: %s" % path)
			continue
		# AudioStreamWAV.loop_mode: 0 = disabled, 1 = forward, 2 = pingpong, 3 = backward.
		var loop_ok := false
		var loop_mode_val := -1
		if stream is AudioStreamWAV:
			loop_mode_val = (stream as AudioStreamWAV).loop_mode
			loop_ok = loop_mode_val == AudioStreamWAV.LOOP_FORWARD
		print("  ok bgm %s  -> %s  length=%.3fs  loop_mode=%d  looping=%s" % [
			bgm_name, stream.get_class(), stream.get_length(),
			loop_mode_val, str(loop_ok)
		])
		if not loop_ok:
			failures.append("BGM not looping: %s" % path)

	if failures.is_empty():
		print("audio_smoke: PASS (8 sfx + 3 bgm)")
		quit(0)
	else:
		for f in failures:
			push_error(f)
		print("audio_smoke: FAIL")
		quit(1)
