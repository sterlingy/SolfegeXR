class_name NoteScorer
extends RefCounted
## Scores one sung note against a target, incrementally (live) or after the fact.
##
## Rules (from the design):
## - Tolerance in cents; ~±50 for beginners, tightened as skill grows.
## - Vibrato is smoothed out (moving average over about one vibrato cycle).
## - The scoop at the start of a note is forgiven (onset grace period).
## - Scored by pitch class: octave errors are forgiven, reported as a range hint.
## - Gradual drift is told apart from singing a different scale degree.

enum Verdict { NO_VOICE, LANDED, CLOSE, LOW, HIGH, DRIFTED_LOW, DRIFTED_HIGH, WRONG_DEGREE }

## Settings (ScoringSettings keeps the learner-level defaults).
var tolerance_cents := 50.0
var onset_grace := 0.15          ## seconds ignored at note start (scoop)
var onset_grace_fraction := 0.25 ## ...or this fraction of the note, whichever is smaller
var smoothing_window := 0.18     ## seconds; ~one cycle of 5.5 Hz vibrato
var min_confidence := 0.6
var min_rms := 0.0015
var landed_ratio := 0.7          ## share of scored time in tolerance to count as landed
var max_spread_cents := 150.0    ## median deviation above this = not a steady sung note

var target_midi: int
var start_time: float
var duration: float
var key: MusicKey

# Raw voiced samples: Vector2(time, midi)
var _raw: Array[Vector2] = []
var _total_frames := 0


func _init(p_target_midi: int, p_start: float, p_duration: float, p_key: MusicKey = null) -> void:
	target_midi = p_target_midi
	start_time = p_start
	duration = p_duration
	key = p_key


func add_frame(f: PitchFrame) -> void:
	if f.time < start_time or f.time > start_time + duration:
		return
	_total_frames += 1
	if f.confidence >= min_confidence and f.rms >= min_rms and f.frequency > 0.0:
		_raw.append(Vector2(f.time, MusicKey.hz_to_midi(f.frequency)))


## Pitch-class distance from the target in cents, folded into [-600, 600).
func folded_cents(midi: float) -> float:
	return (fposmod(midi - target_midi + 6.0, 12.0) - 6.0) * 100.0


func result() -> NoteResult:
	var r := NoteResult.new()
	r.target_midi = target_midi
	var grace := minf(onset_grace, duration * onset_grace_fraction)
	var scored_start := start_time + grace

	var smooth := _smoothed()
	# Onset: first time the (smoothed) pitch is within tolerance.
	for p in smooth:
		if absf(folded_cents(p.y)) <= tolerance_cents:
			r.onset_seconds = p.x - start_time
			break

	var scored: Array[Vector2] = []
	for p in smooth:
		if p.x >= scored_start:
			scored.append(p)
	var expected := maxf(1.0, _total_frames * (duration - grace) / maxf(duration, 0.001))
	r.voiced_ratio = clampf(scored.size() / expected, 0.0, 1.0)
	if scored.size() < 3 or r.voiced_ratio < 0.3:
		r.verdict = Verdict.NO_VOICE
		return r

	var cents: Array[float] = []
	var octave_votes := {}
	var in_tol := 0
	for p in scored:
		var c := folded_cents(p.y)
		cents.append(c)
		if absf(c) <= tolerance_cents:
			in_tol += 1
		var octave := roundi((p.y - target_midi - c / 100.0) / 12.0)
		octave_votes[octave] = octave_votes.get(octave, 0) + 1
	r.in_tune_ratio = float(in_tol) / scored.size()
	r.median_cents = _median(cents)
	# Background noise and speech jump around; a sung note (even with vibrato
	# or drift) stays put. Unsteady "notes" aren't judged at all.
	var spread: Array[float] = []
	for c in cents:
		spread.append(absf(c - r.median_cents))
	if _median(spread) > max_spread_cents:
		r.verdict = Verdict.NO_VOICE
		return r
	r.octave_offset = _argmax(octave_votes)

	# Drift: least-squares slope of cents over time, and where it started.
	r.drift_cents_per_second = _slope(scored, cents)
	var n_head := maxi(3, scored.size() / 5)
	var head := cents.slice(0, n_head)
	var tail := cents.slice(cents.size() - n_head)
	var head_c := _median(head)
	var tail_c := _median(tail)
	var drift_total := tail_c - head_c

	if r.in_tune_ratio >= landed_ratio:
		r.verdict = Verdict.LANDED
	elif absf(head_c) <= tolerance_cents and absf(drift_total) > tolerance_cents * 0.8:
		r.verdict = Verdict.DRIFTED_LOW if drift_total < 0 else Verdict.DRIFTED_HIGH
	else:
		var wrong := _wrong_degree(r.median_cents)
		if wrong != -1:
			r.verdict = Verdict.WRONG_DEGREE
			r.sung_midi = wrong
		elif absf(r.median_cents) <= tolerance_cents * 1.5:
			r.verdict = Verdict.CLOSE
		else:
			r.verdict = Verdict.LOW if r.median_cents < 0 else Verdict.HIGH
	return r


## If the sung pitch sits on a different scale note, return that note (as MIDI
## near the target), else -1. Needs a key; without one, uses any semitone.
func _wrong_degree(median_cents: float) -> int:
	if absf(median_cents) <= tolerance_cents:
		return -1
	var sung := target_midi + median_cents / 100.0
	var nearest := roundi(sung)
	# A half-step neighbour is treated as "low/high" (slide), not a different
	# degree: for beginners that's almost always being off, and sliding fixes it.
	if absi(nearest - target_midi) < 2 or absf(sung - nearest) * 100.0 > 40.0:
		return -1
	if key != null and not key.is_in_key(nearest):
		return -1
	return nearest


func _smoothed() -> Array[Vector2]:
	# Moving average in a centered time window. Uses unfolded midi, but resets
	# across octave jumps so averaging never blends two octaves.
	var out: Array[Vector2] = []
	var half := smoothing_window * 0.5
	var lo := 0
	var hi := 0
	var sum := 0.0
	for i in _raw.size():
		var t := _raw[i].x
		while hi < _raw.size() and _raw[hi].x <= t + half:
			sum += _raw[hi].y
			hi += 1
		while _raw[lo].x < t - half:
			sum -= _raw[lo].y
			lo += 1
		var avg := sum / (hi - lo)
		if absf(avg - _raw[i].y) > 3.0:
			avg = _raw[i].y  # octave/jump inside window: don't blend
		out.append(Vector2(t, avg))
	return out


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return NAN
	var s := values.duplicate()
	s.sort()
	return s[s.size() / 2]


static func _argmax(votes: Dictionary) -> int:
	var best := 0
	var best_n := -1
	for k in votes:
		if votes[k] > best_n:
			best = k
			best_n = votes[k]
	return best


static func _slope(points: Array[Vector2], ys: Array[float]) -> float:
	var n := points.size()
	if n < 2:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for i in n:
		mx += points[i].x
		my += ys[i]
	mx /= n
	my /= n
	var num := 0.0
	var den := 0.0
	for i in n:
		num += (points[i].x - mx) * (ys[i] - my)
		den += (points[i].x - mx) * (points[i].x - mx)
	return num / den if den > 0.0 else 0.0
