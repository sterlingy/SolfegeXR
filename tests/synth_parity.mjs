// Node check: web/synth_worklet.js renders the same samples as SynthEngine (GDScript).
//   1. Godot test run writes build/synth_parity.json (test_synth.gd)
//   2. node tests/synth_parity.mjs
import fs from "fs";
const here = new URL(".", import.meta.url);
const src = fs.readFileSync(new URL("../web/synth_worklet.js", here), "utf8");
const data = JSON.parse(fs.readFileSync(new URL("../build/synth_parity.json", here), "utf8"));

let fail = 0;
for (const c of data.cases) {
  let Proc = null;
  const g = {
    sampleRate: data.rate, currentFrame: 0,
    AudioWorkletProcessor: class { constructor() { this.port = { postMessage() {} }; } },
    registerProcessor: (_, k) => { Proc = k; },
  };
  // currentFrame is read as a global inside the processor: expose a getter.
  const fn = new Function("G", "AudioWorkletProcessor", "registerProcessor",
    "with (G) {" + src + "}");
  fn(g, g.AudioWorkletProcessor, g.registerProcessor);
  const p = new Proc();
  for (const v of c.notes) p.onMessage({ type: "note", v: { ...v } });
  const out = [];
  const total = c.samples.length;
  for (let f = 0; f < total; f += 128) {
    g.currentFrame = f;
    if (f === c.release_at) p.onMessage({ type: "release" });
    const buf = new Float32Array(128);
    p.process([], [[buf]]);
    out.push(...buf);
  }
  let maxErr = 0, at = 0;
  for (let i = 0; i < total; i++) {
    const e = Math.abs(out[i] - c.samples[i]);
    if (e > maxErr) { maxErr = e; at = i; }
  }
  const ok = maxErr < 1e-4;
  if (!ok) fail++;
  console.log(`${ok ? "ok  " : "FAIL"} ${c.timbre}: max difference ${maxErr.toExponential(2)} at sample ${at}`);
}
process.exit(fail ? 1 : 0);
