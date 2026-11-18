class_name PitchTrace
extends Control
## Live pitch line scrolling over horizontal solfège lanes.
##
## Custom drawing happens in _draw() (like a UMG widget's OnPaint); call
## queue_redraw() to request a repaint. Feed it frames with push_frame().

signal feedback_changed(text: String)

@export var history_seconds := 4.0
@export var keep_seconds := 20.0          ## points kept (so a finished attempt can be zoomed out)
@export var now_fraction := 0.78           ## x position of "now", 0..1 of width
@export var span_semitones := 20.0         ## visible range, centered on center_midi
@export var tolerance_cents := 50.0        ## shaded band around each lane
@export var min_confidence := 0.6
@export var min_rms := 0.0015
@export var smoothing_seconds := 0.03      ## light smoothing; vibrato stays visible

@export_group("Colors")
@export var background := Color("1b1d2a")
@export var lane_color := Color(1, 1, 1, 0.16)
@export var do_lane_color := Color("ffd27a", 0.45)
@export var band_color := Color(1, 1, 1, 0.045)
@export var label_color := Color(1, 1, 1, 0.75)
@export var line_color := Color("7fd3ff")
@export var line_on_target := Color("8cf0a6")
@export var folded_color := Color("7fd3ff", 0.35)
@export var target_color := Color("ffd27a", 0.30)
@export var target_border := Color("ffd27a", 0.75)
@export var lyric_color := Color(1, 1, 1, 0.85)

var key := MusicKey.new()
var center_midi := 57.0

# History of points: Vector3(time, midi_displayed, flags). midi is NAN for gaps.
# flags: 1 = on target, 2 = folded into view by octaves.
var _points: Array[Vector3] = []
var _smoothed := NAN
var _last_time := 0.0
var _now := 0.0
var _font: Font
var _feedback := ""
var _targets: Array = []   # {midi, start, duration} in the trace clock
var show_feedback := true


func _ready() -> void:
	_font = get_theme_default_font()
	clip_contents = true


func set_key(k: MusicKey) -> void:
	key = k
	queue_redraw()


func clear() -> void:
	_points.clear()
	_smoothed = NAN
	queue_redraw()


## Show target notes. `origin` is the trace-clock time of target start 0.
func set_targets(targets: Array, origin: float) -> void:
	_targets.clear()
	for t in targets:
		var tt := {midi = t.midi, start = origin + t.start, duration = t.duration, lyric = t.get("lyric", "")}
		if t.has("midi_end"):
			tt.midi_end = t.midi_end
		_targets.append(tt)
	queue_redraw()


func clear_targets() -> void:
	_targets.clear()
	queue_redraw()


## Frame the view around a note range (with a little margin).
func fit_range(low: int, high: int) -> void:
	span_semitones = maxf(12.0, high - low + 5.0)
	center_midi = (low + high) / 2.0
	queue_redraw()


func low_midi() -> float:
	return center_midi - span_semitones * 0.5


func high_midi() -> float:
	return center_midi + span_semitones * 0.5


## Advance the scroll clock even without new frames (keeps scrolling smooth).
func set_now(t: float) -> void:
	_now = maxf(_now, t)
	var cutoff := _now - maxf(history_seconds, keep_seconds) - 0.5
	while _points.size() > 0 and _points[0].x < cutoff:
		_points.pop_front()
	queue_redraw()


func push_frame(f: PitchFrame) -> void:
	_now = maxf(_now, f.time)
	var voiced := f.confidence >= min_confidence and f.rms >= min_rms and f.frequency > 0.0
	if not voiced:
		if not is_nan(_smoothed):
			_points.append(Vector3(f.time, NAN, 0))
		_smoothed = NAN
		_set_feedback("")
		_last_time = f.time
		return

	var midi := MusicKey.hz_to_midi(f.frequency)
	# Exponential smoothing in the pitch (semitone) domain.
	if is_nan(_smoothed) or f.time - _last_time > 0.1:
		_smoothed = midi
	else:
		var a := 1.0 - exp(-(f.time - _last_time) / maxf(smoothing_seconds, 0.001))
		_smoothed = lerpf(_smoothed, midi, a)
	_last_time = f.time

	# Octave errors are forgiven: fold the pitch into the visible range.
	var shown := _smoothed
	var flags := 0
	while shown < low_midi():
		shown += 12.0
		flags = 2
	while shown > high_midi():
		shown -= 12.0
		flags = 2

	var near := _nearest_lane(shown)
	var cents := (shown - near) * 100.0
	if absf(cents) <= tolerance_cents:
		flags |= 1
	_points.append(Vector3(f.time, shown, flags))
	_update_feedback(shown, near, cents, flags & 2 != 0)


## Nearest in-key note (as MIDI) to a pitch.
func _nearest_lane(midi: float) -> int:
	var best := roundi(midi)
	var best_dist := INF
	for cand in range(floori(midi) - 2, ceili(midi) + 3):
		if key.is_in_key(cand) and absf(cand - midi) < best_dist:
			best = cand
			best_dist = absf(cand - midi)
	return best


