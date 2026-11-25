extends Node3D
## The XR experience (WebXR in a browser, or OpenXR in the Android XR app).
##
## The whole 2D app (scenes/app_root.tscn: every screen, practice included)
## renders into a SubViewport shown on a floating panel about a metre in front
## of you; the Curwen hand sign for the note you're aiming at floats beside it.
## Point with a hand or controller and pinch/trigger to press buttons.
##
## Both are "windows" you can move: pinch the grab bar under one and move your
## hand, and it follows (always turning to face you). The round knob next to the
## panel's bar brings both back in front of you, and when both are out of view a
## "Bring windows here" button appears low in front of you.
##
## On see-through glasses (XREAL Aura) the background stays transparent, so
## the panel floats in your room.
## (UE comparison: like a WidgetComponent in world space, with a
## WidgetInteractionComponent driven by the motion controller.)

const PANEL_SIZE := Vector2(0.45, 0.8)        ## metres (portrait, like a phone)
const PANEL_PIXELS := Vector2i(1080, 1920)    ## the app's design resolution
const PANEL_DISTANCE := 1.0                    ## metres in front of the head
const SIGNS := ["do", "re", "mi", "fa", "sol", "la", "ti"]

const BAR_LENGTH := 0.14                       ## grab bar, metres
const BAR_GAP := 0.035                         ## from the window's bottom edge to the bar
const BAR_HIT := Vector2(0.09, 0.025)          ## half size of the bar's pinch area
const KNOB_HIT := Vector2(0.025, 0.025)        ## half size of the recenter knob's pinch area
const SUMMON_HIT := Vector2(0.13, 0.035)       ## half size of "Bring windows here"
const SIGN_BAR_Y := -0.2                       ## grab bar under the hand sign
const AWAY_ANGLE := 55.0                       ## a window this far off your view counts as out of sight
const AWAY_SECONDS := 1.0

const TAP_SLOP := 70.0                         ## panel pixels a pinch may wander and still tap
const PINCH_ON := 0.75                         ## pinch strength that presses (thumb and index nearly touching)
const PINCH_OFF := 0.35                        ## ...and that counts as open again
const RELEASE_HOLD := 0.12                     ## seconds a pinch must stay open to release (tracking drops a frame or two)
const PRESS_LOOKBACK := 0.1                    ## seconds: press where the pointer was before the fingers closed
const DOC_SIZE := Vector2(0.5, 0.6)            ## the manual / privacy window, metres
const DOC_PIXELS := Vector2i(1000, 1200)

const COLOR_IDLE := Color(1, 1, 1, 0.45)
const COLOR_HOVER := Color("7fd3ff")

var origin: XROrigin3D
var camera: XRCamera3D
var panel: MeshInstance3D
var viewport: SubViewport
var hands_root: Node3D         ## the hand-sign window (moves as one)
var hands_float: Node3D        ## inside it: bobs gently
var sign_label: Label3D
var pointer_line: MeshInstance3D
var pointer_dot: MeshInstance3D
var controllers: Array[XRController3D] = []

var panel_bar: MeshInstance3D
var sign_bar: MeshInstance3D
var reset_knob: Node3D
var summon: Node3D              ## "Bring windows here", shown when both windows are out of sight
var doc: MeshInstance3D         ## the manual / privacy window (made on first use)
var doc_vp: SubViewport
var doc_bar: MeshInstance3D
var doc_title: Label
var doc_text: RichTextLabel
var _doc_page := ""
var _doc_anchors := {}
var _press_vp: SubViewport      ## screen the current pinch started on
var _hover_vp: SubViewport      ## screen the pointer is over

var _placed := false
var _shared_rig := false       ## using XRMode's rig (web stereo session)
var _pressed := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _scroll_accum := 0.0
var _scrolling := false         ## this pinch moved far enough to be a scroll
var _press_owner: Variant = null  ## what holds the current press: a controller, "mouse" or "select"
var _pinch := {}                ## controller -> [down, seconds open]
var _history: Array = []        ## recent pointer states: [time, hover, panel pos, screen]
var _pinch_source := {}         ## hand -> "browser" or "joints", for diagnostics
var _web: WebXRInterface
var _active_source := -1
var _active_ctrl: XRController3D  ## the hand/controller that pinched last
var _ctrl_callables := {}       ## controller -> [pressed, released] callables
var _sign := ""
var _t := 0.0

