# Sharing builds with testers over the Internet

## Public home: Sterling's Lab

The app's permanent address is **https://sterling.shivoolabs.com/apps/solfege/**, on Sterling's Lab, the studio owner's own server for all their projects (repo `Y:\_Developer\Sterling\SterlingLabs\sterlings-lab`). The Lab's homepage lists it, using `sterlings-app.json` at this repo's root: a `static` app whose files are in `dist/`.

```
STERLINGS_SSH_KEY=/path/to/lab_deploy_key bash tools/lab/deploy_lab.sh              # export, then deploy
STERLINGS_SSH_KEY=/path/to/lab_deploy_key bash tools/lab/deploy_lab.sh --no-export  # deploy the current build/public
```

- Needs Bun and the Lab's deploy key. That key can manage every app on the Lab, so keep it off shared drives.
- `tools/lab/deploy.ts` is the Lab's self-deploy script, copied unchanged from its `deploy/self-deploy/`. When the Lab updates it, copy it again.
- That script uploads its whole working folder. So `deploy_lab.sh` runs it from `build/lab/`, which holds only the manifest and `dist/` (a copy of `build/public`), not the whole Godot project.
- Commit before deploying: a clean checkout records its commit with the release on the server.
- The Lab serves HTTPS, so the mic works. `?diag=1` reports go nowhere there; use the tunnel below for diagnostics.

The quick tunnel below is still useful for test builds that shouldn't go public yet.

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

The **user manual** (`site/manual/index.html`) is served next to the app at `<address>/manual/`. `serve_public.sh` copies it into `build/public`, and the app links to it from the home screen and Settings.

**To update testers to a new build** while the tunnel is running, re-export to the same folder; the address stays the same:
```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web" build/public/index.html
```
Testers reload the page. Caddy sends `Cache-Control: no-cache`, so browsers check for new files on every load.

## Diagnostics from a tester's device
Add `?diag=1` to the link, for example `https://….trycloudflare.com/?diag=1`. Every 2 s the page reports its mic status to this server:
- state, and the mic's name
- input level and the last pitch reading
- whether the input is exact digital silence
- whether it's an iPhone, and Safari's audio-session mode

Only those reports are logged, in `build/hosting/diag.log`. Ordinary visits are never logged.

## iPhone test (all iOS browsers are Safari underneath)
1. On the iPhone, open the link with `?diag=1`. Try it first with the **silent switch on** and no headphones.
2. Run the range test, then **Free sing**, then one practice exercise.
3. Check:
   - Are the chords and reference tones audible with the silent switch on? This needs iOS 16.4 or later.
   - Does the trace follow the singer?
   - Is playback quieter while the mic is on?
4. Then check `build/hosting/diag.log`: `session` should read `play-and-record` once the mic is on, and `level` should move when singing.

On iPhones the app shows a tip about silent mode and volume when headphones aren't set.

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
