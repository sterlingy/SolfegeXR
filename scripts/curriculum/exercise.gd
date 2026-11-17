class_name Exercise
extends RefCounted
## One thing to sing: a list of target notes in a key, plus how to present it.
## Notes are scale-degree based until realized for a learner.

enum Reference { BEFORE, ALONG, NONE }   ## hear it first / sing along / alone

var skill: Skills.Id
var title := ""
var prompt := ""                     ## encouraging instruction shown to the learner
var key: MusicKey
## Notes: {semis: int (above home tonic, can be negative), beats: float}; rests have semis = null
var notes: Array = []
var tempo_bpm := 72.0
var drone := true
var cadence_first := true
var reference := Reference.BEFORE
var accompaniment := false           ## chord pad under the melody (backing-track stage)
var guide_fade := false              ## guide voice fades out (ensemble stage 4)
var record := true                   ## counts toward skill progress (false for warm-ups)
var song_id := ""                    ## set for song-derived drills
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


## Targets given an explicit base (home tonic) MIDI note.
func realize(home_tonic: int, tempo_scale := 1.0) -> Array:
	var spb := 60.0 / tempo_bpm / tempo_scale
	var out := []
	var t := 0.0
	for n in notes:
		var dur: float = n.beats * spb
		if n.semis != null:
			out.append({midi = home_tonic + int(n.semis), start = t, duration = dur})
		t += dur
	return out


func total_beats() -> float:
	var b := 0.0
	for n in notes:
		b += n.beats
	return b
