class_name Harmonizer
extends RefCounted
## Picks a simple chord for each bar of a melody, for the backing track.
## Candidates are the main chords of the key (I IV V vi in major; i iv V VI in
## minor-ish modes); each bar gets the chord whose tones cover the most of
## that bar's melody (weighted by duration, with a nudge toward I/V on strong
## beats). Simple on purpose: it's an accompaniment, not an arrangement.

## Scale degrees (0-based) of chord roots to consider, in order of preference.
const MAJOR_ROOTS := [0, 4, 3, 5]   # I, V, IV, vi
const MINOR_ROOTS := [0, 4, 3, 5]   # i, V, iv, VI


## Chord tones (semitones above the tonic, 0..11) for a chord on scale degree
## `root`. The dominant gets a major third (leading tone) in minor-ish modes.
static func chord_tones(key: MusicKey, root: int) -> Array[int]:
	var steps := key.steps()
	var tones: Array[int] = []
	for k in [0, 2, 4]:
		var semi := steps[(root + k) % 7]
		if root == 4 and k == 2 and steps[6] == 10:
			semi = 11
		tones.append(semi)
	return tones


## targets: [{midi, start, duration}] (seconds). Returns one entry per bar:
## {start, duration, root (scale degree), tones (semitones above tonic)}.
## first_bar_start: where the first bar begins (negative for a pickup).
static func chords_for(targets: Array, key: MusicKey, bar_seconds: float, length := -1.0,
		first_bar_start := 0.0) -> Array:
	if length < 0.0:
		for t in targets:
			length = maxf(length, t.start + t.duration)
	var out := []
	var bars := maxi(1, ceili((length - first_bar_start) / bar_seconds - 0.001))
	var prev := 0
	for b in bars:
		var b0 := first_bar_start + b * bar_seconds
		var b1 := b0 + bar_seconds
		var weights := {}
		for t in targets:
			var overlap := minf(b1, t.start + t.duration) - maxf(b0, t.start)
			if overlap <= 0.0:
				continue
			var pc := posmod(int(t.midi) - key.tonic_pc, 12)
			var w: float = overlap
			if absf(t.start - b0) < 0.05:
				w *= 1.5  # the note on the downbeat matters most
			weights[pc] = weights.get(pc, 0.0) + w
		var best := prev  # an empty bar keeps the previous chord
		var best_score := -1.0
		for i in MAJOR_ROOTS.size():
			var root: int = MAJOR_ROOTS[i]
			var tones := chord_tones(key, root)
			var score := 0.0
			for pc in weights:
				if pc in tones:
					score += weights[pc]
			score -= 0.01 * i  # tie-break toward I, then V, IV, vi
			if b == bars - 1 and root == 0:
				score += 0.2  # songs end at home
			if score > best_score:
				best_score = score
				best = root
		if weights.is_empty():
			best = prev
		prev = best
		out.append({start = b0, duration = bar_seconds, root = best, tones = chord_tones(key, best)})
	return out
