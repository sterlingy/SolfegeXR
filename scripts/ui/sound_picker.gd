class_name SoundPicker
extends VBoxContainer
## The playback-sound dropdown: "Sound" caption over a "Flute" button with a dropdown arrow. The
## list opens inside the current screen, right-aligned under the button.
## (Godot's OptionButton opens a popup window, which landed in the wrong place
## on the web page and is unreliable inside the XR panel.)
##
## Picking a sound saves it (App.set_timbre) and, when `can_preview` returns
## true, plays a short do-mi-sol-do in it.

var can_preview: Callable = func() -> bool: return true
var _button: Button
var _layer: Control      ## full-screen catcher + the list, while open


## caption: "Sound" above the button. large: full-width, Settings-sized.
func _init(caption := true, large := false) -> void:
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override("separation", 2)
	if caption:
		var cap := UI.muted(self, "Sound", 26)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button = Button.new()
	_button.custom_minimum_size = Vector2(0, UI.BUTTON_H if large else 80)
	_button.add_theme_font_size_override("font_size", 40 if large else 34)
	if large:
		_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button.tooltip_text = "Playback sound"
	UI._style_button(_button, UI.CARD_HI, false)
	# The theme's dropdown arrow (the web font has no ▾ character).
	_button.icon = ThemeDB.get_default_theme().get_icon("arrow", "OptionButton")
	_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_button.add_theme_constant_override("h_separation", 14)
	_button.pressed.connect(_open)
	add_child(_button)
	_refresh()


func _refresh() -> void:
	_button.text = SynthEngine.TIMBRE_NAMES[App.profile.timbre]


func _open() -> void:
	if _layer:
		_close()
		return
	var screen := _screen_root()
	_layer = Control.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_to_group(DragScroll.BLOCK_GROUP)   # the page doesn't scroll under the list
	_layer.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close())
	screen.add_child(_layer)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.CARD
	sb.border_color = UI.ACCENT.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	panel.add_child(list)
	for i in SynthEngine.TIMBRE_NAMES.size():
		var b := Button.new()
		b.text = SynthEngine.TIMBRE_NAMES[i]
		b.custom_minimum_size = Vector2(340, 96)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 40)
		var chosen := i == App.profile.timbre
		UI._style_button(b, UI.ACCENT.darkened(0.55) if chosen else UI.CARD_HI, chosen)
		if chosen:
			b.add_theme_color_override("font_color", UI.ACCENT)
		b.pressed.connect(_pick.bind(i))
		list.add_child(b)
	_layer.add_child(panel)
	# Right-align under the button, kept inside the screen.
	var r := _button.get_global_rect()
	var origin := screen.get_global_rect().position
	panel.reset_size()
	var w := panel.get_combined_minimum_size().x
	var x := clampf(r.end.x - w - origin.x, 8.0, screen.size.x - w - 8.0)
	panel.position = Vector2(x, r.end.y - origin.y + 8.0)


func _pick(i: int) -> void:
	_close()
	App.set_timbre(i)
	_refresh()
	if can_preview.call():
		App.preview_sound()


func _close() -> void:
	if _layer:
		_layer.queue_free()
		_layer = null


func _exit_tree() -> void:
	_close()


## The screen this picker is on (App.go's screen node), so the list covers it.
func _screen_root() -> Control:
	var n: Node = self
	while n.get_parent() and not n.has_meta("screen_name"):
		n = n.get_parent()
	return n as Control if n is Control else get_tree().root.get_child(0) as Control
