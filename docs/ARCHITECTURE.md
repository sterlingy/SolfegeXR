# Architecture

How Solfège Master XR (codename SolfegeApp) fits together, for developers joining the project. The product decisions are in [CLAUDE.md](../CLAUDE.md); running and testing are in [RUNNING.md](RUNNING.md).

Godot terms by UE equivalent: a **scene** is like a Blueprint or prefab, a **node** is like an actor or component, an **autoload** is like a GameInstance subsystem, a **signal** is like an event dispatcher, and a **Resource** is like a DataAsset.

## The big picture

```
 microphone
     │
     ▼
 PitchSource ──────── frames: (time, Hz, confidence, level), ~185/s
 (web / native / demo)        │
                              ▼
        PracticeSession ──► NoteScorer / PhraseScorer / SlideScorer ──► NoteResult(s)
        (the exercise flow)        ▲                                        │
              │                    │ targets (MIDI, start, duration)        ▼
              │              Exercise ◄── Curriculum (core lessons)    LearnerProfile
              │                    ▲  ◄── CourseBuilder (song courses)  (progress, saved)
              ▼                    │
          SynthEngine          SongAnalyzer ◄── MusicXmlReader / MidiReader ◄── song file
   (chords, reference, drone,  (key, degrees, phrases, skills, range)
    glides, backing track)
```

Screens (`scripts/ui/screens/*`) only show state and pass taps along. All the logic above runs without UI, which is why most of it is covered by headless tests.

## Pitch input: `scripts/pitch/`

`PitchSource` (abstract) gives `start / stop / poll() -> [PitchFrame] / now()`, plus device listing and "input is pure silence" detection. Everything above it is platform-independent.

