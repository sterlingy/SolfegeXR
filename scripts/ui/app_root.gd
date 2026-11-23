extends Control
## Root of the app: hosts the screens (see App.go) and handles dev arguments:
##   -- --profile=user://dev.json   use a separate save file
##   -- --demo                      demo singer instead of the mic
##   -- --screen=home|practice-core|practice:PITCH_MATCH:2|course:<id>|...  open a screen directly
##   -- --autostart                 practice screens start right away
##   -- --screenshot=path.png       save a screenshot after --wait seconds, then quit
##   -- --wait=4
##   -- --fake-update               show the "new version" bar (desktop check)


var _update_bar: Button


func _ready() -> void:
	App.root = self
	# Installed web app (PWA): when a newer version has been deployed, offer it.
	if OS.has_feature("web"):
		JavaScriptBridge.pwa_update_available.connect(_on_pwa_update)
		if JavaScriptBridge.pwa_needs_update():
			_on_pwa_update.call_deferred()
	var args := OS.get_cmdline_user_args()
	var screen := ""
	var shot := ""
	var wait := 4.0
	for a in args:
		if a == "--demo":
			App.use_demo_singer = true
		elif a == "--fake-update":
			_on_pwa_update.call_deferred()
		elif a == "--autostart":
			App.dev_autostart = true
		elif a.begins_with("--screen="):
			screen = a.trim_prefix("--screen=")
		elif a.begins_with("--screenshot="):
			shot = a.trim_prefix("--screenshot=")
		elif a.begins_with("--wait="):
			wait = a.trim_prefix("--wait=").to_float()
		elif a == "--xr-preview" and not (get_parent() is SubViewport):
			get_tree().change_scene_to_file.call_deferred(XRMode.XR_SCENE)
			_screenshot_later(args)
			return
	if screen == "practice-core" or screen.begins_with("practice:"):
		# practice:PITCH_MATCH[:index] opens a core lesson (default: Steps).
		var bits := screen.split(":")
		var skill: Skills.Id = Skills.Id.get(bits[1], Skills.Id.STEPS) if bits.size() > 1 else Skills.Id.STEPS
		var index := bits[2].to_int() if bits.size() > 2 else 0
		App.go("home", {}, false)
		App.go("practice", {exercises = Curriculum.exercises_for(skill, 0), index = index,
			title = Skills.display_name(skill)})
	elif screen.begins_with("course-step:"):
		# course-step:<song_id>:<step index or title> opens one step of a song's course.
		var cs := screen.split(":")
		var c := CourseBuilder.build(App.song_analysis(cs[1]), App.profile)
		App.go("home", {}, false)
		var idx := cs[2].to_int()
		for k in c.steps.size():
			if c.steps[k].title == cs[2]:
				idx = k
		App.go("practice", {exercises = c.steps, index = idx, title = c.song.song.title})
	elif screen.begins_with("course:"):
		App.go("home", {}, false)
		App.go("course", {song_id = screen.trim_prefix("course:")})
	elif screen != "":
		App.go("home", {}, false)
		App.go(screen)
	elif not App.profile.onboarded:
		App.go("onboarding", {}, false)
	else:
		App.go("home", {}, false)
	if shot != "" and not (get_parent() is SubViewport):  # the XR panel's copy doesn't screenshot
		await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


func _on_pwa_update() -> void:
	if _update_bar:
		return
	# Its own canvas layer: screens opened later are added after it, and
	# z_index only changes drawing, so they'd catch its taps otherwise.
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var holder := MarginContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -170
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		holder.add_theme_constant_override("margin_" + side, UI.GUTTER)
	layer.add_child(holder)
	_update_bar = UI.button(holder, "A new version is ready. Tap to update.",
		func():
			print("update bar tapped")
			if OS.has_feature("web"):
				JavaScriptBridge.pwa_update(), true)
	_update_bar.add_theme_font_size_override("font_size", 38)


## Screenshot support that survives a scene change (used by --xr-preview).
func _screenshot_later(args: PackedStringArray) -> void:
	var shot := ""
	var wait := 4.0
	for a in args:
		if a.begins_with("--screenshot="):
			shot = a.trim_prefix("--screenshot=")
		elif a.begins_with("--wait="):
			wait = a.trim_prefix("--wait=").to_float()
	if shot == "":
		return
	var tree := get_tree()
	tree.create_timer(wait).timeout.connect(func():
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png(shot)
		tree.quit())
