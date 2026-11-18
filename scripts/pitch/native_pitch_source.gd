class_name NativePitchSource
extends PitchSource
## Microphone input for native builds (Windows now; Android/XR next), through
## Godot's own audio: AudioStreamMicrophone -> a muted "Mic" bus with an
## AudioEffectCapture -> YIN. Uses the C++ detector (YinNative) when the
## GDExtension is loaded, else the GDScript one (slower, larger hop).
##
## Needs Project Settings -> audio/driver/enable_input = true (set in project.godot).
## (In UE terms: an audio capture component feeding a submix you never hear.)

const BUS := "Mic"
const SILENCE_SECONDS := 1.5

var _player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _native: Object            # YinNative, or null
var _rate := 48000.0
var _samples_in := 0           # samples consumed (clock)
var _pending := PackedFloat32Array()   # GDScript fallback: samples waiting for analysis
var _zero_since := -1.0
var _frames: Array[PitchFrame] = []


func _ready() -> void:
	_rate = AudioServer.get_mix_rate()


const ANDROID_MIC := "android.permission.RECORD_AUDIO"


func start() -> void:
	if state == State.RUNNING:
		return
	_set_state(State.STARTING)
	# Android asks the user at runtime; start once they've answered.
	if OS.get_name() == "Android" and ANDROID_MIC not in OS.get_granted_permissions():
		if not get_tree().on_request_permissions_result.is_connected(_on_permission):
			get_tree().on_request_permissions_result.connect(_on_permission)
		OS.request_permission("RECORD_AUDIO")
		return
	_start_capture()


func _on_permission(permission: String, granted: bool) -> void:
	if permission != ANDROID_MIC:
		return
	if granted:
		_start_capture()
	else:
		_set_state(State.ERROR, "The app needs the microphone to hear you. Allow it in the system settings.")


func _start_capture() -> void:
	_ensure_bus()
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = BUS
		add_child(_player)
	_player.play()
	_samples_in = 0
	_pending.clear()
	_zero_since = -1.0
	if ClassDB.class_exists("YinNative"):
		_native = ClassDB.instantiate("YinNative")
		_native.call("configure", _rate, YinDetector.HOP)
	else:
		_native = null
	if not _player.playing:
		_set_state(State.ERROR, "The microphone couldn't start. Check that input is enabled and allowed.")
		return
	_set_state(State.RUNNING)


func stop() -> void:
	if _player:
		_player.stop()
	if _capture:
		_capture.clear_buffer()
	_set_state(State.IDLE)


func now() -> float:
	return _samples_in / _rate


func poll() -> Array[PitchFrame]:
	var out: Array[PitchFrame] = []
	if state != State.RUNNING or _capture == null:
		return out
	var n := _capture.get_frames_available()
	if n <= 0:
		return out
	var stereo := _capture.get_buffer(n)
	var mono := PackedFloat32Array()
	mono.resize(stereo.size())
	var peak := 0.0
	for i in stereo.size():
		var v := (stereo[i].x + stereo[i].y) * 0.5
		mono[i] = v
		peak = maxf(peak, absf(v))
	var t0 := now()
	_samples_in += mono.size()
	# Exact digital silence for a while = wrong/disabled device.
	if peak == 0.0:
		if _zero_since < 0.0:
			_zero_since = t0
	else:
		_zero_since = -1.0
	if _native:
		var flat: PackedFloat32Array = _native.call("push", mono)
		for i in range(0, flat.size(), 4):
			out.append(PitchFrame.new(flat[i], flat[i + 1], flat[i + 2], flat[i + 3]))
	else:
		_analyze_fallback(mono, out)
	return out


## GDScript fallback: analyze in chunks with a larger hop to keep up in real time.
func _analyze_fallback(mono: PackedFloat32Array, out: Array[PitchFrame]) -> void:
	_pending.append_array(mono)
	var needed := int(_rate * 0.05)  # analyze every ~50 ms of audio
	if _pending.size() < needed * 2:
		return
	var base_time := (_samples_in - _pending.size()) / _rate
	for f in YinDetector.analyze_gdscript(_pending, _rate, 512):
		f.time += base_time
		out.append(f)
	# Keep the tail for continuity (one analysis span).
	var keep := int(_rate * 0.04)
	_pending = _pending.slice(_pending.size() - keep)


func input_silent() -> bool:
	return state == State.RUNNING and _zero_since >= 0.0 and now() - _zero_since > SILENCE_SECONDS


func devices() -> Array:
	var out := []
	for d in AudioServer.get_input_device_list():
		out.append({id = d, label = "System default" if d == "Default" else d})
	return out


func current_device() -> String:
	return AudioServer.input_device


func select_device(id: String) -> void:
	if id == "" or id == "demo":
		id = "Default"
	AudioServer.input_device = id
	if state == State.RUNNING:
		stop()
		start()


func describe() -> String:
	return "native mic: %s, detector: %s" % [AudioServer.input_device, "C++" if _native else "GDScript"]


func _ensure_bus() -> void:
	var idx := AudioServer.get_bus_index(BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_mute(idx, true)  # capture only; never play the mic back
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
	_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	_capture.buffer_length = 0.5
