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
