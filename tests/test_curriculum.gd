extends TestCase
## Skill model, mastery, profile save/load, core curriculum, song courses.

var S := Skills.Id
const PATH := "user://test_profile.json"


func _results(landed: int, missed: int) -> Array[NoteResult]:
	var out: Array[NoteResult] = []
	for i in landed + missed:
		var r := NoteResult.new()
		r.verdict = NoteScorer.Verdict.LANDED if i < landed else NoteScorer.Verdict.LOW
		r.median_cents = 10.0 if i < landed else -80.0
		out.append(r)
	return out


func _song(id: String) -> SongAnalyzer.Result:
	return SongAnalyzer.analyze(MusicXmlReader.load_file("res://songs/%s.musicxml" % id))


func test_mastery_needs_accuracy_and_two_days() -> void:
	var p := LearnerProfile.new()
	p.record(S.PITCH_MATCH, _results(20, 2), "2026-11-17")
	assert_false(p.is_mastered(S.PITCH_MATCH), "one day is not enough")
	p.record(S.PITCH_MATCH, _results(18, 2), "2026-11-18")
	assert_true(p.is_mastered(S.PITCH_MATCH), "accuracy %.2f" % p.progress(S.PITCH_MATCH).recent_accuracy())
	assert_eq(p.progress(S.PITCH_MATCH).mastered_on, "2026-11-18")


func test_low_accuracy_not_mastered() -> void:
	var p := LearnerProfile.new()
	p.record(S.STEPS, _results(12, 8), "2026-11-17")
	p.record(S.STEPS, _results(12, 8), "2026-11-18")
	assert_false(p.is_mastered(S.STEPS))


func test_silence_does_not_count_against() -> void:
	var p := LearnerProfile.new()
	var r := NoteResult.new()
	r.verdict = NoteScorer.Verdict.NO_VOICE
	p.record(S.STEPS, [r] as Array[NoteResult], "2026-11-17")
	assert_eq(p.progress(S.STEPS).total_notes, 0)


func test_history_day_one_vs_today() -> void:
	var p := LearnerProfile.new()
	p.record(S.PITCH_MATCH, _results(3, 7), "2026-11-01")
	p.record(S.PITCH_MATCH, _results(9, 1), "2026-11-20")
	var h := p.progress(S.PITCH_MATCH).history()
	assert_eq(h.size(), 2)
	assert_near(h[0].accuracy, 0.3, 0.001)
	assert_near(h[1].accuracy, 0.9, 0.001)


