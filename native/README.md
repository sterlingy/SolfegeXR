# Native code (GDExtension)

`src/yin.h/.cpp` is the shared YIN pitch detector in plain C++17, with no Godot types. `src/yin_native.*` exposes it to GDScript as `YinNative`. `YinDetector.analyze()` uses it automatically when the library is loaded, and falls back to GDScript otherwise.

## Build (Windows, MSVC)
```
bash tools/fetch_godot_cpp.sh          # once: pinned godot-cpp into thirdparty/
cd native
python -m SCons platform=windows target=template_debug
```
Output: `bin/libsolfege.windows.template_debug.x86_64.dll`, which is git-ignored. `native/solfege.gdextension` tells Godot where to find it. The first build also compiles godot-cpp and takes several minutes; later builds are quick.

Android (later): `python -m SCons platform=android target=template_debug arch=arm64`. This needs the Android NDK.

## Web (later)
Compile `src/yin.cpp` with Emscripten into the AudioWorklet, replacing the JavaScript YIN in `web/pitch_worklet.js`. The detector code stays the same, so scores match on every platform.

## Tests
`tests/test_yin.gd` checks that the native detector matches the GDScript reference frame for frame, and that streaming in 128-sample blocks gives the same result as offline analysis. Both tests are skipped when the library isn't built.
