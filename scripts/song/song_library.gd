class_name SongLibrary
extends RefCounted
## The learner's own imported songs (MusicXML or MIDI), saved on this device
## under user://songs/ (in a browser that's the site's local storage).
## Index: user://songs/index.json = [{id, title, file, kind, imported_on, notes}]

const DIR := "user://songs"
const INDEX := "user://songs/index.json"
const EXTENSIONS := ["musicxml", "xml", "mxl", "mid", "midi"]
const MIN_NOTES := 4

## Where the library lives (tests point this elsewhere).
static var dir := DIR


static func _index_path() -> String:
	return dir.path_join("index.json")


static func list() -> Array:
	if not FileAccess.file_exists(_index_path()):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_index_path()))
	return parsed if parsed is Array else []


## Parse a song file from any supported format. Returns null if unreadable.
static func parse_file(path: String) -> Song:
	match path.get_extension().to_lower():
		"mid", "midi":
			return MidiReader.load_file(path)
		"musicxml", "xml", "mxl":
			return MusicXmlReader.load_file(path)
	return null


## Import a file's bytes. Returns {ok: true, id, title} or {ok: false, error}.
static func import_bytes(file_name: String, bytes: PackedByteArray) -> Dictionary:
	var ext := file_name.get_extension().to_lower()
	if ext not in EXTENSIONS:
		return {ok = false, error = "That isn't a song file this app can read. Use MusicXML (.musicxml, .mxl) or MIDI (.mid)."}
	if bytes.is_empty():
		return {ok = false, error = "That file is empty."}
	DirAccess.make_dir_recursive_absolute(dir)
	var id := "%d_%s" % [Time.get_unix_time_from_system(), _slug(file_name.get_basename())]
	var path := dir.path_join(id + "." + ext)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {ok = false, error = "Couldn't save the song on this device."}
	f.store_buffer(bytes)
	f.close()

	var song := parse_file(path)
	var notes := 0
	if song:
		notes = song.melody().sounding_notes().size()
	if song == null or notes < MIN_NOTES:
		DirAccess.remove_absolute(path)
		return {ok = false, error = "I couldn't find a melody in that file. MusicXML from MuseScore, or a MIDI file with the tune on its own track, work best."}

	# Readers fall back to the (internal) saved file name; use the learner's instead.
	var title := song.title
	if title == "" or title == path.get_file().get_basename().capitalize():
		title = file_name.get_basename().capitalize()
	var entries := list()
	entries.append({id = id, title = title, file = path, kind = ext,
		imported_on = Time.get_date_string_from_system(), notes = notes})
	_save_index(entries)
	return {ok = true, id = id, title = title}


static func remove(id: String) -> void:
	var keep := []
	for e in list():
		if e.id == id:
			DirAccess.remove_absolute(e.file)
		else:
			keep.append(e)
	_save_index(keep)


static func find(id: String) -> Dictionary:
	for e in list():
		if e.id == id:
			return e
	return {}


static func _save_index(entries: Array) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(_index_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(entries, "  "))


static func _slug(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	return out.substr(0, 40).strip_edges()
