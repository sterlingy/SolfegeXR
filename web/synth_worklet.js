// SolfegeApp synth: AudioWorklet processor (runs on the browser's audio thread).
//
// JavaScript port of SynthEngine._render_voice (scripts/audio/synth_engine.gd).
// The GDScript side decides WHAT to play (notes, drone, cadences) and the sound:
// it sends each note with its harmonic strengths and settings. This builds the
// same wave table and renders it with the same maths. Keep the two in step;
// tests/synth_parity.mjs compares them sample by sample.
//
// Messages in:  {type:"note", v:{kind, hz, hz_end, gain, at, dur, attack, release,
//                vib_cents, vib_hz, chorus, breath, seed, partials}}
//               (hz_end: the voice glides log-linearly from hz to hz_end over dur)
//               {type:"stop", kind}   release all voices of a kind
//               {type:"release"}      release everything
// Messages out: {type:"level", peak, voices} about every 250 ms (diagnostics)

const CLICK = 3;  // SynthEngine.Kind.CLICK
const TABLE_SIZE = 1024;
const VIBRATO_DELAY = 0.25;
const CLICK_CUTOFF = 8000.0;
const BREATH_CUTOFF = 2500.0;
const MASTER_GAIN = 0.8;

const tables = new Map();  // wave tables by partials, built once

// One cycle of the wave, normalised to an RMS of 0.5 (SynthEngine.build_table).
function buildTable(parts) {
  const key = parts.join(",");
  let t = tables.get(key);
  if (t) return t;
  t = new Float64Array(TABLE_SIZE);
  let sumSq = 0;
  for (let j = 0; j < TABLE_SIZE; j++) {
    let x = 0;
    for (let k = 0; k < parts.length; k++) {
      if (parts[k] !== 0) x += parts[k] * Math.sin(2 * Math.PI * (k + 1) * j / TABLE_SIZE);
    }
    t[j] = x;
    sumSq += x * x;
  }
  const scale = 0.5 / Math.max(1e-9, Math.sqrt(sumSq / TABLE_SIZE));
  for (let j = 0; j < TABLE_SIZE; j++) t[j] *= scale;
  tables.set(key, t);
  return t;
}

// 32-bit linear congruential generator (SynthEngine.lcg).
function lcg(s) { return (Math.imul(s, 1664525) + 1013904223) >>> 0; }

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
      v.start = Math.trunc(v.at * sampleRate);
      v.end = v.dur >= 0 ? Math.trunc((v.at + v.dur) * sampleRate) : -1;
      v.releasedAt = -1;
      v.table = v.kind === CLICK ? null : buildTable(v.partials || [1]);
      v.phase = (v.seed % 1000) / 1000;
      v.phase2 = v.phase;
      v.vibPhase = 0;
      v.lp = 0;
      v.noise = v.seed >>> 0;
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
    const rate = sampleRate;
    const attackS = Math.max(1, v.attack * rate);
    const releaseS = Math.max(1, v.release * rate);
    const isClick = v.kind === CLICK;
    const hzEnd = v.hz_end || v.hz;
    const glide = hzEnd !== v.hz;
    const durS = Math.max(1, v.dur * rate);
    const vibCents = v.vib_cents || 0, vibHz = v.vib_hz || 5;
    const moving = glide || vibCents > 0;
    const chorus = (v.chorus || 0) > 0;
    const chUp = Math.pow(2, (v.chorus || 0) / 2400), chDown = 1 / chUp;
    const breath = v.breath || 0;
    const noiseA = 1 - Math.exp(-2 * Math.PI * (isClick ? CLICK_CUTOFF : BREATH_CUTOFF) / rate);
    const table = v.table, mask = TABLE_SIZE - 1;
    let end = v.end;
    if (v.releasedAt >= 0 && (end < 0 || v.releasedAt < end)) end = v.releasedAt;
    let phase = v.phase, phase2 = v.phase2, vib = v.vibPhase, lp = v.lp, noise = v.noise;
    let dt = v.hz / rate;
    let chiff = 1;
    const first = Math.max(0, v.start - now);
    for (let i = first; i < n; i++) {
      const s = now + i;
      const age = s - v.start;
      let env = Math.min(1, age / attackS);
      if (end >= 0 && s >= end) {
        env *= 1 - (s - end) / releaseS;
        if (env <= 0) return true;
      }
      if ((i & 15) === 0) {
        if (moving) {
          const depth = Math.min(1, Math.max(0, (age / rate - VIBRATO_DELAY) / 0.3));
          vib += 16 * vibHz / rate;
          const base = glide ? v.hz * Math.pow(hzEnd / v.hz, Math.min(1, Math.max(0, age / durS))) : v.hz;
          dt = base / rate * Math.pow(2, depth * vibCents / 1200 * Math.sin(2 * Math.PI * vib));
        }
        if (breath > 0) chiff = 1 + 2.5 * Math.exp(-age / (0.06 * rate));
      }
      let y;
      if (isClick || breath > 0) {
        noise = lcg(noise);
        lp += noiseA * ((noise / 2147483648 - 1) - lp);
      }
      if (isClick) {
        // A metronome tick is a burst of noise: no pitch for the detector to hear.
        y = lp;
      } else {
        phase += chorus ? dt * chDown : dt;
        if (phase >= 1) phase -= 1;
        let x = phase * TABLE_SIZE, j = x | 0, a = table[j];
        y = a + (table[(j + 1) & mask] - a) * (x - j);
        if (chorus) {
          phase2 += dt * chUp;
          if (phase2 >= 1) phase2 -= 1;
          x = phase2 * TABLE_SIZE; j = x | 0; a = table[j];
          y = 0.70710678 * (y + a + (table[(j + 1) & mask] - a) * (x - j));  // 1/sqrt(2): level of one voice
        }
        if (breath > 0) y += lp * breath * chiff;
      }
      out[i] += y * env * v.gain;
    }
    v.phase = phase; v.phase2 = phase2; v.vibPhase = vib; v.lp = lp; v.noise = noise;
    return false;
  }
}

registerProcessor("solfege-synth", SolfegeSynthProcessor);
