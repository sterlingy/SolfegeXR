class_name KeyFinder
extends RefCounted
## Detects tonic and mode: key signature first, then a Krumhansl-Schmuckler
## profile match on duration-weighted pitch classes, with a bonus for the
## final note (melodies almost always end on the tonic).

const MAJOR_PROFILE := [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
const MINOR_PROFILE := [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
const FINAL_NOTE_BONUS := 0.35
const FIRST_NOTE_BONUS := 0.1

const MODE_WORDS := {
	"major": MusicKey.Mode.IONIAN, "ionian": MusicKey.Mode.IONIAN,
	"dorian": MusicKey.Mode.DORIAN, "phrygian": MusicKey.Mode.PHRYGIAN,
	"lydian": MusicKey.Mode.LYDIAN, "mixolydian": MusicKey.Mode.MIXOLYDIAN,
	"minor": MusicKey.Mode.AEOLIAN, "aeolian": MusicKey.Mode.AEOLIAN,
	"locrian": MusicKey.Mode.LOCRIAN,
}


static func find(song: Song, part: Song.Part = null) -> MusicKey:
	if part == null:
		part = song.melody()
	var notes := part.sounding_notes()
	var hist := _histogram(notes)
	var final_pc := posmod(notes[-1].midi, 12) if not notes.is_empty() else -1
	var first_pc := posmod(notes[0].midi, 12) if not notes.is_empty() else -1

	if song.has_key_signature:
		var ionian_pc := posmod(7 * song.key_fifths, 12)
		if MODE_WORDS.has(song.key_mode):
			var mode: MusicKey.Mode = MODE_WORDS[song.key_mode]
			return MusicKey.new(ionian_pc + MusicKey.MAJOR_STEPS[mode], mode)
		# Mode not stated: try each mode of the signature (Locrian/Lydian/Phrygian rare).
		var best := MusicKey.new(ionian_pc, MusicKey.Mode.IONIAN)
		var best_score := -INF
		for mode in [MusicKey.Mode.IONIAN, MusicKey.Mode.AEOLIAN, MusicKey.Mode.DORIAN,
				MusicKey.Mode.MIXOLYDIAN]:
			var tonic := posmod(ionian_pc + MusicKey.MAJOR_STEPS[mode], 12)
			var minorish: bool = mode in [MusicKey.Mode.AEOLIAN, MusicKey.Mode.DORIAN]
			var s := _score(hist, tonic, minorish, final_pc, first_pc)
			if s > best_score:
				best_score = s
				best = MusicKey.new(tonic, mode)
		return best

	# No signature (typical for MIDI): best of 24 major/minor keys.
	var best_key := MusicKey.new(0, MusicKey.Mode.IONIAN)
	var best_s := -INF
	for tonic in 12:
		for minor in [false, true]:
			var s := _score(hist, tonic, minor, final_pc, first_pc)
			if s > best_s:
				best_s = s
				best_key = MusicKey.new(tonic, MusicKey.Mode.AEOLIAN if minor else MusicKey.Mode.IONIAN)
	return best_key


static func _histogram(notes: Array[Song.Note]) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(12)
	for n in notes:
		h[posmod(n.midi, 12)] += n.duration
	return h


static func _score(hist: PackedFloat32Array, tonic: int, minor: bool, final_pc: int, first_pc: int) -> float:
	var profile: Array = MINOR_PROFILE if minor else MAJOR_PROFILE
	var s := _correlation(hist, profile, tonic)
	if final_pc == tonic:
		s += FINAL_NOTE_BONUS
	if first_pc == tonic:
		s += FIRST_NOTE_BONUS
	return s


static func _correlation(hist: PackedFloat32Array, profile: Array, tonic: int) -> float:
	var mx := 0.0
	var my := 0.0
	for i in 12:
		mx += hist[i]
		my += profile[i]
	mx /= 12.0
	my /= 12.0
	var num := 0.0
	var dx := 0.0
	var dy := 0.0
	for i in 12:
		var x := hist[(i + tonic) % 12] - mx
		var y: float = profile[i] - my
		num += x * y
		dx += x * x
		dy += y * y
	return num / sqrt(dx * dy) if dx > 0.0 and dy > 0.0 else 0.0
