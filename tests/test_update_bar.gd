extends TestCase
## The "new version" bar (app_root.gd) must take taps even after screens
## opened later are added on top of it: it lives on its own CanvasLayer.

var vp: SubViewport


func before_each() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(400, 400)
	vp.handle_input_locally = true
	(Engine.get_main_loop() as SceneTree).root.add_child(vp)


func after_each() -> void:
	vp.queue_free()


func _bar(on_layer: bool) -> Button:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.size = Vector2(400, 400)
	vp.add_child(host)
	var b := Button.new()
	b.position = Vector2(0, 300)
	b.size = Vector2(400, 100)
	if on_layer:
		var layer := CanvasLayer.new()
		layer.layer = 10
		host.add_child(layer)
		layer.add_child(b)
	else:
		b.z_index = 100
		host.add_child(b)
	# A screen opened afterwards: full size, stops the mouse.
	var screen := Control.new()
	screen.position = Vector2.ZERO
	screen.size = Vector2(400, 400)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(screen)
	return b


func _tap(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		vp.push_input(e)


func test_bar_on_its_own_layer_takes_the_tap() -> void:
	var b := _bar(true)
	var hits := [0]
	b.pressed.connect(func(): hits[0] += 1)
	_tap(Vector2(200, 350))
	assert_eq(hits[0], 1)


func test_z_index_alone_loses_the_tap_to_a_later_screen() -> void:
	# The old bug: drawn on top, but the later screen got the input.
	var b := _bar(false)
	var hits := [0]
	b.pressed.connect(func(): hits[0] += 1)
	_tap(Vector2(200, 350))
	assert_eq(hits[0], 0)
