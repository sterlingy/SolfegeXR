extends TestCase
## XR window controls (scripts/xr/xr_root.gd): grab bars move a window and keep
## it facing you, the knob brings windows back, and hit tests prefer the
## nearest control. Uses the desktop preview (no headset), with simulated rays.

var root: Node3D


func before_each() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	root = load("res://scenes/xr_root.tscn").instantiate()
	tree.root.add_child(root)
	root._place_in_front()


func _done() -> void:
	root.queue_free()


func _ray_to(target: Vector3) -> Array:
	var from: Vector3 = root.camera.global_position
	return [from, (target - from).normalized()]


func test_bar_and_knob_are_hit_before_the_panel() -> void:
	var bar: Vector3 = root.panel_bar.global_position
	assert_eq(root._control_under(_ray_to(bar))[0], "panel_bar")
	assert_eq(root._control_under(_ray_to(root.reset_knob.global_position))[0], "reset")
	assert_eq(root._control_under(_ray_to(root.sign_bar.global_position))[0], "sign_bar")
	assert_eq(root._control_under(_ray_to(root.panel.global_position))[0], "", "panel centre is not a control")
	_done()


func test_dragging_the_bar_moves_the_panel_and_keeps_it_facing_you() -> void:
	var cam: Vector3 = root.camera.global_position
	var start_ray := _ray_to(root.panel_bar.global_position)
	var dist := cam.distance_to(root.panel.global_position)
	root._start_drag(root.panel, start_ray)
	# Swing the pointer 60 degrees to the left.
	var dir := (start_ray[1] as Vector3).rotated(Vector3.UP, deg_to_rad(60))
	root._drag_to([cam, dir])
	var p: Vector3 = root.panel.global_position
	var to_panel := p - cam
	to_panel.y = 0
	var fwd := Vector3.FORWARD
	assert_near(rad_to_deg(fwd.angle_to(to_panel)), 60.0, 5.0, "panel followed the pointer")
	assert_near(cam.distance_to(p), dist, 0.05, "same distance")
	# The panel's back (-Z) points away from you, so its face looks at you.
	var away: Vector3 = -root.panel.global_basis.z
	assert_true(away.dot(to_panel.normalized()) > 0.99, "panel faces the viewer")
	assert_eq(root.hands_root.global_position.distance_to(root.panel.global_position) > 0.3, true, "sign window stayed put")
	_done()


func test_small_pinch_wobble_stays_a_tap() -> void:
	root._pressed = true
	root._press_pos = Vector2(100, 100)
	root._last_pos = Vector2(100, 100)
	root._move(Vector2(140, 130))  # 50 px: the hand turned while pinching
	assert_false(root._scrolling, "small wobble is still a tap")
	root._move(Vector2(100, 300))  # 200 px: a deliberate drag
	assert_true(root._scrolling, "a clear move scrolls")
	_done()


func test_second_hand_cannot_steal_a_press() -> void:
	var left := XRController3D.new()
	var right := XRController3D.new()
	root._click(true, left)
	root._click(true, right)  # the other hand pinching meanwhile
	assert_true(root._same_owner(left), "first hand keeps the press")
	root._click(false, right)
	assert_true(root._pressed, "other hand's release doesn't end it")
	root._click(false, left)
	assert_false(root._pressed)
	assert_eq(root._press_owner, null)
	left.free()
	right.free()
	_done()


func test_jittery_pinch_is_one_tap() -> void:
	# A pinch whose strength flickers (tracking noise, dropped frames) makes one
	# press and one release, not a burst of taps.
	var c := XRController3D.new()
	root.add_child(c)
	root.controllers = [c] as Array[XRController3D]
	var values := [0.0, 0.5, 0.8, 1.0, 0.0, 1.0, 0.3, 0.9, 0.0, 0.0, 1.0, 0.6]
	var opened := [0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2]
	var downs := 0
	var ups := 0
	for v in values + opened:
		var before: bool = root._pinch.get(c, [false, 0.0])[0]
		root._step_pinch(c, v, true, 1.0 / 72.0)
		var now: bool = root._pinch[c][0]
		downs += int(now and not before)
		ups += int(before and not now)
	assert_eq(downs, 1, "one press")
	assert_eq(ups, 1, "one release, after staying open")
	_done()


func test_press_uses_where_the_pointer_was_before_the_pinch() -> void:
	var c := XRController3D.new()
	root.add_child(c)
	var t: float = root._t
	root._history = [
		[t - 0.15, "panel", Vector2(100, 200), root.viewport],
		[t - 0.09, "panel", Vector2(102, 201), root.viewport],
		[t, "panel", Vector2(180, 300), root.viewport],  # the pinch swung the pointer
	]
	root._click(true, c)
	assert_eq(root._press_pos, Vector2(102, 201), "pressed where it pointed before the fingers closed")
	root._click(false, c)
	_done()


func test_pinch_on_the_bar_starts_a_drag_even_if_it_swung_off() -> void:
	var c := XRController3D.new()
	root.add_child(c)
	var t: float = root._t
	root._history = [[t - 0.09, "panel_bar", Vector2(-1, -1), null], [t, "panel", Vector2(500, 1800), root.viewport]]
	root._hover = "panel"
	root._click(true, c)
	assert_eq(root._press_target, "panel_bar")
	assert_true(root._drag == root.panel, "dragging the panel")
	root._click(false, c)
	assert_true(root._drag == null)
	_done()


func test_manual_opens_in_a_window_beside_the_panel() -> void:
	App.open_manual()  # in the XR scene, this opens the doc window, not a browser tab
	assert_true(root.doc != null and root.doc.visible, "doc window shown")
	assert_true(root.doc_text.text.contains("Quick start"), "manual text loaded")
	var right: Vector3 = root.panel.global_basis.x
	assert_true((root.doc.global_position - root.panel.global_position).dot(right) < -0.3, "to the left of the panel")
	assert_true(root._in_view(root.doc.global_position), "in view")
	# Links: in-page jump, the other page, and "back to the app".
	root._on_doc_link("#trouble")
	root._on_doc_link("../privacy/")
	assert_eq(root._doc_page, "privacy")
	assert_true(root.doc_text.text.contains("Your voice"), "privacy text loaded")
	root._on_doc_link("../")
	assert_false(root.doc.visible, "back to the app closes it")
	_done()


func test_pointer_finds_the_doc_window_and_its_bar() -> void:
	App.open_site_page("privacy")
	var hit: Array = root._hit_screen(_ray_to(root.doc.global_position))
	assert_true(hit[0] == root.doc_vp, "doc window is hit")
	assert_true(root._hit_screen(_ray_to(root.panel.global_position))[0] == root.viewport, "panel still hit")
	assert_eq(root._control_under(_ray_to(root.doc_bar.global_position))[0], "doc_bar")
	_done()


func test_recenter_brings_windows_back_in_front() -> void:
	root._start_drag(root.hands_root, _ray_to(root.sign_bar.global_position))
	root._drag_to([root.camera.global_position, Vector3.BACK])
	assert_false(root._in_view(root.hands_root.global_position), "sign moved behind you")
	root.recenter()
	root._place_in_front()
	assert_true(root._in_view(root.panel.global_position), "panel in front")
	assert_true(root._in_view(root.hands_root.global_position), "sign in front")
	assert_true(root._drag == null, "drag cancelled")
	_done()
