// Node check: yin.wasm (C++ detector) gives the same pitch as the JS fallback.
//   node tests/wasm_parity.mjs
import fs from "fs";
const here = new URL(".", import.meta.url);
const src = fs.readFileSync(new URL("../web/pitch_worklet.js", here), "utf8");
const mod = new WebAssembly.Module(fs.readFileSync(new URL("../web/yin.wasm", here)));

function run(useWasm, signal, rate) {
  const out = [];
  let Proc = null;
  const g = {
    sampleRate: rate, currentTime: 0,
    AudioWorkletProcessor: class { constructor() { this.port = { postMessage: (m) => out.push(m) }; } },
    registerProcessor: (_, c) => { Proc = c; },
  };
  new Function(...Object.keys(g), src)(...Object.values(g));
  const p = new Proc({ processorOptions: useWasm ? { yinModule: mod } : {} });
  for (let i = 0; i < signal.length; i += 128) p.process([[signal.subarray(i, i + 128)]]);
  return { info: out[0], frames: out.filter(Array.isArray) };
}

let fail = 0;
for (const rate of [44100, 48000]) for (const hz of [82.4, 110, 220, 261.6, 440, 880]) {
  const n = rate; const sig = new Float32Array(n);
  for (let i = 0; i < n; i++) { const t = i / rate; sig[i] = 0.3 * Math.sin(2 * Math.PI * hz * t) + 0.15 * Math.sin(4 * Math.PI * hz * t) + 0.05 * Math.sin(6 * Math.PI * hz * t); }
  const w = run(true, sig, rate), j = run(false, sig, rate);
  if (w.info.detector !== "wasm") { console.log("WASM did not load:", w.info.wasmError); process.exit(1); }
  const med = (f) => { const v = f.slice(f.length / 2).map((x) => x[1]).sort((a, b) => a - b); return v[v.length >> 1]; };
  const mw = med(w.frames), mj = med(j.frames);
  const cents = (a, b) => 1200 * Math.log2(a / b);
  const ok = Math.abs(cents(mw, hz)) < 5 && Math.abs(cents(mw, mj)) < 1 && Math.abs(w.frames.length - j.frames.length) <= 2;
  if (!ok) fail++;
  console.log(`${ok ? "ok  " : "FAIL"} ${rate} Hz input, ${hz} Hz tone: wasm ${mw.toFixed(2)} (${w.frames.length} frames), js ${mj.toFixed(2)} (${j.frames.length})`);
}
process.exit(fail ? 1 : 0);