func test_profile_round_trip() -> void:
	var p := LearnerProfile.new()
	p.voice_low = 45
	p.voice_high = 62
	p.chromatic_enabled = true
	p.minor_syllables = MusicKey.MinorSyllables.DO_BASED
	p.record(S.SUSTAIN, _results(5, 1), "2026-11-17")
	assert_eq(p.save(PATH), OK)
	var q := LearnerProfile.load_or_new(PATH)
	assert_eq([q.voice_low, q.voice_high, q.chromatic_enabled], [45, 62, true])
	assert_eq(q.minor_syllables, MusicKey.MinorSyllables.DO_BASED)
	assert_eq(q.progress(S.SUSTAIN).total_landed, 5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_next_skill_follows_core_order_and_toggle() -> void:
	var p := LearnerProfile.new()
	assert_eq(Curriculum.next_skill(p), S.PITCH_MATCH)
	for s in [S.PITCH_MATCH, S.SUSTAIN, S.STEPS, S.SMALL_LEAPS, S.LARGE_LEAPS, S.PHRASES, S.MINOR_MODES]:
		p.progress(s).mastered = true
	assert_eq(Curriculum.next_skill(p), S.BACKING_TRACK, "chromatic skipped while toggle is off")
	p.chromatic_enabled = true
	assert_eq(Curriculum.next_skill(p), S.CHROMATIC)


func test_every_core_skill_has_exercises_or_songs() -> void:
	for s in [S.PITCH_MATCH, S.SUSTAIN, S.STEPS, S.SMALL_LEAPS, S.LARGE_LEAPS, S.MINOR_MODES, S.CHROMATIC]:
		assert_true(Curriculum.exercises_for(s, 0).size() >= 2, "exercises for %s" % Skills.display_name(s))


func test_exercise_degrees_and_home_tonic() -> void:
	var p := LearnerProfile.new()
	p.voice_low = 48  # C3
	p.voice_high = 65  # F4
	var ex := Curriculum.exercises_for(S.PITCH_MATCH, 0)[3]  # sol below
	var t := ex.realize_for(p, 1.0)
	var home := p.home_tonic(0)
	assert_eq(posmod(home, 12), 0, "home tonic is a C")
	assert_eq(t[0].midi, home - 5, "sol below do")
	var scale := Curriculum.exercises_for(S.STEPS, 0)[2].realize(60)
	var midis := scale.map(func(n): return n.midi)
	assert_eq(midis, [60, 62, 64, 65, 67, 69, 71, 72])


func test_home_tonic_fits_range() -> void:
	var p := LearnerProfile.new()
	p.voice_low = 48
	p.voice_high = 67
	for pc in 12:
		var h := p.home_tonic(pc)
		# do and sol above always fit; the high do may not in every key.
		assert_true(h >= p.voice_low and h + 7 <= p.voice_high, "pc %d -> %d" % [pc, h])


func test_course_is_needed_minus_mastered() -> void:
	var p := LearnerProfile.new()
	var a := _song("01_ode_to_joy")
	var full := CourseBuilder.build(a, p)
	assert_true(S.LARGE_LEAPS in full.skills_to_learn)
	assert_true(S.STEPS in full.skills_to_learn)
	p.progress(S.STEPS).mastered = true
	p.progress(S.PITCH_MATCH).mastered = true
	var c := CourseBuilder.build(a, p)
	assert_false(S.STEPS in c.skills_to_learn, "mastered skills skipped")
	assert_true(S.STEPS in c.skills_needed)
	for e in c.steps:
		assert_true(e.skill != S.STEPS, "no step drills: " + e.title)


func test_course_drills_use_song_material() -> void:
	var p := LearnerProfile.new()
	p.voice_low = 45
	p.voice_high = 62
	var c := CourseBuilder.build(_song("01_ode_to_joy"), p)
	var leap: Exercise = null
	for e in c.steps:
		if e.skill == S.LARGE_LEAPS:
			leap = e
			break
	assert_true(leap != null, "has a leap drill")
	if leap == null:
		return
	assert_true(leap.prompt.contains("bar 12"), leap.prompt)
	var t := leap.realize_for(p)
	assert_eq(t[0].midi - t[1].midi, 7, "D down to G, transposed")
	for n in t:
		assert_true(n.midi >= p.voice_low and n.midi <= p.voice_high, "in voice: %d" % n.midi)
	var last := c.steps[-1]
	assert_eq(last.title, "The whole song")
	assert_eq(last.realize_for(p).size(), 62, "every note of Ode to Joy")


func test_chromatic_toggle_controls_drills() -> void:
	var p := LearnerProfile.new()
	var a := _song("08_take_me_out_to_the_ball_game")
	assert_false(S.CHROMATIC in CourseBuilder.build(a, p).skills_needed, "toggle off: no drill")
	p.chromatic_enabled = true
	var c := CourseBuilder.build(a, p)
	assert_true(S.CHROMATIC in c.skills_to_learn)


func test_carol_course_has_ensemble_stages() -> void:
	var c := CourseBuilder.build(_song("11_carol_of_the_bells"), LearnerProfile.new())
	var stages := c.steps.filter(func(e): return e.skill == S.ENSEMBLE)
	assert_eq(stages.size(), CourseBuilder.ENSEMBLE_STAGES.size())
	assert_eq(stages[4].parts.size(), 1, "harmony stage adds one other voice")
	assert_eq(stages[5].parts.size(), 3, "finale has all other parts")


func test_tolerance_tightens_with_mastery() -> void:
	var p := LearnerProfile.new()
	assert_near(p.scoring_settings().tolerance_cents, 50.0, 0.01)
	for s in Curriculum.active_skills(p):
		p.progress(s).mastered = true
	assert_near(p.scoring_settings().tolerance_cents, 25.0, 0.01)


func test_mic_choice_persists() -> void:
	var p := LearnerProfile.new()
	p.mic_device_id = "abc123"
	assert_eq(p.save(PATH), OK)
	assert_eq(LearnerProfile.load_or_new(PATH).mic_device_id, "abc123")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
