class_name Exercise
extends RefCounted
## One thing to sing: a list of target notes in a key, plus how to present it.
## Notes are scale-degree based until realized for a learner.

enum Reference { BEFORE, ALONG, NONE }   ## hear it first / sing along / alone
## NOTES: sing the target notes. SIREN: slide freely up and down (no target).
## SLIDE_TO: start anywhere, slide until you land on the note and hold it.
## FOLLOW: the target glides between notes; follow it.
enum Mode { NOTES, SIREN, SLIDE_TO, FOLLOW }

var skill: Skills.Id
var title := ""
var prompt := ""                     ## encouraging instruction shown to the learner
var key: MusicKey
## Notes: {semis: int (above home tonic, can be negative), beats: float}; rests have semis = null.
## A note with glide = true slides from its pitch to the next note's pitch.
var notes: Array = []
var tempo_bpm := 72.0
var drone := true
var cadence_first := true
var reference := Reference.BEFORE
var mode := Mode.NOTES
var sing_seconds := 6.0               ## SIREN / SLIDE_TO: time allowed to sing
var accompaniment := false           ## backing track under the melody
var needs_headphones := false        ## only offered when the learner has headphones
var beats_per_measure := 4.0         ## for the backing track's bars
var bar_offset_beats := 0.0          ## beats before the first barline (a pickup), 0 = starts on one
var guide_fade := false              ## guide voice fades out (ensemble stage 4)
var record := true                   ## counts toward skill progress (false for warm-ups)
var song_id := ""                    ## set for song-derived drills
var lyrics := ""                     ## the phrase's words, shown above the trace
var parts: Array = []                ## ensemble: other parts as {name, targets} (already realized)
## Song drills store pitches relative to this MIDI base (already transposed
## into the learner's voice). -1 = relative to the learner's home tonic.
var fixed_base := -1


## Add notes by scale degree (1-based like solfège teaching: 1 = do, 8 = do').
## Negative means the octave below: -5 = sol below do.
func add_degrees(degrees: Array, beats := 1.0) -> Exercise:
	var steps := key.steps()
	for d in degrees:
		var zero: int = d - 1 if d > 0 else (-d - 1) - 7  # 1..8 -> 0..7; -5 -> -3 (sol below)
		var octave := floori(zero / 7.0)
		var semis: int = steps[posmod(zero, 7)] + 12 * octave
		notes.append({semis = semis, beats = beats})
	return self


## Targets for this learner (seconds): PhraseScorer / SynthEngine.sequence input.
func realize_for(profile: LearnerProfile, tempo_scale := -1.0) -> Array:
	if tempo_scale < 0.0:
		tempo_scale = profile.tempo_scale
	var base := fixed_base if fixed_base >= 0 else profile.home_tonic(key.tonic_pc)
	return realize(base, tempo_scale)


## Targets given an explicit base (home tonic) MIDI note. Gliding notes get
## midi_end (the pitch they slide to).
func realize(home_tonic: int, tempo_scale := 1.0) -> Array:
	var spb := 60.0 / tempo_bpm / tempo_scale
	var out := []
	var t := 0.0
	for i in notes.size():
		var n: Dictionary = notes[i]
		var dur: float = n.beats * spb
		if n.semis != null:
			var target := {midi = home_tonic + int(n.semis), start = t, duration = dur}
			if n.get("lyric", "") != "":
				target.lyric = n.lyric
			if n.get("glide", false) and i + 1 < notes.size() and notes[i + 1].semis != null:
				target.midi_end = home_tonic + int(notes[i + 1].semis)
			out.append(target)
		t += dur
	return out


## Add a glide through these degrees (each leg `beats` long, ending with a hold).
func add_glide(degrees: Array, beats := 2.0, hold_beats := 1.0) -> Exercise:
	var start := notes.size()
	add_degrees(degrees, beats)
	for i in range(start, notes.size() - 1):
		notes[i].glide = true
	notes[-1].beats = hold_beats
	return self


func total_beats() -> float:
	var b := 0.0
	for n in notes:
		b += n.beats
	return b
