extends TestCase
## Synth renders the right pitch, starts/stops on time, never clips.

const RATE := 48000.0


func _rms(x: PackedFloat32Array, from: int, to: int) -> float:
	var s := 0.0
	for i in range(from, to):
		s += x[i] * x[i]
	return sqrt(s / maxi(1, to - from))


func test_reference_voice_pitch() -> void:
	var e := SynthEngine.new(RATE)
	e.note(57, 0.0, 1.0)  # A3 = 220 Hz
	var x := e.render(int(RATE * 1.0))
	var frames := YinDetector.analyze(x, RATE, 512)
	var hz := TestHelpers.median_hz(frames)
	var cents := 1200.0 * log(hz / 220.0) / log(2.0)
	assert_near(cents, 0.0, 6.0, "median pitch")  # vibrato is ±12 c around 220


func test_note_timing() -> void:
	var e := SynthEngine.new(RATE)
	e.note(60, 0.25, 0.25)
	var x := e.render(int(RATE * 1.0))
	assert_true(_rms(x, 0, int(RATE * 0.24)) < 1e-6, "silent before start")
	assert_true(_rms(x, int(RATE * 0.3), int(RATE * 0.45)) > 0.05, "sounding")
	assert_true(_rms(x, int(RATE * 0.7), int(RATE * 1.0)) < 1e-6, "silent after release")
	assert_eq(e.active_voice_count(), 0, "voice freed")


func test_drone_is_quiet_and_stops() -> void:
	var e := SynthEngine.new(RATE)
	e.set_drone(57)
	var x := e.render(int(RATE * 0.5))
	var level := _rms(x, int(RATE * 0.35), int(RATE * 0.5))
	assert_true(level > 0.01 and level < 0.12, "drone level %s" % level)
	e.set_drone(-1)
	e.render(int(RATE * 0.6))
	assert_eq(e.active_voice_count(), 0)


func test_cadence_never_clips() -> void:
	var e := SynthEngine.new(RATE)
	var key := MusicKey.new(0, MusicKey.Mode.AEOLIAN)
	var length := e.cadence(key, 60)
	e.set_drone(60)
	e.note(60, 0.1, 2.0)
	var x := e.render(int(RATE * length))
	var peak := 0.0
	for v in x:
		peak = maxf(peak, absf(v))
	assert_true(peak < 1.0, "peak %s" % peak)
	assert_true(peak > 0.1, "audible")


func test_sequence_tempo_scales_length() -> void:
	var e := SynthEngine.new(RATE)
	var notes := [{midi = 60, start = 0.0, duration = 0.5}, {midi = 62, start = 0.5, duration = 0.5}]
	assert_near(e.sequence(notes, 1.0), 1.0, 0.001)
	assert_near(e.sequence(notes, 0.5), 2.0, 0.001)
