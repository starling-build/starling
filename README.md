# Starling

**[starling.build](https://starling.build)**

A new Linux desktop environment, whose shell, compositor, framework, and apps
are written in Swift (the framework is a full port of Flutter's Dart framework
to Swift — no Dart VM). It brings its own Wayland compositor and its own X11
server, so it runs native Wayland clients and X11 apps alike. Runs on the
Flutter engine's C core via the sibling repo **starling-engine**, and on the
Flutter→Swift framework from the sibling repo **flutter-swift**.

```
sdk   -> symlink to a flutter-swift checkout — the Flutter→Swift framework port
         (SwiftPM package "FlutterSwift"). Its own repo; ./bootstrap.sh links it.
engine -> symlink to a starling-engine checkout
shell/   the desktop shell: compositor (C Wayland server), window manager,
         dock, spaces, portals — SwiftPM package "DesktopShellApp"
apps/    first-party apps (Settings, Files, Terminal, …), one SwiftPM package each
host/    the windowed host (FlutterRunner + GLFWBridge): run a Swift Flutter app
         in an ordinary window rather than through the shell. Demos only.
build/   packaging: the Ubuntu .deb, session files, app-run/app-install tools,
         vendored flutter_assets
docs/    porting guides and design notes, including plans/
macos-compat/  research: unmodified Mach-O macOS binaries on Linux
```

**Get started:** [Install Starling](docs/INSTALL.md) ·
[User Guide](docs/USER_GUIDE.md) · [Build from source](docs/BUILDING.md)

## Status

**Early development — version 0.4.0.** The desktop boots as a real session, runs
its own compositor and apps, and installs from a `.deb` on a stock Ubuntu
26.04. It is also the work of one person and a few months, so expect rough
edges, missing pieces, and bugs. Nothing here is load-bearing for anyone yet,
and interfaces change without notice.

What follows is deliberately specific about what is and is not done, because
"a desktop environment" invites assumptions that would be wrong.

### What works

| Area | State |
|---|---|
| **Session** | Boots through the normal login path — `gdm3` → `gdm-wayland-session` → `/usr/libexec/starling-session` → `DesktopShellApp --drm`. Unprivileged: DRM master and input come from logind via `libseat`, not from running as root. |
| **Display** | DRM/KMS modeset, GBM/EGL, hardware cursor, flip-driven frame pacing, multi-output layout. Tested on AMD (Radeon 780M) and on virtio-gpu/virgl in a VM. |
| **Compositor** | ~5,700 lines of C implementing `xdg-shell`, `linux-dmabuf` (zero-copy import), `viewporter`, `fractional-scale-v1`, `pointer-constraints`, `relative-pointer`, `text-input-v3`, `presentation-time`, `primary-selection`, `idle-inhibit`, `cursor-shape-v1`, `xdg-decoration`, `xdg-activation`, `xdg-output`, `wlr-data-control`. |
| **Window management** | Floating and tiling (master-and-stack) behind one switch, spaces with a Mission Control overview, drag-move and drag-resize, a dock with running indicators and drag-to-reorder, and a Launchpad. |
| **Apps** | Settings, Files, Terminal (a real PTY), Text Editor, Calculator, App Store, Task Manager, Video Player, Image Viewer — nine first-party apps, all written against the Swift framework port. |
| **Screen recording** | The desktop records itself — whole screen or a single window's own content — to MP4 in `~/Videos`. Hardware H.264 where the machine has an encoder: the composited frame goes to it as a dma-buf, so no frame is copied through the CPU (~0.05 of a core here); a software encoder otherwise. A red dot and a running clock sit in the menu bar for the duration. |
| **Portals** | `xdg-desktop-portal` implementing `Settings`, `FileChooser` (OpenFile/SaveFile/SaveFiles, via a helper window), `ScreenCast` (the interface behind `getDisplayMedia` and OBS), `Session` and `Request`. |
| **Third-party clients** | Launch and render as native Wayland clients: Chrome, VS Code, Slack, Discord, Teams, Telegram, IntelliJ IDEA, GIMP, Blender, GNOME Web, GNOME Text Editor — covering Chromium/Electron, Qt6, GTK3, GTK4, the JetBrains Runtime's Wayland toolkit, and Blender's own GHOST, which drives the viewport (EEVEE included) through our `linux-dmabuf`. Both buffer paths are live: GPU clients via `linux-dmabuf`, software clients via `wl_shm`. Zoom runs with a caveat (below). X11 clients run against the in-tree X server (DRI3/Present). |
| **Packaging** | A 50.8 MB `.deb` that installs on a *minimal* 26.04 image, pulling 26 dependency packages; `Depends` is computed from the shipped binaries by `dpkg-shlibdeps`. |
| **Framework port** | 137 test files under `sdk/Tests`. |

### Known limitations

- **xdg_output state is sent once and never updated.** A client that asks for
  an xdg_output gets the logical position and size as they are at that moment;
  a later mode change, scale change or output hotplug does not re-send them, so
  a long-running client can be left with stale geometry. The resources are not
  tracked per output, which is what fixing it needs.
- **The portal is incomplete.** `Settings` and `FileChooser` work — GTK4 reads
  `org.freedesktop.appearance` through them, and both carry the `version`
  property clients probe first — but `Inhibit`, `Camera` and
  `Print` are absent entirely. The session bus masks the stock
  `xdg-desktop-portal` rather than letting it fill those gaps: it has no
  backend for `Starling`, so it would serve only its backend-less interfaces
  while taking `org.freedesktop.portal.Desktop` away from the shell's own
  portal, breaking the two that do work.
- **No screen lock or screensaver.**
- **Scaling is effectively pinned to 2.0.** Fractional values produced blurry
  text and are not usable yet.
- **No display-mode selection.** The session takes the connector's preferred
  mode; overriding it means editing the session launcher.
- **The third-party app runtime is opt-in and unshipped.** `app-run` expects a
  debootstrap'd runtime under `/var/lib/starling-apps`; third-party apps are
  otherwise expected to use their native packaging.
- **The App Store catalog is small, and its tiles are deliberately generic.**
  Ten entries, all of which install and launch: Chrome and VS Code were driven
  through the store's own buttons, the other eight through `app-install` and
  `app-run` — the paths those buttons invoke. Tiles use category glyphs rather
  than vendor artwork on purpose: those logos are their owners' trademarks and
  Starling ships none of them. Chrome and VS Code do show their real icons in
  the launcher and dock, read from the host at runtime; the rest fall back to a
  generic glyph, since only those two ids are wired to that lookup.
- **One catalogued app runs with a caveat.** Zoom starts but reports
  `no pactl and pacmd found` and has no audio. That is deliberate rather than a
  missing dependency: Zoom segfaults during audio init whenever `pactl` is on
  PATH on a PipeWire box with no native PulseAudio daemon, which is the stock
  Ubuntu 26.04 arrangement. Absent `pactl` it skips audio and runs; present, it
  crashes, and a working `PULSE_SERVER` does not save it. **Do not install
  `pulseaudio-utils` to "fix" this** — it trades a silent Zoom for one that will
  not start. Other libpulse apps (Chrome, Slack, Teams) do get sound; Zoom is a
  single-app exception until `pactl` can be masked for it alone.
- **No CI.** Testing is the framework's unit tests plus manual verification in
  a VM.

### Roadmap

Direction, not commitment:

- **Run the Linux apps people actually use.** The major toolkits composite
  today — Chromium/Electron, Qt6, GTK3 and GTK4 — and X11 clients run against
  the in-tree X server. The bar is that an app installed from your
  distribution simply works, so the remaining work is breadth and the rough
  edges each app exposes, not a missing toolkit.
- **Android apps**, through Waydroid. The launcher and app registry already
  carry entries for it.
- **Windows apps**, through Wine or Proton, once the Linux story is solid.
- **More hardware.** Verified on AMD and on virtio-gpu so far; Intel and NVIDIA
  next, then laptop concerns — lid, backlight, output hotplug — and HiDPI.
- **More platforms.** Distributions beyond Ubuntu 26.04, and ARM alongside
  x86-64.
- **The desktop's own basics**, so it holds up as a daily driver: notifications,
  screen lock, display settings, and enough of the framework port to build
  them comfortably.
- **Stay current with upstream Flutter.** The engine fork is arranged so
  rebasing onto a new release is ordinary `git rebase`.

## Setup

Building both halves on a machine that has neither — toolchains, `gclient`,
apt packages, timings, and the Ubuntu 26.04 workarounds — is
**[docs/BUILDING.md](docs/BUILDING.md)**. The short version follows.

Clone `starling-engine` next to this repo (a built one — see its README), then:

```bash
./bootstrap.sh            # creates the `engine` symlink -> ../starling-engine/engine
```

Every engine reference (bridge headers, `libflutter_engine.so`,
`libflutter_linux_drm.so`, `icudtl.dat`) goes through that symlink; point it at
any engine checkout with `./bootstrap.sh <path>`.

## Build

```bash
cd shell && swift build -c release          # the shell (+ sdk as dependency)
cd apps/TerminalApp && swift build -c release   # each app is its own package
```

Engine C++ changes rebuild in the engine repo (`ninja -C engine/src/out/...`);
the shell needs **no relink** — it binds only the engine's stable C API.

## Run

```bash
build/run-desktop.sh
```

Stages everything into one self-contained tree and runs the desktop from it —
the same layout the package installs, so the dev loop exercises the shipping
configuration. Needs the GPU free (no display manager or compositor). Uses the
distro's Mesa; takes the unprivileged libseat path when a seat manager is
reachable, else `sudo`. `--no-stage` reuses the existing `.stage/`.

Drive it and take screenshots with `sudo build/shell-drive.py "dock settings"
click "shot /tmp/x.png"` (run with no args for the action list).

Do not run straight out of `.build`: child apps are spawned with
`LD_LIBRARY_PATH` scrubbed and resolve libraries through their own `$ORIGIN`,
so they only work when the libraries sit next to them — which is what staging
does.

## Package

```bash
build/stage.sh [outdir]               # the assembled tree (defaults to .stage/)
build/package-desktop.sh [outdir]     # -> starling-desktop_<ver>_amd64.deb
```

`stage.sh` is the single definition of the layout; `package-desktop.sh` wraps
its output with control metadata, the polkit policy, and the session entry.
Prereqs: shell + apps built (`swift build -c release`), engine `host_release`
built. The deb installs under `/usr/lib/starling` + `/usr/share/starling` and
adds a "Starling" session to the login screen.

Packages are maintained as `Starling <dev@starling.build>` — the same project
identity every commit here uses. Use it rather than a personal address for the
`Maintainer:` field and anywhere else the project needs a contact.

## Provenance

This repo starts from a fresh snapshot, with no history before it. The code was
developed in two private repos and re-imported here: the framework port and
shell came from a working branch (`flutter_swift/` → `sdk/`,
`apps/DesktopShellApp/` → `shell/`, `apps/*` → `apps/`), the packaging tools
from a second one. Neither is public, so the pre-import history is not
reachable — everything since is in this repo's log.

The framework port lives in this repo at `sdk/` (it spent a stretch as the
separate starling-sdk repo; that history came back with it as a subtree).
It is a derivative of Flutter and keeps Flutter's licence. The C++ half
lives in
[starling-engine](https://github.com/starling-build/starling-engine), a fork of
`flutter/flutter` whose `starling` branch carries the Starling delta on top of
real upstream history.

## Credits

Starling is a small amount of new code sitting on a great deal of other
people's work. Named here with thanks — the legally required attributions are
in [NOTICE](NOTICE), but these deserve saying out loud:

- **[Flutter](https://flutter.dev)** — the engine Starling runs on, and the
  framework design `sdk/` is a port of. The embedder API is a genuinely
  well-drawn seam: it let a desktop shell supply its own surface, input and
  vsync without forking the renderer. Skia and Impeller do the drawing; Dart's
  tooling built the assets.
- **[Wayland](https://wayland.freedesktop.org) and wayland-protocols** — the
  compositor implements these. Kristian Høgsberg, Collabora, Intel, Red Hat,
  Samsung, Purism, Simon Ser, Jonas Ådahl, Kenny Levinsen and others wrote the
  protocol definitions in `shell/Sources/WaylandServer/*-protocol.c`.
- **[Mesa](https://mesa3d.org)** — EGL, GBM and the gallium drivers; every
  frame Starling puts on screen goes through it.
- **libinput, libseat/seatd, libxkbcommon, libdrm, libevdev** — Peter Hutterer,
  Kenny Levinsen and the freedesktop.org maintainers. `libseat` in particular
  is why the desktop runs unprivileged instead of as root.
- **[Swift](https://swift.org)** — the language, and the corelibs Foundation,
  Dispatch and Observation the whole tree is written against.
- **FreeType, HarfBuzz and ICU** — text rendering and internationalisation,
  bundled inside the engine.
- **[PDFium](https://pdfium.googlesource.com/pdfium/)** — PDF rendering in the
  Image Viewer.
- **Roboto Mono** and **Cupertino Icons** for the typefaces and glyphs, and
  **Daniel Lloyd Blunk-Fernández** for the Golden Gate photograph the desktop
  ships as its wallpaper, via [Unsplash](https://unsplash.com).
- **Debian and Ubuntu** — the packaging conventions this ships under, and the
  distribution it is developed and tested on.

Starling's own contribution is the DRM/KMS embedder, the Wayland compositor,
the Swift port of the framework, and the shell and apps built on top. None of
it would exist without the above.

## Licensing

Starling's own code is **Apache-2.0** ([LICENSE](LICENSE)). Two subtrees keep
their upstream license instead, because they are ports and forks rather than
original work — matching upstream keeps rebasing and contributing back
possible:

| Path | License |
|---|---|
| `shell/`, `apps/`, `build/`, `docs/`, `host/` | Apache-2.0 — © the Starling authors |
| sibling `flutter-swift` (linked as `sdk`) | BSD-3-Clause — © the Flutter Authors |
| `shell/Sources/WaylandServer/*-protocol.{c,h}` | MIT — generated from wayland-protocols XML; the upstream copyright sits in each file |
| sibling `starling-engine` | BSD-3-Clause — a Flutter engine fork |

[NOTICE](NOTICE) lists the third-party components the binaries redistribute —
the Swift runtime, the Flutter engine and its bundled libraries, fonts, and the
wallpaper. The `.deb` ships it as `/usr/share/doc/starling-desktop/copyright`.

No third-party *application artwork* is shipped: those logos are their owners'
trademarks. When such an app is installed, the launcher reads its icon from the
host at runtime via the freedesktop lookup, recorded into the app registry
at install time (`registry/`);
otherwise the shell draws its own generic glyph.

Apache-2.0 is not GPLv2-compatible, which costs nothing today: the shipped
desktop links no GPL code at all (MIT/BSD, dynamically-linked LGPL for glibc
and sd-bus, and the GCC runtime under its Runtime Library Exception).
