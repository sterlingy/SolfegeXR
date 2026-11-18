extends TestCase
## Latency check: finds beeps in mic frames on another clock.


func _simulate(delay: float, offset: float, noise := 0.001, miss := []) -> Dictionary:
	var e := SynthEngine.new(48000.0)
	var lc := LatencyCheck.new()
	lc.start(e)
	# Mic frames on their own clock: mic_time = synth_time - offset.
	var frames: Array[PitchFrame] = []
	var t := 0.0
	while t < lc.beep_times[-1] + 0.8:
		var hz := 0.0
		var rms := noise
		var conf := 0.2
		for i in lc.beep_times.size():
			var b: float = lc.beep_times[i] + delay
			if i not in miss and t >= b and t < b + LatencyCheck.BEEP_SECONDS:
				hz = MusicKey.midi_to_hz(LatencyCheck.BEEP_MIDI)
				rms = 0.05
				conf = 0.95
		frames.append(PitchFrame.new(t - offset, hz, conf, rms))
		t += 1.0 / 187.5
	lc.add_frames(frames, offset)
	return lc.result()


func test_measures_delay_across_clocks() -> void:
	var r := _simulate(0.085, 12.3)
	assert_eq(r.heard, LatencyCheck.BEEPS)
	assert_near(r.round_trip_ms, 85.0, 6.0)


func test_some_beeps_missed() -> void:
	var r := _simulate(0.06, -3.0, 0.001, [1, 4])
	assert_eq(r.heard, LatencyCheck.BEEPS - 2)
	assert_near(r.round_trip_ms, 60.0, 6.0)


func test_nothing_heard() -> void:
	var lc := LatencyCheck.new()
	lc.start(SynthEngine.new(48000.0))
	var r := lc.result()
	assert_eq(r.round_trip_ms, -1.0)
	assert_true(LatencyCheck.describe(r, 20.0).begins_with("I couldn't hear"))


func test_description() -> void:
	var text := LatencyCheck.describe({heard = 6, beeps = 6, round_trip_ms = 70.0, spread_ms = 4.0}, 30.0)
	assert_true(text.contains("70 ms"), text)
	assert_true(text.contains("about 40 ms (great)"), text)
