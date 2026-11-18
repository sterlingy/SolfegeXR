class_name LatencyCheck
extends RefCounted
## Measures timing on a device: the app plays short beeps through the speaker
## and listens for them with the mic. "Round trip" = speaker + mic + detector.
## Subtracting the output latency the platform reports gives an estimate of
## mic-to-screen time (what a singer feels). Target from the design: < ~50 ms.
##
## Clocks: beeps are scheduled on the synth clock; pitch frames come on the
## mic clock. Each frame the caller records offset = synth_now - mic_now, and
## frames are moved onto the synth clock with it.

const BEEP_MIDI := 81          ## A5, 880 Hz: clear of most room noise
const BEEPS := 6
const BEEP_SECONDS := 0.12
const GAP_SECONDS := 0.7
const LEAD_SECONDS := 0.6      ## before the first beep
const SEARCH_SECONDS := 0.45   ## how long after each beep to look for it

var beep_times: Array[float] = []     ## synth clock
var _heard: Array[Vector2] = []       ## (synth-clock time, midi) of clear frames
var _noise_rms := 0.0
var _noise_n := 0


## Schedule the beeps; returns when (synth clock) the last one has had time to arrive.
func start(engine: SynthEngine) -> float:
	beep_times.clear()
	_heard.clear()
	var t0 := engine.time() + LEAD_SECONDS
	for i in BEEPS:
		var t := t0 + i * GAP_SECONDS
		beep_times.append(t)
		engine.note(BEEP_MIDI, t, BEEP_SECONDS, SynthEngine.Kind.VOICE, 0.5)
	return beep_times[-1] + SEARCH_SECONDS + 0.2


## Feed mic frames with the current clock offset (synth_now - mic_now).
func add_frames(frames: Array[PitchFrame], offset: float) -> void:
	for f in frames:
		var t := f.time + offset
		if beep_times.is_empty() or t < beep_times[0] - 0.05:
			_noise_rms += f.rms  # room level before the first beep
			_noise_n += 1
			continue
		if f.confidence >= 0.7 and f.frequency > 0.0:
			var m := MusicKey.hz_to_midi(f.frequency)
			var threshold := maxf(0.003, 3.0 * _noise_rms / maxi(1, _noise_n))
			if f.rms >= threshold and absf(fposmod(m - BEEP_MIDI + 6.0, 12.0) - 6.0) < 1.0:
				_heard.append(Vector2(t, m))


## {heard, beeps, round_trip_ms (median), spread_ms}; round_trip -1 if none heard.
func result() -> Dictionary:
	var delays: Array[float] = []
	for b in beep_times:
		for h in _heard:
			if h.x >= b - 0.02 and h.x <= b + SEARCH_SECONDS:
				delays.append((h.x - b) * 1000.0)
				break
	if delays.is_empty():
		return {heard = 0, beeps = beep_times.size(), round_trip_ms = -1.0, spread_ms = 0.0}
	delays.sort()
	var median := delays[delays.size() / 2]
	return {heard = delays.size(), beeps = beep_times.size(), round_trip_ms = median,
		spread_ms = delays[-1] - delays[0]}


## A plain-language summary. output_ms: the platform's reported speaker
## latency (-1 if unknown).
static func describe(r: Dictionary, output_ms: float) -> String:
	if r.round_trip_ms < 0.0:
		return "I couldn't hear the beeps. Turn the volume up, take headphones off, and try again."
	var text := "Heard %d of %d beeps. Speaker to screen: %d ms." % [r.heard, r.beeps, roundi(r.round_trip_ms)]
	if output_ms > 0.0 and r.round_trip_ms > output_ms:
		var mic_ms: float = r.round_trip_ms - output_ms
		text += "\nYour voice reaches the screen in about %d ms" % roundi(mic_ms)
		text += " (great)." if mic_ms <= 50.0 else (" (fine)." if mic_ms <= 90.0 else ", which is a little slow on this device.")
	return text
