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
	var ex := Curriculum.exercises_for(Skills.Id.PITCH_MATCH, 0)[4]  # Find do
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


func test_no_headphones_means_silence_while_singing() -> void:
	var profile := LearnerProfile.new()
	profile.has_headphones = false
	var ex := Curriculum.exercises_for(Skills.Id.STEPS, 0)[0]
	ex.reference = Exercise.Reference.ALONG
	var engine := SynthEngine.new(48000.0)
	var s := PracticeSession.new(ex, profile, 1.0)
	s.play_cadence = false
	var saw_listen := [false]
	var sing_audio := [0.0]
	s.phase_changed.connect(func(p): if p == PracticeSession.Phase.LISTEN: saw_listen[0] = true)
	s.start(engine)
	var fake := FakePitchSource.new()
	fake.start()
	var t := 0.0
	while s.phase != PracticeSession.Phase.RESULT and t < 30.0:
		var block := engine.render(800)
		if s.phase == PracticeSession.Phase.SING:
			for v in block:
				sing_audio[0] = maxf(sing_audio[0], absf(v))
		fake.advance(800 / 48000.0)
		s.update(fake.poll(), fake.now())
		t += 800 / 48000.0
	assert_true(saw_listen[0], "sing-along reference plays first instead")
	assert_true(sing_audio[0] < 0.01, "speakers quiet while singing: peak %s" % sing_audio[0])
	fake.free()


func test_headphones_keep_drone_and_guide() -> void:
	var profile := LearnerProfile.new()
	profile.has_headphones = true
	var ex := Curriculum.exercises_for(Skills.Id.STEPS, 0)[0]
	ex.reference = Exercise.Reference.ALONG
	var engine := SynthEngine.new(48000.0)
	var s := PracticeSession.new(ex, profile, 1.0)
	s.play_cadence = false
	var peak := 0.0
	s.start(engine)
	var fake := FakePitchSource.new()
	fake.start()
	var t := 0.0
	while s.phase != PracticeSession.Phase.RESULT and t < 30.0:
		var block := engine.render(800)
		if s.phase == PracticeSession.Phase.SING:
			for v in block:
				peak = maxf(peak, absf(v))
		fake.advance(800 / 48000.0)
		s.update(fake.poll(), fake.now())
		t += 800 / 48000.0
	assert_true(peak > 0.05, "guide + drone audible with headphones: %s" % peak)
	fake.free()


func test_melody_has_a_three_second_countdown() -> void:
	var profile := LearnerProfile.new()
	var ex := Curriculum.exercises_for(Skills.Id.STEPS, 0)[0]
	var s := PracticeSession.new(ex, profile, 1.0)
	assert_near(s.count_in_seconds(), 3.0, 0.001)


func test_metronome_ticks_on_the_beat_through_the_countdown_and_song() -> void:
	var profile := LearnerProfile.new()
	profile.metronome = true
	var ex := Curriculum.exercises_for(Skills.Id.STEPS, 0)[0]
	var engine := SynthEngine.new(48000.0)
	var s := PracticeSession.new(ex, profile, 1.0)
	s.play_cadence = false
	s.start(engine)
	# Ride through LISTEN into COUNT_IN.
	var guard := 0
	while s.phase != PracticeSession.Phase.COUNT_IN and guard < 2000:
		engine.render(800)
		s.update([] as Array[PitchFrame], engine.time())
		guard += 1
	assert_eq(s.phase, PracticeSession.Phase.COUNT_IN)
	var downbeat := engine.time() + s.count_in_left()
	var ticks := []
	for v in engine._voices:
		if v.kind == SynthEngine.Kind.CLICK:
			ticks.append(v.start / engine.rate - downbeat)
	var beat := s.beat_seconds()
	assert_true(ticks.size() >= int(3.0 / beat) + int(s.length_seconds() / beat) - 1, "ticks: %d" % ticks.size())
	assert_true(ticks.min() >= -3.0, "starts inside the countdown")
	assert_true(ticks.max() < s.length_seconds(), "stops at the end")
	for t in ticks:
		var off := fposmod(t, beat)
		assert_true(off < 0.002 or beat - off < 0.002, "on the beat: %f" % t)


func test_no_ticks_without_the_metronome() -> void:
	var profile := LearnerProfile.new()
	var ex := Curriculum.exercises_for(Skills.Id.STEPS, 0)[0]
	var engine := SynthEngine.new(48000.0)
	var s := PracticeSession.new(ex, profile, 1.0)
	s.play_cadence = false
	s.start(engine)
	var guard := 0
	while s.phase != PracticeSession.Phase.SING and guard < 4000:
		engine.render(800)
		s.update([] as Array[PitchFrame], engine.time())
		guard += 1
	assert_eq(engine._voices.filter(func(v): return v.kind == SynthEngine.Kind.CLICK).size(), 0)


func test_metronome_ticks_are_ignored_by_the_detector() -> void:
	var engine := SynthEngine.new(48000.0)
	for i in 8:
		engine.note(96 if i % 4 == 0 else 91, 0.05 + i * 0.25, 0.015, SynthEngine.Kind.CLICK, 0.7)
	var audio := engine.render(48000 * 2)
	var voiced := 0
	for f in YinDetector.analyze(audio, 48000.0):
		if f.confidence >= 0.6 and f.frequency > 0.0:
			voiced += 1
	assert_true(voiced <= 2, "ticks read as pitch in %d frames" % voiced)


func test_metronome_can_be_turned_on_mid_song() -> void:
	var profile := LearnerProfile.new()
	var ex := Curriculum.exercises_for(Skills.Id.STEPS, 0)[0]
	var engine := SynthEngine.new(48000.0)
	var s := PracticeSession.new(ex, profile, 1.0)
	s.play_cadence = false
	s.start(engine)
	var guard := 0
	while s.phase != PracticeSession.Phase.SING and guard < 4000:
		engine.render(800)
		s.update([] as Array[PitchFrame], engine.time())
		guard += 1
	s.set_metronome(true)
	var ticks := engine._voices.filter(func(v): return v.kind == SynthEngine.Kind.CLICK)
	assert_true(ticks.size() > 0, "ticks scheduled for the rest of the song")
	for v in ticks:
		assert_true(v.start / engine.rate >= engine.time(), "none in the past")
	s.set_metronome(false)
	engine.render(4800)
	assert_eq(engine._voices.filter(func(v): return v.kind == SynthEngine.Kind.CLICK and v.start / engine.rate < engine.time()).size(), 0, "silenced")
