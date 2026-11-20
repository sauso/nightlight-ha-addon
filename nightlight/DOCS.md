# Nightlight

Nightlight is a private, self-hosted baby monitor for the cameras you already own: live video and audio, sleep tracking and optional alerts, without a subscription or a Nightlight-hosted video service. This app runs **Nightlight 0.49.0** on your Home Assistant machine.

> **Experimental.** Please [report what works and what doesn't](https://github.com/sauso/nightlight-ha-addon/issues).
>
> **Important:** Nightlight is a convenience tool, **not a safety or medical device**. Streams and alerts can fail. It must never replace adult supervision or be relied on to detect a child in distress.

## First start

1. Start the app, then select **Open Web UI**. Nightlight opens in its own browser tab at `http://<your-home-assistant-address>:4000`, not in the Home Assistant sidebar. The button uses the address you opened Home Assistant with, so it works when that is an address on your home network.

   **If you open Home Assistant through a custom domain or a reverse proxy,** the button sends you to that domain on port 4000, where nothing is listening, so the page doesn't load. Open Nightlight by the Home Assistant machine's own address instead, `http://<its-IP-address>:4000`, and bookmark it. Making your own domain reach Nightlight means adding a second reverse-proxy entry that forwards to port 4000 on the Home Assistant machine. This version can't set Nightlight's `TRUST_PROXY` setting (see [what this version can't do](#what-this-version-cant-do)), so Nightlight would see every visitor as the proxy and its per-visitor sign-in limits would apply to everyone together. Prefer the local address for now.
2. **Create the administrator account straight away, from a device you trust.** The first person to open Nightlight is the one asked to create it.
3. Follow the setup guide: your account, your child, your camera, a picture check, then the optional steps. Skip **Watch from anywhere**: the bundled Tailscale can't run here (see [Remote access](#remote-access)). The [first run](https://github.com/sauso/nightlight/blob/main/docs/installation.md#first-run) guide walks through each step.
4. **Set your home timezone** in Nightlight under **Settings → General**. Nightlight doesn't take it from Home Assistant. Until you set it, every time it shows, sleep reports and alert schedules included, is in UTC ([times and your timezone](https://github.com/sauso/nightlight/blob/main/docs/operations.md#times-and-your-timezone)).
5. Optional: turn on **Watchdog** on this app's **Info** tab. Home Assistant is expected to restart Nightlight if it stops or fails its Docker health check (`/api/health`, checked every 30 seconds; three failures in a row count). It's off unless you turn it on. The image's health check was tested with Docker; Home Assistant's watchdog behaviour has not been tested here.

## Host networking

Nightlight shares the Home Assistant machine's network address, as in Nightlight's own Docker quick start. That's what lets it find cameras, announce itself to the phone apps and send low-latency video straight to your devices. It also means Nightlight opens its ports on the Home Assistant machine itself, and Home Assistant can't move them to other numbers. This app has no **Network** settings for that reason: Nightlight always listens on port 4000.

MediaMTX's password-free loopback ports (`127.0.0.2:8554` for RTSP and `127.0.0.2:9997` for its API) are reachable by Home Assistant Core and other apps on the same host under host networking, as in the [Docker host-network quick start](https://github.com/sauso/nightlight/blob/main/docs/architecture.md).

## Ports Nightlight needs

These must be free on the Home Assistant machine. Another app that uses the same port, most likely another camera app, will clash with Nightlight.

| Port | What it's for | If something else is using it |
| --- | --- | --- |
| TCP 4000 | The web app and the phone apps | Nightlight stops during start-up. Its **Log** tab shows an `EADDRINUSE` (address already in use) error |
| UDP 8189 | Low-latency (WebRTC) video | Live video doesn't work |
| TCP 8554, 8888, 8889 and 9997 on `127.0.0.2` | Nightlight's built-in media server, reachable only from the machine itself | Live video doesn't work. An app that uses one of these numbers on every address blocks it too: 8554 is a common RTSP port for camera and restreaming apps |
| UDP 5353 | Announcing Nightlight so the phone apps can find it (mDNS) | Normally shared with other mDNS services, Home Assistant's own included (not yet tried on Home Assistant). If it can't be used, Nightlight logs one warning and carries on; connect by address instead |

## Finding cameras

The camera search listens for Thingino cameras (mDNS) and ONVIF cameras (WS-Discovery). Both use multicast, so whether it reaches your cameras depends on your network, not on Home Assistant. A camera on another VLAN or network segment usually won't be found unless your router passes that traffic between them. Add it by its address instead ([finding cameras](https://github.com/sauso/nightlight/blob/main/docs/cameras.md#finding-cameras)).

Cameras are often the least-updated devices on a network. Where you can, put them on their own network segment that only the Home Assistant machine can reach ([cameras are trusted input](https://github.com/sauso/nightlight/blob/main/docs/cameras.md#cameras-are-trusted-input)).

## Remote access

- **The bundled Tailscale can't be turned on.** Nightlight refuses to start it under host networking, and this app has to use host networking ([Tailscale details and limits](https://github.com/sauso/nightlight/blob/main/docs/remote-access.md#tailscale-details-and-limits)).
- **The other remote access routes need settings this version can't change** (`PUBLIC_HOST`, `CUSTOM_URL`, `TRUST_PROXY`; see the next section). None of them has been tried with this app.

## What this version can't do

Some Nightlight settings exist only as environment variables. This app sets `DATA_DIR` to its private storage, and Home Assistant sets `TZ`. `CLIPS_DIR` is unset, so recordings use Nightlight's default `/data/clips`. Other environment-only settings stay at Nightlight's default, and this version has no way to change them:

| Setting | Value in this app | What that means for you |
| --- | --- | --- |
| `PUBLIC_HOST` | Blank | Low-latency video from outside your home network isn't set up |
| `CUSTOM_URL` | Blank (off) | No secure address of your own for the phone apps and alert links |
| `TRUST_PROXY` | Blank | Nightlight doesn't trust client addresses sent by a reverse proxy |
| `STUN_SERVERS` | `stun:stun.l.google.com:19302` | Low-latency video asks Google's STUN server for a public address. Google can see viewers' public IP addresses and connection times, not your video. It can't be turned off in this version ([what connects to the outside](https://github.com/sauso/nightlight/blob/main/docs/networking.md#what-connects-to-the-outside)) |
| `WEBRTC_UDP_PORT` | 8189 | See [ports](#ports-nightlight-needs) |
| `PORT` | 4000 | See [ports](#ports-nightlight-needs) |
| `MDNS_ANNOUNCE` | On | Nightlight announces itself on your network for the phone apps |
| `SESSION_TTL_DAYS` | 30 | A sign-in lasts 30 days from when it was made |
| `UMASK` | 077 | New files and folders are owner-only by default; processes running as root on the host can still read them |
| `PUID` / `PGID` | 99 / 100 | The user and group that own Nightlight's files in the app's storage. Nothing to do |
| `NIGHTLIGHT_MEDIA_ISOLATION` | On | FFmpeg and the media server run as a separate user, away from the database |
| `JWT_SECRET` | Made on first start and kept in the app's storage | Nothing to do |
| `CLOUDFLARE_ANALYTICS` | Off | Not relevant unless you serve Nightlight through Cloudflare |
| `TZ` | Home Assistant's timezone | Only affects log timestamps and the names of video buffer files. Nightlight's own timezone is set in **Settings → General** |

Also not available in this version:

- **Firebase push to the Android app.** It needs two files placed in Nightlight's data folder, which Home Assistant doesn't let you reach. Pushover, ntfy and Gotify are set up inside Nightlight and should work as usual (not yet tried with this app). See [notifications](https://github.com/sauso/nightlight/blob/main/docs/notifications.md).
- **Base-image fixes between releases.** This app runs a fixed Nightlight release. Nightlight's [weekly rebuild](https://github.com/sauso/nightlight/blob/main/docs/operations.md#the-weekly-rebuild) refreshes the `latest` image with patched system packages, but this app only gets them with the next Nightlight release.

## Where your data lives

| What | Where | In this app's backup? |
| --- | --- | --- |
| The database (cameras, children, accounts, settings, sleep history) and its secrets | The app's own storage (`/data`) | Yes |
| Pictures from alerts and bed transitions | The app's own storage | Yes |
| Alert clips, recordings, wake clips, timelapses and the short rolling video buffer | The app's private storage (`/data/clips`) | No; this folder is excluded |

The database keeps camera passwords and notification tokens in plain text, so treat every backup of this app as private.

Recordings stay in the app's private storage behind Nightlight's own sign-in. They are not visible in Home Assistant's media browser. Nightlight's [retention settings](https://github.com/sauso/nightlight/blob/main/docs/recording.md#retention-and-what-deleting-removes) limit alert clips and wake clips; manual recordings remain until an admin deletes them.

The rolling buffer writes continuously for every camera by default and keeps about a minute of recent footage. Clips and the buffer use Home Assistant's own data disk, often an SD card or eMMC, so allow for disk use and wear. Nightlight checks for at least 500 MB free **before starting** a clip, recording or timelapse; it does not recheck during the write or reserve space for other cameras. If it cannot measure free space, it allows the write. The disk can still fill, causing writes and other services to fail. Check free space and adjust retention as needed.

**Uninstalling the app deletes its private `/data`, including recordings.** Make a separate copy of any recordings you want to keep before uninstalling; this app's backup excludes them.

## Backups

- **Home Assistant is expected to stop Nightlight while it backs this app up**, then start it again. Live view, alerts and sleep tracking would pause for that time. This cold-backup behaviour and its pause have not been tested on Home Assistant; the Docker-level stop was tested. The pause includes up to 30 seconds for Nightlight to stop cleanly and then its start-up.
- **Home Assistant's automatic backup starts between 04:45 and 05:45 by default** ("System optimal"), when many children are still asleep. Pick a time that suits you: **Settings → System → Backups → Configure backup settings**, then set **Time** to **Custom**. Or leave this app out of the automatic backup and back it up yourself at a quiet time.
- **This app's backup excludes `/data/clips`**, including recordings, timelapses and the rolling buffer. The database, secrets and snapshots remain in the backup. Excluding video keeps the archive smaller and the cold-backup pause shorter. It also means an app restore comes back **without recordings**: Supervisor replaces the old `/data` during restore. Keep a separate copy of any recordings you need.

## Restoring

Supervisor's source indicates that a restore removes the app's old `/data` and copies the backed-up files back as its own user, so they no longer belong to Nightlight. At every start Nightlight checks who owns its storage folder, its database and its secrets; when any of them is wrong it gives the whole folder back to itself. The app is expected to start with its database, secrets and snapshots, but **without recordings**, because the backup excludes `/data/clips`. File ownership recovery was tested by copying files the same way outside Home Assistant; a real Home Assistant restore remains unverified.

Nightlight doesn't check every file on every start, only those few. If a restored picture still won't open, restart the app once and look at its **Log** tab. If that doesn't fix it, please [open an issue](https://github.com/sauso/nightlight-ha-addon/issues): this version gives you no way to change file owners yourself. (On other installs the fix is one `chown` on the host; see [restoring](https://github.com/sauso/nightlight/blob/main/docs/operations.md#4-restoring).)

## Updates

Each version of this app runs the Nightlight release with the same number. A new version appears in Home Assistant once a new Nightlight release has been added to this repository, and its changelog is shown before you update. Nightlight's own changes are in [its changelog](https://github.com/sauso/nightlight/blob/main/CHANGELOG.md).

## Help

- The app's **Log** tab shows Nightlight's log.
- [Troubleshooting](https://github.com/sauso/nightlight/blob/main/docs/troubleshooting.md) and the rest of [Nightlight's documentation](https://github.com/sauso/nightlight/blob/main/docs/README.md).
- Problems with this app: [nightlight-ha-addon issues](https://github.com/sauso/nightlight-ha-addon/issues). Problems with Nightlight itself: [Nightlight issues](https://github.com/sauso/nightlight/issues).

## Licence

Nightlight and this app are released under the MIT licence.
