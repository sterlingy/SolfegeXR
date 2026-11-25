// SolfegeApp synth bridge (main thread). Godot evaluates this once and talks
// to window.solfegeSynth through JavaScriptBridge.
//
//   start(workletSource)  create the audio context + synth worklet (async; watch .state)
//   time()                synth clock in seconds (AudioContext.currentTime)
//   note(json)            schedule a note (fields: see synth_worklet.js)
//   stop(kind)            release all voices of a kind
//   release()             release everything
//   state                 "idle" | "starting" | "running" | "error"
//   peak, voices          output level / active voices (diagnostics)
//
// Browsers only start audio after a user gesture, so the context is resumed on
// the first tap or key press if it starts suspended.

(function () {
  if (window.solfegeSynth) return;

  const Y = { state: "idle", error: "", ctx: null, node: null, peak: 0, voices: 0 };

  Y.start = function (workletSource) {
    if (Y.state === "running" || Y.state === "starting") return;
    Y.state = "starting";
    Y._start(workletSource).catch(function (e) {
      Y.state = "error";
      Y.error = (e && (e.name + ": " + e.message)) || String(e);
    });
  };

  Y._start = async function (workletSource) {
    const AC = window.AudioContext || window.webkitAudioContext;
    Y.ctx = new AC({ latencyHint: "interactive" });
    const url = URL.createObjectURL(new Blob([workletSource], { type: "application/javascript" }));
    try {
      await Y.ctx.audioWorklet.addModule(url);
    } finally {
      URL.revokeObjectURL(url);
    }
    Y.node = new AudioWorkletNode(Y.ctx, "solfege-synth", {
      numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2],
    });
    Y.node.port.onmessage = function (e) {
      if (e.data && e.data.type === "level") { Y.peak = e.data.peak; Y.voices = e.data.voices; }
    };
    Y.node.connect(Y.ctx.destination);
    if (Y.ctx.state !== "running") {
      const resume = function () { Y.ctx.resume(); };
      ["pointerdown", "touchend", "keydown"].forEach(function (ev) {
        window.addEventListener(ev, resume, { capture: true, passive: true });
      });
    }
    Y.state = "running";
  };

  Y.time = function () { return Y.ctx ? Y.ctx.currentTime : 0; };
  Y.note = function (json) { if (Y.node) Y.node.port.postMessage({ type: "note", v: JSON.parse(json) }); };
  Y.stop = function (kind) { if (Y.node) Y.node.port.postMessage({ type: "stop", kind: kind }); };
  Y.release = function () { if (Y.node) Y.node.port.postMessage({ type: "release" }); };

  // A hidden tab pauses the app (browsers stop its frame loop) but not this
  // audio thread, so a drone would keep sounding on its own. Go quiet instead.
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) Y.release();
  });

  window.solfegeSynth = Y;
})();
