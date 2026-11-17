#!/usr/bin/env bash
# Downloads the pinned godot-cpp release into thirdparty/godot-cpp (git-ignored).
# Pinned to the 4.5 API: GDExtensions are forward-compatible, so this loads in Godot 4.7.
# (A git submodule isn't used because git refuses nested repos on this network share
#  without extra safe.directory entries.)
set -euo pipefail
TAG="godot-4.5-stable"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/thirdparty/godot-cpp"
if [ -f "$DEST/.pinned_tag" ] && [ "$(cat "$DEST/.pinned_tag")" = "$TAG" ]; then
  echo "godot-cpp $TAG already present"; exit 0
fi
TMPD="$(mktemp -d)"
curl -sSLf -o "$TMPD/godot-cpp.tar.gz" "https://github.com/godotengine/godot-cpp/archive/refs/tags/$TAG.tar.gz"
rm -rf "$DEST" && mkdir -p "$DEST"
tar -xzf "$TMPD/godot-cpp.tar.gz" -C "$DEST" --strip-components=1
echo "$TAG" > "$DEST/.pinned_tag"
rm -rf "$TMPD"
echo "godot-cpp $TAG -> $DEST"
