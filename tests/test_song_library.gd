extends TestCase
## Importing the learner's own songs.

const TEST_DIR := "user://test_songs"


func before_each() -> void:
	SongLibrary.dir = TEST_DIR
	for e in SongLibrary.list():
		SongLibrary.remove(e.id)


func test_import_musicxml() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://songs/07_drunken_sailor.musicxml")
	var r := SongLibrary.import_bytes("Drunken Sailor.musicxml", bytes)
	assert_true(r.ok, str(r))
	assert_eq(r.title, "Drunken Sailor")
	assert_eq(SongLibrary.list().size(), 1)
	var song := SongLibrary.parse_file(SongLibrary.find(r.id).file)
	assert_eq(KeyFinder.find(song).name(), "D Dorian")


func test_import_midi_uses_file_name_when_untitled() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/ode_to_joy.mid")
	var r := SongLibrary.import_bytes("my tune.mid", bytes)
	assert_true(r.ok, str(r))
	assert_eq(r.title, "Ode to Joy", "MIDI track/title meta is used when present")
	var a := SongAnalyzer.analyze(SongLibrary.parse_file(SongLibrary.find(r.id).file))
	assert_eq(a.notes.size(), 62)


func test_import_compressed_mxl() -> void:
	var xml := FileAccess.get_file_as_bytes("res://songs/01_ode_to_joy.musicxml")
	var zpath := "user://test_ode.mxl"
	var z := ZIPPacker.new()
	assert_eq(z.open(zpath), OK)
	z.start_file("META-INF/container.xml")
	z.write_file('<?xml version="1.0"?><container><rootfiles><rootfile full-path="score.xml"/></rootfiles></container>'.to_utf8_buffer())
	z.close_file()
	z.start_file("score.xml")
	z.write_file(xml)
	z.close_file()
	z.close()
	var r := SongLibrary.import_bytes("Ode.mxl", FileAccess.get_file_as_bytes(zpath))
	assert_true(r.ok, str(r))
	assert_eq(SongAnalyzer.analyze(SongLibrary.parse_file(SongLibrary.find(r.id).file)).notes.size(), 62)
	DirAccess.remove_absolute(zpath)


func test_rejects_garbage_and_wrong_types() -> void:
	var bad := SongLibrary.import_bytes("notes.musicxml", "this is not xml at all".to_utf8_buffer())
	assert_false(bad.ok)
	assert_true(bad.error.contains("melody"), bad.error)
	var pdf := SongLibrary.import_bytes("score.pdf", "%PDF-1.7".to_utf8_buffer())
	assert_false(pdf.ok)
	assert_true(pdf.error.contains("MusicXML"), pdf.error)
	assert_false(SongLibrary.import_bytes("empty.mid", PackedByteArray()).ok)
	assert_eq(SongLibrary.list().size(), 0, "nothing saved for failed imports")
	assert_eq(DirAccess.get_files_at(TEST_DIR).size(), 1, "only the index file remains")


func test_remove() -> void:
	var r := SongLibrary.import_bytes("Saints.musicxml", FileAccess.get_file_as_bytes("res://songs/02_when_the_saints.musicxml"))
	var path: String = SongLibrary.find(r.id).file
	SongLibrary.remove(r.id)
	assert_eq(SongLibrary.list().size(), 0)
	assert_false(FileAccess.file_exists(path), "file deleted")


func test_course_from_imported_song() -> void:
	var r := SongLibrary.import_bytes("Amazing Grace.musicxml", FileAccess.get_file_as_bytes("res://songs/06_amazing_grace.musicxml"))
	var a := SongAnalyzer.analyze(SongLibrary.parse_file(SongLibrary.find(r.id).file))
	var c := CourseBuilder.build(a, LearnerProfile.new())
	assert_true(c.steps.size() > 5, "course has drills and phrases")
	assert_true(c.steps.any(func(e): return e.title == "The whole song"))
