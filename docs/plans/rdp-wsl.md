# RDP as the display — the desktop in WSL2, and anywhere else without KMS

The desktop currently has one real output path: DRM/KMS. This plan adds a
second — **the RDP connection is the display** — so the full desktop
(compositor, Wayland/X11 clients, portal, input) runs where `/dev/dri` does
not exist. The acceptance test is docs/WSL.md's one-liner: **the desktop must
start with `/dev/dri` absent** — and, per its trap 1, with no seat of any
kind. WSLg (Weston + FreeRDP) is the existence proof that this shape works on
exactly this platform.

This is a different feature from the RDP *screen-share* built on branch `rdp`
(docs/plans/rdp.md): that one mirrors a DRM desktop and is staying as-is for
real hardware. Two modes, named here once and used everywhere:

- **share mode** — `--drm` + `STARLING_RDP=1`. RDP mirrors the KMS desktop.
  Unchanged; hardware only. docs/plans/rdp.md remains its plan of record.
- **display mode** — `--rdp`. No DRM, no seat, no libinput. The engine runs
  the software renderer, presents land in `rdp_server_push_frame`, and RDP
  input drives the engine directly. This document.

What survives from the share-mode work, verbatim or nearly:

- `shell/Sources/RdpServer/rdp_server.c` + `include/rdp_server.h` — listener,
  single-peer lifecycle (Activate-fires-twice gate), RemoteFX SurfaceBits
  encode, PTR_FLAGS→absolute-button-mask translation (wheel-coordinates fix
  included). It takes frames via `rdp_server_push_frame` and never asks where
  they came from — which is the whole reason display mode is cheap.
- `RdpService.swift`'s cert autogen (`resolveCertificate`) and env config.
- The `InjectPointerAbs` **algorithm** (engine `fl_drm_input.cc:331`):
  absolute mask → phase diff (pressed-before-released), kAdd priming, wheel
  as its own event. The engine implementation is DRM-path-only; display mode
  ports the algorithm to Swift. **No engine changes in W0 at all** — the
  shell links FlutterEmbedderBridge and calls
  `FlutterEngineSendPointerEvent`/`SendWindowMetricsEvent` directly, exactly
  as `runHeadless` proves.

## Measured 2026-08-16: surfaceless EGL works in WSL, and reaches the GPU

Run on the physical Windows box (build 26200, WSL 2.7.11, kernel
6.18.33.2-microsoft-standard-WSL2, WSLg 1.0.73.2, Ubuntu-26.04) with
`test/tools/egl_surfaceless_probe.c` — a GL ES2 context on
`EGL_PLATFORM_SURFACELESS_MESA`, no window system, `/dev/dri` absent:

| selection | GL_RENDERER | 1080p readback | 4K readback |
|---|---|---|---|
| default | `llvmpipe (LLVM 21.1.8)` | 1.6 ms | 4.4 ms |
| `GALLIUM_DRIVER=d3d12` | **`D3D12 (AMD Radeon 780M Graphics)`** | 1.5 ms | 10.1 ms |

Both render correct pixels. Three things follow, and they rewrite this plan:

- **The engine can run on `kOpenGL` in WSL.** That keeps the entire existing
  GL compositor stack — `LinuxTextureRegistry.populateTexture`, the
  `glTexImage2D` SHM upload, the liquid-glass shader — and **deletes the
  software external-texture resolver, which was the only engine change in
  this plan.** It also moots the BGRX finding: `glReadPixels` hands back RGBA,
  the same format share mode already encodes.
- **W2 collapses into an environment variable.** There is no separate GPU
  milestone; `GALLIUM_DRIVER=d3d12` is the whole of it.
- **Mesa defaults to llvmpipe for *everything* in WSL**, including WSLg's own
  apps (`DISPLAY=:0 glxinfo -B` reports llvmpipe until the same variable is
  set). `d3d12_dri.so` ships in the distro's Mesa; it simply is not chosen.
  `MESA_LOADER_DRIVER_OVERRIDE=d3d12` does **not** work — it is a DRI-loader
  knob, and this selection happens in Gallium. Only `GALLIUM_DRIVER` moves it.

Caveats that survive the measurement: readback is mandatory (there is no
scanout to share), and at 4K the GPU is *worse* at it than llvmpipe —
2.3× — because the pixels cross the virtualisation boundary. The probe times
`glClear` + `glReadPixels`, so it measures readback cost, **not** rendering
throughput; a real desktop with blur and shaders is where d3d12 should repay
that. Pick the renderer per-session, measure at the target resolution, and do
not assume the GPU wins. `/dev/dri` is still absent under both, so dmabuf
import stays dead and clients still arrive over SHM.

