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

## Reading the debug line
`Hz` and `conf` show the latest estimate. `level` is input loudness: below 0.004 counts as silence. `est/s` should be about 185. `age` is how old the newest estimate is when Godot draws it. If `age` stays under about 20 ms, the trace feels instant.
