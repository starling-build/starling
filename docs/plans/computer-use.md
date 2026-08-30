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

**The agent seat.** Wayland windows take an *independent focus stream* —
`waylandIntegration.agentPointerEvent(...)`, distinct from the human's seat. The
agent clicks in its window while the person keeps typing in theirs. Nothing else
in this space does this; it is the reason the desktop does not have to be
unattended.

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
