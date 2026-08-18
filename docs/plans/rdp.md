# RDP server — see the desktop from an RDP client, and click on it

> This is **share mode**: RDP mirroring a DRM/KMS desktop on real hardware.
> For **display mode** — RDP *as* the display, no `/dev/dri`, the WSL story —
> see `docs/plans/rdp-wsl.md`. The two share `shell/Sources/RdpServer/`.

The scope is deliberately small: `xfreerdp` (or mstsc) connects over
TCP+TLS, sees the live desktop, and the mouse works — move, left/right
click, wheel. Everything else RDP can do is a non-goal below. The point of
v1 is the plumbing: once frames flow out and pointer events flow in, every
follow-up (keyboard, clipboard, egfx) is an increment on a working pipe.

## Non-goals (v1)

- **Clipboard**, **audio** — separate virtual channels, separate plans.
- **H.264 / GFX (egfx) pipeline** — v1 is SurfaceBits + RemoteFX/raw.
- **Headless / virtual output** — RDP mirrors the physical primary output.
- **Client-driven resize** (Display Control channel), **multi-monitor** —
  the desktop is the primary output's size; the client adapts or letterboxes.
- **NLA auth** — v1 is TLS only, which means **no authentication beyond
  possession of the network path. LAN/dev use only.** NLA is the first
  fast-follow and a hard prerequisite for any default-on story.
- **Keyboard** — deferred by choice, not difficulty: it is ~a day on the
  same inject path (`fl_drm_view_inject_key`, RDP scancode → evdev is
  nearly identity, then the existing `HandleKeyboard` evdev→HID+xkb path).
- **Damage tracking** — v1 sends full-surface updates at a capped fps.
- **RDP pointer-update messages** — the cursor is already composited into
  captured frames, so the remote user sees it for free. Known artifact:
  the client's local pointer AND the remote-drawn cursor are both visible.

## Architecture

Three existing mechanisms carry almost all of it:

```
 engine capture (writer thread)          FreeRDP peer thread
   fl_drm_view_recording_start ──► RdpService.ingest ──► depth-1 mailbox ──► rfx encode ──► SurfaceBits ──► TLS ──► client
                                                                                                             │
 engine platform thread ◄── fl_drm_view_post_task ◄── fl_drm_view_inject_pointer_abs ◄── MouseEvent ◄────────┘
   (FlDrmInput state + hw cursor MoveTo)
```

- **Frames**: the CPU capture sink (`fl_drm_view_set_record_frame_callback`
  + `fl_drm_view_recording_start`) — top-down RGBA per presented frame,
  cursor already composited, fps capped via
  `fl_drm_view_recording_set_max_fps`. Presents are content-driven, so an
  idle desktop sends nothing — exactly what RDP wants.
- **Service shape**: `RdpService` is a sibling of `ScreenCastService`
  (`shell/Sources/DesktopShellApp/Recording/ScreenCastService.swift` is the
  template, near line-for-line): same `.idle/.starting/.live/.draining`
  state machine, same `needsFramePump`/`needsPrimingRebuilds`, same
  pumpTick-observes-the-drain shutdown.
- **C shim**: `shell/Sources/RdpServer/` wraps libfreerdp-server3 the way
  `shell/Sources/PipeWireCast/pwcast.c` wraps PipeWire — a plain C target,
  `publicHeadersPath: "include"`, callbacks out to Swift thunks.
- **Input**: a new engine C API (decision below) that feeds the same
  virtual-desktop pointer state libinput events use.

### The single capture session, now with three claimants

The engine runs EXACTLY ONE capture session. RecordingService and
ScreenCastService already mutually exclude each other, and main.swift's
frame trampoline (main.swift ~line 851) routes each frame to whichever
service owns it. RDP joins the same scheme:

- Trampoline gains a third branch: `RdpService.captureActive` is checked
  first (or second — order is arbitrary, exclusivity makes it moot).
- `RdpService` claims the capture **on peer activation**, not on listen —
  an idle listener costs nothing and blocks nothing.
- All three `start` paths refuse while another claimant is active:
  `RecordingService.start` (line ~456) and `ScreenCastService.startSession`
  (line ~84) each gain a `!RdpService.captureActive` guard; `RdpService`
  activation checks both `fl_drm_view_recording_active()` and
  `ScreenCastService.captureActive`.
- **Stated v1 limitation**: you cannot screen-record or portal-share while
  an RDP client is connected, and vice versa. The losing side gets a clean
  refusal (recording toast / portal failure / RDP disconnect), not a hang.

