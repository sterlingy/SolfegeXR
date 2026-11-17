extends Control
## Home: the next lesson, the songs, and the way to progress and settings.


func setup(_args: Dictionary) -> void:
	var col := UI.page(self)
	var p := App.profile
	UI.title(col, "Ready to sing?")

	var next := Curriculum.next_skill(p)
	var lesson := UI.card(col)
	UI.muted(lesson, "Next lesson", 32)
	UI.label(lesson, Skills.display_name(next), 52, UI.WARM)
	var prog := p.progress(next)
	if prog.total_notes > 0:
		UI.bar(lesson, prog.recent_accuracy(), UI.GOOD, "Recent notes landed: %d%%" % roundi(prog.recent_accuracy() * 100))
	if Curriculum.needs_headphones(next, p):
		UI.muted(lesson, "This lesson needs headphones. You can say you have them in Settings.")
	elif next in [Skills.Id.PHRASES, Skills.Id.BACKING_TRACK, Skills.Id.ENSEMBLE]:
		UI.muted(lesson, "Learn this one through a song below.")
	else:
		UI.button(lesson, "Start", func(): _start_core(next), true)

	UI.label(col, "Songs", 48)
	for s in App.catalog:
		var title: String = s.title
		UI.button(col, title, func(): App.go("course", {song_id = s.id}))

	var r := UI.row(col)
	for item in [["Progress", "progress"], ["Free sing", "free_sing"], ["Settings", "settings"]]:
		var b := UI.button(r, item[0], func(): App.go(item[1]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 36)


func _start_core(skill: Skills.Id) -> void:
	var key_pc := 0  # C major family; transposed into the voice by home_tonic()
	var list: Array[Exercise] = []
	list.append(_key_setup(key_pc))
	list.append_array(Curriculum.exercises_for(skill, key_pc))
	App.go("practice", {exercises = list, title = Skills.display_name(skill)})


## Key setup: after the cadence, sing do-mi-sol-do back.
static func _key_setup(key_pc: int) -> Exercise:
	var e := Exercise.new()
	e.skill = Skills.Id.PITCH_MATCH
	e.key = MusicKey.new(key_pc)
	e.title = "Find the key"
	e.prompt = "Listen to the chords, then sing do, mi, sol, do back."
	e.add_degrees([1, 3, 5, 8], 1.0)
	e.record = false
	return e
