class_name Curriculum
extends RefCounted
## The fixed-order core curriculum. Exercises are defined by scale degree, so
## they work in any key and are transposed to the learner's voice.

const SONG_ORDER := [
	"01_ode_to_joy", "02_when_the_saints", "03_coming_round_the_mountain", "04_oh_susanna",
	"05_auld_lang_syne", "06_amazing_grace", "07_drunken_sailor",
	"08_take_me_out_to_the_ball_game", "09_shenandoah", "10_danny_boy", "11_carol_of_the_bells",
]


## Core skills that apply to this learner (chromatic only when that toggle is on;
## backing and ensemble only with headphones, since the mic hears the speakers).
static func active_skills(profile: LearnerProfile) -> Array[Skills.Id]:
	var out: Array[Skills.Id] = []
	for s in Skills.core_order():
		if s == Skills.Id.CHROMATIC and not profile.chromatic_enabled:
			continue
		out.append(s)
	return out


## The next skill to work on: first one not yet mastered, in core order.
static func next_skill(profile: LearnerProfile) -> Skills.Id:
	for s in active_skills(profile):
		if not profile.is_mastered(s):
			return s
	return Skills.Id.ENSEMBLE


## True when the skill needs headphones that the learner hasn't confirmed.
static func needs_headphones(skill: Skills.Id, profile: LearnerProfile) -> bool:
	return skill in [Skills.Id.BACKING_TRACK, Skills.Id.ENSEMBLE] and not profile.has_headphones


