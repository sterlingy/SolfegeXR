class_name DragScroll
extends Node
## Drag anywhere on a scrolling page to scroll it, buttons included, the way a
## phone list works. Add as a child of a ScrollContainer (UI.page does).
##
## Why: a Godot Button keeps every press that lands on it, so a drag starting
## on one never reaches the ScrollContainer behind it (like a UMG button
## swallowing the touch). Pages made mostly of buttons then barely scroll, and
## mouse-style pointers (desktop, the XR hand pointer) never drag-scroll at all.
##
## How: this watches presses in _input, before the buttons see them. A press
## that moves more than DRAG_SLOP pixels up or down becomes a scroll: the
## page follows the pointer, the button that was pressed is let go without
## firing, and a flick keeps gliding. A press that doesn't move is a normal tap.

const DRAG_SLOP := 14.0          ## pixels a tap may wander before it becomes a scroll
const FRICTION := 5.0            ## glide slows by e^-FRICTION per second
const MIN_GLIDE := 40.0          ## pixels/second below which the glide stops

## Visible controls in this group (an open dropdown list) take presses over
## the page, so nothing scrolls under them.
const BLOCK_GROUP := "drag_scroll_block"

var _scroll: ScrollContainer
var _pressing := false
var _dragging := false
var _start := Vector2.ZERO       ## press position, in the ScrollContainer's space
var _start_scroll := 0.0
var _last_y := 0.0
var _last_t := 0.0
var _velocity := 0.0             ## pixels/second, for the glide after a flick
var _glide := 0.0                ## exact scroll position while gliding


func _ready() -> void:
	_scroll = get_parent() as ScrollContainer
	set_process(false)


func _input(event: InputEvent) -> void:
	if _scroll == null or not _scroll.is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event)
		else:
			_release()
	elif event is InputEventMouseMotion and _pressing:
		_motion(event)


func _press(event: InputEventMouseButton) -> void:
	_pressing = false
	_dragging = false
	set_process(false)          # a press stops a glide
	var local := _local(event)
	if not Rect2(Vector2.ZERO, _scroll.size).has_point(local) or _blocked() or _on_own_drag_control(event):
		return
	_pressing = true
	_start = local
	_start_scroll = _scroll.scroll_vertical
	_last_y = local.y
	_last_t = _now()
	_velocity = 0.0


func _motion(event: InputEventMouseMotion) -> void:
	var local := _local(event)
	if not _dragging:
		var moved := local - _start
		if absf(moved.y) < DRAG_SLOP or absf(moved.y) < absf(moved.x):
			return
		if _max_scroll() <= 0.0:
			_pressing = false
			return
		_dragging = true
		_cancel_presses()
	_scroll.scroll_vertical = int(round(_start_scroll - (local.y - _start.y)))
	var t := _now()
	var dt := t - _last_t
	if dt > 0.0:
		# Smoothed, so one uneven frame doesn't decide the flick.
		_velocity = lerpf(_velocity, -(local.y - _last_y) / dt, 0.5)
	_last_y = local.y
	_last_t = t
	get_viewport().set_input_as_handled()


func _release() -> void:
	if _dragging:
		# A pause before letting go means no flick.
		if _now() - _last_t > 0.08:
			_velocity = 0.0
		if absf(_velocity) > MIN_GLIDE:
			_glide = _scroll.scroll_vertical
			set_process(true)
		# The release still goes on to the controls: the button's press was
		# already cancelled, and the ScrollContainer's own touch drag resets.
	_pressing = false
	_dragging = false


func _process(delta: float) -> void:
	_glide += _velocity * delta
	_velocity *= exp(-FRICTION * delta)
	_scroll.scroll_vertical = int(round(_glide))
	if absf(_velocity) < MIN_GLIDE or _glide <= 0.0 or _glide >= _max_scroll():
		set_process(false)


## True while the pointer is dragging the page (for tests).
func is_dragging() -> bool:
	return _dragging


## Let go of any button under the press without firing it. Disabling a button
## clears its half-finished press; re-enabling straight away means it never
## shows as disabled.
func _cancel_presses() -> void:
	for b in _buttons_at(_start, _scroll):
		if not b.disabled:
			b.disabled = true
			b.disabled = false


func _buttons_at(p: Vector2, n: Node) -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			if c is BaseButton and _scroll_rect_of(c as Control).has_point(p):
				out.append(c)
			out.append_array(_buttons_at(p, c))
	return out


## A control's rectangle in the ScrollContainer's space.
func _scroll_rect_of(c: Control) -> Rect2:
	var xf := _scroll.get_global_transform().affine_inverse() * c.get_global_transform()
	return xf * Rect2(Vector2.ZERO, c.size)


## Sliders, text boxes and scroll bars drag themselves; leave those alone.
func _on_own_drag_control(event: InputEvent) -> bool:
	for c in _controls_at(_local(event), _scroll):
		if c is Slider or c is ScrollBar or c is LineEdit or c is TextEdit:
			return true
	return false


func _controls_at(p: Vector2, n: Node) -> Array[Control]:
	var out: Array[Control] = []
	for c in n.get_children(true):   # internal too: the ScrollContainer's own bar
		if c is Control and (c as Control).is_visible_in_tree():
			if _scroll_rect_of(c as Control).has_point(p):
				out.append(c)
			out.append_array(_controls_at(p, c))
	return out


func _blocked() -> bool:
	for n in get_tree().get_nodes_in_group(BLOCK_GROUP):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			return true
	return false


func _local(event: InputEvent) -> Vector2:
	return (_scroll.make_input_local(event) as InputEventMouse).position


func _max_scroll() -> float:
	var bar := _scroll.get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)


func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0
