# SolfegeApp: Project Handoff

Paste this whole document into Claude Code (Claude desktop, Code tab) on the new machine, with the session folder set to `Y:\temp\SolfegeApp`.

---

## Instructions for Claude

You are picking up a project that was designed in an earlier conversation on another computer. Nothing has been built yet. Everything decided so far is below.

**Working style for this user:**
- An Unreal Engine 5 expert, but a beginner in Godot. Explain Godot-specific concepts briefly when they come up, often by comparison to UE5.
- Prefers to discuss before building. Propose a plan and get agreement before large changes.
- Make local git commits only (no remote yet). Commit at sensible checkpoints, and only after the user agrees with the work.

**First steps:**
1. Save the key points of this handoff to your memory, so future sessions on this machine have them.
2. Run `git init` in `Y:\temp\SolfegeApp` and add a Godot `.gitignore` (ignore `.godot/`, `*.import` caches as appropriate, and export output).
3. Create a `CLAUDE.md` in the project root summarizing the decisions below, and keep this `HANDOFF.md` in `docs/`.
4. Propose the plan for the first milestone (below) and wait for the user's OK before building it.

The full design doc lives on claude.ai: https://claude.ai/artifact/Y2N1LR4gFB6d5oMuAsxjqu. The user can open it. It may not be readable from this session, so this handoff is self-contained.

---

## The product

An app that teaches adults who believe they can't sing to sing a song in key, using **movable-do solfège** and live pitch feedback from the microphone.

- **Learner:** an adult who thinks they can't sing, and wants the confidence to sing with others.
- **Goal:** sing a song in key, in a key that fits the learner's own voice.
- **Name:** none yet. "SolfegeApp" is the working codename.
- **Relationship to ChordMasterXR:** a separate product that borrows ChordMasterXR's tech and branding. ChordMasterXR is the user's company's Godot XR guitar-chord app. It's a team project with other developers.

## Learning approach

- Most "non-singers" are untrained, not tone-deaf. The app's tone is "you're new at this," never "you're bad at this."
- **Pitch matching first:** sirens and slides to land a single note, before solfège and before songs.
- **Encouraging feedback:** no red X. Show "a little low, slide up" and let them see themselves land the note.
- Progress is visible over weeks, for example day 1 next to today.
- Privacy: nothing is shared automatically.

## Curriculum

Two tracks share **one skill model**:

**Core curriculum (fixed order):**
1. Pitch matching
2. Sustained notes
3. Steps
4. Small leaps
5. Large leaps
6. Phrases and songs
7. Minor keys and modes
8. Chromatic notes (when that toggle is on)
9. Singing with a backing track
10. Singing alongside other voices

**Generated course for an imported song** = the skills the song needs minus the skills the user has mastered. Drills use the song's own material, transposed to the user's key ("this is the jump in bar 12 of your song").

**Mastery thresholds:** start with sensible defaults, then tune over time from real learner data.

## Ensemble stages (singing with others)

1. Solo with reference tone and drone
2. Over chord accompaniment with no melody
3. Unison guide voice
4. Guide voice that fades out
5. A second voice on a different line (harmony)
6. Several parts at once (Carol of the Bells is the finale)
7. Later: real people

Parts can come from the other staves of a MusicXML file. **Headphones are required** for backing and ensemble stages in v1, because the mic picks up the backing audio.

## Solfège settings (two independent toggles)

| Toggle | Options | Default |
|---|---|---|
| Minor-key syllables | La-based / Do-based | La-based |
| Chromatic notes | On / Off | Off until diatonic skills are solid |

- Store notes neutrally as a **scale degree relative to the tonic, plus the mode**. The toggles only change how syllables are rendered, so switching never resets progress.
- La-based means syllables follow the key signature (Dorian starts on *re*). Do-based means the home note is always *do* (Dorian is do–re–me–fa–sol–la–te).
- Do-based minor syllables (me, le, te) belong to the minor-key lessons, **not** to the chromatic toggle.
- The chromatic toggle covers only notes *outside* the key. With it off, those notes are still sung but marked "outside the scale," with no syllable drill.
- The user chooses at onboarding and can change it in settings.

## Curated songs (in order)

1. Ode to Joy: stepwise motion, the first song
2. When the Saints Go Marching In: narrow range
3. She'll Be Coming 'Round the Mountain: repeated notes, group sing-along
4. Oh! Susanna: steps plus small leaps (use the later standard verses, not the 1848 original)
5. Auld Lang Syne: sol→do leap, a group song
6. Amazing Grace: pentatonic, sustained notes
7. Drunken Sailor: minor/Dorian, tests the minor setting
8. Take Me Out to the Ball Game: chromatic notes (1908 lyrics)
9. Shenandoah: long phrases, breath control, wide range
10. Danny Boy: wide range, the graduation song
11. Carol of the Bells: the **full layered version**, last. Uses Peter Wilhousky's English lyrics for now (the user said not to worry about legal issues yet).

