// SolfegeApp mic bridge: runs on the page's main thread.
//
// Godot evaluates this file once (JavaScriptBridge.eval) and then talks to
// window.solfegePitch through JavaScriptBridge.get_interface().
//
//   start(workletSource, deviceId, wasmB64)  -> begins mic capture (async; watch .state).
//                                      wasmB64 = yin.wasm as base64 ("" = JS detector).
//                                      deviceId "" = the browser's choice.
//   stop()
//   drain()            -> JSON string: [[t, hz, conf, rms], ...] since last drain
//   state              -> "idle" | "starting" | "running" | "error"
//   error              -> message when state == "error"
//   isSilent()         -> true when the input has been exact digital silence
//                         for over 1.5 s (wrong device, e.g. a loop-back or a
//                         VR headset's virtual mic); not just a quiet room
//   devicesJson        -> JSON [{id, label}] of audio inputs (labels appear
//                         once mic permission is granted)
//   currentDeviceId    -> the device actually in use
//   info()             -> JSON with sample rate / latency / settings details
//
// Mic cleanup (echo cancellation, noise suppression, auto gain) is turned OFF:
// those filters smear pitch and pump the level, which hurts detection.
//
// Dev aids (URL parameters): ?testtone=220 replaces the mic with a synthetic
// tone; ?diag=1 reports mic status to the local dev server every 2 s.

