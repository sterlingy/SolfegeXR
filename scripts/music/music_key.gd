class_name MusicKey
extends RefCounted
## A key = tonic pitch class + mode. Converts between MIDI pitches and the
## neutral note representation (scale degree relative to the tonic + mode),
## and renders solfège syllables according to the two display toggles.
##
## Stored data never depends on the toggles: they only change what text is shown.

enum Mode { IONIAN, DORIAN, PHRYGIAN, LYDIAN, MIXOLYDIAN, AEOLIAN, LOCRIAN }
enum MinorSyllables { LA_BASED, DO_BASED }

const MODE_NAMES := ["Major", "Dorian", "Phrygian", "Lydian", "Mixolydian", "Minor", "Locrian"]
const TONIC_NAMES := ["C", "C♯/D♭", "D", "E♭", "E", "F", "F♯/G♭", "G", "A♭", "A", "B♭", "B"]

const MAJOR_STEPS: PackedInt32Array = [0, 2, 4, 5, 7, 9, 11]
const MAJOR_SYLLABLES: PackedStringArray = ["do", "re", "mi", "fa", "sol", "la", "ti"]
# Altered syllables by major-scale degree (index 0..6 = do..ti).
const FLAT_SYLLABLES: PackedStringArray = ["de", "ra", "me", "fe", "se", "le", "te"]
const SHARP_SYLLABLES: PackedStringArray = ["di", "ri", "mi", "fi", "si", "li", "ti"]
# Chromatic (outside-the-key) names relative to do, by semitone. A common
# teaching set; revisit when the chromatic lessons are designed.
const CHROMATIC_SYLLABLES := {1: "di", 3: "me", 6: "fi", 8: "si", 10: "te"}

var tonic_pc: int = 0
var mode: Mode = Mode.IONIAN
var minor_syllables: MinorSyllables = MinorSyllables.LA_BASED
var chromatic_enabled := false


func _init(p_tonic_pc := 0, p_mode := Mode.IONIAN) -> void:
	tonic_pc = posmod(p_tonic_pc, 12)
	mode = p_mode


## Semitone offsets of the 7 scale degrees above the tonic.
func steps() -> PackedInt32Array:
	var rot := int(mode)
	var out := PackedInt32Array()
	for i in 7:
		out.append(posmod(MAJOR_STEPS[(i + rot) % 7] - MAJOR_STEPS[rot], 12))
	return out


func name() -> String:
	return "%s %s" % [TONIC_NAMES[tonic_pc], MODE_NAMES[mode]]


## Semitones above the tonic (0..11) for any MIDI note.
func semitone_of(midi: int) -> int:
	return posmod(midi - tonic_pc, 12)


## Scale degree 0..6 for a MIDI note in the key, or -1 if it is outside the key.
func degree_of(midi: int) -> int:
	return steps().find(semitone_of(midi))


func is_in_key(midi: int) -> bool:
	return degree_of(midi) >= 0


## Syllable for a scale degree (0..6), honoring the minor-syllable toggle.
func degree_syllable(degree: int) -> String:
	if minor_syllables == MinorSyllables.LA_BASED or mode == Mode.IONIAN:
		# Syllables follow the key signature: Dorian starts on re, minor on la.
		return MAJOR_SYLLABLES[(degree + int(mode)) % 7]
	# Do-based: home is always do; altered degrees get me/le/te/ra/fi/se.
	var diff := steps()[degree] - MAJOR_STEPS[degree]
	if diff < 0:
		return FLAT_SYLLABLES[degree]
	if diff > 0:
		return SHARP_SYLLABLES[degree]
	return MAJOR_SYLLABLES[degree]


## Syllable for any MIDI note. Outside-the-key notes return "" when the
## chromatic toggle is off (the UI then says "outside the scale").
func syllable_of(midi: int) -> String:
	var d := degree_of(midi)
	if d >= 0:
		return degree_syllable(d)
	if not chromatic_enabled:
		return ""
	var semis_from_do := semitone_of(midi)
	if minor_syllables == MinorSyllables.LA_BASED:
		semis_from_do = posmod(semis_from_do + MAJOR_STEPS[int(mode)], 12)
	return CHROMATIC_SYLLABLES.get(semis_from_do, "?")


## The lowest tonic MIDI note at or above `midi`.
func tonic_at_or_above(midi: int) -> int:
	return midi + posmod(tonic_pc - midi, 12)


static func hz_to_midi(hz: float) -> float:
	return 69.0 + 12.0 * log(hz / 440.0) / log(2.0)


static func midi_to_hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)
