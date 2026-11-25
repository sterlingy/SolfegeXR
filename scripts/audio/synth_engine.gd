class_name SynthEngine
extends RefCounted
## Sample-accurate software synth for the reference voice, tonic drone and
## chord cadences. Pure DSP (no nodes), so it renders offline in tests and
## feeds an AudioStreamGenerator live (see SynthPlayer).
##
## Timbre: each sound is a set of harmonic strengths read from a band-limited
## wave table (nothing above ~8 kHz, so no raspy edge), plus per-sound vibrato,
## an optional two-voice chorus and, for the flute, a little breath noise.
## The learner picks the sound in Settings (LearnerProfile.timbre).
##
## The web build renders in web/synth_worklet.js. This file still decides the
## harmonics and settings and sends them with each note; the worklet uses the
## same table, envelope, vibrato, chorus and noise maths. Keep them in step:
## tests/synth_parity.mjs compares the two sample by sample.

enum Kind { VOICE, DRONE, PAD, CLICK }  ## CLICK: a short metronome tick
enum Timbre { WARM, FLUTE, CHOIR, ORGAN }

## Names for the Settings dropdown, in Timbre order.
const TIMBRE_NAMES := ["Warm", "Flute", "Choir (ooh)", "Soft organ"]
const TABLE_SIZE := 1024              ## power of two
const MAX_PARTIAL_HZ := 8000.0
const VOICE_VIBRATO_DELAY := 0.25
const CLICK_CUTOFF := 8000.0
const BREATH_CUTOFF := 2500.0

var rate: float
var master_gain := 0.8
var timbre := Timbre.WARM
## When set (web builds), notes are sent here instead of rendered locally:
## an object with note(Dictionary), time() -> float, stop_kind(int), release_all().
var sink: Object = null
var _now := 0          ## samples rendered so far
var _seed := 1         ## per-note seed: start phase and noise (same maths on the web)
var _voices: Array[Dictionary] = []
static var _tables := {}   ## wave tables by partials, built once


func _init(p_rate := 48000.0) -> void:
	rate = p_rate


## Current engine time in seconds (what `at` values are relative to).
func time() -> float:
	return sink.time() if sink else _now / rate


## Set by SynthPlayer on desktop: seconds from engine time to the speaker.
var lead_fn: Callable


## Seconds between a note's engine time and when it comes out of the speaker:
## the browser's reported output latency on the web; the generator's buffer
## plus the driver's latency on desktop; 0 in tests. Screens that draw notes
## on their own clock shift them by this so picture and sound line up.
func output_lead() -> float:
	if sink and sink.has_method("output_lead"):
		return sink.output_lead()
	if lead_fn.is_valid():
		return lead_fn.call()
	return 0.0


## Envelope, vibrato, chorus and breath for a sound and kind of note.
static func settings(t: Timbre, kind: Kind) -> Dictionary:
	var s := {attack = 0.3, release = 0.4, vib_cents = 0.0, vib_hz = 5.0, chorus = 0.0, breath = 0.0,
		level = [1.0, 1.0, 1.23, 0.82][t]}  ## level: evens out loudness between sounds
	if kind == Kind.CLICK:
		s.level = 1.0
		s.attack = 0.001
		s.release = 0.05
		return s
	if kind == Kind.VOICE:
		match t:
			Timbre.WARM:
				s.merge({attack = 0.04, release = 0.09, vib_cents = 12.0, vib_hz = 5.2}, true)
			Timbre.FLUTE:
				s.merge({attack = 0.06, release = 0.1, vib_cents = 10.0, vib_hz = 5.0, breath = 0.04}, true)
			Timbre.CHOIR:
				s.merge({attack = 0.12, release = 0.16, vib_cents = 15.0, vib_hz = 4.8, chorus = 8.0}, true)
			Timbre.ORGAN:
				s.merge({attack = 0.02, release = 0.07, chorus = 3.0}, true)
		return s
	# Drone and chord pads: slow swell, no vibrato; the choir and organ keep their chorus.
	if t == Timbre.CHOIR:
		s.chorus = 8.0
	elif t == Timbre.ORGAN:
		s.chorus = 3.0
	return s


