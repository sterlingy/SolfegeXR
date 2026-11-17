// SolfegeApp pitch detector: AudioWorklet processor (runs on the audio thread).
//
// Temporary JavaScript stand-in for the shared C++ YIN/pYIN detector. When the
// C++ version is compiled to WASM it replaces analyze() below; the message
// format to the main thread stays the same.
//
// Pipeline: mic samples -> decimate to ~24 kHz -> ring buffer -> every HOP
// samples run YIN on the latest WINDOW samples -> postMessage([t, hz, conf, rms]).
//
// Loaded by pitch_bridge.js from a Blob URL, so this file is plain text inside
// the Godot export (see include_filter in export_presets.cfg).

const TARGET_RATE = 24000; // analysis rate; plenty for sung fundamentals
const WINDOW = 512;        // ~21 ms at 24 kHz
const HOP = 128;           // ~5.3 ms between estimates
const MIN_HZ = 70;         // lowest fundamental we look for (low bass ~E2 = 82 Hz)
const MAX_HZ = 1200;       // highest (soprano top ~C6 = 1047 Hz)
const YIN_THRESHOLD = 0.15;

class SolfegePitchProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.decim = Math.max(1, Math.round(sampleRate / TARGET_RATE));
    this.rate = sampleRate / this.decim;
    this.tauMin = Math.max(2, Math.floor(this.rate / MAX_HZ));
    this.tauMax = Math.ceil(this.rate / MIN_HZ);
    this.bufLen = WINDOW + this.tauMax + 2;
    this.ring = new Float32Array(this.bufLen * 2); // doubled so a window is always contiguous
    this.write = 0;
    this.filled = 0;
    this.sinceHop = 0;
    this.accum = 0;      // decimation accumulator (box filter)
    this.accumN = 0;
    this.diff = new Float32Array(this.tauMax + 2);
    this.port.postMessage({ type: "info", sampleRate, rate: this.rate, decim: this.decim });
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || input.length === 0) return true;
    const ch = input[0];
    for (let i = 0; i < ch.length; i++) {
      // Simple box-filter decimation. Fine for voice: harmonics above 12 kHz
      // barely matter to YIN, and aliasing of them is tiny.
      this.accum += ch[i];
      if (++this.accumN < this.decim) continue;
      const s = this.accum / this.decim;
      this.accum = 0;
      this.accumN = 0;

      this.ring[this.write] = s;
      this.ring[this.write + this.bufLen] = s;
      this.write = (this.write + 1) % this.bufLen;
      if (this.filled < this.bufLen) this.filled++;

      if (++this.sinceHop >= HOP && this.filled >= this.bufLen) {
        this.sinceHop = 0;
        this.analyze();
      }
    }
    return true;
  }

  analyze() {
    // Oldest sample of the contiguous view is at this.write.
    const buf = this.ring;
    const start = this.write;
    const W = WINDOW;
    const tauMax = this.tauMax;
    const d = this.diff;

    // Loudness of the analysis window (for silence gating on the Godot side).
    let sumSq = 0;
    for (let i = 0; i < W; i++) {
      const v = buf[start + i];
      sumSq += v * v;
    }
    const rms = Math.sqrt(sumSq / W);

    // YIN step 2: difference function.
    for (let tau = 1; tau <= tauMax; tau++) {
      let sum = 0;
      for (let i = 0; i < W; i++) {
        const delta = buf[start + i] - buf[start + i + tau];
        sum += delta * delta;
      }
      d[tau] = sum;
    }

    // Step 3: cumulative mean normalized difference.
    d[0] = 1;
    let running = 0;
    for (let tau = 1; tau <= tauMax; tau++) {
      running += d[tau];
      d[tau] = running > 0 ? (d[tau] * tau) / running : 1;
    }

    // Step 4: absolute threshold, then walk to the local minimum.
    let tau = -1;
    for (let t = this.tauMin; t < tauMax; t++) {
      if (d[t] < YIN_THRESHOLD) {
        while (t + 1 < tauMax && d[t + 1] < d[t]) t++;
        tau = t;
        break;
      }
    }
    if (tau < 0) {
      // No dip under threshold: take the global minimum, report low confidence.
      let best = this.tauMin;
      for (let t = this.tauMin + 1; t < tauMax; t++) if (d[t] < d[best]) best = t;
      tau = best;
    }

    // Step 5: parabolic interpolation for sub-sample period.
    let betterTau = tau;
    if (tau > 1 && tau < tauMax) {
      const a = d[tau - 1], b = d[tau], c = d[tau + 1];
      const denom = a + c - 2 * b;
      if (denom !== 0) betterTau = tau + (a - c) / (2 * denom);
    }

    const hz = this.rate / betterTau;
    const conf = Math.max(0, Math.min(1, 1 - d[tau]));
    // currentTime is the context time of the current render quantum.
    this.port.postMessage([currentTime, hz, conf, rms]);
  }
}

registerProcessor("solfege-pitch", SolfegePitchProcessor);