var _hover := ""                ## "panel_bar", "sign_bar", "reset", "summon", "panel" or ""
var _press_target := ""         ## what the current pinch started on
var _drag: Node3D               ## window being moved
var _drag_dist := 0.0           ## from the pointer to the grab point, metres
var _drag_offset := Vector3.ZERO  ## grab point -> window origin, in the window's frame
var _away := 0.0                ## seconds both windows have been out of sight


func _ready() -> void:
	_build_world()
	_build_panel()
	_build_hand_signs()
	_build_pointer()
	_build_summon()
	XRMode.doc_requested.connect(open_doc)
	if App.has_signal("target_syllable_changed"):
		App.target_syllable_changed.connect(_show_sign)
	_web = XRServer.find_interface("WebXR") as WebXRInterface
	if _web and _web.is_initialized():
		_web.selectstart.connect(func(id): _on_select(id, true))
		_web.selectend.connect(func(id): _on_select(id, false))
	# Native OpenXR and Godot's own WebXR render through the main viewport. The
	# web stereo rig renders its own eyes, so the main viewport stays non-XR.
	get_viewport().use_xr = XRMode.active and not _shared_rig


func _exit_tree() -> void:
	# The shared rig's controllers outlive this scene.
	for c: XRController3D in _ctrl_callables:
		var pair: Array = _ctrl_callables[c]
		if is_instance_valid(c):
			if c.button_pressed.is_connected(pair[0]):
				c.button_pressed.disconnect(pair[0])
			if c.button_released.is_connected(pair[1]):
				c.button_released.disconnect(pair[1])
	_ctrl_callables.clear()


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
	_shared_rig = XRMode.active and XRMode.origin != null and XRMode.origin.is_inside_tree()
	if _shared_rig:
		# Web stereo session: the tracked rig lives in XRMode and outlives this scene.
		origin = XRMode.origin
		camera = XRMode.camera
		controllers = XRMode.controllers.duplicate()
	else:
		origin = XROrigin3D.new()
		add_child(origin)
		camera = XRCamera3D.new()
		camera.position = Vector3(0, 1.6, 0) if not XRMode.active else Vector3.ZERO
		origin.add_child(camera)
		for hand in ["left_hand", "right_hand"]:
			var c := XRController3D.new()
			c.tracker = hand
			c.pose = "aim"
			origin.add_child(c)
			controllers.append(c)
	for c in controllers:
		var on_press := _on_controller_pressed.bind(c)
		var on_release := _on_controller_released.bind(c)
		c.button_pressed.connect(on_press)
		c.button_released.connect(on_release)
		_ctrl_callables[c] = [on_press, on_release]


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

	var bar_y := -PANEL_SIZE.y * 0.5 - BAR_GAP
	panel_bar = _make_bar()
	panel_bar.position = Vector3(0, bar_y, 0.002)
	panel.add_child(panel_bar)
	reset_knob = _make_knob()
	reset_knob.position = Vector3(BAR_LENGTH * 0.5 + 0.04, bar_y, 0.002)
	panel.add_child(reset_knob)


## A window's grab bar: a short rounded pill (like Android XR / visionOS).
func _make_bar() -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.0065
	cap.height = BAR_LENGTH
	bar.mesh = cap
	bar.rotation_degrees = Vector3(0, 0, 90)  # capsules stand along Y; lay it along X
	bar.material_override = _ui_material(COLOR_IDLE)
	return bar


