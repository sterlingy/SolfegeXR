class_name YinDetector
extends RefCounted
## Offline YIN pitch detector: the same algorithm and parameters as
## web/pitch_worklet.js. Used for WAV analysis and tests in the editor.
## Slow in GDScript; when the C++ GDExtension class "YinNative" is loaded,
## analyze() uses it instead.

const TARGET_RATE := 24000
const WINDOW := 512
const HOP := 128
const MIN_HZ := 70.0
const MAX_HZ := 1200.0
const THRESHOLD := 0.15


## Analyze mono samples. Returns one PitchFrame per hop; frame.time is the end of
## the analyzed span in seconds, matching what the live worklet reports.
static func analyze(samples: PackedFloat32Array, sample_rate: float, hop := HOP) -> Array[PitchFrame]:
	if has_native():
		return _analyze_native(samples, sample_rate, hop)
	return analyze_gdscript(samples, sample_rate, hop)


static func has_native() -> bool:
	return ClassDB.class_exists("YinNative")


## The pure-GDScript path (reference implementation, and the fallback).
static func analyze_gdscript(samples: PackedFloat32Array, sample_rate: float, hop := HOP) -> Array[PitchFrame]:
	var decim := maxi(1, roundi(sample_rate / TARGET_RATE))
	var rate := sample_rate / decim
	var x := PackedFloat32Array()
	x.resize(samples.size() / decim)
	for i in x.size():
		var s := 0.0
		for k in decim:
			s += samples[i * decim + k]
		x[i] = s / decim
	var tau_min := maxi(2, floori(rate / MAX_HZ))
	var tau_max := ceili(rate / MIN_HZ)
	var span := WINDOW + tau_max + 2
	var d := PackedFloat32Array()
	d.resize(tau_max + 2)
	var frames: Array[PitchFrame] = []
	var start := 0
	while start + span <= x.size():
		frames.append(_analyze_at(x, start, rate, tau_min, tau_max, d, (start + span) / rate))
		start += hop
	return frames


static func _analyze_at(x: PackedFloat32Array, start: int, rate: float, tau_min: int,
		tau_max: int, d: PackedFloat32Array, time: float) -> PitchFrame:
	var sum_sq := 0.0
	for i in WINDOW:
		sum_sq += x[start + i] * x[start + i]
	var rms := sqrt(sum_sq / WINDOW)
	for tau in range(1, tau_max + 1):
		var acc := 0.0
		var j := start + tau
		for i in range(start, start + WINDOW):
			var delta := x[i] - x[j]
			acc += delta * delta
			j += 1
		d[tau] = acc
	d[0] = 1.0
	var running := 0.0
	for tau in range(1, tau_max + 1):
		running += d[tau]
		d[tau] = d[tau] * tau / running if running > 0.0 else 1.0
	var tau := -1
	var t := tau_min
	while t < tau_max:
		if d[t] < THRESHOLD:
			while t + 1 < tau_max and d[t + 1] < d[t]:
				t += 1
			tau = t
			break
		t += 1
	if tau < 0:
		tau = tau_min
		for k in range(tau_min + 1, tau_max):
			if d[k] < d[tau]:
				tau = k
	var better := float(tau)
	if tau > 1 and tau < tau_max:
		var a := d[tau - 1]
		var b := d[tau]
		var c := d[tau + 1]
		var denom := a + c - 2.0 * b
		if denom != 0.0:
			better = tau + (a - c) / (2.0 * denom)
	return PitchFrame.new(time, rate / better, clampf(1.0 - d[tau], 0.0, 1.0), rms)


static func _analyze_native(samples: PackedFloat32Array, sample_rate: float, hop: int) -> Array[PitchFrame]:
	var native: Object = ClassDB.instantiate("YinNative")
	var flat: PackedFloat32Array = native.call("analyze", samples, sample_rate, hop)
	var frames: Array[PitchFrame] = []
	for i in range(0, flat.size(), 4):
		frames.append(PitchFrame.new(flat[i], flat[i + 1], flat[i + 2], flat[i + 3]))
	return frames
