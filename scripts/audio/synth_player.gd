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


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = AudioServer.get_mix_rate()
	gen.buffer_length = 0.1  # 100 ms: enough headroom for frame hitches
	stream = gen
	engine = SynthEngine.new(gen.mix_rate)
	play()
	_playback = get_stream_playback()
	_fill()


func _process(_delta: float) -> void:
	_fill()


func _fill() -> void:
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
