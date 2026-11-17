extends SceneTree
## Renders listening samples of the synth to build/audio/*.wav and times it.
##   Godot_console.exe --headless --path . -s res://tools/render_samples.gd

const RATE := 48000.0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/audio"))
	var a_major := MusicKey.new(9, MusicKey.Mode.IONIAN)
	var a_minor := MusicKey.new(9, MusicKey.Mode.AEOLIAN)

	_render("reference_scale_A3", 4.0, func(e: SynthEngine):
		var notes := []
		var steps := a_major.steps()
		for i in 8:
			notes.append({midi = 57 + (steps[i] if i < 7 else 12), start = i * 0.5, duration = 0.5})
		e.sequence(notes, 1.0, 0.0))
	_render("reference_long_note_A3", 3.0, func(e: SynthEngine): e.note(57, 0.0, 2.5))
	_render("drone_A", 3.0, func(e: SynthEngine):
		e.set_drone(57)
		e.render(int(RATE * 2.5))
		e.set_drone(-1), false)
	_render("cadence_A_major", 4.5, func(e: SynthEngine): e.cadence(a_major, 57, 0.8, 0.0))
	_render("cadence_A_minor", 4.5, func(e: SynthEngine): e.cadence(a_minor, 57, 0.8, 0.0))
	_render("key_setup_A_major", 7.0, func(e: SynthEngine):
		var len := e.cadence(a_major, 57, 0.8, 0.0)
		e.sequence([{midi = 57, start = 0.0, duration = 0.5}, {midi = 61, start = 0.5, duration = 0.5},
			{midi = 64, start = 1.0, duration = 0.5}, {midi = 69, start = 1.5, duration = 1.0}], 1.0, len))

	# Real-time budget: 1 s of drone + cadence + voice (7 voices).
	var e := SynthEngine.new(RATE)
	e.set_drone(57)
	e.cadence(a_major, 57, 0.8, 0.0)
	e.note(57, 0.0, 1.0)
	var t0 := Time.get_ticks_usec()
	for i in 47:
		e.render(1024)
	print("render cost: %.0f ms per second of audio (7 voices)" % ((Time.get_ticks_usec() - t0) / 1000.0))
	quit()


func _render(name: String, seconds: float, setup: Callable, schedule := true) -> void:
	var e := SynthEngine.new(RATE)
	var pre := PackedFloat32Array()
	if schedule:
		setup.call(e)
	else:
		# setup renders part itself (to change state mid-way); capture by re-running.
		e = SynthEngine.new(RATE)
		e.set_drone(57)
		pre = e.render(int(RATE * 2.5))
		e.set_drone(-1)
	var x := pre + e.render(int(RATE * seconds) - pre.size())
	var path := "res://build/audio/%s.wav" % name
	AudioIO.save_wav(ProjectSettings.globalize_path(path), x, int(RATE))
	print("wrote " + path)