func _update_feedback(shown: float, lane: int, cents: float, folded: bool) -> void:
	var nearest_semi := roundi(shown)
	var semi_cents := (shown - nearest_semi) * 100.0
	if not key.is_in_key(nearest_semi) and absf(semi_cents) < 30.0:
		var syl := key.syllable_of(nearest_semi)
		_set_feedback(syl if syl != "" else "outside the scale")
		return
	var syl := key.syllable_of(lane)
	var text: String
	if absf(cents) <= tolerance_cents * 0.4:
		text = "%s — right there" % syl
	elif absf(cents) <= tolerance_cents:
		text = "%s — %s" % [syl, "nearly, a touch higher" if cents < 0 else "nearly, a touch lower"]
	else:
		text = "%s — %s" % [syl, "a little low, slide up" if cents < 0 else "a little high, ease down"]
	if folded:
		text += "  (different octave, that's fine)"
	_set_feedback(text)


func _set_feedback(text: String) -> void:
	if not show_feedback:
		return
	if text != _feedback:
		_feedback = text
		feedback_changed.emit(text)


func _y_of(midi: float) -> float:
	return remap(midi, low_midi(), high_midi(), size.y, 0.0)


func _x_of(t: float) -> float:
	var now_x := size.x * now_fraction
	return now_x - (_now - t) / history_seconds * now_x


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background)
	var font_size := int(clampf(size.y / span_semitones * 0.55, 22.0, 44.0))
	var band_h := absf(_y_of(0.0) - _y_of(tolerance_cents / 100.0))

	# Lanes: every in-key note in view; do lanes highlighted.
	for m in range(ceili(low_midi()), floori(high_midi()) + 1):
		var y := _y_of(m)
		if key.is_in_key(m):
			var is_home := key.semitone_of(m) == 0
			draw_rect(Rect2(0, y - band_h, size.x, band_h * 2.0), band_color)
			draw_line(Vector2(0, y), Vector2(size.x, y),
					do_lane_color if is_home else lane_color, 3.0 if is_home else 1.5)
			draw_string(_font, Vector2(16, y - 6), key.syllable_of(m),
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
		elif key.chromatic_enabled:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(lane_color, 0.06), 1.0)

	# Target notes: bars on their lanes, labeled with the syllable.
	for t in _targets:
		var x0 := _x_of(t.start)
		var x1 := _x_of(t.start + t.duration)
		if x1 < 0.0 or x0 > size.x:
			continue
		var y := _y_of(t.midi)
		if t.has("midi_end"):
			# A glide: a sloped band from this pitch to the next.
			var y1 := _y_of(t.midi_end)
			var band := PackedVector2Array([Vector2(x0, y - band_h), Vector2(x1, y1 - band_h),
				Vector2(x1, y1 + band_h), Vector2(x0, y + band_h)])
			draw_colored_polygon(band, target_color)
			band.append(band[0])
			draw_polyline(band, target_border, 2.0, true)
			continue
		var r := Rect2(x0, y - band_h, maxf(4.0, x1 - x0 - 4.0), band_h * 2.0)
		draw_rect(r, target_color)
		draw_rect(r, target_border, false, 2.0)
		var syl := key.syllable_of(t.midi)
		if syl != "" and x1 - x0 > font_size:
			draw_string(_font, Vector2(x0 + 8, y + font_size * 0.35), syl,
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size * 0.8), Color(1, 1, 1, 0.9))
		# The word sung on this note, just under its bar.
		if t.lyric != "":
			draw_string(_font, Vector2(x0 + 4, y + band_h + font_size * 0.9), t.lyric,
					HORIZONTAL_ALIGNMENT_LEFT, maxf(x1 - x0, font_size * 3.0), int(font_size * 0.75), lyric_color)

	# "Now" marker.
	var now_x := size.x * now_fraction
	draw_line(Vector2(now_x, 0), Vector2(now_x, size.y), Color(1, 1, 1, 0.12), 2.0)

	# Trace: break at gaps, at large jumps (octave folds) and at color changes.
	var seg := PackedVector2Array()
	var seg_color := line_color
	for i in _points.size():
		var p := _points[i]
		var col := _color_for(int(p.z))
		var breaks := is_nan(p.y)
		if not breaks and seg.size() > 0:
			var prev := _points[i - 1]
			breaks = is_nan(prev.y) or absf(prev.y - p.y) > 6.0 or col != seg_color
		if breaks:
			_flush(seg, seg_color)
			# Start the new segment at the previous point to keep the line continuous on color change.
			seg = PackedVector2Array()
			if not is_nan(p.y) and i > 0 and not is_nan(_points[i - 1].y) \
					and absf(_points[i - 1].y - p.y) <= 6.0:
				seg.append(Vector2(_x_of(_points[i - 1].x), _y_of(_points[i - 1].y)))
		if not is_nan(p.y):
			seg.append(Vector2(_x_of(p.x), _y_of(p.y)))
			seg_color = col
	_flush(seg, seg_color)

	# Current-pitch dot.
	if _points.size() > 0:
		var last := _points[-1]
		if not is_nan(last.y) and _now - last.x < 0.15:
			var pos := Vector2(_x_of(last.x), _y_of(last.y))
			draw_circle(pos, 16.0, _color_for(int(last.z)))
			draw_circle(pos, 7.0, background)


func _flush(seg: PackedVector2Array, col: Color) -> void:
	if seg.size() >= 2:
		draw_polyline(seg, col, 6.0, true)


func _color_for(flags: int) -> Color:
	if flags & 2:
		return folded_color
	return line_on_target if flags & 1 else line_color
