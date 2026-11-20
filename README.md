# Nightlight for Home Assistant

Run [Nightlight](https://github.com/sauso/nightlight), a private, self-hosted baby monitor for the cameras you already own, as an app on Home Assistant OS. (Home Assistant used to call apps "add-ons"; this is the same thing.)

> **Experimental.** This app has not yet been installed on a real Home Assistant system. Please [report what you find](https://github.com/sauso/nightlight-ha-addon/issues), whether it works or not.
>
> **Important:** Nightlight is a convenience tool, **not a safety or medical device**. Streams and alerts can fail. It must never replace adult supervision or be relied on to detect a child in distress.

## Install

[![Open your Home Assistant and add this repository.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fsauso%2Fnightlight-ha-addon)

Or add it by hand:

1. In Home Assistant, go to **Settings → Apps** and select **Install app**.
2. Open the menu at the top right and select **Repositories**.
3. Enter `https://github.com/sauso/nightlight-ha-addon` and select **Add**.
4. Find **Nightlight** in the store, under **Nightlight add-ons**, and select **Install**.
5. Read the app's **Documentation** tab, then select **Start** and **Open Web UI**.

Older versions of Home Assistant have this under **Settings → Add-ons → Add-on store**, with **Repositories** in the ⋮ menu.

**Can't see Nightlight in the store?** It's marked experimental. Home Assistant 2026.4 and later list experimental apps for everyone, with a flask icon. Version 2026.3 and earlier show them only when **Advanced mode** is on in your user profile.

## What you need

- **Home Assistant OS** on a 64-bit machine (`amd64` or `aarch64`). Apps only run on Home Assistant OS, and Home Assistant stopped supporting Supervised installations with 2025.12. On Home Assistant Container, [install Nightlight with Docker](https://github.com/sauso/nightlight/blob/main/docs/installation.md) next to it instead.
- **Cameras with an RTSP stream** that the Home Assistant machine can reach ([which cameras work](https://github.com/sauso/nightlight/blob/main/docs/cameras.md#which-cameras-work)).
- **A few free ports** on the Home Assistant machine, because Nightlight uses host networking: TCP 4000 and UDP 8189 among them. The [Documentation tab](nightlight/DOCS.md#ports-nightlight-needs) lists them all.

Nobody has measured how much CPU, memory or disk Nightlight needs per camera yet ([what has been tested](https://github.com/sauso/nightlight/blob/main/docs/requirements.md)).

## How it works

The app runs the same image as every other Nightlight install, `ghcr.io/sauso/nightlight`, pinned to one Nightlight release (now 0.49.0). Nothing is built on your machine. A new version of the app appears in Home Assistant after each Nightlight release is added here.

This first version can't change Nightlight's environment-only settings (such as `PUBLIC_HOST` or `STUN_SERVERS`) and can't run the bundled Tailscale. The [Documentation tab](nightlight/DOCS.md#what-this-version-cant-do) lists everything it leaves out.

## More

- [The app's Documentation tab](nightlight/DOCS.md): first start, ports, backups and restores.
- [Nightlight's documentation](https://github.com/sauso/nightlight/blob/main/docs/README.md), and its [Home Assistant page](https://github.com/sauso/nightlight/blob/dev/docs/home-assistant.md).
- Problems with this app: [issues here](https://github.com/sauso/nightlight-ha-addon/issues). Problems with Nightlight itself: [Nightlight issues](https://github.com/sauso/nightlight/issues).

## Licence

MIT, the same as Nightlight. See [LICENSE](LICENSE).