### The frame pump: floor, not source

The frame-tick pump (`Shell/DesktopShell.swift` lines 1110-1180) is a
LIVENESS FLOOR — full-rate rebuilds saturate the pipeline and starve real
presents (this is what once pinned recordings to 10fps; the comment at line
1163 is load-bearing). RDP rides it exactly like ScreenCastService:

- `needsFramePump` while non-idle (presents carry start/stop requests and
  the frames themselves; the stop is never observed without them).
- `needsPrimingRebuilds` only in `.starting` — the PBO ring needs a few
  presents to surface the first frame, and RDP activation should not show
  black for seconds. Once `.live`, floor rate only: a static desktop
  produces few frames, which is the point.

## Input path decision

Two candidates were on the table:

**(a) uinput absolute pointer** (what `build/shell-drive.py` does): zero
engine changes, proven — the engine's `HandlePointerMotionAbsolute` already
maps absolute devices onto the primary output. But `/dev/uinput` is
root-only: fine on the dev box (shell runs as root), **broken in the
packaged session** (shell runs unprivileged under libseat/GDM). Fixing it
means a udev rule in `build/session/` — a privilege-path change, which
triggers the `test/vm.sh` gate.

**(b) engine inject API** — **chosen**. The shipped session is
unprivileged, so (a) dead-ends exactly where it matters; (b) works
unprivileged, works in the VM, needs no packaging or privilege change, and
the same pattern carries keyboard later. Cost: an engine change (both repos
commit, engine branch `starling`, host_debug AND host_release rebuilds; a
release build must set `STARLING_ENGINE_OUT` to host_release or it links
debug). shell-drive's uinput path remains available as a zero-code way to
sanity-check the frame pipe before the engine API lands.

The API:

```c
// Inject an absolute pointer event in PRIMARY-OUTPUT PHYSICAL pixels.
// buttons is the absolute Flutter button mask (1=primary, 2=secondary,
// 4=middle); wheel deltas in scroll units. Safe from any thread —
// marshalled to the platform thread via the post-task trampoline.
FL_DRM_EXPORT void fl_drm_view_inject_pointer_abs(FlDrmView* view,
                                                  double x, double y,
                                                  int64_t buttons,
                                                  double wheel_dx,
                                                  double wheel_dy);
```

Implementation notes (all verified against current source):

- `FlDrmInput::InjectPointerAbs(FlutterEngine engine, ...)` mirrors
  `HandlePointerMotionAbsolute`'s transform (fl_drm_input.cc:304-316):
  under `state_mutex_`, `vx_ = p.logical_x + x / p.scale` against the
  primary region — so scale and multi-output placement stay correct, and
  the RDP client's 1:1 framebuffer-pixel coordinates land where they
  should. Phase (down/up/move/hover) is derived by diffing the incoming
  mask against `buttons_`, then the mask **replaces** `buttons_`
  (last-writer-wins with the physical mouse; contention is out of scope).
  Wheel deltas go out as a hover/move with scroll deltas, same as
  `HandlePointerAxis`.
- `engine_` is set lazily by `ProcessEvents` — the inject method takes the
  engine explicitly (`view->engine`), like `ProcessEvents` does.
- The C wrapper heap-boxes the args and rides `fl_drm_view_post_task`
  (same boxing pattern as the host-switch trampoline, main.swift:397).
  After injecting, it repeats the `CursorPlacement()` + `cursor.MoveTo()`
  dance from the input-fd epoll branch (fl_drm_view.cc:2707-2709) —
  **without this the hardware cursor sprite never moves, and since the
  remote view's visible cursor IS that sprite composited into capture
  frames, the remote user would see a frozen pointer.**
- No exports change: `drm_exports.lst` exports `fl_drm_view_*` by wildcard.

## The C shim: `shell/Sources/RdpServer/`

`rdp_server.c` + `include/rdp_server.h`, modelled on pwcast.c (212 lines;
this one is bigger). Linked, not dlopen'd — `libfreerdp-server3-3` ships in
Ubuntu 26.04 and `dpkg-shlibdeps` picks up the dependency from the staged
binary automatically. Crib peer lifecycle from weston's RDP backend and
FreeRDP's `server/shadow` (same library, same 3.x API).

Surface (callbacks fire on RdpServer's own threads; Swift thunks are
C-convention globals, the `portalScreenCastStartThunk` pattern):

