extends Control
## Import your own song: MusicXML (.musicxml, .xml, .mxl) or MIDI (.mid).
## Web: the browser's file chooser (web/file_picker.js). Desktop: Godot's FileDialog.

const ACCEPT := ".musicxml,.xml,.mxl,.mid,.midi,application/vnd.recordare.musicxml+xml,application/vnd.recordare.musicxml,audio/midi,audio/x-midi"

var _status: Label
var _choose: Button
var _js: JavaScriptObject
var _waiting := false


func setup(_args: Dictionary) -> void:
	var col := UI.page(self)
	UI.back_button(col)
	UI.title(col, "Import a song", 56)
	UI.label(col, "Bring your own song as sheet music, and the app builds a course for it in your key.")
	var how := UI.card(col)
	UI.label(how, "Which files work", 40)
	UI.muted(how, "• MusicXML: in MuseScore, File → Export → MusicXML (.musicxml or .mxl).")
	UI.muted(how, "• MIDI (.mid): works best when the tune is on its own track.")
	UI.muted(how, "The first part with notes is used as the melody. The file stays on this device.")
	_choose = UI.button(col, "Choose a file", _on_choose, true)
	_status = UI.label(col, "", 38, UI.WARM)
	if OS.has_feature("web"):
		JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/file_picker.js"), true)
		_js = JavaScriptBridge.get_interface("solfegeFiles")


func _on_choose() -> void:
	_status.text = ""
	if _js:
		_js.pick(ACCEPT)
		_waiting = true
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.musicxml, *.xml, *.mxl ; MusicXML", "*.mid, *.midi ; MIDI"])
	dlg.use_native_dialog = true
	dlg.file_selected.connect(func(path: String):
		_import(path.get_file(), FileAccess.get_file_as_bytes(path)))
	add_child(dlg)
	dlg.popup_centered_ratio(0.8)


func _process(_delta: float) -> void:
	if not _waiting or _js == null:
		return
	match str(_js.state):
		"reading":
			_status.text = "Reading…"
		"cancelled":
			_waiting = false
			_status.text = ""
		"error":
			_waiting = false
			_status.text = str(_js.error)
		"done":
			_waiting = false
			var picked: Dictionary = JSON.parse_string(str(_js.take()))
			_import(picked.name, Marshalls.base64_to_raw(picked.b64))


func _import(file_name: String, bytes: PackedByteArray) -> void:
	_status.text = "Reading %s…" % file_name
	var r := SongLibrary.import_bytes(file_name, bytes)
	if not r.ok:
		_status.text = r.error
		return
	App.go("course", {song_id = r.id}, false)