## Harmonic strengths (partial 1 first) for a sound at `hz`. Drones are darker
## and pads a little darker than the melody voice.
static func partials(t: Timbre, kind: Kind, hz: float, p_rate: float) -> PackedFloat64Array:
	var top := clampi(int(minf(MAX_PARTIAL_HZ, p_rate * 0.45) / maxf(hz, 1.0)), 1, 16)
	var out := PackedFloat64Array()
	for k in range(1, top + 1):
		var a := 0.0
		match t:
			Timbre.WARM:
				a = [1.0, 0.32, 0.12, 0.05, 0.025, 0.012][k - 1] if k <= 6 else 0.0
			Timbre.FLUTE:
				a = [1.0, 0.22, 0.07, 0.03, 0.01][k - 1] if k <= 5 else 0.0
			Timbre.CHOIR:
				# "Ooh": formants near 320 Hz and 800 Hz, on a log-frequency scale.
				var f := k * hz
				var f1 := exp(-pow(log(f / 320.0) / 0.45, 2.0))
				var f2 := 0.35 * exp(-pow(log(f / 800.0) / 0.35, 2.0))
				a = (f1 + f2 + 0.03) / pow(k, 0.6)
			Timbre.ORGAN:
				# Drawbars: 8', 4', 2 2/3', 2', 1 3/5' (soft), 1 1/3', 1'.
				a = {1: 1.0, 2: 0.55, 3: 0.15, 4: 0.3, 5: 0.05, 6: 0.08, 8: 0.12}.get(k, 0.0)
		if kind == Kind.DRONE:
			a *= pow(0.55, k - 1)
		elif kind == Kind.PAD:
			a *= pow(0.8, k - 1)
		out.append(a)
	# Trailing zeros don't change the sound; trimming them shares more tables.
	while out.size() > 1 and out[out.size() - 1] == 0.0:
		out.resize(out.size() - 1)
	return out


## One cycle of the wave, normalised to an RMS of 0.5 (about the old voice's level).
static func build_table(parts: PackedFloat64Array) -> PackedFloat64Array:
	var key := str(parts)
	if _tables.has(key):
		return _tables[key]
	var t := PackedFloat64Array()
	t.resize(TABLE_SIZE)
	var sum_sq := 0.0
	for j in TABLE_SIZE:
		var x := 0.0
		for k in parts.size():
			if parts[k] != 0.0:
				x += parts[k] * sin(TAU * (k + 1) * j / TABLE_SIZE)
		t[j] = x
		sum_sq += x * x
	var scale := 0.5 / maxf(1e-9, sqrt(sum_sq / TABLE_SIZE))
	for j in TABLE_SIZE:
		t[j] *= scale
	_tables[key] = t
	return t


## Next value of a 32-bit linear congruential generator (same in the worklet).
static func lcg(s: int) -> int:
	return (s * 1664525 + 1013904223) & 0xFFFFFFFF


## Schedule a note. `at` is absolute engine time in seconds (use time() + delay).
## duration < 0 means "until release_all/stop_kind".
func note(midi: float, at: float, duration: float, kind := Kind.VOICE, gain := 0.3,
		midi_end := NAN) -> void:
	var hz := MusicKey.midi_to_hz(midi)
	var hz_end := hz if is_nan(midi_end) else MusicKey.midi_to_hz(midi_end)
	_seed = lcg(_seed)
	var st := settings(timbre, kind)
	var parts := PackedFloat64Array() if kind == Kind.CLICK else partials(timbre, kind, hz, rate)
	var msg := {kind = kind, hz = hz, hz_end = hz_end, gain = gain * st.level, at = at, dur = duration,
		attack = st.attack, release = st.release, vib_cents = st.vib_cents, vib_hz = st.vib_hz,
		chorus = st.chorus, breath = st.breath, seed = _seed, partials = Array(parts)}
	if sink:
		sink.note(msg)
		return
	var v := msg.duplicate()
	v.start = int(at * rate)
	v.end = int((at + duration) * rate) if duration >= 0.0 else -1
	v.released_at = -1
	v.table = PackedFloat64Array() if kind == Kind.CLICK else build_table(parts)
	v.phase = (_seed % 1000) / 1000.0
	v.phase2 = v.phase
	v.vib_phase = 0.0
	v.lp = 0.0
	v.noise = _seed
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
		# Glides run their full length so they join the next note smoothly.
		if n.has("midi_end"):
			note(n.midi, at + s, d, Kind.VOICE, 0.3, n.midi_end)
		else:
			note(n.midi, at + s, d * 0.97)
		length = maxf(length, s + d)
	return length


