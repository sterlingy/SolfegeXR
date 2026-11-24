class_name SongAnalyzer
extends RefCounted
## The analysis pipeline:
##   parse -> key/mode -> scale degrees + chromatic flags -> range/transpose
##   -> phrases -> skill tags. (Course generation lives in CourseBuilder.)

## One melody note with its neutral representation.
class AnalyzedNote:
	var midi := 0
	var start := 0.0          ## beats
	var duration := 1.0       ## beats
	var degree := -1          ## 0..6, or -1 when chromatic
	var semitone := 0         ## 0..11 above the tonic
	var chromatic := false
	var lyric := ""
	var syllabic := ""
	var measure := 0
	var phrase := 0

	func lyric_display() -> String:
		return Song.lyric_text(lyric, syllabic)


class Result:
	var song: Song
	var part: Song.Part              ## the line being learned (a voice of the song)
	var key: MusicKey
	var notes: Array[SongAnalyzer.AnalyzedNote] = []
	var phrases: Array[Vector2i] = []   ## [first, last] note indices (inclusive)
	var low := 0
	var high := 0
	## Skills.Id -> Array of examples {index, measure, interval} (song's own material)
	var skills := {}

	func range_semitones() -> int:
		return high - low

	func needs(skill: Skills.Id) -> bool:
		return skills.has(skill)

	func has_lyrics() -> bool:
		for n in notes:
			if n.lyric != "":
				return true
		return false

	## The lyrics of notes first..last as one line ("" if none).
	func lyric_line(first: int, last: int) -> String:
		var parts := []
		for i in range(first, last + 1):
			parts.append(notes[i].lyric_display())
		return Song.lyric_line(parts)

	## Semitones to shift so the song sits in the learner's range [lo, hi].
	## Centers the song; if it is wider than the voice, keeps the top reachable
	## (low notes can be dropped an octave more easily than high ones).
	func transposition_for(voice_low: int, voice_high: int) -> int:
		var song_center := (low + high) / 2.0
		var voice_center := (voice_low + voice_high) / 2.0
		var shift := roundi(voice_center - song_center)
		if range_semitones() > voice_high - voice_low:
			shift = voice_high - high
		return shift

	## Target list for PhraseScorer / SynthEngine.sequence, in seconds.
	func targets(transpose := 0, tempo_scale := 1.0, from_note := 0, to_note := -1) -> Array:
		if to_note < 0:
			to_note = notes.size() - 1
		var spb := song.seconds_per_beat() / tempo_scale
		var origin := notes[from_note].start if from_note < notes.size() else 0.0
		var out := []
		for i in range(from_note, to_note + 1):
			var n := notes[i]
			out.append({midi = n.midi + transpose, start = (n.start - origin) * spb,
				duration = n.duration * spb, degree = n.degree, index = i})
		return out


const SUSTAIN_SECONDS := 1.2
const LONG_PHRASE_MEASURES := 4


static func analyze(song: Song, part: Song.Part = null) -> Result:
	if part == null:
		part = song.melody()
	var r := Result.new()
	r.song = song
	r.part = part
	# The key comes from the melody: an inner voice often ends off the tonic
	# (the tenor of a hymn in E minor ends on G), but it's sung in the same key.
	r.key = KeyFinder.find(song, song.melody())

	# Notes with degrees; phrase breaks from rests, breath marks, line ends.
	var break_before := false
	var phrase_start := 0
	var phrase_start_measure := 0
	r.low = 999
	r.high = -999
	for n in part.notes:
		if n.is_rest():
			if n.duration >= 0.5 and not r.notes.is_empty():
				break_before = true
			continue
		var a := AnalyzedNote.new()
		a.midi = n.midi
		a.start = n.start
		a.duration = n.duration
		a.lyric = n.lyric
		a.syllabic = n.syllabic
		a.measure = n.measure
		a.semitone = r.key.semitone_of(n.midi)
		a.degree = r.key.degree_of(n.midi)
		a.chromatic = a.degree < 0
		# Very long phrases split after a long note once past N measures.
		if not r.notes.is_empty() and not break_before:
			var prev := r.notes[-1]
			if prev.duration >= 2.0 and a.measure - phrase_start_measure >= LONG_PHRASE_MEASURES:
				break_before = true
		if break_before:
			r.phrases.append(Vector2i(phrase_start, r.notes.size() - 1))
			phrase_start = r.notes.size()
			phrase_start_measure = a.measure
			break_before = false
		a.phrase = r.phrases.size()
		r.notes.append(a)
		r.low = mini(r.low, a.midi)
		r.high = maxi(r.high, a.midi)
		if n.breath_after or n.line_end:
			break_before = true
	if not r.notes.is_empty():
		r.phrases.append(Vector2i(phrase_start, r.notes.size() - 1))
	else:
		r.low = 0
		r.high = 0

	_tag_skills(r, song.parts.size())
	return r


static func _tag_skills(r: Result, part_count: int) -> void:
	var S := Skills.Id
	var spb := r.song.seconds_per_beat()
	_add(r, S.PITCH_MATCH, 0, 0, 0)
	if r.phrases.size() > 0:
		_add(r, S.PHRASES, 0, 0, 0)
	for i in r.notes.size():
		var n := r.notes[i]
		if n.duration * spb >= SUSTAIN_SECONDS:
			_add(r, S.SUSTAIN, i, n.measure, 0)
		if n.chromatic:
			_add(r, S.CHROMATIC, i, n.measure, 0)
		if i == 0 or r.notes[i - 1].phrase != n.phrase:
			continue  # intervals only within a phrase
		var interval := n.midi - r.notes[i - 1].midi
		var size := absi(interval)
		if size == 0:
			continue
		if size <= 2:
			_add(r, S.STEPS, i, n.measure, interval)
		elif size <= 4:
			_add(r, S.SMALL_LEAPS, i, n.measure, interval)
		else:
			_add(r, S.LARGE_LEAPS, i, n.measure, interval)
	if r.key.mode != MusicKey.Mode.IONIAN:
		_add(r, S.MINOR_MODES, 0, 0, 0)
	if part_count > 1:
		_add(r, S.ENSEMBLE, 0, 0, 0)


static func _add(r: Result, skill: Skills.Id, index: int, measure: int, interval: int) -> void:
	if not r.skills.has(skill):
		r.skills[skill] = []
	r.skills[skill].append({index = index, measure = measure, interval = interval})
