// SolfegeApp synth: AudioWorklet processor (runs on the browser's audio thread).
//
// JavaScript port of SynthEngine._render_voice (scripts/audio/synth_engine.gd).
// The GDScript side still decides WHAT to play (notes, drone, cadences) and
// sends each note here; this renders it. Keep the two in sync.
//
// Messages in:  {type:"note", v:{kind, hz, hz_end, gain, at, dur, attack, release, saw_mix, cutoff}}
//               (hz_end: the voice glides log-linearly from hz to hz_end over dur)
//               {type:"stop", kind}   release all voices of a kind
//               {type:"release"}      release everything
// Messages out: {type:"level", peak, voices} about every 250 ms (diagnostics)

const VOICE = 0;
const CLICK = 3;  // SynthEngine.Kind.CLICK
const VIBRATO_HZ = 5.2;
const VIBRATO_CENTS = 12.0;
const VIBRATO_DELAY = 0.25;
const MASTER_GAIN = 0.8;

function polyBlep(t, dt) {
  if (t < dt) { const x = t / dt; return x + x - x * x - 1.0; }
  if (t > 1.0 - dt) { const x = (t - 1.0) / dt; return x * x + x + x + 1.0; }
  return 0.0;
}

class SolfegeSynthProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.voices = [];
    this.peak = 0;
    this.blocks = 0;
    this.port.onmessage = (e) => this.onMessage(e.data);
  }

  onMessage(m) {
    if (m.type === "note") {
      const v = m.v;
      v.start = Math.round(v.at * sampleRate);
      v.end = v.dur >= 0 ? Math.round((v.at + v.dur) * sampleRate) : -1;
      v.phase = Math.random();
      v.vibPhase = 0;
      v.lp = 0;
      v.releasedAt = -1;
      v.lpA = 1 - Math.exp(-2 * Math.PI * v.cutoff / sampleRate);
      this.voices.push(v);
    } else if (m.type === "stop" || m.type === "release") {
      for (const v of this.voices) {
        if (v.releasedAt < 0 && (m.type === "release" || v.kind === m.kind)) v.releasedAt = currentFrame;
      }
    }
  }

  process(inputs, outputs) {
    const out = outputs[0][0];
    const n = out.length;
    out.fill(0);
    const now = currentFrame;
    const keep = [];
    for (const v of this.voices) {
      if (!this.renderVoice(v, out, now, n)) keep.push(v);
    }
    this.voices = keep;
    let peak = this.peak;
    for (let i = 0; i < n; i++) {
      const y = Math.tanh(out[i] * MASTER_GAIN);
      out[i] = y;
      const a = y < 0 ? -y : y;
      if (a > peak) peak = a;
    }
    for (let c = 1; c < outputs[0].length; c++) outputs[0][c].set(out);
    this.peak = peak;
    if (++this.blocks % 94 === 0) {  // ~250 ms at 48 kHz
      this.port.postMessage({ type: "level", peak: this.peak, voices: this.voices.length });
      this.peak = 0;
    }
    return true;
  }

  // Returns true when the voice is finished.
  renderVoice(v, out, now, n) {
    if (v.start >= now + n) return false;
    const attackS = v.attack * sampleRate;
    const releaseS = v.release * sampleRate;
    const isVoice = v.kind === VOICE;
    const isClick = v.kind === CLICK;
    let end = v.end;
    if (v.releasedAt >= 0 && (end < 0 || v.releasedAt < end)) end = v.releasedAt;
    let phase = v.phase, vib = v.vibPhase, lp = v.lp;
    let dt = v.hz / sampleRate;
    const hzEnd = v.hz_end || v.hz;
    const glide = hzEnd !== v.hz;
    const durS = Math.max(1, v.dur * sampleRate);
    const first = Math.max(0, v.start - now);
    for (let i = first; i < n; i++) {
      const s = now + i;
      const age = s - v.start;
      let env = Math.min(1, age / attackS);
      if (end >= 0 && s >= end) {
        env *= 1 - (s - end) / releaseS;
        if (env <= 0) { v.phase = phase; return true; }
      }
      if (isVoice && (i & 15) === 0) {
        const depth = Math.min(1, Math.max(0, (age / sampleRate - VIBRATO_DELAY) / 0.3));
        vib += 16 * VIBRATO_HZ / sampleRate;
        const base = glide ? v.hz * Math.pow(hzEnd / v.hz, Math.min(1, Math.max(0, age / durS))) : v.hz;
        dt = base / sampleRate * Math.pow(2, depth * VIBRATO_CENTS / 1200 * Math.sin(2 * Math.PI * vib));
      }
      phase += dt;
      if (phase >= 1) phase -= 1;
      const tri = 4 * Math.abs(phase - 0.5) - 1;
      const saw = 2 * phase - 1 - polyBlep(phase, dt);
      // A metronome tick is a burst of noise: no pitch for the detector to hear.
      const raw = isClick ? Math.random() * 2 - 1 : tri + (saw - tri) * v.saw_mix;
      lp += v.lpA * (raw - lp);
      out[i] += lp * env * v.gain;
    }
    v.phase = phase; v.vibPhase = vib; v.lp = lp;
    return false;
  }
}

registerProcessor("solfege-synth", SolfegeSynthProcessor);
