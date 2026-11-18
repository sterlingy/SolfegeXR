# Status

Last updated 18 November 2026. The full history is in `git log`.

## Platforms

| Platform | State | Verified on |
|---|---|---|
| **Web** (main target) | Working; shared with testers through the tunnel ([HOSTING.md](HOSTING.md)) | Desktop Chrome (mic), Android Chrome (mic), iPad Pro Safari (mic, audio-session fix active) |
| iPhone (Safari) | Should match iPad; silent-switch fix in place | Not yet |
| Desktop (native Windows) | Native mic plus C++ detector working | This PC: a 220 Hz tone through the speakers detected as 220.1 Hz |
| Native Android | Next: toolchain downloads and license need approval | — |
| Android XR / OpenXR | After native Android | — |
| WebXR | Not planned; possible shortcut to an XR prototype | — |

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
| C++ detector as WebAssembly | Waiting on Emscripten download approval |

## Needs a person

- **Check melodies 2–10** in MuseScore, and choose lyric versions.
- **Carol of the Bells:** a public-domain Leontovych score, if the original arrangement is wanted.
- **iPhone test; Timing check on real phones** (Settings → Check timing).
- **Approvals:**
  - downloads for Emscripten (about 1 GB) and the Android toolchain (about 3–4 GB)
  - the Android SDK license
  - a way to install on the phone
- **Decisions:** app name and branding (replaces the placeholder icon); stable hosting address and tester login; WebXR prototype or not.

## Known limits

- The quick-tunnel address changes if the PC restarts.
- On the web, a hidden tab pauses the app. The synth goes quiet, and the exercise picks up when the tab is back.
- When someone is remoted into the studio PC, Windows can hand audio to the remote session, so the PC's own mic may be unavailable to native builds. The app shows the silent-input warning.
