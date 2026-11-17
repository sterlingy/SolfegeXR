class_name PhraseScorer
extends RefCounted
## Scores a sequence of target notes. Each frame goes to the note whose time
## window contains it. `latency` shifts frames earlier to account for mic and
## detector delay (frame.time is when the sound was analyzed, a bit after it was sung).

var notes: Array[NoteScorer] = []
var latency := 0.03


## targets: Array of Dictionaries {midi:int, start:float, duration:float}
func _init(targets: Array, key: MusicKey = null, settings: ScoringSettings = null) -> void:
	for t in targets:
		var n := NoteScorer.new(t.midi, t.start, t.duration, key)
		if settings:
			settings.apply(n)
		notes.append(n)


func add_frame(f: PitchFrame) -> void:
	var shifted := PitchFrame.new(f.time - latency, f.frequency, f.confidence, f.rms)
	for n in notes:
		if shifted.time >= n.start_time and shifted.time <= n.start_time + n.duration:
			n.add_frame(shifted)
			return


func results() -> Array[NoteResult]:
	var out: Array[NoteResult] = []
	for n in notes:
		out.append(n.result())
	return out


## Share of notes landed, 0..1.
func landed_fraction() -> float:
	if notes.is_empty():
		return 0.0
	var landed := 0
	for r in results():
		if r.landed():
			landed += 1
	return float(landed) / notes.size()