## The recenter knob: a small disc with a ring on it.
func _make_knob() -> Node3D:
	var knob := Node3D.new()
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.016
	cyl.bottom_radius = 0.016
	cyl.height = 0.003
	disc.mesh = cyl
	disc.rotation_degrees = Vector3(90, 0, 0)  # face the viewer (+Z)
	disc.material_override = _ui_material(Color(0.1, 0.12, 0.16, 0.75))
	knob.add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.007
	torus.outer_radius = 0.0095
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = Vector3(0, 0, 0.003)
	ring.material_override = _ui_material(COLOR_IDLE)
	knob.add_child(ring)
	knob.set_meta("tint", ring)
	return knob


func _ui_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _build_hand_signs() -> void:
	hands_root = Node3D.new()
	add_child(hands_root)
	hands_float = Node3D.new()
	hands_root.add_child(hands_float)
	var scene: PackedScene = load("res://assets/xr/curwen_hands.glb")
	var hands := scene.instantiate() as Node3D
	hands.scale = Vector3.ONE * 1.9
	# Three-quarter view toward the viewer, so each sign reads clearly.
	hands.rotation_degrees = Vector3(38, 40, 0)
	hands.position = Vector3(-0.09, 0, 0)
	hands_float.add_child(hands)
	for n in _sign_nodes():
		n.visible = false
	sign_label = Label3D.new()
	sign_label.font_size = 64
	sign_label.pixel_size = 0.0012
	sign_label.modulate = Color("ffd27a")
	sign_label.outline_size = 10
	sign_label.position = Vector3(0, -0.13, 0)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hands_float.add_child(sign_label)
	sign_bar = _make_bar()
	sign_bar.position = Vector3(0, SIGN_BAR_Y, 0)
	hands_root.add_child(sign_bar)
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


## "Bring windows here": a pill with a label, shown low in front of you when
## both windows are out of sight, so they can always be found again.
func _build_summon() -> void:
	summon = Node3D.new()
	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SUMMON_HIT * 2.0
	back.mesh = quad
	back.material_override = _ui_material(Color(0.1, 0.12, 0.16, 0.8))
	summon.add_child(back)
	summon.set_meta("tint", back)
	var label := Label3D.new()
	label.text = "Bring windows here"
	label.font_size = 48
	label.pixel_size = 0.0008
	label.outline_size = 0
	label.position = Vector3(0, 0, 0.002)
	summon.add_child(label)
	summon.visible = false
	add_child(summon)


# ------------------------------------------------------------ doc window

## Show the user manual or privacy page ("manual" / "privacy", from site/) in
## its own window. A browser can't show a web page inside an XR session, so
## the page's text is converted and shown here instead (scripts/ui/html_doc.gd).
func open_doc(page: String) -> void:
	var path := "res://site/%s/index.html" % page
	if not FileAccess.file_exists(path):
		push_warning("XR doc window: %s isn't in this build" % path)
		return
	if doc == null:
		_build_doc()
	var first := not doc.visible
	var d := HtmlDoc.from_file(path)
	_doc_page = page
	_doc_anchors = d.anchors
	doc_title.text = "User manual" if page == "manual" else page.capitalize()
	doc_text.text = d.text
	doc_text.scroll_to_line(0)
	doc.visible = true
	if first:
		_place_doc()
	XRMode.diag("doc window: %s" % page)


func close_doc() -> void:
	if doc:
		doc.visible = false
	if _drag == doc:
		_drag = null


