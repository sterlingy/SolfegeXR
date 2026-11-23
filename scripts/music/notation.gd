class_name Notation
extends RefCounted
## Staff notation for an exercise in the learner's key: key signature, note
## spelling, staff positions, note values, bar lines, ties, beams and
## accidentals. Pure logic; PitchTrace draws it (sheet music view).
##
## Staff "steps" count diatonic positions: step = octave * 7 + letter
## (C = 0 ... B = 6), so middle C (C4) is 28 and each step is half a staff space.

enum Clef { TREBLE, BASS }

const LETTERS := ["C", "D", "E", "F", "G", "A", "B"]
const NATURAL_PC: PackedInt32Array = [0, 2, 4, 5, 7, 9, 11]
const SHARP_ORDER: PackedInt32Array = [3, 0, 4, 1, 5, 2, 6]   # F C G D A E B
const FLAT_ORDER: PackedInt32Array = [6, 2, 5, 1, 4, 0, 3]    # B E A D G C F
## Note values (in beats) that can be written with one symbol, longest first.
const VALUES: PackedFloat32Array = [4.0, 3.0, 2.0, 1.5, 1.0, 0.75, 0.5, 0.25]
const NO_ACCIDENTAL := 99

## Bottom-line step of each clef: treble E4, bass G2.
const BOTTOM_STEP := {Clef.TREBLE: 30, Clef.BASS: 18}
## Key-signature steps, in the order they're written (treble; bass is 14 lower).
const SHARP_STEPS: PackedInt32Array = [38, 35, 39, 36, 33, 37, 34]
const FLAT_STEPS: PackedInt32Array = [34, 37, 33, 36, 32, 35, 31]

## Below this average pitch (MIDI) the bass clef is used (bass and tenor voices).
const BASS_CLEF_BELOW := 59.0


## Sharps (+) or flats (-) in the key signature, -6..6. A key that could be
## written either way takes flats (G♭ major, E♭ minor).
static func key_fifths(key: MusicKey) -> int:
	var major_pc := posmod(key.tonic_pc - MusicKey.MAJOR_STEPS[key.mode], 12)
	var f := posmod(major_pc * 7, 12)
	return f - 12 if f >= 6 else f


## Alteration the key signature gives a letter: +1, -1 or 0.
static func key_alter(letter: int, fifths: int) -> int:
	for i in absi(fifths):
		if fifths > 0 and SHARP_ORDER[i] == letter:
			return 1
		if fifths < 0 and FLAT_ORDER[i] == letter:
			return -1
	return 0


## {letter, alter, octave, step} for a MIDI note in this key. Notes outside the
## key follow the chromatic syllables: di, fi and si are the note below raised
## (F♯ in C, the leading tone C♯ in D minor); me and te are the note above
## lowered (B♭ in C).
static func spell(midi: int, fifths: int) -> Dictionary:
	var pc := posmod(midi, 12)
	var letter := -1
	var alter := 0
	for l in 7:
		if posmod(NATURAL_PC[l] + key_alter(l, fifths), 12) == pc:
			letter = l
			alter = key_alter(l, fifths)
	if letter < 0:
		var do_pc := posmod(fifths * 7, 12)
		var raise := posmod(pc - do_pc, 12) in [1, 6, 8]
		var neighbour := posmod(pc + (-1 if raise else 1), 12)
		for l in 7:
			if posmod(NATURAL_PC[l] + key_alter(l, fifths), 12) == neighbour:
				letter = l
				alter = key_alter(l, fifths) + (1 if raise else -1)
	var octave := floori((midi - alter) / 12.0) - 1
	return {letter = letter, alter = alter, octave = octave, step = octave * 7 + letter}


static func step_of(midi: int, fifths: int) -> int:
	return spell(midi, fifths).step


static func clef_for(midis: Array) -> Clef:
	if midis.is_empty():
		return Clef.TREBLE
	var sum := 0.0
	for m in midis:
		sum += m
	return Clef.BASS if sum / midis.size() < BASS_CLEF_BELOW else Clef.TREBLE


## Readable key name with proper spelling: "D minor", "B♭ major".
static func key_name(key: MusicKey) -> String:
	var s := spell(60 + key.tonic_pc, key_fifths(key))
	var acc: String = {1: "♯", -1: "♭", 0: ""}[s.alter]
	return "%s%s %s" % [LETTERS[s.letter], acc, MusicKey.MODE_NAMES[key.mode].to_lower()]


## Split a length (beats) into writable values, tied together.
static func split_value(beats: float) -> Array:
	var out := []
	var left := beats
	while left > 0.124:
		var v := 0.25
		for cand in VALUES:
			if cand <= left + 0.01:
				v = cand
				break
		out.append(v)
		left -= v
	if out.is_empty():
		out.append(0.25)
	return out


