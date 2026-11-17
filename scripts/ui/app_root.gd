extends Control
## Root of the app: hosts the screens (see App.go) and handles dev arguments:
##   -- --profile=user://dev.json   use a separate save file
##   -- --demo                      demo singer instead of the mic
##   -- --screen=home|practice|...  open a screen directly (practice: core lesson)
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
	if screen == "practice-core":
		App.go("home", {}, false)
		App.go("practice", {exercises = Curriculum.exercises_for(Skills.Id.STEPS, 0), title = "Steps"})
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