The user rejected Jingle Bells, Happy Birthday, and Row, Row, Row Your Boat. They are still choosing lyric versions for songs 1–10.

## Practice experience

- **Range test** first. Every song is transposed to fit the learner's voice.
- **Key setup:** a tonic drone or a I–IV–V–I cadence, then do–mi–sol–do sung back.
- **Tempo control is required:** slow practice speeds for every exercise and song.
- **Reference audio:** a synth tone for now (a recorded human voice comes later). Don't use a pure sine wave; use a filtered triangle or light sawtooth with gentle vibrato, played in the learner's octave, with an optional quiet tonic drone.
- **Display:** a live pitch trace scrolling over horizontal lanes labeled with syllables, not note names.
- **Scoring:** tolerance in cents (about ±50 for beginners, tightening over time). Smooth out vibrato, forgive the scoop at the start of a note, score by pitch class (octave errors forgiven) with a separate range hint, and tell gradual drift apart from a wrong scale degree.

## Sheet music import

- **MVP:** MusicXML (Godot's `XMLParser`) and MIDI files (a small custom parser; Godot has no .mid reader).
- **Later:** photo scanning (OMR), always shown to the user to correct before use.
- **Analysis pipeline:**
  1. Parse the file.
  2. Detect key and mode (key signature plus a key-finding algorithm).
  3. Convert notes to scale degrees and flag chromatic notes.
  4. Measure the range and transpose to the learner's voice.
  5. Split into phrases at rests, breath marks and lyric lines.
  6. Tag the skills the song needs.
  7. Generate the course.

## Technical architecture

- **Engine:** Godot 4.x. App logic in GDScript.
- **`PitchSource` interface** returns (frequency, confidence). Everything above it is shared across platforms.
  - **Web backend (decided):** a JavaScript AudioWorklet using `getUserMedia` with **echoCancellation, noiseSuppression and autoGainControl turned off**. Pitch values pass into Godot through `JavaScriptBridge`. Don't use Godot's built-in web mic.
  - **Native backend (later):** a C++ GDExtension with mic input through `AudioStreamMicrophone` and `AudioEffectCapture`.
- **One shared pitch detector** (YIN/pYIN) written in C++, compiled to WebAssembly for web and to native code for the other platforms, so scoring is identical everywhere. Until Emscripten is set up, a JavaScript version may stand in. Target latency is under about 50 ms.
- **Synth tone and drone:** `AudioStreamGenerator`.
- **Shared module with ChordMasterXR:** a Godot addon in its own repo (music theory, UI and branding kit, later the XR and hand-tracking setup), used by this app as a pinned git submodule. **ChordMasterXR itself must not be touched.** It's a team project. If the team adopts the addon later, it goes in as a vendored copy, by team agreement, on a branch. The company owns all the ChordMasterXR code, so reusing it is cleared. The shared addon is not set up yet; for now, start inside this repo and split it out later.

## Platforms and roadmap

1. **Web first, until all functionality is complete.** Test in desktop browsers and in Chrome on Android.
2. **Native Android phone.**
3. **Android XR:** the Samsung Galaxy XR headset (fully immersive, a virtual choir) and XREAL Aura glasses (optical see-through, hand tracking, a light solfège lane, Curwen hand signs).
4. **iOS.**

**Later:** photo OMR and a recorded human voice.

**Guardrails for web-first:**
- Design every screen phone-first (portrait, touch-friendly), even in the desktop browser.
- Test the web build in Android Chrome from week one.
- Do a throwaway native Android mic test early to measure latency.
- Write the pitch detector once in C++.

## Tools

- Godot 4.x plus the web export templates
- Chrome (desktop and Android)
- MuseScore (free) for MusicXML
- Emscripten (later, for C++ to WASM)
- Blender isn't needed for the web version; it's for the XR phase later.
- Serving on `localhost` counts as a secure context, so the mic works without HTTPS.

## First milestone (propose a plan, then build after approval)

**Web pitch-trace prototype:** one screen. The mic goes through the JavaScript AudioWorklet (cleanup off) to `JavaScriptBridge` into Godot, which draws a live line scrolling over solfège lanes for a chosen key. It must run in desktop Chrome and in Chrome on an Android phone, in a phone-shaped portrait layout. If it feels responsive, the rest is content and UI.

## Open questions

- App name
- Lyric versions for songs 1–10 (the user is choosing)
- Exact design of the ensemble stages
- Which ChordMasterXR code seeds the shared addon first
- Exact mastery thresholds (to be tuned over time)
