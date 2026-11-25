extends Control
## Practice: one exercise at a time. Chords set the key, you hear the notes,
## then sing them while your pitch draws over the target bars.

const TEMPOS := [[0.5, "Slow"], [0.75, "Easy"], [1.0, "Normal"]]

var _exercises: Array = []
var _index := 0
var _title := ""
var _session: PracticeSession
var _key_played_for := -1        ## tonic pc whose cadence already played
var _tempo := 1.0

var _col: VBoxContainer
var _heading: Label
var _prompt: Label
var _status: Label
var _lyrics: Label
var _trace: PitchTrace
var _result: Label
var _start_button: Button
var _next_button: Button
var _tempo_buttons: Array[Button] = []
var _metronome: Button
var _view: Button
var _play_along: Button
var _hear_first: Button
var _countdown := 0             ## number last shown in the countdown
var _announced := ""
var _preview_targets: Array = []


func setup(args: Dictionary) -> void:
	_exercises = args.get("exercises", [])
	_index = args.get("index", 0)
	_title = args.get("title", "")
	_tempo = App.profile.tempo_scale
	_build()
	_load_exercise()
	if App.dev_autostart:
		_on_start.call_deferred()


func _build() -> void:
	_col = UI.page(self, false)
	var top := UI.row(_col)
	var back := UI.flat_button("‹ Back", func(): App.back())
	top.add_child(back)
	var t := Label.new()
	t.text = _title
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", UI.MUTED)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	top.add_child(t)
	# Top right: the playback sound (the web Manual link is hidden on this screen).
	top.add_child(_sound_picker())

	_heading = UI.title(_col, "", 56)
	_prompt = UI.muted(_col, "")
	_lyrics = UI.label(_col, "", 46)
	_lyrics.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = UI.label(_col, "", 44, UI.WARM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var picker := MicPicker.new()
	picker.only_when_silent = true
	_col.add_child(picker)
	var tip := App.ios_audio_tip()
	if tip != "":
		UI.muted(_col, tip, 30)

	_trace = PitchTrace.new()
	_trace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trace.custom_minimum_size = Vector2(0, 600)
	_trace.now_fraction = 0.3
	_trace.history_seconds = 1.8
	_trace.show_feedback = false
	_col.add_child(_trace)

	_result = UI.label(_col, "", 40)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var tempo_row := UI.row(_col)
	for tp in TEMPOS:
		var b := Button.new()
		b.text = tp[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 90)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 34)
		b.add_theme_color_override("font_pressed_color", UI.ACCENT)
		b.add_theme_color_override("font_hover_pressed_color", UI.ACCENT)
		b.button_pressed = is_equal_approx(tp[0], _tempo)
		b.pressed.connect(func(): _set_tempo(tp[0]))
		tempo_row.add_child(b)
		_tempo_buttons.append(b)

	var options := UI.row(_col)
	var options2 := UI.row(_col)
	_view = _toggle_button(options, App.profile.sheet_view)
	_view.toggled.connect(func(on: bool):
		App.profile.sheet_view = on
		App.profile.save()
		_label_view()
		_trace.view_sheet = on and _exercise().mode == Exercise.Mode.NOTES)
	_label_view()
	_hear_first = _toggle_button(options, App.profile.hear_first)
	_hear_first.toggled.connect(func(on: bool):
		App.profile.hear_first = on
		App.profile.save()
		if _session:
			_session.set_hear_first(on)
		_label_hear_first())
	_label_hear_first()
	_play_along = _toggle_button(options2, App.profile.play_along)
	_play_along.toggled.connect(func(on: bool):
		App.profile.play_along = on
		App.profile.save()
		if _session:
			_session.set_play_along(on)
		_label_play_along())
	_label_play_along()
	_metronome = _toggle_button(options2, App.profile.metronome)
	_metronome.toggled.connect(func(on: bool):
		App.profile.metronome = on
		App.profile.save()
		if _session:
			_session.set_metronome(on)
		_label_metronome())
	_label_metronome()

	var actions := UI.row(_col)
	_start_button = UI.button(actions, "Start", _on_start, true)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_button = UI.button(actions, "Next ›", _on_next)
	_next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## The playback sound (same choice as in Settings). Picking one plays a short
