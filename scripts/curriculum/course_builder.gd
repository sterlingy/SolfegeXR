class_name CourseBuilder
extends RefCounted
## Builds a learning course for one song:
##   course = skills the song needs - skills the learner has mastered,
## with drills cut from the song's own material ("the jump in bar 12"),
## transposed into the learner's voice, then the song phrase by phrase.

## The ensemble stages, in order (design doc). Real people come later.
const ENSEMBLE_STAGES := [
	"Solo with a reference tone and drone",
	"Over chords, with no melody",
	"With a guide voice singing along",
	"With a guide voice that fades away",
	"With a second voice on a different line",
	"With all the parts at once",
]

const MAX_DRILLS_PER_SKILL := 3


class Course:
	var song: SongAnalyzer.Result
	var transpose := 0
	var key: MusicKey                     ## the song's key after transposition
	var skills_needed: Array[Skills.Id] = []
	var skills_to_learn: Array[Skills.Id] = []
	var steps: Array[Exercise] = []


static func build(analysis: SongAnalyzer.Result, profile: LearnerProfile) -> Course:
	var c := Course.new()
	c.song = analysis
	c.transpose = analysis.transposition_for(profile.voice_low, profile.voice_high)
	c.key = MusicKey.new(analysis.key.tonic_pc + c.transpose, analysis.key.mode)
	profile.apply_to_key(c.key)

	for s in Skills.core_order():
		if not analysis.needs(s):
			continue
		# With the chromatic toggle off, outside-the-scale notes are still sung
		# but not drilled.
		if s == Skills.Id.CHROMATIC and not profile.chromatic_enabled:
			continue
		c.skills_needed.append(s)
		if not profile.is_mastered(s):
			c.skills_to_learn.append(s)

	for s in c.skills_to_learn:
		c.steps.append_array(_drills(s, analysis, c))

	# Then the song itself, phrase by phrase, then whole.
	for pi in analysis.phrases.size():
		var ph: Vector2i = analysis.phrases[pi]
		var ex := _from_notes(analysis, c, ph.x, ph.y, Skills.Id.PHRASES,
			"Phrase %d" % (pi + 1), "Bars %d-%d of %s." % [
				analysis.notes[ph.x].measure + 1, analysis.notes[ph.y].measure + 1, analysis.song.title])
		ex.reference = Exercise.Reference.ALONG
		c.steps.append(ex)
	var whole := _from_notes(analysis, c, 0, analysis.notes.size() - 1, Skills.Id.PHRASES,
		"The whole song", "Put it all together. Take your time.")
	whole.reference = Exercise.Reference.ALONG
	c.steps.append(whole)
	if analysis.needs(Skills.Id.ENSEMBLE):
		c.steps.append_array(_ensemble(analysis, c))
	return c


