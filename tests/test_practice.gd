extends TestCase
## End-to-end practice flow and range test, headless, with the demo singer.

const FPS := 60.0


func before_each() -> void:
	LearnerProfile.save_path = "user://test_practice_profile.json"


func _run(session: PracticeSession, fake: FakePitchSource, engine: SynthEngine, max_seconds := 30.0) -> Array:
	var phases := []
	session.phase_changed.connect(func(p):
		phases.append(p)
		if p == PracticeSession.Phase.SING:
			fake.follow(session.targets, session.sing_origin_source))
	session.start(engine)
	var t := 0.0
	while session.phase != PracticeSession.Phase.RESULT and t < max_seconds:
		engine.render(int(engine.rate / FPS))
		fake.advance(1.0 / FPS)
		session.update(fake.poll(), fake.now())
		t += 1.0 / FPS
	return phases


func test_full_exercise_flow_scores_and_records() -> void:
	var profile := LearnerProfile.new()
	var ex := Curriculum.exercises_for(Skills.Id.STEPS, 0)[0]  # do re mi re do
	var fake := FakePitchSource.new()
	fake.miss_chance = 0.0
	fake.quiet()
	fake.start()
	var engine := SynthEngine.new(48000.0)
	var s := PracticeSession.new(ex, profile, 1.0)
	var P := PracticeSession.Phase
	var phases := _run(s, fake, engine)
	assert_eq(phases, [P.CADENCE, P.LISTEN, P.COUNT_IN, P.SING, P.RESULT])
	assert_eq(s.results.size(), 5)
	var landed := s.results.filter(func(r): return r.landed()).size()
	assert_eq(landed, 5, PracticeSession.summary(s.results, ex.key))
	assert_eq(profile.progress(Skills.Id.STEPS).total_landed, 5, "recorded")
	assert_eq(PracticeSession.summary(s.results, ex.key), "You landed every note!")
	fake.free()


func test_wrong_notes_get_feedback() -> void:
	var profile := LearnerProfile.new()
	var ex := Curriculum.exercises_for(Skills.Id.STEPS, 0)[0]
	var fake := FakePitchSource.new()
	fake.miss_chance = 1.0  # every note off
	fake.quiet()
	fake.start()
	var s := PracticeSession.new(ex, profile, 1.0)
	s.play_cadence = false
	_run(s, fake, SynthEngine.new(48000.0))
	var summary := PracticeSession.summary(s.results, ex.key)
	assert_true(summary.begins_with("You landed 0 of 5"), summary)
	fake.free()


func test_slow_tempo_doubles_length() -> void:
	var profile := LearnerProfile.new()
	var ex := Curriculum.exercises_for(Skills.Id.STEPS, 0)[0]
	var normal := PracticeSession.new(ex, profile, 1.0).length_seconds()
	var slow := PracticeSession.new(ex, profile, 0.5).length_seconds()
	assert_near(slow, normal * 2.0, 0.001)


func test_warmup_not_recorded() -> void:
	var profile := LearnerProfile.new()
	var ex := Curriculum.exercises_for(Skills.Id.PITCH_MATCH, 0)[0]
	ex.record = false
	var fake := FakePitchSource.new()
	fake.miss_chance = 0.0
	fake.quiet()
	fake.start()
	var s := PracticeSession.new(ex, profile, 1.0)
	s.play_cadence = false
	_run(s, fake, SynthEngine.new(48000.0))
	assert_eq(profile.progress(Skills.Id.PITCH_MATCH).total_notes, 0)
	fake.free()


func test_range_test_from_sirens() -> void:
	var fake := FakePitchSource.new()
	fake.start()
	var rt := RangeTest.new()
	fake.siren(44, 52)
	fake.advance(6.0)
	for f in fake.poll():
		rt.add_low(f)
	fake.siren(62, 70)
	fake.advance(6.0)
	for f in fake.poll():
		rt.add_high(f)
	var r := rt.result()
	assert_true(r.x >= 45 and r.x <= 47, "low %d" % r.x)
	assert_true(r.y >= 67 and r.y <= 69, "high %d" % r.y)
	fake.free()


func test_range_test_rejects_too_narrow() -> void:
	var rt := RangeTest.new()
	for i in 40:
		rt.add_low(PitchFrame.new(i, MusicKey.midi_to_hz(55), 0.95, 0.1))
		rt.add_high(PitchFrame.new(i, MusicKey.midi_to_hz(58), 0.95, 0.1))
	assert_eq(rt.result(), Vector2i(-1, -1))
