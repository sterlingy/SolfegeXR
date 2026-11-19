extends TestCase
## MusicXML / MIDI import and the analysis pipeline, on the curated songs.

const EXPECTED_KEYS := {
	"01_ode_to_joy": [0, MusicKey.Mode.IONIAN],
	"02_when_the_saints": [0, MusicKey.Mode.IONIAN],
	"03_coming_round_the_mountain": [7, MusicKey.Mode.IONIAN],
	"04_oh_susanna": [0, MusicKey.Mode.IONIAN],
	"05_auld_lang_syne": [5, MusicKey.Mode.IONIAN],
	"06_amazing_grace": [7, MusicKey.Mode.IONIAN],
	"07_drunken_sailor": [2, MusicKey.Mode.DORIAN],
	"08_take_me_out_to_the_ball_game": [0, MusicKey.Mode.IONIAN],
	"09_shenandoah": [2, MusicKey.Mode.IONIAN],
	"10_danny_boy": [0, MusicKey.Mode.IONIAN],
	"11_carol_of_the_bells": [7, MusicKey.Mode.AEOLIAN],
	"12_god_rest_you_merry": [4, MusicKey.Mode.AEOLIAN],
}
var S := Skills.Id


func _load(id: String) -> Song:
	return MusicXmlReader.load_file("res://songs/%s.musicxml" % id)


func test_catalog_songs_parse_with_expected_keys() -> void:
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://songs/catalog.json"))
	assert_eq(catalog.size(), 12)
	for entry in catalog:
		var song := MusicXmlReader.load_file(entry.file)
		assert_true(song != null, "parse " + entry.id)
		if song == null:
			continue
		assert_true(song.melody().sounding_notes().size() >= 8, "notes in " + entry.id)
		var key := KeyFinder.find(song)
		var want: Array = EXPECTED_KEYS[entry.id]
		assert_eq([key.tonic_pc, key.mode], want, "key of " + entry.id)


func test_ode_degrees_phrases_skills() -> void:
	var r := SongAnalyzer.analyze(_load("01_ode_to_joy"))
	assert_eq(r.key.name(), "C Major")
	var degrees := []
	for i in 4:
		degrees.append(r.key.degree_syllable(r.notes[i].degree))
	assert_eq(degrees, ["mi", "mi", "fa", "sol"])
	assert_eq(r.phrases.size(), 4, "phrases split at breath marks")
	assert_true(r.needs(S.STEPS))
	assert_true(r.needs(S.SMALL_LEAPS), "E-C in bar 9")
	assert_true(r.needs(S.LARGE_LEAPS), "D-G3 in bar 12")
	assert_false(r.needs(S.CHROMATIC))
	assert_false(r.needs(S.MINOR_MODES))
	assert_eq(r.low, 55)
	assert_eq(r.high, 67)
	var leap: Dictionary = r.skills[S.LARGE_LEAPS][0]
	assert_eq(leap.interval, -7)
	assert_eq(leap.measure, 11, "0-based measure of the leap")


func test_chromatic_and_mode_tags() -> void:
	assert_true(SongAnalyzer.analyze(_load("08_take_me_out_to_the_ball_game")).needs(S.CHROMATIC))
	var sailor := SongAnalyzer.analyze(_load("07_drunken_sailor"))
	assert_true(sailor.needs(S.MINOR_MODES))
	assert_eq(sailor.key.degree_syllable(0), "re", "La-based Dorian starts on re")


func test_mode_found_from_final_note_when_unstated() -> void:
	var song := _load("07_drunken_sailor")
	song.key_mode = ""
	var key := KeyFinder.find(song)
	assert_eq([key.tonic_pc, key.mode], [2, MusicKey.Mode.DORIAN])


func test_key_found_without_signature() -> void:
	for id in ["01_ode_to_joy", "05_auld_lang_syne", "06_amazing_grace"]:
		var song := _load(id)
		song.has_key_signature = false
		var key := KeyFinder.find(song)
		var want: Array = EXPECTED_KEYS[id]
		assert_eq(key.tonic_pc, want[0], "tonic of " + id)


func test_ties_merge() -> void:
	var notes := _load("06_amazing_grace").melody().sounding_notes()
	var longest := 0.0
	for n in notes:
		longest = maxf(longest, n.duration)
	assert_near(longest, 5.0, 0.001, "D5 tied across the bar line")


func test_carol_is_an_ensemble() -> void:
	var song := _load("11_carol_of_the_bells")
	assert_eq(song.parts.size(), 4)
	assert_eq(song.parts[0].name, "Bells (ostinato)")
	assert_true(SongAnalyzer.analyze(song).needs(S.ENSEMBLE))
	var ostinato := song.parts[0].sounding_notes()
	assert_eq([ostinato[0].midi, ostinato[1].midi, ostinato[2].midi, ostinato[3].midi], [70, 69, 70, 67])


func test_midi_matches_musicxml() -> void:
	var xml := _load("01_ode_to_joy").melody().sounding_notes()
	var mid_song := MidiReader.load_file("res://tests/fixtures/ode_to_joy.mid")
	assert_true(mid_song != null, "midi parsed")
	var mid := mid_song.melody().sounding_notes()
	assert_eq(mid.size(), xml.size(), "note count")
	for i in mini(mid.size(), xml.size()):
		if mid[i].midi != xml[i].midi or absf(mid[i].start - xml[i].start) > 0.01:
			fail("note %d differs: midi %d@%s vs xml %d@%s" % [i, mid[i].midi, mid[i].start, xml[i].midi, xml[i].start])
			break
	assert_near(mid_song.tempo_bpm, 100.0, 0.5)
	assert_eq(KeyFinder.find(mid_song).name(), "C Major")


func test_transpose_into_voice() -> void:
	var r := SongAnalyzer.analyze(_load("01_ode_to_joy"))  # G3..G4
	var shift := r.transposition_for(45, 62)  # low voice A2..D4
	assert_true(r.low + shift >= 45 and r.high + shift <= 62, "fits: shift %d" % shift)
	var danny := SongAnalyzer.analyze(_load("10_danny_boy"))
	var s2 := danny.transposition_for(50, 64)  # narrow range: keep the top reachable
	assert_eq(danny.high + s2, 64)


func test_targets_in_seconds() -> void:
	var r := SongAnalyzer.analyze(_load("01_ode_to_joy"))  # 100 bpm
	var t := r.targets(2, 0.5, 0, 3)
	assert_eq(t.size(), 4)
	assert_eq(t[0].midi, 66)
	assert_near(t[1].start, 1.2, 0.001, "0.6 s per beat at half speed")
