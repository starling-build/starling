# Computer use — Claude Desktop on Starling

Goal: give **Claude Desktop for Linux** the computer use it shipped without, by
exposing the shell's agent broker as the execution environment. The claim worth
testing is not "we can do computer use too" — anyone with `xdotool` and
`grim` can. It is that **owning the compositor makes the safety properties
structural**, so Starling can offer computer use on a real desktop that the
human is still using, without the VM everyone else needs.

## The gap, stated exactly

Claude Desktop for Linux launched **2026-06-30** as an official beta: package
`claude-desktop` from `https://downloads.claude.ai/claude-desktop/apt/stable`,
Ubuntu 22.04+ / Debian 12+, amd64/arm64. Our base platform is Ubuntu 26.04, so
it installs on the desktop as-is.

Anthropic's own install page lists what Linux does not get:

- **"Computer use isn't available."**
- "Dictation isn't available."
- Quick Entry's global hotkey "works only on X11; Wayland requires desktop
  GlobalShortcuts portal."

That third line is a separate, smaller Starling win — we ship
`Sources/PortalService/`, so implementing `org.freedesktop.portal.GlobalShortcuts`
makes Quick Entry work on our Wayland desktop when it works on no other. Track
it, don't conflate it.

The first line is the subject of this document.

## Why everyone else needs a VM, and we don't

The reference implementation of computer use is a Docker container running
Xvfb — a throwaway desktop nobody is looking at. Claude Desktop's own Cowork
feature takes the same position and pays for it in the requirements: **KVM,
QEMU, ~25 GB of disk and 8 GB of RAM** for a virtual machine, on Linux, per the
install page.

Isolation is the right instinct and a blunt instrument. It buys safety at the
cost of a machine, and *inside* that machine the agent still has:

- **one cursor**, which it fights the human for — which is why the desktop has
  to be one nobody is using;
- **the whole screen**, so any window that happens to be open is in the
  screenshot;
- **`wait 2 seconds`** as the only synchronisation primitive;
- **no identity** — nothing distinguishes the agent's clicks from a person's
  after the fact.

A compositor can enforce every one of those *finely*, because it is the thing
that decides what exists and who sees it. That is the whole argument.

## What we already have

`Shell/AgentBroker.swift` (1028 lines) is a computer-use substrate that predates
the question. One JSON-lines socket at `$XDG_RUNTIME_DIR/starling-agent.sock`,
versioned `hello`, per-agent token re-attach (so a client that runs as a series
of short-lived processes stays the same agent), every effectful call answered
and audited to `$XDG_RUNTIME_DIR/starling-agents/`.

| Broker op | What it does |
|---|---|
| `list_windows` | owned windows only — id, app, title, content size, focus |
| `launch` | `chrome` (Wayland client) or a first-party child app |
| `inject` | `click`, `hover`/`move`, `scroll`, `key`, `text` |
| `capture` | mmap the window's linear DMA-BUF → raw pixels + stride + fourcc |
| `await_settled` | per-window frame-quiet **plus** shell animations quiescent |
| `cdp_endpoint` | Chrome DevTools Protocol endpoint for an owned Chrome window |
| `semantic_tree` / `perform_action` | label/id addressing, proxied to the child |
| `screen`, `dock_rects`, `screensaver` | unscoped, read-only |

Four properties are already load-bearing, and they are the ones a VM cannot
express:

**Scope is default-deny by window ownership.** `ownedWindow()`
(`AgentBroker.swift:583`) is the single chokepoint: a `win` argument resolves
only if `win.ownerAgentId == agentId`. The human's windows and other agents'
windows are not listed, not injectable, not capturable — not by policy, by
lookup failure. This replaces the machine boundary with a per-window one.

**Agent input does not touch the human's controls.** Wayland windows get
agent input through `waylandIntegration.agentPointerEvent(...)` and friends —
per-event surface targeting with separate focus trackers
(`agentPointerFocus`/`agentKeyboardFocus`), so the agent clicks in its window
while the person keeps typing in theirs. Honesty note: this is NOT a second
`wl_seat`. A real seat-1 API exists in C (`wayland_server.c`,
`wayland_server_agent_*`) and is called from nowhere — Chromium's Ozone is
single-seat and produced zero DOM events from seat 1, which is why delivery
rides seat 0 with explicit targeting (`WaylandIntegration.swift:1455-1517`
records the history). The isolation property holds either way; the mechanism is
delivery routing, not seat separation.

**Capture is per-window, not per-screen.** The broker reads the window's own
buffer, so the result is clean, unoccluded, and content-local. An agent cannot
see the human's other windows *even if they overlap the one it owns* — a
stronger privacy property than a VM screenshot, which shows everything inside
the VM.

