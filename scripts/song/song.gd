class_name Song
extends RefCounted
## A parsed piece of music, independent of file format (MusicXML or MIDI).
## Times and durations are in beats (quarter note = 1.0).

class Note:
	var midi := -1               ## -1 = rest
	var start := 0.0             ## beats from the start of the song
	var duration := 1.0          ## beats
	var lyric := ""
	var breath_after := false    ## breath mark or comma after this note
	var measure := 0
	var line_end := false        ## end of a lyric line / system (phrase hint)

	func is_rest() -> bool:
		return midi < 0

	func end() -> float:
		return start + duration


class Part:
	var name := ""
	var notes: Array[Song.Note] = []

	func sounding_notes() -> Array[Song.Note]:
		var out: Array[Song.Note] = []
		for n in notes:
			if not n.is_rest():
				out.append(n)
		return out


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


func seconds_per_beat() -> float:
	return 60.0 / tempo_bpm
