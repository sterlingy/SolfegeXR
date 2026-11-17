extends Control
## Progress over weeks: for each skill, your first day next to your latest.


func setup(_args: Dictionary) -> void:
	var col := UI.page(self)
	UI.back_button(col)
	UI.title(col, "Your progress", 56)
	var p := App.profile
	var any := false
	for s in Curriculum.active_skills(p):
		var prog := p.progress(s)
		if prog.total_notes == 0:
			continue
		any = true
		var c := UI.card(col)
		var name := Skills.display_name(s)
		if prog.mastered:
			name += "  ✓"
		UI.label(c, name, 44, UI.GOOD if prog.mastered else UI.TEXT)
		var h := prog.history()
		var first: Dictionary = h[0]
		var last: Dictionary = h[-1]
		UI.bar(c, first.accuracy, UI.ACCENT.darkened(0.3), "First day (%s): %d%% landed" % [first.date, roundi(first.accuracy * 100)])
		if h.size() > 1:
			UI.bar(c, last.accuracy, UI.GOOD, "Latest (%s): %d%% landed" % [last.date, roundi(last.accuracy * 100)])
		UI.muted(c, "%d notes sung over %d days" % [prog.total_notes, h.size()], 30)
	if not any:
		UI.label(col, "Sing your first lesson and your progress will show up here.")