static func _drills(skill: Skills.Id, a: SongAnalyzer.Result, c: Course) -> Array[Exercise]:
	var S := Skills.Id
	var out: Array[Exercise] = []
	var examples: Array = a.skills.get(skill, [])
	match skill:
		S.STEPS, S.SMALL_LEAPS, S.LARGE_LEAPS:
			# Distinct intervals first, biggest first for leaps.
			var seen := {}
			var sorted := examples.duplicate()
			sorted.sort_custom(func(x, y): return absi(x.interval) > absi(y.interval))
			for ex in sorted:
				var i: int = ex.index
				var from := a.notes[i - 1]
				var to := a.notes[i]
				var sig := "%d>%d" % [from.semitone, to.semitone]
				if seen.has(sig):
					continue
				seen[sig] = true
				var syl_a := c.key.syllable_of(from.midi + c.transpose)
				var syl_b := c.key.syllable_of(to.midi + c.transpose)
				var e := _two_note(a, c, from.midi, to.midi, skill,
					"%s to %s" % [_label(syl_a), _label(syl_b)],
					"This is the %s in bar %d of your song." % [
						"step" if skill == S.STEPS else "jump", ex.measure + 1])
				out.append(e)
				if out.size() >= MAX_DRILLS_PER_SKILL:
					break
		S.SUSTAIN:
			var longest := examples.duplicate()
			longest.sort_custom(func(x, y): return a.notes[x.index].duration > a.notes[y.index].duration)
			for ex in longest.slice(0, 2):
				var n := a.notes[ex.index]
				var e := _from_notes(a, c, ex.index, ex.index, skill,
					"Hold %s" % _label(c.key.syllable_of(n.midi + c.transpose)),
					"The long note in bar %d. Land it and keep it steady." % [n.measure + 1])
				out.append(e)
		S.MINOR_MODES:
			var e := Exercise.new()
			e.skill = skill
			e.key = c.key
			e.title = "The home of this song"
			e.prompt = "This song lives in %s. Get to know its home notes." % c.key.name().to_lower()
			e.add_degrees([1, 2, 3, 2, 1, 3, 5, 1], 1.0)
			e.song_id = a.song.title
			out.append(e)
		S.CHROMATIC:
			for ex in examples.slice(0, MAX_DRILLS_PER_SKILL):
				var i: int = ex.index
				var lo := maxi(0, i - 1)
				var hi := mini(a.notes.size() - 1, i + 1)
				var syl := c.key.syllable_of(a.notes[i].midi + c.transpose)
				out.append(_from_notes(a, c, lo, hi, skill, "%s, outside the scale" % _label(syl),
					"Bar %d has a note outside the scale. Hear how it leans." % [ex.measure + 1]))
		S.PITCH_MATCH:
			var first := a.notes[0]
			out.append(_from_notes(a, c, 0, 0, skill, "Your first note",
				"The song starts on %s. Find it." % _label(c.key.syllable_of(first.midi + c.transpose))))
	return out


static func _ensemble(a: SongAnalyzer.Result, c: Course) -> Array[Exercise]:
	var out: Array[Exercise] = []
	for i in ENSEMBLE_STAGES.size():
		var e := _from_notes(a, c, 0, a.notes.size() - 1, Skills.Id.ENSEMBLE,
			"Stage %d" % (i + 1), ENSEMBLE_STAGES[i] + ". Headphones on.")
		e.reference = Exercise.Reference.ALONG if i in [2, 3] else Exercise.Reference.NONE
		e.accompaniment = i >= 1
		if i >= 4:
			for p in a.song.parts:
				if p == a.song.melody():
					continue
				var other := SongAnalyzer.analyze(a.song, p)
				e.parts.append({name = p.name, targets = other.targets(c.transpose)})
				if i == 4:
					break
		out.append(e)
	return out


static func _two_note(a: SongAnalyzer.Result, c: Course, from_midi: int, to_midi: int,
		skill: Skills.Id, title: String, prompt: String) -> Exercise:
	var e := Exercise.new()
	e.skill = skill
	e.key = c.key
	e.title = title
	e.prompt = prompt
	e.tempo_bpm = minf(a.song.tempo_bpm, 80.0)
	var tonic := c.key.tonic_pc
	for m in [from_midi, to_midi, from_midi, to_midi]:
		e.notes.append({semis = m + c.transpose - tonic, beats = 1.5})
	e.song_id = a.song.title
	e.fixed_base = tonic
	return e


## Exercise with notes copied from the song, at the transposed pitch.
static func _from_notes(a: SongAnalyzer.Result, c: Course, first: int, last: int,
		skill: Skills.Id, title: String, prompt: String) -> Exercise:
	var e := Exercise.new()
	e.skill = skill
	e.key = c.key
	e.title = title
	e.prompt = prompt
	e.tempo_bpm = a.song.tempo_bpm
	var tonic := c.key.tonic_pc
	var cursor := a.notes[first].start
	for i in range(first, last + 1):
		var n := a.notes[i]
		if n.start > cursor + 1e-4:
			e.notes.append({semis = null, beats = n.start - cursor})
		e.notes.append({semis = n.midi + c.transpose - tonic, beats = n.duration})
		cursor = n.start + n.duration
	e.song_id = a.song.title
	e.fixed_base = tonic
	return e


static func _label(syl: String) -> String:
	return syl.capitalize() if syl != "" else "Outside the scale"