## What runDRM wires that runHeadless doesn't (the seam, measured)

`runHeadless` (main.swift:1006–1067) is engine + widget tree only: software
renderer, discard-the-frame present callback, fixed 1440×900, no services.
`runDRM` (main.swift:556–1002) additionally wires, in order: DRM view/seat →
scale adoption → DisplayLayout → texture registry (GL) → external/process app
managers → Wayland integration (+ epoll fd registration + dmabuf
advertisement) → capture trampoline (recording/screencast/rdp-share) → X11
integration (+ epoll fds) → external texture callback → portal →
notifications → `fl_drm_view_run`.

Of those, only these actually require the DRM view: the seat, the GL/EGL
stack behind `LinuxTextureRegistry.populateTexture`, dmabuf import, the
capture session (recording/screencast/share-mode RDP), hardware cursor, and
the epoll loop (`fl_drm_view_add_external_fd`). Everything else needs only a
running engine and a place to dispatch fds:

- `WaylandIntegration.start(screenWidth:screenHeight:scale:shellDpi:refreshMhz:)`
  has no DRM dependency; `advertiseDmaBufFormats` is a separate, skippable
  call. SHM commits already land in `updatePixelData` (CPU).
- `X11Integration.start(displayNum:...)` takes `drmView` as an *optional*;
  the view is used for epoll fd registration and the GetImage capture mirror.
- `PortalIntegration`/`NotificationIntegration` need only the session bus.
- `AgentBroker` is started by DesktopShell itself and already runs in WSL.

In display mode the engine's platform thread is the main thread (no custom
task runners — the `runHeadless` shape), so "dispatch on the platform thread"
becomes `DispatchQueue.main` + `RunLoop.main.run()`, and the epoll
registrations become `DispatchSourceRead` on the main queue.

## Compositing: what the GL measurement changed

> **Superseded in part.** This section was written for a software-renderer
> backend, before surfaceless GL was measured. On `kOpenGL` the table's
> middle column *is* the WSL column for every row but the last two, and the
> engine change below is not needed. It is kept because it is the fallback
> if surfaceless GL ever fails on a target box, and because the last two
> rows (dmabuf, first-party children) hold regardless of renderer.


Every client window reaches the screen as an engine **external texture**
(`LinuxTextureRegistry` → `TextureWidget`), and the embedder resolves
external textures **only for kOpenGL and kMetal**
(embedder.cc:2301–2350; `EmbedderExternalTextureResolver::ResolveExternalTexture`
returns nullptr otherwise). Under `kSoftware` a TextureLayer paints nothing.
Consequences, per client class:

| class | transport today | in WSL software mode |
|---|---|---|
| shell chrome, vector wallpaper | engine Skia raster | **works in W0** (`DesktopBackground` fallback runs when no wallpaper texture is registered, DesktopShell.swift:3071) |
| Wayland SHM clients | `updatePixelData` (CPU) → glTexImage2D | pixels already CPU-side; need only a software texture resolver (W1) |
| Wayland dmabuf clients (Chrome GPU) | EGLImage import | dead (no `/dev/dri`); we don't advertise linux-dmabuf → clients fall back to wl_shm themselves |
| X11 clients | PutImage/SHM (CPU) or DRI3 | SHM path works with the W1 resolver; DRI3/GLX dead — don't advertise |
| first-party child apps | **GPU-only**: `GpuDmaBufRenderer.openDrmDevice` must allocate a `gbm_bo`; `drmCandidates()` is empty without `/dev/dri` → child dies | needs a child-side software renderer + memfd transport (W1) |

W1's engine change (the only engine change in this plan): a software external
texture path. `FlutterSoftwareRendererConfig` gains a struct_size-versioned
`external_texture_frame_callback` that fills `{pixels, row_bytes, width,
height}`; a new `embedder_external_texture_software.{h,cc}` (modeled on
`embedder_external_texture_gl.cc`, ~140 lines) wraps them in
`SkImage::MakeRasterData` → `DlImage` → `DrawImageRect`; the resolver grows
the third branch. Shell-side, `LinuxTextureRegistry` already *stores* CPU
pixels per entry — it gains a `populateSoftwarePixels(id:)` (~40 lines) and
the Wayland/X11 SHM paths work **unchanged**. Fallback if the engine change
stalls: paint client buffers as framework images (`Canvas.drawImage` renders
fine under software Skia) via a `SoftwareTextureWidget` — workable, but it
forks `DesktopWindow` per backend, so it is the fallback, not the plan.

