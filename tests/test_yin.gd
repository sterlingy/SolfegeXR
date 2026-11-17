extends TestCase
## Detector accuracy on synthetic voice-like tones, and WAV round trip.

const RATE := 48000


static func voice(hz: float, seconds: float, rate := RATE, noise := 0.005) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * rate))
	var ph := 0.0
	for i in out.size():
		ph += hz / rate
		var v := 0.0
		for k in range(1, 9):
			v += sin(TAU * k * ph) / (k * k * 0.7 + 0.3)
		out[i] = 0.1 * v + noise * randf_range(-0.5, 0.5)
	return out


static func median_hz(frames: Array[PitchFrame]) -> float:
	var hz: Array[float] = []
	for f in frames:
		if f.confidence > 0.8:
			hz.append(f.frequency)
	if hz.is_empty():
		return NAN
	hz.sort()
	return hz[hz.size() / 2]


func test_detects_range_of_voices() -> void:
	for hz in [82.4, 196.0, 440.0, 880.0]:
		var frames := YinDetector.analyze(voice(hz, 0.15), RATE, 256)
		assert_true(frames.size() > 5, "frames for %s" % hz)
		var cents := 1200.0 * log(median_hz(frames) / hz) / log(2.0)
		assert_near(cents, 0.0, 5.0, "cents error at %s Hz" % hz)


func test_44k1_input() -> void:
	var frames := YinDetector.analyze(voice(261.6, 0.15, 44100), 44100, 256)
	assert_near(median_hz(frames), 261.6, 1.0)


func test_silence_is_quiet() -> void:
	var s := PackedFloat32Array()
	s.resize(RATE / 5)
	for i in s.size():
		s[i] = randf_range(-0.001, 0.001)
	for f in YinDetector.analyze(s, RATE, 512):
		assert_true(f.rms < 0.004, "silence rms %s" % f.rms)


func test_wav_round_trip() -> void:
	var path := "user://test_tone.wav"
	assert_eq(AudioIO.save_wav(path, voice(220.0, 0.2), RATE), OK)
	var src := WavPitchSource.new()
	src.path = path
	assert_true(src.load_now(), "load")
	assert_near(median_hz(src.all_frames()), 220.0, 1.0)
	src.free()
