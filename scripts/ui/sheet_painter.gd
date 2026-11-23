class_name SheetPainter
extends RefCounted
## Draws a Notation layout as a scrolling staff inside a PitchTrace (the sheet
## music view): paper, staff, clef, key and time signature, notes, rests,
## beams, ties, solfège and lyrics. The trace keeps drawing the sung line on top.
##
## Units: `s` is one staff space in pixels; a staff step is s / 2.

const PAPER := Color("f6f1e4")
const INK := Color("23252f")
const INK_SOFT := Color("23252f", 0.55)
const LINE := Color("1c78c8")
const LINE_ON := Color("1e9b53")
const NOW := Color("e07a10")
## Note colors after singing: landed, nearly, keep going, not heard. Never red.
const LANDED := Color("1e9b53")
const NEARLY := Color("c98a00")
const KEEP_GOING := Color("6a5acd")
const UNHEARD := Color("23252f", 0.3)

const G_CLEF := 0x1D11E
const F_CLEF := 0x1D122
const SHARP := 0x266F
const FLAT := 0x266D
const NATURAL := 0x266E
const RESTS := {4.0: 0x1D13B, 3.0: 0x1D13C, 2.0: 0x1D13C, 1.5: 0x1D13D, 1.0: 0x1D13D, 0.75: 0x1D13E,
	0.5: 0x1D13E, 0.25: 0x1D13F}
## Glyph outlines in font units (Noto Music, 1000 per em): x_min, y_min, x_max, y_max (y up).
const BOUNDS := {
	0x1D11E: [50, -398, 661, 1334], 0x1D122: [50, 101, 742, 900],
	0x1D13B: [50, 378, 733, 512], 0x1D13C: [50, 244, 733, 378], 0x1D13D: [51, 123, 307, 878],
	0x1D13E: [50, 269, 312, 730], 0x1D13F: [50, 147, 380, 852],
	0x266F: [50, -247, 275, 509], 0x266D: [50, -55, 249, 615], 0x266E: [50, -221, 226, 486],
}

var n: Dictionary = {}           ## Notation.build() result; empty = no score
var results: Array = []          ## NoteResult per sung note, after an attempt
var header := ""
var show_syllables := true
var spb := 0.5                   ## seconds per beat at the practice tempo

var s := 20.0
var panel_w := 0.0
var px_per_beat := 100.0
## After an attempt: true when the whole attempt fits at a readable size;
## otherwise the staff stays full size and can be dragged back.
var fits_whole := false
var _top_step := 0.0
var _top_y := 0.0
var _anchor := PackedFloat32Array()   # MIDI -> staff step for in-key (and written) notes, NAN otherwise
var _font: Font
var _text_font: Font


func _init() -> void:
	_font = load("res://assets/fonts/NotoMusic-Regular.ttf")   # UI.MUSIC_FONT_PATH, without the UI dependency


func active() -> bool:
	return not n.is_empty()


func set_notation(notation: Dictionary, key: MusicKey, seconds_per_beat: float) -> void:
	n = notation
	spb = seconds_per_beat
	results = []
	_anchor.resize(128)
	for m in 128:
		_anchor[m] = NAN
		if not n.is_empty() and (key.is_in_key(m) or n.chromatic.has(m)):
			_anchor[m] = Notation.step_of(m, n.fifths)


## Staff step of any pitch (fractional between notes). Same result as
## Notation.pitch_step, from a table, because it runs for every trace point.
func step_of_midi(midi: float) -> float:
	var lo := clampi(floori(midi), 1, 126)
	while lo > 0 and is_nan(_anchor[lo]):
		lo -= 1
	var hi := clampi(lo + 1, 1, 127)
	while hi < 127 and is_nan(_anchor[hi]):
		hi += 1
	var a := _anchor[lo]
	var b := _anchor[hi]
	if b <= a:
		return a
	return lerpf(a, b, (midi - lo) / float(hi - lo))


func y_of_step(step: float) -> float:
	return _top_y + (_top_step - step) * s * 0.5


func y_of_midi(midi: float) -> float:
	return y_of_step(step_of_midi(midi))


func bottom() -> int:
	return n.bottom_step


