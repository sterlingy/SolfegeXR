# Architecture

How SolfegeApp fits together, for developers joining the project. The product decisions are in [CLAUDE.md](../CLAUDE.md); running and testing are in [RUNNING.md](RUNNING.md).

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

- `MusicKey` is tonic plus mode. It converts between pitches and **scale degrees** (the neutral stored form) and renders syllables with the two toggles (La/Do-based minor, chromatic).
- The readers produce a format-neutral `Song` (parts, notes in beats, lyrics with syllabic joins, breath marks).
- `KeyFinder` uses the key signature plus a Krumhansl-Schmuckler match, with a bonus for the final note.
- `SongAnalyzer` runs the pipeline: degrees and chromatic flags, range, transposition into the learner's voice, phrases (rests, breath marks, long notes), and skill tags with the song's own examples ("the jump in bar 12").
- `SongLibrary` stores imported songs in `user://songs/`.

## Curriculum: `scripts/curriculum/`

- `Skills.Id` is the one skill model, in core order. `SkillProgress` and `LearnerProfile` store progress as JSON in `user://` (the browser's storage on web). `MasteryRules` sets the threshold: 80% of the last 20 notes, on 2 or more days.
- An `Exercise` is degree-based notes, plus how to present them: reference before, along or none; mode (notes, siren, slide-to, follow); drone, accompaniment, lyrics, and whether it needs headphones.
- `Curriculum` defines the core exercises. `CourseBuilder` builds a song's course as needed skills minus mastered ones: drills from the song, phrases, the whole song, the backing track, and ensemble stages.

## Practice flow: `scripts/practice/`

`PracticeSession` runs the phases CADENCE → LISTEN → COUNT_IN → SING → RESULT. Its timing follows the synth clock, and pitch frames are mapped from the mic clock at the downbeat. Without headphones nothing plays while the learner sings, so the mic doesn't hear the speaker. `RangeTest` and `LatencyCheck` are small siblings.

## Sound: `scripts/audio/`

- `SynthEngine` decides what plays (notes, glides, drone, cadence, sequences). On desktop it renders in GDScript. On the web it sends each note to `web/synth_worklet.js` through `WebSynthSink` and renders on the browser's audio thread, at about 1% of the GDScript CPU cost. **Keep the two voice implementations in sync.**
- `Harmonizer` picks one chord per bar from the melody for the backing track.

## App shell: `scripts/app.gd`, `scripts/ui/`

- `App` (autoload) owns the profile, the pitch source, the synth, the song catalog and navigation (`App.go(name, args)`, `App.back()`).
- Screens are built in code with the `UI` helpers for a consistent phone-first look. `PitchTrace` is the custom-drawn lanes, target bars (including glides and lyrics) and the sung line.
- `scenes/main.tscn` is the original sandbox, now **Free sing**.

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

`tests/test_*.gd`, about 90 of them, run headless in about 5 s. Script errors fail a test.
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/run_tests.gd
```
