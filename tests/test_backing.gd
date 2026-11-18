extends TestCase
## Backing track: chords that fit the melody, on the real barlines.

var C := MusicKey.new(0)


func _ode() -> SongAnalyzer.Result:
	return SongAnalyzer.analyze(MusicXmlReader.load_file("res://songs/01_ode_to_joy.musicxml"))


func test_chords_fit_ode_to_joy() -> void:
	var a := _ode()
	var t := a.targets(0, 1.0)
	var bar := 4.0 * 60.0 / a.song.tempo_bpm
	var chords := Harmonizer.chords_for(t, a.key, bar)
	assert_eq(chords.size(), 16)
	var roots := chords.map(func(c): return c.root)
	assert_eq(roots[0], 0, "bar 1 (E E F G): I")
	assert_eq(roots[2], 0, "bar 3 (C C D E): I")
	assert_eq(roots[3], 4, "bar 4 (E. D D): V")
	assert_eq(roots[7], 0, "bar 8 ends the phrase at home: I")
	assert_eq(roots[15], 0, "the song ends on I")


func test_minor_dominant_has_leading_tone() -> void:
	var a_minor := MusicKey.new(9, MusicKey.Mode.AEOLIAN)
	assert_eq(Harmonizer.chord_tones(a_minor, 4), [7, 11, 2] as Array[int], "E major in A minor: E G# B")
	assert_eq(Harmonizer.chord_tones(a_minor, 0), [0, 3, 7] as Array[int])


func test_pickup_aligns_bars() -> void:
	var a := SongAnalyzer.analyze(MusicXmlReader.load_file("res://songs/05_auld_lang_syne.musicxml"))
	var c := CourseBuilder.build(a, LearnerProfile.new())
	var whole: Exercise = c.steps.filter(func(e): return e.title == "The whole song")[0]
	assert_near(whole.bar_offset_beats, 1.0, 0.001, "one-beat pickup before the first barline")
	var ode_whole: Exercise = CourseBuilder.build(_ode(), LearnerProfile.new()).steps.filter(
		func(e): return e.title == "The whole song")[0]
	assert_near(ode_whole.bar_offset_beats, 0.0, 0.001, "Ode to Joy starts on the downbeat")


func test_backing_step_needs_headphones() -> void:
	var c := CourseBuilder.build(_ode(), LearnerProfile.new())
	var backing: Exercise = c.steps.filter(func(e): return e.skill == Skills.Id.BACKING_TRACK)[0]
	assert_true(backing.accompaniment and backing.needs_headphones)
	assert_true(Skills.Id.BACKING_TRACK in c.skills_to_learn)


func test_backing_plays_bass_and_chords_with_headphones() -> void:
	var profile := LearnerProfile.new()
	profile.has_headphones = true
	var c := CourseBuilder.build(_ode(), profile)
	var backing: Exercise = c.steps.filter(func(e): return e.skill == Skills.Id.BACKING_TRACK)[0]
	var sink := TestSynthSink.new()
	var engine := SynthEngine.new(48000.0)
	engine.sink = sink
	var s := PracticeSession.new(backing, profile, 1.0)
	s.play_cadence = false
	s.start(engine)
	var fake := FakePitchSource.new()
	fake.quiet()
	fake.start()
	var t := 0.0
	while s.phase != PracticeSession.Phase.SING and t < 10.0:
		sink.t += 0.02
		fake.advance(0.02)
		s.update(fake.poll(), fake.now())
		t += 0.02
	var pads := sink.notes.filter(func(n): return n.kind == SynthEngine.Kind.PAD)
	# 16 bars of 4/4: 2 bass notes + 2 chords of 3 notes per bar.
	assert_eq(pads.size(), 16 * (2 + 2 * 3), "pad notes scheduled")
	var first_bass: Dictionary = pads[0]
	assert_true(first_bass.hz < MusicKey.midi_to_hz(s.drone_tonic()), "bass sits below the tonic")
	fake.free()
