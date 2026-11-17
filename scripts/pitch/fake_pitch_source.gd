class_name FakePitchSource
extends PitchSource
## A synthetic "singer" for running in the editor (no mic there on this path).
## Sings do-re-mi-fa-sol-fa-mi-re-do in the given key with vibrato, an onset
## scoop, slow drift and breaths, so the trace can be developed without a browser.

const RATE := 187.5  # frames per second, same as the web worklet (24 kHz / 128)

var base_midi := 57.0  ## tonic to sing around; main.gd sets it from the key
var scale_steps := PackedInt32Array([0, 2, 4, 5, 7, 5, 4, 2, 0])
var note_length := 0.9
var gap_length := 0.25

var _t := 0.0
var _emitted := 0.0


func start() -> void:
	_t = 0.0
	_emitted = 0.0
	_set_state(State.RUNNING)


func stop() -> void:
	_set_state(State.IDLE)


func now() -> float:
	return _t


func _process(delta: float) -> void:
	if state == State.RUNNING:
		_t += delta


func poll() -> Array[PitchFrame]:
	var frames: Array[PitchFrame] = []
	if state != State.RUNNING:
		return frames
	while _emitted + 1.0 / RATE <= _t:
		_emitted += 1.0 / RATE
		frames.append(_frame_at(_emitted))
	return frames


func _frame_at(t: float) -> PitchFrame:
	var slot := note_length + gap_length
	var idx := int(t / slot)
	var local := fmod(t, slot)
	if local > note_length:
		return PitchFrame.new(t, 0.0, 0.1, 0.001)  # breath
	var target := base_midi + scale_steps[idx % scale_steps.size()]
	var scoop := -1.2 * exp(-local / 0.06)            # start low, slide up
	var vibrato := 0.3 * sin(TAU * 5.5 * local) * clampf(local / 0.3, 0.0, 1.0)
	var drift := 0.35 * sin(TAU * t / 11.0)          # slow "going flat" wander
	var midi := target + scoop + vibrato + drift + randf_range(-0.04, 0.04)
	return PitchFrame.new(t, 440.0 * pow(2.0, (midi - 69.0) / 12.0), 0.95, 0.1)
