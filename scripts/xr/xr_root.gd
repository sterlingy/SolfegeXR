extends Node3D
## The XR experience (WebXR in a browser, or OpenXR in the Android XR app).
##
## The whole 2D app (scenes/app_root.tscn: every screen, practice included)
## renders into a SubViewport shown on a floating panel about a metre in front
## of you; the Curwen hand sign for the note you're aiming at floats beside it.
## Point with a hand or controller and pinch/trigger to press buttons.
##
## On see-through glasses (XREAL Aura) the background stays transparent, so
## the panel floats in your room.
## (UE comparison: like a WidgetComponent in world space, with a
## WidgetInteractionComponent driven by the motion controller.)

const PANEL_SIZE := Vector2(0.45, 0.8)        ## metres (portrait, like a phone)
const PANEL_PIXELS := Vector2i(1080, 1920)    ## the app's design resolution
const PANEL_DISTANCE := 1.0                    ## metres in front of the head
const SIGNS := ["do", "re", "mi", "fa", "sol", "la", "ti"]

var origin: XROrigin3D
var camera: XRCamera3D
var panel: MeshInstance3D
var viewport: SubViewport
var hands_root: Node3D
var sign_label: Label3D
var pointer_line: MeshInstance3D
var pointer_dot: MeshInstance3D
var controllers: Array[XRController3D] = []

var _placed := false
var _pressed := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _scroll_accum := 0.0
var _web: WebXRInterface
var _active_source := -1
var _sign := ""
var _t := 0.0


func _ready() -> void:
	_build_world()
	_build_panel()
	_build_hand_signs()
	_build_pointer()
	if App.has_signal("target_syllable_changed"):
		App.target_syllable_changed.connect(_show_sign)
	_web = XRServer.find_interface("WebXR") as WebXRInterface
	if _web and _web.is_initialized():
		_web.selectstart.connect(func(id): _on_select(id, true))
		_web.selectend.connect(func(id): _on_select(id, false))
	# get_viewport().use_xr is set by whoever started the XR session (XRMode).
	get_viewport().use_xr = XRMode.active


func _build_world() -> void:
	var env := Environment.new()
	# Transparent background: see-through glasses / passthrough show the room.
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.95)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	get_viewport().transparent_bg = XRMode.transparent
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	origin = XROrigin3D.new()
	add_child(origin)
	camera = XRCamera3D.new()
	camera.position = Vector3(0, 1.6, 0) if not XRMode.active else Vector3.ZERO
	origin.add_child(camera)
	for hand in ["left_hand", "right_hand"]:
		var c := XRController3D.new()
		c.tracker = hand
		c.pose = "aim"
		c.button_pressed.connect(func(name): _on_controller_button(c, name, true))
		c.button_released.connect(func(name): _on_controller_button(c, name, false))
		origin.add_child(c)
		controllers.append(c)


func _build_panel() -> void:
	viewport = SubViewport.new()
	viewport.size = PANEL_PIXELS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	add_child(viewport)
	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	viewport.add_child(app)

	panel = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = PANEL_SIZE
	panel.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	panel.material_override = mat
	add_child(panel)


func _build_hand_signs() -> void:
	hands_root = Node3D.new()
	add_child(hands_root)
	var scene: PackedScene = load("res://assets/xr/curwen_hands.glb")
	var hands := scene.instantiate() as Node3D
	hands.scale = Vector3.ONE * 1.9
	# Three-quarter view toward the viewer, so each sign reads clearly.
	hands.rotation_degrees = Vector3(38, 40, 0)
	hands.position = Vector3(-0.09, 0, 0)
	hands_root.add_child(hands)
	for n in _sign_nodes():
		n.visible = false
	sign_label = Label3D.new()
	sign_label.font_size = 64
	sign_label.pixel_size = 0.0012
	sign_label.modulate = Color("ffd27a")
	sign_label.outline_size = 10
	sign_label.position = Vector3(0, -0.13, 0)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hands_root.add_child(sign_label)
	_show_sign("do")


func _sign_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for name in SIGNS:
		var n := hands_root.find_child(name, true, false) as Node3D
		if n:
			out.append(n)
	return out


func _build_pointer() -> void:
	pointer_line = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0015
	cyl.bottom_radius = 0.0015
	cyl.height = 1.0
	pointer_line.mesh = cyl
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.5, 0.83, 1.0, 0.6)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pointer_line.material_override = lm
	pointer_line.visible = false
	add_child(pointer_line)
	pointer_dot = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.006
	sph.height = 0.012
	pointer_dot.mesh = sph
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color("7fd3ff")
	pointer_dot.material_override = dm
	pointer_dot.visible = false
	add_child(pointer_dot)


## Show the Curwen sign for a syllable (hidden for chromatic/unknown ones).
func _show_sign(syllable: String) -> void:
	if syllable == _sign:
		return
	_sign = syllable
	for n in _sign_nodes():
		n.visible = n.name == syllable
	sign_label.text = syllable if syllable in SIGNS else ""


