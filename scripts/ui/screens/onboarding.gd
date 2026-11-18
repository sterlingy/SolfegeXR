extends Control
## First run: welcome, the two solfège settings, headphones. Then the range test.

var _col: VBoxContainer
var _step := 0


func setup(_args: Dictionary) -> void:
	_show()


func _show() -> void:
	if _col:
		_col.get_parent().get_parent().queue_free()
		for c in get_children():
			c.queue_free()
	_col = UI.page(self)
	var p := App.profile
	match _step:
		0:
			UI.title(_col, "Let's find your voice")
			UI.label(_col, "Most people who think they can't sing were just never taught. You're new at this, not bad at it.")
			UI.label(_col, "We'll start by matching single notes, then learn the syllables do re mi, then sing real songs in a key that suits your voice.")
			UI.muted(_col, "Everything stays on this device. Nothing is shared.")
			UI.button(_col, "Let's go", _next, true)
		1:
			UI.title(_col, "Syllables in minor keys", 56)
			UI.label(_col, "Songs in minor keys can be sung two ways. You can change this any time in Settings.")
			var la := UI.card(_col)
			UI.label(la, "La-based (recommended)", 44, UI.WARM)
			UI.muted(la, "Syllables follow the key signature, so a minor song's home note is la.")
			UI.button(la, "Use la-based", func():
				p.minor_syllables = MusicKey.MinorSyllables.LA_BASED
				_next(), true)
			var doc := UI.card(_col)
			UI.label(doc, "Do-based", 44, UI.WARM)
			UI.muted(doc, "Home is always do; minor notes become me, le and te.")
			UI.button(doc, "Use do-based", func():
				p.minor_syllables = MusicKey.MinorSyllables.DO_BASED
				_next())
		2:
			UI.title(_col, "Notes outside the scale", 56)
			UI.label(_col, "Some songs use notes from outside their key. Learning their syllables (like fi and te) is easier once the basics feel solid.")
			UI.muted(_col, "Until then you'll still sing them; they're just marked \"outside the scale\".")
			UI.toggle(_col, "Learn chromatic syllables now", p.chromatic_enabled, func(on): p.chromatic_enabled = on)
			UI.button(_col, "Continue", _next, true)
		3:
			UI.title(_col, "Headphones?", 56)
			UI.label(_col, "Later lessons sing along with music and other voices. For those you'll need headphones, so the microphone only hears you.")
			if App.is_ios():
				UI.muted(_col, "On iPhone, headphones also keep the tones clear while the microphone is on.")
			UI.button(_col, "I have headphones", func():
				p.has_headphones = true
				_next(), true)
			UI.button(_col, "Not right now", func():
				p.has_headphones = false
				_next())
		_:
			p.onboarded = true
			p.save()
			App.go("range_test", {first_run = true}, false)


func _next() -> void:
	_step += 1
	_show()
