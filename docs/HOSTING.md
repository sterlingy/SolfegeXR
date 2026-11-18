# Sharing builds with testers over the Internet

During development the web build is served from the studio PC through a **Cloudflare quick tunnel**:

```
testers' browsers ──https──▶ Cloudflare ──tunnel──▶ cloudflared (this PC) ──▶ Caddy 127.0.0.1:8090 ──▶ build/public
```

- **HTTPS comes from Cloudflare,** so the mic works for testers, including on phones, from any network.
- **No router changes and no open ports:** `cloudflared` makes an outgoing connection.
- **Not reachable from the studio LAN:** Caddy listens on `127.0.0.1` only, so the tunnel is the only way in. It serves only `build/public`: no folder listings, and nothing outside that folder.
- When development is done, copy `build/public` to the studio's own web server unchanged. That server must use HTTPS.

## Commands (Git Bash, from the project root)

```
bash tools/hosting/serve_public.sh               # export a release build, start server + tunnel, print the address
bash tools/hosting/serve_public.sh --no-export   # same, reusing the current build/public
bash tools/hosting/stop_public.sh                # take it offline
```

The public address is printed and saved to `build/public_url.txt`. Logs are in `build/hosting/`.

**To update testers to a new build** while the tunnel is running, re-export to the same folder; the address stays the same:
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web" build/public/index.html
```
Testers reload the page. Caddy sends `Cache-Control: no-cache`, so browsers check for new files on every load.

## Limits of the quick tunnel (fine for testing, not for launch)

- **The address is random and changes** whenever the tunnel restarts, including after a reboot. Send testers the new link from `build/public_url.txt`.
- **No login:** anyone with the link can open the app. The link is unguessable, but it can be forwarded, so treat it as semi-private.
- **No uptime guarantee:** Cloudflare's quick tunnels are meant for testing and have no service level.
- **After a reboot,** run `serve_public.sh` again. Starting it automatically would need a Windows scheduled task or service, which is a system change to decide on separately.
- **Bandwidth:** each new visitor downloads about 11 MB, the engine plus the app, from the studio connection.

## Upgrading later: stable address + tester login

With a Cloudflare account and a domain managed in Cloudflare:
1. Create a named tunnel: `cloudflared tunnel login`, then `cloudflared tunnel create solfege`, then route `solfege.<domain>` to it. The address is then permanent.
2. Add a **Cloudflare Access** application for that hostname with an email allow-list. Testers sign in with a one-time code sent to their email.
3. Run it as a Windows service (`cloudflared service install`) so it survives reboots.

## Tools

`thirdparty/caddy/caddy.exe` (Caddy v2.11.9) and `thirdparty/cloudflared/cloudflared.exe` (cloudflared 2026.11.1). Both were downloaded from the official GitHub releases and checked against the published SHA-256 digests. `thirdparty/` is git-ignored.