## Milestones

### W0 — prove the pipe in WSL (connect, render, mouse; the v1 scope bar)

Full-desktop startup minus DRM. No Wayland/X11/portal yet; the desktop is
shell chrome over the vector wallpaper. Window *frames* for clients would be
blank anyway until W1's resolver, so services wait.

Pipeline: `--rdp` → `runRdpDisplay()` → **engine on `kOpenGL`, backed by a
surfaceless EGL context** (`rdp_egl.c`: the probe's setup — surfaceless
display, ES2 context, one FBO at the negotiated size — ~250 lines) → present
callback does `glReadPixels` into the service mailbox (raster thread: **read,
copy, return**, nothing else) → encode queue → `rdp_server_push_frame` →
client. Pointer: `on_pointer` (peer thread) → main queue → ported
InjectPointerAbs → `FlutterEngineSendPointerEvent`.

Choosing `kOpenGL` over `kSoftware` costs one C file and buys the entire
existing compositor stack unchanged — external textures, SHM upload, shaders
— plus GPU rendering for free via `GALLIUM_DRIVER`. The software renderer
stays as the documented fallback if surfaceless EGL fails on some future
target; `runHeadless` already is that fallback, minus a frame sink.

Two facts that must be built in:

- **Frames are RGBA**, from `glReadPixels` — exactly what share mode already
  encodes as `PIXEL_FORMAT_RGBX32`, verified end-to-end. (Had this been the
  software renderer it would have been BGRX: Linux Skia builds with
  `SK_R32_SHIFT=16`, engine/src/flutter/skia/BUILD.gn:40, and the software
  surface is `MakeN32`, embedder_surface_software.cc:73. That trap applies
  only to the fallback path — if it is ever taken, `rdp_server_start` needs a
  pixel-format parameter.)
- **The client wins the size negotiation** (inverse of share mode's
  server-wins in `peer_post_connect`, rdp_server.c:100–117). A
  `honor_client_size` flag: keep the client's DesktopWidth/Height, report it
  through `on_activated(w,h)`; Swift sends `FlutterWindowMetricsEvent`
  (physical px, `pixel_ratio` = `STARLING_RDP_SCALE`, default 1.0 — trap 2:
  never derive), builds `DisplayLayout.build(...)`, sets `currentShellDpi`,
  then primes: `Flutter._forceNextComposite = true` +
  `PlatformDispatcher.scheduleFrame()` (the SIGUSR1 lesson, main.swift:979).
  Standalone default before any client: 1920×1080 (`STARLING_RDP_SIZE`).

Pacing without vsync: presents are content-driven (`scheduleFrame` on
damage), the depth-1 mailbox coalesces, `STARLING_RDP_FPS` (default 30)
caps at push time with a trailing-flush timer so the final frame of an
animation is never stranded. The share-mode pump machinery
(`needsFramePump`/`needsPrimingRebuilds`/`pumpTick`, DesktopShell.swift
~1163) is capture-session plumbing — display mode does **not** ride it; there
is no PBO ring to prime and no engine capture to drain. The 10fps-starvation
trap does not transfer: in software mode a present *is* the rebuild; the
equivalent hazard is blocking the raster thread in the present callback,
hence copy-only.

Cursor in W0: none composited, none sent — the RDP client draws its local
arrow by default, which sits exactly where the injected pointer is
(client-authoritative, zero latency). Artifact: always an arrow. W1 fixes the
shape.

File-by-file:

