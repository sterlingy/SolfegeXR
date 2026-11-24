#!/usr/bin/env bash
# Put the brand name into an exported web build:
#   bash tools/web/brand_build.sh build/public
# Godot takes the page <title> and the installed-app (PWA) name from the
# project's config/name, which stays "SolfegeApp" because it names the
# save-data folder. The running app sets the tab title itself (App._ready);
# this covers the moment before it loads and the name shown when installed.
set -euo pipefail
DIR="${1:?usage: brand_build.sh <export folder>}"
sed -i 's#<title>SolfegeApp</title>#<title>Solfège Master XR</title>#' "$DIR/index.html"
sed -i 's#"name":"SolfegeApp"#"name":"Solfège Master XR","short_name":"Solfège XR"#' "$DIR/index.manifest.json"
grep -q "<title>Solfège Master XR</title>" "$DIR/index.html"
grep -q '"short_name":"Solfège XR"' "$DIR/index.manifest.json"
