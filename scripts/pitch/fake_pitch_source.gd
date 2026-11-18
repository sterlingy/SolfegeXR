class_name FakePitchSource
extends PitchSource
## A synthetic "singer" for the editor and tests (no mic needed).
##
## Modes:
## - scale (default): sings do-re-mi-fa-sol-fa-mi-re-do with vibrato, scoops,
##   drift and breaths.
## - follow(targets): sings a given exercise, imperfectly, like a beginner.
## - siren(lo, hi): slides between two notes (for the range test).

const RATE := 187.5  # frames per second, same as the web worklet (24 kHz / 128)

var base_midi := 57.0  ## tonic for scale mode
var scale_steps := PackedInt32Array([0, 2, 4, 5, 7, 5, 4, 2, 0])
var note_length := 0.9
var gap_length := 0.25
## In follow mode: chance per note to be off (by a step or 70 cents).
var miss_chance := 0.2

var _t := 0.0
var _emitted := 0.0
var _mode := "scale"
var _targets: Array = []
var _origin := 0.0
var _note_offsets := {}
var _siren := Vector2(45, 70)


func start() -> void:
	_t = 0.0
	_emitted = 0.0
	_set_state(State.RUNNING)


func stop() -> void:
	_set_state(State.IDLE)


func now() -> float:
	return _t


func devices() -> Array:
	return [{id = "demo", label = "Demo singer"}]


func current_device() -> String:
	return "demo"


## Sing these targets (relative seconds) starting at source time `origin`.
func follow(targets: Array, origin: float) -> void:
	_mode = "follow"
	_targets = targets
	_origin = origin
	_note_offsets.clear()
	for i in targets.size():
		var r := randf()
		_note_offsets[i] = 0.0 if r > miss_chance else ([-0.7, 0.7, -2.0][randi() % 3])


func siren(lo: float, hi: float) -> void:
	_mode = "siren"
	_siren = Vector2(lo, hi)


func scale_mode() -> void:
	_mode = "scale"


## Stay silent (e.g. while the app plays the reference).
func quiet() -> void:
	_mode = "quiet"


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


## Advance the clock by hand (tests run without _process).
func advance(seconds: float) -> void:
	_t += seconds


func _frame_at(t: float) -> PitchFrame:
	match _mode:
		"quiet":
			return PitchFrame.new(t, 0.0, 0.1, 0.001)
		"follow":
			return _follow_frame(t)
		"siren":
			var u := 0.5 - 0.5 * cos(TAU * t / 6.0)
			return _voiced(t, lerpf(_siren.x, _siren.y, u) + 0.15 * sin(TAU * 5.5 * t))
	var slot := note_length + gap_length
	var idx := int(t / slot)
	var local := fmod(t, slot)
	if local > note_length:
		return PitchFrame.new(t, 0.0, 0.1, 0.001)  # breath
	var target := base_midi + scale_steps[idx % scale_steps.size()]
	return _voiced(t, target + _human(local) + 0.35 * sin(TAU * t / 11.0))


func _follow_frame(t: float) -> PitchFrame:
	var rel := t - _origin
	for i in _targets.size():
		var n: Dictionary = _targets[i]
		if rel >= n.start and rel < n.start + n.duration - 0.03:
			var local: float = rel - n.start
			var midi: float = n.midi
			if n.has("midi_end"):
				midi = lerpf(n.midi, n.midi_end, local / n.duration)
				return _voiced(t, midi + _note_offsets.get(i, 0.0) + 0.2 * sin(TAU * 5.5 * local))
			return _voiced(t, midi + _note_offsets.get(i, 0.0) + _human(local))
	return PitchFrame.new(t, 0.0, 0.1, 0.001)


## Onset scoop + vibrato + jitter.
func _human(local: float) -> float:
	var scoop := -1.2 * exp(-local / 0.06)
	var vibrato := 0.3 * sin(TAU * 5.5 * local) * clampf(local / 0.3, 0.0, 1.0)
	return scoop + vibrato + randf_range(-0.04, 0.04)


func _voiced(t: float, midi: float) -> PitchFrame:
	return PitchFrame.new(t, MusicKey.midi_to_hz(midi), 0.95, 0.1)
