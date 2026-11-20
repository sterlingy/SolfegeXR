# Running the pitch-trace prototype

## Getting the code
The Shivoo XR addon is a git submodule (`addons/shivoo_xr`, from the studio GitLab). Clone with it:
```
git clone --recurse-submodules <repo>
```
In an existing checkout, run `git submodule update --init`. The first fetch from GitLab asks you to sign in once. If the project is on a network share, git may refuse the submodule folder as "dubious ownership"; add it with `git config --global --add safe.directory <path to addons/shivoo_xr>`, as for the main folder.

## In the editor (no mic)
Open the project in Godot 4.7 and press F5. It uses your real microphone; turn on *Demo singer* (Free sing, or Settings → Developer) to see the trace without singing.

From a terminal:
```
Godot_v4.7.2-stable_win64.exe --path . -- --demo
```

## As a desktop program (real mic)
Running the project from the editor (F5) or as a Windows build uses the **native mic path**. Godot records the default input into a muted "Mic" audio bus, and the C++ detector (`YinNative`, see native/README.md) analyzes it. If the C++ library isn't built, a slower GDScript fallback is used. Pick the input in **Settings → Microphone**. Add `-- --demo` to use the demo singer instead.

Quick check that the mic works, without the app UI:
```
Godot_v4.7.2-stable_win64_console.exe --path . -s res://tools/mic_probe.gd -- 4
Godot_v4.7.2-stable_win64_console.exe --path . -s res://tools/mic_probe.gd -- 4 tone
```
The second version plays a 220 Hz tone through the speakers; a working mic reports a median of about 220 Hz.

## In desktop Chrome (real mic)
1. Install the export templates once: **Editor → Manage Export Templates → Download and Install**.
2. Click the **Remote Deploy** (browser) button at the top right of the editor, or press Alt+Shift+F5. Godot exports, serves the build on `http://localhost:8060`, and opens it.
3. Tap **Start** and allow the microphone. Headphones aren't needed for this screen.

`localhost` counts as a secure page, so the mic works without HTTPS.

## On an Android phone (Chrome)
1. Turn on USB debugging and plug in the phone.
2. Run the browser deploy above, so the server is up on port 8060.
3. Forward the port, so the phone's `localhost` reaches your PC:
   ```
   adb reverse tcp:8060 tcp:8060
   ```
4. In Chrome on the phone, open `http://localhost:8060/tmp_js_export.html`. The exact filename is in the address bar of the desktop tab.

Using the PC's LAN IP instead of `adb reverse` won't work: the page isn't secure there, so Chrome blocks the mic.

## Without the editor (export + serve)
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-debug "Web" build/web/index.html
python -m http.server 8060 --bind 127.0.0.1 --directory build/web
```
`.claude/launch.json` has the same server as `web-build`, for Claude's browser pane. `build/` is git-ignored.

Run `--import` first after changing scripts (`... --headless --path . --import`). On the network share, an export straight after an edit has picked up the previous version of a script.

## On XR glasses (WebXR)
1. Open the tester link on the glasses (for example the XREAL Aura's Chrome) with `?diag=1` at the end, and tap **Enter AR (glasses / headset)**.
2. The app floats in a panel about a metre in front of you, with the hand sign to its right. Point with your hand and pinch to tap. Pinch and drag up or down to scroll.
3. To move a window, pinch the pale bar under it and move your hand. The round knob by the app's bar brings all windows back in front of you. If you lose them, a **Bring windows here** button appears low in front of you.
4. To leave, tap **Exit AR** on the home screen.

URL switches: `?xr=vr` starts a VR session instead of AR, and `?webxr=native` uses Godot's own WebXR renderer (blank on the Aura; see [ARCHITECTURE.md](ARCHITECTURE.md)).

With `?diag=1`, each XR step, the frame rate, the tracked hands and every tap go to `build/hosting/diag.log` as `/__diag?xr=...` requests. To read them:
```
grep -o '"uri":"/__diag?xr=[^"&]*' build/hosting/diag.log | sed 's#.*xr=##' | python -c "import sys,urllib.parse;[print(urllib.parse.unquote(l.strip())) for l in sys.stdin]"
```

**Desktop XR preview** (no headset; the mouse points and clicks):
```
Godot_v4.7.2-stable_win64.exe --path . -- --demo --xr-preview
```

## Testing without a singer
Add `?testtone=220` to the URL, for example `http://localhost:8060/?testtone=220`, then press **Start**. Instead of the mic, a filtered sawtooth tone with vibrato steps through do-re-mi-fa-sol, and some notes are sharp on purpose. It exercises the real AudioWorklet → JavaScriptBridge → trace path, and needs no mic permission.

## If the app can't hear you
- **Settings → Microphone** lists every input. The range test, practice and Free sing screens show the same picker, with a warning, whenever the input is exact digital silence. That usually means the wrong device: a loop-back channel on an audio interface, or a VR headset's virtual mic. The choice is remembered.
- Chrome keeps its own default mic, separate from Windows: `chrome://settings/content/microphone`.
- Add `?diag=1` to the URL, and the page reports mic status (device, level, last pitch) to the server it came from every 2 s. Locally it shows in the dev server's request log; over the tunnel it goes to `build/hosting/diag.log` (see docs/HOSTING.md).
- Without headphones, nothing plays while you sing: the drone stops at the count-in, and sing-along references play first instead, so the mic doesn't hear the speakers. Turn on "I have headphones" in Settings to get the drone and guide voice while singing.

## Reading the debug line
`Hz` and `conf` show the latest estimate. `level` is input loudness: below 0.004 counts as silence. `est/s` should be about 185. `age` is how old the newest estimate is when Godot draws it. If `age` stays under about 20 ms, the trace feels instant.

## Tests
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/run_tests.gd
```
Add `-- name` to run only tests whose `file:method` contains `name`. Tests live in `tests/test_*.gd` and extend `TestCase`. The exit code is the number of failures.

`node tests/wasm_parity.mjs` checks that `web/yin.wasm` and the JavaScript fallback give the same pitch and frame count for a set of test tones. Run it after rebuilding the WASM.

## The pitch detector on the web (WebAssembly)
The web build runs the shared C++ detector (`native/src/yin.cpp`) as `web/yin.wasm`. The JavaScript version in `web/pitch_worklet.js` is the fallback when the WASM can't load. The debug info shows which one is running (`detector: "wasm"` or `"js"`). Add `?detector=js` to the URL to force the fallback for comparison.

Rebuild `web/yin.wasm` after changing the detector. It needs the Emscripten SDK; set `EMSDK` to its folder (the default is `%LOCALAPPDATA%/solfege-tools/emsdk`):
```
EMSDK=<emsdk folder> EM_CONFIG=<emsdk folder>/.emscripten bash tools/build_wasm.sh
```
`web/yin.wasm` is committed, so a normal export doesn't need Emscripten.

## The detector for Android (GDExtension)
```
cd native
python -m SCons platform=android arch=arm64 target=template_debug
```
Set `ANDROID_HOME` to the Android SDK and `ANDROID_NDK_ROOT` to its `ndk/<version>` folder first. The output goes to `bin/libsolfege.android.template_debug.arm64.so`. Use `target=template_release` for the release library.
