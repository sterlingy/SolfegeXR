#!/usr/bin/env bash
# Compiles the shared C++ YIN detector to web/yin.wasm (standalone, no JS glue).
# Needs the Emscripten SDK (emsdk). Default location: %LOCALAPPDATA%/solfege-tools/emsdk.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMSDK="${EMSDK:-$LOCALAPPDATA/solfege-tools/emsdk}"
EMCC="$EMSDK/upstream/emscripten/em++.exe"; [ -x "$EMCC" ] || EMCC="$EMSDK/upstream/emscripten/em++.bat"
"$EMCC" -O3 -std=c++17 -fno-exceptions -fno-rtti \
  -sSTANDALONE_WASM -sINITIAL_MEMORY=2MB -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=64KB \
  -sEXPORTED_FUNCTIONS=_yin_create,_yin_input,_yin_block_size,_yin_push,_yin_output,_yin_destroy,_malloc,_free \
  -sERROR_ON_UNDEFINED_SYMBOLS=1 --no-entry \
  "$ROOT/native/src/yin.cpp" "$ROOT/native/src/yin_wasm.cpp" -o "$ROOT/web/yin.wasm"
ls -la "$ROOT/web/yin.wasm"
