# starling-desktop — desktop, display, apps and compositor guide

Split out of the repo `CLAUDE.md` (2026-11-21) so sessions that never touch the desktop
(Office, Word, Slides, Sheets work) do not load it on every call. Read it before running,
deploying or changing the desktop shell, the display path, Wayland, the apps or iOS.

## Run, display, iOS, package

- Run: `build/run-desktop.sh` — stages into `.stage/` then runs from there.
  Drive/screenshot with `sudo build/shell-drive.py …` (each action is **one**
  argv element: `"shot /tmp/x.png"`, not `shot /tmp/x.png`).
- **This dev box has a real display. Never force a connector on it.** It is a
  laptop: `eDP-1` is its own panel (AUO, 2560x1600, scale 2) and there is
  usually a Dell P2715Q on `HDMI-A-1` (3840x2160) as well. Both are on the AMD
  680M, both hand out a real EDID, and `build/run-desktop.sh` finds them on its
  own — **nothing here needs the synthetic display below.** Use that recipe only
  where `grep -l '^connected' /sys/class/drm/card*-*/status` comes back empty.
  Three rules, each paid for in a real screen going dark:
  - **Never write `off` to a connector's `status`, and never write anything to
    `eDP-1`'s.** `off` is `DRM_FORCE_OFF`: the output blanks for every process
    on the machine and stays blanked — no timeout, no reversion when the shell
    exits. Only `echo detect` on that same file, or a reboot, undoes it. A
    session forced `eDP-1` off to "keep it out of the scan", left it that way,
    and the user's laptop screen was dead until they rebooted. `eDP-1` is the
    screen the person using this machine is looking at.
  - **Read an EDID with `cat`, never `stat`.** `.../edid` is a sysfs *bin*
    attribute and always stats as **0 bytes**, on a perfectly good panel —
    misreading that as "no EDID" is what started the above. Use
    `cat /sys/class/drm/card2-eDP-1/edid | wc -c` (128 or 256 on a live
    output) and `wc -l < .../modes`; the honest failure signal is `dmesg`'s
    `No EDID found on connector: …`.
  - **Card numbers move — never hardcode one.** They follow probe order: today
    `card2` is the AMD 680M (`0000:73:00.0`) and owns every connector, `card1`
    is the NVIDIA 3050. Both `run-desktop.sh` and `build/session/starling-session`
    scan for the first *connected* connector, and fall back to `/dev/dri/card0`
    when they find none — which does not exist here, and on a hybrid laptop is
    the **displayless** dGPU. The error then reads `Failed to open
    /dev/dri/card0` rather than "no display".
