# PWAs as first-class apps

Goal: install a progressive web app and have it behave like every other app on
the desktop — a launcher tile, a dock icon, its own window, a real app identity,
and offline support. On Linux this is not a nicety: Microsoft retired the native
Teams desktop client, so on this platform Teams *is* a PWA or it is nothing.

## The road not taken, so it is not re-litigated

The obvious-looking route was WebF (openwebf) — HTML/CSS/JS rendered through
Flutter's own render tree, which sounds like a perfect fit for a desktop already
built on the engine. **It cannot run PWAs, close to by definition.** A PWA is a
service worker plus a manifest, and WebF has no service workers and no web
workers at all; one long-lived JS context, no page lifecycle, no Shadow DOM, no
iframes, no float or table layout, Grid experimental. Two lines from its own
documentation settle it:

- it "is not a browser and disallows navigation to untrusted or external
  origins"
- "while WebView is heavily sandboxed, WebF removes this sandbox to enable true
  deep integration"

A PWA is third-party code from an external origin. WebF is built to run code we
wrote, with native access and no sandbox. Pointing it at someone else's web app
is both incompatible and unsafe.

WebF stays interesting for a *different* product — letting people write Starling
apps in HTML/CSS/JS instead of Electron. That is not this. The two should not be
blurred, because they have opposite requirements: one needs compatibility with
the whole web, the other needs none of it.

**Engine: Google Chrome**, which the registry already installs
(`registry/catalog.d/chrome.app`, `Install=chrome`, from Google's own .deb).
Widevine settles it — Spotify and streaming need the proprietary CDM, which
Chrome ships and WebKitGTK on Linux typically lacks.

**What this does not buy: memory.** Running a PWA means running a browser. The
memory argument only exists in the WebF-shaped world where compatibility was
traded away. Nobody should sell this feature as lighter than Electron.

## Most of this already exists

This is a data-and-recipes job, not an engine job — which is exactly what "apps
are data, not code" was built for:

- `registry/catalog.d/*.app` — the record format: `Name`, `Glyph`, `Color`,
  `Order`, `Exec`, `WmClass`, `DesktopEntry`, store copy.
- `/var/lib/starling/installed.d/<id>.app` — written on install, watched with
  inotify, so an install lights up the launcher and dock with no relogin.
- `app-install --record <id>` — re-resolve and rewrite one record without
  installing anything; `STARLING_APP_RECORDS=<dir>` to test unprivileged.
- `build/app-run.sh`'s `chrome` branch — `--ozone-platform=wayland`,
  `--force-device-scale-factor`, ANGLE, and the sandbox arrangement that lets
  Chrome's own zygote work under bwrap. **It already carries per-launch profile
  machinery** for the agent CDP endpoint (`STARLING_CDP`), which is the same
  isolation a PWA needs.
- Window identity: `xdg_toplevel.set_app_id` matched against `WmClass=`.
- `PortalService` serves FileChooser, ScreenCast, Settings, Session, Request —
  so screen sharing has an implementation to talk to.

## The shape

An installed PWA is one record plus one launch recipe:

    chrome --app=<start_url> --class=<id> --user-data-dir=<profile>

- `--app=` gives a browser-chrome-less window at the start URL.
- `--class=` sets the app id the compositor sees, which is what the dock matches
  `WmClass=` against. Title matching is not an option here — it is opt-in
  (`TitleMatch=`) and only for windows carrying no app_id at all.
- `--user-data-dir=` is what makes it a *separate app* rather than another
  window of the user's browser: its own cookies, its own service worker
  registration, its own process tree.

The web app manifest supplies the rest: `name`/`short_name` → `Name`, `icons` →
the record's icon, `start_url`, `display`, `theme_color` → tile colour.

## Steps

1. **Manifest → record.** Fetch the page, find `<link rel="manifest">`, parse
   name/icons/start_url/display/theme_color, pick and download the best icon,
   write an installed record. A new `pwa` install kind in `app-install.sh`.
   *Proves:* the record path, and that the launcher and dock pick it up live.
2. **Launch recipe.** A `pwa` branch in `app-run.sh` composing the three flags
   above on top of the `chrome` branch's existing ozone/scale/sandbox flags.
   *Proves:* the window arrives with the right app_id and the right scale, and
   the dock binds icon to window.
3. **Drive one real app end to end**, on a real session, unprivileged. Teams
   first — it is the strongest argument for the feature and the most demanding
   surface at once (WebRTC, screen share, SSO, notifications).
4. **Then decide about the widget.** Web content *inside* a Starling app is a
   separate project: offscreen browser → dma-buf → Flutter external texture.
   `GpuDmaBufRenderer`, `DmaBufBridge` and the embedder's external-texture API
   already exist; there is no webview anywhere in the tree. Do not start it
   until step 3 says what people actually install.

## Traps, this repo specifically

- **The dev box runs third-party clients as root, and Chrome refuses that.**
  Teams has already died here once on `FATAL: The SUID sandbox helper binary …
  is not configured correctly`. Any conclusion about a PWA drawn from
  `run-desktop.sh` may be an artifact. Test unprivileged —
  `LIBSEAT_BACKEND=seatd /usr/libexec/starling-session` — or in the VM
  (`test/vm-harness/`, apps run as `tester` through a real GDM login). This is
  the single most likely way to reach a confidently wrong answer.
- **`org.freedesktop.secrets` is masked deliberately**, not accidentally: the
  stock gnome-keyring service file never claims the name, so every
  Chromium/Electron app stalls 120 s on `service_start_timeout`, and the stub
  fails in milliseconds instead. The consequence for PWAs is that Chrome uses
  its *basic* password store — tokens persist, but obfuscated rather than
  encrypted. Not a bug to fix; a decision to make, once a PWA is holding
  somebody's work session.
- **Verify what Chrome actually reports as app_id under ozone/wayland** before
  trusting `--class`. The dock's identity comes from app_id, and getting this
  wrong is how an app ends up launching with no icon.
- **Chromium is not Chrome**: distro Chromium builds ship without the Widevine
  CDM, so a media PWA that works in one fails in the other.
- **Notifications and badging have no path yet.** Out of scope for the first
  cut; note what breaks rather than building it.

## Open questions

- **One profile per PWA, or one shared profile with several `--app` windows?**
  Per-PWA is cleaner isolation and what the browsers do; it also means a
  separate process tree per app, which is where the memory goes.
- **Where do profiles live**, and do they follow the same runtime-dependent
  placement the CDP profile already negotiates in `app-run.sh`?
- **Uninstall**: remove the record and the profile, or keep the profile so a
  reinstall keeps the login?
- **Does the App Store list PWAs** — a curated `catalog.d` entry per app, the
  way Chrome has one — or is this user-supplied-URL only? Curated entries get
  proper tiles and store copy; user-supplied is the whole point of PWAs.

## Test targets

| App | What it exercises |
|---|---|
| Teams | WebRTC camera/mic, screen share through the portal, SSO, badging |
| Spotify / YouTube Music | Media pipeline and Widevine |
| Google Docs | Heavy DOM editing, IME, clipboard, printing |
| Figma | WebGL and WASM, GPU pressure — and no Linux native exists at all |
| Gmail / Proton Mail | Service worker offline, notifications, background sync |
