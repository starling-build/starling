# Installing Starling

Starling ships as a single Debian package. Install it, log out, and pick
**Starling** at the login screen. This guide covers the requirements, the
install, upgrades and removal, and what to do when something does not come up.

For building from source instead, see [BUILDING.md](BUILDING.md). For using
the desktop once it is running, see the [User Guide](USER_GUIDE.md).

---

## Requirements

- **Ubuntu 26.04 LTS**, **amd64**. This is the only release the package
  targets. It may work on newer Ubuntu; it is not tested there.
- **A Wayland-capable login manager** — GDM, or LightDM/SDDM configured for
  Wayland. Ubuntu Desktop already has GDM. On Server or a minimal install you
  add one (below); the package will also pull one in if you have none.
- **Graphics**: verified on **AMD** (Radeon 780M) and on **virtio-gpu / virgl**
  in a VM. Intel and NVIDIA are not yet tested — Starling may or may not come
  up on them. See [Troubleshooting](#troubleshooting) if the screen stays
  black.
- **~130 MB** of disk for the package and its dependencies. The `.deb` itself
  is about 51 MB and pulls in roughly 26 dependency packages on a minimal
  image.
- **Bare metal or a virtual machine — not a container.** See below.

Starling runs as your ordinary user through the normal login path. It does
**not** run as root and does not replace your existing desktop — it installs
alongside it as another session you select at login.

### Containers won't work; virtual machines will

Starling *is* the display server — it takes DRM master and drives the GPU
through DRM/KMS. That needs a `/dev/dri/cardN`, a connector reporting
`connected` under `/sys/class/drm/card*-*/status`, and a real logind **seat**
for `libseat` to take DRM master from.

A **container** (Proxmox LXC, Docker, systemd-nspawn) has none of these: it
shares the host kernel and has no seat of its own. GNOME and KDE fail there
for the same reason. You'll install cleanly, reboot, and land back at a
terminal.

A **virtual machine** works. What's tested:

| Setting | Value |
|---|---|
| Display adapter | **VirtIO-GPU**, 3D acceleration (virgl) if the host supports it |
| CPU / RAM | 2+ cores, 4 GB |
| Firmware | either BIOS or UEFI |

On Proxmox specifically, create a **VM (QEMU/KVM)**, not a **CT**. The virtual
GPU is what matters — the host's GPU is not used unless you configure PCI
passthrough.

---

## Install

```bash
# 1. Make sure a Wayland-capable login manager is present. Ubuntu Desktop
#    already has GDM; on Server or a minimal install, add it:
sudo apt install gdm3

# 2. Download the package (or use the button on https://starling.build):
curl -fLO https://github.com/starling-build/starling/releases/download/v0.4.0/starling_0.4.0_amd64.deb

# 3. Install it. `apt` (not `dpkg -i`) so it also pulls the dependencies:
sudo apt install ./starling_0.4.0_amd64.deb
```

`apt install ./file.deb` is deliberate — plain `dpkg -i` installs the package
but not its dependencies and leaves you to chase them by hand.

### Log in to Starling

1. **Log out** of your current session (or reboot).
2. At the login screen, **click your name**.
3. Open the **session menu** — usually a gear or a small icon in a lower
   corner of the password box.
4. Choose **Starling**.
5. Enter your password and sign in.

The session menu only appears if a Wayland-capable login manager is running.
If you do not see it, see [Troubleshooting](#no-starling-in-the-session-menu).

### Verify it installed

```bash
dpkg -s starling | grep -E '^(Package|Version|Status)'
#   Package: starling
#   Version: 0.4.0
#   Status: install ok installed
```

The session entry the login manager reads lives at
`/usr/share/wayland-sessions/starling.desktop`.

---

## Upgrading

Download the newer `.deb` and install it the same way — `apt` replaces the
old version:

```bash
curl -fLO https://github.com/starling-build/starling/releases/download/<version>/starling_<version>_amd64.deb
sudo apt install ./starling_<version>_amd64.deb
```

The package was renamed from `starling-desktop` to `starling` in 0.2. It
declares `Conflicts`/`Replaces`/`Provides: starling-desktop`, so if you have
the old package `apt` removes it and installs the new one in a single step —
you do not need to uninstall first. Your installed-app records under
`/var/lib/starling/installed.d` are preserved across the change.

---

## Uninstalling

```bash
sudo apt remove starling        # remove the package
sudo apt purge starling         # also remove its config/data
```

Removing the package takes the **Starling** entry out of the login menu; your
other sessions are untouched. `purge` additionally clears
`/var/lib/starling`. A couple of runtime files may remain in `/tmp`
(`/tmp/xdg-starling-<uid>`, `/tmp/starling-session-*.log`); they are cleared
on reboot.

---

## Troubleshooting

The session writes a full log to **`/tmp/starling-session-<your-uid>.log`**
(find your uid with `id -u`). It is the first place to look for any startup
problem.

### No "Starling" in the session menu

The login manager is not Wayland-capable, or no login manager is running.
Install GDM and reboot:

```bash
sudo apt install gdm3
sudo systemctl enable gdm
sudo reboot
```

Confirm the session file is present: `ls /usr/share/wayland-sessions/starling.desktop`.

### Black screen, or it drops back to the login screen

Almost always the GPU or the display connector. Check the log
(`/tmp/starling-session-<uid>.log`) for the display lines:

- **`[DRM] No connected connector found`** — Starling could not find a
  connected output on the card it picked. If you have more than one GPU, point
  it at the right card:

  ```bash
  # See which cards have a connected output:
  for s in /sys/class/drm/card*-*/status; do echo "$(dirname "$s" | xargs basename): $(cat "$s")"; done
  ```

  Then set `FLUTTER_DRM_DEVICE=/dev/dri/cardN` in the session launcher
  (`/usr/libexec/starling-session`) for the card that shows `connected`.

- **No `[EGL] Initialized` line** — the GPU driver did not come up. Intel and
  NVIDIA are not yet tested; on those, a black screen is expected for now.

### It runs but an app won't launch

First-party apps (Settings, Files, Terminal, Calculator, App Store) are in the
package and should always launch. Third-party apps (Chrome, VS Code, …) must
be installed on the host first — Starling launches what is there, it does not
bundle them. Install them through the **App Store** (which uses your system's
`apt`), or with your distribution's own packaging. See the
[User Guide](USER_GUIDE.md#installing-more-apps).

### Zoom starts but has no audio

Expected in this release — and the obvious fix makes it worse. Zoom reports
`no pactl and pacmd found` because `pactl` is deliberately not installed: Zoom
segfaults during audio init whenever `pactl` is on PATH on a PipeWire system
with no native PulseAudio daemon, which is the stock Ubuntu 26.04 arrangement.

**Do not `apt install pulseaudio-utils`.** With `pactl` absent, Zoom skips audio
and runs normally; with it present, Zoom crashes at startup, and setting
`PULSE_SERVER` does not help.

Sound in other apps is unaffected — Chrome, Slack and Teams reach the host's
PipeWire/PulseAudio socket normally.

### Getting a clean log for a bug report

```bash
# Log out of Starling first, then from a console or SSH:
cat /tmp/starling-session-$(id -u).log
```

Include that, your GPU (`lspci | grep -i vga`), and whether you are on bare
metal or a VM. Issues: <https://github.com/starling-build/starling/issues>.

---

## A note on what this is

## On Windows, through WSL

Starling runs on a Windows machine inside WSL. There is no graphics device
there — none, not an empty one — so the desktop takes a different path: it
renders surfacelessly and **the RDP surface is the display**. What you connect
to is the real desktop, not a mirror of a local one.

```bash
# inside your WSL distro (Ubuntu 26.04)
sudo apt install ./starling_0.4.0_amd64.deb
starling-session
```

`starling-session` detects WSL itself and starts in display mode — you do not
pass a flag or set anything up. It prints where to connect:

**If `wsl` logs you in as root, Starling steps down to your ordinary account
by itself** and says so. Many distros have no user set up and hand out a root
shell; the desktop needs nothing root can give it, and browsers refuse to run
as root at all. If the distro has no ordinary account, Starling says that too
and carries on — browsers then run without their sandbox, and the fix is
`adduser <name>` and starting Starling as them.

```
Starling is starting in RDP display mode (this is WSL -- there is no
graphics device, so the remote screen is the display).

  From Windows:  mstsc /v:localhost:3390
  From anywhere: any RDP client, port 3390
```

**Port 3390, not RDP's usual 3389**, and deliberately: Windows' own Remote
Desktop listens on 3389, and WSL forwards localhost both ways — so a user told
to connect to 3389 would reach their Windows machine instead of this desktop,
and the failure reads as "Starling is showing me my own PC".

Override with `STARLING_RDP_PORT` and `STARLING_RDP_SIZE` if you want a
different port or resolution. `STARLING_FORCE_DRM=1` makes it take the normal
graphics path regardless, if you have somehow arranged for one.

[**Watch the walkthrough**](../ui/video/wsl-walkthrough.mp4) — install,
start, connect, use it, recorded end to end.

Starling is an **early preview** (v0.4.0). It boots as a real desktop on real
hardware and runs real applications, but it is the work of one person over a
few months — expect rough edges, missing settings, and bugs. It is not meant
to be anyone's only desktop yet. Installing it is safe and reversible: it adds
a login option and changes nothing about your existing session.
