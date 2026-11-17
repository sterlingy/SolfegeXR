class_name TestHelpers
extends RefCounted
## Shared helpers for tests.

const RATE := 48000


static func voice(hz: float, seconds: float, rate := RATE, noise := 0.005) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * rate))
	var ph := 0.0
	for i in out.size():
		ph += hz / rate
		var v := 0.0
		for k in range(1, 9):
			v += sin(TAU * k * ph) / (k * k * 0.7 + 0.3)
		out[i] = 0.1 * v + noise * randf_range(-0.5, 0.5)
	return out


static func median_hz(frames: Array[PitchFrame]) -> float:
	var hz: Array[float] = []
	for f in frames:
		if f.confidence > 0.8:
			hz.append(f.frequency)
	if hz.is_empty():
		return NAN
	hz.sort()
	return hz[hz.size() / 2]
