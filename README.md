# Starling

**[starling.build](https://starling.build)** ·
[GitHub releases](https://github.com/starling-build/starling/releases)

Starling is an **open software factory** building world-class applications and
the shared foundation behind them. A fast terminal, an office suite, a desktop,
and a Swift SDK are part of the same project. The Linux desktop is where
Starling began; it is one of the products we build today.

Our ambition is great software that everyone can use, study, change, and build
on. **Free to use. Open source.** Starling's own code is Apache-2.0; the framework
port and engine retain their upstream licenses (see [Licensing](#licensing)).

## Applications

| Project | What it does | Explore |
|---|---|---|
| **Starling Terminal** | A fast terminal with tabs, split panes, local shells, SSH connections, and remote workspaces. Persistent sessions can outlive the connection through `starling-termd`. | [Terminal releases](https://github.com/starling-build/starling/releases/tag/terminal-v0.2.0) · [Source](apps/TerminalApp) · [Session daemon](termd/README.md) |
| **Starling Office** | Writer, Slides, and Sheets: documents, presentations, and spreadsheets. The browser apps share the Swift implementation with native builds. | [Office presentation](https://openoffice.starling.build/) · [Writer](https://writer.starling.build/) · [Slides](https://slides.starling.build/) · [Sheets](https://sheets.starling.build/) · [Build guide](apps/OfficeApp/README.md) |
| **Starling Desktop** | A native desktop with its own Wayland compositor and X11 server, built-in tools, floating and tiling windows, and dedicated agent workspaces. Familiar 2D and a living 3D city are two views of the same desktop. | [Desktop presentation](https://starling.build/desktop/) · [Install](docs/INSTALL.md) · [User Guide](docs/USER_GUIDE.md) |
| **Starling SDK** | Flutter's framework ported to Swift: widgets, rendering, painting, gestures, animation, and platform hosts, without a Dart VM. The building blocks behind our applications are open, too. | [SDK guide](sdk/README.md) · [Source](sdk/) |

The applications have different platform support and levels of maturity.
Terminal has macOS, Windows, and Linux builds; Office can be tried directly in
the browser; Desktop targets Ubuntu and Windows through WSL2. Follow each
product's guide for its supported setup. These are actively developed projects,
and features and interfaces continue to evolve.

## A shared foundation

Starling applications are written in Swift against the SDK in this repository.
Native hosts use the Flutter engine's C core through
[starling-engine](https://github.com/starling-build/starling-engine). Browser
builds use Swift WebAssembly and the skwasm renderer. Applications can run in
their own host windows or in the Starling desktop; they are not limited to a
Linux desktop session.

The desktop brings the same approach to the whole workspace: its dock, menus,
and windows are widgets in one tree. That architecture supports everyday app
use, dedicated agent workspaces, and new views such as the 3D city.

## Repository map

| Path | Contents |
|---|---|
| [`apps/`](apps/) | First-party applications, including Terminal and Office, plus desktop tools such as Files and Settings. |
| [`sdk/`](sdk/) | The Swift framework port, UI libraries, platform bindings, and examples; included in this repository. |
| [`shell/`](shell/) | Desktop shell, compositor, window management, dock, spaces, portals, and desktop views. |
| [`termd/`](termd/) | The terminal-session daemon for sessions that survive client disconnects. |
| [`host/`](host/) | Windowed application-host plumbing. |
| [`build/`](build/) | Build, packaging, browser, and platform tooling. |
| [`ui/`](ui/) | The Starling landing page and the Office and Desktop slide presentations. |
| [`docs/`](docs/) | Setup and user guides, engineering notes, and project plans. |
| [`macos-compat/`](macos-compat/) | Research into running unmodified Mach-O macOS binaries on Linux. |
| `engine` | A local symlink to a sibling `starling-engine` checkout, created by `bootstrap.sh`. |

## Development

Start with the [SDK guide](sdk/README.md) for the shared framework or the
[Office build guide](apps/OfficeApp/README.md) for native and browser builds.
Desktop setup is documented in [docs/BUILDING.md](docs/BUILDING.md); its common
commands follow. Product-specific instructions take precedence over these
Linux desktop commands.

## Desktop development

### Setup

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

### Build

```bash
cd shell && swift build -c release          # the shell (+ sdk as dependency)
cd apps/TerminalApp && swift build -c release   # each app is its own package
```

Engine C++ changes rebuild in the engine repo (`ninja -C engine/src/out/...`);
the shell needs **no relink** — it binds only the engine's stable C API.

### Run

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

### Package

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
| `sdk/` — the Flutter framework port | BSD-3-Clause — © the Flutter Authors |
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