**Take-over.** The human takes a window's controls until Esc; every op that acts
on a window **or reads its contents** refuses while it holds. The comment at
`AgentBroker.swift:594` records why that is broader than it first was: it was
checked only in `inject`, "which by then was the one path an agent driving a web
page did not use."

And two escapes from pixels entirely, which matter more than they sound:
`semantic_tree`/`perform_action` address first-party UI by label and node id
through the same closure a human gesture would run, and `cdp_endpoint` drives
web content through CDP. Neither needs a screenshot, a coordinate, or a
scale factor.

## The contract we have to meet

The current tool is **`computer_toolset_20260801`** — no beta header, supported
on `claude-opus-5`, `claude-sonnet-5`, `claude-opus-4-8`, `claude-fable-5`,
`claude-mythos-5`. Seventeen member tools dispatched as
`("toolset_name": "computer", "name": ACTION)`:

- pixels — `screenshot`, `zoom`
- mouse — `left_click`, `right_click`, `middle_click`, `double_click`,
  `triple_click`, `left_click_drag`, `mouse_move`, `left_mouse_down`,
  `left_mouse_up`, `cursor_position`
- keyboard — `type`, `key`, `hold_key`
- other — `scroll`, `wait`

Three details decide the shim's shape:

1. **Coordinates are screenshot pixels, top-left origin.** There are no
   `display_width_px`/`display_height_px` parameters any more — *the returned
   image's dimensions are the coordinate space*. Whoever encodes the image owns
   the mapping.
2. **Size is capped and small is better.** ≤2576 px long edge and ≈3.75 MP on
   Opus 4.7+. Recommended 1024×768 or 1280×720; explicitly "avoid >1920×1080".
   Our panel is 2560×1600 at scale 2 and the Dell is 3840×2160 — every capture
   gets downscaled and every coordinate inverse-mapped.
3. **Batched actions run sequentially and stop at the first failure.** The
   remaining results must come back `is_error: true` with "Not executed: an
   earlier computer action in this turn failed."

## Two delivery paths, and why both

**Claude Desktop cannot be handed the toolset.** `computer_toolset_20260801` is
declared by the application on its own API requests; a third party cannot inject
a tool into someone else's client. What Claude Desktop *does* load is **MCP**,
from `~/.config/claude/claude_desktop_config.json` under `mcpServers`.

So:

**Path A — `starling-computer-use`, an MCP server.** stdio, one tool per
computer-use member, same names and same semantics, backed by the broker socket.
Claude Desktop gets computer use in everything but the wire format. This is the
path that answers the user-facing question, and it works on the shipped
`claude-desktop` package with no cooperation from it beyond a config file.

**Path B — a real toolset loop.** A Python agent that declares the actual
`computer_toolset_20260801` against `claude-opus-5` and executes it against the
broker. Nothing to do with Claude Desktop; it is how we prove the substrate
against the real contract instead of our approximation of it, and it is what a
Starling app or `app-run` recipe would embed later.

They share one executor. Write the broker→action mapping once, put an MCP
frontend on one side and a sampling loop on the other.

## What is actually missing

Ordered by what will bite, not by size.

**1. `capture` does not work for Wayland clients — the windows that matter.**
The op resolves pixels through `linuxProcessAppManager.dmaBufInfo(textureId:)`
(`LinuxProcessAppManager.swift:246`), which reads `apps[textureId]` — the
DMA-BUF *child app* table, first-party only. Wayland surfaces register their
textures through `WaylandIntegration.processSurfaceCommit` →
`textureRegistry.importDmaBuf` and never appear in `apps[]`, so `capture` on a
Chrome window returns `"window has no capturable buffer"`. Chrome, VS Code,
Claude Desktop itself — every interesting target is a Wayland client.

And this is **not** a missing lookup. First-party children render into *linear*
buffers, which is why an mmap works at all; client buffers carry a
format modifier (tiled on the AMD 680M), so mapping one gives swizzled garbage
rather than an error. It needs a GPU readback.

The readback already exists, twice, for other reasons:

