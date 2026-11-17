class_name MicPicker
extends VBoxContainer
## Microphone chooser plus a warning when the input is digital silence
## (usually the wrong device: a loop-back, a VR headset's virtual mic...).
## With only_when_silent, it stays hidden until there's a problem.

var only_when_silent := false

var _warn: Label
var _opt: OptionButton
var _ids: Array = []
var _signature := ""
var _timer := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_warn = UI.label(self, "Your microphone is sending complete silence, so it's probably the wrong input. Pick the one you sing into:", 34, UI.WARM)
	_opt = OptionButton.new()
	_opt.custom_minimum_size = Vector2(0, UI.BUTTON_H)
	_opt.add_theme_font_size_override("font_size", 34)
	_opt.clip_text = true
	_opt.item_selected.connect(_on_pick)
	add_child(_opt)
	_refresh()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	var src := App.pitch_source()
	var silent := src.input_silent()
	_warn.visible = silent
	visible = silent or not only_when_silent
	var devs := src.devices()
	var current := src.current_device()
	var sig := JSON.stringify(devs) + "|" + current
	if sig == _signature:
		return
	_signature = sig
	_opt.clear()
	_ids.clear()
	if devs.is_empty():
		_opt.add_item("Start singing once to see your microphones")
		_opt.disabled = true
		return
	_opt.disabled = false
	for d in devs:
		_opt.add_item(str(d.label))
		_ids.append(str(d.id))
	var idx := _ids.find(current)
	if idx >= 0:
		_opt.select(idx)


func _on_pick(index: int) -> void:
	if index >= 0 and index < _ids.size():
		App.select_mic(_ids[index])
		_signature = ""
