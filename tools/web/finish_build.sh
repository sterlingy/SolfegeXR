#!/usr/bin/env bash
# Finish an exported web build (run by the publish scripts after each export):
#   bash tools/web/finish_build.sh build/public
#
# 1. Brand name. Godot takes the page <title> and the installed-app (PWA) name
#    from the project's config/name, which stays "SolfegeApp" because it names
#    the save-data folder. The running app sets the tab title itself
#    (App._ready); this covers the moment before it loads and the installed name.
#
# 2. Fresh files in the offline cache. Godot's service worker saves the app's
#    files with plain fetches, which a browser may answer from its own HTTP
#    cache (GitHub Pages allows 10 minutes). Opened soon after a publish, the
#    new version could then be saved with the old index.pck and never offer an
#    update again. Asking with cache: "no-cache" makes the browser check with
#    the server each time (a cheap "not modified" when nothing changed).
set -euo pipefail
DIR="${1:?usage: finish_build.sh <export folder>}"
SW="$DIR/index.service.worker.js"

sed -i 's#<title>SolfegeApp</title>#<title>Solfège Master XR</title>#' "$DIR/index.html"
sed -i 's#"name":"SolfegeApp"#"name":"Solfège Master XR","short_name":"Solfège XR"#' "$DIR/index.manifest.json"

sed -i 's#cache.addAll(CACHED_FILES)#cache.addAll(CACHED_FILES.map((f) => new Request(f, { cache: "no-cache" })))#' "$SW"
sed -i 's#response = await self.fetch(event.request);#response = await self.fetch(event.request, { cache: "no-cache" });#' "$SW"

# Fail loudly if a Godot update changed any of these lines.
grep -q "<title>Solfège Master XR</title>" "$DIR/index.html"
grep -q '"short_name":"Solfège XR"' "$DIR/index.manifest.json"
grep -q 'new Request(f, { cache: "no-cache" })' "$SW"
grep -q 'self.fetch(event.request, { cache: "no-cache" })' "$SW"
