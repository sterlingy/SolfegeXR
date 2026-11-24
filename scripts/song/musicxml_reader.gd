class_name MusicXmlReader
extends RefCounted
## Reads MusicXML (score-partwise, .musicxml/.xml, or compressed .mxl) into a Song.
## Uses Godot's XMLParser, a streaming (SAX-style) reader.
##
## Every line of the score becomes its own Song.Part: each (part, staff,
## voice) is a line, and a line written in chords (soprano and alto sharing
## stems) splits into a top and a bottom line, so a two-staff SATB hymn gives
## four parts. Lines are named from the part name ("Soprano/Alto"), as S/A/T/B
## for a four-line choir part, or "Piano, line 2". Ties are merged; breath
## marks and lyrics are kept, and wordless lower voices borrow the melody's.

const STEP_SEMITONES := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


static func load_file(path: String) -> Song:
	var bytes: PackedByteArray
	if path.get_extension().to_lower() == "mxl":
		bytes = _read_mxl(path)
	else:
		bytes = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("MusicXML: couldn't read " + path)
		return null
	var song := parse(bytes)
	if song and song.title == "":
		song.title = path.get_file().get_basename().capitalize()
	return song


static func _read_mxl(path: String) -> PackedByteArray:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return PackedByteArray()
	var root_file := ""
	if zip.file_exists("META-INF/container.xml"):
		var p := XMLParser.new()
		p.open_buffer(zip.read_file("META-INF/container.xml"))
		while p.read() == OK:
			if p.get_node_type() == XMLParser.NODE_ELEMENT and p.get_node_name() == "rootfile":
				root_file = p.get_named_attribute_value_safe("full-path")
				break
	if root_file == "":
		for f in zip.get_files():
			if f.ends_with(".xml") and not f.begins_with("META-INF"):
				root_file = f
				break
	var data := zip.read_file(root_file) if root_file != "" else PackedByteArray()
	zip.close()
	return data


static func parse(bytes: PackedByteArray) -> Song:
	var p := XMLParser.new()
	if p.open_buffer(bytes) != OK:
		return null
	var song := Song.new()
	var part_names := {}
	var part_name := ""
	var lanes := {}            # "staff/voice" -> Array of events, for the current part
	var lane_order: Array[String] = []
	var divisions := 1.0
	var cursor := 0.0          # beats, position within the part
	var measure_index := 0
	var path: Array[String] = []
	var note := {}             # fields of the note being read
	var pending_part_id := ""
	var tempo_set := false
	var in_part := false

	while p.read() == OK:
		var type := p.get_node_type()
		if type == XMLParser.NODE_ELEMENT:
			var name := p.get_node_name()
			var empty := p.is_empty()
			match name:
				"score-part":
					pending_part_id = p.get_named_attribute_value_safe("id")
				"part":
					part_name = part_names.get(p.get_named_attribute_value_safe("id"), "Part %d" % (song.parts.size() + 1))
					lanes = {}
					lane_order = []
					cursor = 0.0
					measure_index = 0
					in_part = true
				"note":
					note = {chord = false, rest = false, step = "", alter = 0.0, octave = 4,
						duration = 0.0, voice = "1", staff = "1", tie_start = false,
						tie_stop = false, lyric = "", syllabic = "", breath = false, grace = false}
				"chord":
					note.chord = true
				"rest":
					note.rest = true
				"grace":
					note.grace = true
				"tie":
					if p.get_named_attribute_value_safe("type") == "start":
						note.tie_start = true
					else:
						note.tie_stop = true
				"breath-mark", "caesura":
					if not note.is_empty():
						note.breath = true
				"sound":
					var t := p.get_named_attribute_value_safe("tempo")
					if t != "" and not tempo_set:
						song.tempo_bpm = t.to_float()
						tempo_set = true
			if not empty:
				path.append(name)
		elif type == XMLParser.NODE_ELEMENT_END:
			var name := p.get_node_name()
			if not path.is_empty():
				path.pop_back()
			match name:
				"measure":
					measure_index += 1
				"note":
					if in_part and not note.grace:
						_collect(lanes, lane_order, note, divisions, cursor, measure_index)
						if not note.chord:
							cursor += note.duration / divisions
					note = {}
				"part":
					_add_lines(song, part_name, lanes, lane_order)
					in_part = false
		elif type == XMLParser.NODE_TEXT:
			var text := p.get_node_data().strip_edges()
			if text == "" or path.is_empty():
				continue
			var leaf: String = path[-1]
			var parent: String = path[-2] if path.size() > 1 else ""
			match leaf:
				"work-title", "movement-title":
					if song.title == "":
						song.title = text
				"part-name":
					if pending_part_id != "":
						part_names[pending_part_id] = text
				"divisions":
					divisions = maxf(1.0, text.to_float())
				"fifths":
					song.key_fifths = text.to_int()
					song.has_key_signature = true
				"mode":
					song.key_mode = text.to_lower()
				"beats":
					song.beats_per_measure = text.to_float()
				"beat-type":
					song.beats_per_measure *= 4.0 / text.to_float()
				"per-minute":
					if not tempo_set:
						song.tempo_bpm = text.to_float()
						tempo_set = true
				"step":
					if parent == "pitch":
						note.step = text
				"alter":
					if parent == "pitch":
						note.alter = text.to_float()
				"octave":
					if parent == "pitch":
						note.octave = text.to_int()
				"duration":
					if parent == "note":
						note.duration = text.to_float()
					elif parent == "backup":
						cursor -= text.to_float() / divisions
					elif parent == "forward":
						cursor += text.to_float() / divisions
				"voice":
					if parent == "note":
						note.voice = text
				"staff":
					if parent == "note":
						note.staff = text
				"text":
					if parent == "lyric" and not note.is_empty() and note.lyric == "":
						note.lyric = text
				"syllabic":
					if parent == "lyric" and not note.is_empty() and note.syllabic == "":
						note.syllabic = text
	share_lyrics(song)
	return song


