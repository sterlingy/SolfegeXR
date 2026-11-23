extends TestCase
## Sheet music view: key signatures, spelling, layout, and where a sung pitch
## lands on the staff.

const M := MusicKey.Mode


func _spelled(midi: int, fifths: int) -> String:
	var s := Notation.spell(midi, fifths)
	return "%s%s%d" % [Notation.LETTERS[s.letter], {1: "#", -1: "b", 0: ""}[s.alter], s.octave]


func test_key_signatures_for_every_tonic_and_mode() -> void:
	assert_eq(Notation.key_fifths(MusicKey.new(0, M.IONIAN)), 0)
	assert_eq(Notation.key_fifths(MusicKey.new(7, M.IONIAN)), 1, "G major")
	assert_eq(Notation.key_fifths(MusicKey.new(5, M.IONIAN)), -1, "F major")
	assert_eq(Notation.key_fifths(MusicKey.new(4, M.AEOLIAN)), 1, "E minor")
	assert_eq(Notation.key_fifths(MusicKey.new(2, M.AEOLIAN)), -1, "D minor")
	assert_eq(Notation.key_fifths(MusicKey.new(2, M.DORIAN)), 0, "D dorian")
	assert_eq(Notation.key_fifths(MusicKey.new(1, M.IONIAN)), -5, "D-flat, not C-sharp")
	assert_eq(Notation.key_fifths(MusicKey.new(6, M.IONIAN)), -6, "G-flat on the tie")
	assert_eq(Notation.key_fifths(MusicKey.new(11, M.IONIAN)), 5, "B, not C-flat")
	for pc in 12:
		for mode in 7:
			assert_true(absi(Notation.key_fifths(MusicKey.new(pc, mode))) <= 6)


func test_key_names_are_spelled() -> void:
	assert_eq(Notation.key_name(MusicKey.new(4, M.AEOLIAN)), "E minor")
	assert_eq(Notation.key_name(MusicKey.new(10, M.IONIAN)), "B♭ major")
	assert_eq(Notation.key_name(MusicKey.new(3, M.AEOLIAN)), "E♭ minor")
	assert_eq(Notation.key_name(MusicKey.new(6, M.AEOLIAN)), "F♯ minor")


func test_spelling_in_and_out_of_the_key() -> void:
	assert_eq(_spelled(66, 1), "F#4", "G major's F#")
	assert_eq(_spelled(70, -1), "Bb4", "F major's Bb")
	assert_eq(_spelled(66, 0), "F#4", "fi in C")
	assert_eq(_spelled(70, 0), "Bb4", "te in C")
	assert_eq(_spelled(71, -1), "B4", "fi in F is B natural, not C-flat")
	assert_eq(_spelled(61, -1), "C#4", "leading tone of D minor")
	assert_eq(_spelled(63, 1), "D#4", "leading tone of E minor")
	assert_eq(_spelled(67, 4), "G4", "me in E major is G natural, no double sharp")
	assert_eq(_spelled(60, 0), "C4")
	assert_eq(Notation.step_of(60, 0), 28, "middle C")
	assert_eq(Notation.step_of(64, 0), 30, "treble bottom line")


func test_clef_follows_the_voice() -> void:
	assert_eq(Notation.clef_for([60, 64, 67, 72]), Notation.Clef.TREBLE)
	assert_eq(Notation.clef_for([48, 52, 55, 60]), Notation.Clef.BASS)


func test_note_values_split_and_tie_across_bar_lines() -> void:
	var key := MusicKey.new(0)
	# 4/4: a dotted half, then a half that crosses the bar line.
	var notes := [{semis = 0, beats = 3.0}, {semis = 2, beats = 2.0}, {semis = 4, beats = 3.0}]
	var n := Notation.build(key, notes, 60, 4.0, 0.0)
	assert_eq(n.bars, [4.0], "one bar line")
	var ev: Array = n.events
	assert_eq(ev.size(), 4, "the half splits into two tied quarters")
	assert_eq(ev[1].value, 1.0)
	assert_true(ev[1].tie, "tied over the bar line")
	assert_eq(ev[2].value, 1.0)
	assert_false(ev[2].tie)
	assert_eq(ev[2].note_index, -1, "the continuation isn't a new note")
	assert_eq(ev[3].note_index, 2)
	assert_eq(ev[3].value, 3.0)


func test_pickup_bar_lines_and_rests() -> void:
	var key := MusicKey.new(4, M.AEOLIAN)
	var notes := [{semis = 0, beats = 1.0}, {semis = 0, beats = 1.0}, {semis = null, beats = 1.0}, {semis = 7, beats = 2.0}]
	var n := Notation.build(key, notes, 64, 4.0, 1.0)
	assert_eq(n.bars, [1.0], "first bar line after the one-beat pickup")
	assert_eq(n.events[2].midi, -1, "rest")
	assert_eq(n.events[3].note_index, 2, "rests don't count as notes")


func test_eighths_in_one_beat_share_a_beam() -> void:
	var key := MusicKey.new(7)
	var notes := [{semis = 0, beats = 2.0}, {semis = 4, beats = 0.5}, {semis = 2, beats = 0.5}, {semis = 0, beats = 1.0},
		{semis = 2, beats = 0.5}]
	var n := Notation.build(key, notes, 67, 4.0, 0.0)
	var ev: Array = n.events
	assert_true(ev[1].beam >= 0)
	assert_eq(ev[1].beam, ev[2].beam)
	assert_eq(ev[3].beam, -1, "quarter")
	assert_eq(ev[4].beam, -1, "a lone eighth gets a flag")