```c
typedef struct RdpServer RdpServer;
typedef struct {
    // Peer activated: desktop is w×h, claim the capture. Return 0 to accept.
    int  (*on_activated)(void* ud, uint32_t w, uint32_t h);
    void (*on_disconnected)(void* ud);
    // Absolute px + Flutter button mask + wheel, translated from
    // PTR_FLAGS_* by the shim (it owns the mask bookkeeping).
    void (*on_pointer)(void* ud, double x, double y, int64_t buttons,
                       double wheel_dx, double wheel_dy);
} RdpServerCallbacks;

RdpServer* rdp_server_start(const char* bind_addr, int port,
                            const char* cert_path, const char* key_path,
                            uint32_t desktop_w, uint32_t desktop_h,
                            const RdpServerCallbacks* cbs, void* ud);
void rdp_server_stop(RdpServer* s);
// Called from RdpService's mailbox consumer: top-down RGBA, full surface.
// Copies/encodes on the caller's thread; never blocks the capture callback
// (the caller IS already off the capture thread — see threading).
void rdp_server_push_frame(RdpServer* s, const uint8_t* rgba,
                           uint32_t w, uint32_t h);
int  rdp_server_client_connected(RdpServer* s);
```

Inside:

- `freerdp_listener_new()` → `listener->Open(bind_addr, port)`; a listener
  thread waits on `listener->GetEventHandles` and calls
  `CheckFileDescriptor`. Port 3389 is unprivileged — no root needed.
- `PeerAccepted`: **single client; a second connection is refused**
  (closed immediately). Refuse, not replace: replace adds a
  drain-and-reclaim race against the capture state machine for zero v1
  value.
- Peer settings before `Initialize`: `TlsSecurity=TRUE`,
  `RdpSecurity=FALSE`, `NlaSecurity=FALSE`; certificate/key via
  `freerdp_certificate_new_from_file` / `freerdp_key_new_from_file` into
  `FreeRDP_RdpServerCertificate` / `FreeRDP_RdpServerRsaKey`;
  `DesktopWidth/Height` forced to the primary output's physical size in
  PostConnect (server wins the size negotiation; client-side smart-sizing
  handles the rest). `RemoteFxCodec=TRUE`, `NSCodec=TRUE`, 32bpp.
- Per-peer thread: `WaitForMultipleObjects` on the peer's transport handles
  plus a frame event; `CheckFileDescriptor` for protocol traffic,
  `input->MouseEvent`/`MouseEventEx` → PTR_FLAGS translation → `on_pointer`.
- Encode: after activation, check what the client actually negotiated —
  `RemoteFxCodec` → `rfx_context` SurfaceBits (64px tiling handled by the
  codec), else `NSCodec` → `nsc_context`, else raw bitmap updates. This is
  weston's exact ladder. Frame markers if `FrameMarkerCommandEnabled`.
- **Pixel format**: capture frames are RGBA (R at byte 0) = FreeRDP's
  `PIXEL_FORMAT_RGBX32`. Try `rfx_context_set_pixel_format(ctx,
  PIXEL_FORMAT_RGBX32)` first — if the codec path only behaves with BGRX,
  swizzle in the encode thread (`freerdp_image_copy` or a 20-line loop;
  at 15fps full-surface it is noise next to the RFX transform itself).

## Threading (the whole contract in one place)

| thread | does | must never |
|---|---|---|
| engine writer thread | `RdpService.ingest`: copy into depth-1 drop-oldest mailbox, signal, return | encode, send, take slow locks |
| RdpServer peer thread | drain mailbox → swizzle → rfx encode → TLS send; RDP input dispatch | touch shell state directly |
| engine platform thread | injected pointer events (via post_task), hw cursor MoveTo | — |
| main queue | pumpTick: observe drain, release capture | — |

Backpressure falls out of the mailbox: a slow client blocks its own peer
thread in `send`, frames overwrite each other in the mailbox, and the
client simply sees the newest frame when it catches up. Nothing upstream
ever waits.

## Config and security posture

Off by default. Opt-in via environment (read in main.swift, the
`STARLING_SIM_OUTPUTS` pattern):