func _build_doc() -> void:
	doc_vp = SubViewport.new()
	doc_vp.size = DOC_PIXELS
	doc_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	doc_vp.gui_embed_subwindows = true
	add_child(doc_vp)
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	doc_vp.add_child(page)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	page.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	doc_title = Label.new()
	doc_title.add_theme_font_size_override("font_size", 44)
	doc_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doc_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(doc_title)
	var close := UI.button(top, "Close", close_doc)
	close.custom_minimum_size = Vector2(200, 100)
	doc_text = RichTextLabel.new()
	doc_text.bbcode_enabled = true
	doc_text.scroll_active = true
	doc_text.selection_enabled = false
	doc_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	doc_text.add_theme_font_size_override("normal_font_size", 34)
	doc_text.add_theme_font_size_override("bold_font_size", 34)
	doc_text.add_theme_font_size_override("italics_font_size", 34)
	doc_text.add_theme_font_size_override("mono_font_size", 30)
	doc_text.add_theme_font_size_override("bold_italics_font_size", 34)
	# The app font has no bold or italic face: synthesize them.
	var base: Font = ThemeDB.get_project_theme().default_font if ThemeDB.get_project_theme() and ThemeDB.get_project_theme().default_font else ThemeDB.fallback_font
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_embolden = 0.9
	var italic := FontVariation.new()
	italic.base_font = base
	italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	var bold_italic := bold.duplicate() as FontVariation
	bold_italic.variation_transform = italic.variation_transform
	doc_text.add_theme_font_override("bold_font", bold)
	doc_text.add_theme_font_override("italics_font", italic)
	doc_text.add_theme_font_override("bold_italics_font", bold_italic)
	doc_text.add_theme_constant_override("line_separation", 6)
	doc_text.add_theme_constant_override("table_h_separation", 18)
	doc_text.add_theme_constant_override("table_v_separation", 10)
	doc_text.meta_clicked.connect(_on_doc_link)
	col.add_child(doc_text)

	doc = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = DOC_SIZE
	doc.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = doc_vp.get_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	doc.material_override = mat
	doc.visible = false
	add_child(doc)
	doc_bar = _make_bar()
	doc_bar.position = Vector3(0, -DOC_SIZE.y * 0.5 - BAR_GAP, 0.002)
	doc.add_child(doc_bar)


## Links in the doc: in-page jumps, the other doc, or "back to the app" (close).
func _on_doc_link(meta: Variant) -> void:
	var href := str(meta)
	if href.begins_with("#"):
		var id := href.substr(1)
		var at := _anchor_position(id)
		if at >= 0:
			doc_text.scroll_to_paragraph(doc_text.get_character_paragraph(at))
	elif href.contains("privacy"):
		open_doc("privacy")
	elif href.contains("manual"):
		open_doc("manual")
	elif href == "../" or href == "./" or href == "/":
		close_doc()
	# Other sites can't be opened from inside XR; the link does nothing.


## Where an element id's text starts in the displayed doc, or -1. The last
## match: a heading comes after its own entry in the Contents list.
func _anchor_position(id: String) -> int:
	if not _doc_anchors.has(id):
		return -1
	return doc_text.get_parsed_text().rfind(_doc_anchors[id])


## The doc window goes to the left of the app panel (the hand sign is on the right).
func _place_doc() -> void:
	if doc == null:
		return
	var right := panel.global_basis.x
	var pos := panel.global_position - right * (PANEL_SIZE.x * 0.5 + DOC_SIZE.x * 0.5 + 0.06)
	pos.y = panel.global_position.y + (PANEL_SIZE.y - DOC_SIZE.y) * 0.5
	doc.global_transform = Transform3D(_facing_basis(pos), pos)


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
	# The hand sign bobs gently inside its window.
	hands_float.position.y = 0.01 * sin(_t * 1.6)
	_update_summon(delta)
	_update_pointer()
	_poll_pinches(delta)


## Put both windows in front of where the user is looking, level with their
## eyes, facing them (yaw only): the panel straight ahead, the sign beside it.
func _place_in_front() -> void:
	_placed = true
	_drag = null
	var cam := camera.global_transform
	var fwd := -cam.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var pos := cam.origin + fwd * PANEL_DISTANCE
	pos.y = cam.origin.y - 0.08
	# The quad faces +Z, so point -Z away from the viewer (along fwd).
	panel.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
	var right := panel.global_transform.basis.x
	hands_root.global_position = pos + right * (PANEL_SIZE.x * 0.5 + 0.16) + Vector3(0, 0.12, 0)
	hands_root.global_basis = panel.global_basis
	if doc and doc.visible:
		_place_doc()
	summon.visible = false
	_away = 0.0


func recenter() -> void:
	_placed = false


## Basis that turns a window at `pos` to face the viewer (yaw only, upright).
func _facing_basis(pos: Vector3) -> Basis:
	var fwd := pos - camera.global_position
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return panel.global_basis
	return Basis.looking_at(fwd.normalized(), Vector3.UP)