## Files one <note> under its staff/voice line. A chord note joins the event
## before it.
static func _collect(lanes: Dictionary, order: Array[String], n: Dictionary, divisions: float,
		cursor: float, measure: int) -> void:
	var key := "%s/%s" % [n.staff, n.voice]
	if not lanes.has(key):
		lanes[key] = []
		order.append(key)
	var events: Array = lanes[key]
	var midi := -1
	if not n.rest:
		midi = 12 * (n.octave + 1) + STEP_SEMITONES.get(n.step, 0) + roundi(n.alter)
	if n.chord and not events.is_empty():
		var last: Dictionary = events[-1]
		if midi >= 0:
			last.pitches.append(midi)
			if n.tie_start:
				last.tie_start[midi] = true
			if n.tie_stop:
				last.tie_stop[midi] = true
		last.breath = last.breath or n.breath
		if last.lyric == "" and n.lyric != "":
			last.lyric = n.lyric
			last.syllabic = n.syllabic
		return
	var ev := {start = cursor, duration = n.duration / divisions, pitches = [], tie_start = {},
		tie_stop = {}, lyric = n.lyric, syllabic = n.syllabic, breath = n.breath, measure = measure}
	if midi >= 0:
		ev.pitches.append(midi)
		if n.tie_start:
			ev.tie_start[midi] = true
		if n.tie_stop:
			ev.tie_stop[midi] = true
	events.append(ev)


## Turns one part's lines into Song.Parts: top staff first, and within a
## staff the highest line first.
static func _add_lines(song: Song, part_name: String, lanes: Dictionary, order: Array[String]) -> void:
	var lines: Array = []    # {notes, pitch, staff}
	for key in order:
		var events: Array = lanes[key]
		var chords := false
		for ev in events:
			if ev.pitches.size() > 1:
				chords = true
		var staff := (key as String).get_slice("/", 0).to_int()
		var made: Array = [_line(events, true)]
		if chords:
			made.append(_line(events, false))
		for notes: Array[Song.Note] in made:
			if _has_sound(notes):
				lines.append({notes = notes, pitch = _mean_pitch(notes), staff = staff})
	if lines.is_empty():
		var empty := Song.Part.new()
		empty.name = part_name
		song.parts.append(empty)
		return
	lines.sort_custom(func(a, b): return a.staff < b.staff or (a.staff == b.staff and a.pitch > b.pitch))
	var names := _line_names(part_name, lines.size(), song.parts.is_empty())
	for i in lines.size():
		var part := Song.Part.new()
		part.name = names[i]
		part.notes.assign(lines[i].notes)
		song.parts.append(part)