## Fit the staff, the notes and the singer's visible range into the control.
func layout(tr: PitchTrace) -> void:
	_text_font = tr.get_theme_default_font()
	var lo := minf(n.low_step, step_of_midi(tr.low_midi()))
	var hi := maxf(n.high_step, step_of_midi(tr.high_midi()))
	var text_steps := 8.0 if show_syllables else 5.0
	var total := (hi - lo) + 4.0 + text_steps + 3.0
	s = clampf(minf(2.0 * tr.size.y / total, tr.size.x / 26.0), 12.0, 64.0)
	_set_panel()
	fits_whole = false
	if tr.zoomed_out:
		# Shrink to show the whole attempt, but only while it stays readable.
		var normal := s
		var beats := maxf(1.0, tr.history_seconds / spb)
		for i in 3:
			var per_beat := (tr.size.x * tr.now_fraction - panel_w) / beats
			if per_beat < 3.0 * s:
				s = maxf(8.0, per_beat / 3.0)
				_set_panel()
		fits_whole = s >= normal * 0.7
		if not fits_whole:
			s = normal
			_set_panel()
	var block := total * s * 0.5
	_top_step = hi
	_top_y = maxf(0.0, (tr.size.y - block) * 0.5) + 5.0 * s * 0.5
	px_per_beat = clampf(tr.size.x * 0.14, 4.0 * s, 9.0 * s)


func _set_panel() -> void:
	panel_w = s * (3.4 + 0.85 * absi(n.fifths) + (2.2 if _has_time() else 0.4))


func _has_time() -> bool:
	var b: float = n.beats_per_measure
	return is_equal_approx(b, roundf(b)) and b >= 2.0 and b <= 7.0


func _text_rows() -> Array:
	var under := y_of_step(mini(n.bottom_step, n.low_step) - 2) + s * 1.3
	var row := s * 1.45
	return [under, under + row] if show_syllables else [-1.0, under]


## Everything that scrolls: staff lines, bar lines, notes, rests, words.
func draw_music(tr: PitchTrace) -> void:
	tr.draw_rect(Rect2(Vector2.ZERO, tr.size), PAPER)
	var lw := maxf(1.5, s * 0.09)
	for i in 5:
		var y := y_of_step(bottom() + i * 2)
		tr.draw_line(Vector2(0, y), Vector2(tr.size.x, y), INK_SOFT, lw)

	var origin := tr.sheet_origin()
	for b in n.bars:
		var x := tr._x_of(origin + b * spb) - s * 0.35
		if x > panel_w and x < tr.size.x:
			tr.draw_line(Vector2(x, y_of_step(bottom())), Vector2(x, y_of_step(bottom() + 8)), INK, lw * 1.3)

	var events: Array = n.events
	var heads := []   # per event: Vector2 head center (or null)
	var colors := []
	var color := INK
	for ev in events:
		if ev.note_index >= 0:
			color = _note_color(ev.note_index)
		colors.append(color if ev.midi >= 0 else INK)
		var x0 := tr._x_of(origin + ev.start * spb)
		heads.append(Vector2(x0 + s * 0.7, y_of_step(ev.step)) if ev.midi >= 0 else Vector2(x0, NAN))

	var rows := _text_rows()
	var text_size := int(clampf(s * 0.95, 18.0, 40.0))
	var beams := {}
	for i in events.size():
		var ev: Dictionary = events[i]
		var h: Vector2 = heads[i]
		var x0 := tr._x_of(origin + ev.start * spb)
		if x0 > tr.size.x + s or x0 < panel_w - 10.0 * s:
			continue
		if ev.midi < 0:
			_draw_rest(tr, ev.value, x0 + s * 0.4)
			continue
		var col: Color = colors[i]
		_ledgers(tr, ev.step, h.x, col, lw)
		if ev.acc != Notation.NO_ACCIDENTAL:
			var glyph: int = {1: SHARP, -1: FLAT, 0: NATURAL}[ev.acc]
			var spans: Array = {SHARP: [2.7, 2.7], FLAT: [1.3, 3.5], NATURAL: [2.7, 2.7]}[glyph]
			_glyph(tr, glyph, h.x - s * 1.25, ev.step - spans[0], ev.step + spans[1], col)
		_head(tr, h, ev.value, col)
		if ev.value in [3.0, 1.5, 0.75]:
			var dy := -s * 0.5 if posmod(ev.step - bottom(), 2) == 0 else 0.0
			tr.draw_circle(Vector2(h.x + s * 1.05, h.y + dy), s * 0.16, col)
		if ev.beam >= 0:
			if not beams.has(ev.beam):
				beams[ev.beam] = []
			beams[ev.beam].append(i)
		elif ev.value < 4.0:
			var up: bool = ev.step < bottom() + 4
			var stem_x := h.x + (s * 0.6 if up else -s * 0.6)
			var tip := h.y + (-s * 3.4 if up else s * 3.4)
			tr.draw_line(Vector2(stem_x, h.y + (-0.15 if up else 0.15) * s), Vector2(stem_x, tip), col, lw * 1.2)
			if ev.value <= 0.75:
				_flag(tr, Vector2(stem_x, tip), up, col)
				if ev.value <= 0.25:
					_flag(tr, Vector2(stem_x, tip + (s * 0.85 if up else -s * 0.85)), up, col)
		if ev.tie and i + 1 < events.size():
			_tie(tr, h, heads[i + 1], ev.step < bottom() + 4, col)
		if ev.note_index >= 0:
			if show_syllables:
				var syl := tr.key.syllable_of(ev.midi)
				if syl == "":
					syl = "·"
				_text(tr, syl, h.x, rows[0], text_size, Color(INK, 0.7))
			if ev.lyric != "":
				_text(tr, ev.lyric, h.x, rows[1], text_size, INK)

	for id in beams:
		_beam_group(tr, beams[id], events, heads, colors, lw)


