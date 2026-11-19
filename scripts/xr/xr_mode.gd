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
## OpenXR (native builds). Typed as XRInterface: the web build doesn't include
## the OpenXRInterface class, so naming it would break the script there.
var _openxr: XRInterface
var _ar_supported := false
var _vr_supported := false
var _xr_frames := 0            ## frames since entering XR (diagnostics)


func _ready() -> void:
	if OS.has_feature("web"):
		_install_web_diag()
		_web = XRServer.find_interface("WebXR") as WebXRInterface
		diag("webxr interface=%s" % (_web != null))
		if _web:
			_web.session_supported.connect(_on_session_supported)
			_web.session_started.connect(_on_web_started)
			_web.session_ended.connect(_on_ended)
			_web.session_failed.connect(func(msg): diag("session_failed " + str(msg)); push_warning("WebXR failed: " + msg); _on_ended())
			_web.is_session_supported("immersive-ar")
			_web.is_session_supported("immersive-vr")
	elif OS.has_feature("xr"):
		_openxr = XRServer.find_interface("OpenXR")
		available = _openxr != null
		if available:
			_start_openxr.call_deferred()


func _on_session_supported(session_mode: String, supported: bool) -> void:
	if session_mode == "immersive-ar":
		# "?xr=vr" skips AR: on Android, Chrome's immersive-ar can route through the
		# Play Store (Google Play Services for AR). Optical see-through glasses like
		# the XREAL Aura still show the room in a VR session (black = clear).
		_ar_supported = supported and _web_query("xr") != "vr"
	elif session_mode == "immersive-vr":
		_vr_supported = supported
	diag("supported %s=%s (xr=%s)" % [session_mode, supported, _web_query("xr")])
	var was := available
	available = _ar_supported or _vr_supported
	mode_label = "AR" if _ar_supported else "VR"
	if available != was:
		availability_changed.emit(available)


## A URL query value on the web ("" if absent or not on the web).
static func _web_query(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval(
		"new URLSearchParams(location.search).get(%s) || ''" % JSON.stringify(key), true)
	return str(v) if v != null else ""


## Start XR. On the web this must follow a tap (browsers require a gesture).
func enter() -> void:
	if active:
		return
	if _web:
		_web.session_mode = "immersive-ar" if _ar_supported else "immersive-vr"
		_web.required_features = "local"
		_web.optional_features = "local-floor, hand-tracking"
		_web.requested_reference_space_types = "local-floor, local"
		diag("enter: requesting " + _web.session_mode)
		var ok := _web.initialize()
		diag("enter: initialize returned %s" % ok)
		if not ok:
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
	diag("session_started mode=%s ref=%s" % [_web.session_mode, _web.reference_space_type])
	active = true
	var blend := _web.get_environment_blend_mode() if _web.has_method("get_environment_blend_mode") else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	transparent = _web.session_mode == "immersive-ar" or blend != XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	diag("blend=%s transparent=%s; loading XR scene" % [blend, transparent])
	_xr_frames = 0
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
	var hz: float = _openxr.call("get_display_refresh_rate") if _openxr.has_method("get_display_refresh_rate") else 0.0
	Engine.physics_ticks_per_second = int(hz) if hz > 0.0 else 72
	active = true
	_switch_to_xr()


func _switch_to_xr() -> void:
	get_viewport().use_xr = true
	get_tree().change_scene_to_file(XR_SCENE)
	session_changed.emit(true)


func _on_ended() -> void:
	diag("session_ended (active=%s, frames=%d)" % [active, _xr_frames])
	if not active:
		return
	active = false
	transparent = false
	get_viewport().use_xr = false
	get_viewport().transparent_bg = false
	get_tree().change_scene_to_file(APP_SCENE)
	session_changed.emit(false)


func _process(_delta: float) -> void:
	if active and _web:
		_xr_frames += 1
		if _xr_frames in [1, 30, 120, 600]:
			diag("xr frame %d, fps %d" % [_xr_frames, Engine.get_frames_per_second()])


## Opt-in remote diagnostics (web, "?diag=1"): sends one short line to the
## hosting server's /__diag log. Lets us see how far XR got on a headset we
## can't attach a debugger to. Nothing is sent without ?diag=1.
static func diag(msg: String) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("window.solfegeXrDiag && window.solfegeXrDiag(%s)" % JSON.stringify(msg), true)


static func _install_web_diag() -> void:
	JavaScriptBridge.eval("""
(function () {
  if (window.solfegeXrDiag) return;
  var on = new URLSearchParams(location.search).get('diag') === '1';
  window.solfegeXrDiag = function (msg) {
    if (!on) return;
    try {
      var url = '/__diag?xr=' + encodeURIComponent(String(msg).slice(0, 300)) + '&t=' + Date.now();
      if (navigator.sendBeacon) navigator.sendBeacon(url); else fetch(url, { keepalive: true });
    } catch (e) {}
  };
  if (!on) return;
  window.addEventListener('error', function (e) { window.solfegeXrDiag('js error: ' + e.message + ' @' + e.filename + ':' + e.lineno); });
  window.addEventListener('unhandledrejection', function (e) { window.solfegeXrDiag('js rejection: ' + (e.reason && (e.reason.message || e.reason))); });
  window.solfegeXrDiag('page ' + navigator.userAgent + ' xr=' + ('xr' in navigator));
})();
""", true)
