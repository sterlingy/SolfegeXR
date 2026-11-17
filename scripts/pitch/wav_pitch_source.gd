class_name WavPitchSource
extends PitchSource
## Plays back a recorded WAV through the detector, as if it were live mic input.
## Analysis happens up front, then frames are released in real time.
## Use: record yourself into tests/audio/*.wav and point `path` at it.

@export_file("*.wav") var path := ""
var loop := false

var _frames: Array[PitchFrame] = []
var _next := 0
var _t := 0.0


func load_now() -> bool:
	var audio := AudioIO.load_wav(path)
	if audio.is_empty():
		_set_state(State.ERROR, "Couldn't read " + path)
		return false
	_frames = YinDetector.analyze(audio.samples, audio.rate)
	return true


## All frames, for tests and offline scoring.
func all_frames() -> Array[PitchFrame]:
	return _frames


func start() -> void:
	if _frames.is_empty() and not load_now():
		return
	_t = 0.0
	_next = 0
	_set_state(State.RUNNING)


func stop() -> void:
	_set_state(State.IDLE)


func now() -> float:
	return _t


func _process(delta: float) -> void:
	if state == State.RUNNING:
		_t += delta


func poll() -> Array[PitchFrame]:
	var out: Array[PitchFrame] = []
	if state != State.RUNNING:
		return out
	while _next < _frames.size() and _frames[_next].time <= _t:
		out.append(_frames[_next])
		_next += 1
	if _next >= _frames.size():
		if loop:
			_t = 0.0
			_next = 0
		else:
			_set_state(State.IDLE)
	return out