func _process(delta: float) -> void:
	_t += delta
	if not _placed and (not XRMode.active or camera.global_transform.origin != Vector3.ZERO or _t > 0.5):
		_place_in_front()
	# Hand sign bobs gently beside the panel.
	hands_root.position.y = panel.position.y + 0.12 + 0.01 * sin(_t * 1.6)
	_update_pointer()


## Put the panel (and hand sign) in front of where the user is looking,
## level with their eyes, facing them (yaw only).
func _place_in_front() -> void:
	_placed = true
	var cam := camera.global_transform
	var fwd := -cam.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var pos := cam.origin + fwd * PANEL_DISTANCE
	pos.y = cam.origin.y - 0.08
	# The quad faces +Z, so point -Z away from the viewer (along fwd).
	panel.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
	var right := panel.global_transform.basis.x
	hands_root.global_position = pos + right * (PANEL_SIZE.x * 0.5 + 0.16)
	hands_root.global_basis = panel.global_basis


func recenter() -> void:
	_placed = false


# ---------------------------------------------------------------- pointing

## Ray (origin, direction) from the active pointer, or null.
func _pointer_ray() -> Variant:
	if _web and _active_source >= 0:
		var tr := _web.get_input_source_tracker(_active_source)
		if tr:
			for pose_name in ["default", "aim"]:
				var pose := tr.get_pose(pose_name)
				if pose and pose.has_tracking_data:
					var t := origin.global_transform * pose.transform
					return [t.origin, -t.basis.z]
	for c in controllers:
		if c.get_is_active() and c.get_has_tracking_data():
			return [c.global_position, -c.global_basis.z]
	if not XRMode.active:
		# Desktop preview: the mouse ray through the camera.
		var mp := get_viewport().get_mouse_position()
		return [camera.project_ray_origin(mp), camera.project_ray_normal(mp)]
	return null


## Panel pixel hit by a ray, or Vector2(-1, -1).
func _hit_panel(ray: Array) -> Vector2:
	var inv := panel.global_transform.affine_inverse()
	var o: Vector3 = inv * (ray[0] as Vector3)
	var d: Vector3 = inv.basis * (ray[1] as Vector3)
	if absf(d.z) < 1e-5:
		return Vector2(-1, -1)
	var t := -o.z / d.z
	if t <= 0.0:
		return Vector2(-1, -1)
	var p := o + d * t
	var uv := Vector2(p.x / PANEL_SIZE.x + 0.5, 0.5 - p.y / PANEL_SIZE.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv * Vector2(PANEL_PIXELS)


func _update_pointer() -> void:
	var ray: Variant = _pointer_ray()
	if ray == null:
		pointer_line.visible = false
		pointer_dot.visible = false
		return
	var pos := _hit_panel(ray)
	var start: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var length := 2.0
	if pos.x >= 0.0:
		var hit_world := panel.global_transform * Vector3(
			(pos.x / PANEL_PIXELS.x - 0.5) * PANEL_SIZE.x, (0.5 - pos.y / PANEL_PIXELS.y) * PANEL_SIZE.y, 0.003)
		length = start.distance_to(hit_world)
		pointer_dot.global_position = hit_world
		pointer_dot.visible = true
		_move(pos)
	else:
		pointer_dot.visible = false
	if XRMode.active:
		pointer_line.visible = true
		pointer_line.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), start + dir * length * 0.5) \
			* Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3.ZERO)
		pointer_line.scale = Vector3(1, length, 1)


func _move(pos: Vector2) -> void:
	if pos.distance_to(_last_pos) < 0.5:
		return
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = pos - _last_pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
	viewport.push_input(ev)
	if _pressed:
		# Dragging up/down scrolls (wheel steps), like a finger on a phone.
		_scroll_accum += pos.y - _last_pos.y
		while absf(_scroll_accum) >= 60.0:
			var up := _scroll_accum > 0.0
			_wheel(pos, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN)
			_scroll_accum -= 60.0 * (1.0 if up else -1.0)
	_last_pos = pos


func _click(pressed: bool) -> void:
	var ray: Variant = _pointer_ray()
	if ray == null:
		return
	var pos := _hit_panel(ray)
	if pos.x < 0.0:
		pos = _last_pos
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	# A drag of more than ~40 px was a scroll, not a tap: release off-target.
	if not pressed and pos.distance_to(_press_pos) > 40.0:
		ev.position = Vector2(-100, -100)
		ev.global_position = ev.position
	viewport.push_input(ev)
	_pressed = pressed
	if pressed:
		_press_pos = pos
		_scroll_accum = 0.0


func _wheel(pos: Vector2, button: MouseButton) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = down
		ev.position = pos
		ev.global_position = pos
		viewport.push_input(ev)


func _on_select(input_source_id: int, pressed: bool) -> void:
	if pressed:
		_active_source = input_source_id
	_click(pressed)
	if not pressed:
		_active_source = -1


func _on_controller_button(_c: XRController3D, name: String, pressed: bool) -> void:
	if name in ["trigger_click", "select_button", "trigger", "pinch", "grip_click"]:
		_click(pressed)
	elif name in ["by_button", "menu_button"] and pressed:
		recenter()


func _unhandled_input(event: InputEvent) -> void:
	# Desktop preview: the mouse clicks the panel.
	if XRMode.active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_click(event.pressed)
