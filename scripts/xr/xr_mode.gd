extends Node
## XR on/off for the whole app (autoload "XRMode").
##
## Web: WebXR through the Shivoo XR addon's two-pass stereo (addons/shivoo_xr,
## scripts/webxr_stereo.gd + web/webxr_stereo.js). Godot's own WebXR renderer
## needs the OVR_multiview2 WebGL extension, which Chrome on the XREAL Aura and
## Galaxy XR doesn't have, so nothing showed. The addon runs the session itself and
## renders each eye into its own SubViewport instead. "immersive-ar" is preferred
## (the room shows through); "?xr=vr" forces immersive-vr, "?webxr=native" uses
## Godot's own WebXR session (for comparison on browsers that have multiview).
##
## Native (Android XR build, feature tag "xr"): OpenXR, started automatically,
## with a see-through blend mode when the device has one.
##
## While XR is active the main scene is scenes/xr_root.tscn, which hosts the
## normal 2D app on a floating panel.
## (UE comparison: the rig below is like a persistent VR Pawn spawned by the
## GameInstance, so it survives level changes; xr_root is the level.)

signal availability_changed(available: bool)
signal session_changed(active: bool)
## A site page ("manual" / "privacy") was asked for while the XR scene is
## showing; it opens in a window there (a browser tab can't show inside XR).
signal doc_requested(page: String)

const XR_SCENE := "res://scenes/xr_root.tscn"
const APP_SCENE := "res://scenes/app_root.tscn"
const START_XR_SCRIPT := preload("res://addons/godot-xr-tools/xr/start_xr.gd")
const STEREO_SCRIPT := preload("res://addons/shivoo_xr/scripts/webxr_stereo.gd")

var available := false        ## an XR session can be started here
var active := false           ## an XR session is running
var transparent := false      ## the world shows through (AR / see-through)
var mode_label := "AR"        ## "AR" or "VR", for buttons

## The tracked rig, shared with xr_root while a session runs (web stereo path).
## Only in the tree during a session, so the 2D app never renders 3D.
var origin: XROrigin3D
var camera: XRCamera3D
var controllers: Array[XRController3D] = []

var _web: WebXRInterface
## OpenXR (native builds). Typed as XRInterface: the web build doesn't include
## the OpenXRInterface class, so naming it would break the script there.
var _openxr: XRInterface
var _ar_supported := false
var _vr_supported := false
var _start_xr: Node            ## XRToolsStartXR (web stereo path)
var _stereo: Node              ## the addon's WebXRStereo node
var _xr_frames := 0            ## frames since entering XR (diagnostics)
var _last_stage := ""
var _select_js: JavaScriptObject  ## window.solfegeXrSelect: the browser's pinch per hand


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
		# Headsets and glasses: set up the stereo rig now, while the page is still
		# drawing (the addon must hook the WebGL context before a session starts).
		# Only when VR is supported: XR Tools' StartXR alerts "your browser doesn't
		# support immersive-vr" otherwise, which every phone and desktop would see.
		if supported and _web_query("webxr") != "native":
			_build_stereo_rig.call_deferred()
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


# ------------------------------------------------------------ web stereo rig

