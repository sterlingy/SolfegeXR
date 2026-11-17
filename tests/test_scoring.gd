extends TestCase
## Scoring on synthetic sung notes (no audio needed).

const RATE := 187.5  # frames per second, like the live detector
const A3 := 57
var V := NoteScorer.Verdict
var key := MusicKey.new(9, MusicKey.Mode.IONIAN)  # A major: A3 = do


## Build frames for a note. pitch_fn(t_local) -> midi offset from target.
func sing(scorer: NoteScorer, pitch_fn: Callable, voiced := true) -> NoteResult:
	var t := scorer.start_time
	while t <= scorer.start_time + scorer.duration:
		var midi: float = scorer.target_midi + pitch_fn.call(t - scorer.start_time)
		var conf := 0.95 if voiced else 0.1
		scorer.add_frame(PitchFrame.new(t, MusicKey.midi_to_hz(midi), conf, 0.1 if voiced else 0.001))
		t += 1.0 / RATE
	return scorer.result()


func vibrato(t: float) -> float:
	return 0.35 * sin(TAU * 5.5 * t)


func test_steady_with_vibrato_lands() -> void:
	var r := sing(NoteScorer.new(A3, 0.0, 1.5, key), func(t): return vibrato(t))
	assert_eq(r.verdict, V.LANDED)
	assert_near(r.median_cents, 0.0, 15.0)


func test_scoop_is_forgiven() -> void:
	var r := sing(NoteScorer.new(A3, 0.0, 1.5, key), func(t): return -2.0 * exp(-t / 0.05))
	assert_eq(r.verdict, V.LANDED)
	assert_true(r.onset_seconds < 0.2, "onset %s" % r.onset_seconds)


func test_octave_error_forgiven_with_hint() -> void:
	var r := sing(NoteScorer.new(A3, 0.0, 1.0, key), func(t): return -12.0 + vibrato(t))
	assert_eq(r.verdict, V.LANDED)
	assert_eq(r.octave_offset, -1)
	assert_true(r.feedback(key).contains("octave lower"), r.feedback(key))


func test_slightly_flat_within_tolerance() -> void:
	var r := sing(NoteScorer.new(A3, 0.0, 1.0, key), func(_t): return -0.3)
	assert_eq(r.verdict, V.LANDED)


func test_flat_beyond_tolerance_is_low() -> void:
	var r := sing(NoteScorer.new(A3, 0.0, 1.0, key), func(_t): return -0.8)
	assert_eq(r.verdict, V.LOW)
	assert_true(r.feedback().containsn("slide up"), r.feedback())


func test_half_step_neighbour_is_low_not_wrong() -> void:
	var r := sing(NoteScorer.new(A3, 0.0, 1.0, key), func(_t): return -1.0)
	assert_eq(r.verdict, V.LOW)


func test_close_band() -> void:
	var r := sing(NoteScorer.new(A3, 0.0, 1.0, key), func(_t): return 0.62)
	assert_eq(r.verdict, V.CLOSE)


func test_drift_is_not_wrong_degree() -> void:
	# Starts on pitch, sinks 1.3 semitones over 2 s.
	var r := sing(NoteScorer.new(A3, 0.0, 2.0, key), func(t): return -0.65 * t)
	assert_eq(r.verdict, V.DRIFTED_LOW)
	assert_true(r.drift_cents_per_second < -40.0, "slope %s" % r.drift_cents_per_second)


func test_wrong_degree_named_in_feedback() -> void:
	# Target mi (C#4 = 61), sang re (B3 = 59) steadily.
	var r := sing(NoteScorer.new(61, 0.0, 1.0, key), func(t): return -2.0 + vibrato(t))
	assert_eq(r.verdict, V.WRONG_DEGREE)
	assert_eq(r.sung_midi, 59)
	assert_eq(r.feedback(key), "That was re. We're looking for mi.")


func test_silence_is_no_voice() -> void:
	var r := sing(NoteScorer.new(A3, 0.0, 1.0, key), func(_t): return 0.0, false)
	assert_eq(r.verdict, V.NO_VOICE)


func test_tighter_tolerance_for_skilled() -> void:
	var s := ScoringSettings.for_skill(1.0)
	var n := NoteScorer.new(A3, 0.0, 1.0, key)
	s.apply(n)
	var r := sing(n, func(_t): return -0.35)
	assert_eq(r.verdict, V.CLOSE)


func test_phrase_routes_frames_to_notes() -> void:
	var targets := [
		{midi = 57, start = 0.0, duration = 0.5},
		{midi = 59, start = 0.5, duration = 0.5},
		{midi = 61, start = 1.0, duration = 0.5},
	]
	var p := PhraseScorer.new(targets, key)
	p.latency = 0.0
	var t := 0.0
	while t < 1.5:
		var target: int = targets[mini(int(t / 0.5), 2)].midi
		var off := -1.0 if target == 61 else 0.0  # third note sung a semitone low
		p.add_frame(PitchFrame.new(t, MusicKey.midi_to_hz(target + off), 0.95, 0.1))
		t += 1.0 / RATE
	var r := p.results()
	assert_eq(r[0].verdict, V.LANDED)
	assert_eq(r[1].verdict, V.LANDED)
	assert_true(r[2].verdict != V.LANDED, "third note should not land")
	assert_near(p.landed_fraction(), 2.0 / 3.0, 0.01)
