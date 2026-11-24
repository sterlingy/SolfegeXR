class_name Song
extends RefCounted
## A parsed piece of music, independent of file format (MusicXML or MIDI).
## Times and durations are in beats (quarter note = 1.0).

class Note:
	var midi := -1               ## -1 = rest
	var start := 0.0             ## beats from the start of the song
	var duration := 1.0          ## beats
	var lyric := ""
	## MusicXML syllabic: "single", "begin", "middle", "end" ("" = unknown)
	var syllabic := ""
	var breath_after := false    ## breath mark or comma after this note
	var measure := 0
	var line_end := false        ## end of a lyric line / system (phrase hint)

	func is_rest() -> bool:
		return midi < 0

	func end() -> float:
		return start + duration

	## The lyric as shown under a note: "ga-" for the start of "gather".
	func lyric_display() -> String:
		return Song.lyric_text(lyric, syllabic)


class Part:
	var name := ""
	var notes: Array[Song.Note] = []

	func sounding_notes() -> Array[Song.Note]:
		var out: Array[Song.Note] = []
		for n in notes:
			if not n.is_rest():
				out.append(n)
		return out


## Shared by MusicXML/MIDI notes and analyzed notes.
static func lyric_text(lyric: String, syllabic: String) -> String:
	if lyric == "":
		return ""
	return lyric + ("-" if syllabic in ["begin", "middle"] else "")


## Join syllables into a line: ["Shall", "we", "ga-", "ther"] -> "Shall we gather".
static func lyric_line(displays: Array) -> String:
	var out := ""
	for d: String in displays:
		if d == "":
			continue
		if out.ends_with("-"):
			out = out.trim_suffix("-") + d
		elif out == "":
			out = d
		else:
			out += " " + d
	return out.trim_suffix("-")


var title := ""
var tempo_bpm := 100.0
var beats_per_measure := 4.0
var key_fifths := 0          ## from the key signature, if the file had one
var key_mode := ""           ## "major", "minor", "dorian"... or "" if unknown
var has_key_signature := false
var parts: Array[Song.Part] = []


## The part to sing by default: the first part with notes.
func melody() -> Song.Part:
	for p in parts:
		if not p.sounding_notes().is_empty():
			return p
	return parts[0] if not parts.is_empty() else Song.Part.new()


## Parts with notes to sing, in score order (the voices a learner can pick).
func singable_parts() -> Array[Song.Part]:
	var out: Array[Song.Part] = []
	for p in parts:
		if not p.sounding_notes().is_empty():
			out.append(p)
	return out


## The singable part with this name, or null.
func part_named(part_name: String) -> Song.Part:
	for p in singable_parts():
		if p.name == part_name:
			return p
	return null


func seconds_per_beat() -> float:
	return 60.0 / tempo_bpm