## Everything needed to draw an exercise as sheet music.
## notes: Exercise.notes ({semis or null, beats, lyric}); base: MIDI of semis 0.
## clef: -1 picks one from the notes; pass the learner's (clef_for their range)
## so every exercise of a course uses the same clef.
static func build(key: MusicKey, notes: Array, base: int, beats_per_measure: float,
		bar_offset: float, clef := -1) -> Dictionary:
	var fifths := key_fifths(key)
	var midis := []
	for n in notes:
		if n.semis != null:
			midis.append(base + int(n.semis))
	if clef < 0:
		clef = clef_for(midis)
	var bpm := maxf(1.0, beats_per_measure)

	var total := 0.0
	for n in notes:
		total += float(n.beats)
	var bars: Array = []
	var b := bar_offset if bar_offset > 0.001 else bpm
	while b < total - 0.001:
		bars.append(b)
		b += bpm

	var events: Array = []
	var t := 0.0
	var note_index := 0
	var acc_memory := {}     # step -> alter in force this bar
	var bar_i := 0
	for n in notes:
		var length := float(n.beats)
		var midi: int = -1 if n.semis == null else base + int(n.semis)
		var sp := spell(midi, fifths) if midi >= 0 else {}
		var first := true
		var first_piece := events.size()
		# Pieces: cut at bar lines, then into writable values.
		var end := t + length
		var cursor := t
		while cursor < end - 0.001:
			while bar_i < bars.size() and bars[bar_i] <= cursor + 0.001:
				bar_i += 1
				acc_memory.clear()
			var piece_end := end
			if bar_i < bars.size() and bars[bar_i] < end - 0.001:
				piece_end = bars[bar_i]
			var values := split_value(piece_end - cursor)
			for vi in values.size():
				var v: float = values[vi]
				var ev := {start = cursor, value = v, midi = midi, tie = false,
					acc = NO_ACCIDENTAL, lyric = "", note_index = -1, beam = -1}
				if midi >= 0:
					ev.step = sp.step
					if first:
						ev.note_index = note_index
						ev.lyric = n.get("lyric", "")
						var in_force: int = acc_memory.get(sp.step, key_alter(sp.letter, fifths))
						if sp.alter != in_force:
							ev.acc = sp.alter
					acc_memory[sp.step] = sp.alter
				events.append(ev)
				first = false
				cursor += v
		if midi >= 0:
			# Every piece of a note is tied to the next one.
			for j in range(first_piece, events.size() - 1):
				events[j].tie = true
			note_index += 1
		t = end

	_beam(events, bars, bpm, bar_offset)
	var lo := 999
	var hi := -999
	for ev in events:
		if ev.midi >= 0:
			lo = mini(lo, ev.step)
			hi = maxi(hi, ev.step)
	var bottom: int = BOTTOM_STEP[clef]
	return {fifths = fifths, clef = clef, events = events, bars = bars, total_beats = total,
		beats_per_measure = bpm, bottom_step = bottom, low_step = mini(lo, bottom), high_step = maxi(hi, bottom + 8),
		chromatic = _chromatic_midis(events, key)}


## Group eighths and sixteenths inside the same beat under one beam.
static func _beam(events: Array, bars: Array, bpm: float, bar_offset: float) -> void:
	var group_id := 0
	var i := 0
	while i < events.size():
		var group := []
		var beat := _beat_index(events[i].start, bars, bpm, bar_offset)
		var j := i
		while j < events.size() and events[j].midi >= 0 and events[j].value < 0.99 \
				and _beat_index(events[j].start, bars, bpm, bar_offset) == beat:
			group.append(j)
			j += 1
		if group.size() >= 2:
			for k in group:
				events[k].beam = group_id
			group_id += 1
			i = j
		else:
			i += 1


## A beat counter that restarts at each bar line (so beams never cross one).
static func _beat_index(start: float, bars: Array, _bpm: float, _bar_offset: float) -> Vector2i:
	var bar := 0
	var bar_start := 0.0
	for b in bars:
		if b <= start + 0.001:
			bar += 1
			bar_start = b
	return Vector2i(bar, floori(start - bar_start + 0.001))


static func _chromatic_midis(events: Array, key: MusicKey) -> Dictionary:
	var out := {}
	for ev in events:
		if ev.midi >= 0 and not key.is_in_key(ev.midi):
			out[ev.midi] = true
	return out


## Continuous staff position for a sung pitch. In-key notes (and the
## exercise's own outside-the-scale notes) sit exactly on their line or space;
## anything between them is placed in proportion to pitch, so singing a little
## flat shows just below the note.
static func pitch_step(midi: float, key: MusicKey, fifths: int, chromatic: Dictionary) -> float:
	var lo := floori(midi)
	while not (key.is_in_key(lo) or chromatic.has(lo)):
		lo -= 1
	var hi := lo + 1
	while not (key.is_in_key(hi) or chromatic.has(hi)):
		hi += 1
	var a := float(step_of(lo, fifths))
	var b := float(step_of(hi, fifths))
	if b <= a:
		return a   # same letter (F and F♯): both are written on that line
	return lerpf(a, b, (midi - lo) / float(hi - lo))