| file | change | ~lines |
|---|---|---|
| `shell/Sources/RdpServer/rdp_server.c` + `include/rdp_server.h` | `honor_client_size` + pixel-format param (start-config struct); report negotiated size in `on_activated` | +60 |
| `shell/Sources/RdpServer/rdp_egl.c` (new) | surfaceless EGL context + FBO at the negotiated size + readback (the probe, productionised) | ~250 |
| `shell/Sources/DesktopShellApp/Rdp/RdpDisplayMode.swift` (new) | `runRdpDisplay()`: engine init on kOpenGL, present→mailbox, metrics/DisplayLayout on activate, RunLoop | ~220 |
| `shell/Sources/DesktopShellApp/Rdp/RdpDisplayService.swift` (new) | listener lifecycle, mailbox+encode queue, fps cap + trailing flush, activation state (no capture claim) | ~200 |
| `shell/Sources/DesktopShellApp/Rdp/RdpPointer.swift` (new) | InjectPointerAbs ported: phase diff, kAdd priming, wheel-as-own-event, first-frame gate | ~120 |
| `shell/Sources/DesktopShellApp/Recording/RdpService.swift` | extract `resolveCertificate` into a shared helper both services use | ±40 |
| `shell/Sources/DesktopShellApp/main.swift` | `--rdp` dispatch before the fatalError | +8 |
| `build/session/starling-session` | `--rdp` branch: skip DRM probe and `LIBSEAT_BACKEND`, exec `DesktopShellApp --rdp` (trap 1: no seat path at all) | +15 |
| `build/run-desktop.sh` | `STARLING_RDP_SCALE`/`STARLING_RDP_SIZE` in the env passthrough | +2 |

Exit criteria, in WSL with seatd **stopped**: `starling-session --rdp`;
`xfreerdp /v:localhost:3390 /cert:ignore` inside WSL shows the desktop;
mouse moves/clicks open the launcher; colours correct; disconnect+reconnect
works; and it runs both with and without `GALLIUM_DRIVER=d3d12` (llvmpipe is
the floor, d3d12 the fast path). Estimate: **4–5 days**, zero engine
rebuilds.

**W0 landed and was verified in WSL on 2026-08-16.** On the physical Windows
box, Ubuntu-26.04 under WSL2, with `/dev/dri` absent and seatd stopped:
`DesktopShellApp --rdp` starts, `xfreerdp` under WSLg's X11 shows the
desktop at 1280x800, and a click on the dock opens the launcher. Both
renderers work and render identically —

```
[RdpEgl] renderer: llvmpipe (LLVM 21.1.8, 256 bits) | OpenGL ES 3.2
[RdpEgl] renderer: D3D12 (AMD Radeon 780M Graphics) | OpenGL ES 3.1   # GALLIUM_DRIVER=d3d12
```

— so the session logs which one it got, because nothing else in WSL hints at
it. The wallpaper is the vector fallback and client windows would be blank:
both are W1's service wiring, not faults. Packaging needed no changes;
`dpkg-shlibdeps` picked up libfreerdp-server3-3, libegl1 and libgles2 off
the staged binary by itself.

Two traps met while getting there, both already documented elsewhere in the
tree and both worth re-reading before the next round: every launcher appends
`--drm`, so `--rdp` must be tested first or display mode silently becomes a
DRM desktop; and `apt-get install` of an unchanged version number is a
silent no-op, so a rebuilt .deb must go in with `dpkg -i` and be checked by
md5 against the local binary.

### W1 — a usable desktop

1. ~~Software external textures~~ — **deleted by the GL measurement.** On
   `kOpenGL` the existing resolver, the `glTexImage2D` SHM upload and the
   Wayland Y-flip all behave exactly as they do on DRM. No engine change, no
   engine rebuilds. (Reinstate only if a target box cannot do surfaceless
   EGL.) **Saves ~2–3 days and the only cross-repo commit in the plan.**
2. **Keyboard.** rdp_server.c forwards `KeyboardEvent`
   (scancode, extended, release) / `SynchronizeEvent` / `UnicodeKeyboardEvent`
   to new callbacks (+40). Translation, in the pipeline's canonical order —
   RDP set-1 scancode → evdev (identity for the main block; ~20-entry
   extended table: 0xE0 0x1D→97, 0x38→100, nav cluster, KP-enter/slash,
   Win/Menu) → HID via the **same table** `WaylandIntegration.hidToEvdev`
   uses, converted from a switch into a shared pair table so both directions
   have one source of truth (trap 3: this exact-inverse property is what
   keeps letters working in Wayland clients) → xkb (us pc105, matching
   `wayland_seat.c`'s default keymap) for keysym + UTF-8 via a small C shim
   (`rdp_keyboard.c`, xkbcommon is already linked) →
   `FlutterEngineSendKeyEvent` on main. `SynchronizeEvent` updates xkb
   locked-mods. ~2 days.
3. **Service wiring** in `runRdpDisplay`: LinuxTextureRegistry (no GL
   resolver), Wayland (no dmabuf advertisement), X11 (no GLX/DRI3), portal,
   notifications, process manager. Fd dispatch: `X11Integration`/wayland fd
   registration parameterized by a `registerFd: (Int32, @escaping () -> Void) -> Void`
   closure — DRM passes `fl_drm_view_add_external_fd`, display mode builds
   `DispatchSourceRead` on main. runDRM is otherwise untouched. ~2 days.
4. **First-party child apps**: `GpuDmaBufRenderer` grows a software path
   (child engine on `kSoftware`, frames into a memfd; same socket protocol
   with a "CPU/linear" meta flag), `LinuxProcessAppManager` maps the memfd
   and routes frame signals to `updatePixelData`. ~3 days.
5. **Cursor shapes**: wire `DesktopCursor.shapeSetter` →
   `rdp_server_set_pointer(rgba,w,h,hotx,hoty)` (Color Pointer Update PDU,
   cached; System Pointer for default/hidden); sprites lifted from
   `fl_drm_cursor.cc`. ~1–2 days.
6. **mstsc**: pull share-mode M1's NSC/raw codec ladder in (rdp_server.c is
   shared; display mode is currently RFX-only, so W0/W1 tests use xfreerdp).
   Plus `SuppressOutput` honored (stop pushing, force-composite on resume).
   ~1–2 days.

