extends TestCase
## Choosing a voice: every line of a score is a part, the course follows the
## part the learner picks, and the choice is saved per song.

const M := MusicKey.Mode


func _note(step: String, octave: int, voice: int, staff: int, beats := 1, alter := 0, chord := false,
		lyric := "", tie := "") -> String:
	var x := "<note>"
	if chord:
		x += "<chord/>"
	x += "<pitch><step>%s</step>%s<octave>%d</octave></pitch>" % [step, "<alter>%d</alter>" % alter if alter != 0 else "", octave]
	x += "<duration>%d</duration>" % beats
	if tie != "":
		x += "<tie type=\"%s\"/>" % tie
	x += "<voice>%d</voice><staff>%d</staff>" % [voice, staff]
	if lyric != "":
		x += "<lyric><syllabic>single</syllabic><text>%s</text></lyric>" % lyric
	return x + "</note>"


func _score(part_name: String, measures: Array) -> Song:
	var x := "<?xml version=\"1.0\"?><score-partwise><part-list><score-part id=\"P1\"><part-name>%s</part-name></score-part></part-list><part id=\"P1\">" % part_name
	for i in measures.size():
		x += "<measure number=\"%d\">" % (i + 1)
		if i == 0:
			x += "<attributes><divisions>1</divisions><key><fifths>1</fifths><mode>minor</mode></key><time><beats>2</beats><beat-type>4</beat-type></time><staves>2</staves></attributes>"
		x += measures[i] + "</measure>"
	x += "</part></score-partwise>"
	return MusicXmlReader.parse(x.to_utf8_buffer())


## Closed-score SATB: S and A as voices 1 and 2 on the top staff, T and B as
## voices 3 and 4 on the bottom, with <backup> between them, as MuseScore writes.
func _closed_score(part_name := "Choir") -> Song:
	var m1 := _note("B", 4, 1, 1, 1, 0, false, "God") + _note("A", 4, 1, 1, 1, 0, false, "rest") \
		+ "<backup><duration>2</duration></backup>" + _note("E", 4, 2, 1) + _note("D", 4, 2, 1, 1, 1) \
		+ "<backup><duration>2</duration></backup>" + _note("G", 3, 3, 2) + _note("F", 3, 3, 2, 1, 1) \
		+ "<backup><duration>2</duration></backup>" + _note("E", 3, 4, 2) + _note("B", 2, 4, 2)
	var m2 := _note("E", 4, 1, 1, 2, 0, false, "ye") \
		+ "<backup><duration>2</duration></backup>" + _note("E", 4, 2, 1, 2) \
		+ "<backup><duration>2</duration></backup>" + _note("G", 3, 3, 2, 2) \
		+ "<backup><duration>2</duration></backup>" + _note("E", 3, 4, 2, 2)
	return _score(part_name, [m1, m2])


func _midis(p: Song.Part) -> Array:
	var out := []
	for n in p.sounding_notes():
		out.append(n.midi)
	return out


func test_a_two_staff_choir_score_gives_four_voices() -> void:
	var song := _closed_score()
	var names := []
	for p in song.parts:
		names.append(p.name)
	assert_eq(names, ["Soprano", "Alto", "Tenor", "Bass"])
	assert_eq(_midis(song.parts[0]), [71, 69, 64])
	assert_eq(_midis(song.parts[1]), [64, 63, 64], "alto, with its D sharp")
	assert_eq(_midis(song.parts[2]), [55, 54, 55])
	assert_eq(_midis(song.parts[3]), [52, 47, 52])
	assert_eq(song.melody(), song.parts[0], "the soprano is still the melody")


func test_lower_voices_borrow_the_melody_words() -> void:
	var song := _closed_score()
	var words := []
	for n in song.parts[3].sounding_notes():
		words.append(n.lyric)
	assert_eq(words, ["God", "rest", "ye"])