func test_accidentals_show_once_per_bar() -> void:
	var key := MusicKey.new(0)
	var notes := [{semis = 6, beats = 1.0}, {semis = 6, beats = 1.0}, {semis = 5, beats = 2.0}, {semis = 6, beats = 1.0}]
	var n := Notation.build(key, notes, 60, 4.0, 0.0)
	var ev: Array = n.events
	assert_eq(ev[0].acc, 1, "F#")
	assert_eq(ev[1].acc, Notation.NO_ACCIDENTAL, "still sharp in this bar")
	assert_eq(ev[2].acc, 0, "natural sign to cancel it")
	assert_eq(ev[3].acc, 1, "new bar: sharp again")


func test_sung_pitch_sits_between_lines_in_proportion() -> void:
	var key := MusicKey.new(0)
	var none := {}
	assert_near(Notation.pitch_step(64.0, key, 0, none), 30.0, 0.001, "E on the line")
	assert_near(Notation.pitch_step(67.0, key, 0, none), 32.0, 0.001, "G")
	assert_near(Notation.pitch_step(66.5, key, 0, none), 31.75, 0.001, "a quarter tone flat of G sits just below")
	assert_near(Notation.pitch_step(64.5, key, 0, none), 30.5, 0.001, "halfway from E to F")
	assert_near(Notation.pitch_step(66.0, key, 0, none), 31.5, 0.001, "F# between F and G when it isn't in the music")
	assert_near(Notation.pitch_step(66.0, key, 0, {66: true}), 31.0, 0.001, "F# written on the F line when it is")


func test_every_shift_of_a_song_lays_out() -> void:
	var a := SongAnalyzer.analyze(MusicXmlReader.load_file("res://songs/12_god_rest_you_merry.musicxml"))
	for shift in range(-12, 12):
		var key := MusicKey.new(a.key.tonic_pc + shift, a.key.mode)
		var notes := []
		for n in a.notes:
			notes.append({semis = n.midi + shift - key.tonic_pc, beats = n.duration})
		var n := Notation.build(key, notes, key.tonic_pc, a.song.beats_per_measure, 1.0)
		var count := 0
		for ev in n.events:
			if ev.note_index >= 0:
				count += 1
			assert_true(ev.midi < 0 or abs(ev.step - Notation.step_of(ev.midi, n.fifths)) == 0)
		assert_eq(count, a.notes.size(), "shift %d: every note drawn once" % shift)
		assert_true(absi(n.fifths) <= 6)


func _sheet_trace(song: String, beats_limit := 9999.0) -> PitchTrace:
	var a := SongAnalyzer.analyze(MusicXmlReader.load_file("res://songs/%s.musicxml" % song))
	var key := a.key
	var notes := []
	var t := 0.0
	for n in a.notes:
		if t >= beats_limit:
			break
		notes.append({semis = n.midi - key.tonic_pc, beats = n.duration})
		t += n.duration
	var tr := PitchTrace.new()
	tr.size = Vector2(1000, 600)
	tr.set_key(key)
	tr.set_notation(Notation.build(key, notes, key.tonic_pc, a.song.beats_per_measure, 1.0), 0.4)
	tr.fit_range(60, 80)
	tr.view_sheet = true
	return tr


func test_a_perfectly_sung_note_draws_on_its_notehead() -> void:
	var tr := _sheet_trace("12_god_rest_you_merry")
	tr._sheet.layout(tr)
	for midi in [64, 66, 67, 71, 72, 74, 76]:
		assert_near(tr._y_of(float(midi)), tr._sheet.y_of_step(Notation.step_of(midi, 1)), 0.01, "midi %d" % midi)
	assert_true(tr._y_of(66.6) < tr._y_of(66.0), "a little sharp draws a little higher")
	tr.free()


func test_after_singing_a_short_phrase_fits_and_a_whole_song_scrolls() -> void:
	var short := _sheet_trace("12_god_rest_you_merry", 6.0)
	short.zoomed_out = true
	short.now_fraction = 0.97
	short.history_seconds = 6.0 * 0.4 + 0.6
	short._sheet.layout(short)
	assert_true(short._sheet.fits_whole, "two bars fit")
	var whole := _sheet_trace("12_god_rest_you_merry")
	whole.zoomed_out = true
	whole.now_fraction = 0.97
	whole.history_seconds = 77.0 * 0.4 + 0.6
	whole._sheet.layout(whole)
	assert_false(whole._sheet.fits_whole, "the whole song stays readable and scrolls instead")
	short.free()
	whole.free()


func test_preview_stays_still_until_start() -> void:
	var tr := PitchTrace.new()
	tr.set_targets([{midi = 60, start = 0.0, duration = 1.0}], 10.0)
	tr.park(1.0)
	tr.set_now(20.0)
	assert_near(tr._targets[0].start, 21.0, 0.001, "first note waits one second ahead")
	tr.set_now(25.0)
	assert_near(tr._targets[0].start, 26.0, 0.001)
	assert_near(tr.sheet_origin(), 26.0, 0.001, "sheet music moves with it")
	tr.set_targets([{midi = 60, start = 0.0, duration = 1.0}], 30.0)
	tr.set_now(31.0)
	assert_near(tr._targets[0].start, 30.0, 0.001, "a real run scrolls again")
	tr.free()