## sample when nothing is running; mid-exercise it applies from the next notes
## played (notes already scheduled keep their sound).
func _sound_picker() -> Control:
	var p := SoundPicker.new()
	p.can_preview = func() -> bool:
		return not _session or _session.phase in [PracticeSession.Phase.IDLE, PracticeSession.Phase.RESULT]
	return p


func _toggle_button(parent: Control, on: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 90)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_pressed_color", UI.ACCENT)
	b.add_theme_color_override("font_hover_pressed_color", UI.ACCENT)
	b.button_pressed = on
	parent.add_child(b)
	return b


func _label_view() -> void:
	_view.text = "Sheet music" if _view.button_pressed else "Solfège lanes"


func _label_hear_first() -> void:
	_hear_first.text = "Hear it first: on" if _hear_first.button_pressed else "Hear it first: off"


func _label_play_along() -> void:
	_play_along.text = "Play along: on" if _play_along.button_pressed else "Play along: off"


func _label_metronome() -> void:
	_metronome.text = "Metronome: on" if _metronome.button_pressed else "Metronome: off"


func _exercise() -> Exercise:
	return _exercises[_index]


func _load_exercise() -> void:
	var e := _exercise()
	App.profile.apply_to_key(e.key)
	_heading.text = e.title
	_prompt.text = e.prompt
	_lyrics.text = "“%s”" % e.lyrics if e.lyrics != "" else ""
	_lyrics.visible = e.lyrics != ""
	_status.text = "%d of %d" % [_index + 1, _exercises.size()]
	_result.text = ""
	_start_button.text = "Start"
	_next_button.visible = _index < _exercises.size() - 1
	_trace.set_key(e.key)
	# Sirens and slides have no beat to click.
	_metronome.visible = e.mode == Exercise.Mode.NOTES
	_view.visible = e.mode == Exercise.Mode.NOTES
	_play_along.visible = e.mode == Exercise.Mode.NOTES
	_hear_first.visible = e.mode == Exercise.Mode.NOTES
	_trace.now_fraction = 0.3
	_trace.history_seconds = 1.8
	_trace.zoomed_out = false
	_trace.clear()
	_load_notation(e)
	var preview := PracticeSession.new(e, App.profile, _tempo)
	_preview_targets = preview.reference
	if e.mode == Exercise.Mode.SIREN:
		_trace.fit_range(App.profile.voice_low, App.profile.voice_high)
	else:
		var lo := 999
		var hi := -999
		for n in preview.reference + preview.targets:
			lo = mini(lo, mini(n.midi, n.get("midi_end", n.midi)))
			hi = maxi(hi, maxi(n.midi, n.get("midi_end", n.midi)))
		_trace.fit_range(lo - 2, hi + 2)
	# A still preview: the first notes wait just past the line until Start.
	_trace.set_targets(preview.reference, App.pitch_source().now() + 1.0)
	_trace.park(1.0)


## The exercise as sheet music, in the learner's key (songs are already transposed).
func _load_notation(e: Exercise) -> void:
	if e.mode != Exercise.Mode.NOTES:
		_trace.clear_notation()
		_trace.view_sheet = false
		return
	var n := Notation.build(e.key, e.notes, e.base_for(App.profile), e.beats_per_measure, e.bar_offset_beats,
		Notation.clef_for([App.profile.voice_low, App.profile.voice_high]))
	var sung := Notation.key_name(e.key)
	var header := "Key: %s" % sung
	if e.original_key != null:
		var printed := Notation.key_name(e.original_key)
		header = "Printed in %s · sung in %s" % [printed, sung] if printed != sung else "Key: %s (as printed)" % sung
	_trace.set_notation(n, 60.0 / e.tempo_bpm / _tempo, header, App.profile.sheet_syllables)
	_trace.view_sheet = App.profile.sheet_view


func _set_tempo(t: float) -> void:
	_tempo = t
	App.profile.tempo_scale = t
	App.profile.save()
	for i in _tempo_buttons.size():
		_tempo_buttons[i].button_pressed = is_equal_approx(TEMPOS[i][0], t)
	if _session == null or _session.phase == PracticeSession.Phase.RESULT:
		_load_exercise()


