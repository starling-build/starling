# Guest display — M1, "Windows in a window"

Implementation plan, approved 2026-09-02. Phases 1–5 are **done and verified
on the dev box**; §Status at the foot of this file says exactly what was seen
and what is still open. The three §Open decisions were settled on their
recommendations.

The design is `docs/plans/windows-home-vm.md`; its verdict after the M0 spike
is that Layer 1 (QEMU's `-display dbus,gl=on` handing us the guest's scanout as
a dma-buf over a peer-to-peer D-Bus socket) is a zero-copy path that can be
planned on. This is that plan: the compositor grows a `GuestDisplay`, the
registry grows a `windows.app`, and clicking it puts the Windows console on the
desktop as an ordinary window — dock icon, spaces, Mission Control, resize —
with input, the guest's own cursor, and (text) clipboard. It replaces
`docs/windows-vm/{dbus-display.py,wshot.py,type-keys.py}` as the way a person
uses the VM; the scripts stay as the protocol reference.

Everything protocol-level below was measured in the spike (`windows-home-vm.md`
§Results A, `docs/windows-vm/dbus-display.py`), not inferred. Everything
shell-level was surveyed from source on 2026-09-02; file:line references are
to that tree. Planning happened on macOS; the build, the run and every
verification step need the Linux dev box.

Fixed by the design doc, not re-opened here: **Path A, 2D guest** (viogpudo,
no virgl) for the first release; the Windows *installer* flow is a later
milestone, so M1 assumes a domain that already exists; Triton and the
flipping-guest patch are out of scope; so are audio, USB redirection, multiple
heads, non-text clipboard, and agent ownership of the guest window.

## Measured on the dev box (2026-09-02)

Phase 2's probe was written and run against `win11-dbus` on the Lenovo before
any of the shell work — stock Ubuntu 26.04 QEMU **10.2.1**, the shipping
target, not a patched build. It is `docs/windows-vm/guest-display-probe.c`
(386 lines):

    gcc -O1 -g probe.c -o probe $(pkg-config --cflags --libs libsystemd) -lvirt
    ./probe win11-dbus 30            # or: ./probe win11-dbus 120 detach

**The recipe in Phase 2 works verbatim.** `sd_bus_new` → `sd_bus_set_fd(fd, fd)`
→ `sd_bus_negotiate_fds(1)` → vtables → `sd_bus_start`, with no
`sd_bus_set_bus_client` and no Hello, authenticates against QEMU's GDBus
server and receives calls. `RegisterListener` as one synchronous call is safe
(the listener is not live yet — `dbus-display.py` does the same), QEMU's
`GetAll` on `Interfaces` is answered by sd-bus's own property handling, and
`ScanoutDMABUF2` arrives with a passed fd that `dup()`s and is large enough to
map. So Phase 2 is a transcription job, not a research one.

What the guest actually sends, and what it costs:

| | |
|---|---|
| first scanout | placeholder `XB24`, **`y0_top=0`**, then the real `AB24`, **`y0_top=1`** |
| planes / modifier | 1 plane, `0x00ffffffffffffff` (= `DRM_FORMAT_MOD_INVALID`) |
| stride | **not `width*4`** — 1400 wide came back as 5632 (1408 px), 1280 as 5120 |
| buffer size | larger than `stride*height` (6,524,928 for 5,913,600 needed) |
| `SetUIInfo` → new scanout | **38 ms** |
| `CursorDefine` | 64×64, hot 0,0, 16384 bytes — *exactly* the cursor plane |
| damage | small and frequent: ~200 `UpdateDMABUF` in 12 s, mostly 60×50 near the pointer |
| `Mouse.IsAbsolute` | true |

Three of those change the plan rather than confirm it:

1. **`y0_top` is per-scanout, not per-window.** The placeholder says 0 and the
   real buffer says 1, and both arrive again after every resize. `flipTextureY`
   must be re-set on each scanout (a `WindowInfo` mutation + repaint), not
   fixed when the window is created. Setting it once from the first scanout
   paints the desktop upside down.
2. **Stride carries padding.** Import with the reported stride; never compute
   it from the width.
3. **`SD_BUS_VTABLE_UNPRIVILEGED` is not required here** — the probe works with
   the flag stripped, though QEMU runs as `libvirt-qemu` and the probe as
   `starling`. sd-bus treats a *direct* connection as trusted; the PortalService
   precedent is a bus connection, which is a different case. Keep the flag as
   explicit intent, but it is not the trap I claimed.

**Phase 3 is validated end-to-end against real Windows.** qnum `0xDB` — HID
`0xE3`, straight out of the table generated this session — opened the Start
menu, and the guest repainted **63 ms** later. The table is right where it
counts.

### The reboot crash — fixed, by a one-line guard that did not exist yet

Rebooting the guest while a GL listener is registered **crashes the whole VM**
on stock 10.2.1, reproduced twice:

    qemu-system-x86_64: ui/dbus-listener.c:600:
        dbus_scanout_texture: Assertion `tex_id' failed.
    shutting down, reason=crashed

Two things we believed about this were wrong, and both cost a VM to find out.

**There is no client-side workaround.** QEMU sends `Disable` about 1.3 s before
the assert, so dropping the listener there looks like a clean dodge; with it
armed (`./probe … detach`) the VM still died, 0.64 s after the listener closed.
The teardown is already in flight, and a guest-initiated restart gives no
earlier warning.

**`patches/0001` does not fix it either.** The Triton build
(`/opt/triton`, QEMU 10.0.12, 0001–0004 applied — verified in the built source
and by build timestamp) asserts in exactly the same place. 0001 makes the
render-node context current inside the `DisplayGLCtx` texture hooks, which
fixes a texture created *without* a context; the reset path never gets that
far. On reset the console hands `dbus_gl_gfx_switch()` a fresh
`DisplaySurface` whose texture has not been created yet, and line 805 passes
`ddl->ds->texture` — zero — straight into `dbus_scanout_texture()`.

The fix is a one-line guard, now `patches/0005`:

    -    if (ddl->ds) {
    +    if (ddl->ds && ddl->ds->texture) {

There is nothing to show for a surface with no texture, and the next
`gfx_update`/switch scans out once one exists. **Measured with it in place:
the guest reboots with the listener attached, the VM stays up, and frames
resume on the far side** — 110 s attached across a reboot, 12 scanouts, 812
damage events, versus a dead VM within 13 s on both unguarded builds.

So M1's blocking decision is closed: the desktop needs a QEMU carrying **0001
and 0005** (0005 is the one that matters for a 2D guest). Both are small and
upstream-shaped; 0005 in particular is a defensive guard on a path that can
only be reached with no texture to draw.

The other stock-QEMU worry is gone too: **detach and reattach works.** A
second probe run right after the first gets scanouts immediately, so patch
`0002` does not block close-then-reopen, and the detach-on-close design stands.

## Shape

```
QEMU (dbus display, p2p)        shell process
────────────────────────        ──────────────────────────────────────────────
Console/Keyboard/Mouse  ◄─ctl─► GuestDisplay (C, sd-bus, its own thread)
Listener  ─────listener socket─►   │ callbacks (bus thread)      ▲ commands (any thread)
                                   ▼                             │ eventfd
                                GuestSession (Swift, UI thread) ─┘
                                   │ reimportDmaBuf      │ addWindow      │ setImage
                                   ▼                     ▼                ▼
                                LinuxTextureRegistry   WindowInfo      engine cursor