## Exercises for a core skill, in a major key on `tonic_pc` (minor skills use
## the relative minor's mode). Learners start with sirens before any syllables.
static func exercises_for(skill: Skills.Id, tonic_pc := 0) -> Array[Exercise]:
	var S := Skills.Id
	var major := MusicKey.new(tonic_pc, MusicKey.Mode.IONIAN)
	var out: Array[Exercise] = []
	match skill:
		S.PITCH_MATCH:
			# Sirens and slides first: find the voice before aiming at notes.
			var siren := _ex(skill, major, "Siren", "Slide your voice up and down like a siren, on \"ooo\". No wrong notes here.")
			siren.mode = Exercise.Mode.SIREN
			siren.record = false  # a warm-up
			siren.tempo_bpm = 60.0
			siren.add_glide([1, 5, 1], 2.0, 0.5)  # example: do up to sol and back, inside any voice
			out.append(siren)
			var slide := _ex(skill, major, "Slide to do", "Listen to do. Then start anywhere and slide until the line turns green. Stay there.")
			slide.mode = Exercise.Mode.SLIDE_TO
			slide.add_degrees([1], 3.0)
			out.append(slide)
			var follow := _ex(skill, major, "Follow the slide", "The note slides from do up to sol and back. Slide along with it.")
			follow.mode = Exercise.Mode.FOLLOW
			follow.tempo_bpm = 60.0
			follow.add_glide([1, 5, 1], 3.0, 1.0)
			out.append(follow)
			var slide_sol := _ex(skill, major, "Slide to sol", "Same idea, higher: slide until you land on sol, then stay.")
			slide_sol.mode = Exercise.Mode.SLIDE_TO
			slide_sol.add_degrees([5], 3.0)
			out.append(slide_sol)
			out.append(_ex(skill, major, "Find do", "Listen, then sing the same note. Slide around until it locks in.")
				.add_degrees([1], 3.0))
			out.append(_ex(skill, major, "Find sol", "Same idea, a little higher.").add_degrees([5], 3.0))
			out.append(_ex(skill, major, "Find mi", "This one sits between them.").add_degrees([3], 3.0))
			out.append(_ex(skill, major, "Sol below", "Now a low one. Let it be relaxed.").add_degrees([-5], 3.0))
		S.SUSTAIN:
			out.append(_ex(skill, major, "Hold do", "Land it, then keep it steady. Keep the air flowing.")
				.add_degrees([1], 6.0))
			out.append(_ex(skill, major, "Hold sol", "Steady and easy.").add_degrees([5], 6.0))
			out.append(_ex(skill, major, "Hold mi", "Nice and long.").add_degrees([3], 8.0))
		S.STEPS:
			out.append(_ex(skill, major, "Do re mi", "Little steps up and back.").add_degrees([1, 2, 3, 2, 1], 1.0))
			out.append(_ex(skill, major, "Mi fa sol", "The next three steps.").add_degrees([3, 4, 5, 4, 3], 1.0))
			out.append(_ex(skill, major, "Up the scale", "All the way up to high do.")
				.add_degrees([1, 2, 3, 4, 5, 6, 7, 8], 1.0))
			out.append(_ex(skill, major, "Down the scale", "And back down.")
				.add_degrees([8, 7, 6, 5, 4, 3, 2, 1], 1.0))
		S.SMALL_LEAPS:
			out.append(_ex(skill, major, "Do to mi", "Skip over re.").add_degrees([1, 3, 1, 3, 1], 1.0))
			out.append(_ex(skill, major, "Mi to sol", "Another skip.").add_degrees([3, 5, 3, 5, 3], 1.0))
			out.append(_ex(skill, major, "The triad", "Do, mi, sol: the home chord.").add_degrees([1, 3, 5, 3, 1], 1.0))
			out.append(_ex(skill, major, "Re to fa", "Skips can start anywhere.").add_degrees([2, 4, 2, 4, 2], 1.0))
		S.LARGE_LEAPS:
			out.append(_ex(skill, major, "Do to sol", "A bigger jump. Imagine sol before you sing it.")
				.add_degrees([1, 5, 1, 5, 1], 1.5))
			out.append(_ex(skill, major, "Sol up to do", "Like the start of Auld Lang Syne.")
				.add_degrees([-5, 1, -5, 1], 1.5))
			out.append(_ex(skill, major, "Do to high do", "The octave. Same note, higher.")
				.add_degrees([1, 8, 1, 8, 1], 1.5))
			out.append(_ex(skill, major, "Do to fa", "A fourth, like 'Here comes the bride'.")
				.add_degrees([1, 4, 1, 4, 1], 1.5))
		S.MINOR_MODES:
			var minor := MusicKey.new(tonic_pc + 9, MusicKey.Mode.AEOLIAN)
			out.append(_ex(skill, minor, "Minor home", "A darker home note. Listen first.")
				.add_degrees([1, 2, 3, 2, 1], 1.0))
			out.append(_ex(skill, minor, "Minor triad", "The minor home chord.").add_degrees([1, 3, 5, 3, 1], 1.0))
			var dorian := MusicKey.new(tonic_pc + 2, MusicKey.Mode.DORIAN)
			out.append(_ex(skill, dorian, "Dorian", "The sailor's mode: minor with a brighter sixth.")
				.add_degrees([1, 2, 3, 4, 5, 6, 5, 1], 1.0))
		S.CHROMATIC:
			var ex := _ex(skill, major, "Fi", "A note between fa and sol. It leans up to sol.")
			ex.notes = [{semis = 7, beats = 1.0}, {semis = 6, beats = 1.0}, {semis = 7, beats = 2.0}]
			out.append(ex)
			var ex2 := _ex(skill, major, "Te", "Just below ti. It leans down to la.")
			ex2.notes = [{semis = 12, beats = 1.0}, {semis = 10, beats = 1.0}, {semis = 9, beats = 2.0}]
			out.append(ex2)
		S.PHRASES, S.BACKING_TRACK, S.ENSEMBLE:
			pass  # built from songs; see CourseBuilder
	return out


static func _ex(skill: Skills.Id, key: MusicKey, title: String, prompt: String) -> Exercise:
	var e := Exercise.new()
	e.skill = skill
	e.key = key
	e.title = title
	e.prompt = prompt
	return e
