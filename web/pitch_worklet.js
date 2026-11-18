// SolfegeApp pitch detector: AudioWorklet processor (runs on the audio thread).
//
// Runs the shared C++ YIN detector (yin.wasm) when the bridge provides it, and
// otherwise falls back to the JavaScript version in analyze() below. The message
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

// The shared C++ detector (native/src/yin.cpp) compiled to WebAssembly. The
// bridge compiles yin.wasm on the main thread and hands the Module over in
// processorOptions; if anything fails we fall back to the JS version below.
class WasmYin {
  constructor(module, rate) {
    const stub = () => 0;
    const inst = new WebAssembly.Instance(module, {
      env: { emscripten_notify_memory_growth: () => {} },
      wasi_snapshot_preview1: { fd_close: stub, fd_write: stub, fd_seek: stub },
    });
    this.x = inst.exports;
    if (this.x._initialize) this.x._initialize();
    this.mem = this.x.memory;
    this.block = this.x.yin_block_size();
    this.h = this.x.yin_create(rate, HOP);
    if (!this.h) throw new Error("yin_create failed");
    this.inPtr = this.x.yin_input(this.h);
  }
  // Feeds input-rate samples; calls emit(time, hz, conf, rms) per estimate.
  push(ch, emit) {
    for (let off = 0; off < ch.length; off += this.block) {
      const n = Math.min(this.block, ch.length - off);
      new Float32Array(this.mem.buffer, this.inPtr, n).set(ch.subarray(off, off + n));
      const count = this.x.yin_push(this.h, n);
      if (count > 0) {
        const out = new Float32Array(this.mem.buffer, this.x.yin_output(this.h), count * 4);
        for (let i = 0; i < count; i++) emit(out[i * 4], out[i * 4 + 1], out[i * 4 + 2], out[i * 4 + 3]);
      }
    }
  }
}

class SolfegePitchProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.wasm = null;
    let wasmError = "";
    const mod = options && options.processorOptions && options.processorOptions.yinModule;
    if (mod) {
      try {
        this.wasm = new WasmYin(mod, sampleRate);
      } catch (e) {
        wasmError = String(e);
      }
    }
    this.t0 = -1; // context time of the first sample fed to the WASM detector
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
    this.port.postMessage({
      type: "info", sampleRate, rate: this.rate, decim: this.decim,
      detector: this.wasm ? "wasm" : "js", wasmError,
    });
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || input.length === 0) return true;
    const ch = input[0];
    if (this.wasm) {
      if (this.t0 < 0) this.t0 = currentTime;
      // C++ times are seconds since the first sample; map to context time.
      this.wasm.push(ch, (t, hz, conf, rms) => this.port.postMessage([this.t0 + t, hz, conf, rms]));
      return true;
    }
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
