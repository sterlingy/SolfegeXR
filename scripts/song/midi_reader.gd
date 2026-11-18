class_name MidiReader
extends RefCounted
## Minimal Standard MIDI File reader (format 0 and 1). Godot has no .mid
## importer, so this parses the bytes directly.
## Each track (or each channel, for format 0) with notes becomes a Song.Part.
## Polyphony inside a track is reduced to the top voice.


static func load_file(path: String) -> Song:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("MIDI: couldn't read " + path)
		return null
	var song := parse(bytes)
	if song and song.title == "":
		song.title = path.get_file().get_basename().capitalize()
	return song


static func parse(b: PackedByteArray) -> Song:
	if b.size() < 14 or b.slice(0, 4).get_string_from_ascii() != "MThd":
		return null
	var format := _u16(b, 8)
	var track_count := _u16(b, 10)
	var division := _u16(b, 12)
	if division & 0x8000:
		push_error("MIDI: SMPTE time division not supported")
		return null
	var tpq := float(division)
	var song := Song.new()
	var pos := 8 + _u32(b, 4)
	var tempo_set := false
	for t in track_count:
		if pos + 8 > b.size() or b.slice(pos, pos + 4).get_string_from_ascii() != "MTrk":
			break
		var length := _u32(b, pos + 4)
		var end := pos + 8 + length
		var i := pos + 8
		var tick := 0
		var running := 0
		var track_name := ""
		var open := {}        # key: channel*128+note -> start tick
		var events := []      # [start_tick, end_tick, note, channel]
		var lyrics := {}      # tick -> text (meta 0x05)
		while i < end:
			var vlq := _vlq(b, i)
			tick += vlq[0]
			i = vlq[1]
			var status := b[i]
			if status < 0x80:
				status = running
			else:
				i += 1
			if status == 0xFF:
				var meta := b[i]
				var len_v := _vlq(b, i + 1)
				var data := b.slice(len_v[1], len_v[1] + len_v[0])
				i = len_v[1] + len_v[0]
				match meta:
					0x03:
						track_name = data.get_string_from_utf8()
					0x05:
						var text := data.get_string_from_utf8().strip_edges()
						if text != "":
							lyrics[tick] = text
					0x51:
						if not tempo_set and data.size() == 3:
							var us := (data[0] << 16) | (data[1] << 8) | data[2]
							song.tempo_bpm = 60000000.0 / us
							tempo_set = true
					0x58:
						if data.size() >= 2:
							song.beats_per_measure = data[0] * 4.0 / pow(2.0, data[1])
					0x59:
						if data.size() == 2:
							song.key_fifths = data[0] - 256 if data[0] > 127 else data[0]
							song.key_mode = "minor" if data[1] == 1 else "major"
							song.has_key_signature = true
				continue
			if status == 0xF0 or status == 0xF7:
				var len_s := _vlq(b, i)
				i = len_s[1] + len_s[0]
				continue
			running = status
			var kind := status & 0xF0
			var ch := status & 0x0F
			match kind:
				0x80, 0x90:
					var key := b[i]
					var vel := b[i + 1]
					i += 2
					var id := ch * 128 + key
					if kind == 0x90 and vel > 0:
						if not open.has(id):
							open[id] = tick
					elif open.has(id):
						events.append([open[id], tick, key, ch])
						open.erase(id)
				0xA0, 0xB0, 0xE0:
					i += 2
				0xC0, 0xD0:
					i += 1
				_:
					i += 1
		pos = end
		if events.is_empty():
			if song.title == "" and track_name != "" and format == 1 and t == 0:
				song.title = track_name
			continue
		# Format 0: split by channel. Format 1: one part per track.
		var by_channel := {}
		for e in events:
			var key: int = e[3] if format == 0 else 0
			if not by_channel.has(key):
				by_channel[key] = []
			by_channel[key].append(e)
		for key in by_channel:
			var part := _events_to_part(by_channel[key], tpq, song.beats_per_measure, lyrics)
			part.name = track_name if track_name != "" else "Part %d" % (song.parts.size() + 1)
			song.parts.append(part)
	return song


static func _events_to_part(events: Array, tpq: float, beats_per_measure: float, lyrics := {}) -> Song.Part:
	events.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[2] > b[2]))
	var part := Song.Part.new()
	var cursor := 0.0
	for e in events:
		var start: float = e[0] / tpq
		var end: float = e[1] / tpq
		if not part.notes.is_empty() and start < part.notes[-1].end() - 1e-6:
			continue  # overlapping (chord/polyphony): keep the earlier/top note
		if start > cursor + 1e-6:
			var rest := Song.Note.new()
			rest.midi = -1
			rest.start = cursor
			rest.duration = start - cursor
			part.notes.append(rest)
		var n := Song.Note.new()
		n.midi = e[2]
		n.start = start
		n.duration = end - start
		n.measure = int(start / beats_per_measure)
		if lyrics.has(e[0]):
			# Karaoke-style MIDI: a trailing "-" means the word continues.
			var text: String = lyrics[e[0]]
			n.lyric = text.trim_suffix("-")
			n.syllabic = "begin" if text.ends_with("-") else "single"
		part.notes.append(n)
		cursor = end
	return part


static func _u16(b: PackedByteArray, i: int) -> int:
	return (b[i] << 8) | b[i + 1]


static func _u32(b: PackedByteArray, i: int) -> int:
	return (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]


## Variable-length quantity: returns [value, next_index].
static func _vlq(b: PackedByteArray, i: int) -> Array:
	var v := 0
	while true:
		var c := b[i]
		i += 1
		v = (v << 7) | (c & 0x7F)
		if c < 0x80:
			break
	return [v, i]
