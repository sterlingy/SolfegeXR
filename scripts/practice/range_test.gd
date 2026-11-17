class_name RangeTest
extends RefCounted
## Finds the learner's comfortable range: they slide down to their lowest
## easy note, then up to their highest. Uses steady, confident pitches only
## and trims the extremes, so strained notes don't set the range.

const MIN_SPAN := 9          ## semitones; narrower results fall back to a preset
const TRIM := 1              ## semitones pulled in from each measured extreme

var lows: Array[float] = []
var highs: Array[float] = []
var min_confidence := 0.75
var min_rms := 0.002


func add_low(f: PitchFrame) -> void:
	if _ok(f):
		lows.append(MusicKey.hz_to_midi(f.frequency))


func add_high(f: PitchFrame) -> void:
	if _ok(f):
		highs.append(MusicKey.hz_to_midi(f.frequency))


func _ok(f: PitchFrame) -> bool:
	return f.confidence >= min_confidence and f.rms >= min_rms and f.frequency > 60.0 and f.frequency < 1300.0


func has_enough() -> bool:
	return lows.size() >= 30 and highs.size() >= 30


## Returns Vector2i(low, high) MIDI, or Vector2i(-1, -1) if unusable.
func result() -> Vector2i:
	if not has_enough():
		return Vector2i(-1, -1)
	var lo := ceili(_percentile(lows, 0.1)) + TRIM
	var hi := floori(_percentile(highs, 0.9)) - TRIM
	if hi - lo < MIN_SPAN:
		return Vector2i(-1, -1)
	return Vector2i(lo, hi)


static func _percentile(values: Array[float], q: float) -> float:
	var s := values.duplicate()
	s.sort()
	return s[clampi(int(q * (s.size() - 1)), 0, s.size() - 1)]


## Presets for "skip the test" and as a fallback.
const PRESETS := [
	["Low voice", 43, 62],      # G2..D4
	["Middle voice", 48, 67],   # C3..G4
	["High voice", 55, 74],     # G3..D5
]
