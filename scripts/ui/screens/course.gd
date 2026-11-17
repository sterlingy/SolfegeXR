extends Control
## A song's generated course: what it needs, what you already know, the steps.


func setup(args: Dictionary) -> void:
	var col := UI.page(self)
	UI.back_button(col)
	var entry: Dictionary = {}
	for s in App.catalog:
		if s.id == args.song_id:
			entry = s
	var analysis := App.song_analysis(args.song_id)
	if analysis == null:
		UI.label(col, "Couldn't open that song.")
		return
	var course := CourseBuilder.build(analysis, App.profile)
	UI.title(col, entry.get("title", analysis.song.title), 56)
	UI.muted(col, "In %s for your voice · %d phrases" % [course.key.name(), analysis.phrases.size()])
	if entry.get("confidence", "high") in ["low", "medium"]:
		UI.muted(col, "Draft transcription: notes may still be corrected.", 28)

	var known: Array[String] = []
	var todo: Array[String] = []
	for s in course.skills_needed:
		(todo if s in course.skills_to_learn else known).append(Skills.display_name(s))
	if not known.is_empty():
		UI.label(col, "You already know: " + ", ".join(known), 36, UI.GOOD)
	if not todo.is_empty():
		UI.label(col, "This song will teach: " + ", ".join(todo), 36, UI.WARM)

	var needs_phones := analysis.needs(Skills.Id.ENSEMBLE) and not App.profile.has_headphones
	for i in course.steps.size():
		var e: Exercise = course.steps[i]
		if e.skill == Skills.Id.ENSEMBLE and needs_phones:
			UI.muted(col, "Ensemble stages need headphones (Settings).")
			break
		var b := UI.button(col, e.title, func(): _open(course, i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 38)


func _open(course: CourseBuilder.Course, i: int) -> void:
	App.go("practice", {exercises = course.steps, index = i, title = course.song.song.title})
