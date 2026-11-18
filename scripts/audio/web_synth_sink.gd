class_name WebSynthSink
extends RefCounted
## Sends SynthEngine notes to the browser's audio thread (web/synth_worklet.js),
## so tones don't depend on GDScript keeping up. Same timbre as SynthEngine.

const BRIDGE_PATH := "res://web/synth_bridge.js"
const WORKLET_PATH := "res://web/synth_worklet.js"

var _js: JavaScriptObject


func _init() -> void:
	JavaScriptBridge.eval(FileAccess.get_file_as_string(BRIDGE_PATH), true)
	_js = JavaScriptBridge.get_interface("solfegeSynth")
	_js.start(FileAccess.get_file_as_string(WORKLET_PATH))


func state() -> String:
	return str(_js.state)


func ok() -> bool:
	return state() in ["starting", "running"]


func time() -> float:
	return float(_js.time())


func note(v: Dictionary) -> void:
	_js.note(JSON.stringify(v))


func stop_kind(kind: int) -> void:
	_js.stop(kind)


func release_all() -> void:
	_js.release()


func peak() -> float:
	return float(_js.peak)