## The fixed part on the left: clef, key and time signature, and the header.
func draw_panel(tr: PitchTrace) -> void:
	tr.draw_rect(Rect2(0, 0, panel_w, tr.size.y), PAPER)
	var lw := maxf(1.5, s * 0.09)
	for i in 5:
		var y := y_of_step(bottom() + i * 2)
		tr.draw_line(Vector2(0, y), Vector2(panel_w, y), INK_SOFT, lw)
	var x := s * 0.5
	if n.clef == Notation.Clef.TREBLE:
		_glyph(tr, G_CLEF, x, bottom() - 3.2, bottom() + 13.2, INK)
	else:
		_glyph(tr, F_CLEF, x, bottom() + 1.6, bottom() + 8.1, INK)
	x += s * 2.9
	var shift := 0 if n.clef == Notation.Clef.TREBLE else -14
	for i in absi(n.fifths):
		var st: int = (Notation.SHARP_STEPS[i] if n.fifths > 0 else Notation.FLAT_STEPS[i]) + shift
		if n.fifths > 0:
			_glyph(tr, SHARP, x, st - 2.7, st + 2.7, INK)
		else:
			_glyph(tr, FLAT, x, st - 1.3, st + 3.5, INK)
		x += s * 0.85
	if _has_time():
		var big := int(s * 2.3)
		var cx := x + s * 0.9
		_text(tr, str(roundi(n.beats_per_measure)), cx, y_of_step(bottom() + 4) - s * 0.1, big, INK)
		_text(tr, "4", cx, y_of_step(bottom()) - s * 0.1, big, INK)
	if header != "":
		var hs := int(clampf(s * 0.9, 18.0, 34.0))
		tr.draw_string(_text_font, Vector2(s * 0.5, hs * 1.2), header, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(INK, 0.75))
	if not results.is_empty():
		# Color key along the bottom.
		var hs := int(clampf(tr.size.y * 0.035, 18.0, 30.0))
		var y := tr.size.y - hs * 0.7
		var lx := hs * 0.6
		var items := [["landed", LANDED], ["nearly", NEARLY], ["keep going", KEEP_GOING], ["not heard", UNHEARD]]
		if tr.zoomed_out and not fits_whole:
			items.append(["· drag to look back", Color(INK, 0.6)])
		for item in items:
			if not item[0].begins_with("·"):
				tr.draw_circle(Vector2(lx + hs * 0.3, y - hs * 0.35), hs * 0.3, item[1])
				lx += hs * 0.9
			tr.draw_string(_text_font, Vector2(lx, y), item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, hs, item[1])
			lx += _text_font.get_string_size(item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x + hs * 0.9


func _note_color(index: int) -> Color:
	if index >= results.size():
		return INK
	var V := NoteScorer.Verdict
	match results[index].verdict:
		V.LANDED:
			return LANDED
		V.CLOSE, V.DRIFTED_LOW, V.DRIFTED_HIGH:
			return NEARLY
		V.NO_VOICE:
			return UNHEARD
	return KEEP_GOING


func _head(tr: PitchTrace, c: Vector2, value: float, col: Color) -> void:
	var w := s * (0.78 if value >= 4.0 else 0.66)
	var h := s * 0.47
	var pts := PackedVector2Array()
	var inner := PackedVector2Array()
	var tilt := -0.35 if value < 4.0 else 0.0
	for k in 20:
		var a := TAU * k / 20.0
		pts.append(c + Vector2(cos(a) * w, sin(a) * h).rotated(tilt))
		inner.append(c + Vector2(cos(a) * w * 0.62, sin(a) * h * 0.5).rotated(tilt if value >= 4.0 else -0.6))
	tr.draw_colored_polygon(pts, col)
	if value >= 2.0:
		tr.draw_colored_polygon(inner, PAPER)


func _ledgers(tr: PitchTrace, step: int, x: float, col: Color, lw: float) -> void:
	var b := bottom()
	var st := b - 2
	while st >= step:
		var y := y_of_step(st)
		tr.draw_line(Vector2(x - s, y), Vector2(x + s, y), col, lw)
		st -= 2
	st = b + 10
	while st <= step:
		var y := y_of_step(st)
		tr.draw_line(Vector2(x - s, y), Vector2(x + s, y), col, lw)
		st += 2


func _flag(tr: PitchTrace, tip: Vector2, up: bool, col: Color) -> void:
	var d := 1.0 if up else -1.0
	var pts := PackedVector2Array([tip, tip + Vector2(s * 0.3, d * s * 0.55), tip + Vector2(s * 0.95, d * s * 1.2),
		tip + Vector2(s * 0.8, d * s * 2.3)])
	tr.draw_polyline(pts, col, s * 0.22, true)


func _tie(tr: PitchTrace, a: Vector2, b: Vector2, below: bool, col: Color) -> void:
	if is_nan(b.y):
		return
	var d := 1.0 if below else -1.0
	var p0 := a + Vector2(s * 0.5, d * s * 0.55)
	var p1 := b + Vector2(-s * 0.5, d * s * 0.55)
	var pts := PackedVector2Array()
	for k in 13:
		var t := k / 12.0
		pts.append(p0.lerp(p1, t) + Vector2(0, d * sin(PI * t) * s * 0.6))
	tr.draw_polyline(pts, col, s * 0.16, true)


func _beam_group(tr: PitchTrace, idx: Array, events: Array, heads: Array, colors: Array, lw: float) -> void:
	var mean := 0.0
	for i in idx:
		mean += events[i].step
	mean /= idx.size()
	var up := mean < bottom() + 4
	var beam_y := INF if up else -INF
	for i in idx:
		var y: float = heads[i].y + (-s * 3.3 if up else s * 3.3)
		beam_y = minf(beam_y, y) if up else maxf(beam_y, y)
	var xs := []
	for i in idx:
		var h: Vector2 = heads[i]
		var x := h.x + (s * 0.6 if up else -s * 0.6)
		xs.append(x)
		tr.draw_line(Vector2(x, h.y), Vector2(x, beam_y), colors[i], lw * 1.2)
	var thick := s * 0.48
	var d := 1.0 if up else -1.0
	tr.draw_rect(Rect2(xs[0], beam_y if up else beam_y - thick, xs[-1] - xs[0] + lw, thick), colors[idx[0]])
	# Second beam for sixteenths: between neighbours, or a stub.
	for k in idx.size():
		if events[idx[k]].value > 0.26:
			continue
		var y2: float = beam_y + d * thick * 1.6
		var rect_y: float = y2 if up else y2 - thick
		if k + 1 < idx.size() and events[idx[k + 1]].value <= 0.26:
			tr.draw_rect(Rect2(xs[k], rect_y, xs[k + 1] - xs[k] + lw, thick), colors[idx[k]])
		elif k == 0 or events[idx[k - 1]].value > 0.26:
			var w := s * 0.9
			var x: float = xs[k] if k == 0 else xs[k] - w
			tr.draw_rect(Rect2(x, rect_y, w, thick), colors[idx[k]])


func _draw_rest(tr: PitchTrace, value: float, x: float) -> void:
	var b := bottom()
	var glyph: int = RESTS.get(value, 0x1D13D)
	match glyph:
		0x1D13B:
			_glyph(tr, glyph, x, b + 5.0, b + 6.0, INK)
		0x1D13C:
			_glyph(tr, glyph, x, b + 4.0, b + 5.0, INK)
		0x1D13D:
			_glyph(tr, glyph, x, b + 1.4, b + 6.9, INK)
		0x1D13E:
			_glyph(tr, glyph, x, b + 2.2, b + 5.8, INK)
		_:
			_glyph(tr, glyph, x, b + 0.4, b + 5.8, INK)
	if value in [3.0, 1.5, 0.75]:
		tr.draw_circle(Vector2(x + s * 1.3, y_of_step(b + 5)), s * 0.16, INK)


## Draw a font glyph so its outline spans from staff step `from_step` (bottom)
## to `to_step` (top), with its left edge at x.
func _glyph(tr: PitchTrace, code: int, x: float, from_step: float, to_step: float, col: Color) -> void:
	var bb: Array = BOUNDS[code]
	var y_bottom := y_of_step(from_step)
	var y_top := y_of_step(to_step)
	var size := int(maxf(4.0, (y_bottom - y_top) * 1000.0 / float(bb[3] - bb[1])))
	var k := size / 1000.0
	var baseline: float = y_bottom + bb[1] * k
	tr.draw_char(_font, Vector2(x - bb[0] * k, baseline), String.chr(code), size, col)


func _text(tr: PitchTrace, text: String, cx: float, y: float, size: int, col: Color) -> void:
	var w := _text_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	tr.draw_string(_text_font, Vector2(cx - w * 0.5, y + size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
