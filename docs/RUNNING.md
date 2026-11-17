# Running the pitch-trace prototype

## In the editor (no mic)
Open the project in Godot 4.7 and press F5. Tap **Start**: the *Demo singer* walks up and down the scale, so you can see the trace without a browser.

From a terminal:
```
Godot_v4.7.2-stable_win64.exe --path . -- --demo
```

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

## Testing without a singer
Add `?testtone=220` to the URL, for example `http://localhost:8060/?testtone=220`, then press **Start**. Instead of the mic, a filtered sawtooth tone with vibrato steps through do-re-mi-fa-sol, and some notes are sharp on purpose. It exercises the real AudioWorklet → JavaScriptBridge → trace path, and needs no mic permission.

## If the app can't hear you
- **Settings → Microphone** lists every input. The range test, practice and Free sing screens show the same picker, with a warning, whenever the input is exact digital silence. That usually means the wrong device: a loop-back channel on an audio interface, or a VR headset's virtual mic. The choice is remembered.
- Chrome keeps its own default mic, separate from Windows: `chrome://settings/content/microphone`.
- Add `?diag=1` to the URL on localhost, and the page reports mic status (device, level, last pitch) to the dev server every 2 s. It shows up in the server's request log.
- Without headphones, nothing plays while you sing: the drone stops at the count-in, and sing-along references play first instead, so the mic doesn't hear the speakers. Turn on "I have headphones" in Settings to get the drone and guide voice while singing.

## Reading the debug line
`Hz` and `conf` show the latest estimate. `level` is input loudness: below 0.004 counts as silence. `est/s` should be about 185. `age` is how old the newest estimate is when Godot draws it. If `age` stays under about 20 ms, the trace feels instant.

## Tests
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/run_tests.gd
```
Add `-- name` to run only tests whose `file:method` contains `name`. Tests live in `tests/test_*.gd` and extend `TestCase`. The exit code is the number of failures.
