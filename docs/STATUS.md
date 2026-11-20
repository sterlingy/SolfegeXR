# Status: Solfège Master XR

Last updated 19 November 2026. The full history is in `git log`.

## Platforms

| Platform | State | Verified on |
|---|---|---|
| **Web** (main target) | Working; shared with testers through the tunnel ([HOSTING.md](HOSTING.md)) | Desktop Chrome (mic), Android Chrome (mic), iPad Pro Safari (mic, audio-session fix active) |
| iPhone (Safari) | Should match iPad; silent-switch fix in place | Not yet |
| Desktop (native Windows) | Native mic plus C++ detector working | This PC: a 220 Hz tone through the speakers detected as 220.1 Hz |
| Native Android | Detector library built (`bin/libsolfege.android.template_debug.arm64.so`; release build not yet); APK via `tools/android/build_apk.ps1`, run from your own PowerShell | — |
| Android XR / OpenXR | After native Android; APK not yet built with the XR addons | — |
| **WebXR** (AR on glasses) | Working through the Shivoo XR addon's two-pass stereo | XREAL Aura (Chrome 157): `immersive-ar`, steady 72 fps, both hands tracked, pinch to tap, windows moved and recentered, manual window read (19 Nov 2026) |

## Features

| Area | State |
|---|---|
| Pitch trace, scoring, feedback | Done |
| Range test, key setup, tempo control | Done |
| Sirens and slides (pitch matching) | Done |
| Core curriculum (10 skills), mastery, progress over days | Done; thresholds are defaults to tune |
| 11 curated songs | Done, but melodies 2–10 are drafts to check ([SONGS.md](SONGS.md)); Carol is an original layering, not Leontovych's score |
| Song import (MusicXML, MIDI), song courses | Done |
| Lyrics display | Done; no built-in songs have lyrics yet |
| Backing track (chords follow the melody) | Done; needs headphones |
| Ensemble stages (guide, fading guide, other parts) | Basic version done; needs headphones |
| Web synth (AudioWorklet), web mic (AudioWorklet YIN) | Done |
| Mic picker, silent-mic warning, no speaker bleed without headphones | Done |
| Installable app (PWA) with update prompt | Done (placeholder icon) |
| Timing check | Done; real device numbers not measured yet |
| User manual, privacy page | Done (`/manual/`, `/privacy/`) |
| C++ detector as WebAssembly | Done: the web build runs `web/yin.wasm`, with the JS detector as fallback (`?detector=js`); matches JS exactly (`node tests/wasm_parity.mjs`) |
| XR: app panel, hand-sign window, movable windows, recenter | Done (web); every button responds to an XR tap (checked in the desktop preview) |
| XR: manual and privacy in their own window | Done |

## Needs a person

- **Check melodies 2–10** in MuseScore, and choose lyric versions.
- **Carol of the Bells:** a public-domain Leontovych score, if the original arrangement is wanted.
- **iPhone test; Timing check on real phones** (Settings → Check timing).
- **Approvals:**
  - a way to install on the phone
- **Decisions:** branding and icon (the app name, Solfège Master XR, is decided; the icon replaces the placeholder); stable hosting address and tester login.

## Known limits

- The quick-tunnel address changes if the PC restarts.
- In AR, **Import a song → Choose a file** opens the browser's file picker behind the AR view, and the "A new version is ready" bar reloads the page, which ends AR. Use both outside AR for now.
- In AR, the manual's one diagram shows as its caption only, and links to other websites do nothing.
- On the web, a hidden tab pauses the app. The synth goes quiet, and the exercise picks up when the tab is back.
- When someone is remoted into the studio PC, Windows can hand audio to the remote session, so the PC's own mic may be unavailable to native builds. The app shows the silent-input warning.
