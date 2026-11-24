#!/usr/bin/env bash
# Publish the web build (web version and WebAR) to GitHub Pages:
#   https://sterlingy.github.io/SolfegeXR/
#
#   bash tools/pages/publish_pages.sh              export a release build, then publish
#   bash tools/pages/publish_pages.sh --no-export  publish the current build/public
#
# GitHub can't build this project itself (its runners can't fetch the Shivoo XR
# addon from the studio GitLab), so the build is made here and pushed to the
# gh-pages branch. That branch holds only the latest build, as one commit
# replaced on every publish (force push), so old builds don't pile up in the repo.
# Repository Settings -> Pages is set to "Deploy from a branch: gh-pages / (root)".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-/c/Godot/Godot_v4.7.2-stable_win64_console.exe}"
REMOTE="$(git remote get-url origin)"
mkdir -p build
touch build/.gdignore   # keep the Godot editor from importing build output

if [ "${1:-}" != "--no-export" ]; then
  echo "Exporting release web build..."
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
  "$GODOT" --headless --path . --export-release "Web" build/public/index.html >build/pages_export.log 2>&1
  bash tools/web/brand_build.sh build/public
fi
for page in manual privacy; do
  mkdir -p "build/public/$page"
  cp -r "site/$page/." "build/public/$page/"
done

# Build the gh-pages commit in a local temp folder: Git refuses a new repo on
# the network share ("dubious ownership").
SITE="$(mktemp -d)"
trap 'rm -rf "$SITE"' EXIT
cp -r build/public/. "$SITE/"
touch "$SITE/.nojekyll"   # serve files as they are, no Jekyll processing

SRC="$(git rev-parse --short HEAD)"
DIRTY=""
[ -z "$(git status --porcelain)" ] || DIRTY=" (with uncommitted changes)"
cd "$SITE"
git init -q -b gh-pages
git add -A
git -c user.name="$(git -C "$ROOT" config user.name)" -c user.email="$(git -C "$ROOT" config user.email)" \
  commit -qm "Web build from $SRC$DIRTY"
git push -q --force "$REMOTE" gh-pages
echo "Published build of $SRC$DIRTY. GitHub Pages updates in about a minute:"
echo "  https://sterlingy.github.io/SolfegeXR/"