```

Decisions, each with the reason it is fixed rather than open:

1. **The bus lives on its own pthread inside a new C target, `GuestDisplay`** —
   the PortalService/ImeBridge idiom (`shell/Sources/PortalService/portal_service.c:1242`
   poll loop and `:1401` thread; `shell/Sources/ImeBridge/ime_bridge.c:370-380`,
   `:489`), not
   `fl_drm_view_add_external_fd`. That export must be called before
   `fl_drm_view_run()` (`engine/src/flutter/shell/platform/linux_drm/fl_drm_view.h:79`),
   and the VM is opened at click time, long after.
2. **A guest window is a texture-backed `WindowInfo`, nothing more.** The
   texture path is `LinuxTextureRegistry.importDmaBuf/reimportDmaBuf`
   (`shell/Sources/DesktopShellApp/Compositor/LinuxTextureRegistry.swift:324`,
   `:375`), which is metadata-only on the UI thread and does the EGL import on
   the raster thread inside `populateTexture` (`:475`, dma-buf branch
   `:553-747`) with a per-buffer EGLImage cache keyed on dev/ino. Its
   parameter list is one-to-one with `ScanoutDMABUF2`. The window is
   `windowManager.addWindow(textureId:…)` (`Shell/WindowManager.swift:599`)
   with the five callbacks, copied from the X11 template
   (`Shell/DesktopShell.swift:3551-3620`), **not** a fake Wayland surface —
   that would inherit the opaque-fourcc rewrite and `wayland-<id>` parsing for
   nothing. Dock, spaces, Mission Control, focus, minimise, resize handles all
   come free (they only know `textureId`).
3. **The `UpdateDMABUF` reply is the frame ack, and we send it from the
   output-present callback** — the same clock that fires Wayland frame
   callbacks (`main.swift:843-854` → `WaylandIntegration.handlePresent`
   `:425`). QEMU blocks the guest's display path until the reply, so replying
   on present paces the guest to our refresh exactly as a monitor would; a
   20 ms deadline on the bus thread covers a minimised or covered window.
   `STARLING_GUEST_ACK=immediate` acks on receipt, as a diagnostic knob.
4. **The guest's cursor goes on the hardware cursor plane.** Today the plane is
   shape-enumerated only (`fl_drm_view_set_cursor_shape`, `fl_drm_view.h:339`)
   and `wl_pointer.set_cursor` is an explicit no-op
   (`shell/Sources/WaylandServer/wayland_seat.c:24-36`) — there is no bitmap
   cursor anywhere. But the plane is already a 64×64 ARGB GBM BO
   (`fl_drm_cursor.cc:238`) and QEMU's `CursorDefine` is a 64×64 ARGB bitmap
   plus hot-spot, so one engine export closes the gap at zero latency. A
   software sprite would cost a frame and need the plane hidden anyway.
5. **Keys go out as XT set-1 scancodes ("qnum") from a checked-in table
   generated from keycodemapdb**, `usb → qnum`, in the same one-array-two-
   lookups form as `Wayland/HidEvdev.swift:21`. `routeKey` hands us the HID
   usage directly (`DesktopShell.swift:2418-2433`), so HID→qnum is one hop;
   going through evdev would be two tables and a second drift surface.
6. **libvirt is linked, not shelled out to.** `virsh` cannot pass an fd across
   exec, and `virDomainOpenGraphicsFD` is the only way to get the p2p socket.
   `CLibvirt` is a system-library target like `CUdev`
   (`shell/Sources/CUdev/module.modulemap`), connecting to `qemu:///system`
   with flags 0 as the spike did.
7. **Close means detach; the VM keeps running.** Shutting Windows down is an
   explicit dock-menu item (`virDomainShutdown`, ACPI). Quit-with-reap
   (`_quitApp`/`_reapAfterQuit`, `DesktopShell.swift:7401-7481`) has nothing to
   reap — `_clientPid(of:)` returns nil for our prefix and that is the right
   answer, so no arm is added there.
8. **Registry: `Kind=vm` and a new `Domain=` key**, one record `windows.app`.
   `AppRecord.Kind` (`registry/Sources/StarlingRegistry/AppRecord.swift:29-40`)
   gains a fifth case; `AppRegistry.probe` (`AppRegistry.swift:361-378`) is an
   exhaustive switch so the compiler finds the arm. The launch arm goes into
   `_launchOrFocusApp`'s kind switch (`DesktopShell.swift:8021`, beside `.x11`
   at `:8115`) and opens the display in-process — there is no Wayland client
   to point at a socket, so `app-run.sh` is not involved.

## Phase 1 — Engine: a caller-supplied cursor image

Repo **starling-engine, branch `starling`**. Files
`engine/src/flutter/shell/platform/linux_drm/fl_drm_cursor.{h,cc}`,
`fl_drm_view.{h,cc}`.

New export — the name MUST keep the `fl_drm_view_` prefix (`drm_exports.lst`
is a wildcard on it; anything else is localised silently):

```c
// Put a caller-supplied bitmap on the hardware cursor plane (a VM guest's
// cursor). `bgra` is width×height straight-alpha BGRA8888 (0xAARRGGBB words
// on a little-endian host — what QEMU's CursorDefine and DRM's ARGB8888 both
// mean), tightly packed, clipped to the 64×64 plane; the engine premultiplies.
// hot_x/hot_y are in image pixels. A later fl_drm_view_set_cursor_shape()
// replaces it. width == 0 || height == 0 hides the sprite (transparent image).
FL_DRM_EXPORT void fl_drm_view_set_cursor_image(FlDrmView* view,
    const uint8_t* bgra, int width, int height, int hot_x, int hot_y);
```

Inside `FlDrmCursor`:

