class_name PracticeSession
extends RefCounted
## Runs one exercise: key setup (cadence + drone), listen, count-in, sing,
## score. No UI; the practice screen drives it each frame and shows its state.
##
## Clocks: the synth schedules in engine time; pitch frames arrive in the
## pitch source's own clock. At the start of SING we note both, and score
## frames by time since that moment.

signal phase_changed(phase: Phase)
signal finished(results: Array[NoteResult])

enum Phase { IDLE, CADENCE, LISTEN, COUNT_IN, SING, RESULT }

const COUNT_IN_SECONDS := 1.2   ## sirens and slides
const COUNTDOWN_SECONDS := 3.0  ## before the first note of a melody: "3, 2, 1"
const TAIL_SECONDS := 0.4

var exercise: Exercise
var profile: LearnerProfile
var tempo_scale := 1.0
var play_cadence := true
var metronome := false          ## click the beat (count-in and singing); from the profile
var phase := Phase.IDLE
var targets: Array = []         ## what's scored and drawn (relative seconds, learner's voice)
var reference: Array = []       ## what the synth plays as the example
var scorer: RefCounted          ## PhraseScorer (notes) or SlideScorer (sirens and slides)
var results: Array[NoteResult] = []
var sing_origin_source := 0.0   ## pitch-source time when SING started

var _engine: SynthEngine
var _phase_end := 0.0           ## engine time
var _sing_start_engine := 0.0


func _init(p_exercise: Exercise, p_profile: LearnerProfile, p_tempo_scale := -1.0) -> void:
	exercise = p_exercise
	profile = p_profile
	tempo_scale = p_tempo_scale if p_tempo_scale > 0.0 else profile.tempo_scale
	metronome = profile.metronome
	reference = exercise.realize_for(profile, tempo_scale)
	match exercise.mode:
		Exercise.Mode.SIREN:
			targets = []  # free sliding: nothing to aim at
		Exercise.Mode.SLIDE_TO:
			# One target held for the whole singing window.
			targets = [{midi = reference[0].midi, start = 0.0, duration = exercise.sing_seconds}]
		_:
			targets = reference


func home_tonic() -> int:
	return exercise.fixed_base if exercise.fixed_base >= 0 else profile.home_tonic(exercise.key.tonic_pc)


## The tonic note in the learner's octave (for drone and cadence).
func drone_tonic() -> int:
	var t := profile.home_tonic(exercise.key.tonic_pc)
	return t


func length_seconds() -> float:
	if exercise.mode in [Exercise.Mode.SIREN, Exercise.Mode.SLIDE_TO]:
		return exercise.sing_seconds
	var end := 0.0
	for t in targets:
		end = maxf(end, t.start + t.duration)
	return end


func start(engine: SynthEngine) -> void:
	_engine = engine
	if exercise.drone:
		engine.set_drone(drone_tonic())
	if play_cadence and exercise.cadence_first:
		_enter(Phase.CADENCE, engine.cadence(exercise.key, drone_tonic(), 0.75 / tempo_scale))
	else:
		_after_cadence()


## Call every frame. `source_now` is the pitch source clock.
func update(frames: Array[PitchFrame], source_now: float) -> void:
	if phase == Phase.IDLE or phase == Phase.RESULT:
		return
	if phase == Phase.SING:
		for f in frames:
			var rel := PitchFrame.new(f.time - sing_origin_source, f.frequency, f.confidence, f.rms)
			scorer.add_frame(rel)
	if _engine.time() < _phase_end:
		if phase == Phase.COUNT_IN:
			# Track the source clock right up to the downbeat.
			sing_origin_source = source_now + (_phase_end - _engine.time())
		return
	match phase:
		Phase.CADENCE:
			_after_cadence()
		Phase.LISTEN:
			_enter(Phase.COUNT_IN, count_in_seconds())
		Phase.COUNT_IN:
			_begin_sing(source_now)
		Phase.SING:
			_finish()


func stop() -> void:
	if _engine:
		_engine.release_all()
	phase = Phase.IDLE


## Melodies get a 3-second countdown; sirens and slides a short pause.
func count_in_seconds() -> float:
	return COUNTDOWN_SECONDS if exercise.mode == Exercise.Mode.NOTES else COUNT_IN_SECONDS


## Seconds left before the first note (during COUNT_IN), else 0.
func count_in_left() -> float:
	if phase != Phase.COUNT_IN or _engine == null:
		return 0.0
	return maxf(0.0, _phase_end - _engine.time())


## One beat at the practice tempo, in seconds.
func beat_seconds() -> float:
	return 60.0 / maxf(1.0, exercise.tempo_bpm) / tempo_scale


## Beat times relative to the downbeat (first note = 0) from `from` up to the
## end, on the song's own beat grid (pickups included). Each is [time, accent].
func beat_times(from: float) -> Array:
	var beat := beat_seconds()
	var beats := maxi(1, roundi(exercise.beats_per_measure))
	var first_bar := 0.0
	if exercise.bar_offset_beats > 0.0:
		first_bar = exercise.bar_offset_beats * beat - beats * beat
	var out := []
	var k := ceili((from - first_bar) / beat - 0.001)
	while true:
		var t := first_bar + k * beat
		if t >= length_seconds() - 0.01:
			break
		out.append([t, posmod(k, beats) == 0])
		k += 1
	return out


## Metronome ticks from the start of the countdown to the last note: a higher
## tick on the first beat of each bar. Short and unpitched to the detector
## (far above any voice), so they are allowed without headphones too.
func _schedule_clicks(downbeat: float) -> void:
	for b in beat_times(-count_in_seconds() + 0.05):
		var accent: bool = b[1]
		_engine.note(96 if accent else 91, downbeat + b[0], 0.012, SynthEngine.Kind.CLICK, 0.22 if accent else 0.15)


