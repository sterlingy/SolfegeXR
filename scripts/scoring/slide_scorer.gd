class_name SlideScorer
extends RefCounted
## Scores the sliding exercises that come before single notes (design:
## "sirens and slides to land a single note"). Produces one NoteResult with
## its own encouraging wording, so it plugs into the same results flow.
##
## SIREN     no target: did the voice slide over a good stretch of pitch?
## SLIDE_TO  start anywhere, slide until on the target, then hold it there.
## FOLLOW    the target glides; how much of the time did the voice follow it?
## Pitch-class scoring as everywhere else: octave differences don't matter.

const SIREN_SPAN_GOOD := 7.0      ## semitones covered for a full "nice siren"
const SIREN_SPAN_MIN := 4.0
const HOLD_SECONDS := 0.8         ## SLIDE_TO: how long to stay on the note
const FOLLOW_GOOD := 0.6          ## FOLLOW: share of voiced time on the glide

var mode: Exercise.Mode
var targets: Array                ## relative seconds; FOLLOW legs may have midi_end
var tolerance_cents := 50.0
var min_confidence := 0.6
var min_rms := 0.0015
var latency := 0.0                ## same meaning as PhraseScorer.latency

var _points: Array[Vector2] = []  ## (time, midi), voiced frames only
var _frames := 0


func _init(p_mode: Exercise.Mode, p_targets: Array, settings: ScoringSettings = null) -> void:
	mode = p_mode
	targets = p_targets
	if settings:
		tolerance_cents = settings.tolerance_cents


func add_frame(f: PitchFrame) -> void:
	_frames += 1
	if f.confidence >= min_confidence and f.rms >= min_rms and f.frequency > 0.0:
		_points.append(Vector2(f.time - latency, MusicKey.hz_to_midi(f.frequency)))


func results() -> Array[NoteResult]:
	var r := NoteResult.new()
	r.target_midi = targets[0].midi if not targets.is_empty() else 0
	r.voiced_ratio = float(_points.size()) / maxi(1, _frames)
	if _points.size() < 20:
		r.verdict = NoteScorer.Verdict.NO_VOICE
		r.custom_feedback = "I didn't hear you that time. Try again a little louder."
		return [r] as Array[NoteResult]
	match mode:
		Exercise.Mode.SIREN:
			_score_siren(r)
		Exercise.Mode.SLIDE_TO:
			_score_slide_to(r)
		_:
			_score_follow(r)
	return [r] as Array[NoteResult]


## Pitch target (MIDI) at time t, or NAN outside every target.
func target_at(t: float) -> float:
	for tg in targets:
		if t >= tg.start and t <= tg.start + tg.duration:
			var end_midi: float = tg.get("midi_end", tg.midi)
			return lerpf(tg.midi, end_midi, (t - tg.start) / maxf(tg.duration, 0.001))
	return NAN


static func _pc_cents(midi: float, target: float) -> float:
	return (fposmod(midi - target + 6.0, 12.0) - 6.0) * 100.0


func _smoothed() -> Array[Vector2]:
	# Light moving average (~120 ms) so vibrato doesn't count against a slide.
	var out: Array[Vector2] = []
	for i in _points.size():
		var sum := 0.0
		var n := 0
		for j in range(maxi(0, i - 11), mini(_points.size(), i + 12)):
			if absf(_points[j].y - _points[i].y) < 3.0:
				sum += _points[j].y
				n += 1
		out.append(Vector2(_points[i].x, sum / n))
	return out


func _score_siren(r: NoteResult) -> void:
	var s := _smoothed()
	var ys: Array[float] = []
	for p in s:
		ys.append(p.y)
	ys.sort()
	# Ignore the extreme 5% at each end (stray readings).
	var lo := ys[int(ys.size() * 0.05)]
	var hi := ys[int(ys.size() * 0.95)]
	var span := hi - lo
	r.in_tune_ratio = clampf(span / SIREN_SPAN_GOOD, 0.0, 1.0)
	if span >= SIREN_SPAN_GOOD:
		r.verdict = NoteScorer.Verdict.LANDED
		r.custom_feedback = "Lovely siren! You slid over %d notes. That's your voice warming up." % roundi(span)
	elif span >= SIREN_SPAN_MIN:
		r.verdict = NoteScorer.Verdict.CLOSE
		r.custom_feedback = "Nice slide. Next time let it go a little higher and lower, like a siren."
	else:
		r.verdict = NoteScorer.Verdict.CLOSE
		r.custom_feedback = "That stayed in one place. Let your voice swoop up and down, like a siren."


func _score_slide_to(r: NoteResult) -> void:
	var target: float = targets[0].midi
	var s := _smoothed()
	var run_start := -1.0
	for p in s:
		if absf(_pc_cents(p.y, target)) <= tolerance_cents:
			if run_start < 0.0:
				run_start = p.x
			if p.x - run_start >= HOLD_SECONDS:
				r.verdict = NoteScorer.Verdict.LANDED
				r.onset_seconds = run_start
				r.in_tune_ratio = 1.0
				r.custom_feedback = "You found it, and held it! That took %.1f seconds." % maxf(0.0, run_start) \
					if run_start > 0.6 else "You found it right away, and held it!"
				return
		else:
			run_start = -1.0
	# Never held it: say which way to go, from the last second of singing.
	var tail: Array[float] = []
	for p in s:
		if p.x >= s[-1].x - 1.0:
			tail.append(_pc_cents(p.y, target))
	tail.sort()
	var c: float = tail[tail.size() / 2]
	r.median_cents = c
	r.verdict = NoteScorer.Verdict.LOW if c < 0 else NoteScorer.Verdict.HIGH
	if absf(c) <= tolerance_cents * 2.0:
		r.verdict = NoteScorer.Verdict.CLOSE
		r.custom_feedback = "So close! You touched it. Try to stay there a moment longer."
	else:
		r.custom_feedback = "Keep sliding %s until the line turns green, then stay there." % ("up" if c < 0 else "down")


func _score_follow(r: NoteResult) -> void:
	var on := 0
	var counted := 0
	for p in _smoothed():
		var t := target_at(p.x)
		if is_nan(t):
			continue
		counted += 1
		if absf(_pc_cents(p.y, t)) <= tolerance_cents * 1.2:
			on += 1
	r.in_tune_ratio = float(on) / maxi(1, counted)
	if counted == 0:
		r.verdict = NoteScorer.Verdict.NO_VOICE
		r.custom_feedback = "Start singing when the slide starts, and follow it."
	elif r.in_tune_ratio >= FOLLOW_GOOD:
		r.verdict = NoteScorer.Verdict.LANDED
		r.custom_feedback = "You followed the slide! %d%% of the way on the line." % roundi(r.in_tune_ratio * 100)
	else:
		r.verdict = NoteScorer.Verdict.CLOSE
		r.custom_feedback = "You were with it %d%% of the way. Try it again slowly." % roundi(r.in_tune_ratio * 100)
