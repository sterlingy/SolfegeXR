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
var _trace: PitchTrace
var _result: Label
var _start_button: Button
var _next_button: Button
var _tempo_buttons: Array[Button] = []


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
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(t)

	_heading = UI.title(_col, "", 56)
	_prompt = UI.muted(_col, "")
	_status = UI.label(_col, "", 44, UI.WARM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

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

	var actions := UI.row(_col)
	_start_button = UI.button(actions, "Start", _on_start, true)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_button = UI.button(actions, "Next ›", _on_next)
	_next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _exercise() -> Exercise:
	return _exercises[_index]


func _load_exercise() -> void:
	var e := _exercise()
	App.profile.apply_to_key(e.key)
	_heading.text = e.title
	_prompt.text = e.prompt
	_status.text = "%d of %d" % [_index + 1, _exercises.size()]
	_result.text = ""
	_start_button.text = "Start"
	_next_button.visible = _index < _exercises.size() - 1
	_trace.set_key(e.key)
	_trace.now_fraction = 0.3
	_trace.history_seconds = 1.8
	_trace.clear()
	var preview := PracticeSession.new(e, App.profile, _tempo)
	var lo := 999
	var hi := -999
	for n in preview.targets:
		lo = mini(lo, n.midi)
		hi = maxi(hi, n.midi)
	_trace.fit_range(lo - 2, hi + 2)
	_trace.set_targets(preview.targets, App.pitch_source().now() + 1.0)


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
			_trace.set_targets(_session.targets, App.pitch_source().now() + 0.1)
		P.COUNT_IN:
			_status.text = "Your turn…"
		P.SING:
			_status.text = "Sing!"
			_trace.set_targets(_session.targets, _session.sing_origin_source)
			var fake := App.fake_singer()
			if fake:
				fake.follow(_session.targets, _session.sing_origin_source)


func _on_finished(results: Array[NoteResult]) -> void:
	# Freeze and zoom out so the whole attempt stays visible over the targets.
	_trace.now_fraction = 0.97
	_trace.history_seconds = _session.length_seconds() + 0.6
	_trace.queue_redraw()
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


func _exit_tree() -> void:
	if _session:
		_session.stop()
