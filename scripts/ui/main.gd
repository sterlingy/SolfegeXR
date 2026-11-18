extends Control
## The milestone-1 screen: pick a key and voice range, start the mic, sing.
## Nodes marked "%Name" in the scene are "unique names" (Access as Unique Name),
## which lets the script find them without hard-coding paths.

const VOICE_RANGES := [
	["Low voice", 50.0],     # center pitch (MIDI): D3
	["Middle voice", 57.0],  # A3
	["High voice", 64.0],    # E4
]

@onready var trace: PitchTrace = %PitchTrace
@onready var feedback: Label = %Feedback
@onready var tonic_picker: OptionButton = %TonicPicker
@onready var mode_picker: OptionButton = %ModePicker
@onready var range_picker: OptionButton = %RangePicker
@onready var do_based_toggle: CheckButton = %DoBasedToggle
@onready var chromatic_toggle: CheckButton = %ChromaticToggle
@onready var demo_toggle: CheckButton = %DemoToggle
@onready var start_button: Button = %StartButton
@onready var debug_label: Label = %DebugLabel

var key := MusicKey.new(9, MusicKey.Mode.IONIAN)  # A major
var source: PitchSource
var _web_source: PitchSource   ## the real mic (web or native), null in demo mode
var _fake_source: FakePitchSource
var _frame_count := 0
var _frame_window := 0.0
var _rate := 0.0
var _last: PitchFrame


func _ready() -> void:
	for i in MusicKey.TONIC_NAMES.size():
		tonic_picker.add_item(MusicKey.TONIC_NAMES[i], i)
	for m in [MusicKey.Mode.IONIAN, MusicKey.Mode.AEOLIAN, MusicKey.Mode.DORIAN,
			MusicKey.Mode.MIXOLYDIAN, MusicKey.Mode.LYDIAN, MusicKey.Mode.PHRYGIAN,
			MusicKey.Mode.LOCRIAN]:
		mode_picker.add_item(MusicKey.MODE_NAMES[m], m)
	for r in VOICE_RANGES:
		range_picker.add_item(r[0])
	tonic_picker.select(key.tonic_pc)
	range_picker.select(1)

	_fake_source = FakePitchSource.new()
	add_child(_fake_source)
	# Share the app's mic source (and its chosen device): web or native.
	var app_src := App.pitch_source()
	if not (app_src is FakePitchSource):
		_web_source = app_src
		_web_source.state_changed.connect(_on_source_state)
	var picker := MicPicker.new()
	picker.only_when_silent = true
	$Margin/Column.add_child(picker)
	$Margin/Column.move_child(picker, 1)
	demo_toggle.button_pressed = _web_source == null
	demo_toggle.disabled = _web_source == null

	tonic_picker.item_selected.connect(func(_i): _apply_settings())
	mode_picker.item_selected.connect(func(_i): _apply_settings())
	range_picker.item_selected.connect(func(_i): _apply_settings())
	do_based_toggle.toggled.connect(func(_on): _apply_settings())
	chromatic_toggle.toggled.connect(func(_on): _apply_settings())
	demo_toggle.toggled.connect(func(_on): _stop())
	start_button.pressed.connect(_on_start_pressed)
	trace.feedback_changed.connect(func(t): feedback.text = t)

	_apply_settings()
	feedback.text = "Pick a key, then tap Start and sing any note."
	_handle_dev_args()


## Dev helpers: `godot --path . -- --demo [--screenshot=out.png]`
func _handle_dev_args() -> void:
	var args := OS.get_cmdline_user_args()
	if "--demo" in args:
		demo_toggle.button_pressed = true
		_on_start_pressed()
	for a in args:
		if a.begins_with("--screenshot="):
			await get_tree().create_timer(4.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(a.trim_prefix("--screenshot="))
			get_tree().quit()


func _apply_settings() -> void:
	key.tonic_pc = tonic_picker.get_selected_id()
	key.mode = mode_picker.get_selected_id() as MusicKey.Mode
	key.minor_syllables = MusicKey.MinorSyllables.DO_BASED if do_based_toggle.button_pressed \
			else MusicKey.MinorSyllables.LA_BASED
	key.chromatic_enabled = chromatic_toggle.button_pressed
	trace.center_midi = VOICE_RANGES[range_picker.selected][1]
	trace.set_key(key)
	_fake_source.base_midi = key.tonic_at_or_above(int(trace.center_midi) - 7)
	# Demo singer walks degrees 1-2-3-4-5-4-3-2-1 of the chosen key.
	var steps := key.steps()
	var demo := PackedInt32Array()
	for degree in [0, 1, 2, 3, 4, 3, 2, 1, 0]:
		demo.append(steps[degree])
	_fake_source.scale_steps = demo


func _on_start_pressed() -> void:
	if source and source.state in [PitchSource.State.RUNNING, PitchSource.State.STARTING]:
		_stop()
		return
	source = _fake_source if demo_toggle.button_pressed else _web_source
	trace.clear()
	if source == _web_source:
		App.ensure_listening()
	else:
		source.start()
	start_button.text = "Stop"
	if source == _fake_source:
		feedback.text = "Demo singer (no microphone)."


func _stop() -> void:
	if source:
		source.stop()
	source = null
	start_button.text = "Start"


func _on_source_state(state: PitchSource.State, message: String) -> void:
	match state:
		PitchSource.State.STARTING:
			feedback.text = "Allow the microphone when the browser asks."
		PitchSource.State.RUNNING:
			feedback.text = "Listening. Sing any note."
		PitchSource.State.ERROR:
			feedback.text = "Couldn't open the microphone: " + message
			start_button.text = "Start"
			source = null


func _process(delta: float) -> void:
	if source == null:
		return
	var frames := source.poll()
	for f in frames:
		trace.push_frame(f)
		_last = f
	trace.set_now(source.now())

	_frame_count += frames.size()
	_frame_window += delta
	if _frame_window >= 0.5:
		_rate = _frame_count / _frame_window
		_frame_count = 0
		_frame_window = 0.0
	if _last:
		var lag_ms := (source.now() - _last.time) * 1000.0
		debug_label.text = "%6.1f Hz  conf %.2f  level %.3f  |  %d est/s  age %d ms  |  %d fps" % [
			_last.frequency, _last.confidence, _last.rms, _rate, lag_ms,
			Engine.get_frames_per_second()]