| Source | Where | How |
|---|---|---|
| `WebPitchSource` | browsers | `web/pitch_bridge.js` opens the mic (echo cancellation, noise suppression and auto gain **off**), and `web/pitch_worklet.js` runs YIN on the audio thread. Results reach Godot through `JavaScriptBridge`. |
| `NativePitchSource` | desktop now; Android/XR next | `AudioStreamMicrophone` into a muted "Mic" bus with `AudioEffectCapture`, then the `YinNative` C++ detector (GDScript fallback if it isn't built). |
| `FakePitchSource` | editor, tests | A demo singer: sings scales, follows targets imperfectly, siren, or stays quiet. |
| `WavPitchSource` | tests | Plays a recorded WAV through the detector. |

**One detector, three implementations, kept in step:** `native/src/yin.cpp` (C++; meant to become WebAssembly for the web), `web/pitch_worklet.js` (the JavaScript stand-in until then), and `scripts/dsp/yin_detector.gd` (the reference). The parameters are identical (24 kHz analysis, 512-sample window, 128-sample hop, threshold 0.15), and tests check that C++ matches GDScript frame for frame.

## Scoring: `scripts/scoring/`

- `NoteScorer` scores one note. It uses a cents tolerance (±50, tightening to ±25 with mastery via `ScoringSettings`), smooths out vibrato, forgives the onset scoop, and scores by pitch class (octave errors forgiven, with a hint). It tells drift apart from a wrong scale degree, treats half-step neighbours as "low/high", and doesn't judge unsteady pitch at all (noise or speech).
- `PhraseScorer` routes frames to the note whose time window they fall in.
- `SlideScorer` scores the siren, slide-to-note and follow-the-glide exercises.
- `NoteResult.feedback()` holds all learner-facing wording. It's encouraging and specific: never "wrong".

## Music and songs: `scripts/music/`, `scripts/song/`

- `Notation` (`scripts/music/notation.gd`) turns an exercise into staff notation in the learner's key: key signature (flats on a tie), spelling (chromatic notes follow di/fi/si raised, me/te lowered), clef from the learner's range, note values split and tied at bar lines, beams, accidentals per bar, and the continuous staff position of a sung pitch.
- `MusicKey` is tonic plus mode. It converts between pitches and **scale degrees** (the neutral stored form) and renders syllables with the two toggles (La/Do-based minor, chromatic).
- The readers produce a format-neutral `Song` (parts, notes in beats, lyrics with syllabic joins, breath marks). `MusicXmlReader` makes every line its own part: each (part, staff, voice), and a voice written in chords splits into top and bottom lines, so a two-staff SATB hymn gives Soprano, Alto, Tenor, Bass. Wordless lower voices borrow the melody's lyrics. `Song.melody()` is the first part with notes.
- **Choosing a voice:** `SongAnalyzer.analyze(song, part)` analyses one part (`Result.part`); the key always comes from the melody. `App.song_analysis(id)` uses the part saved in `LearnerProfile.song_parts[id]` (by name), else the melody; `App.best_fit_part` marks the part whose printed range is closest to the learner's. The course screen's "Your part" box sets it. The ensemble stages use the other parts, shifted by the same transposition.
- `KeyFinder` uses the key signature plus a Krumhansl-Schmuckler match, with a bonus for the final note.
- `SongAnalyzer` runs the pipeline: degrees and chromatic flags, range, transposition into the learner's voice, phrases (rests, breath marks, long notes), and skill tags with the song's own examples ("the jump in bar 12").
- `SongLibrary` stores imported songs in `user://songs/`.

## Curriculum: `scripts/curriculum/`

- `Skills.Id` is the one skill model, in core order. `SkillProgress` and `LearnerProfile` store progress as JSON in `user://` (the browser's storage on web). `MasteryRules` sets the threshold: 80% of the last 20 notes, on 2 or more days.
- An `Exercise` is degree-based notes, plus how to present them: reference before, along or none; mode (notes, siren, slide-to, follow); drone, accompaniment, lyrics, and whether it needs headphones.
- `Curriculum` defines the core exercises. `CourseBuilder` builds a song's course as needed skills minus mastered ones: drills from the song, phrases, the whole song, the backing track, and ensemble stages.

## Practice flow: `scripts/practice/`

`PracticeSession` runs the phases CADENCE → LISTEN → COUNT_IN → SING → RESULT. Its timing follows the synth clock, and pitch frames are mapped from the mic clock at the downbeat. Without headphones nothing plays while the learner sings, so the mic doesn't hear the speaker. Sound reaches the speaker `SynthEngine.output_lead()` seconds after its engine time (the browser's `outputLatency + baseLatency` on the web; the generator buffer plus driver latency on desktop). `PracticeSession.audio_lead` shifts the sung part, and the practice screen shifts the bars it draws, by that much, so a note is heard as its bar meets the line. `RangeTest` and `LatencyCheck` are small siblings.

## Sound: `scripts/audio/`

- `SynthEngine` decides what plays (notes, glides, drone, cadence, sequences). On desktop it renders in GDScript. On the web it sends each note to `web/synth_worklet.js` through `WebSynthSink` and renders on the browser's audio thread, at about 1% of the GDScript CPU cost. **Keep the two voice implementations in sync.**
- **Sounds:** `SynthEngine.Timbre` (Warm, Flute, Choir, Soft organ; `LearnerProfile.timbre`, picked in Settings). Each is a list of harmonic strengths (`SynthEngine.partials`, capped at 8 kHz) read from a 1024-sample wave table, with per-sound vibrato, an optional two-voice chorus, flute breath noise and a level trim (`settings`). GDScript works out the harmonics and settings and sends them with every note, so the worklet only builds the table and renders. Noise and start phases come from a per-note seed, so both sides produce the same samples: `node tests/synth_parity.mjs` checks it after a test run. `tools/render_sounds.gd` writes a demo of each sound to `build/sounds/`. The picker is `SoundPicker` (`scripts/ui/sound_picker.gd`), used in Settings and at the top right of the practice screen; it opens its list inside the screen rather than as a popup window, because `OptionButton` popups landed in the wrong place on the web page. On the web, `App` shows the page's Manual link (`web/page_head.html`) only on the screens in `App.MANUAL_LINK_SCREENS` (home, onboarding), so the top-right corner is free elsewhere.
- `Harmonizer` picks one chord per bar from the melody for the backing track.

## App shell: `scripts/app.gd`, `scripts/ui/`

- `App` (autoload) owns the profile, the pitch source, the synth, the song catalog and navigation (`App.go(name, args)`, `App.back()`).
- Screens are built in code with the `UI` helpers for a consistent phone-first look. `PitchTrace` is the custom-drawn lanes, target bars (including glides and lyrics) and the sung line. With `view_sheet` on it draws the exercise as a scrolling staff instead (`SheetPainter`, using the Noto Music font for clefs, rests and accidentals), keeping the same clock so the sung line lands on the noteheads.
- `scenes/main.tscn` is the original sandbox, now **Free sing**.

## XR: `scripts/xr/`, `addons/`

- `XRMode` (autoload) starts and ends XR. `scenes/xr_root.tscn` (`xr_root.gd`) is the XR scene. The whole 2D app runs in a SubViewport shown on a floating panel, with the Curwen hand sign in a second window beside it. (UE comparison: a WidgetComponent in world space, driven like a WidgetInteractionComponent.)
- **Windows:** each has a grab bar under it; pinch it and move your hand to move the window, which keeps facing you. The round knob by the panel's bar recenters everything. When every window is out of sight for a second, a "Bring windows here" button appears low in front of you. The manual and privacy pages open in a third window, because a browser tab can't show inside XR. `HtmlDoc` (`scripts/ui/html_doc.gd`) converts `site/*/index.html` to RichTextLabel BBCode, so `site/*.html` is packed into both exports.
- **Pointing:** the hand or controller that pinched last drives the pointer. A pinch may wander up to 70 panel pixels and still count as a tap, released where it was pressed. A pinch and a grasp from the same gesture count as one press.
- **Web (WebXR):**
  - Godot's own WebXR renderer needs the `OVR_multiview2` WebGL extension, which Chrome on the XREAL Aura and Galaxy XR doesn't have, so it shows nothing there. Instead, XRMode uses the studio's **Shivoo XR** addon (`addons/shivoo_xr`, `scripts/webxr_stereo.gd` + `web/webxr_stereo.js`). It runs the WebXR session itself and renders each eye into its own SubViewport.
  - XRMode builds that rig in code once the browser reports `immersive-vr` support. It is XR Tools' `StartXR` (built in code so the web export doesn't carry XR Tools' scenes), the stereo node, and an `XROrigin3D` with a camera and two controllers. The rig outlives scene changes. Its origin joins the tree only while a session runs.
  - URL switches: `?xr=vr` forces VR, `?webxr=native` uses Godot's own WebXR session, and `?diag=1` logs each XR step and tap to the server (see [RUNNING.md](RUNNING.md)).
- **Native (Android XR, feature tag `xr`):** OpenXR through Godot, with a see-through blend mode when the device has one.
- **Addons:**
  - `addons/shivoo_xr` is a **git submodule** pinned to a commit of `gitlab.shivoostudios.com/shivoo-core/godot/shivooxrplugin`. Don't edit it here: changes go to the plugin's own repo, then update the pin. Its editor plugin is left off on purpose: its export step would add 1.8 MB of image-tracking script to every web build. The web preset includes `addons/shivoo_xr/web/webxr_stereo.js` by name instead. If a plugin update needs another web file, add it to the web preset's include filter.
  - `addons/godot-xr-tools` is the official 4.5.2 release, unmodified. It provides `StartXR` and its two autoloads. The web preset excludes its scenes, models and textures.
  - `addons/godotopenxrvendors` is git-ignored and used by the Android XR build.

## Web page and hosting

- `web/page_head.html` is injected into the exported page (the "Manual" link). `web/platform.js` handles iOS detection and the audio session for the silent switch. `web/file_picker.js` is the file chooser for imports.
- The export is a PWA (installable, service worker, update prompt).
- `site/` holds plain pages served next to the app: `manual/` and `privacy/`.
- Testers reach it through a Cloudflare tunnel to Caddy on the studio PC ([HOSTING.md](HOSTING.md)).

## Adding things

- **A core exercise:** add it in `Curriculum.exercises_for(skill)`. Use `add_degrees([1, 3, 5])` for notes or `add_glide([1, 5, 1])` for slides, and set `mode` for sirens and slides. Write a test that runs it through `PracticeSession` with `FakePitchSource`.
- **A built-in song:** add it to `tools/songs/make_songs.py` (the compact notation is described at the top), run it, and check the bar-check output. `songs/catalog.json` updates by itself.
- **A screen:** create `scripts/ui/screens/<name>.gd` (extends `Control`, with `setup(args)`), build it with `UI.page()`, and open it with `App.go("<name>")`. For screenshots, use the dev args in `scripts/ui/app_root.gd`.
- **Feedback wording:** edit `NoteResult.feedback()` or `SlideScorer`. Keep the tone of "you're new at this".
- **Anything audio on the web:** remember that a hidden tab pauses Godot's frame loop but not the audio threads.

## Tests

`tests/test_*.gd`, about 100 of them, run headless in about 7 s. Script errors fail a test. The runner waits one frame first, so scene tests (for example `test_xr_windows.gd`) can add nodes to the tree.
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/run_tests.gd
```
