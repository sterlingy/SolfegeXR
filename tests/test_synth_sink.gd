extends TestCase
## SynthEngine with a sink (the web path): notes go to the sink, the clock
## comes from the sink, and a full practice exercise runs on that clock.


class FakeSink extends RefCounted:
	var t := 0.0
	var notes: Array = []
	var stops: Array = []
	var releases := 0

	func time() -> float:
		return t

	func note(v: Dictionary) -> void:
		notes.append(v)

	func stop_kind(kind: int) -> void:
		stops.append(kind)

	func release_all() -> void:
		releases += 1


func test_notes_go_to_sink() -> void:
	var e := SynthEngine.new(48000.0)
	var sink := FakeSink.new()
	sink.t = 10.0
	e.sink = sink
	assert_near(e.time(), 10.0, 1e-6)
	e.note(57, 10.5, 1.0)
	e.set_drone(57)
	assert_eq(sink.notes.size(), 3, "1 note + 2 drone voices")
	assert_near(sink.notes[0].hz, 220.0, 0.01)
	assert_near(sink.notes[0].at, 10.5, 1e-6)
	e.set_drone(-1)
	assert_true(SynthEngine.Kind.DRONE in sink.stops)
	assert_eq(e.active_voice_count(), 0, "nothing rendered locally")


func test_practice_runs_on_sink_clock() -> void:
	var profile := LearnerProfile.new()
	var ex := Curriculum.exercises_for(Skills.Id.STEPS, 0)[0]
	var e := SynthEngine.new(48000.0)
	var sink := FakeSink.new()
	sink.t = 66.5
	e.sink = sink
	var fake := FakePitchSource.new()
	fake.quiet()
	fake.start()
	var s := PracticeSession.new(ex, profile, 1.0)
	s.play_cadence = false
	var phases := []
	s.phase_changed.connect(func(p): phases.append(p))
	s.start(e)
	var waited := 0.0
	while s.phase != PracticeSession.Phase.RESULT and waited < 30.0:
		sink.t += 1.0 / 60.0
		fake.advance(1.0 / 60.0)
		s.update(fake.poll(), fake.now())
		waited += 1.0 / 60.0
	var P := PracticeSession.Phase
	assert_eq(phases, [P.LISTEN, P.COUNT_IN, P.SING, P.RESULT], "phases (stuck after %.1f s?)" % waited)
	fake.free()


## Every note a song step plays (cadence, drone, the song's notes, the backing
## track) uses the sound chosen in Settings, not just the core lessons.
func test_song_steps_use_the_chosen_sound() -> void:
	var song := MusicXmlReader.load_file("res://songs/01_ode_to_joy.musicxml")
	var profile := LearnerProfile.new()
	profile.has_headphones = true
	var course := CourseBuilder.build(SongAnalyzer.analyze(song), profile)
	for t in [SynthEngine.Timbre.FLUTE, SynthEngine.Timbre.CHOIR]:
		for step in course.steps.slice(-8):   # last phrase, whole song, backing track, ensemble
			var e := SynthEngine.new(48000.0)
			e.timbre = t
			var sink := FakeSink.new()
			e.sink = sink
			var fake := FakePitchSource.new()
			fake.quiet()
			fake.start()
			var s := PracticeSession.new(step, profile, 1.0)
			s.start(e)
			var waited := 0.0
			while s.phase != PracticeSession.Phase.RESULT and waited < 60.0:
				sink.t += 1.0 / 30.0
				fake.advance(1.0 / 30.0)
				s.update(fake.poll(), fake.now())
				waited += 1.0 / 30.0
			fake.free()
			assert_true(sink.notes.size() > 3, "%s played notes" % step.title)
			for n in sink.notes:
				if n.kind == SynthEngine.Kind.CLICK:
					continue
				var want := Array(SynthEngine.partials(t, n.kind, n.hz, 48000.0))
				assert_eq(n.partials, want, "%s: %s note uses %s" % [step.title, SynthEngine.Kind.keys()[n.kind], SynthEngine.TIMBRE_NAMES[t]])