- `FlCursorShape` gains `kCustom`. `SetImage(...)` writes the BO the way
  `LoadShape` does (`fl_drm_cursor.cc:250-280`: fill, `gbm_bo_write`, then
  `current_shape_`/`hot_x_`/`hot_y_` under `state_mu_`), then re-binds and
  re-anchors exactly as `SetShape` does (`:291-295`) — the re-anchor matters
  because the hot-spot changes with every image and legacy `drmModeSetCursor`
  has no hot-spot of its own. `SetShape`'s early-return (`:283`) stays
  correct: `kCustom` never equals an enum shape, and two successive
  `SetImage` calls must not short-circuit.
- Keep a 64×64 RGBA copy of the last image. The two capture sites that paint
  the cursor into screenshots and recordings (`fl_drm_view.cc:481`, `:717`)
  call the static `RenderShapeRGBA(shape, …)` (`fl_drm_cursor.cc:371`); give
  them an instance `RenderCurrentRGBA` that returns the copy for `kCustom`, so
  agent screenshots of the guest window show the Windows cursor, not the
  arrow.
- Premultiply on copy. The baked shapes are pure black/white with alpha 0 or
  255, so nothing in the file has had to think about this yet; Windows cursors
  have soft edges, and the KMS default blend mode is pre-multiplied.

**Rebuild BOTH out dirs** — `host_debug` and `host_release`
(CLAUDE.md, Build & iterate): a new export missing from one fails the link,
missing from the other fails at first use with a `symbol lookup error` that
looks like "the cursor crashes the shell".

## Phase 2 — `GuestDisplay`: the C target

New target `shell/Sources/GuestDisplay/` (`guest_display.c`, `include/guest_display.h`)
in `shell/Package.swift`, with `cSettings: sdbusCSettings` /
`linkerSettings: sdbusLinkerSettings` (`shell/Package.swift:111-118` — this is
what makes the basu/`STARLING_DEPLOY` build work) plus a new
`CLibvirt` system-library target (`link "virt"`), both added to `shellDeps`
(`:85-104`). Build dep `libvirt-dev`; runtime `libvirt0` — dpkg-shlibdeps
picks it off the staged binary (`build/package-desktop.sh:223-243`), the same
reasoning RdpServer records at `shell/Package.swift:184-188`.

The header is a callback struct plus command functions — the `RdpServerCallbacks`
idiom (`shell/Sources/RdpServer/include/rdp_server.h:29-53`), chosen over
per-callback setters because of what CLAUDE.md records about
`wayland_server_on_*`: a setter nobody calls fails silently and looks like a
rendering bug; a struct field the compiler can see does not.

```c
typedef struct GuestDisplay GuestDisplay;

enum { GUEST_DISPLAY_CONNECTING, GUEST_DISPLAY_CONNECTED,
       GUEST_DISPLAY_DISCONNECTED, GUEST_DISPLAY_FAILED };

typedef struct GuestDisplayCallbacks {
    void* ctx;
    // All on the bus thread. Return quickly; never call a guest_display_*
    // function synchronously from inside one except the queued ones below.
    void (*on_state)(void* ctx, int state, const char* detail);
    // One new scanout. fd is a dup owned by the callee. Plane 0 only (the
    // spike saw one plane, AB24, modifier INVALID); extra planes are closed
    // here, as wayland_dmabuf.c:97-99 does. y0_top: row 0 is the bottom.
    void (*on_scanout)(void* ctx, int fd, uint32_t width, uint32_t height,
                       uint32_t stride, uint32_t offset, uint32_t fourcc,
                       uint64_t modifier, int y0_top);
    // Damage. The reply — QEMU's frame ack — is withheld until
    // guest_display_ack_frame(token) or the deadline, whichever first.
    void (*on_update)(void* ctx, uint64_t token, int x, int y, int w, int h);
    void (*on_disable)(void* ctx);
    // CursorDefine: straight-alpha BGRA, len == w*h*4.
    void (*on_cursor_define)(void* ctx, int w, int h, int hot_x, int hot_y,
                             const uint8_t* bgra, size_t len);
    void (*on_mouse_set)(void* ctx, int x, int y, int visible);
    // Phase 6.
    void (*on_clipboard_grab)(void* ctx, const char* const* mimes, int n);
    void (*on_clipboard_release)(void* ctx);
    void (*on_clipboard_request)(void* ctx, uint64_t token, const char* mime);
} GuestDisplayCallbacks;

// Returns at once; connects on its own thread and reports through on_state.
GuestDisplay* guest_display_open(const char* domain, const GuestDisplayCallbacks* cb);
// Joins the thread. Not from inside a callback.
void guest_display_close(GuestDisplay*);

// Any thread. Each is queued to the bus thread (eventfd wake) and never blocks.
void guest_display_ack_frame(GuestDisplay*, uint64_t token);
void guest_display_key(GuestDisplay*, uint32_t qnum, int down);
void guest_display_mouse_abs(GuestDisplay*, uint32_t x, uint32_t y);   // guest pixels
void guest_display_mouse_button(GuestDisplay*, uint32_t button, int down);
    // 0 left, 1 middle, 2 right, 3 wheel-up, 4 wheel-down (press+release per notch)
void guest_display_set_ui_size(GuestDisplay*, uint32_t w, uint32_t h);
    // Console.SetUIInfo(0,0,0,0,w,h); the guest's resolution service does the rest
void guest_display_clipboard_grab(GuestDisplay*, const char* const* mimes, int n);
void guest_display_clipboard_reply(GuestDisplay*, uint64_t token,
                                   const char* mime, const void* data, size_t len);

// libvirt, synchronous (tens of ms). Not for the UI thread.
int guest_display_domain_state(const char* domain);   // -1 no such domain, else virDomainState
int guest_display_domain_start(const char* domain);
int guest_display_domain_shutdown(const char* domain);  // ACPI
```

The thread, in order:

1. `virConnectOpen("qemu:///system")`, `virDomainLookupByName`,
   `virDomainOpenGraphicsFD(dom, 0, &fd, 0)` — flags 0, the spike's
   `dom.openGraphicsFD(0, 0)`. Failure → `on_state(FAILED, virGetLastError…)`.
