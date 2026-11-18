extends SceneTree
## Renders a song's backing track (with the guide melody) to build/audio/backing_<id>.wav
##   Godot_console.exe --headless --path . -s res://tools/render_backing.gd -- 01_ode_to_joy


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0] if args.size() > 0 else "01_ode_to_joy"
	var a := SongAnalyzer.analyze(MusicXmlReader.load_file("res://songs/%s.musicxml" % id))
	var profile := LearnerProfile.new()
	profile.has_headphones = true
	var c := CourseBuilder.build(a, profile)
	var ex: Exercise = c.steps.filter(func(e): return e.skill == Skills.Id.BACKING_TRACK)[0]
	ex.reference = Exercise.Reference.ALONG  # include the melody so it can be judged
	var engine := SynthEngine.new(48000.0)
	var s := PracticeSession.new(ex, profile, 1.0)
	s.play_cadence = false
	s.start(engine)
	var out := PackedFloat32Array()
	var fake := FakePitchSource.new()
	fake.quiet()
	fake.start()
	while s.phase != PracticeSession.Phase.RESULT:
		var block := engine.render(1024)
		if s.phase == PracticeSession.Phase.SING:
			out.append_array(block)
		fake.advance(1024 / 48000.0)
		s.update(fake.poll(), fake.now())
	out.append_array(engine.render(48000))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/audio"))
	var path := "res://build/audio/backing_%s.wav" % id
	AudioIO.save_wav(ProjectSettings.globalize_path(path), out, 48000)
	print("wrote %s (%.1f s)" % [path, out.size() / 48000.0])
	fake.free()
	quit()
