class_name SkillProgress
extends RefCounted
## Progress on one skill. Keeps a short window of recent results plus a
## per-day summary, so the app can show "day 1 next to today".

var skill: Skills.Id
var total_notes := 0
var total_landed := 0
var recent: Array[bool] = []          ## last N landed/not (N = rules.window)
var days := {}                        ## "YYYY-MM-DD" -> {notes:int, landed:int, cents:float}
var mastered := false
var mastered_on := ""


func _init(p_skill := Skills.Id.PITCH_MATCH) -> void:
	skill = p_skill


func record(results: Array[NoteResult], rules: MasteryRules, date: String) -> void:
	for r in results:
		if r.verdict == NoteScorer.Verdict.NO_VOICE:
			continue  # silence isn't a miss; don't punish hesitation
		var landed := r.landed()
		total_notes += 1
		if landed:
			total_landed += 1
		recent.append(landed)
		while recent.size() > rules.window:
			recent.pop_front()
		var d: Dictionary = days.get(date, {notes = 0, landed = 0, cents = 0.0})
		d.notes += 1
		if landed:
			d.landed += 1
		if not is_nan(r.median_cents):
			d.cents += absf(r.median_cents)
		days[date] = d
	if not mastered and is_mastered(rules):
		mastered = true
		mastered_on = date


func recent_accuracy() -> float:
	if recent.is_empty():
		return 0.0
	return float(recent.count(true)) / recent.size()


func is_mastered(rules: MasteryRules) -> bool:
	return total_notes >= rules.min_notes and recent.size() >= rules.window \
			and recent_accuracy() >= rules.accuracy and days.size() >= rules.min_days


## Accuracy per day, oldest first: [{date, accuracy, avg_cents}]
func history() -> Array:
	var keys := days.keys()
	keys.sort()
	var out := []
	for k in keys:
		var d: Dictionary = days[k]
		out.append({date = k, accuracy = float(d.landed) / maxi(1, d.notes),
			avg_cents = d.cents / maxi(1, d.notes)})
	return out


func to_dict() -> Dictionary:
	return {skill = Skills.Id.keys()[skill], total_notes = total_notes, total_landed = total_landed,
		recent = recent, days = days, mastered = mastered, mastered_on = mastered_on}


static func from_dict(d: Dictionary) -> SkillProgress:
	var p := SkillProgress.new(Skills.Id.get(d.get("skill", "PITCH_MATCH"), 0))
	p.total_notes = int(d.get("total_notes", 0))
	p.total_landed = int(d.get("total_landed", 0))
	for b in d.get("recent", []):
		p.recent.append(bool(b))
	p.days = d.get("days", {})
	p.mastered = bool(d.get("mastered", false))
	p.mastered_on = str(d.get("mastered_on", ""))
	return p
