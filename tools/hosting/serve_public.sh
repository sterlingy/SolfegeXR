#!/usr/bin/env bash
# Share the current build with testers over the Internet.
#   bash tools/hosting/serve_public.sh          export release build, start server + tunnel
#   bash tools/hosting/serve_public.sh --no-export   reuse the existing build/public
#   bash tools/hosting/stop_public.sh           stop both
# Prints the public https://....trycloudflare.com address (also saved to
# build/public_url.txt). That address changes every time the tunnel restarts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-/c/Godot/Godot_v4.7.2-stable_win64_console.exe}"
LOGS="$ROOT/build/hosting"
mkdir -p "$LOGS"
touch "$ROOT/build/.gdignore"   # keep the Godot editor from importing build output

if [ "${1:-}" != "--no-export" ]; then
  echo "Exporting release web build..."
  "$GODOT" --headless --path . --export-release "Web" build/public/index.html >"$LOGS/export.log" 2>&1
  bash tools/web/brand_build.sh build/public
fi

# Plain web pages served next to the app: /manual/, /privacy/.
for page in manual privacy; do
  mkdir -p "build/public/$page"
  cp -r "site/$page/." "build/public/$page/"
done

bash "$ROOT/tools/hosting/stop_public.sh" >/dev/null 2>&1 || true

echo "Starting web server on 127.0.0.1:8090..."
nohup thirdparty/caddy/caddy.exe run --config tools/hosting/Caddyfile --adapter caddyfile \
  >"$LOGS/caddy.log" 2>&1 &
sleep 2
curl -sf -o /dev/null http://127.0.0.1:8090/index.html || { echo "Server failed; see $LOGS/caddy.log"; exit 1; }

echo "Starting Cloudflare quick tunnel..."
nohup thirdparty/cloudflared/cloudflared.exe tunnel --no-autoupdate --url http://127.0.0.1:8090 \
  >"$LOGS/tunnel.log" 2>&1 &
for i in $(seq 1 30); do
  URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOGS/tunnel.log" | head -1 || true)
  [ -n "$URL" ] && break
  sleep 1
done
if [ -z "${URL:-}" ]; then echo "Tunnel didn't report an address; see $LOGS/tunnel.log"; exit 1; fi
echo "$URL" > "$ROOT/build/public_url.txt"
echo "Public address: $URL"
