class_name MusicXmlReader
extends RefCounted
## Reads MusicXML (score-partwise, .musicxml/.xml, or compressed .mxl) into a Song.
## Uses Godot's XMLParser, a streaming (SAX-style) reader.
##
## Melody extraction per part: voice 1 of staff 1; in chords, the top note.
## Ties are merged into one note. Breath marks and lyrics are kept.

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
	var part: Song.Part = null
	var divisions := 1.0
	var cursor := 0.0          # beats, position within the part
	var measure_index := 0
	var measure_start := 0.0
	var path: Array[String] = []
	var note := {}             # fields of the note being read
	var tie_open: Song.Note = null
	var pending_part_id := ""
	var tempo_set := false

	while p.read() == OK:
		var type := p.get_node_type()
		if type == XMLParser.NODE_ELEMENT:
			var name := p.get_node_name()
			var empty := p.is_empty()
			match name:
				"score-part":
					pending_part_id = p.get_named_attribute_value_safe("id")
				"part":
					part = Song.Part.new()
					part.name = part_names.get(p.get_named_attribute_value_safe("id"), "Part %d" % (song.parts.size() + 1))
					song.parts.append(part)
					cursor = 0.0
					measure_index = 0
					tie_open = null
				"measure":
					measure_start = cursor
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
					if part != null and not note.grace:
						tie_open = _commit_note(song, part, note, divisions, cursor, measure_index, tie_open)
						if not note.chord:
							cursor += note.duration / divisions
					note = {}
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
	return song


## Adds the note to the part (melody voice only). Returns the note that a
## following tie should extend, or null.
static func _commit_note(song: Song, part: Song.Part, n: Dictionary, divisions: float,
		cursor: float, measure: int, tie_open: Song.Note) -> Song.Note:
	if n.voice != "1" or n.staff != "1":
		return tie_open
	var beats: float = n.duration / divisions
	var midi := -1
	if not n.rest:
		midi = 12 * (n.octave + 1) + STEP_SEMITONES.get(n.step, 0) + roundi(n.alter)
	if n.chord:
		# Keep the top note of a chord as the melody.
		if not part.notes.is_empty() and midi > part.notes[-1].midi:
			part.notes[-1].midi = midi
		return tie_open
	if n.tie_stop and tie_open != null and tie_open.midi == midi:
		tie_open.duration += beats
		tie_open.breath_after = tie_open.breath_after or n.breath
		return tie_open if n.tie_start else null
	var note := Song.Note.new()
	note.midi = midi
	note.start = cursor
	note.duration = beats
	note.lyric = n.lyric
	note.syllabic = n.syllabic
	note.breath_after = n.breath
	note.measure = measure
	# Merge consecutive rests.
	if note.is_rest() and not part.notes.is_empty() and part.notes[-1].is_rest():
		part.notes[-1].duration += beats
		return null
	part.notes.append(note)
	return note if n.tie_start else null