2. Control bus: `sd_bus_new` → `sd_bus_set_fd(bus, fd, fd)` →
   `sd_bus_negotiate_fds(bus, 1)` → `sd_bus_start`. No `set_bus_client`
   (no Hello: there is no bus daemon), no `set_server` (QEMU is the
   authentication server on both sockets; we are the SASL client on both,
   as the spike's `AUTHENTICATION_CLIENT` was). Nothing in the tree has used
   `sd_bus_set_fd` on a p2p socket before — PortalService goes through
   `sd_bus_set_address` (`portal_service.c:1171-1177`) — so this is the first
   thing the probe (below) proves.
3. Listener bus: `socketpair(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC)`; second
   `sd_bus` on our end, same setup, **vtables added before `sd_bus_start`**
   (sd-bus's equivalent of GDBus's `DELAY_MESSAGE_PROCESSING`, which the
   spike needed): `/org/qemu/Display1/Listener` carrying both
   `org.qemu.Display1.Listener` and `org.qemu.Display1.Listener.Unix.ScanoutDMABUF2`,
   plus the `Interfaces` property (`as`, const) naming the latter — QEMU does
   a synchronous `GetAll` on it during registration. Signatures are the ones
   in `dbus-display.py`'s `LISTENER_XML`; `Scanout`/`Update` (the non-dma-buf
   `ay` pixel path, only taken with `gl=off`) are implemented as log-and-ack so
   a misconfigured domain shows a black window rather than a stalled one.
   Methods are `SD_BUS_VTABLE_UNPRIVILEGED` (as `portal_service.c:173-236`)
   as a statement of intent — measured, sd-bus treats this *direct* connection
   as trusted and a bare vtable works too, so unlike on a bus connection this
   is not load-bearing.
4. `Console.RegisterListener(h)` with the other socketpair end, via
   **`sd_bus_call_method_async`** — and from here on **no synchronous call on
   the bus thread, ever** (`dbus-display.py` `cmd_resize` comment: once a
   listener is registered a sync call deadlocks both sides for the 25 s
   timeout, and QEMU reports it as a listener downgrade). `Clipboard.Register`
   likewise.
5. Loop: `poll()` over `sd_bus_get_fd/get_events/get_timeout` of both buses
   plus the eventfd (`ime_bridge.c:370-380`); drain the command queue on wake;
   `on_update` handlers `sd_bus_message_ref(m); return 1;` and the reply is
   built with `sd_bus_message_new_method_return` + `sd_bus_send` when
   `ack_frame` arrives or the 20 ms deadline (folded into the poll timeout)
   passes. `dup()` every received `h` before the message is unreffed. Held
   keys are tracked so `guest_display_close` releases them.
6. Disconnect (either socket hangs up): `on_state(DISCONNECTED)`; no
   auto-reconnect in M1 — one control client per domain, and reconnect on
   stock QEMU has a known trap (§Traps).

**Probe first.** Before any Swift, an executable target `guest-display-probe`
(`shell/Sources/GuestDisplayProbe/main.c`, not staged) that opens a domain,
registers, prints the first scanout's dims/fourcc/modifier/`y0_top` and the
first `CursorDefine`, sends one `SetUIInfo`, and exits. It is the sd-bus
counterpart of `dbus-display.py info` and settles the p2p/SASL/fd-passing
questions in isolation from the shell.

## Phase 3 — The HID → qnum table — **DONE 2026-09-02**

Built ahead of the rest because it depends on none of the open decisions and
is verifiable on macOS. Three files:

- `shell/Sources/DesktopShellApp/Guest/HidQnum.swift` (216 lines, 168 keys):
  `static let pairs: [(hid: UInt64, qnum: UInt32)]` in the `HidEvdev.pairs`
  form, plus a lazily built dictionary and `qnum(forHid:) -> UInt32?`.
  Nothing references it yet.
- `build/tools/gen-hid-qnum.py` — regenerates that file from keycodemapdb's
  `data/keymaps.csv` (`USB Keycodes` × `AT set1 keycode`, the two columns
  `keymap-gen code-map … usb qnum` uses; revision ab223f5d3113, 2024-11-05).
  It takes a local CSV as `argv[1]` to work offline, and its output is
  byte-identical to the checked-in file, so regeneration is a no-op diff.
- `test/hid_qnum.py`, wired into `test/run.sh` after the MCP-framing step:
  the table is non-trivial, no HID usage is mapped twice, **every usage
  `HidEvdev.pairs` can deliver has a qnum**, every qnum is a non-zero single
  byte, and five spot-checks pin the extended encoding. Both files are parsed
  as text, as `test/lint.py` does. Each check was confirmed to fail on a
  mutated table before being kept.

Two facts worth recording. Extended set-1 codes are `0xe0`-prefixed and QEMU
folds the prefix into the high bit (`0xe01c` keypad Enter → qnum `0x9c`);
`0xe1`-prefixed codes (Pause on real set 1) have no qnum encoding and are
skipped, Pause reaching the guest through `0xe046` instead. And the generated
table agrees with the hand-derived `QNUM` dict the M0 spike drove a real guest
with (`docs/windows-vm/dbus-display.py`) on **all 110 names the two share,
with zero mismatches** — an independent check that this table is right, since
that dict is known-working against Windows.

## Phase 4 — Shell: `GuestSession`

New `shell/Sources/DesktopShellApp/Guest/GuestSession.swift` — one per domain,
owned by `DesktopShell` state in a `[String: GuestSession]` keyed by domain;
`Guest/` is a peer of `Wayland/` and `X11/`. It owns the `GuestDisplay*`, the
texture id, the shell window id, the last cursor image, held keys, pending
ack tokens and the resize debounce. Trampolines marshal every callback to the
UI thread with `DispatchQueue.main.async`, the idiom `main.swift` uses for
every engine-thread → UI hop (`:469`, `:517`, and the present callback at
`:850`).

- **Scanout** → `dup` already done by C; on the UI thread, first time
  `registerTexture` (`LinuxTextureRegistry.swift:241`) then `importDmaBuf`,
  every later time `reimportDmaBuf` (it keeps the old EGLImage alive until the
  new one binds, so a resize never flashes black), always `ownsFd: true`,
  offset passed through. **Not** `markAsWaylandSurface` — a guest framebuffer
  is already opaque; if AB24 arrives with garbage alpha, rewrite the fourcc
  to XB24 at import the way `:577-590` does, per-texture. Gate the modifier
  with `wayland_server_dmabuf_modifier_importable(fourcc, modifier)`
  (`wayland_server.h:313`, public) before importing: the spike's buffers are
  modifier INVALID, which always passes, but a virtio-gpu buffer that carries a
  tiled AMD modifier is exactly the case that can abort the shell under
  memory pressure. Then `FrameCallbackScheduler.shared.noteTextureUpdate(id)`
  (`sdk/Sources/Flutter/Scheduler/FrameCallbackScheduler.swift:37`) — texture
  content changes are invisible to the widget dirty flags, this is what makes
  the compositor frame happen.
