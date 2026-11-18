extends Control
## Root of the app: hosts the screens (see App.go) and handles dev arguments:
##   -- --profile=user://dev.json   use a separate save file
##   -- --demo                      demo singer instead of the mic
##   -- --screen=home|practice-core|practice:PITCH_MATCH:2|course:<id>|...  open a screen directly
##   -- --autostart                 practice screens start right away
##   -- --screenshot=path.png       save a screenshot after --wait seconds, then quit
##   -- --wait=4


func _ready() -> void:
	App.root = self
	var args := OS.get_cmdline_user_args()
	var screen := ""
	var shot := ""
	var wait := 4.0
	for a in args:
		if a == "--demo":
			App.use_demo_singer = true
		elif a == "--autostart":
			App.dev_autostart = true
		elif a.begins_with("--screen="):
			screen = a.trim_prefix("--screen=")
		elif a.begins_with("--screenshot="):
			shot = a.trim_prefix("--screenshot=")
		elif a.begins_with("--wait="):
			wait = a.trim_prefix("--wait=").to_float()
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
	if shot != "":
		await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
