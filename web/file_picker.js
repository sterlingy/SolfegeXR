// SolfegeApp file picker (web): opens the browser's own file chooser and
// hands the chosen file to Godot as base64 (JavaScriptBridge passes strings).
//
//   window.solfegeFiles.pick(accept)   open the chooser (call right after a tap)
//   window.solfegeFiles.state          "idle" | "picking" | "reading" | "done" | "cancelled" | "error"
//   window.solfegeFiles.name / .b64 / .error
//   window.solfegeFiles.take()         returns JSON {name, b64} once, then resets
(function () {
  if (window.solfegeFiles) return;
  const F = { state: "idle", name: "", b64: "", error: "" };
  const MAX_BYTES = 10 * 1024 * 1024;

  F.pick = function (accept) {
    F.state = "picking"; F.name = ""; F.b64 = ""; F.error = "";
    const input = document.createElement("input");
    input.type = "file";
    input.accept = accept || "";
    input.style.display = "none";
    document.body.appendChild(input);
    input.addEventListener("cancel", function () { F.state = "cancelled"; input.remove(); });
    input.addEventListener("change", function () {
      const file = input.files && input.files[0];
      input.remove();
      if (!file) { F.state = "cancelled"; return; }
      if (file.size > MAX_BYTES) { F.state = "error"; F.error = "That file is too big for a song (over 10 MB)."; return; }
      F.state = "reading";
      const reader = new FileReader();
      reader.onload = function () {
        const bytes = new Uint8Array(reader.result);
        let bin = "";
        for (let i = 0; i < bytes.length; i += 0x8000) {
          bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
        }
        F.name = file.name;
        F.b64 = btoa(bin);
        F.state = "done";
      };
      reader.onerror = function () { F.state = "error"; F.error = "Couldn't read that file."; };
      reader.readAsArrayBuffer(file);
    });
    input.click();
  };

  F.take = function () {
    const out = JSON.stringify({ name: F.name, b64: F.b64 });
    F.state = "idle"; F.name = ""; F.b64 = "";
    return out;
  };

  window.solfegeFiles = F;
})();
