class_name WebPitchSource
extends PitchSource
## Mic input in the browser through web/pitch_bridge.js + web/pitch_worklet.js.
## JavaScriptBridge only exists in web exports; check OS.has_feature("web") first.

const BRIDGE_PATH := "res://web/pitch_bridge.js"
const WORKLET_PATH := "res://web/pitch_worklet.js"
const WASM_PATH := "res://web/yin.wasm"  ## shared C++ detector; JS fallback if missing

var _js: JavaScriptObject
var _last_js_state := ""
var device_id := ""   ## "" = the browser's choice


func _ready() -> void:
	if not OS.has_feature("web"):
		push_error("WebPitchSource used outside a web export")
		return
	JavaScriptBridge.eval(FileAccess.get_file_as_string(BRIDGE_PATH), true)
	_js = JavaScriptBridge.get_interface("solfegePitch")


func start() -> void:
	if _js == null:
		_set_state(State.ERROR, "Pitch bridge not loaded")
		return
	var wasm := FileAccess.get_file_as_bytes(WASM_PATH)
	var wasm_b64 := Marshalls.raw_to_base64(wasm) if wasm.size() > 0 else ""
	_js.start(FileAccess.get_file_as_string(WORKLET_PATH), device_id, wasm_b64)


func stop() -> void:
	if _js:
		_js.stop()


func now() -> float:
	return float(_js.now()) if _js else 0.0


func poll() -> Array[PitchFrame]:
	var frames: Array[PitchFrame] = []
	if _js == null:
		return frames
	_sync_state()
	if state != State.RUNNING:
		return frames
	var parsed: Variant = JSON.parse_string(str(_js.drain()))
	if parsed is Array:
		for f: Array in parsed:
			frames.append(PitchFrame.new(f[0], f[1], f[2], f[3]))
	return frames


func describe() -> String:
	return str(_js.info()) if _js else ""


func devices() -> Array:
	if _js == null:
		return []
	var parsed: Variant = JSON.parse_string(str(_js.devicesJson))
	return parsed if parsed is Array else []


func current_device() -> String:
	return str(_js.currentDeviceId) if _js else ""


func select_device(id: String) -> void:
	device_id = id
	if _js and str(_js.state) in ["running", "starting"]:
		_js.stop()
		_last_js_state = ""
		start()


func input_silent() -> bool:
	return _js != null and bool(_js.isSilent())


func _sync_state() -> void:
	var s := str(_js.state)
	if s == _last_js_state:
		return
	_last_js_state = s
	match s:
		"idle": _set_state(State.IDLE)
		"starting": _set_state(State.STARTING)
		"running": _set_state(State.RUNNING)
		"error": _set_state(State.ERROR, str(_js.error))