## Seconds since SING began (source clock), for drawing targets.
func sing_elapsed(source_now: float) -> float:
	return source_now - sing_origin_source


## Without headphones the mic hears the speakers, so nothing may play while the
## learner sings: the drone stops and sing-along references play first instead.
func speakers_only() -> bool:
	return not profile.has_headphones


func _after_cadence() -> void:
	if exercise.reference == Exercise.Reference.BEFORE 			or (exercise.reference == Exercise.Reference.ALONG and speakers_only()):
		var len := _engine.sequence(reference, 1.0, _engine.time() + 0.1)
		_enter(Phase.LISTEN, len + 0.3)
	else:
		_enter(Phase.COUNT_IN, count_in_seconds())


func _begin_sing(source_now: float) -> void:
	sing_origin_source = source_now
	_sing_start_engine = _engine.time()
	if exercise.mode == Exercise.Mode.NOTES:
		scorer = PhraseScorer.new(targets, exercise.key, profile.scoring_settings())
	else:
		scorer = SlideScorer.new(exercise.mode, targets, profile.scoring_settings())
	scorer.latency = 0.0
	if speakers_only():
		_engine.set_drone(-1)
		_enter(Phase.SING, length_seconds() + TAIL_SECONDS)
		return
	if exercise.reference == Exercise.Reference.ALONG:
		_play_guide()
	if exercise.accompaniment:
		_play_chords()
	for p in exercise.parts:
		for t in p.targets:
			_engine.note(t.midi, _sing_start_engine + t.start / tempo_scale, t.duration / tempo_scale * 0.97,
				SynthEngine.Kind.PAD, 0.14)
	_enter(Phase.SING, length_seconds() + TAIL_SECONDS)


## Guide voice; for the "fading guide" ensemble stage it gets quieter and stops.
func _play_guide() -> void:
	var fade := exercise.guide_fade
	for i in targets.size():
		var t: Dictionary = targets[i]
		var g := 0.22
		if fade:
			g *= clampf(1.0 - float(i) / maxf(1.0, targets.size() * 0.6), 0.0, 1.0)
		if g > 0.0:
			_engine.note(t.midi, _sing_start_engine + t.start, t.duration * 0.97, SynthEngine.Kind.VOICE, g)


## Backing track: a chord per bar that fits the melody (Harmonizer), played
## as bass on the strong beats and chords on the others ("oom-pah").
func _play_chords() -> void:
	var tonic := drone_tonic()
	var beat := 60.0 / exercise.tempo_bpm / tempo_scale
	var bpm := maxf(1.0, exercise.beats_per_measure)
	var bar := bpm * beat
	var first_bar := 0.0
	if exercise.bar_offset_beats > 0.0:
		first_bar = exercise.bar_offset_beats * beat - bar
	var beats := roundi(bpm)
	for c in Harmonizer.chords_for(targets, exercise.key, bar, length_seconds(), first_bar):
		var root_semi: int = c.tones[0]
		var fifth_semi: int = c.tones[2]
		for b in beats:
			var t: float = c.start + b * beat
			if t < -0.001 or t >= length_seconds():
				continue
			var strong := b == 0 or (beats == 4 and b == 2)
			if strong:
				var bass_semi := root_semi if b == 0 else fifth_semi
				_engine.note(tonic - 12 + _fold(bass_semi, -2), _sing_start_engine + t, beat * 0.9,
					SynthEngine.Kind.PAD, 0.13)
			else:
				for semi in c.tones:
					_engine.note(tonic + _fold(semi, 2), _sing_start_engine + t, beat * 0.6,
						SynthEngine.Kind.PAD, 0.06)


## Fold a pitch class into an octave window starting `low` semitones above the tonic.
static func _fold(semi: int, low: int) -> int:
	var s := semi
	while s >= low + 12:
		s -= 12
	while s < low:
		s += 12
	return s


func _finish() -> void:
	_engine.set_drone(-1)
	results = scorer.results()
	if exercise.record:
		profile.record(exercise.skill, results)
		profile.save()
	_enter(Phase.RESULT, 0.0)
	finished.emit(results)


func _enter(p: Phase, seconds: float) -> void:
	# Fade the drone during the count-in so its release is over by the downbeat.
	if p == Phase.COUNT_IN and speakers_only():
		_engine.set_drone(-1)
	phase = p
	_phase_end = _engine.time() + seconds
	if p == Phase.COUNT_IN and metronome and exercise.mode == Exercise.Mode.NOTES:
		_schedule_clicks(_phase_end)
	phase_changed.emit(p)


## A friendly one-line summary of the results.
static func summary(res: Array[NoteResult], key: MusicKey) -> String:
	var landed := 0
	var voiced := 0
	var first_miss: NoteResult = null
	for r in res:
		if r.verdict != NoteScorer.Verdict.NO_VOICE:
			voiced += 1
		if r.landed():
			landed += 1
		elif first_miss == null and r.verdict != NoteScorer.Verdict.NO_VOICE:
			first_miss = r
	if res.size() == 1 and res[0].custom_feedback != "":
		return res[0].custom_feedback
	if voiced == 0:
		return "I didn't hear you that time. Try again a little louder."
	if landed == res.size():
		return "You landed every note!" if res.size() > 1 else "You landed it!"
	var head := "You landed %d of %d notes." % [landed, res.size()]
	if first_miss:
		head += " " + first_miss.feedback(key)
	return head