# ------------------------------------------------------- out-of-sight button

func _update_summon(delta: float) -> void:
	if not XRMode.active or _drag:
		summon.visible = false
		_away = 0.0
		return
	var out_of_sight := not _in_view(panel.global_position) and not _in_view(hands_root.global_position) \
		and not (doc and doc.visible and _in_view(doc.global_position))
	_away = _away + delta if out_of_sight else 0.0
	if not out_of_sight:
		summon.visible = false
		return
	if _away < AWAY_SECONDS:
		return
	# Low in front of you, following your gaze lazily.
	var cam := camera.global_transform
	var fwd := -cam.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var target := cam.origin + fwd * 0.7 + Vector3(0, -0.18, 0)
	if not summon.visible:
		summon.global_position = target
		summon.visible = true
	else:
		summon.global_position = summon.global_position.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	summon.global_basis = _facing_basis(summon.global_position)


func _in_view(point: Vector3) -> bool:
	var to := point - camera.global_position
	if to.length() < 0.01:
		return true
	if to.length() > 6.0:
		return false
	return rad_to_deg((-camera.global_basis.z).angle_to(to)) < AWAY_ANGLE


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
	# The hand that pinched last points; otherwise the first one tracked
	# (right hand first: most people point with it).
	var order: Array[XRController3D] = []
	if _active_ctrl:
		order.append(_active_ctrl)
	for i in range(controllers.size() - 1, -1, -1):
		order.append(controllers[i])
	for c in order:
		if c.get_is_active() and c.get_has_tracking_data():
			return [c.global_position, -c.global_basis.z]
	if not XRMode.active:
		# Desktop preview: the mouse ray through the camera.
		var mp := get_viewport().get_mouse_position()
		return [camera.project_ray_origin(mp), camera.project_ray_normal(mp)]
	return null


## Distance along `ray` to where it crosses `node`'s local XY plane inside
## `half` (half width/height), or -1.
func _hit_rect(node: Node3D, ray: Array, half: Vector2) -> float:
	if not node.is_visible_in_tree():
		return -1.0
	var inv := node.global_transform.affine_inverse()
	var o: Vector3 = inv * (ray[0] as Vector3)
	var d: Vector3 = inv.basis * (ray[1] as Vector3)
	if absf(d.z) < 1e-5:
		return -1.0
	var t := -o.z / d.z
	if t <= 0.0:
		return -1.0
	var p := o + d * t
	if absf(p.x) > half.x or absf(p.y) > half.y:
		return -1.0
	return (node.global_transform * p).distance_to(ray[0])


## The flat screens you can point at: [mesh, viewport, size in metres, pixels].
func _screens() -> Array:
	var out := [[panel, viewport, PANEL_SIZE, PANEL_PIXELS]]
	if doc and doc.visible:
		out.append([doc, doc_vp, DOC_SIZE, DOC_PIXELS])
	return out


## The nearest screen hit by a ray: [viewport, pixel, distance], or
## [null, (-1, -1), -1].
func _hit_screen(ray: Array) -> Array:
	var best := [null, Vector2(-1, -1), -1.0]
	for s in _screens():
		var mesh: Node3D = s[0]
		var size: Vector2 = s[2]
		var inv := mesh.global_transform.affine_inverse()
		var o: Vector3 = inv * (ray[0] as Vector3)
		var d: Vector3 = inv.basis * (ray[1] as Vector3)
		if absf(d.z) < 1e-5:
			continue
		var t := -o.z / d.z
		if t <= 0.0:
			continue
		var p := o + d * t
		var uv := Vector2(p.x / size.x + 0.5, 0.5 - p.y / size.y)
		if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
			continue
		var dist := (mesh.global_transform * p).distance_to(ray[0])
		if best[2] < 0.0 or dist < best[2]:
			best = [s[1], uv * Vector2(s[3]), dist]
	return best


## Pixel hit on the app panel by a ray, or Vector2(-1, -1).
func _hit_panel(ray: Array) -> Vector2:
	var hit := _hit_screen(ray)
	return hit[1] if hit[0] == viewport else Vector2(-1, -1)


