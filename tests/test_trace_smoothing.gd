extends TestCase
## The steady voice line (PitchTrace.steady): tiny shakes in a held note are
## smoothed away, but note changes and vibrato still show promptly.

const DT := 0.0053   ## the web detector's frame spacing


func _trace(steady: bool) -> PitchTrace:
	var t := PitchTrace.new()
	t.steady = steady
	t.center_midi = 60.0
	return t


## Feed `seconds` of pitch from `f(time)`; returns [time, shown] pairs.
func _sing(t: PitchTrace, from: float, seconds: float, f: Callable) -> Array:
	var out := []
	var n := int(seconds / DT)
	for i in n:
		var time := from + i * DT
		t.push_frame(PitchFrame.new(time, MusicKey.midi_to_hz(f.call(time)), 0.95, 0.1))
		out.append([time, t._points[-1].y])
	return out


## Deterministic shake: ±`cents` around `midi`, changing every frame.
func _shaky(midi: float, cents: float) -> Callable:
	var seed := [12345]
	return func(_time: float) -> float:
		seed[0] = (seed[0] * 1103515245 + 12345) % 2147483648
		return midi + (float(seed[0]) / 2147483648.0 * 2.0 - 1.0) * cents / 100.0


func _spread(points: Array, after: float) -> float:
	var lo := INF
	var hi := -INF
	for p in points:
		if p[0] >= after:
			lo = minf(lo, p[1])
			hi = maxf(hi, p[1])
	return (hi - lo) * 100.0


func test_steady_line_removes_most_of_the_shake() -> void:
	# The singer's pitch jumps around within ±20 cents (a 40 cent band).
	var light := _spread(_sing(_trace(false), 0.0, 1.0, _shaky(60.0, 20.0)), 0.3)
	var s := _spread(_sing(_trace(true), 0.0, 1.0, _shaky(60.0, 20.0)), 0.3)
	assert_true(s < 12.0, "steady line wobbles %.1f cents (light smoothing: %.1f)" % [s, light])


func test_steady_line_follows_a_note_change_quickly() -> void:
	var t := _trace(true)
	_sing(t, 0.0, 0.5, func(_x): return 60.0)
	var pts := _sing(t, 0.5, 0.5, func(_x): return 62.0)
	var reached := -1.0
	for p in pts:
		if absf(p[1] - 62.0) < 0.15:
			reached = p[0] - 0.5
			break
	assert_true(reached >= 0.0 and reached < 0.15, "within 15 cents after %.3f s" % reached)


func test_steady_line_keeps_vibrato_visible() -> void:
	var t := _trace(true)
	var pts := _sing(t, 0.0, 1.5, func(x): return 60.0 + 0.5 * sin(TAU * 5.5 * x))
	var s := _spread(pts, 0.5)
	assert_true(s > 50.0, "a ±50 cent vibrato still swings %.0f cents" % s)


func test_setting_is_saved() -> void:
	var p := LearnerProfile.new()
	assert_true(p.smooth_trace, "on by default")
	p.smooth_trace = false
	var back := LearnerProfile.from_dict(p.to_dict())
	assert_false(back.smooth_trace)