func test_soprano_and_alto_written_as_chords_split_in_two() -> void:
	var m1 := _note("B", 4, 1, 1) + _note("E", 4, 1, 1, 1, 0, true) \
		+ _note("A", 4, 1, 1) + _note("D", 4, 1, 1, 1, 1, true)
	var m2 := _note("G", 4, 1, 1, 2, 0, false, "", "start") + _note("E", 4, 1, 1, 2, 0, true, "", "start")
	var m3 := _note("G", 4, 1, 1, 1, 0, false, "", "stop") + _note("E", 4, 1, 1, 1, 0, true, "", "stop") \
		+ _note("F", 4, 1, 1, 1, 1)
	var song := _score("Soprano/Alto", [m1, m2, m3])
	assert_eq(song.parts.size(), 2)
	assert_eq([song.parts[0].name, song.parts[1].name], ["Soprano", "Alto"])
	assert_eq(_midis(song.parts[0]), [71, 69, 67, 66])
	assert_eq(_midis(song.parts[1]), [64, 63, 64, 66], "the tie holds the alto's E; a single note is shared")
	assert_near(song.parts[1].sounding_notes()[2].duration, 3.0, 0.001, "tied over the bar line")


func test_other_parts_with_several_lines_are_numbered() -> void:
	var song := _closed_score("Piano")
	assert_eq(song.parts[2].name, "Piano, line 3")


func test_one_line_parts_keep_their_names() -> void:
	var song := MusicXmlReader.load_file("res://songs/11_carol_of_the_bells.musicxml")
	assert_eq(song.parts.size(), 4)
	assert_eq(song.parts[3].name, "Bass")


func test_god_rest_ye_has_all_four_voices_in_one_key() -> void:
	var song := MusicXmlReader.load_file("res://songs/12_god_rest_you_merry.musicxml")
	var names := []
	for p in song.singable_parts():
		names.append(p.name)
		var a := SongAnalyzer.analyze(song, p)
		assert_eq([a.key.tonic_pc, a.key.mode], [4, M.AEOLIAN], p.name + " is in E minor, like the melody")
		assert_near(p.notes[-1].end(), song.parts[0].notes[-1].end(), 0.001, p.name + " ends with the others")
	assert_eq(names, ["Soprano", "Alto", "Tenor", "Bass"])


func _profile(low: int, high: int) -> LearnerProfile:
	var p := LearnerProfile.new()
	p.voice_low = low
	p.voice_high = high
	return p


func test_the_part_that_fits_a_voice_is_suggested() -> void:
	var song := MusicXmlReader.load_file("res://songs/12_god_rest_you_merry.musicxml")
	assert_eq(App.best_fit_part(song, _profile(60, 79)).name, "Soprano", "high voice")
	assert_true(App.best_fit_part(song, _profile(43, 60)).name in ["Tenor", "Bass"], "low voice")


func test_the_course_follows_the_chosen_part() -> void:
	var song := MusicXmlReader.load_file("res://songs/12_god_rest_you_merry.musicxml")
	var p := _profile(43, 62)
	assert_eq(App.part_for(song, "12_god_rest_you_merry", p).name, "Soprano", "melody until a choice is made")
	p.song_parts["12_god_rest_you_merry"] = "Bass"
	var part := App.part_for(song, "12_god_rest_you_merry", p)
	assert_eq(part.name, "Bass")
	var a := SongAnalyzer.analyze(song, part)
	var c := CourseBuilder.build(a, p)
	assert_true(a.low + c.transpose >= p.voice_low and a.high + c.transpose <= p.voice_high, "bass line in range")
	var whole: Exercise = null
	for e in c.steps:
		if e.title == "The whole song":
			whole = e
	assert_true(whole != null)
	var sung := 0
	for n in whole.notes:
		if n.semis != null:
			sung += 1
	assert_eq(sung, a.notes.size(), "every note of the bass line (rests aside)")
	var finale: Exercise = c.steps[-1]
	var others := []
	for o in finale.parts:
		others.append(o.name)
	assert_eq(others, ["Soprano", "Alto", "Tenor"], "the other voices sing with you")


func test_an_unknown_saved_part_falls_back_to_the_melody() -> void:
	var song := MusicXmlReader.load_file("res://songs/01_ode_to_joy.musicxml")
	var p := _profile(48, 67)
	p.song_parts["01_ode_to_joy"] = "Tenor"
	assert_eq(App.part_for(song, "01_ode_to_joy", p), song.melody())


func test_the_choice_is_saved() -> void:
	var p := _profile(48, 67)
	p.song_parts["12_god_rest_you_merry"] = "Alto"
	var back := LearnerProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(back.song_parts, {"12_god_rest_you_merry": "Alto"})