- **Window** — created on the **first scanout**, not on connect (the child-app
  path does the same at `DesktopShell.swift:8200-8215`: a scanout buffer
  before the guest's first paint is uninitialised GPU memory). Sized to the
  scanout in logical pixels (`px / currentShellDpi`), centred, capped to the
  screen as the X11 template does (`:3560-3570`); if capping changed the size,
  request the capped size × dpi through `set_ui_size` so the guest follows.
  `addWindow(title: rec.name, appId: "guest-\(domain)", textureId:,
  flipTextureY: y0_top, …)` and set `win.wmClass = rec.id` — `_appOwning`
  (`:6496-6502`) matches by `wmClass` second, so the dock icon, running dot
  and menu resolve to `windows.app` without a registry hack. `y0_top` maps
  straight onto `flipTextureY`, which is a widget-layer `Transform`
  (`Window/DesktopWindow.swift:22-27`) also honoured by Mission Control,
  workspace panes and agent captures (`Shell/WorkspaceSpace.swift:447`,
  `Shell/MissionControl.swift:139`, `Shell/AgentBroker.swift:1025`).
- **Update / ack** — `on_update` marks the texture available
  (`FlutterEngineMarkExternalTextureFrameAvailable` + schedule, via
  `markGLTextureDirty`-style call on the registry) and queues the token.
  `main.swift:843-854`'s present callback gains one line,
  `GuestSessions.handlePresent()`, which acks every queued token from that
  thread (`ack_frame` is any-thread). Damage rects are dropped: the compositor
  repaints full surfaces (`wayland_compositor.c:59`, `:334` are no-ops) and
  nothing downstream consumes rects; the rect's only job here is timing.
- **Pointer** — `onPointerEvent(phase, x, y, buttons)`: phases as
  `DesktopWindow.swift:44-90` sends them (2 down, 3 move, 1 up, 6 hover);
  `x*dpi, y*dpi` → `mouse_abs` (guest pixels == physical pixels, because the
  guest renders at content × dpi); button transitions from the `buttons`
  mask → `mouse_button`. `onScrollEvent(x, y, dx, dy)` accumulates logical
  pixels and emits one wheel notch (press+release of 3/4) per line — take the
  per-notch value from `HandlePointerAxis` in `fl_drm_input.cc` on the box
  rather than guessing. Ignore the `buttons` argument's hard-coded `BTN_LEFT`
  precedent at `WaylandIntegration.swift:1331` — track all three.
- **Keys** — a `guest-` branch in `routeKey` beside `wayland-`
  (`DesktopShell.swift:2418`), placed **ahead of the IME check** (`:2401`):
  Windows runs its own IME, and fcitx would otherwise swallow every key. HID
  → `HidQnum` → `guest_display_key`; `.repeat` is delivered as another press
  (PS/2 typematic is exactly that, and the X11 branch at `:2435-2446` set the
  precedent). Unmapped usages are dropped with one log line. Release every
  held key when the window loses focus — `WindowManagerState.focusedWindowId`
  (`WindowManager.swift:246`) is written in five places (`:328, :546, :671,
  :696, :902`); add a `didSet` that notifies the sessions rather than
  patching each. Shell chords (`:2330-2400`) keep winning; Ctrl+Alt+Del is a
  dock-menu item, not a chord.
- **Cursor** — `on_cursor_define` → keep the image; `on_mouse_set(visible:0)`
  → a transparent image. New `DesktopCursor.setImage(_:)`
  (`Utils/DesktopCursor.swift`) calling `fl_drm_view_set_cursor_image`, and
  it must invalidate `lastShape` (`:29`) so the next `setShape(.default)` is
  actually sent. The window's hover handler resets the shape to `.default` on
  every tick (`DesktopWindow.swift:88-90`) — which would clobber the image the
  moment the pointer arrives from a resize edge. Add
  `WindowInfo.onPointerHoverCursor: (() -> Void)?`; `DesktopWindow` calls it
  instead of `setShape(.default)` when set; the guest's re-asserts the
  current image, de-duplicated by a generation counter so hovering does not
  re-upload a BO per event. Leaving the window lands in some other
  `setShape(.default)` (wallpaper `:3802`, title bar, dock) and the arrow
  comes back.
- **Resize** — `onContentResize` debounced 150 ms → `set_ui_size(w*dpi,
  h*dpi)`; `onResizeComplete` sends at once. `TextureWidget` fills the
  content area, so the old scanout stretches until the new one lands
  (30–45 ms in the spike, given `vgpusrv -i`). If no scanout matches within
  1 s the guest is not cooperating: snap the window back to the scanout's
  size, the X11 buffer-resize handler's behaviour (`DesktopShell.swift:3669`).
- **Detach / shutdown** — `onWindowClose` → `guest_display_close` +
  `unregisterTexture` (`LinuxTextureRegistry.swift:253`) + drop the session;
  the domain keeps running. `_buildDockIconMenu` (`:7343`) gets, for
  `kind == .vm` and running, "Shut Down Windows" (`domain_shutdown` off the UI
  thread) and "Send Ctrl+Alt+Del". `AgentBroker.swift:712` refuses `.vm` next
  to `.x11`/`.android` with the same reasoning (one window for the whole
  session).

## Phase 5 — Registry and launch

- `AppRecord.Kind`: `case vm` — "a VM console; `Domain` names the libvirt
  domain". `AppRegistry.makeRecord` (`:182-259`) parses `Domain`; `probe`
  (`:361-378`) arm: `bins` like `.host` — `Bins=/usr/bin/virsh` is the
  cheapest honest "libvirt is here" (the registry package must not link
  libvirt; the App Store loads it too), and "no such domain" is reported by
  the launch arm, in the shell, where a notice can be shown.
- `registry/catalog.d/windows.app`: `Kind=vm`, `Domain=windows`,
  `Bins=/usr/bin/virsh`, `Name=Windows`, glyph/colour, `Order`, no `Dock`
  (launcher-only until pinned), no `Install` (the installer is a later
  milestone). `STARLING_GUEST_DOMAIN` overrides `Domain` for the dev box,
  where the working domain is `win11-dbus`; `build/run-desktop.sh` forwards
  it only when non-empty (the empty-string trap, CLAUDE.md).
- Launch arm at `DesktopShell.swift:8021`: existing-window focus is already
  handled above the switch (`:8011`, via `_appOwning`, which now matches by
  `wmClass`). Otherwise: `_pendingAppLaunches.insert` for the dock bounce;
  off the UI thread, `domain_state` → start if shut off → `guest_display_open`;
  `FAILED` clears the spinner and posts a notification through the existing
  notification path with libvirt's message ("no such domain", "permission
  denied" — the two a fresh box will actually hit).
- `test/lint.py` (`:170-246`): `Kind=vm` requires `Domain=`; `Domain=` on any
  other kind fails. `registry/catalog.d/README.md` key table gains `Domain`
  and the `vm` kind.

## Phase 6 — Clipboard, text only

Host→guest works on stock QEMU (qemu-vdagent in the domain; spike Results A);
guest→host needs `docs/windows-vm/triton/patches/0003` and was not verified,
so it is built but marked contingent.

- `GuestDisplay` exports `/org/qemu/Display1/Clipboard` on the control bus
  (`dbus-display.py` `CLIPBOARD_XML`) and calls `Register` async after the
  listener is up.
- Shell side takes the survey's recommended door: `GuestSession` is a
  `zwlr_data_control_v1` client of our own compositor through `wlclip_*`
  (`sdk/Sources/WaylandClipboardBridge/include/WaylandClipboardBridge.h:46-63`),
  exactly as first-party apps are (`docs/plans/clipboard.md` is explicit that
  the shell must not broker a pull-based clipboard). Selection changes →
  `clipboard_grab(["text/plain;charset=utf-8"])`; guest `Request` →
  `wlclip_read_text` → `clipboard_reply`; guest `Grab` (patched QEMU only) →
  `Request` the text → `wlclip_set_text`. Loop guard: ignore our own grabs
  (`wlclip_owns_selection`).

## Phase 7 — Packaging, guest prep, docs, tests

- `docs/BUILDING.md:245-255` apt list gains `libvirt-dev`; the .deb's
  `Depends` picks up `libvirt0` from dpkg-shlibdeps. The session user needs
  read-write `qemu:///system`, i.e. membership of `libvirt` — documented in
  `docs/WINDOWS-VM.md`, not done by the package (§Open decisions).
- `docs/WINDOWS-VM.md` §"The dbus display" becomes the guest-prep section M1
  depends on: `HWCursor=1` under the display-class key, `vgpusrv.exe -i`,
  `powercfg /change monitor-timeout-ac 0` (and `-dc`), `<graphics type='dbus'
  p2p='yes'><gl enable='yes' …/>` in the domain (`docs/windows-vm/win11-dbus.xml:177-179`),
  and the one-client rule. The Python tools move under a "protocol reference"
  heading.
- `test/functional.py`: one check, `guest: windows.app opens the domain's
  console`, `Skip` unless `virsh -c qemu:///system domstate $STARLING_GUEST_DOMAIN`
  succeeds (the pattern at `:393`): launch through the launcher, wait for
  a window owned by `windows`, `capture` it and assert non-black, inject the
  Super key and assert the capture changed (Start menu), close it, assert the
  domain is still `running`.
- `docs/plans/windows-home-vm.md`: M1 checkbox, pointer to this file.

## Verification (the Linux dev box)

1. Engine: build **both** out dirs; `nm -D … | grep set_cursor_image` in each.
2. `guest-display-probe win11-dbus` on **stock** 26.04 QEMU (10.2.1) — the
   shipping target; the patched Triton build is for comparison only. Expect
   the spike's first scanout (placeholder 1920×1080 XB24, then the guest's,
   AB24, one plane, INVALID, `y0_top=true`), a `CursorDefine` after a mouse
   move (only with `HWCursor=1`), and a fresh scanout ≤50 ms after `SetUIInfo`.
