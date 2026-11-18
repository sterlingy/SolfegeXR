#!/usr/bin/env bash
# Stop the public tunnel and the local web server started by serve_public.sh.
taskkill //F //IM cloudflared.exe >/dev/null 2>&1 && echo "Tunnel stopped." || echo "Tunnel not running."
taskkill //F //IM caddy.exe >/dev/null 2>&1 && echo "Server stopped." || echo "Server not running."
