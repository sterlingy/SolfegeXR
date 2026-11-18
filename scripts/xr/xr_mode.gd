extends Node
## XR on/off for the whole app (autoload "XRMode").
##
## Web: WebXR. "immersive-ar" is preferred (see-through glasses like the XREAL
## Aura, or passthrough), with "immersive-vr" as a fallback (e.g. a headset
## browser without AR). Native (Android XR build, feature tag "xr"): OpenXR,
## started automatically, with a see-through blend mode when the device has one.
##
## While XR is active the main scene is scenes/xr_root.tscn, which hosts the
## normal 2D app on a floating panel.

signal availability_changed(available: bool)
signal session_changed(active: bool)

const XR_SCENE := "res://scenes/xr_root.tscn"
const APP_SCENE := "res://scenes/app_root.tscn"

var available := false        ## an XR session can be started here
var active := false           ## an XR session is running
var transparent := false      ## the world shows through (AR / see-through)
var mode_label := "AR"        ## "AR" or "VR", for buttons

var _web: WebXRInterface
var _openxr: OpenXRInterface
var _ar_supported := false
var _vr_supported := false


func _ready() -> void:
	if OS.has_feature("web"):
		_web = XRServer.find_interface("WebXR") as WebXRInterface
		if _web:
			_web.session_supported.connect(_on_session_supported)
			_web.session_started.connect(_on_web_started)
			_web.session_ended.connect(_on_ended)
			_web.session_failed.connect(func(msg): push_warning("WebXR failed: " + msg); _on_ended())
			_web.is_session_supported("immersive-ar")
			_web.is_session_supported("immersive-vr")
	elif OS.has_feature("xr"):
		_openxr = XRServer.find_interface("OpenXR") as OpenXRInterface
		available = _openxr != null
		if available:
			_start_openxr.call_deferred()


func _on_session_supported(session_mode: String, supported: bool) -> void:
	if session_mode == "immersive-ar":
		_ar_supported = supported
	elif session_mode == "immersive-vr":
		_vr_supported = supported
	var was := available
	available = _ar_supported or _vr_supported
	mode_label = "AR" if _ar_supported else "VR"
	if available != was:
		availability_changed.emit(available)


## Start XR. On the web this must follow a tap (browsers require a gesture).
func enter() -> void:
	if active:
		return
	if _web:
		_web.session_mode = "immersive-ar" if _ar_supported else "immersive-vr"
		_web.required_features = "local"
		_web.optional_features = "local-floor, hand-tracking"
		_web.requested_reference_space_types = "local-floor, local"
		if not _web.initialize():
			push_warning("WebXR could not start")
	elif _openxr:
		_start_openxr()


func exit() -> void:
	if not active:
		return
	if _web:
		_web.uninitialize()  # session_ended follows
	elif _openxr:
		get_tree().quit()  # native XR app: leaving XR means leaving the app


func _on_web_started() -> void:
	active = true
	var blend := _web.get_environment_blend_mode() if _web.has_method("get_environment_blend_mode") else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	transparent = _web.session_mode == "immersive-ar" or blend != XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	_switch_to_xr()


func _start_openxr() -> void:
	if not _openxr.is_initialized() and not _openxr.initialize():
		push_warning("OpenXR could not start")
		return
	# See-through glasses use additive blending; passthrough headsets alpha blend.
	var modes: Array = _openxr.get_supported_environment_blend_modes()
	for m in [XRInterface.XR_ENV_BLEND_MODE_ADDITIVE, XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND]:
		if m in modes and _openxr.set_environment_blend_mode(m):
			transparent = true
			break
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.physics_ticks_per_second = int(_openxr.get_display_refresh_rate()) if _openxr.get_display_refresh_rate() > 0 else 72
	active = true
	_switch_to_xr()


func _switch_to_xr() -> void:
	get_viewport().use_xr = true
	get_tree().change_scene_to_file(XR_SCENE)
	session_changed.emit(true)


func _on_ended() -> void:
	if not active:
		return
	active = false
	transparent = false
	get_viewport().use_xr = false
	get_viewport().transparent_bg = false
	get_tree().change_scene_to_file(APP_SCENE)
	session_changed.emit(false)