## The window control under the ray (nearest first), with the hit distance.
func _control_under(ray: Array) -> Array:
	# The sign bar sits in hands_root's frame; the panel's bar and knob in the
	# panel's, but slightly in front of it, so test the rect at their own nodes.
	var best := ["", -1.0]
	var entries := [["summon", summon, SUMMON_HIT], ["reset", reset_knob, KNOB_HIT],
			["panel_bar", _rect_node(panel_bar), BAR_HIT], ["sign_bar", _rect_node(sign_bar), BAR_HIT]]
	if doc:
		entries.append(["doc_bar", _rect_node(doc_bar), BAR_HIT])
	for entry in entries:
		var t := _hit_rect(entry[1], ray, entry[2])
		if t >= 0.0 and (best[1] < 0.0 or t < best[1]):
			best = [entry[0], t]
	return best


## Bars are capsules rotated 90 degrees; hit-test them in their window's frame
## (an unrotated helper at the bar's position).
func _rect_node(bar: MeshInstance3D) -> Node3D:
	if not bar.has_meta("frame"):
		var frame := Node3D.new()
		frame.position = bar.position
		bar.get_parent().add_child(frame)
		bar.set_meta("frame", frame)
	return bar.get_meta("frame")


func _update_pointer() -> void:
	var ray: Variant = _pointer_ray()
	if ray == null:
		pointer_line.visible = false
		pointer_dot.visible = false
		_set_hover("")
		return
	var start: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var length := 2.0
	var dot_at: Variant = null
	if _drag:
		dot_at = _drag_to(ray)
		length = _drag_dist
	else:
		var control := _control_under(ray)
		var hit := _hit_screen(ray)
		var screen_t: float = hit[2]
		if control[0] != "" and (screen_t < 0.0 or control[1] <= screen_t):
			_set_hover(control[0])
			length = control[1]
			dot_at = start + dir * length
		elif hit[0] != null:
			_set_hover("panel")
			length = screen_t
			dot_at = start + dir * length
			_move(hit[1], hit[0])
		else:
			_set_hover("")
		_remember(hit)
	pointer_dot.visible = dot_at != null
	if dot_at != null:
		pointer_dot.global_position = dot_at
	if XRMode.active:
		pointer_line.visible = true
		pointer_line.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), start + dir * length * 0.5) \
			* Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3.ZERO)
		pointer_line.scale = Vector3(1, length, 1)


## Highlight the control under the pointer.
func _set_hover(what: String) -> void:
	if what == _hover:
		return
	_hover = what
	var tints := {
		"panel_bar": panel_bar,
		"sign_bar": sign_bar,
		"reset": reset_knob.get_meta("tint"),
	}
	if doc:
		tints["doc_bar"] = doc_bar
	for key in tints:
		var m := (tints[key] as MeshInstance3D).material_override as StandardMaterial3D
		m.albedo_color = COLOR_HOVER if (key == what or _drag and _drag_name() == key) else COLOR_IDLE
	var back := (summon.get_meta("tint") as MeshInstance3D).material_override as StandardMaterial3D
	back.albedo_color = Color(0.2, 0.35, 0.45, 0.9) if what == "summon" else Color(0.1, 0.12, 0.16, 0.8)


func _drag_name() -> String:
	if _drag == panel:
		return "panel_bar"
	if _drag == hands_root:
		return "sign_bar"
	return "doc_bar" if _drag and _drag == doc else ""