- `fl_drm_view_recording_start_texture(...)` — **"TRUE app capture: record an
  external texture (a window's own composited content, resolved per present
  through the compositor's texture callback) instead of the framebuffer.
  Overlapping windows and position never show"**, live even when minimized. It
  already takes `content_top_down` for exactly the flipTextureY split between
  Wayland clients and first-party children. This is per-window capture with the
  privacy property intact — it is the right answer, and it is a recording
  session API that needs a one-shot form.
- `fl_drm_view_read_capture(x, y, w, h, dst, len)` — an in-memory rect of the
  presented desktop as BGRX top-down, GPU-mirrored via a PBO ring so the present
  path is never stalled, with `arm_capture` scheduling a frame so an idle
  desktop still refreshes. Built for the X server's GetImage. This is
  *full-screen* capture, so it matches the tool's coordinate model exactly and
  **breaks the per-window scoping** — worth having as an explicit, separately
  consented mode, never as the default.

**2. No image encoding.** `capture` returns base64 of the raw buffer plus
`stride`, `fourcc` and `row_order`. The tool wants a base64 PNG or JPEG. Encode
in the shim, not the shell: the shim already has to downscale and own the
coordinate mapping, and doing both in one place keeps the mapping honest.

**3. Half the actions are missing.** `inject` handles `click`, `hover`/`move`,
`scroll`, `key`, `text`. Absent: right/middle/double/triple click, mouse
down/up, drag, `hold_key`, `cursor_position`, `wait`. Most are small additions
to the existing switch. `double_click` is the one with history —
`onDoubleTap` is unusable on the DRM embedder (see CLAUDE.md), so this is two
synthesised clicks with a real gap, not a gesture.

**4. `launchable` is a table in the shell, and CLAUDE.md says it must not be.**
`AgentBroker.swift:120` hardcodes `files`, `settings`, `terminal`, plus `chrome`
special-cased in the handler — 4 of the registry's 24 apps. "Never add an app id
to a table in the shell or the store — there are no such tables any more."
`AppRegistry.shared.app(id:)` is right there. Fixing this is what makes computer
use worth having: an agent that can only open Settings is a demo.

**5. No MCP server, no `claude.app` record, no install recipe.** The registry
record is one file per the usual rule; the install recipe follows `chrome.app`'s
`DebUrl` shape or an apt source drop-in.

**6. `zoom` has no analogue** and should be a crop-and-rescale of a fresh
capture in the shim — the doc notes Claude keeps using full-screenshot
coordinates after a zoom, so the shim must not rebase them.

## Milestones

1. **Per-window pixels for Wayland clients.** A one-shot form of the texture
   capture path, surfaced as `capture` for any owned window regardless of
   client type. This is the gate — nothing else is testable without it.
2. **Fill in `inject`.** The missing mouse and keyboard actions, and `wait`.
3. **`launch` reads the registry.** Delete the table.
4. **The executor** — broker client, PNG encode, downscale, coordinate
   mapping, batch semantics with the stop-at-first-failure result shape.
5. **Path A: the MCP server**, plus the `claude_desktop_config.json` snippet and
   a `claude.app` registry record so the desktop can install and launch it.
6. **Path B: the toolset loop** against `computer_toolset_20260801` on
   `claude-opus-5`, as the conformance check.
7. **Functional coverage.** `test/functional.py` already drives the broker with
   a real identity and asserts on semantic trees rather than pixels — the same
   trick works here and keeps the tier fast.

## Traps

- **This repo's mainline is `main`; the engine's is `starling`.** Milestone 1
  changes both, and both get committed.
- **Do not let the human's seat leak.** Every new `inject` action must go
  through `agentPointerEvent` for Wayland windows, the same as `click` does. A
  new action that reaches for the shared seat silently reintroduces the
  cursor-fighting this whole design exists to avoid.
- **Every new op goes through `ownedWindow()`.** It is one line and it is the
  entire security model. The take-over check has already been widened once
  because an op read window contents without asking.
- **`capture` must stay per-window by default.** Full-screen readback exists and
  is easier; reaching for it turns the strongest claim in this document into the
  weakest.
- **Recommended resolutions are much smaller than our panels.** 1280×720 from a
  2560×1600 window at scale 2 is two independent factors — do not fold the
  buffer's own `scale` (physical/logical, already reported by `capture`) into
  the downscale factor by accident.
- **A capture on an idle desktop is stale.** The engine consumes capture
  requests in the present callback and an idle desktop presents nothing;
  `shell-drive.py`'s `shot` pumps SIGRTMIN+2 frame ticks for exactly this
  reason. `await_settled` is the right primitive to pair with a capture, and it
  measures quiet from the latest of *frame or injection*.
- **Claude Desktop is an Electron app, so it is a Wayland client** — it is
  subject to milestone 1 like everything else, including if we ever want an
  agent to drive Claude Desktop itself.

---

# Implementation plan (approved 2026-08-29)

The survey above is the *why*; this is the *how*, phase by phase. Two decisions
are fixed: **per-window scope only** (no full-desktop readback mode this pass),
and deliver the **MCP server plus a conformance loop** (no `claude.app`
packaging yet). Exploration confirmed the survey's blocker and turned up two
more, all reflected below.

## Phase 1 — Engine: one-shot per-window texture capture

Repo **starling-engine, branch `starling`**. Files
`engine/src/flutter/shell/platform/linux_drm/fl_drm_view.{h,cc}`.

New export — the name MUST keep the `fl_drm_view_` prefix (`drm_exports.lst` is
a wildcard on it; anything else is localized silently):

```c
// Synchronous one-shot capture of an external texture's current content.
// Scales to out_w×out_h (GL_LINEAR, same rule as recording_start_texture),
// writes top-down RGBA into dst. 0 on success; negative for unresolvable
// texture / no ES3 / timeout.
FL_DRM_EXPORT int fl_drm_view_capture_texture_once(
    FlDrmView* view, int64_t texture_id, int content_top_down,
    int out_w, int out_h, uint8_t* dst, int dst_len);
```

"Option B" — synchronous readback, no present, no pump, no recording session
(the session path collides with the engine-wide single-capture arbitration that
RDP/ScreenCast/Recording already share, and carries a 3-present latency + a
writer-thread join; wrong tool for an on-demand grab):

- Post a task to the **raster thread** with `FlutterEnginePostRenderThreadTask`
  (`embedder.h:3365`, currently unused in-tree); block the caller on a condvar
  with a ~1s timeout.
- In the task: `v->egl.MakeCurrent()` (the engine clears the context between
  frames), resolve the texture via `v->external_texture_callback` — the SAME
  resolver the present path uses (`fl_drm_view.cc:1212-1231`); it also refreshes
  a dirty client texture, which is what makes this immune to idle-desktop
  staleness *without* the frame pump. Then reuse the existing blit shape
  (`:1237-1256`): `src_fbo` + `glFramebufferTexture2D`, scale-blit into a scratch
  RGBA renderbuffer at `out_w×out_h` honoring the `content_top_down` flip
  (top-down = straight, bottom-up = flipped), a blocking `glReadPixels`, then
  `ClearCurrent()`.
- Gate on `GetEs3Fns()` like the recording path (`:1042-1044`). Return DISTINCT
  errors for unresolvable / no-ES3 / timeout — resolve failure is silent on the
  present path and must not be here.
- Never cache the resolved GL texture name (the registry defers deletions to the
  next resolve on the GL thread).

Rebuild BOTH outputs — host_debug fails the *link* without the export,
host_release fails at *runtime*:
`ninja -C engine/src/out/{host_debug,host_release} libflutter_linux_drm.so libflutter_engine.so`.

## Phase 2 — Shell: broker completeness

This repo, branch `computer-use`. Files `AgentBroker.swift`, `AgentWindows.swift`,
`WaylandIntegration.swift`, `DesktopShell.swift`.

**2a. `capture` for every window kind** (`AgentBroker.swift:766-812`). Try
`fl_drm_view_capture_texture_once` first — it works for Wayland clients AND
first-party children, and it fixes the documented virtualised-GPU empty-mmap
failure (`agent-client.py:429-440`). Keep the mmap path as a fallback. Accept an
optional `max_px` long-edge target; the engine blit does the downscale, so the
shim never rescales pixels. Reply gains `"format":"rgba"` (top-down) + image
dims alongside the existing `content`/`scale`. Pass `win.flipTextureY` as
`content_top_down`.

**2b. Fill in `inject`.** All Wayland routing stays on the existing
agent-targeted delivery (`agentPointerEvent`/`agentKeyEvent`/`agentScrollEvent`).
- `agentPointerEvent` gains a `button` param (0x110/0x111/0x112); the C layer
  already passes buttons verbatim (`wayland_server.c:444-452`).
- New ev types: `rclick`, `mclick`, `dblclick` (two synthesized down/up pairs
  with a REAL delay — `onDoubleTap` is unusable on DRM per CLAUDE.md), `down`,
  `up`, `drag` (down → motion glide → up), `keydown`/`keyup` (for `hold_key`).
- Agent modifier state: mirror the human path's `modifierBit`/`modsDepressed`
  logic (`WaylandIntegration.swift:1226-1304`) and call
  `wayland_server_keyboard_modifiers` on the agent path — without it every chord
  is silently unmodified (Ctrl+C arrives as `c`). Also send pointer leave on
  agent focus change (a stale enter persists today) and track the last agent
  (x,y) per window for `cursor_position`.
- Fix `inject text` on Wayland: it currently passes the textureId guard then
  no-ops inside `LinuxProcessAppManager.sendKeyEvent` while replying `ok:true`
  (`AgentBroker.swift:749-761`). Branch on `agentSurf` like `key` does;
  synthesize per-char key events via an ASCII→HID(+shift) table
  (precedent: `shell-drive.py` KEYCODES). Keep the DMA-BUF path unchanged.

**2c. Registry-backed `launch`** — delete the `launchable` table
(`AgentBroker.swift:120-124`):
- `.firstParty` → existing `_launchAgentChildApp(execName: rec.exec, …)`.
- `.host` → generalize `_launchAgentChrome` (`AgentWindows.swift:63-89`) to a
  `_launchAgentHostApp(recipe:)`: recipe = `rec.exec`, `STARLING_CDP` only when
  recipe == "chrome", ADD `setsid` (without it a `kill(-pgid)` for app-quit
  takes the shell down — the `_spawnLauncher` hazard, `DesktopShell.swift:7954-7968`),
  and honor `Gpu=discrete` → `STARLING_APP_GPU`.
- `.x11` / `.android` → refuse (they don't fit the wl_client-claim model —
  WeChat is a whole rootful Xwayland screen, Waydroid one window for all apps).
  Uninstalled → refuse "not installed".
- Serialize agent launches: `_pendingAgentWayland` is a global one-shot claim;
  reject a second host-app launch while one is armed (registry breadth makes the
  race real). Consider keying the claim on child pid
  (`waylandIntegration.clientPid(surfaceId:)`).
- Update the scope echo in BOTH hello replies (`AgentBroker.swift:317, 331`) and
  the error at `:641` to derive from the registry.

## Phase 3 — Executor + MCP server (Path A)

New `build/computer-use-mcp.py`, staged by `stage.sh` next to the
`agent-client.py` line (`stage.sh:234`) as `$OUT/bin/starling-computer-use`
(`package-desktop.sh` picks `bin/` up automatically). Python stdlib only,
importing `agent-client.py`'s `Broker`, `capture_to_rgba`, `write_png` via
importlib from the installed path.

- MCP stdio server: JSON-RPC 2.0, `initialize` / `tools/list` / `tools/call`.
  Identity persists through agent-client's state file, so broker re-attach keeps
  window ownership across Claude Desktop restarts.
- Tools: the 17 toolset members with matching names/semantics, each taking an
  explicit `win`, plus `computer_launch(app, url?)` and `computer_windows()` for
  the per-window model. `screenshot` = broker `capture` with `max_px` 1280 → PNG
  image block; `zoom` = fresh capture, crop, rescale (coordinates STAY
  full-screenshot-based per the contract). Screenshot-px → content-local logical
  mapping lives in exactly one place (reply `content` vs image dims).
- Batch semantics: sequential, stop at first failure, remaining answered
  `is_error` "Not executed: an earlier computer action in this turn failed."
- `install` subcommand: merge (never clobber) an `mcpServers` entry into
  `~/.config/claude/claude_desktop_config.json`.

## Phase 4 — Conformance loop (Path B)

New `test/computeruse/conformance.py` — manual, needs API credentials, NOT in
run.sh. Declares the real `computer_toolset_20260801` on `claude-opus-5`
(adaptive thinking, streaming), drives members through the same executor module,
runs a scripted task. Purpose: catch drift between our member implementations
and the real contract before users do.

## Phase 5 — Tests + docs

- `test/functional.py`: new inject actions asserted via `semantic_tree` (the
  existing no-pixel pattern); a one-shot `capture` on a first-party window
  asserting dims + non-empty.
- Fast tier: an MCP-framing test against a fake broker socket (pure Python, no
  GPU), wired like `xdg_open_routing.py`. `test/run.sh` stays green.
- This doc: keep the agent-seat honesty note current as the code changes.

## Verification (the Linux dev box — planning happened on macOS)

1. `test/run.sh` after each shell change; engine build for BOTH out dirs.
2. `build/build-all.sh && build/run-desktop.sh`; then `agent-client.py launch
   chrome …` + `shot` — the shot must now come from the broker, not the CDP
   fallback (its own output says which).
3. Drive the MCP server standalone over stdio; screenshot a launched Settings
   window, click by coordinate, confirm via `semantic_tree`.
4. `sudo test/run.sh --functional`.
5. End to end: install `claude-desktop`, `starling-computer-use install`,
   restart it, ask Claude to open Settings and act — confirm the human cursor
   never moves and no human window appears in any screenshot.
6. Conformance loop against the real API once, with credentials.