3. `test/run.sh` (lint + `hid_qnum.py`) after every shell change; then
   `build/build-all.sh && STARLING_GUEST_DOMAIN=win11-dbus build/run-desktop.sh`.
4. Launcher → Windows: a window with the desktop in it, right way up (if it is
   upside down, `y0_top` went the wrong way — compare against `wshot.py`, which
   the spike already got right). `shell-drive.py` shot to prove it.
5. Type into Notepad (letters, Shift, arrows — extended keys are the `0x80`
   set); drag-resize the window and watch the resolution follow; move the
   pointer over a link and see the hand cursor; minimise, and confirm the
   guest is not stalled (the deadline ack) by un-minimising to a live clock.
6. Close the window, reopen from the launcher — proven at the probe level
   (reattach works on stock QEMU); confirm it through the real window too.
   Guest reboot is the 0001 crash, already characterised; re-test once the
   decision below is made.
7. Unprivileged: `LIBSEAT_BACKEND=seatd /usr/libexec/starling-session` over SSH
   as `starling` (CLAUDE.md: a privilege-gated path differs from the dev path)
   — this is where `libvirt` group membership and the cross-uid SASL handshake
   are actually exercised.
8. `sudo test/run.sh --functional` with `STARLING_GUEST_DOMAIN=win11-dbus`.

## Traps

Carried from the spike, all of which look like something else:

- **A synchronous D-Bus call after `RegisterListener` deadlocks for 25 s** and
  QEMU logs it as the listener downgrading. Every call is async; the probe
  enforces it by having no sync path at all.
- **One control client per domain.** A second `openGraphicsFD` closes the
  first. `wshot.py`/`dbus-display.py` and the shell cannot share a domain —
  running either while the window is open kills the window, and it looks like
  a shell crash.
- **`y0_top` is inverted relative to its name** — row 0 is the bottom when it
  is true. Set `flipTextureY` from it and check a real frame, not the doc.
- **No `CursorDefine` without `HWCursor=1`** in the guest; the Windows cursor
  is then painted into the framebuffer and our plane shows the arrow on top.
- **Guest reboot with a listener registered kills the VM** unless QEMU carries
  `patches/0005` — `patches/0001` does **not** cover it, and dropping the
  listener on `Disable` does not either (both measured). A desktop running on
  an unguarded QEMU will lose the VM to a Windows Update restart.
- **A disconnected listener staying registered** (patch `0002`) does not
  reproduce on 10.2.1: reattach after close works, measured.
- **`powercfg` monitor timeout** blanks the console after 10 min; it reads as
  a scanout bug.

New here:

- **Stride is not `width*4`** (1400 px came back as 5632 bytes) and the buffer
  is bigger than `stride*height`. Import with what the message says.
- **`y0_top` changes between scanouts of the same window** — placeholder 0,
  real buffer 1 — so `flipTextureY` is per-frame state.
- **The received `h` is owned by the message.** `dup()` before unref, then
  hand ownership to the texture registry (`ownsFd: true`); the Wayland path
  learned this at `WaylandIntegration.swift:883`.
- **Import through the modifier gate.** INVALID always passes; the gate is
  for the day the guest is Triton or a different QEMU allocates tiled.
- **The window hover resets the cursor every tick** (`DesktopWindow.swift:89`);
  without the hover hook the guest cursor lasts until the pointer crosses a
  resize edge.
- **`fl_drm_view_add_external_fd` is before-run only.** Own thread, not the
  engine loop, or the second VM opened in a session cannot register.
- **IME goes first in `routeKey`.** With fcitx on, a guest branch placed after
  it never sees a key.

