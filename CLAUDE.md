# Solfège Master XR

Brand name: **Solfège Master XR** (grave accent on the second e). Code, folders and identifiers keep the old codename (`SolfegeApp`, `SolfegeXR`); the Godot `config/name` stays `SolfegeApp` because it sets the save-data folder.

Teaches adults who believe they can't sing to sing a song in key, using **movable-do solfège** and live microphone pitch feedback. Full background: [docs/HANDOFF.md](docs/HANDOFF.md). Design doc: https://claude.ai/artifact/Y2N1LR4gFB6d5oMuAsxjqu

## Working with this user
- UE5 expert, Godot beginner: explain Godot concepts briefly, by UE5 comparison when useful.
- Discuss and agree a plan before large changes.
- Local git commits only (no remote). Commit at checkpoints, only after the user approves the work.

## Product principles
- Tone is "you're new at this," never "you're bad at this." No red X; show "a little low, slide up."
- Pitch matching (sirens/slides) comes before solfège, solfège before songs.
- Progress visible over weeks. Nothing shared automatically.

## Music model
- Store notes as **scale degree relative to tonic + mode**. Display settings never touch stored data, so switching never resets progress.
- Toggle 1, minor syllables: **La-based** (default; follows key signature, Dorian starts on *re*) or Do-based (home is always *do*; me/le/te live in minor-key lessons).
- Toggle 2, chromatic notes: **Off** by default until diatonic skills are solid. Covers only notes outside the key; when off they're sung but labelled "outside the scale."
- Scoring: cents tolerance (~±50 for beginners, tightening), smooth vibrato, forgive the onset scoop, score by pitch class (octave errors forgiven, separate range hint), distinguish gradual drift from a wrong degree.
- Every song transposed to the learner's measured range. Tempo control on everything.
- Reference tone: filtered triangle / light saw with gentle vibrato (not a sine), learner's octave, optional quiet tonic drone.

## Curriculum
Core (fixed order): pitch matching → sustained notes → steps → small leaps → large leaps → phrases & songs → minor keys & modes → chromatic (if toggled) → backing track → other voices. Imported songs generate a course = skills needed − skills mastered, with drills built from the song's own material. Mastery thresholds: sensible defaults, tuned later.

Ensemble stages: solo + drone → chords only → unison guide → fading guide → second harmony line → multiple parts (Carol of the Bells finale) → later real people. **Headphones required** for backing/ensemble in v1.

Curated songs in order: Ode to Joy, When the Saints, She'll Be Coming 'Round the Mountain, Oh! Susanna (later standard verses), Auld Lang Syne, Amazing Grace, Drunken Sailor, Take Me Out to the Ball Game (1908), Shenandoah, Danny Boy, God Rest You Merry Gentlemen, Carol of the Bells (full layered, Wilhousky lyrics). Rejected: Jingle Bells, Happy Birthday, Row Row Row Your Boat.

## Sheet music import
MVP: MusicXML (Godot `XMLParser`) and MIDI (small custom parser). Later: photo OMR, always user-corrected. Pipeline: parse → key/mode detection → scale degrees + chromatic flags → range & transpose → phrase split (rests, breath marks, lyric lines) → skill tags → course.

## Architecture
- Godot 4.x, app logic in GDScript.
- `PitchSource` interface returns `(frequency, confidence)`; everything above it is platform-independent.
  - Web (now): JS AudioWorklet via `getUserMedia` with **echoCancellation, noiseSuppression, autoGainControl all off** → `JavaScriptBridge` → Godot. Do **not** use Godot's built-in web mic.
  - Native (later): C++ GDExtension, `AudioStreamMicrophone` + `AudioEffectCapture`.
- One pitch detector (YIN/pYIN) in C++, compiled to WASM and native so scoring is identical. A JS stand-in is OK until Emscripten is set up. Target latency < ~50 ms.
- Synth tone / drone: `AudioStreamGenerator`.
- Shared code with ChordMasterXR will become a Godot addon in its own repo (pinned submodule). For now, build inside this repo and split later. **Never modify ChordMasterXR** (team project).

## Platforms
1. Web until feature-complete (desktop Chrome + Chrome on Android, from week one).
2. Native Android. 3. Android XR (Galaxy XR immersive choir; XREAL Aura light lane + Curwen hand signs). 4. iOS.

Guardrails: phone-first portrait touch UI everywhere; early throwaway native Android mic latency test; detector written once in C++. `localhost` is a secure context, so the mic works without HTTPS locally (Android over LAN needs HTTPS or `adb reverse`).

## Code map
- `web/` holds the JS mic bridge and the AudioWorklet YIN detector. They ship as plain text through the export preset's `include_filter`.
- `scripts/pitch/`: `PitchSource` (abstract), `WebPitchSource`, `FakePitchSource` (demo singer for the editor), `PitchFrame`.
- `scripts/music/music_key.gd`: tonic + mode, scale degrees, syllable rendering.
- `scripts/ui/`: `PitchTrace` (custom-drawn lanes, targets, trace), `main.gd` (free-sing sandbox), `ui.gd` (shared look), `screens/*.gd` (onboarding, range_test, home, practice, course, settings, progress, free_sing). Screens are built in code.
- `scripts/app.gd`: the `App` autoload (profile, pitch source, synth, navigation via `App.go(name, args)`). Root scene: `scenes/app_root.tscn`.
- `scripts/scoring/`, `scripts/song/`, `scripts/curriculum/`, `scripts/practice/`, `scripts/audio/`, `scripts/dsp/`: scoring, import and analysis, skill model and courses, the practice flow, the synth, offline YIN and WAV.
- Dev args (app_root): `-- --profile=user://dev.json --demo --screen=home|practice-core|course:<song_id> --autostart --screenshot=out.png --wait=4`.
- How to run, test on Android, and read the debug line: [docs/RUNNING.md](docs/RUNNING.md). Dev args: `-- --demo`, `-- --screenshot=out.png`.
- Commit `*.uid` files. Godot 4.4+ uses them to keep resource references stable.
- Tests: `Godot_..._console.exe --headless --path . -s res://tests/run_tests.gd` (see docs/RUNNING.md). Run them before every commit.
- `thirdparty/` is git-ignored; fetch with `tools/fetch_godot_cpp.sh`.

## More docs
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (how it fits together, how to add things) · [docs/STATUS.md](docs/STATUS.md) (what's done and verified, what needs a person) · [docs/HOSTING.md](docs/HOSTING.md) · [docs/SONGS.md](docs/SONGS.md) · user manual and privacy page in `site/`.

## Open questions
Branding and icon · lyric versions for songs 1–10 · ensemble stage details · which ChordMasterXR code seeds the shared addon · mastery thresholds.
