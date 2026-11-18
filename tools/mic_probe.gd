extends SceneTree
## Native mic check: opens the default input through NativePitchSource for a
## few seconds and reports what it heard.
##   Godot_console.exe --path . -s res://tools/mic_probe.gd [-- seconds]
## Add "tone" after the seconds to play a 220 Hz reference through the speakers
## (the mic should pick it up): -- 4 tone
## (Not --headless: the dummy audio driver has no input.)

var src: NativePitchSource
var frames: Array[PitchFrame] = []
var elapsed := 0.0
var seconds := 4.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seconds = args[0].to_float()
	src = NativePitchSource.new()
	root.add_child(src)
	src.start.call_deferred()
	print("devices: ", src.devices().map(func(d): return d.label))
	if "tone" in args:
		var synth := SynthPlayer.new()
		root.add_child(synth)
		(func(): synth.engine.note(57, synth.engine.time() + 0.3, seconds - 0.8, SynthEngine.Kind.VOICE, 0.6)).call_deferred()
	(func(): print("using: ", src.describe(), "  state: ", src.state)).call_deferred()


func _process(delta: float) -> bool:
	elapsed += delta
	frames.append_array(src.poll())
	if elapsed < seconds:
		return false
	var max_rms := 0.0
	var voiced: Array[float] = []
	for f in frames:
		max_rms = maxf(max_rms, f.rms)
		if f.confidence > 0.8 and f.rms > 0.0015:
			voiced.append(f.frequency)
	voiced.sort()
	var lag_ms := (src.now() - (frames[-1].time if not frames.is_empty() else 0.0)) * 1000.0
	print("frames: %d (%.0f/s)  max level: %.4f  clear pitches: %d%s  silent-input: %s  last-frame lag: %.0f ms" % [
		frames.size(), frames.size() / elapsed, max_rms, voiced.size(),
		("  median %.1f Hz" % voiced[voiced.size() / 2]) if not voiced.is_empty() else "",
		src.input_silent(), lag_ms])
	src.stop()
	return true