(function () {
  if (window.solfegePitch) return;

  const SILENCE_MS = 1500;

  const S = {
    state: "idle",
    error: "",
    queue: [],
    ctx: null,
    stream: null,
    node: null,
    workletInfo: null,
    devicesJson: "[]",
    currentDeviceId: "",
    _zeroSince: 0,
    _diag: { frames: 0, maxRms: 0, last: null },
  };

  S.start = function (workletSource, deviceId, wasmB64) {
    if (S.state === "running" || S.state === "starting") return;
    S.state = "starting";
    S.error = "";
    S._start(workletSource, deviceId || "", wasmB64 || "").catch(function (e) {
      S.state = "error";
      S.error = (e && (e.name + ": " + e.message)) || String(e);
      S.stop(true);
    });
  };

  S._start = async function (workletSource, deviceId, wasmB64) {
    const testHz = parseFloat(new URLSearchParams(location.search).get("testtone") || "0");
    if (!testHz) {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        throw new Error("Microphone needs a secure page (https or localhost).");
      }
      // iOS Safari 16.4+: a play-and-record session keeps our tones audible
      // with the silent switch on while the mic is open.
      if (navigator.audioSession) {
        try { navigator.audioSession.type = "play-and-record"; } catch (e) {}
      }
      const audio = {
        echoCancellation: false,
        noiseSuppression: false,
        autoGainControl: false,
        channelCount: 1,
      };
      if (deviceId) audio.deviceId = { exact: deviceId };
      try {
        S.stream = await navigator.mediaDevices.getUserMedia({ audio: audio, video: false });
      } catch (e) {
        // A remembered device that's been unplugged: fall back to the default.
        if (deviceId && (e.name === "OverconstrainedError" || e.name === "NotFoundError")) {
          delete audio.deviceId;
          S.stream = await navigator.mediaDevices.getUserMedia({ audio: audio, video: false });
        } else {
          throw e;
        }
      }
      const track = S.stream.getAudioTracks()[0];
      S.currentDeviceId = (track && track.getSettings().deviceId) || "";
      S.refreshDevices();
    }

    const AC = window.AudioContext || window.webkitAudioContext;
    S.ctx = new AC({ latencyHint: "interactive" });
    if (S.ctx.state === "suspended") await S.ctx.resume();

    const url = URL.createObjectURL(new Blob([workletSource], { type: "application/javascript" }));
    try {
      await S.ctx.audioWorklet.addModule(url);
    } finally {
      URL.revokeObjectURL(url);
    }

    const src = testHz ? S._testTone(testHz) : S.ctx.createMediaStreamSource(S.stream);
    // Shared C++ detector as WebAssembly; "?detector=js" forces the JS fallback.
    let yinModule = null;
    if (wasmB64 && new URLSearchParams(location.search).get("detector") !== "js") {
      try {
        const bin = atob(wasmB64);
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        yinModule = await WebAssembly.compile(bytes);
      } catch (e) {
        console.warn("yin.wasm unavailable, using JS detector:", e);
      }
    }
    S.node = new AudioWorkletNode(S.ctx, "solfege-pitch", {
      processorOptions: yinModule ? { yinModule: yinModule } : {},
      numberOfInputs: 1,
      numberOfOutputs: 1,
      channelCount: 1,
      channelCountMode: "explicit",
    });
    S._zeroSince = 0;
    S.node.port.onmessage = function (ev) {
      const m = ev.data;
      if (Array.isArray(m)) {
        S.queue.push(m);
        if (S.queue.length > 2000) S.queue.splice(0, S.queue.length - 2000);
        // Exact zeros = digital silence (a real mic always has some noise).
        if (m[3] === 0) {
          if (!S._zeroSince) S._zeroSince = performance.now();
        } else {
          S._zeroSince = 0;
        }
        S._diag.frames++;
        S._diag.maxRms = Math.max(S._diag.maxRms, m[3]);
        S._diag.last = m;
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

  S.isIOS = function () {
    return !!(window.solfegePlatform && window.solfegePlatform.isIOS());
  };

  S.isSilent = function () {
    return S.state === "running" && S._zeroSince > 0 && performance.now() - S._zeroSince > SILENCE_MS;
  };

  S.refreshDevices = async function () {
    try {
      const all = await navigator.mediaDevices.enumerateDevices();
      const list = [];
      all.forEach(function (d) {
        if (d.kind !== "audioinput" || d.deviceId === "default" || d.deviceId === "communications") return;
        list.push({ id: d.deviceId, label: d.label || "Microphone " + (list.length + 1) });
      });
      S.devicesJson = JSON.stringify(list);
    } catch (e) {
      S.devicesJson = "[]";
    }
  };
  if (navigator.mediaDevices && navigator.mediaDevices.addEventListener) {
    navigator.mediaDevices.addEventListener("devicechange", function () { S.refreshDevices(); });
  }

  // Sawtooth through a lowpass, gliding up and down a few semitones, with vibrato.
  S._testTone = function (hz) {
    const ctx = S.ctx;
    const osc = ctx.createOscillator();
    osc.type = "sawtooth";
    osc.frequency.value = hz;
    const t0 = ctx.currentTime;
    for (let i = 0; i < 120; i++) {
      const semis = [0, 2, 4, 5, 7, 5, 4, 2][i % 8] + (i % 3 === 1 ? 0.3 : 0); // some notes sharp
      osc.frequency.setTargetAtTime(hz * Math.pow(2, semis / 12), t0 + i * 0.8, 0.03);
    }
    const lfo = ctx.createOscillator();
    lfo.frequency.value = 5.5;
    const depth = ctx.createGain();
    depth.gain.value = hz * 0.012;
    lfo.connect(depth).connect(osc.frequency);
    const lp = ctx.createBiquadFilter();
    lp.type = "lowpass";
    lp.frequency.value = 2500;
    const amp = ctx.createGain();
    amp.gain.value = 0.2;
    osc.connect(lp).connect(amp);
    osc.start();
    lfo.start();
    return amp;
  };

  S.stop = function (keepError) {
    try { if (S.node) S.node.disconnect(); } catch (e) {}
    try { if (S.stream) S.stream.getTracks().forEach(function (t) { t.stop(); }); } catch (e) {}
    try { if (S.ctx) S.ctx.close(); } catch (e) {}
    S.node = null; S.stream = null; S.ctx = null; S.queue = []; S._zeroSince = 0;
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
      device: track ? track.label : "",
      echoCancellation: settings.echoCancellation,
      noiseSuppression: settings.noiseSuppression,
      autoGainControl: settings.autoGainControl,
      worklet: S.workletInfo,
    });
  };

  // Diagnostics (opt-in with ?diag=1): report mic status every 2 s to this
  // same server (/__diag), where it is logged. Only numbers, the state and the
  // mic's name are sent, and only to the site the page came from.
  const params = new URLSearchParams(location.search);
  if (params.get("diag") === "1") {
    setInterval(function () {
      const track = S.stream && S.stream.getAudioTracks()[0];
      const p = new URLSearchParams({
        state: S.state,
        error: S.error || "",
        ctx: S.ctx ? S.ctx.state : "none",
        device: track ? track.label : "none",
        frames: S._diag.frames,
        maxRms: S._diag.maxRms.toFixed(5),
        silent: S.isSilent() ? "yes" : "no",
        ios: S.isIOS() ? "yes" : "no",
        session: navigator.audioSession ? navigator.audioSession.type : "n/a",
        last: S._diag.last ? S._diag.last.map(function (v) { return Number(v).toFixed(3); }).join("/") : "",
      });
      S._diag.frames = 0;
      S._diag.maxRms = 0;
      fetch("/__diag?" + p.toString()).catch(function () {});
    }, 2000);
  }

  window.solfegePitch = S;
})();
