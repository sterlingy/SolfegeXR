class_name NoteResult
extends RefCounted
## Outcome of scoring one note. See NoteScorer.

var target_midi := 0
var verdict: NoteScorer.Verdict = NoteScorer.Verdict.NO_VOICE
var in_tune_ratio := 0.0          ## share of scored time within tolerance
var voiced_ratio := 0.0           ## share of the note that had a voice
var median_cents := NAN           ## pitch-class offset from target (+ = sharp)
var octave_offset := 0            ## -1 = sang an octave below, etc. (range hint)
var onset_seconds := -1.0         ## time to first land in tolerance, -1 = never
var drift_cents_per_second := 0.0
var sung_midi := -1               ## for WRONG_DEGREE: the note actually sung


func landed() -> bool:
	return verdict == NoteScorer.Verdict.LANDED


## Encouraging, specific feedback. Never "wrong" or "bad".
func feedback(key: MusicKey = null) -> String:
	var V := NoteScorer.Verdict
	var text := ""
	match verdict:
		V.NO_VOICE:
			text = "I didn't hear that one. Try singing a little louder."
		V.LANDED:
			text = "You landed it!"
			if onset_seconds > 0.4:
				text = "You found it! Next time try to land it a little sooner."
		V.CLOSE:
			text = "So close. A tiny bit %s." % ("higher" if median_cents < 0 else "lower")
		V.LOW:
			text = "A little low. Slide up until it locks in."
		V.HIGH:
			text = "A little high. Ease down until it locks in."
		V.DRIFTED_LOW:
			text = "Great start! It sank a little as you held it. Keep the air going."
		V.DRIFTED_HIGH:
			text = "Great start! It crept up a little as you held it. Stay relaxed."
		V.WRONG_DEGREE:
			if key != null:
				text = "That was %s. We're looking for %s." % [
					key.syllable_of(sung_midi), key.syllable_of(target_midi)]
			else:
				text = "That was a neighbouring note. Listen again and try once more."
	if octave_offset != 0 and verdict != V.NO_VOICE:
		text += " (You sang it an octave %s, which is fine.)" % ("lower" if octave_offset < 0 else "higher")
	return text
