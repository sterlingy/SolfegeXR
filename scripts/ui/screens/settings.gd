extends Control
## Settings: solfège toggles, headphones, practice speed, range, data.

var _confirm_reset := false
var _reset_button: Button


func setup(_args: Dictionary) -> void:
	var col := UI.page(self)
	var p := App.profile
	UI.back_button(col)
	UI.title(col, "Settings", 56)

	var syl := UI.card(col)
	UI.label(syl, "Minor-key syllables", 44)
	UI.muted(syl, "Your progress is kept either way; only the names change.")
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(0, UI.BUTTON_H)
	opt.add_theme_font_size_override("font_size", 40)
	opt.get_popup().add_theme_font_size_override("font_size", 40)
	opt.add_item("La-based (home is la)", MusicKey.MinorSyllables.LA_BASED)
	opt.add_item("Do-based (home is do)", MusicKey.MinorSyllables.DO_BASED)
	opt.select(p.minor_syllables)
	opt.item_selected.connect(func(i): _apply(func(): p.minor_syllables = opt.get_item_id(i)))
	syl.add_child(opt)
	UI.toggle(syl, "Chromatic syllables (fi, te…)", p.chromatic_enabled,
		func(on): _apply(func(): p.chromatic_enabled = on))
	UI.toggle(syl, "Solfège under the sheet music", p.sheet_syllables,
		func(on): _apply(func(): p.sheet_syllables = on))

	var snd := UI.card(col)
	UI.label(snd, "Playback sound", 44)
	UI.muted(snd, "The voice that plays notes for you, the drone and the chords.", 30)
	var timbre := OptionButton.new()
	timbre.custom_minimum_size = Vector2(0, UI.BUTTON_H)
	timbre.add_theme_font_size_override("font_size", 40)
	timbre.get_popup().add_theme_font_size_override("font_size", 40)
	for i in SynthEngine.TIMBRE_NAMES.size():
		timbre.add_item(SynthEngine.TIMBRE_NAMES[i], i)
	timbre.select(p.timbre)
	timbre.item_selected.connect(func(i):
		_apply(func(): p.timbre = timbre.get_item_id(i))
		App.synth.engine.timbre = p.timbre as SynthEngine.Timbre
		_preview())
	snd.add_child(timbre)
	UI.button(snd, "Hear it", _preview)

	var mic := UI.card(col)
	UI.label(mic, "Microphone", 44)
	UI.muted(mic, "If the app can't hear you, try another input here.", 30)
	mic.add_child(MicPicker.new())

	var gear := UI.card(col)
	UI.toggle(gear, "I have headphones", p.has_headphones, func(on): _apply(func(): p.has_headphones = on))
	UI.muted(gear, "Needed for backing tracks and singing with other voices.", 30)

	var voice := UI.card(col)
	UI.label(voice, "Your range: %s to %s" % [UI.note_name(p.voice_low), UI.note_name(p.voice_high)], 40)
	UI.button(voice, "Test my range again", func(): App.go("range_test"))

	if not OS.has_feature("web") or OS.is_debug_build():
		var dev := UI.card(col)
		UI.label(dev, "Developer", 40)
		UI.toggle(dev, "Demo singer instead of microphone", App.use_demo_singer,
			func(on): App.use_demo_singer = on)

	var help := UI.card(col)
	UI.label(help, "Help", 40)
	UI.button(help, "User manual", func(): App.open_manual())
	UI.button(help, "Check timing", func(): App.go("latency_check"))

	var data := UI.card(col)
	UI.label(data, "Your data", 40)
	UI.muted(data, "Progress is saved only on this device.")
	UI.button(data, "Privacy", func(): App.open_site_page("privacy"))
	_reset_button = UI.button(data, "Reset all progress", _on_reset)


func _apply(change: Callable) -> void:
	change.call()
	App.profile.save()


## do, mi, sol, do in the middle of the learner's range, in the chosen sound.
func _preview() -> void:
	var e := App.synth.engine
	e.release_all()
	var tonic := (App.profile.voice_low + App.profile.voice_high) / 2 - 4
	var at := e.time() + 0.05
	for i in 4:
		e.note(tonic + [0, 4, 7, 12][i], at + i * 0.45, 0.42 if i < 3 else 0.9)


func _on_reset() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		_reset_button.text = "Tap again to erase everything"
		return
	var fresh := LearnerProfile.new()
	fresh.save()
	App.profile = fresh
	App.synth.engine.timbre = SynthEngine.Timbre.WARM
	App.home()
	App.go("onboarding", {}, false)