## Open decisions

- **Domain name.** `Domain=windows` in the shipped record (the installer
  milestone will create that domain) with `STARLING_GUEST_DOMAIN` for the dev
  box's `win11-dbus`. Alternative: `virsh domrename win11-dbus windows` on the
  dev box and no override — but `docs/WINDOWS-VM.md` names `win11-dbus`
  throughout. **Recommendation: the override.**
- **Close semantics.** Detach and keep the VM running (recommended: reopening
  is instant, and nothing the user did not ask for shuts down their Windows);
  the dock menu carries the explicit shutdown. Alternative: close = ACPI
  shutdown, which matches "quit" for every other app but makes closing the
  window a 20 s operation.
- **`libvirt` group.** Document it (recommended for M1) versus `postinst`
  adding the session user to `libvirt` — a distro package granting VM control
  silently is the kind of thing a reviewer rejects; the installer milestone
  is the right place to make it deliberate.
- **Which QEMU M1 ships against — SETTLED 2026-09-02: we ship our own QEMU
  binary.** Not "wait for Ubuntu", not "upstream first and hope". Upstreaming
  `0005` is still worth doing on its own merits — it is three words of C and
  fixes a crash any `dbus-display` user with `gl=on` can hit — but nothing
  here waits on it.

  What that decision buys, which is more than it looks: a Starling QEMU can
  carry **`0003`** as well, and `0003` is the whole of guest-to-host
  clipboard. Phase 6's second half was written up as "built but contingent"
  purely because it needed a patch we were not going to ship. It is not
  contingent any more; it is just work.

  What it costs: the .deb has to carry or depend on that binary, and
  `docs/BUILDING.md` needs the recipe that produces it. The patches are
  `docs/windows-vm/triton/patches/000{1,3,5}` — the desktop needs `0001`
  (a texture created without a current context) and `0005` (a `gfx_switch`
  that arrives before any texture exists, which kills the VM on a guest
  reboot); `0003` is the clipboard.


---

# Status (2026-09-02)

**Windows runs in a window on the desktop.** Phases 1, 2, 3 and 5 are complete;
Phase 4 is complete except the clipboard hook it shares with Phase 6. Verified
live on the Lenovo against `win11-dbus`, on **stock** Ubuntu 26.04 QEMU 10.2.1:

- The launcher shows a **Windows** tile from `registry/catalog.d/windows.app`
  alone — no table anywhere in the shell.
- Clicking it opens the domain's display and imports the guest's scanout as a
  dma-buf: `3840x2112 stride=15360 AB24 modifier=INVALID`. Dock icon, running
  dot and tooltip resolve through `wmClass`, with no registry special case.
- **Pointer** — clicking the guest's Start button opened the Start menu.
- **Keyboard** — typing `notepad` reached Windows Search, which offered
  Notepad; Escape closed it. Both through `HidQnum`, ahead of fcitx.
- **Resize** — maximising made the guest re-render at 3840x2112 natively
  (`SetUIInfo` answered with a fresh scanout), not scale a smaller desktop up.
- **Close is detach** — `virsh domstate` said `running` afterwards, and
  reopening from the launcher reconnected and re-imported at once.
- The C target has its own harness, `build/tools/guest-display-selftest.c`,
  which drives `GuestDisplay` against a domain with no shell in the way:
  connect in 10 ms, the placeholder XB24 scanout then the real AB24, SetUIInfo
  answered in 35 ms, 52 acked frames, a repaint 158 ms after a scancode,
  reattach after a clean close, and a close that returns in 1 ms having
  released a held key.

**What the plan got wrong, and the code now records.**

- **`y0_top` maps to `flipTextureY` INVERTED, and the plan said to set it
  directly.** Two inversions cancel: QEMU's `y0_top` is true for a
  bottom-up GL texture, and `flipTextureY` is the flip this shell applies to a
  TOP-DOWN buffer. Setting `flipTextureY = y0_top` puts the Windows taskbar at
  the top of the window — which is exactly what the first run showed. It is
  `!y0_top`.
- **`CLibvirt` is not needed.** Every libvirt call lives inside the
  `GuestDisplay` C target, so nothing Swift-side wants its headers; one target,
  not two.
- **The probe was already written.** `docs/windows-vm/guest-display-probe.c`
  from the M0 spike answered the sd-bus question, so Phase 2's
  `GuestDisplayProbe` target was replaced by a selftest of the shipping code.
- **`Package.swift` cannot take an inline `sdbusLinkerSettings + [...]`** in
  the targets literal — the manifest stops type-checking, exactly as its own
  comments warn. Hoisted to `guestDisplayLinkerSettings`.

**The last mile, run 2026-09-02 (second pass).**

- **Unprivileged works.** `STARLING_SEAT_MODE=libseat build/run-desktop.sh`
  over SSH puts the shell on uid 1000 with no sudo in the launch path, and the
  guest display connects from there: the cross-uid SASL handshake to QEMU
  (which runs as `libvirt-qemu`) needs nothing beyond `libvirt` group
  membership, which is the documented requirement and nothing more. Windows
  opened, filled the usable area and took input exactly as under root.
- **Drag-resize does work** — the earlier failure was a grab point, not the
  code. Dragging the right edge in by 500 logical px logged
  `ask for 3090x2055` and the guest re-rendered at 3090x2055 (stride 12800,
  padded from 12360). Note the bottom edge of a full-height window sits under
  the dock, so it cannot be grabbed; that is the macOS overlay dock behaving
  as designed, not a guest bug.
- **The reopen shrink is fixed.** `openWindow` now caps to the USABLE area
  (`screenH - topInset - bottomInset`), which is what `_outputFillRect` clamps
  to anyway. A guest bigger than that is asked once for the usable size and
  then matches it, so the second open asks for nothing. Previously the window
  was capped to the panel, clamped afterwards, and the guest followed the
  clamp — losing the inset every time it was reopened.
- **An invisible guest pointer now falls back to the desktop's arrow.** QEMU
  reports `MouseSet(on=0)` at connect, before the guest has drawn a pointer —
  so this is the state on the FIRST hover every time, and uploading a
  transparent image (the original behaviour) lost the human's pointer inside
  the window with nothing to aim with. On a real machine "hidden" means no
  pointer; in a window it has to mean the ordinary one.
- **QEMU does not replay `CursorDefine` on reconnect.** A fresh session shows
  the desktop arrow over the guest until Windows next changes cursor shape.
  Harmless now that the fallback is an arrow rather than nothing, but it is
  why a reconnected session logs no `first cursor` line.

