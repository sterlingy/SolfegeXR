extends TestCase
## Sirens and slides: the exercises before single notes.

const RATE := 187.5
var V := NoteScorer.Verdict
var major := MusicKey.new(0)


## Feed frames from pitch_fn(t) -> midi (NAN = silence) for `seconds`.
func feed(scorer: SlideScorer, seconds: float, pitch_fn: Callable) -> NoteResult:
	var t := 0.0
	while t < seconds:
		var m: float = pitch_fn.call(t)
		if is_nan(m):
			scorer.add_frame(PitchFrame.new(t, 0.0, 0.1, 0.001))
		else:
			scorer.add_frame(PitchFrame.new(t, MusicKey.midi_to_hz(m), 0.95, 0.1))
		t += 1.0 / RATE
	return scorer.results()[0]


func test_wide_siren_is_praised() -> void:
	var s := SlideScorer.new(Exercise.Mode.SIREN, [])
	var r := feed(s, 6.0, func(t): return 52.0 + 5.0 * sin(TAU * t / 3.0))
	assert_eq(r.verdict, V.LANDED)
	assert_true(r.feedback().begins_with("Lovely siren"), r.feedback())


func test_flat_siren_gets_a_nudge() -> void:
	var s := SlideScorer.new(Exercise.Mode.SIREN, [])
	var r := feed(s, 6.0, func(t): return 52.0 + 0.3 * sin(TAU * t))
	assert_eq(r.verdict, V.CLOSE)
	assert_true(r.feedback().contains("swoop"), r.feedback())


func test_slide_to_found_and_held() -> void:
	var target := [{midi = 60, start = 0.0, duration = 6.0}]
	var s := SlideScorer.new(Exercise.Mode.SLIDE_TO, target)
	# Start a fifth low, slide up over 2 s, then hold.
	var r := feed(s, 6.0, func(t): return 53.0 + 7.0 * minf(1.0, t / 2.0))
	assert_eq(r.verdict, V.LANDED)
	assert_true(r.onset_seconds > 1.0 and r.onset_seconds < 2.2, "found at %.2f s" % r.onset_seconds)
	assert_true(r.feedback().contains("held it"), r.feedback())


func test_slide_to_never_reached_says_which_way() -> void:
	var target := [{midi = 60, start = 0.0, duration = 6.0}]
	var s := SlideScorer.new(Exercise.Mode.SLIDE_TO, target)
	var r := feed(s, 6.0, func(_t): return 56.0)
	assert_eq(r.verdict, V.LOW)
	assert_true(r.feedback().contains("sliding up"), r.feedback())


func test_slide_to_octave_counts() -> void:
	var target := [{midi = 60, start = 0.0, duration = 6.0}]
	var s := SlideScorer.new(Exercise.Mode.SLIDE_TO, target)
	assert_eq(feed(s, 3.0, func(_t): return 48.0).verdict, V.LANDED)


func test_follow_glide() -> void:
	var ex := Curriculum.exercises_for(Skills.Id.PITCH_MATCH, 0)[2]
	assert_eq(ex.mode, Exercise.Mode.FOLLOW)
	var targets := ex.realize(60, 1.0)
	assert_eq(targets.size(), 3, "up-glide, down-glide, final hold")
	assert_eq(targets[0].midi_end, 67)
	assert_eq(targets[1].midi_end, 60)
	var good := SlideScorer.new(Exercise.Mode.FOLLOW, targets)
	var r := feed(good, 7.0, func(t): return good.target_at(t) + 0.2 * sin(TAU * 5.5 * t))
	assert_eq(r.verdict, V.LANDED, r.feedback())
	var stuck := SlideScorer.new(Exercise.Mode.FOLLOW, targets)
	assert_eq(feed(stuck, 7.0, func(_t): return 60.0).verdict, V.CLOSE, "staying put isn't following")


func test_silence_is_no_voice() -> void:
	var s := SlideScorer.new(Exercise.Mode.SIREN, [])
	assert_eq(feed(s, 6.0, func(_t): return NAN).verdict, V.NO_VOICE)


func test_synth_glides() -> void:
	var e := SynthEngine.new(48000.0)
	e.note(57, 0.0, 2.0, SynthEngine.Kind.VOICE, 0.3, 69)  # A3 -> A4 over 2 s
	var x := e.render(96000)
	var start := TestHelpers.median_hz(YinDetector.analyze(x.slice(0, 9600), 48000.0, 512))
	var end_hz := TestHelpers.median_hz(YinDetector.analyze(x.slice(86400, 96000), 48000.0, 512))
	assert_near(start, 224.0, 8.0, "starts near A3")
	assert_near(end_hz, 430.0, 15.0, "ends near A4")


func test_practice_runs_each_slide_mode() -> void:
	var profile := LearnerProfile.new()
	for i in 4:
		var ex := Curriculum.exercises_for(Skills.Id.PITCH_MATCH, 0)[i]
		var engine := SynthEngine.new(48000.0)
		var fake := FakePitchSource.new()
		fake.miss_chance = 0.0
		fake.quiet()
		fake.start()
		var s := PracticeSession.new(ex, profile, 1.0)
		s.play_cadence = false
		s.phase_changed.connect(func(p):
			if p == PracticeSession.Phase.SING:
				if ex.mode == Exercise.Mode.SIREN:
					fake.siren(48, 62)
				else:
					fake.follow(s.targets, s.sing_origin_source))
		s.start(engine)
		var t := 0.0
		while s.phase != PracticeSession.Phase.RESULT and t < 40.0:
			engine.render(800)
			fake.advance(800 / 48000.0)
			s.update(fake.poll(), fake.now())
			t += 800 / 48000.0
		assert_eq(s.phase, PracticeSession.Phase.RESULT, "%s finished" % ex.title)
		assert_eq(s.results.size(), 1, ex.title)
		assert_eq(s.results[0].verdict, V.LANDED, "%s: %s" % [ex.title, s.results[0].feedback()])
		fake.free()