## Pointer moved over a screen. While pinched, everything goes to the screen
## the pinch started on.
func _move(pos: Vector2, vp: SubViewport = null) -> void:
	if _pressed and _press_vp:
		vp = _press_vp
	elif vp == null:
		vp = viewport
	var switched := vp != _hover_vp
	if switched:
		# Moved onto another screen: let the old one know the pointer left.
		if _hover_vp and is_instance_valid(_hover_vp) and not _pressed:
			var away := InputEventMouseMotion.new()
			away.position = Vector2(-100, -100)
			away.global_position = away.position
			_hover_vp.push_input(away)
		_hover_vp = vp
		_last_pos = pos
	if not switched and pos.distance_to(_last_pos) < 0.5:
		return
	if _pressed and not _scrolling:
		# Pinching turns the hand a little, which drags the pointer. Small moves
		# during a pinch are ignored so it stays on the button pressed (small
		# ones like "‹ Back" especially); only a clear move becomes a scroll.
		if pos.distance_to(_press_pos) < TAP_SLOP:
			return
		_scrolling = true
		_last_pos = _press_pos
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = pos - _last_pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
	vp.push_input(ev)
	if _pressed and vp == doc_vp:
		# Dragging up/down scrolls the doc window (wheel steps). The app panel's
		# pages scroll themselves from the drag (DragScroll).
		_scroll_accum += pos.y - _last_pos.y
		while absf(_scroll_accum) >= 60.0:
			var up := _scroll_accum > 0.0
			_wheel(pos, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN, vp)
			_scroll_accum -= 60.0 * (1.0 if up else -1.0)
	_last_pos = pos


## Pinch / trigger / mouse button. Window controls take the pinch first;
## everything else is a tap on the panel.
func _click(pressed: bool, owner: Variant = "mouse") -> void:
	# One press at a time: while one hand (or the mouse) holds it, the other
	# hand's pinches are ignored, and only the owner's release ends it.
	if pressed:
		if _press_owner != null:
			return
		_press_owner = owner
	else:
		if _press_owner == null or not _same_owner(owner):
			return
		_press_owner = null
	var ray: Variant = _pointer_ray()
	# A hand's pointer swings as the fingers close, so a pinch presses what the
	# pointer was on just before.
	var before: Array = _lookback() if pressed and owner is XRController3D else []
	var hover := _hover if before.is_empty() else str(before[1])
	if pressed:
		_press_target = hover if hover in ["panel_bar", "sign_bar", "doc_bar", "reset", "summon"] else ""
		match _press_target:
			"panel_bar":
				_start_drag(panel, ray)
				return
			"sign_bar":
				_start_drag(hands_root, ray)
				return
			"doc_bar":
				_start_drag(doc, ray)
				return
			"reset", "summon":
				recenter()
				return
	else:
		var target := _press_target
		_press_target = ""
		if target != "":
			_drag = null
			_set_hover("")
			return
	if ray == null and pressed:
		return
	var hit := _hit_screen(ray) if ray != null else [null, Vector2(-1, -1), -1.0]
	if not before.is_empty() and before[3] != null:
		hit = [before[3], before[2], 0.0]
	var pos: Vector2 = hit[1]
	if pos.x < 0.0:
		pos = _last_pos
	if pressed:
		_press_vp = hit[0] if hit[0] != null else (_hover_vp if _hover_vp else viewport)
	var vp: SubViewport = _press_vp if _press_vp else viewport
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	if pressed:
		ev.position = pos
	elif _scrolling:
		# That was a scroll, not a tap: release off-target.
		ev.position = Vector2(-100, -100)
	else:
		# A tap: release where it was pressed, whatever the pinch did to the pointer.
		ev.position = _press_pos
	ev.global_position = ev.position
	if not pressed:
		XRMode.diag("tap %s at %s, pointer moved %d px%s" % [
			"scroll" if _scrolling else "release", _press_pos.round(), int(pos.distance_to(_press_pos)),
			" on the doc" if vp == doc_vp else ""])
	vp.push_input(ev)
	_pressed = pressed
	if pressed:
		_press_pos = pos
		_last_pos = pos
		_scroll_accum = 0.0
		_scrolling = false
	else:
		_scrolling = false


## Start moving a window: it keeps its distance from the pointer and its offset
## from the grab point, and turns to face you as it moves.
func _start_drag(window: Node3D, ray: Variant) -> void:
	if ray == null:
		return
	var start: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var bar := panel_bar if window == panel else (doc_bar if window == doc else sign_bar)
	var t := _hit_rect(_rect_node(bar), ray, BAR_HIT)
	_drag_dist = t if t > 0.0 else start.distance_to(bar.global_position)
	var grab := start + dir * _drag_dist
	_drag_offset = window.global_basis.inverse() * (window.global_position - grab)
	_drag = window