**Phase 6, host to guest, done 2026-09-02.** Copying in a desktop app and
pasting inside Windows works: `wl-copy` on the host, Ctrl+V in the guest's
search box, and the text appears. The shell is a `zwlr_data_control_v1` client
of its own compositor (`WaylandClipboardProvider`), announces a `Grab` when the
desktop's selection changes to something textual, and answers the guest's
`Request` with the selection as it is at paste time.

Three things this needed that the plan did not name:

- **The bridge had no selection-changed signal at all** — it could set, read
  and report ownership, and nothing else. `wlclip_set_selection_callback` is
  new, and `WaylandClipboardProvider` exposes it as `onSelectionChanged`
  alongside `ownsSelection`. The `mine` flag is the loop guard: answering the
  guest's paste makes US the selection owner, and announcing that back would
  be one announcement per paste, for ever.
- **A `Grab` with serial 0 is not a grab.** QEMU orders grabs by the serial;
  the first version passed the unused command token, which is 0, and the guest
  never saw a thing. Serials now start at 1 and only go up.
- **`Register` must be async and the reply is worth reading.** QEMU's Register
  handler does a synchronous `GetAll` on OUR object before replying, so the
  reply cannot arrive until the bus thread is back in its poll loop — the same
  rule as the listener. It logs `clipboard Register: ok`, which is what
  distinguishes "the guest ignored us" from "we were never registered".

**Phase 6, guest to host, done 2026-09-02** — once the decision to ship our
own QEMU made `0003` shippable. Copying inside Windows and running `wl-paste`
on the desktop returns the text. The guest's `Grab` triggers a `Request` back
out to QEMU, and the answer becomes the desktop's selection through
`wlclip_set_text`; setting it makes us the owner, so the `mine` guard on the
next selection change stops the two clipboards announcing to each other for
ever.

The one thing it needed beyond the plan: **QEMU allows exactly one outstanding
clipboard `Request`.** A second is refused with "Pending request", which is
what a burst of guest grabs produces — Ctrl+A then Ctrl+C is two of them. So
pulls are serialised, and a grab arriving mid-pull is remembered rather than
dropped, because the content it announced is newer than the one being fetched.

**Testing it needs a domain that has both halves**, and neither dev-box domain
did: `win11-dbus` has the guest agent but runs stock QEMU, and `win11-dbuspatch`
runs the patched build but is a separate overlay on `win11-snap` with no agent
installed. The rig is an overlay on the domain that HAS the agent, run under
the patched emulator:

    qemu-img create -f qcow2 -b /var/lib/libvirt/images/win11-dbus.qcow2 \
        -F qcow2 /var/lib/libvirt/images/win11-clip.qcow2
    virsh dumpxml win11-dbuspatch | sed -e 's|<name>win11-dbuspatch</name>|<name>win11-clip</name>|' \
        -e '/<uuid>/d' -e 's|win11-dbuspatch.qcow2|win11-clip.qcow2|' > /tmp/win11-clip.xml
    virsh define /tmp/win11-clip.xml

**Delete it when done** (`virsh undefine win11-clip; rm …win11-clip.qcow2`):
while that overlay exists, booting `win11-dbus` writes to its backing file and
corrupts it. Also note `vdservice` starts before `vdagent` — the session agent
appears a minute or so after the guest agent answers, and until it does the
guest never grabs.

**Two bugs the clipboard work uncovered, both unrelated to it.**

- **A resize could leave the window black.** QEMU answers a mode change with
  its placeholder XB24 buffer and then the guest's real AB24 one AT THE SAME
  SIZE. The scanout handler chose `reimportDmaBuf` vs `importDmaBuf` on
  whether the dimensions changed — and only reimport sets `needsReimport`, so
  the second buffer took the path that rebinds the EGLImage it already has and
  ignores the new fd. The placeholder stuck. A scanout now ALWAYS reimports:
  it means "here is a different buffer" by definition, and same-buffer damage
  goes through `noteDmaBufContentChanged` instead.
- **Pointer coordinates were mapped by dpi, not by the content rect.** The two
  agree only while the guest's buffer is exactly the window's content size
  times the scale — false for the whole interval between asking for a resize
  and the guest answering, and false for ever if the guest refuses the mode.
  In that state every click lands somewhere else inside Windows and the window
  reads as unresponsive rather than mis-aimed.

**Open.**

- **The guest's cursor is drawn, but has not been PROVEN to be the guest's.**
  Investigated properly 2026-09-03, and the earlier claim here — "no capture
  can show the cursor plane" — was wrong. The shell's own Control Centre has
  **Record** and **Record App**, and both composite the plane through
  `RenderSnapshotRGBA`, which is exactly the Phase 1 code. Driving that
  (control centre at logical 2505,15; the tiles at 2292,214 and 2432,214;
  then a window card in the picker) produces an MP4 under `~/Videos` with a
  cursor composited at the pointer position over the guest window. So the
  chain runs end to end: the guest sends `CursorDefine`, the shell calls
  `fl_drm_view_set_cursor_image`, and something is on the plane and in the
  capture.

  What could NOT be settled is whether that something is the guest's bitmap
  or the shell's own baked arrow, because **both are the classic arrow** and
  H.264 destroys the one property that separates them. The measurements, so
  nobody repeats them:
  - anti-aliasing is the real discriminator (the guest's cursor reports 67
    partially-transparent pixels; `kBitmapDefault` is pure black/white by
    construction) — but the codec manufactures its own edge ramps, so a grey
    count proves nothing either way;
  - shape does not separate them: the baked arrow's left edge is vertical for
    17 of 21 rows and then notches right by 7, and the recorded cursor is
    vertical for 13 of 19 and notches right by 8. Different proportions,
    within what scaling and blur can do.

  The test that WOULD settle it is an A/B against a first-party window, where
  the plane certainly holds the shell's arrow, through the identical capture
  and codec path — different cursors means the guest's image is reaching the
  plane. It was not run because child apps would not launch in that session
  (`list_apps` kept reporting `settings window=false`). The other decisive
  option is making the guest's cursor a *different shape* — hovering a text
  field gives an I-beam, which an arrow can never be blurred into.

  Both are half an hour with a working desktop, and neither needs new code.
- **Phase 6's guest-to-host half** needs a `Request` call out to QEMU and a
  patched build to test against (`win11-dbuspatch` carries 0003).
- **Phase 7**: `docs/BUILDING.md` has `libvirt-dev`; the functional check, the
  `docs/WINDOWS-VM.md` guest-prep rewrite and the `windows-home-vm.md`
  checkbox are not written.
- **A guest reboot still needs a patched QEMU** (`triton/patches/0005`). The
  desktop was tested on stock 10.2.1 and never rebooted the guest.
