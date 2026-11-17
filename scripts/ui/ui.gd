class_name UI
extends RefCounted
## Small helpers so every screen looks the same: phone-first, big touch
## targets, one column. (Building UI in code here; the same nodes could be
## laid out in the editor as .tscn scenes later.)

const BG := Color("14151f")
const CARD := Color("1f2130")
const CARD_HI := Color("2a2d42")
const TEXT := Color("f1f1f5")
const MUTED := Color(1, 1, 1, 0.6)
const ACCENT := Color("7fd3ff")
const GOOD := Color("8cf0a6")
const WARM := Color("ffd27a")

const GUTTER := 40
const BUTTON_H := 120


## Background + margins + scrolling column. Returns the column to add to.
static func page(screen: Control, scroll := true) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, GUTTER)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 40)
	screen.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	if scroll:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		margin.add_child(sc)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(col)
	else:
		margin.add_child(col)
	return col


static func back_button(parent: Control, text := "‹ Back") -> Button:
	var b := flat_button(text, func(): App.back())
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(b)
	return b


static func title(parent: Control, text: String, size := 64) -> Label:
	var l := label(parent, text, size)
	return l


static func label(parent: Control, text: String, size := 40, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


static func muted(parent: Control, text: String, size := 34) -> Label:
	return label(parent, text, size, MUTED)


static func button(parent: Control, text: String, on_press: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BUTTON_H)
	b.add_theme_font_size_override("font_size", 44)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_button(b, ACCENT.darkened(0.55) if primary else CARD_HI, primary)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


static func flat_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.custom_minimum_size = Vector2(0, 90)
	b.add_theme_font_size_override("font_size", 40)
	b.add_theme_color_override("font_color", ACCENT)
	b.pressed.connect(on_press)
	return b


static func _style_button(b: Button, color: Color, primary: bool) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		if state == "hover":
			sb.bg_color = color.lightened(0.08)
		elif state == "pressed":
			sb.bg_color = color.darkened(0.15)
		elif state == "disabled":
			sb.bg_color = color.darkened(0.4)
		elif state == "focus":
			sb.draw_center = false
			sb.border_color = ACCENT
			sb.set_border_width_all(3)
		sb.set_corner_radius_all(24)
		sb.content_margin_left = 28
		sb.content_margin_right = 28
		if primary:
			sb.border_color = ACCENT
			sb.set_border_width_all(2 if state != "focus" else 3)
		b.add_theme_stylebox_override(state, sb)


static func card(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.set_corner_radius_all(28)
	sb.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	return col


static func toggle(parent: Control, text: String, value: bool, on_toggle: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.custom_minimum_size = Vector2(0, BUTTON_H)
	c.add_theme_font_size_override("font_size", 40)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.toggled.connect(on_toggle)
	parent.add_child(c)
	return c


static func row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 20)
	parent.add_child(r)
	return r


## A horizontal bar for progress (0..1).
static func bar(parent: Control, value: float, color := GOOD, caption := "") -> Control:
	var holder := VBoxContainer.new()
	if caption != "":
		muted(holder, caption, 30)
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 24)
	var bg := StyleBoxFlat.new()
	bg.bg_color = BG
	bg.set_corner_radius_all(12)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(12)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	holder.add_child(p)
	parent.add_child(holder)
	return holder


static func note_name(midi: int) -> String:
	const NAMES := ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
	return "%s%d" % [NAMES[posmod(midi, 12)], floori(midi / 12.0) - 1]