## Move the window being dragged to follow `ray`; returns the grab point.
func _drag_to(ray: Array) -> Vector3:
	var grab: Vector3 = (ray[0] as Vector3) + (ray[1] as Vector3) * _drag_dist
	var basis := _facing_basis(grab)
	_drag.global_transform = Transform3D(basis, grab + basis * _drag_offset)
	return grab


func _wheel(pos: Vector2, button: MouseButton, vp: SubViewport) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = down
		ev.position = pos
		ev.global_position = pos
		vp.push_input(ev)


func _on_select(input_source_id: int, pressed: bool) -> void:
	if pressed:
		_active_source = input_source_id
	_click(pressed, "select")
	if not pressed:
		_active_source = -1


## Taps come from _poll_pinches; buttons only recenter.
func _on_controller_pressed(name: String, _c: XRController3D) -> void:
	if name in ["by_button", "menu_button"]:
		recenter()


func _on_controller_released(_name: String, _c: XRController3D) -> void:
	pass


func _same_owner(owner: Variant) -> bool:
	return typeof(owner) == typeof(_press_owner) and owner == _press_owner


# ---------------------------------------------------------------- pinching

## Read each hand's pinch as a strength (0 open .. 1 closed), with hysteresis:
## it presses when nearly closed, and releases only after staying clearly open
## for RELEASE_HOLD. Hand tracking jitters and drops frames, and a single
## on/off threshold read one pinch as dozens of taps. Only the thumb and index
## count: a relaxed, half-curled hand isn't a press.
func _poll_pinches(delta: float) -> void:
	for c in controllers:
		_step_pinch(c, _pinch_value(c), c.get_has_tracking_data(), delta)


func _step_pinch(c: XRController3D, value: float, tracked: bool, delta: float) -> void:
	var state: Array = _pinch.get(c, [false, 0.0])
	if not state[0]:
		if value >= PINCH_ON and tracked:
			_pinch[c] = [true, 0.0]
			_on_pinch(c, true)
			return
	elif value <= PINCH_OFF:
		state[1] += delta
		if state[1] >= RELEASE_HOLD:
			_pinch[c] = [false, 0.0]
			_on_pinch(c, false)
			return
	else:
		state[1] = 0.0
	_pinch[c] = state


## The browser's own pinch (WebXR select) when it reports one; otherwise the
## strength the addon works out from the hand joints (or a controller trigger).
func _pinch_value(c: XRController3D) -> float:
	if not c.get_is_active():
		return 0.0
	var hand := c.tracker.trim_suffix("_hand")
	var browser := XRMode.select_state(hand)
	var source := "browser" if browser >= 0 else "joints"
	if source != _pinch_source.get(hand, ""):
		_pinch_source[hand] = source
		XRMode.diag("pinch source (%s): %s" % [hand, source])
	if browser >= 0:
		return float(browser)
	return c.get_float("trigger")


func _on_pinch(c: XRController3D, pressed: bool) -> void:
	if pressed and _press_owner == null and _active_ctrl != c and not _drag:
		# Point with the hand that pinched before working out what it hits.
		_active_ctrl = c
		_history.clear()
		_update_pointer()
	_click(pressed, c)


## Keep the last moment of pointer states, for _lookback.
func _remember(hit: Array) -> void:
	_history.append([_t, _hover, hit[1], hit[0] if _hover == "panel" else null])
	while _history.size() > 1 and _history[0][0] < _t - 0.3:
		_history.pop_front()


## The pointer state from PRESS_LOOKBACK ago (or the oldest kept), or [].
func _lookback() -> Array:
	for entry: Array in _history:
		if entry[0] >= _t - PRESS_LOOKBACK:
			return entry
	return []


func _unhandled_input(event: InputEvent) -> void:
	# Desktop preview: the mouse clicks the panel.
	if XRMode.active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_click(event.pressed)
