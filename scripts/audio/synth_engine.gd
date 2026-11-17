class_name SynthEngine
extends RefCounted
## Sample-accurate software synth for the reference voice, tonic drone and
## chord cadences. Pure DSP (no nodes), so it renders offline in tests and
## feeds an AudioStreamGenerator live (see SynthPlayer).
##
## Timbre (per design): not a sine. A triangle blended with a little
## band-limited sawtooth, through a gentle low-pass, with delayed vibrato.

enum Kind { VOICE, DRONE, PAD }

const VOICE_VIBRATO_HZ := 5.2
const VOICE_VIBRATO_CENTS := 12.0
const VOICE_VIBRATO_DELAY := 0.25

var rate: float
var master_gain := 0.8
var _now := 0          ## samples rendered so far
var _voices: Array[Dictionary] = []


func _init(p_rate := 48000.0) -> void:
	rate = p_rate


## Current engine time in seconds (what `at` values are relative to).
func time() -> float:
	return _now / rate


## Schedule a note. `at` is absolute engine time in seconds (use time() + delay).
## duration < 0 means "until release_all/stop_kind".
func note(midi: float, at: float, duration: float, kind := Kind.VOICE, gain := 0.3) -> void:
	var hz := MusicKey.midi_to_hz(midi)
	var v := {
		kind = kind,
		hz = hz,
		gain = gain,
		start = int(at * rate),
		end = int((at + duration) * rate) if duration >= 0.0 else -1,
		phase = randf(),
		vib_phase = 0.0,
		lp = 0.0,
		attack = 0.04 if kind == Kind.VOICE else 0.3,
		release = 0.08 if kind == Kind.VOICE else 0.4,
		saw_mix = 0.3 if kind == Kind.VOICE else (0.6 if kind == Kind.DRONE else 0.15),
		cutoff = minf(hz * 4.0, 3000.0) if kind == Kind.VOICE else (700.0 if kind == Kind.DRONE else 1800.0),
		released_at = -1,
	}
	_voices.append(v)


## Start/stop the quiet tonic drone (tonic plus the octave below).
func set_drone(tonic_midi: int, gain := 0.07) -> void:
	stop_kind(Kind.DRONE)
	if tonic_midi < 0:
		return
	note(tonic_midi, time(), -1.0, Kind.DRONE, gain)
	note(tonic_midi - 12, time(), -1.0, Kind.DRONE, gain * 0.8)


## I-IV-V-I (i-iv-V-i in minor) around `tonic_midi`. Returns its length in seconds.
func cadence(key: MusicKey, tonic_midi: int, chord_seconds := 0.8, at := -1.0) -> float:
	if at < 0.0:
		at = time() + 0.05
	var steps := key.steps()
	var chords := [0, 3, 4, 0]
	for i in chords.size():
		var degree: int = chords[i]
		var tones: Array[int] = []
		for k in [0, 2, 4]:
			var d: int = degree + k
			var semi: int = steps[d % 7] + 12 * (d / 7)
			# Dominant gets a major third (leading tone) in minor-ish modes.
			if degree == 4 and k == 2 and steps[6] == 10:
				semi += 1
			tones.append(semi)
		# Close voicing near the tonic: fold upper tones into [-2, 9] semitones.
		var start := at + i * chord_seconds
		var dur := chord_seconds * (1.6 if i == chords.size() - 1 else 0.95)
		for semi in tones:
			var s := semi
			while s > 9:
				s -= 12
			note(tonic_midi + s, start, dur, Kind.PAD, 0.09)
		note(tonic_midi + tones[0] - (12 if tones[0] < 7 else 24), start, dur, Kind.PAD, 0.12)  # bass
	return chord_seconds * (chords.size() + 0.6)


## A sequence of {midi, start (relative s), duration} as the reference voice.
## `tempo` > 1 is faster; 0.5 is half speed.
func sequence(notes: Array, tempo := 1.0, at := -1.0) -> float:
	if at < 0.0:
		at = time() + 0.05
	var length := 0.0
	for n in notes:
		var s: float = n.start / tempo
		var d: float = n.duration / tempo
		note(n.midi, at + s, d * 0.97)
		length = maxf(length, s + d)
	return length


func stop_kind(kind: Kind) -> void:
	for v in _voices:
		if v.kind == kind and v.released_at < 0:
			v.released_at = _now


func release_all() -> void:
	for v in _voices:
		if v.released_at < 0:
			v.released_at = _now


func active_voice_count() -> int:
	return _voices.size()


## Render `count` mono samples and advance time.
func render(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	var finished: Array[int] = []
	for vi in _voices.size():
		var v: Dictionary = _voices[vi]
		if _render_voice(v, out, count):
			finished.append(vi)
	for i in range(finished.size() - 1, -1, -1):
		_voices.remove_at(finished[i])
	for i in count:
		# tanh soft clip: transparent at normal levels, never exceeds ±1.
		out[i] = tanh(out[i] * master_gain)
	_now += count
	return out


## Returns true when the voice is finished and can be removed.
func _render_voice(v: Dictionary, out: PackedFloat32Array, count: int) -> bool:
	var start: int = v.start
	if start >= _now + count:
		return false
	var hz: float = v.hz
	var attack_s: float = v.attack * rate
	var release_s: float = v.release * rate
	var lp_a := 1.0 - exp(-TAU * v.cutoff / rate)
	var is_voice: bool = v.kind == Kind.VOICE
	var phase: float = v.phase
	var vib_phase: float = v.vib_phase
	var lp: float = v.lp
	var saw_mix: float = v.saw_mix
	var gain: float = v.gain
	var end_sample: int = v.end
	if v.released_at >= 0 and (end_sample < 0 or v.released_at < end_sample):
		end_sample = v.released_at
	var dt := hz / rate
	var first := maxi(0, start - _now)
	for i in range(first, count):
		var n := _now + i
		var age := n - start
		# Envelope: linear attack, linear release after end.
		var env := minf(1.0, age / attack_s)
		if end_sample >= 0 and n >= end_sample:
			env *= 1.0 - (n - end_sample) / release_s
			if env <= 0.0:
				v.phase = phase
				return true
		# Vibrato updated every 16 samples (0.33 ms): inaudible, much cheaper.
		if is_voice and (i & 15) == 0:
			var depth := clampf((age / rate - VOICE_VIBRATO_DELAY) / 0.3, 0.0, 1.0)
			vib_phase += 16.0 * VOICE_VIBRATO_HZ / rate
			dt = hz / rate * pow(2.0, depth * VOICE_VIBRATO_CENTS / 1200.0 * sin(TAU * vib_phase))
		phase += dt
		if phase >= 1.0:
			phase -= 1.0
		var tri := 4.0 * absf(phase - 0.5) - 1.0
		var saw := 2.0 * phase - 1.0 - _poly_blep(phase, dt)
		var raw := lerpf(tri, saw, saw_mix)
		lp += lp_a * (raw - lp)
		out[i] += lp * env * gain
	v.phase = phase
	v.vib_phase = vib_phase
	v.lp = lp
	return false


## Band-limiting correction for the saw's discontinuity (PolyBLEP).
static func _poly_blep(t: float, dt: float) -> float:
	if t < dt:
		var x := t / dt
		return x + x - x * x - 1.0
	if t > 1.0 - dt:
		var x := (t - 1.0) / dt
		return x * x + x + x + 1.0
	return 0.0