- `STARLING_RDP=1` — enable; anything else, no listener, zero cost.
- `STARLING_RDP_PORT` — default 3389.
- `STARLING_RDP_CERT` / `STARLING_RDP_KEY` — PEM paths; when unset, a
  self-signed cert is generated on first enable (`openssl req -x509
  -newkey rsa:2048 -days 3650 -nodes`) into
  `<login user's home>/.config/starling/rdp/` (the `LoginUser` helper,
  `Utils/LoginUser.swift`), key chmod 600 — and chowned to the login user
  when the shell runs as root (dev mode), so the packaged unprivileged
  session can reuse it.

**Honest v1 posture: TLS with no NLA means anyone who can reach the port
controls the desktop's mouse and sees the screen. This is a LAN/dev
feature. NLA is the first fast-follow; nothing defaults on before it.**

## Milestones

### M0 — dev-box spike (connect + render + mouse, fewest moving parts)

Engine (branch `starling`; rebuild `ninja -C engine/src/out/host_debug
libflutter_engine.so libflutter_linux_drm.so`):

| file | change | ~lines |
|---|---|---|
| `engine/src/flutter/shell/platform/linux_drm/fl_drm_input.h` | declare `InjectPointerAbs` | +10 |
| `engine/src/flutter/shell/platform/linux_drm/fl_drm_input.cc` | transform + phase diff + SendPointerEvent under `state_mutex_` | +70 |
| `engine/src/flutter/shell/platform/linux_drm/fl_drm_view.h` | API decl + contract comment | +25 |
| `engine/src/flutter/shell/platform/linux_drm/fl_drm_view.cc` | boxed post_task wrapper + cursor MoveTo | +45 |

Shell:

| file | change | ~lines |
|---|---|---|
| `shell/Sources/RdpServer/rdp_server.c` | listener, one peer, TLS from env-provided cert (no autogen yet), **RFX-only** (refuse non-RFX clients), mouse | ~450 |
| `shell/Sources/RdpServer/include/rdp_server.h` | API above | ~70 |
| `shell/Package.swift` | RdpServer target (pwcast pattern, `-lfreerdp-server3 -lfreerdp3 -lwinpr3`, freerdp3 include dirs) + shellDeps entry | +18 |
| `shell/Sources/DesktopShellApp/Recording/RdpService.swift` | state machine, mailbox, capture claim on activation, pointer thunk → inject API | ~220 |
| `shell/Sources/DesktopShellApp/main.swift` | env gate, service init, third trampoline branch | +25 |
| `shell/Sources/DesktopShellApp/Shell/DesktopShell.swift` | pump branch (tick + priming rebuilds + pumpTick) | +10 |

Exit criteria: `xfreerdp /v:devbox /cert:ignore` shows the live desktop;
moving the mouse moves the (remote-drawn) cursor; click opens the
launcher; wheel scrolls; disconnect releases the capture and a recording
can start afterwards. `sudo apt-get install freerdp3-dev` on the dev box
first. Estimate: **3-4 days** (one of them engine).

### M1 — basic shippable (the scope at the top, packaged)

| file | change | ~lines |
|---|---|---|
| `rdp_server.c` | NSC + raw-bitmap fallback ladder; frame markers; second-connection refusal hardening; clean peer teardown/reconnect | +180 |
| `RdpService.swift` | cert autogen + perms/chown; `STARLING_RDP_FPS` (default 15 → `recording_set_max_fps`); refusal guards added in RecordingService + ScreenCastService | +80 across 3 files |
| `docs/BUILDING.md` | `freerdp3-dev` in the apt block (§2.1) + one paragraph | +10 |
| `build/package-desktop.sh` | verify `dpkg-shlibdeps` picked up `libfreerdp-server3-3` from the staged shell binary (it computes Depends from ELF objects — expected zero-change, confirm in the built .deb) | 0 |
| `test/tools/rdp_probe.c` + `test/functional.py` | see test plan | ~260 |
| `docs/plans/rdp.md` | this document | — |

Plus `host_release` engine rebuild before packaging (`STARLING_ENGINE_OUT`
must point at host_release or the release links debug). Estimate: **3-4
days**. Total M0+M1: **~1.5 weeks**.

## Test plan

- `test/run.sh` (fast tier): nothing meaningful to test without a client;
  keep it clean — no new fast-tier tests beyond compile.