- **Running headless — for a box with no monitor at all.** With every connector
  `disconnected` and zero modes, the shell dies at `fl_drm_view_create`. Force a
  connector on and hand it an EDID; the real GPU then programs a real CRTC and
  scans out into memory, so this is the ordinary path (real EGL/GBM, real page
  flips), not an emulation — and `shell-drive.py` screenshots work unchanged.
  Pick a connector that has nothing plugged into it — an unused HDMI/DP port,
  never the panel:

      python3 build/tools/mkedid.py 4k > /tmp/edid.bin   # or 1080p
      CARD=card2; CONN=HDMI-A-1                          # verify, don't assume
      C=/sys/kernel/debug/dri/$(basename $(readlink -f /sys/class/drm/$CARD/device))/$CONN
      echo detect | sudo tee /sys/class/drm/$CARD-$CONN/status   # re-probe
      sudo dd if=/tmp/edid.bin of=$C/edid_override bs=128 count=1
      echo on | sudo tee /sys/class/drm/$CARD-$CONN/status

  **Revert it in the same session** — `echo detect | sudo tee
  /sys/class/drm/$CARD-$CONN/status` — rather than leaving a machine forced.
  (Both settings live in debugfs/sysfs, so a reboot also clears them, but that
  is the user's reboot, not yours.) The synthetic blob is `LNX`/`Starling VD`
  and declares the same 60x34cm as a 27" 4K panel, so it impersonates a real
  Dell convincingly in every tool that shows resolution — check the
  manufacturer bytes, not the mode list, when you need to know which you are
  looking at.
  **Order matters, twice over.** Writing `detect` to the sysfs `status` file
  *clears* the force, so the EDID goes first and the force second — the other
  way round reports `disconnected` with no hint why. And a connector that is
  *already* forced on caches its mode list: writing a new EDID over it changes
  nothing until you cycle through `detect`, which is why the leading line is
  there and why swapping 1080p for 4K appears to silently fail without it.
  The EDID is what produces the mode list at all: forced on without one, the
  connector goes `connected` with **zero modes** and fails exactly like no
  display. The declared physical size drives `DeriveScale`, so `4k` (a 27"
  panel, ~163 dpi) comes up at **1.5x — 2560x1440 logical**, which is also the
  cheapest way to exercise the fractional-scale path.
  `vkms` looks like the obvious answer and is not — it has no render node, and
  the shell opens **one** device for both GBM/EGL and KMS.
- **iOS** → `build/ios-app.sh [app] [--run]`, which builds, assembles a real
  `.app` and can install and launch it on a simulator. It is `stage.sh`'s
  counterpart and exists for a stronger version of the same reason: an iOS app
  cannot run out of `.build` at all — a bare Mach-O is not an app there, the
  loader only follows `@rpath` into the bundle, and the engine finds its assets
  through `NSBundle`. Needs an iOS engine first:

      cd engine/src
      ./flutter/tools/gn --ios --simulator --simulator-cpu arm64 --no-lto
      ninja -C out/ios_debug_sim_arm64 \
          flutter/shell/platform/darwin/ios:universal_flutter_framework \
          flutter/lib/ui/swift:swift_bridge

  **`STARLING_IOS=1` is an environment variable and cannot be a `#if`.** A
  `Package.swift` is compiled and run on the *host*, so `#if os(iOS)` is false
  there even mid-cross-compile, and a manifest that tests it silently builds
  the macOS configuration. Sources are the opposite — `#if os(iOS)` in a
  `.swift` file under `Sources/` is evaluated for the target and is the right
  spelling there. Both manifests (`sdk/` and the app's) must agree on the
  variable, because it picks the engine out-directory each links against.
- Package: `build/package-desktop.sh` → .deb. It consumes `build/stage.sh`, which
  is the **single definition of the layout** — change assembly there, never in
  the packager alone. The session launcher, its `.desktop`, the polkit policy
  and the NetworkManager drop-in are files in `build/session/`, installed
  verbatim; edit them there and never re-inline them as heredocs, or a distro
  package built from this tree ships a stale copy of the launcher.
**"Deploy" means: build, install, and run it — end to end, without asking.**
The dev box is the assistant's machine to drive; there is no user session on it
to protect and no separate operator to confirm with. Deploy is four steps:

1. Build (shell + apps release, engine host_release if the engine moved).
2. **Stop** whatever is running — `gdm` if active, and any live
   `DesktopShellApp` (`pkill -x DesktopShellApp`; `pkill -f` matches its own
   `bash -c` line).
3. Install the .deb — `dpkg -i`, adding `--force-all` if it balks. A rebuild at
   the same `VER` is the normal case, not an error: `dpkg -i` reinstalls over
   an identical version, so **do not** stop to ask about the version string.
4. Start it again — `systemctl start gdm` (equivalently `restart`, which folds
   in step 2). This only works because GDM is set to autologin: with a bare
   greeter it parks there and the shell never starts, so a deploy that ends at
   `start gdm` would look done while nothing ran. On this box that is
   `AutomaticLogin = starling` in `/etc/gdm3/custom.conf`, plus
   `Session=starling` in `/var/lib/AccountsService/users/starling`. Both are
   machine-local, not repo state — on a fresh box, set them or start
   `LIBSEAT_BACKEND=seatd /usr/libexec/starling-session` directly. GDM is
   deliberately left `disabled` at boot; it is started on demand.

Do not stop after installing to report that "the running session is still the
old code" and offer to restart it. Restarting *is* the deploy. Likewise, do not
hold a deploy for `test/vm.sh` — that gate is for releases (and for session or
privilege-path changes), never for putting a build on the dev box.

**Always run from the staged tree, never straight out of `.build`.** Child apps
are spawned with `LD_LIBRARY_PATH` scrubbed (`STARLING_CHILD_HOST_GL`) and
resolve libraries through their own `$ORIGIN`/RUNPATH only, so they work solely
when the libraries sit beside them — exactly what staging (and the package)
arranges. A `.build`-relative layout appears to work right up until a child app
dies with `libflutter_engine.so: cannot open shared object file`.

## Apps are data, not code

**The App Store is Flathub, and shows nothing else.** Its pages — Discover
(search, popular, trending), Installed, and one shelf per Flathub category —
are all filled from Flathub, and it installs through `app-install --flatpak`; the shell discovers what is installed from the
Flatpak exports directory. Do not add a catalog record plus hand-written
apt/deb/tarball recipes for an app that is on Flathub — that was the old
model, and its recipes rotted. The catalog is now our own apps, Android apps,
WeChat, and a few host entries the store does NOT list: Chrome, VS Code,
IntelliJ (the workspace and agent features drive them directly, and a
sandboxed editor cannot see host toolchains) and Ubuntu's App Center. Those
are launcher and dock entries, installed from the command line with
`app-install <id>`. Follow-up: sandboxed apps reach the portal on the regular
user bus, so our portal backend has to serve that bus for file dialogs and
screen sharing to work on a clean install.

Adding a curated app is **one file**: `registry/catalog.d/<id>.app` (plus a
launch recipe in `build/app-run.sh` and an install recipe in
`build/app-install.sh` if it is a third-party host app). Never add an app id to a table in the shell
or the store — there are no such tables any more, and reintroducing one is how
this drifted the first time: an app was in seven tables and missing from two,
so it launched but had no dock icon and no real icon.

- `registry/catalog.d/*.app` — shipped, read-only. Name, tile colour, glyph,
  dock position, store copy, install/launch recipe names, the `.desktop`
  entries to read, the window classes its windows report. Read by the shell's
  launcher and dock, the App Store, and `app-install`.
- `/var/lib/starling/installed.d/<id>.app` — written by `app-install` on a
  successful install, deleted on removal. Carries what only exists once the
  app is on disk: its `.desktop` file, `StartupWMClass`, icon, version. The
  shell watches this directory (inotify), so an install lights up the launcher
  and dock with no relogin.
- Debug it with `app-install --record <id>`, which re-resolves and rewrites one
  record without installing anything (`STARLING_APP_RECORDS=<dir>` to test
  unprivileged), then `cat` the result.

**Window → app identity is `app_id`, never the title.** A window's
`xdg_toplevel.set_app_id` matches the `StartupWMClass` in the app's `.desktop`
entry; that pairing exists for exactly this purpose and `app-install` records
it. Title matching cannot work in general — IntelliJ's project window is
titled `untitled – Main.java`, with nothing app-shaped in it — so it is opt-in
per record (`TitleMatch=`) and only for windows that carry no app_id at all:
Zoom on the in-tree X server, WeChat inside rootful Xwayland, and Waydroid,
which renders every Android app into one window.

## Standing directions (desktop)

## Standing directions

- **The desktop has STYLES, and which one you are writing for decides the
  question.** A style is a complete look the user picks at runtime — macOS
  (the default) and Windows Fluent today, more later. It is defined in
  `shell/Sources/DesktopShellApp/Utils/ShellStyle.swift` as three separable
  things: a `ShellTheme` colour pair, a `ShellMetrics` layout set, and a
  `ShellChrome` that decides which surfaces exist and where. Adding a style is
  one file plus one entry in `ShellStyles.all`; there is deliberately no
  `if style == …` anywhere else in the shell, and adding one is a bug.
  - **Shell chrome** is whatever the active style says. The macOS half lives
    in `DesktopShell.swift` as the `macos*` builders; the Fluent half is
    `shell/Sources/DesktopShellApp/Fluent/`. New chrome means an entry in
    BOTH, or an honest note in `FluentChrome` saying which macOS surface it
    still falls through to.
  - **Apps are still macOS-only**, and that is a real constraint rather than a
    preference: `FluentApp`'s scaffold traps on mount as a DMA-BUF child
    (`apps/FileExplorerApp/.../main.swift:14`). Until that is fixed, every app
    shell is `MacosApp`, app UI goes through the `Macos*` controls and
    `CupertinoIcons`, and a Fluent widget in `apps/` is a bug.
  - If the `Macos*` control you need is missing or a stub, implement it in
    `sdk/` rather than reaching for the Fluent one — that is where `MacosMenu`
    and `MacosScrollbar` came from. The Fluent name is often the one that
    autocompletes (`Slider`, `MenuFlyout`), and `MacosSlider` was a
    display-only stub for a while, which is how Fluent sliders once leaked
    into the control center.
  - **`grep Fluent` is no longer the check**, and nothing loud replaces it:
    `MacosApp` installs a `FluentTheme` internally, so a misplaced Fluent
    widget renders happily instead of failing. The check now is by
    DIRECTORY — Fluent widgets belong under `shell/…/Fluent/` and nowhere
    else in `shell/`, and nowhere at all in `apps/`.
  - Colours come from `shellTheme`, never from a literal. `accentInk` in
    particular is not a synonym for white: Fluent's dark accent is a light
    blue that takes BLACK glyphs, and `Color(0xFFFFFFFF)` on an accent fill is
    legible in one style and invisible in the other.
- **Wayland only.** Do not read, modify, or reference `X11Server/` or X11 launch
  paths unless explicitly asked.
- **No security hardening on the app runtime** (`build/app-run.sh` is an app
  environment, not a sandbox; its bwrap flags are load-bearing for the runtime).
## Traps: runtime and session

- **Dev mode runs third-party clients as ROOT; a real session does not.** The
  shell under `run-desktop.sh` owns the Wayland socket as root, so clients have
  to be root too — but GDM starts apps as the user, so anything you conclude
  about a third-party app from the dev box may be an artifact. Three "bugs"
  chased this way turned out to be exactly that: Teams died on
  `FATAL: The SUID sandbox helper binary ... is not configured correctly`
  (Chromium refuses the setuid path as root), Spotify started seven processes
  and never drew a window (dconf could not write in the root-owned
  `XDG_RUNTIME_DIR`), and Teams' earlier `SIGILL` did not reproduce at all.
  **Test user-facing app behaviour in the VM** (`test/vm-harness/`, apps run as
  `tester` through a real GDM login); use the dev box for GPU-specific
  questions — that is what confirmed the GTK4 crash is not a virgl artifact.
- **Root mode also HIDES bugs, not just invents them** — and those are worse,
  because the dev box says the feature works. `main.swift` pinned the portal's
  bus address only under `getuid() == 0`; unprivileged it passed nil, so sd-bus
  honoured the inherited `DBUS_SESSION_BUS_ADDRESS` and the portal claimed
  `org.freedesktop.portal.Desktop` on the user's real `/run/user/<uid>/bus`
  instead of the session's `$XDG_RUNTIME_DIR/bus` that `app-run` points every
  client at. The name was then unowned on the session bus, so the first client
  request D-Bus-activated the stock `xdg-desktop-portal` there, which has no
  `Starling` backend and therefore no FileChooser — every file dialog in every
  Chromium/Electron/GTK app broke. It worked perfectly under `sudo`. **When a
  shipping path differs from the dev path by a privilege check, test the
  unprivileged one**: `LIBSEAT_BACKEND=seatd /usr/libexec/starling-session`
  runs the real packaged session unprivileged over SSH, given `seatd` is
  active and you are in the `video` group.
- **A session-bus name is not yours just because you claimed it.** The private
  dbus-daemon still searches `/usr/share/dbus-1/services`, so system services
  are activatable on it, and we ask for our name with `ALLOW_REPLACEMENT`.
  Mask anything that would compete by dropping a stub `.service` in the
  private `XDG_DATA_HOME` servicedir (searched first) — that is what both
  launchers do for `org.freedesktop.secrets` and
  `org.freedesktop.portal.Desktop`. To check who actually answers:
  `busctl --address=unix:path=/tmp/xdg-starling-$(id -u)/bus call
  org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus
  GetNameOwner s <name>` (the runtime dir is per-user — use the uid of
  whoever runs the session).
Engine / compositor:
- **Audit `wayland_server_on_*` in the header against what
  `WaylandIntegration.swift` actually registers.** This has now bitten twice.
  `on_shm_surface_commit` was unregistered and every software client
  composited as nothing (1b1050a); `on_app_id_changed` was unregistered, so
  every window's app_id was thrown away and the dock guessed from titles —
  which meant no dock icon for IntelliJ or GIMP, and could not have worked for
  IntelliJ at all. In both cases the C side was complete: declared, defined,
  called. Nothing warns you.
- **A C callback the Swift side never registers fails silently and looks like
  a rendering bug.** `wayland_server_on_shm_surface_commit` was declared,
  defined, and called by `wayland_compositor.c` — but nothing in
  `WaylandIntegration.swift` ever set it, so the SHM branch tested
  `server->cb.on_shm_surface_commit &&` against NULL and dropped every
  software frame. The protocol side looked perfect from the client's seat:
  buffers attached, damaged, committed, and *released*, so a `WAYLAND_DEBUG`
  trace showed nothing wrong — the window just composited as nothing. Every
  `wl_shm` client was affected (IntelliJ, `weston-simple-shm`), while dma-buf
  clients were fine, which reads as "that one app is broken" rather than "half
  the compositor is unwired". When one class of client renders and another
  doesn't, check the callback is actually **set** before reading the paths it
  feeds. Two format traps live in that handler: `wl_shm`'s ARGB/XRGB8888 is
  B,G,R,A in memory but the CPU texture path uploads `GL_RGBA`, and toplevels
  routinely commit alpha=0, which composites the window away unless alpha is
  forced opaque (dma-buf sidesteps this by importing an opaque fourcc; the X
  server's shadow blit forces `0xff` for the same reason).
- **Java/Swing needs two X server gaps closed, and one of them crashes the
  client, not the server.** XI1 `ListInputDevices` must reply — AWT blocks on
  it during init holding the toolkit lock, so treating it as void deadlocks
  the app before it maps a window. And RENDER `QueryPictFormats` must list the
  depth-32 root visual: `XRenderFindVisualFormat` returns NULL for a visual we
  omit and `XRenderCreatePicture` then segfaults *inside libXrender*, with no
  protocol error to show for it. Even with both fixed, our RENDER is a drawing
  stub (`CreatePicture` is a no-op), so Java2D needs
  `-Dsun.java2d.xrender=false` to reach the paths we implement.
- `EvdevToHID` (engine repo, `fl_drm_input.cc`) and
  `WaylandIntegration.hidToEvdev` (shell) are exact inverses. **Change one,
  change the other**, or letters break for Wayland clients.
- **Keyboard focus is lazy, and "activated" is not focus.** `wl_keyboard.enter`
  is sent from the *first keystroke* (`sendKeyEvent` in
  `WaylandIntegration.swift`), not when a window is focused — so a window the
  user has clicked, and which is drawing and decorated, may never have received
  a keyboard enter. Meanwhile `wayland_server_configure_toplevel` sends
  `XDG_TOPLEVEL_STATE_ACTIVATED` **unconditionally**, so GDK cheerfully reports
  `GDK_WINDOW_STATE_FOCUSED` for such a window. Do not infer keyboard focus from
  a client's own focus flag; anything that must reach a client the moment the
  user engages with it belongs on **pointer** enter as well. This cost a full
  round of wrong implementation on the clipboard (`docs/plans/clipboard.md`),
  where hooking only `WL_KB_ENTER` looked correct and did nothing.
- If the shell dies uncleanly it leaves `/tmp/xdg-starling-<uid>/wayland-0.lock`
  and the next run listens on **wayland-1**; clients must use the socket from
  the current run's `wayland_server: listening on wayland-N` log line.
- `pkill -f <word>` matches its own `bash -c` line — use `pkill -x`.
