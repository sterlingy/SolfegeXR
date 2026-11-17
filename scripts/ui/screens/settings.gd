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
	opt.add_item("La-based (home is la)", MusicKey.MinorSyllables.LA_BASED)
	opt.add_item("Do-based (home is do)", MusicKey.MinorSyllables.DO_BASED)
	opt.select(p.minor_syllables)
	opt.item_selected.connect(func(i): _apply(func(): p.minor_syllables = opt.get_item_id(i)))
	syl.add_child(opt)
	UI.toggle(syl, "Chromatic syllables (fi, te…)", p.chromatic_enabled,
		func(on): _apply(func(): p.chromatic_enabled = on))

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

	var data := UI.card(col)
	UI.label(data, "Your data", 40)
	UI.muted(data, "Progress is saved only on this device.")
	_reset_button = UI.button(data, "Reset all progress", _on_reset)


func _apply(change: Callable) -> void:
	change.call()
	App.profile.save()


func _on_reset() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		_reset_button.text = "Tap again to erase everything"
		return
	var fresh := LearnerProfile.new()
	fresh.save()
	App.profile = fresh
	App.home()
	App.go("onboarding", {}, false)
