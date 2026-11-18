extends TestCase
## Lyrics travel from song files to the practice screen.


func test_syllables_join_into_words() -> void:
	assert_eq(Song.lyric_line(["Shall", "we", "ga-", "ther-", "ing"]), "Shall we gathering")
	assert_eq(Song.lyric_line(["", "la", "", "la"]), "la la")
	assert_eq(Song.lyric_text("ga", "begin"), "ga-")
	assert_eq(Song.lyric_text("ing", "end"), "ing")


func test_musicxml_lyrics_and_phrases() -> void:
	var a := SongAnalyzer.analyze(MusicXmlReader.load_file("res://tests/fixtures/lyrics_test.musicxml"))
	assert_true(a.has_lyrics())
	assert_eq(a.notes[2].lyric_display(), "ga-")
	assert_eq(a.phrases.size(), 2, "breath mark + rest split the phrases")
	assert_eq(a.lyric_line(a.phrases[0].x, a.phrases[0].y), "Shall we gathering")
	assert_eq(a.lyric_line(a.phrases[1].x, a.phrases[1].y), "at home")


func test_course_phrases_carry_lyrics() -> void:
	var a := SongAnalyzer.analyze(MusicXmlReader.load_file("res://tests/fixtures/lyrics_test.musicxml"))
	var c := CourseBuilder.build(a, LearnerProfile.new())
	var phrase: Exercise = null
	for e in c.steps:
		if e.title == "Phrase 1":
			phrase = e
	assert_true(phrase != null)
	if phrase == null:
		return
	assert_eq(phrase.lyrics, "Shall we gathering")
	var t := phrase.realize_for(LearnerProfile.new())
	assert_eq(t.size(), 5)
	assert_eq(t[2].lyric, "ga-", "each target carries its syllable")


func test_midi_karaoke_lyrics() -> void:
	var song := MidiReader.load_file("res://tests/fixtures/lyrics_test.mid")
	var notes := song.melody().sounding_notes()
	assert_eq(notes.size(), 4)
	assert_eq(notes[2].lyric_display(), "ga-")
	var a := SongAnalyzer.analyze(song)
	assert_eq(a.lyric_line(0, 3), "Shall we gather")


func test_songs_without_lyrics_unchanged() -> void:
	var a := SongAnalyzer.analyze(MusicXmlReader.load_file("res://songs/01_ode_to_joy.musicxml"))
	assert_false(a.has_lyrics())
	var c := CourseBuilder.build(a, LearnerProfile.new())
	assert_eq(c.steps[-1].lyrics, "")
