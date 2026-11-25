class_name SynthPlayer
extends AudioStreamPlayer
## Plays a SynthEngine live through an AudioStreamGenerator.
## (An AudioStreamGenerator is a stream you push samples into each frame,
## a bit like a procedural USoundWave.)
##
## Usage:
##   synth.engine.note(midi, synth.engine.time() + 0.1, 1.0)
##   synth.engine.set_drone(tonic_midi)
##   synth.engine.cadence(key, tonic_midi)

var engine: SynthEngine
var _playback: AudioStreamGeneratorPlayback


var web_sink: WebSynthSink


func _ready() -> void:
	# Web: render in a browser AudioWorklet (smooth on phones). Elsewhere, or if
	# that fails to start, render here in GDScript through a generator.
	if OS.has_feature("web"):
		web_sink = WebSynthSink.new()
		if web_sink.ok():
			engine = SynthEngine.new(48000.0)
			engine.sink = web_sink
			return
		push_warning("Web synth unavailable (%s); using GDScript synth" % web_sink.state())
		web_sink = null
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = AudioServer.get_mix_rate()
	gen.buffer_length = 0.1  # 100 ms: enough headroom for frame hitches
	stream = gen
	# Web exports default to "sample" playback, which can't play generators.
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	engine = SynthEngine.new(gen.mix_rate)
	play()
	_playback = get_stream_playback()
	# Samples are rendered ahead into the generator's buffer, then the driver
	# adds its own latency before the speaker.
	var buffer_frames := gen.buffer_length * gen.mix_rate
	engine.lead_fn = func() -> float:
		var queued := buffer_frames - _playback.get_frames_available() if _playback else 0.0
		return maxf(0.0, queued) / gen.mix_rate + AudioServer.get_output_latency()
	_fill()


func _process(_delta: float) -> void:
	_fill()


func _fill() -> void:
	if web_sink:
		return
	if _playback == null:
		return
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var mono := engine.render(n)
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		frames[i] = Vector2(mono[i], mono[i])
	_playback.push_buffer(frames)