func _build_stereo_rig() -> void:
	if _stereo:
		return
	diag("building stereo rig")
	origin = XROrigin3D.new()
	origin.name = "XROrigin"
	camera = XRCamera3D.new()
	camera.name = "XRCamera"
	camera.near = 0.05
	origin.add_child(camera)
	for hand in ["left_hand", "right_hand"]:
		var c := XRController3D.new()
		c.name = hand
		c.tracker = hand
		c.pose = "aim"
		origin.add_child(c)
		controllers.append(c)
	# XR Tools' StartXR, built in code rather than from start_xr.tscn so the web
	# export doesn't have to carry XR Tools' scenes (their hand models and
	# textures are ~12 MB). Same node names as the scene: the stereo node looks
	# for EnterWebXR/EnterVRButton. Our home screen has its own Enter AR button,
	# so XR Tools' overlay button stays hidden and is only pressed from code.
	_start_xr = Node.new()
	_start_xr.name = "StartXR"
	_start_xr.set_script(START_XR_SCRIPT)
	var layer := CanvasLayer.new()
	layer.name = "EnterWebXR"
	layer.visible = false
	_start_xr.add_child(layer)
	var button := Button.new()
	button.name = "EnterVRButton"
	button.visible = false
	layer.add_child(button)
	button.pressed.connect(Callable(_start_xr, "_on_enter_webxr_button_pressed"))
	add_child(_start_xr)
	_stereo = Node.new()
	_stereo.name = "WebXRStereo"
	_stereo.set_script(STEREO_SCRIPT)
	_stereo.set("start_xr", _start_xr)
	_stereo.set("origin", origin)
	_stereo.set("prefer_passthrough", _web_query("xr") != "vr")
	add_child(_stereo)
	_start_xr.connect("xr_started", _on_stereo_started)
	_start_xr.connect("xr_ended", _on_ended)
	diag("stereo rig ready (prefer AR=%s)" % _stereo.get("prefer_passthrough"))


func _stereo_js() -> JavaScriptObject:
	return JavaScriptBridge.get_interface("ShivooStereo") if OS.has_feature("web") else null


func _on_stereo_started() -> void:
	var js := _stereo_js()
	diag("stereo session started mode=%s ref=%s" % [js.sessionMode if js else "?", js.referenceSpaceType if js else "?"])
	# Into the tree only now (a failed start leaves no 3D camera behind). The
	# stereo node first moves its eyes in its next _process, after this.
	if origin.get_parent() == null:
		add_child(origin)
	active = true
	transparent = bool(_stereo.get("passthrough_active"))
	_xr_frames = 0
	# The stereo node renders the eyes itself; the main viewport stays non-XR.
	_watch_select()
	get_tree().change_scene_to_file(XR_SCENE)
	session_changed.emit(true)


## Listen for the browser's own pinch (WebXR selectstart/selectend) on the
## stereo session. It is the system's pinch recogniser, steadier than working
## one out from the hand joints. `?pinch=joints` turns it off.
func _watch_select() -> void:
	_select_js = null
	if not OS.has_feature("web") or _web_query("pinch") == "joints":
		return
	JavaScriptBridge.eval("""
(function () {
  var st = window.solfegeXrSelect = { left: 0, right: 0, seenleft: 0, seenright: 0 };
  var s = window.ShivooStereo && window.ShivooStereo.session;
  if (!s) return;
  function on(v) {
    return function (e) {
      var h = e.inputSource && e.inputSource.handedness;
      if (h !== 'left' && h !== 'right') return;
      st[h] = v;
      if (!st['seen' + h]) {
        st['seen' + h] = 1;
        if (window.solfegeXrDiag) window.solfegeXrDiag('browser select events: yes (' + h + ')');
      }
    };
  }
  s.addEventListener('selectstart', on(1));
  s.addEventListener('selectend', on(0));
})();
""", true)
	_select_js = JavaScriptBridge.get_interface("solfegeXrSelect")


## The browser's pinch for "left" or "right": 1 pinched, 0 open, or -1 when
## the browser hasn't reported one for that hand (use the joints instead).
func select_state(hand: String) -> int:
	if _select_js == null or not active:
		return -1
	if not bool(_select_js.get("seen" + hand)):
		return -1
	return int(_select_js.get(hand))


# ------------------------------------------------------------------ enter/exit

## Start XR. On the web this must follow a tap (browsers require a gesture).
func enter() -> void:
	if active:
		return
	if _stereo:
		diag("enter: stereo, AR=%s" % _stereo.get("prefer_passthrough"))
		# The stereo node took over this button's pressed signal.
		(_start_xr.get_node("EnterWebXR/EnterVRButton") as Button).pressed.emit()
	elif _web:
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
	if _stereo:
		var js := _stereo_js()
		if js:
			js.end()  # xr_ended follows
	elif _web:
		_web.uninitialize()  # session_ended follows
	elif _openxr:
		get_tree().quit()  # native XR app: leaving XR means leaving the app


