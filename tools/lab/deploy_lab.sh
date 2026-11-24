#!/usr/bin/env bash
# Deploy the web build to Sterling's Lab: https://sterling.shivoolabs.com/apps/solfegexr/
#   STERLINGS_SSH_KEY=/path/to/deploy_key bash tools/lab/deploy_lab.sh [--no-export]
# Needs Bun (runs the Lab's self-deploy script, tools/lab/deploy.ts, copied
# unchanged from the Lab repo). That script uploads its whole working folder,
# so it runs from build/lab/, which holds only sterlings-app.json and dist/.
# Commit first: a clean checkout records its commit on the server.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-/c/Godot/Godot_v4.7.2-stable_win64_console.exe}"
: "${STERLINGS_SSH_KEY:?Set STERLINGS_SSH_KEY to the Lab deploy key file}"
BUN="$(command -v bun || true)"
if [ -z "$BUN" ]; then   # winget install, before the shell has picked up the new PATH
  BUN="$(ls "${LOCALAPPDATA:-$HOME/AppData/Local}"/Microsoft/WinGet/Packages/Oven-sh.Bun_*/bun-windows-x64/bun.exe 2>/dev/null | head -1 || true)"
fi
[ -n "$BUN" ] || { echo "Bun is required: https://bun.sh"; exit 1; }
mkdir -p build
touch build/.gdignore

if [ "${1:-}" != "--no-export" ]; then
  echo "Exporting release web build..."
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
  "$GODOT" --headless --path . --export-release "Web" build/public/index.html >build/lab_export.log 2>&1
fi
for page in manual privacy; do
  mkdir -p "build/public/$page"
  cp -r "site/$page/." "build/public/$page/"
done

STAGE="$ROOT/build/lab"
rm -rf "$STAGE"
mkdir -p "$STAGE/dist"
cp sterlings-app.json "$STAGE/"
cp -r build/public/. "$STAGE/dist/"
cp tools/lab/deploy.ts "$STAGE/../lab_deploy.ts"
cd "$STAGE"
"$BUN" "$STAGE/../lab_deploy.ts"