Stated W1 limitations: no recording/screencast in display mode (both are
welded to `fl_drm_view_recording_*`; a present-callback tee is future work),
no Display Control resize, single client, TLS-no-NLA posture unchanged.
Estimate: **~2 weeks**.

### W2 — GPU — **folded into W0; the probe came back green**

Kept for the record: this was scoped as a separate milestone gated on a probe.
The probe (above) ran on 2026-08-16 and surfaceless EGL reaches the GPU with
`GALLIUM_DRIVER=d3d12`, so W0 builds on GL from the start and there is no W2.
What remains is a *policy* question, not a milestone: which renderer a session
picks. Recommendation — default to whatever Mesa chooses (llvmpipe today),
expose `STARLING_RDP_GPU=1` to set `GALLIUM_DRIVER=d3d12`, and measure at the
session's real resolution before defaulting it on, because 4K readback is
2.3× worse on d3d12 than on llvmpipe and only a shader-heavy scene repays it.

The original text follows for the fallback case (surfaceless EGL unavailable).

#### Original W2 (obsolete unless surfaceless EGL fails)

Probe before building (half a day, no shell changes): a ~100-line C probe run
in WSL — `eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA)` on the d3d12
driver, GLES2 context, FBO render, `glReadPixels`; measure readback at
1080p/4K. If it holds: `runRdpDisplay` gets a GL branch —
`FlutterOpenGLRendererConfig` backed by a shell-side surfaceless EGL context
(`rdp_egl.c`, ~250 lines), present = readback → the same
`rdp_server_push_frame` (RGBA again there); `LinuxTextureRegistry` runs its
existing GL paths (SHM upload via glTexImage2D); the W1 software resolver
remains as fallback. dmabuf import stays dead regardless — no `/dev/dri`, so
nothing changes for clients; the win is shader effects (liquid glass),
scaling quality, and frame rate. If d3d12-surfaceless fails: try llvmpipe
surfaceless (GL semantics at CPU cost — adopt only if it measures better than
the software resolver), else W1 stands as the WSL answer. Estimate: **probe
0.5d + 4–5 days if green**.

## Risks and traps

- **Trap 1 (no seat).** Display mode must never touch libseat, libinput, or
  any `fl_drm_view_*` that needs a view. Regression-proof it: the W0 test
  runs with seatd stopped. (Global reads like `fl_drm_view_capture_active()`
  return 0 without a view and are safe in shared code paths like the pump.)
- **Trap 2 (scale).** `STARLING_RDP_SCALE` only; `DeriveScale` reads EDID
  physical size and RDP reports nothing trustworthy.
- **Trap 3 (keyboard representation).** scancode→evdev→HID with the shared
  table; the regression test is typing into a Wayland client, not the shell.
- **Software external textures.** Without W1's resolver every client window
  is a blank rect — expected in W0, a bug after. The wallpaper is safe
  (vector fallback).
- **BGRX vs RGBX.** Two modes, two formats, one encoder — parameterized, not
  edited. A red/blue-swapped desktop means the parameter went to the wrong
  mode.
- **Y-flip.** The Wayland texture flip is a GL-origin artifact; unconditional
  flip renders every Wayland window upside down in software mode.
- **Raster-thread present.** The present callback blocks the engine pipeline;
  copy-signal-return, encode elsewhere (the ingest contract, again).
