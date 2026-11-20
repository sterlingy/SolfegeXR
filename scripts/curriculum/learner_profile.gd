class_name LearnerProfile
extends RefCounted
## Everything the app remembers about the learner, saved locally as JSON in
## user:// (on web that's the browser's IndexedDB). Nothing is shared.

## Where save()/load_or_new() go by default (dev runs point this elsewhere).
static var save_path := "user://profile.json"
const VERSION := 1

var voice_low := 48            ## comfortable range from the range test (MIDI)
var voice_high := 64
var range_tested := false
var minor_syllables := MusicKey.MinorSyllables.LA_BASED
var chromatic_enabled := false
var has_headphones := false
var tempo_scale := 1.0         ## preferred practice speed
var metronome := false         ## click the beat during the count-in and singing
var mic_device_id := ""        ## chosen input ("" = browser default)
var onboarded := false
var skills := {}               ## Skills.Id -> SkillProgress
var rules := MasteryRules.new()


func progress(skill: Skills.Id) -> SkillProgress:
	if not skills.has(skill):
		skills[skill] = SkillProgress.new(skill)
	return skills[skill]


func is_mastered(skill: Skills.Id) -> bool:
	return skills.has(skill) and skills[skill].mastered


func record(skill: Skills.Id, results: Array[NoteResult], date := "") -> void:
	if date == "":
		date = Time.get_date_string_from_system()
	progress(skill).record(results, rules, date)


## Overall skill 0..1 (share of core skills mastered); drives scoring tolerance.
func skill_level() -> float:
	var core := Curriculum.active_skills(self)
	var n := 0
	for s in core:
		if is_mastered(s):
			n += 1
	return float(n) / maxi(1, core.size())


func scoring_settings() -> ScoringSettings:
	return ScoringSettings.for_skill(skill_level())


## The tonic to use for exercises in key `tonic_pc`: low enough that the octave
## above fits, high enough that sol below fits when the range allows.
func home_tonic(tonic_pc: int) -> int:
	var best := -1
	var best_score := -INF
	for m in range(voice_low - 12, voice_high + 1):
		if posmod(m, 12) != tonic_pc:
			continue
		var score := 0.0
		score -= maxf(0.0, voice_low - (m - 5)) * 2.0     # sol below should fit
		score -= maxf(0.0, (m + 12) - voice_high) * 3.0   # do' above should fit
		score -= maxf(0.0, voice_low - m) * 10.0          # do itself must fit
		if score > best_score:
			best_score = score
			best = m
	return best


func apply_to_key(key: MusicKey) -> void:
	key.minor_syllables = minor_syllables
	key.chromatic_enabled = chromatic_enabled


func to_dict() -> Dictionary:
	var sk := {}
	for id in skills:
		sk[Skills.Id.keys()[id]] = skills[id].to_dict()
	return {version = VERSION, voice_low = voice_low, voice_high = voice_high,
		range_tested = range_tested, minor_syllables = int(minor_syllables),
		chromatic_enabled = chromatic_enabled, has_headphones = has_headphones,
		tempo_scale = tempo_scale, metronome = metronome, onboarded = onboarded, mic_device_id = mic_device_id, skills = sk}


static func from_dict(d: Dictionary) -> LearnerProfile:
	var p := LearnerProfile.new()
	p.voice_low = int(d.get("voice_low", p.voice_low))
	p.voice_high = int(d.get("voice_high", p.voice_high))
	p.range_tested = bool(d.get("range_tested", false))
	p.minor_syllables = int(d.get("minor_syllables", 0)) as MusicKey.MinorSyllables
	p.chromatic_enabled = bool(d.get("chromatic_enabled", false))
	p.has_headphones = bool(d.get("has_headphones", false))
	p.tempo_scale = float(d.get("tempo_scale", 1.0))
	p.metronome = bool(d.get("metronome", false))
	p.onboarded = bool(d.get("onboarded", false))
	p.mic_device_id = str(d.get("mic_device_id", ""))
	var sk: Dictionary = d.get("skills", {})
	for name in sk:
		if Skills.Id.has(name):
			p.skills[Skills.Id[name]] = SkillProgress.from_dict(sk[name])
	return p


func save(path := "") -> Error:
	if path == "":
		path = save_path
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "  "))
	return OK


static func load_or_new(path := "") -> LearnerProfile:
	if path == "":
		path = save_path
	if not FileAccess.file_exists(path):
		return LearnerProfile.new()
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(d) if d is Dictionary else LearnerProfile.new()
