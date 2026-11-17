// SolfegeApp mic bridge: runs on the page's main thread.
//
// Godot evaluates this file once (JavaScriptBridge.eval) and then talks to
// window.solfegePitch through JavaScriptBridge.get_interface().
//
//   start(workletSource)  -> begins mic capture (async; watch .state)
//   stop()
//   drain()               -> JSON string: [[t, hz, conf, rms], ...] since last drain
//   state                 -> "idle" | "starting" | "running" | "error"
//   error                 -> message when state == "error"
//   info()                -> JSON string with sample rate / latency details
//
// Mic cleanup (echo cancellation, noise suppression, auto gain) is turned OFF:
// those filters smear pitch and pump the level, which hurts detection.

(function () {
  if (window.solfegePitch) return;

  const S = {
    state: "idle",
    error: "",
    queue: [],
    ctx: null,
    stream: null,
    node: null,
    workletInfo: null,
  };

  S.start = function (workletSource) {
    if (S.state === "running" || S.state === "starting") return;
    S.state = "starting";
    S.error = "";
    S._start(workletSource).catch(function (e) {
      S.state = "error";
      S.error = (e && (e.name + ": " + e.message)) || String(e);
      S.stop(true);
    });
  };

  S._start = async function (workletSource) {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      throw new Error("Microphone needs a secure page (https or localhost).");
    }
    S.stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: false,
        noiseSuppression: false,
        autoGainControl: false,
        channelCount: 1,
      },
      video: false,
    });

    const AC = window.AudioContext || window.webkitAudioContext;
    S.ctx = new AC({ latencyHint: "interactive" });
    if (S.ctx.state === "suspended") await S.ctx.resume();

    const url = URL.createObjectURL(new Blob([workletSource], { type: "application/javascript" }));
    try {
      await S.ctx.audioWorklet.addModule(url);
    } finally {
      URL.revokeObjectURL(url);
    }

    const src = S.ctx.createMediaStreamSource(S.stream);
    S.node = new AudioWorkletNode(S.ctx, "solfege-pitch", {
      numberOfInputs: 1,
      numberOfOutputs: 1,
      channelCount: 1,
      channelCountMode: "explicit",
    });
    S.node.port.onmessage = function (ev) {
      const m = ev.data;
      if (Array.isArray(m)) {
        S.queue.push(m);
        if (S.queue.length > 2000) S.queue.splice(0, S.queue.length - 2000);
      } else if (m && m.type === "info") {
        S.workletInfo = m;
      }
    };
    // Some browsers only pull a node that reaches the destination. Route it
    // through a muted gain so nothing is audible.
    const mute = S.ctx.createGain();
    mute.gain.value = 0;
    src.connect(S.node);
    S.node.connect(mute);
    mute.connect(S.ctx.destination);

    S.state = "running";
  };

  S.stop = function (keepError) {
    try { if (S.node) S.node.disconnect(); } catch (e) {}
    try { if (S.stream) S.stream.getTracks().forEach(function (t) { t.stop(); }); } catch (e) {}
    try { if (S.ctx) S.ctx.close(); } catch (e) {}
    S.node = null; S.stream = null; S.ctx = null; S.queue = [];
    if (!keepError) { S.state = "idle"; S.error = ""; }
  };

  S.drain = function () {
    const out = JSON.stringify(S.queue);
    S.queue = [];
    return out;
  };

  S.now = function () {
    return S.ctx ? S.ctx.currentTime : 0;
  };

  S.info = function () {
    const track = S.stream && S.stream.getAudioTracks()[0];
    const settings = track && track.getSettings ? track.getSettings() : {};
    return JSON.stringify({
      contextRate: S.ctx ? S.ctx.sampleRate : 0,
      baseLatency: S.ctx ? S.ctx.baseLatency || 0 : 0,
      echoCancellation: settings.echoCancellation,
      noiseSuppression: settings.noiseSuppression,
      autoGainControl: settings.autoGainControl,
      worklet: S.workletInfo,
    });
  };

  window.solfegePitch = S;
})();
