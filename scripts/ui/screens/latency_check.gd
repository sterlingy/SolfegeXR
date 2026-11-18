extends Control
## Settings → Check timing: beeps out of the speaker, listened for by the mic.

var _check: LatencyCheck
var _status: Label
var _result: Label
var _button: Button
var _end_time := -1.0


func setup(_args: Dictionary) -> void:
	var col := UI.page(self)
	UI.back_button(col)
	UI.title(col, "Check timing", 56)
	UI.label(col, "This measures how quickly your singing shows up on screen on this device.")
	UI.muted(col, "Take headphones off and turn the volume up. The app plays six short beeps and listens for them. Stay quiet for a few seconds.")
	_button = UI.button(col, "Start", _on_start, true)
	_status = UI.label(col, "", 40, UI.WARM)
	_result = UI.label(col, "", 40)
	if App.dev_autostart:
		_on_start.call_deferred()


func _on_start() -> void:
	App.ensure_listening()
	var fake := App.fake_singer()
	if fake:
		fake.quiet()
	_check = LatencyCheck.new()
	_end_time = _check.start(App.synth.engine)
	_status.text = "Listening…"
	_result.text = ""
	_button.disabled = true


func _process(_delta: float) -> void:
	if _check == null or _end_time < 0.0:
		return
	var src := App.pitch_source()
	var engine := App.synth.engine
	_check.add_frames(src.poll(), engine.time() - src.now())
	if src.state == PitchSource.State.ERROR:
		_status.text = "I can't hear the microphone. Check its permission, or choose another one in Settings."
		_end_time = -1.0
		_button.disabled = false
		return
	if engine.time() < _end_time:
		return
	_end_time = -1.0
	_button.disabled = false
	_button.text = "Check again"
	_status.text = ""
	_result.text = LatencyCheck.describe(_check.result(), _output_latency_ms())


## The speaker latency the platform reports (ms), or -1 if unknown.
func _output_latency_ms() -> float:
	if OS.has_feature("web"):
		var v: Variant = JavaScriptBridge.eval(
			"(function(){var c=window.solfegeSynth&&solfegeSynth.ctx;return c?((c.outputLatency||0)+(c.baseLatency||0))*1000:-1})()", true)
		return float(v) if v != null else -1.0
	return AudioServer.get_output_latency() * 1000.0