- `sudo test/run.sh --functional`: new check, gated on `freerdp3-dev`
  presence —
  1. Restart the fixture desktop with `STARLING_RDP=1` and a pre-baked
     test cert from `test/fixtures/`.
  2. `test/tools/rdp_probe.c` (libfreerdp-client3, ~200 lines): connect
     with TLS-verify off, wait for the first surface update, dump the GDI
     buffer, **assert nonblack**.
  3. Probe sends MouseEvent click at the Start button
     (x~25, y~775 at 1280x800 — coordinates table in
     `shell/Sources/DesktopShellApp/CLAUDE.md`).
  4. Screenshot via shell-drive, assert the launcher opened.
  5. Disconnect; assert `fl_drm_view_recording_active()` returns to 0 and
     a RecordingService start now succeeds (capture actually released).
- Mutual-exclusion check: start a portal screencast
  (`test/screencast_client.py`), then connect the probe — assert the RDP
  activation is refused, and vice versa.
- `test/vm.sh`: not triggered per-change (no privilege-path or session
  files change — that was the point of input path (b)); the release gate
  covers the .deb Depends and the unprivileged-session run as usual.

## Risks and traps

- **Single capture session, three claimants.** Every start path must
  check the other two; the trampoline must route by claim, not by
  guesswork. Miss one guard and frames leak into the wrong mailbox
  (ScreenCastService's stop path comments describe exactly this hazard).
  v1 limitation is documented, not hidden.
- **Frame-pump starvation.** Full-rate rebuilds while `.live` will
  recreate the pinned-at-10fps bug. Priming rebuilds ONLY in `.starting`,
  floor rate after — copy ScreenCastService, do not improvise.
- **Root vs unprivileged.** The uinput path silently works in dev and
  silently dies in the packaged session — which is why it lost. Anything
  that later touches `/dev/uinput` or `build/session/` goes through the
  vm.sh gate.
- **Frozen remote cursor.** Injected motion that skips
  `CursorPlacement`/`cursor.MoveTo` updates Flutter's pointer but not the
  hw sprite — and the sprite is what capture composites. Easy to miss,
  invisible on the dev box if you're also moving the physical mouse.
- **RGBA vs BGRX.** Try `PIXEL_FORMAT_RGBX32` end-to-end first; budget
  for a swizzle. Wrong order shows as a red/blue-swapped desktop —
  obvious, cheap to fix, annoying to discover late.
- **mstsc codec negotiation.** Modern Windows clients may decline
  RemoteFX; the NSC/raw ladder is not optional polish, it is what makes
  mstsc work at all. Test both clients in M1.
- **TLS key perms.** Key file 600; when the dev-mode root shell generates
  it, chown to the login user or the packaged session can never read it.
- **Slow-client backpressure.** All frame waiting happens on the peer
  thread against the depth-1 mailbox. If any path lets the writer-thread
  callback block (a lock held across encode, a full channel), the whole
  desktop's capture stalls — the ingest contract is copy-signal-return.
- **Stop/drain races.** The engine consumes stop requests on presents;
  releasing the capture before `recording_active()` reads 0 (or dropping
  `captureActive` while frames are still in flight) corrupts the next
  session. The pumpTick-observes-drain pattern exists because of this.
- **Encode cost at 4K.** Full-surface RFX at 4096x2160/15fps may not hold
  on one thread. Escape hatch: capture with `downscale_shift=1` and
  multiply injected coordinates by `(1<<shift)` — a two-line input change,
  since the inject API takes physical px. Decide from M0 measurements, not
  up front.

## Open decisions (each with a recommendation)

1. **Second client: refuse or replace?** → **Refuse.** Replace couples
   peer teardown to capture reclaim mid-stream for no v1 benefit.
2. **RFX-only M0?** → **Yes.** xfreerdp negotiates RFX; the fallback
   ladder lands in M1 where mstsc testing happens anyway.
3. **Injected vs physical button state.** → **Last writer wins** (inject
   mask replaces `buttons_`). Two mice fighting is out of scope; anything
   fancier buys nothing.
4. **Capture claim point.** → **On peer activation**, released on
   disconnect. A listening socket must cost nothing.
5. **Downscale shift.** → **0 (full res) until M0 measurements say
   otherwise**; the escape hatch is priced above.
6. **Where the frame loop lives.** → Mailbox in Swift (`RdpService`, like
   ScreenCastService), encode+send in C (`rdp_server_push_frame` called
   from a Swift consumer thread). Keeps the trampoline contract uniform
   across all three services.

## Follow-ups, in order

NLA auth (prerequisite for anything beyond LAN/dev) → keyboard (~1 day,
same inject path) → damage tracking (send dirty rects, not full surface) →
clipboard → egfx/H.264 → Display Control resize.
