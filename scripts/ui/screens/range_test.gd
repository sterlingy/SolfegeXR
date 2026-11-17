extends Control
## Range test: slide down to your lowest easy note, then up to your highest.

const PHASE_SECONDS := 6.0

enum Phase { INTRO, LOW, HIGH, DONE }

var _phase := Phase.INTRO
var _test := RangeTest.new()
var _col: VBoxContainer
var _trace: PitchTrace
var _status: Label
var _timer := 0.0
var _first_run := false
var _result := Vector2i(-1, -1)


func setup(args: Dictionary) -> void:
	_first_run = args.get("first_run", false)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_col = UI.page(self, false)
	if not _first_run:
		UI.back_button(_col)
	UI.title(_col, "Your singing range", 56)
	match _phase:
		Phase.INTRO:
			UI.label(_col, "We'll find the notes that are comfortable for you, so every song fits your voice.")
			UI.label(_col, "First, slide your voice down like a sigh, \"ooo\", to the lowest note that still feels easy. Then slide up.")
			UI.muted(_col, "Don't push. Comfortable is the goal, not impressive.")
			_spacer()
			UI.button(_col, "Start", _begin, true)
			UI.button(_col, "Skip: choose a voice type", _show_presets)
		Phase.LOW, Phase.HIGH:
			_status = UI.label(_col, "", 48, UI.WARM)
			_trace = PitchTrace.new()
			_trace.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_trace.key = MusicKey.new(0)
			_trace.span_semitones = 40.0
			_trace.center_midi = 57.0
			_trace.history_seconds = 3.0
			_trace.show_feedback = false
			_col.add_child(_trace)
			_update_status()
		Phase.DONE:
			if _result.x < 0:
				UI.label(_col, "I couldn't get a clear reading that time. That's normal: mics and rooms vary.")
				UI.button(_col, "Try again", _restart, true)
				_show_preset_buttons()
			else:
				UI.label(_col, "Your comfortable range:")
				UI.title(_col, "%s to %s" % [UI.note_name(_result.x), UI.note_name(_result.y)], 72)
				UI.muted(_col, "That's %d semitones. Songs will be moved into this range for you." % (_result.y - _result.x))
				_spacer()
				UI.button(_col, "Sounds good", func(): _save(_result), true)
				UI.button(_col, "Try again", _restart)


func _spacer() -> void:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_col.add_child(s)


func _begin() -> void:
	App.ensure_listening()
	var fake := App.fake_singer()
	if fake:
		fake.siren(44, 52)
	_phase = Phase.LOW
	_timer = PHASE_SECONDS
	_build()


func _restart() -> void:
	_test = RangeTest.new()
	_phase = Phase.INTRO
	_build()


func _update_status() -> void:
	if _status == null:
		return
	if _phase == Phase.LOW:
		_status.text = "Slide down, low and easy… %d" % ceili(_timer)
	else:
		_status.text = "Now slide up, high and light… %d" % ceili(_timer)


func _process(delta: float) -> void:
	if _phase != Phase.LOW and _phase != Phase.HIGH:
		return
	var src := App.pitch_source()
	for f in src.poll():
		_trace.push_frame(f)
		if _phase == Phase.LOW:
			_test.add_low(f)
		else:
			_test.add_high(f)
	_trace.set_now(src.now())
	if src.state == PitchSource.State.STARTING:
		_status.text = "Allow the microphone when the browser asks."
		return
	if src.state == PitchSource.State.ERROR:
		_status.text = "I can't hear the microphone. Check the browser's permission, or skip this step."
		return
	_timer -= delta
	_update_status()
	if _timer <= 0.0:
		if _phase == Phase.LOW:
			_phase = Phase.HIGH
			_timer = PHASE_SECONDS
			var fake := App.fake_singer()
			if fake:
				fake.siren(62, 70)
		else:
			_phase = Phase.DONE
			_result = _test.result()
			_build()


func _show_presets() -> void:
	for c in get_children():
		c.queue_free()
	_col = UI.page(self)
	UI.back_button(_col).pressed.connect(func(): _restart(), CONNECT_ONE_SHOT)
	UI.title(_col, "Choose a voice type", 56)
	UI.muted(_col, "You can run the range test later from Settings.")
	_show_preset_buttons()


func _show_preset_buttons() -> void:
	for pr in RangeTest.PRESETS:
		UI.button(_col, "%s (%s to %s)" % [pr[0], UI.note_name(pr[1]), UI.note_name(pr[2])],
			func(): _save(Vector2i(pr[1], pr[2])))


func _save(r: Vector2i) -> void:
	App.profile.voice_low = r.x
	App.profile.voice_high = r.y
	App.profile.range_tested = true
	App.profile.save()
	App.home()