- **Port 3389 collision.** Windows' own RDP owns 3389 on the host side, and
  WSL localhost-forwarding maps into it — test on `STARLING_RDP_PORT=3390`
  (mstsc `localhost:3390`); inside-WSL xfreerdp doesn't care. LAN → WSL
  needs netsh portproxy or mirrored networking; out of scope.
- **Keeping share mode working.** rdp_server.c becomes shared; every change
  there re-runs the share-mode exit criteria on the dev box
  (`--drm STARLING_RDP=1` + xfreerdp).
- **Test-loop mechanics.** PowerShell quoting: scripts to files, strip CRs
  (`sed 's/\r$//'`). Guest file transfer via `python3 -m http.server` on
  virbr0 + `curl.exe`, not the agent channel. The session log is
  `/tmp/starling-session-0.log` — a silent run is normal, read the log.
- **LoginUser under WSL root.** Cert autogen targets the login user's config
  dir; a root-only distro must fall back sanely — verify in W0.

## Open decisions (each with a recommendation)

1. **Entry point** → `--rdp` flag + `starling-session --rdp`. `--headless`
   keeps meaning liveness-only; `STARLING_RDP=1` under `--drm` keeps meaning
   share mode. No ambiguity, no env-flag mode switching.
2. **W1 compositing mechanism** → engine software external texture resolver;
   framework-image painting is the documented fallback. Keeps `TextureWidget`
   and all integrations unchanged.
3. **First-party child transport** → memfd on the existing socket protocol.
   Running children as Wayland SHM clients would lose DPI/theme/caret
   integration for zero savings.
4. **Client resize** → first client's size wins for the session; W0 refuses
   mismatched reconnects, W1 re-sends metrics per activation. Display Control
   is a follow-up.
5. **Display-mode default fps** → 30 (interactive desktop, software encode of
   damage-driven frames; 15 stays the share-mode default).
6. **Seam depth** → new `runRdpDisplay` duplicating ~150 lines of service
   wiring; the only runDRM-adjacent refactor is the `registerFd` closure in
   the integrations. Do not refactor a working DRM monolith to serve a new
   mode.
7. **Cursor** → client-local arrow in W0, server pointer PDUs in W1.
   Compositing a cursor into frames adds latency and was rejected.
8. **docs/plans/rdp.md** → stays authoritative for share mode and the C
   shim's internals; gains a two-line header pointing here for display mode.
   This file (docs/plans/rdp-wsl.md) owns display mode. Neither absorbs the
   other — they share code, not a mode.

## Test plan (win11-gpu's WSL, xfreerdp harness)

Loop: `virsh start win11-gpu` → guest 192.168.122.209 → stage the .deb via
`python3 -m http.server` + `curl.exe` → `wsl -d Ubuntu-26.04 -u root` →
install → scripts staged as files, CRs stripped.

- **W0 acceptance** (scriptable end-to-end inside WSL, no Windows-side
  client needed): `systemctl stop seatd || true`; `ls /dev/dri` must fail;
  `starling-session --rdp` with `STARLING_RDP_PORT=3390`; under WSLg's
  `DISPLAY=:0`, run `xfreerdp /v:localhost:3390 /cert:ignore /size:1920x1080`;
  ImageMagick `import -window <xfreerdp window>`; assert nonblack taskbar
  row; `xdotool` click at the start button (x~25, y~1055 at 1920×1080, the
  DesktopShellApp/CLAUDE.md table) through the xfreerdp window; re-screenshot,
  assert launcher pixels. Then kill xfreerdp, reconnect, assert frames again.
- **W1**: launch `weston-simple-shm`/`weston-terminal` against the session's
  `WAYLAND_DISPLAY`; assert the window composites (nonblack in its rect,
  right-side-up — the Y-flip check); type `ls\n` and assert glyphs
  (test/glyph-pixels.py); open Settings (first-party memfd path); mstsc from
  the Windows side against `localhost:3390` once the codec ladder lands.
- **Share-mode regression** on the dev box after any rdp_server.c change.
- **W2 probe** runs standalone in WSL before any W2 code is written.
- These runs are driven scripts under `test/tools/rdp-wsl/`, not CI — the
  fast tier gains nothing beyond compile, and vm.sh gates the
  `starling-session` change as usual.

Effort summary, after the GL measurement: **W0 4–5 days · W1 ~1.5 weeks**
(the software-texture engine change is gone) **· W2 folded into W0.**
No engine changes anywhere in the plan — this is shell-only work.