func _on_start() -> void:
	if _session and _session.phase not in [PracticeSession.Phase.IDLE, PracticeSession.Phase.RESULT]:
		_session.stop()
		_session = null
		_load_exercise()
		return
	App.ensure_listening()
	var e := _exercise()
	_session = PracticeSession.new(e, App.profile, _tempo)
	_session.play_cadence = e.cadence_first and _key_played_for != e.key.tonic_pc
	_key_played_for = e.key.tonic_pc
	_session.phase_changed.connect(_on_phase)
	_session.finished.connect(_on_finished)
	_trace.now_fraction = 0.3
	_trace.history_seconds = 1.8
	_trace.zoomed_out = false
	_trace.set_results([])
	_trace.clear()
	_trace.clear_targets()
	_result.text = ""
	_start_button.text = "Stop"
	var fake := App.fake_singer()
	if fake:
		fake.quiet()
	_session.start(App.synth.engine)


func _on_phase(phase: PracticeSession.Phase) -> void:
	var P := PracticeSession.Phase
	match phase:
		P.CADENCE:
			_status.text = "Listen: this is home."
		P.LISTEN:
			_status.text = "Listen…"
			_trace.set_targets(_session.reference, App.pitch_source().now() + 0.1)
		P.COUNT_IN:
			_countdown = 0
			_show_countdown()
			if _exercise().mode == Exercise.Mode.NOTES:
				# The notes scroll in toward the line during the countdown.
				_trace.set_targets(_session.targets, App.pitch_source().now() + _session.count_in_left())
		P.SING:
			_status.text = {Exercise.Mode.SIREN: "Slide up and down!", Exercise.Mode.SLIDE_TO: "Slide to the note, then hold it!",
				Exercise.Mode.FOLLOW: "Follow the slide!"}.get(_exercise().mode, "Sing!")
			_trace.set_targets(_session.targets, _session.sing_origin_source)
			var fake := App.fake_singer()
			if fake:
				if _exercise().mode == Exercise.Mode.SIREN:
					fake.siren(App.profile.voice_low + 2, App.profile.voice_high - 3)
				else:
					fake.follow(_session.targets, _session.sing_origin_source)


## "3… 2… 1…" before the first note (melodies); a short "Your turn" otherwise.
func _show_countdown() -> void:
	if _exercise().mode != Exercise.Mode.NOTES:
		_status.text = "Your turn…"
		return
	var n := maxi(1, ceili(_session.count_in_left() - 0.001))
	if n != _countdown:
		_countdown = n
		_status.text = "Sing in %d…" % n


func _on_finished(results: Array[NoteResult]) -> void:
	# Freeze and zoom out so the whole attempt stays visible over the targets.
	_trace.now_fraction = 0.97
	_trace.history_seconds = _session.length_seconds() + 0.6
	_trace.zoomed_out = true
	_trace.set_results(results)
	_status.text = ""
	_result.text = PracticeSession.summary(results, _exercise().key)
	_start_button.text = "Again"
	_next_button.visible = _index < _exercises.size() - 1
	if _index == _exercises.size() - 1:
		_next_button.visible = true
		_next_button.text = "Done"


func _on_next() -> void:
	if _session:
		_session.stop()
		_session = null
	if _index >= _exercises.size() - 1:
		App.back()
		return
	_index += 1
	_load_exercise()


func _process(_delta: float) -> void:
	var src := App.pitch_source()
	var frames := src.poll()
	var frozen := _session != null and _session.phase == PracticeSession.Phase.RESULT
	if not frozen:
		for f in frames:
			_trace.push_frame(f)
		_trace.set_now(src.now())
	if src.state == PitchSource.State.ERROR:
		_status.text = "I can't hear the microphone. Check the browser's permission."
	if _session:
		_session.update(frames, src.now())
		if _session and _session.phase == PracticeSession.Phase.COUNT_IN:
			_show_countdown()
	_announce_target(src)


## Tell the app (and the XR hand sign) which syllable is being aimed at.
func _announce_target(src: PitchSource) -> void:
	var targets: Array = _session.targets if _session and not _session.targets.is_empty() else _preview_targets
	if targets.is_empty():
		return
	var midi: float = targets[0].midi
	if _session and _session.phase == PracticeSession.Phase.SING:
		var t := _session.sing_elapsed(src.now())
		for tg in targets:
			if t >= tg.start - 0.15:
				midi = tg.midi
				# Halfway through a glide, show where it's heading.
				if tg.has("midi_end") and t > tg.start + tg.duration * 0.5:
					midi = tg.midi_end
	var syl := _exercise().key.syllable_of(roundi(midi))
	if syl != _announced:
		_announced = syl
		App.target_syllable_changed.emit(syl)


func _exit_tree() -> void:
	if _session:
		_session.stop()
