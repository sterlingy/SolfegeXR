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