## One line from a staff/voice: the top (or bottom) note of each chord, ties
## merged, rests merged, gaps filled with rests.
static func _line(events: Array, top: bool) -> Array[Song.Note]:
	var out: Array[Song.Note] = []
	var tie_open: Song.Note = null
	for ev in events:
		var midi := -1
		if not ev.pitches.is_empty():
			midi = ev.pitches.max() if top else ev.pitches.min()
		var end_prev := out[-1].end() if not out.is_empty() else 0.0
		if ev.start > end_prev + 0.001:
			_append_rest(out, end_prev, ev.start - end_prev, ev.measure)
			tie_open = null
		if midi >= 0 and tie_open != null and tie_open.midi == midi and ev.tie_stop.has(midi):
			tie_open.duration += ev.duration
			tie_open.breath_after = tie_open.breath_after or ev.breath
			if not ev.tie_start.has(midi):
				tie_open = null
			continue
		if midi < 0:
			_append_rest(out, ev.start, ev.duration, ev.measure)
			tie_open = null
			continue
		var note := Song.Note.new()
		note.midi = midi
		note.start = ev.start
		note.duration = ev.duration
		note.lyric = ev.lyric
		note.syllabic = ev.syllabic
		note.breath_after = ev.breath
		note.measure = ev.measure
		out.append(note)
		tie_open = note if ev.tie_start.has(midi) else null
	return out


static func _append_rest(out: Array[Song.Note], start: float, beats: float, measure: int) -> void:
	if not out.is_empty() and out[-1].is_rest():
		out[-1].duration += beats
		return
	var r := Song.Note.new()
	r.midi = -1
	r.start = start
	r.duration = beats
	r.measure = measure
	out.append(r)


static func _has_sound(notes: Array[Song.Note]) -> bool:
	for n in notes:
		if not n.is_rest():
			return true
	return false


static func _mean_pitch(notes: Array[Song.Note]) -> float:
	var sum := 0.0
	var beats := 0.0
	for n in notes:
		if not n.is_rest():
			sum += n.midi * n.duration
			beats += n.duration
	return sum / maxf(beats, 0.001)


const VOICE_WORDS := {"soprano": "Soprano", "sopranos": "Soprano", "alto": "Alto", "altos": "Alto",
	"tenor": "Tenor", "tenors": "Tenor", "bass": "Bass", "basses": "Bass", "baritone": "Baritone",
	"mezzo": "Mezzo", "s": "Soprano", "a": "Alto", "t": "Tenor", "b": "Bass"}


## Names for a part's lines, highest first. "Soprano/Alto" with two lines
## gives Soprano and Alto; a choir part (or a lone unnamed one) with four
## lines gives Soprano, Alto, Tenor, Bass; otherwise "Piano, line 2".
static func _line_names(part_name: String, count: int, first_part: bool) -> Array[String]:
	var out: Array[String] = []
	if count == 1:
		out.append(part_name)
		return out
	var cleaned := part_name.to_lower()
	for sep in ["/", ",", "&", "+", "-", ".", "(", ")"]:
		cleaned = cleaned.replace(sep, " ")
	var tokens := cleaned.split(" ", false)
	for w in tokens:
		if VOICE_WORDS.has(w):
			out.append(VOICE_WORDS[w])
	if out.size() == count:
		return out
	out.clear()
	var choir := false
	for w in ["choir", "chorus", "satb", "voices", "vocal"]:
		if w in tokens:
			choir = true
	if count == 4 and (choir or (first_part and part_name.begins_with("Part "))):
		out.assign(["Soprano", "Alto", "Tenor", "Bass"])
		return out
	for i in count:
		out.append("%s, line %d" % [part_name, i + 1])
	return out


## Lower voices of a hymn usually have no words of their own: each wordless
## note borrows the melody's syllable that starts at the same moment.
static func share_lyrics(song: Song) -> void:
	if song.parts.size() < 2:
		return
	var melody := song.melody()
	var by_start := {}
	for n in melody.notes:
		if n.lyric != "":
			by_start[snappedf(n.start, 0.001)] = n
	if by_start.is_empty():
		return
	for part in song.parts:
		if part == melody:
			continue
		var has_words := false
		for n in part.notes:
			if n.lyric != "":
				has_words = true
				break
		if has_words:
			continue
		for n in part.notes:
			var m: Song.Note = by_start.get(snappedf(n.start, 0.001))
			if m != null and not n.is_rest():
				n.lyric = m.lyric
				n.syllabic = m.syllabic