func stop_kind(kind: Kind) -> void:
	if sink:
		sink.stop_kind(kind)
		return
	for v in _voices:
		if v.kind == kind and v.released_at < 0:
			v.released_at = _now


func release_all() -> void:
	if sink:
		sink.release_all()
		return
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
	var hz_end: float = v.hz_end
	var glide: bool = hz_end != hz
	var dur_s: float = maxf(1.0, v.dur * rate)
	var attack_s: float = maxf(1.0, v.attack * rate)
	var release_s: float = maxf(1.0, v.release * rate)
	var is_click: bool = v.kind == Kind.CLICK
	var vib_cents: float = v.vib_cents
	var vib_hz: float = v.vib_hz
	var moving := glide or vib_cents > 0.0
	var chorus: bool = v.chorus > 0.0
	var ch_up := pow(2.0, v.chorus / 2400.0)    # +half the chorus spread
	var ch_down := 1.0 / ch_up                   # -half
	var breath: float = v.breath
	var noise_a := 1.0 - exp(-TAU * (CLICK_CUTOFF if is_click else BREATH_CUTOFF) / rate)
	var table: PackedFloat64Array = v.table
	var mask := TABLE_SIZE - 1
	var phase: float = v.phase
	var phase2: float = v.phase2
	var vib_phase: float = v.vib_phase
	var lp: float = v.lp
	var noise: int = v.noise
	var gain: float = v.gain
	var end_sample: int = v.end
	if v.released_at >= 0 and (end_sample < 0 or v.released_at < end_sample):
		end_sample = v.released_at
	var dt := hz / rate
	var chiff := 1.0
	var first := maxi(0, start - _now)
	for i in range(first, count):
		var n := _now + i
		var age := n - start
		# Envelope: linear attack, linear release after end.
		var env := minf(1.0, age / attack_s)
		if end_sample >= 0 and n >= end_sample:
			env *= 1.0 - (n - end_sample) / release_s
			if env <= 0.0:
				return true
		# Vibrato, glide and the breath's onset puff are updated every 16
		# samples (0.33 ms): inaudible, much cheaper.
		if (i & 15) == 0:
			if moving:
				var depth := clampf((age / rate - VOICE_VIBRATO_DELAY) / 0.3, 0.0, 1.0)
				vib_phase += 16.0 * vib_hz / rate
				var base := hz
				if glide:
					base = hz * pow(hz_end / hz, clampf(age / dur_s, 0.0, 1.0))
				dt = base / rate * pow(2.0, depth * vib_cents / 1200.0 * sin(TAU * vib_phase))
			if breath > 0.0:
				chiff = 1.0 + 2.5 * exp(-age / (0.06 * rate))
		var y := 0.0
		if is_click or breath > 0.0:
			noise = (noise * 1664525 + 1013904223) & 0xFFFFFFFF
			lp += noise_a * ((noise / 2147483648.0 - 1.0) - lp)
		if is_click:
			# A tick is a burst of noise: no pitch for the detector to hear.
			y = lp
		else:
			phase += dt * ch_down if chorus else dt
			if phase >= 1.0:
				phase -= 1.0
			var x := phase * TABLE_SIZE
			var j := int(x)
			var a: float = table[j]
			y = a + (table[(j + 1) & mask] - a) * (x - j)
			if chorus:
				phase2 += dt * ch_up
				if phase2 >= 1.0:
					phase2 -= 1.0
				x = phase2 * TABLE_SIZE
				j = int(x)
				a = table[j]
				# Two detuned voices: scale by 1/sqrt(2) to keep the level of one.
				y = 0.70710678 * (y + a + (table[(j + 1) & mask] - a) * (x - j))
			if breath > 0.0:
				y += lp * breath * chiff
		out[i] += y * env * gain
	v.phase = phase
	v.phase2 = phase2
	v.vib_phase = vib_phase
	v.lp = lp
	v.noise = noise
	return false
