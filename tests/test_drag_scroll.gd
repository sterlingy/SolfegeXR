extends TestCase
## Drag-to-scroll on pages (scripts/ui/drag_scroll.gd): a drag that starts on
## a button scrolls the page and doesn't press it; a tap still presses it.

var vp: SubViewport
var sc: ScrollContainer
var drag: DragScroll
var buttons: Array[Button] = []
var hits := [0]


func before_each() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(400, 600)
	vp.handle_input_locally = true
	(Engine.get_main_loop() as SceneTree).root.add_child(vp)
	sc = ScrollContainer.new()
	sc.position = Vector2.ZERO
	sc.size = Vector2(400, 600)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vp.add_child(sc)
	drag = DragScroll.new()
	sc.add_child(drag)
	# A column of full-width buttons, much taller than the page.
	var content := Control.new()
	content.custom_minimum_size = Vector2(400, 2000)
	sc.add_child(content)
	buttons.clear()
	hits[0] = 0
	for i in 20:
		var b := Button.new()
		b.position = Vector2(0, i * 100)
		b.size = Vector2(400, 96)
		b.pressed.connect(func(): hits[0] += 1)
		content.add_child(b)
		buttons.append(b)
	# Headless tests run no frames, so set the scroll range layout would set.
	var bar := sc.get_v_scroll_bar()
	bar.max_value = 2000
	bar.page = 600


func after_each() -> void:
	vp.queue_free()


func _button(pressed: bool, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.global_position = at
	vp.push_input(e)


func _move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(e)


func test_page_is_taller_than_the_view() -> void:
	assert_true(drag._max_scroll() > 1000.0, "max scroll %s" % drag._max_scroll())


func test_tap_on_a_button_presses_it() -> void:
	_button(true, Vector2(200, 250))
	_move(Vector2(203, 254))          # a little wobble is still a tap
	_button(false, Vector2(203, 254))
	assert_eq(hits[0], 1)
	assert_eq(sc.scroll_vertical, 0)


func test_drag_starting_on_a_button_scrolls_and_does_not_press() -> void:
	_button(true, Vector2(200, 450))
	for y in [430, 400, 350, 300, 250]:
		_move(Vector2(200, y))
	assert_true(drag.is_dragging())
	assert_eq(sc.scroll_vertical, 200, "the page follows the pointer")
	_button(false, Vector2(200, 250))
	assert_eq(hits[0], 0, "a scroll is not a tap")
	assert_false(buttons[4].button_pressed)


func test_drag_down_at_the_top_stays_at_the_top() -> void:
	_button(true, Vector2(200, 100))
	_move(Vector2(200, 300))
	_button(false, Vector2(200, 300))
	assert_eq(sc.scroll_vertical, 0)
	assert_eq(hits[0], 0)


func test_sideways_move_is_not_a_scroll() -> void:
	_button(true, Vector2(100, 250))
	_move(Vector2(160, 255))
	assert_false(drag.is_dragging())
	_button(false, Vector2(160, 255))
	assert_eq(hits[0], 1)


func test_an_open_dropdown_blocks_page_scrolling() -> void:
	var layer := Control.new()
	layer.add_to_group(DragScroll.BLOCK_GROUP)
	vp.add_child(layer)
	_button(true, Vector2(200, 450))
	_move(Vector2(200, 250))
	_button(false, Vector2(200, 250))
	assert_eq(sc.scroll_vertical, 0)
	layer.free()


func test_after_a_scroll_the_next_tap_works() -> void:
	_button(true, Vector2(200, 450))
	_move(Vector2(200, 250))
	_button(false, Vector2(200, 250))
	_button(true, Vector2(200, 250))
	_button(false, Vector2(200, 250))
	assert_eq(hits[0], 1)
