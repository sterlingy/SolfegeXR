extends Control
## A song's generated course: what it needs, what you already know, the steps.


func setup(args: Dictionary) -> void:
	var col := UI.page(self)
	UI.back_button(col)
	var entry := App.song_entry(args.song_id)
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

	_part_picker(col, args.song_id, analysis)

	var told := false
	for i in course.steps.size():
		var e: Exercise = course.steps[i]
		if e.needs_headphones and not App.profile.has_headphones:
			if not told:
				UI.muted(col, "Steps with music (backing track, other voices) need headphones. Turn on \"I have headphones\" in Settings.")
				told = true
			continue
		var b := UI.button(col, e.title, func(): _open(course, i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 38)

	if entry.get("imported", false):
		var rm := UI.flat_button("Remove this song from the app", func(): _remove(args.song_id))
		rm.add_theme_color_override("font_color", UI.MUTED)
		col.add_child(rm)


## "Your part": one button per voice in the song (Soprano, Alto, Tenor,
## Bass...), with its printed range. The part closest to the learner's voice
## is marked. Picking one rebuilds the course around that line, moved into
## the learner's range; the choice is saved per song.
func _part_picker(col: VBoxContainer, song_id: String, analysis: SongAnalyzer.Result) -> void:
	var parts := analysis.song.singable_parts()
	if parts.size() < 2:
		return
	var card := UI.card(col)
	UI.label(card, "Your part", 40)
	var fit := App.best_fit_part(analysis.song, App.profile)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	card.add_child(grid)
	for p in parts:
		var a := analysis if p == analysis.part else SongAnalyzer.analyze(analysis.song, p)
		var text := "%s\n%s to %s" % [p.name, UI.note_name(a.low), UI.note_name(a.high)]
		if p == fit:
			text += " · fits you"
		var chosen := p == analysis.part
		var part_name := p.name
		var b := UI.button(grid, text, func(): _choose(song_id, part_name), chosen)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 34)
		if chosen:
			b.add_theme_color_override("font_color", UI.ACCENT)
	UI.muted(card, "Every part is moved into your range. The other parts play with you in the ensemble steps.", 28)


func _choose(song_id: String, part_name: String) -> void:
	App.profile.song_parts[song_id] = part_name
	App.profile.save()
	App.go("course", {song_id = song_id}, false)


func _open(course: CourseBuilder.Course, i: int) -> void:
	App.go("practice", {exercises = course.steps, index = i, title = course.title()})


func _remove(id: String) -> void:
	SongLibrary.remove(id)
	App.home()
