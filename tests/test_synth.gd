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


func _peak(x: PackedFloat32Array) -> float:
	var p := 0.0
	for v in x:
		p = maxf(p, absf(v))
	return p


func test_every_sound_has_the_right_pitch() -> void:
	for t in SynthEngine.Timbre.values():
		for midi in [45, 57, 69]:  # A2, A3, A4
			var e := SynthEngine.new(RATE)
			e.timbre = t
			e.note(midi, 0.0, 1.0)
			var x := e.render(int(RATE * 1.0))
			var hz := TestHelpers.median_hz(YinDetector.analyze(x, RATE, 512))
			var want := MusicKey.midi_to_hz(midi)
			var cents := 1200.0 * log(hz / want) / log(2.0)
			assert_near(cents, 0.0, 8.0, "%s at midi %d" % [SynthEngine.TIMBRE_NAMES[t], midi])


func test_every_sound_is_audible_and_never_clips() -> void:
	var key := MusicKey.new(0, MusicKey.Mode.IONIAN)
	for t in SynthEngine.Timbre.values():
		var e := SynthEngine.new(RATE)
		e.timbre = t
		var length := e.cadence(key, 60)
		e.set_drone(60)
		e.note(72, 0.1, 2.0)
		var x := e.render(int(RATE * length))
		var p := _peak(x)
		assert_true(p < 1.0 and p > 0.1, "%s peak %s" % [SynthEngine.TIMBRE_NAMES[t], p])


func test_no_partials_above_8_khz() -> void:
	for t in SynthEngine.Timbre.values():
		var parts := SynthEngine.partials(t, SynthEngine.Kind.VOICE, 880.0, RATE)
		assert_true(parts.size() * 880.0 <= 8000.0, "%s: %d partials" % [SynthEngine.TIMBRE_NAMES[t], parts.size()])


## Writes build/synth_parity.json: the notes the web worklet would receive and
## what GDScript renders for them. `node tests/synth_parity.mjs` renders the
## same notes through web/synth_worklet.js and compares sample by sample.
func test_export_parity_scenario() -> void:
	var cases := []
	for t in SynthEngine.Timbre.values():
		var sink := TestSynthSink.new()
		var web := SynthEngine.new(RATE)
		web.sink = sink
		var local := SynthEngine.new(RATE)
		for e in [web, local]:
			e.timbre = t
			e.note(57, 0.01, 0.5)                                       # voice with vibrato
			e.note(60, 0.6, 0.4, SynthEngine.Kind.VOICE, 0.3, 64.0)     # glide
			e.note(48, 0.05, -1.0, SynthEngine.Kind.DRONE, 0.07)
			e.note(64, 0.2, 0.6, SynthEngine.Kind.PAD, 0.09)
			e.note(0, 0.3, 0.03, SynthEngine.Kind.CLICK, 0.2)
		var release_at := 128 * 700   # 1.87 s, on a block boundary
		var x := local.render(release_at)
		local.release_all()
		x.append_array(local.render(int(RATE * 0.6)))
		cases.append({timbre = SynthEngine.TIMBRE_NAMES[t], notes = sink.notes, release_at = release_at,
			samples = Array(x)})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var f := FileAccess.open("res://build/synth_parity.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({rate = RATE, cases = cases}))
	f.close()
	assert_true(cases.size() == SynthEngine.Timbre.size())
