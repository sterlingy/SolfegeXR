extends TestCase
## Detector accuracy on synthetic voice-like tones, and WAV round trip.

const RATE := 48000


func test_detects_range_of_voices() -> void:
	for hz in [82.4, 196.0, 440.0, 880.0]:
		var frames := YinDetector.analyze(TestHelpers.voice(hz, 0.15), RATE, 256)
		assert_true(frames.size() > 5, "frames for %s" % hz)
		var cents := 1200.0 * log(TestHelpers.median_hz(frames) / hz) / log(2.0)
		assert_near(cents, 0.0, 5.0, "cents error at %s Hz" % hz)


func test_44k1_input() -> void:
	var frames := YinDetector.analyze(TestHelpers.voice(261.6, 0.15, 44100), 44100, 256)
	assert_near(TestHelpers.median_hz(frames), 261.6, 1.0)


func test_silence_is_quiet() -> void:
	var s := PackedFloat32Array()
	s.resize(RATE / 5)
	for i in s.size():
		s[i] = randf_range(-0.001, 0.001)
	for f in YinDetector.analyze(s, RATE, 512):
		assert_true(f.rms < 0.004, "silence rms %s" % f.rms)


func test_wav_round_trip() -> void:
	var path := "user://test_tone.wav"
	assert_eq(AudioIO.save_wav(path, TestHelpers.voice(220.0, 0.2), RATE), OK)
	var src := WavPitchSource.new()
	src.path = path
	assert_true(src.load_now(), "load")
	assert_near(TestHelpers.median_hz(src.all_frames()), 220.0, 1.0)
	src.free()


func test_native_matches_gdscript() -> void:
	if not YinDetector.has_native():
		print("        (skipped: YinNative not built; see native/README.md)")
		return
	var x := TestHelpers.voice(196.0, 0.3)
	var native := YinDetector.analyze(x, RATE, 256)
	var gd := YinDetector.analyze_gdscript(x, RATE, 256)
	assert_eq(native.size(), gd.size(), "frame count")
	for i in mini(native.size(), gd.size()):
		var a := native[i]
		var b := gd[i]
		if absf(a.time - b.time) > 1e-4 or absf(a.frequency - b.frequency) > 0.01 \
				or absf(a.confidence - b.confidence) > 1e-3 or absf(a.rms - b.rms) > 1e-4:
			fail("frame %d: native %s/%s/%s/%s vs gdscript %s/%s/%s/%s" % [i, a.time, a.frequency,
				a.confidence, a.rms, b.time, b.frequency, b.confidence, b.rms])
			return


func test_native_streaming_matches_offline() -> void:
	if not YinDetector.has_native():
		return
	var x := TestHelpers.voice(330.0, 0.25)
	var native: Object = ClassDB.instantiate("YinNative")
	var whole: PackedFloat32Array = native.call("analyze", x, RATE, 128)
	native.call("configure", RATE, 128)
	var streamed := PackedFloat32Array()
	for start in range(0, x.size(), 128):  # 128-sample blocks, like a mic callback
		streamed.append_array(native.call("push", x.slice(start, start + 128)))
	assert_eq(streamed.size(), whole.size())
	assert_eq(streamed, whole)
