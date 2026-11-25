extends SceneTree
## Renders a short demo of each playback sound to build/sounds/<name>.wav:
## the I-IV-V-I cadence, then do re mi fa sol fa mi re do over the drone.
##   Godot_console.exe --headless --path . -s res://tools/render_sounds.gd

const RATE := 48000.0


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path("res://build/sounds")
	DirAccess.make_dir_recursive_absolute(dir)
	var key := MusicKey.new(0, MusicKey.Mode.IONIAN)
	var tonic := 55  # G3
	for t in SynthEngine.Timbre.values():
		var e := SynthEngine.new(RATE)
		e.timbre = t
		var at := e.cadence(key, tonic, 0.8, 0.1) + 0.3
		e.note(tonic, at, -1.0, SynthEngine.Kind.DRONE, 0.07)
		e.note(tonic - 12, at, -1.0, SynthEngine.Kind.DRONE, 0.056)
		var steps := [0, 2, 4, 5, 7, 5, 4, 2, 0]
		for i in steps.size():
			e.note(tonic + steps[i], at + 0.4 + i * 0.5, 0.48 if i < steps.size() - 1 else 1.2)
		var length := at + 0.4 + steps.size() * 0.5 + 1.0
		var x := e.render(int(RATE * length))
		e.release_all()
		x.append_array(e.render(int(RATE * 0.6)))
		var name: String = SynthEngine.TIMBRE_NAMES[t].to_lower().replace(" ", "_").replace("(", "").replace(")", "")
		AudioIO.save_wav(dir.path_join("%d_%s.wav" % [t + 1, name]), x, int(RATE))
		print("wrote %d_%s.wav (%.1f s)" % [t + 1, name, x.size() / RATE])
	quit()