func _on_web_started() -> void:
	diag("session_started mode=%s ref=%s" % [_web.session_mode, _web.reference_space_type])
	active = true
	var blend := _web.get_environment_blend_mode() if _web.has_method("get_environment_blend_mode") else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	transparent = _web.session_mode == "immersive-ar" or blend != XRInterface.XR_ENV_BLEND_MODE_OPAQUE
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
	if origin and origin.get_parent() == self:
		remove_child(origin)
	if not active:
		return
	active = false
	transparent = false
	get_viewport().use_xr = false
	get_viewport().transparent_bg = false
	get_tree().change_scene_to_file(APP_SCENE)
	session_changed.emit(false)


# ---------------------------------------------------------------- diagnostics

func _process(_delta: float) -> void:
	if _stereo:
		var js := _stereo_js()
		if js:
			var stage := str(js.stage)
			if stage != _last_stage:
				_last_stage = stage
				diag("stereo stage: " + stage)
	if active:
		_xr_frames += 1
		if _xr_frames in [1, 30, 120, 600]:
			diag("xr frame %d, fps %d, %s" % [_xr_frames, Engine.get_frames_per_second(), _scene_report()])


## Where the camera and panel are, and what the headset reports.
func _scene_report() -> String:
	var out := ""
	var root := get_tree().current_scene
	if root and root.get("camera") and root.get("panel"):
		var cam: Node3D = root.camera
		var pan: Node3D = root.panel
		var to_panel := pan.global_position - cam.global_position
		var ang := rad_to_deg((-cam.global_basis.z).angle_to(to_panel)) if to_panel.length() > 0.001 else -1.0
		out += "cam=%s panel=%s dist=%.2f angle=%.0f placed=%s" % [
			cam.global_position.snapped(Vector3.ONE * 0.01), pan.global_position.snapped(Vector3.ONE * 0.01),
			to_panel.length(), ang, root.get("_placed")]
	else:
		out += "(scene=%s)" % (root.name if root else "none")
	var js := _stereo_js()
	if js:
		var frame: Variant = JSON.parse_string(str(js.frameJson))
		if frame is Dictionary:
			var hands := []
			for i: Dictionary in frame["inputs"]:
				hands.append("%s:%s%s" % [i["hand"], i["profile"], " (hand)" if i.get("isHand", false) else ""])
			out += " views=%d inputs=[%s]" % [(frame["views"] as Array).size(), ", ".join(hands)]
			if not (frame["views"] as Array).is_empty():
				out += " viewport=%s" % [frame["views"][0]["viewport"]]
		out += " | " + str(js.godotInfo)
	return out


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
      var url = '/__diag?xr=' + encodeURIComponent(String(msg).slice(0, 400)) + '&t=' + Date.now();
      if (navigator.sendBeacon) navigator.sendBeacon(url); else fetch(url, { keepalive: true });
    } catch (e) {}
  };
  if (!on) return;
  window.addEventListener('error', function (e) { window.solfegeXrDiag('js error: ' + e.message + ' @' + e.filename + ':' + e.lineno); });
  window.addEventListener('unhandledrejection', function (e) { window.solfegeXrDiag('js rejection: ' + (e.reason && (e.reason.message || e.reason))); });
  // The stereo script logs its progress and once-a-second stats to the console.
  var info = console.info.bind(console), err = console.error.bind(console), n = 0;
  console.info = function () { var s = Array.prototype.join.call(arguments, ' '); if (/WebXR stereo/.test(s) && n++ < 40) window.solfegeXrDiag('console: ' + s); info.apply(null, arguments); };
  console.error = function () { var s = Array.prototype.join.call(arguments, ' '); if (/WebXR|stereo/i.test(s)) window.solfegeXrDiag('console error: ' + s); err.apply(null, arguments); };
  window.solfegeXrDiag('page ' + navigator.userAgent + ' xr=' + ('xr' in navigator));
})();
""", true)
