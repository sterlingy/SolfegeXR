// SolfegeApp platform helpers, evaluated by Godot at startup (web only).
//   window.solfegePlatform.isIOS()                  iPhone/iPad (all iOS browsers are Safari inside)
//   window.solfegePlatform.hasAudioSession()        Safari 16.4+ audio session API
(function () {
  if (window.solfegePlatform) return;
  const P = {};
  P.isIOS = function () {
    const ua = navigator.userAgent || "";
    return /iPhone|iPad|iPod/.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  };
  P.hasAudioSession = function () {
    return !!navigator.audioSession;
  };
  // iOS mutes web audio with the silent switch on unless the page says it is
  // playback (Safari 16.4+). The mic bridge switches to play-and-record later.
  if (navigator.audioSession) {
    try { navigator.audioSession.type = "playback"; } catch (e) {}
  }
  window.solfegePlatform = P;
})();
