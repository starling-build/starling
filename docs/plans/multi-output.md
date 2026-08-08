# Multi-output — one virtual desktop, N panels

Goal: a second monitor that is a full member of the desktop, not a wallpaper
with windows on it. Today it is most of the way there for *windows* and almost
nowhere for *chrome and spaces*, and this doc is about closing that second gap.

The arrangement is already settled and is not in question here: outputs are
placed in one global logical coordinate space (`DisplayLayout`), each with its
own scale, and a window's rect is virtual-desktop coordinates. Everything below
assumes that.

## Where we are

**Built and working.** The engine enumerates outputs, gives each a Flutter view
(the primary is the implicit view 0), and rebuilds pointer regions on hotplug so
clicks route to the right view in view-local coordinates. `DisplayLayout` owns
the arrangement; `SecondaryOutputScreen` renders each non-primary output's
wallpaper, menu bar and the windows intersecting it; `wl_output` enter/leave
tracks which outputs a surface straddles; unplugging brings stranded windows
home.

**Window geometry is already per-output**, which is easy to miss because the
call sites still take `screenWidth`/`screenHeight` parameters. They are a
fallback for the non-DRM dev paths only: `_outputFillRect` resolves the *owning*
output from the window's own rect (`WindowManager.swift:639`), so maximize and
fullscreen fill the monitor the window is on, and `retile` groups windows by
owning output and tiles each independently (`WindowManager.swift:766`).

**Window chrome is per-output as of `1ee803b`.** The traffic lights, the
title-bar double-click, and the fullscreen title-bar reveal all work on a
secondary monitor. Before that the secondary passed three callbacks out of
seven and every button on it was inert. `test/lint.py`'s `window-chrome` check
now compares the two trees so this cannot drift again.

**Deliberately primary-only.** The dock. macOS has one dock and so do we; this
is not a gap. (The menu bar is per-display in macOS, and ours already is.)
**Which** display is primary is now the user's, in Settings › Displays, and the
dock follows it — see "The primary display is a choice" below.

**Workspace mode and the launcher follow the pointer** as of staging step 1
below: both open on the monitor they were invoked from.

**Not migrated, and the subject of this doc.** The space model, Mission
Control, the desktop context menu, and the screensaver overlay (see `screensaver.md`, which already flags its own). Concretely, on a
second monitor today you cannot right-click the desktop — the primary wraps its
wallpaper in a `Listener` that opens the context menu, and
`SecondaryOutputScreen._wallpaper()` returns a bare `TextureWidget` with no
listener at all. And an animated wallpaper preset plays on the primary while
the secondary falls back to `.slate`, because the secondary reads only
`sharedWallpaperTextureId`, which is the still-image path.

## The primary display is a choice

Settings › Displays lists the connected screens and lets the user pick the
primary. Two things share the name "primary" and separating them is the whole
of the design:

- **The host** (`DisplayOutput.isHost`) is the output the engine renders
  Flutter's implicit view to. `FlDrmDisplay` picks it — the largest panel by
  pixel count — and the binding is hardware: the implicit view owns that
  output's swap chain and EGL surface. The shell's own widget tree is drawn
  into it, so the host's logical rect *is* that tree's coordinate space, which
  is why the host is always at (0,0) and why `screenWidth`/`screenHeight` read
  the host and not the primary. Reading the primary there laid the whole shell
  out against a panel it was not on.
- **The primary** (`DisplayOutput.isPrimary`) is the user's pick: the dock, new
  window placement, the `wl_output` the compositor advertises first, and the
  fallback output for the workspace and launcher.

They coincide until the user says otherwise, so N=1 is unchanged.

Because the host cannot move, the *dock* moves instead. `dockWidget(forOutput:)`
and `dockIconMenuWidget(forOutput:)` on `_DesktopShellState` lay the dock out
for a given output; the shell's tree draws it only while `dockIsOnHost`, and
`SecondaryOutputScreen` draws it when its own output is primary. Exactly one
tree draws it, and the pieces that were implicitly host-relative had to be
parameterised: `_dockMetrics(outputWidth:)`, `_dockIconAnchorX`, and
`_updateDockHover(x:y:outputId:)`, which the secondary's root `Listener` feeds
because the host tree never sees a pointer event on another panel.
`dockSlots()` (the broker, hence `shell-drive.py`) now reports virtual-desktop
coordinates rather than host-local ones, unchanged whenever the primary is the
host.

Two traps found while building it. The secondary's rebuild gate exists to drop
"dock animations and other primary-only churn" — but once the dock is *there*
that churn is its own, so `_poke` bypasses the gate while the output is
primary, and `isPrimary` is in the signature as well, because the bypass is
edge-blind on the way out (the same shape as the `ovl:` term). And
`_SecondaryScreenHostState` held its `DisplayOutput` by value from view-creation
time; only its `id` is dependable, so it re-resolves against the live layout —
otherwise `isPrimary` was frozen at whatever it was when the monitor was
plugged in.

The choice is persisted to `~/.config/starling/primary-display` **by connector
name**, not by index: indexes are the engine's enumeration order and a hotplug
reshuffles them, so an index would promote a different monitor after replugging.
`DisplayLayout` applies it on construction, so startup and hotplug agree, and a
primary that is currently unplugged falls back to the host and reclaims the role
when it returns.

The list reaches the Settings app over the same DMA-BUF control socket as the
theme and wallpaper: `DMABUF_DISPLAY_NAME` chunks then `DMABUF_DISPLAY_INFO` per
output, as a self-delimiting run (`phase` packs index and count), with
`DMABUF_CONTROL_SET_PRIMARY_DISPLAY` coming back. Same latch/replay contract as
the other pushes, so the pane seeds correctly from a push that arrived before
its widget tree existed.

**The engine switch exists now — the whole shell moves.**
`fl_drm_view_set_primary_output(view, index, ratio)` rebinds the implicit view
at runtime: EGL primary surface, swap-chain alias, present-callback pacing,
refresh period, `view_to_output[0]`, view-0 metrics, capture-hook target, and
the pointer region — each mirroring what `fl_drm_view_create` does for the
startup primary. The explicit view on the target output is displaced through
`FlutterEngineRemoveView` with a **detach-only** completion — deliberately not
the hotplug teardown baton, which would disable the CRTC and destroy the very
surfaces the implicit view is moving onto. Refused while a recording session
is active (the recorder freezes capture geometry against the session-start
primary) and on the legacy non-compositor path. It is platform-thread-only
(AddView/RemoveView affinity); `fl_drm_view_post_task()` is the runtime door
onto that thread. The shell orchestrates the rest through existing exports:
after the rebind it gives the old host an explicit view (`add_output_view`,
which now accepts it) and re-runs the `set_output_layout` pass.

On the shell side, `_setPrimaryDisplay` fires `requestHostOutputSwitch` when
host and primary disagree (also the retry path after an engine refusal —
the dock-only move is the graceful degradation), windows are translated by
their owning output's origin delta so they stay on their physical monitors
while the virtual desktop renumbers around them, and the persisted choice is
applied at startup *before any secondary views exist* — main is still the
platform thread then, and there is nothing to displace.

Two scale facts fell out. `fl_drm_view_get_output_derived_scale()` exposes the
engine's EDID-based per-panel scale, and `computeRealLayoutFromEngine` seeds
NEW outputs from it instead of hardcoding secondaries to 1× — this machine's
14" 2560×1600 laptop panel is a 227-DPI 2× display that the width-only Swift
heuristic would have called 1×. And outputs already in the layout keep their
scale across switches and hotplugs, so a slider adjustment survives.

## Mixed refresh rates: who paces whom

Each output has always been modeset and page-flipped at its own rate (this
machine runs 90Hz eDP beside 30Hz HDMI). What was wrong was above the kernel,
and two changes fixed the two real defects:

- **Secondary chains are frame-dropping mailboxes** (`set_skip_when_busy` in
  `FlDrmSwapChain`). The engine's single raster thread presents every view
  sequentially, and `Present()` used to block on that output's previous flip —
  so one 30Hz panel's 33ms flip-wait throttled everything, including the
  90Hz primary. Now a busy secondary drops the frame (no swap, no lock — the
  buffer accounting is untouched, which is what makes it safe) and the flip
  bridge reports `dropped`, on which the shell force-rebuilds that output's
  screen host (`secondaryScreenForceRedraws` — the *gated* invalidator would
  do nothing, since a drop changes no signature) so the final frame of an
  animation always lands. The PRIMARY still blocks: its back-pressure is the
  pipeline's pacing, and skipping there would busy-spin the renderer.
- **Clients are paced by their own panel.** `fl_drm_view_set_output_present_callback`
  fires on EVERY output's flips (one bridge on all chains, demuxed by CRTC)
  with that output's own refresh period; the legacy primary-only callback is
  gone. `wayland_server_on_present` takes the flipping output's bit and
  completes frame callbacks + presentation feedback only for surfaces paced
  by it; a surface's pacing output is the one it MOSTLY sits on
  (`pace_mask`, set alongside the enter/leave mask — a straddler must not be
  paced by both panels). Measured live with `WAYLAND_DEBUG` gap analysis:
  a client on eDP sits on the 11.1ms grid, one on HDMI on the 33.6ms grid,
  simultaneously — and the eDP client's rate holds while the HDMI client
  streams and the dock animates, which is the throttling defect gone.

What this deliberately does NOT give: per-view frame *scheduling*. Flutter's
embedder API schedules frames globally (one vsync stream, one ScheduleFrame),
so frame production is paced by the primary and a client's full round trip
(commit → texture → engine frame → flip → frame callback) spans 2–3 refresh
periods rather than 1. Closing that means wiring a real vsync waiter off the
primary's flips (plus a vblank-estimating timer for the idle case) — known
deadlock-prone (a dropped baton hangs the UI thread), worth doing as its own
carefully-tested change if the latency matters.

## The one that blocks the rest: a space is global

`activeSpaceIndex` is a single `Int` on `WindowManager` (`WindowManager.swift:256`).
`SpaceInfo` is `id` plus `kind` and nothing else (`:158`). `WindowInfo.spaceId`
is a flat tag. Nothing anywhere associates a space, or a window's membership in
one, with an output.

So every output renders the same active space, because
`SecondaryOutputScreen._windows()` draws `wm.visibleWindows`, which is
`visibleWindows(inSpaceId: activeSpace.id)`. Verified live on a two-output
layout: a window sitting on the second monitor **disappears from it** when you
switch spaces on the first, and comes back when you switch back. Same for
entering workspace mode, which is just another space.

This is exactly macOS with *"Displays have separate Spaces"* switched **off**.
The behaviour is self-consistent and not a bug; it is simply the option we
never implemented, and it is the reason workspace mode cannot appear on a
second monitor.

There is a second, smaller consequence hiding behind it. The space-switch slide
(`slideLayers`, `DesktopShell.swift:2660`) offsets layers by multiples of
`screenWidth` and is rendered only in the primary tree. A secondary output has
no `dx` term at all, so it should snap to the new space instantly while the
primary animates for 380ms. Read from the code, not observed — worth confirming
with a mid-slide capture before fixing.

## Design: per-output active space

The model change is small and the fan-out is not.

```
   WindowManager
-  var activeSpaceIndex: Int
+  var activeSpaceByOutput: [Int: Int]      // outputId -> spaceId
+  var activeSpace(onOutput:) -> SpaceInfo
+  var activeSpace: SpaceInfo               // primary's, as the N=1 default
```

Keeping a primary-flavoured `activeSpace` is what makes this stageable: at N=1
it is the only entry and every existing caller keeps working unchanged.

What has to become output-scoped, and why each is not mechanical:

- **`visibleWindows`** — the secondary already asks for a space's windows, it
  just asks for the wrong one. Cheapest part.
- **`focusTopmostInActiveSpace`** — focus is global (one `focusedWindowId`) but
  the candidate set is now per-output. Which output's topmost wins when the
  active space changes on one of them? Proposal: focus follows the output that
  changed.
- **Window placement.** A new window picks a space today by implication —
  there is only one. With per-output spaces it must choose, and the honest
  answer is "the active space of the output the window is opening on", which
  `WindowManager.swift:461` already gestures at by offsetting new windows from
  `displayLayout.primary.origin`.
- **`_switchToSpace`** — takes an output, and only that output slides.
- **Edge-drag carry** (`_checkEdgeCarry`) — currently arms when the pointer hits
  `0` or `screenWidth`. Those are the *primary's* edges; on a multi-output
  desktop the meaningful edges are the virtual desktop's outer boundary, since
  an inner edge is a seam the pointer crosses onto the next monitor.
- **Mission Control** — one strip of spaces today. Per-output spaces means
  either a strip per display, or an overview that shows the strip for the
  display it was invoked from. The latter is less work and probably righter.

## Workspace mode on the invoking output

Workspace mode is a space, so it inherits all of the above. But it has one
problem of its own that the space work does not solve, and it is worth stating
because it rules out the obvious answer.

`_applyWorkspaceWindowGeometry` (`WorkspaceSpace.swift:360`) does not lay out a
picture. It sets each owned window's `rect` and calls `onContentResize`, which
configures the real Wayland/DMA-BUF client to the pane's size. A client has one
buffer size. Two outputs of different sizes want two different pane sizes, so
**the same workspace cannot be shown on both monitors** — not as a rendering
limitation but because the windows in it would have to be two sizes at once.

That leaves two coherent options, and only one is cheap:

- **Move it** — workspace mode opens on the output you invoked it from; the
  others keep their desktops. Needs only that `_buildWorkspaceSpace` and
  `_applyWorkspaceWindowGeometry` take an output instead of reading
  `screenWidth`/`screenHeight`, which are hardwired to `dl.primary`
  (`DesktopShell.swift:214`). One workspace, one output, one client size. This
  is buildable today, ahead of the space work, and is the recommendation.
- **A workspace per output** — each monitor runs its own workspace with its own
  driver and tabs. Coherent, genuinely useful with two large displays, and
  needs the full per-output space model first.

Mirroring the same workspace onto both is not on the list. A letterboxed copy
would be the only honest version and nobody wants it.

## Staging

1. ~~**Workspace mode on the invoking output.**~~ **Done.**
   `_buildWorkspaceSpace(output:)` and `_applyWorkspaceWindowGeometry(output:)`
   take an output; `_workspaceOutputId` records which monitor the pointer was
   over at toggle time, and whichever screen owns it draws it. The launcher
   came along for the ride — the workspace's `+` opens it, and an app picker
   that lands on a different monitor from the thing that asked for it is worse
   than no support at all, so it has a `_launcherOutputId` and the same
   treatment. Every call site now goes through `openLauncher()`.

   Two things fell out worth remembering. The shared divider position had to be
   clamped per output (`_workspaceDriverWidth(forOutputWidth:)`), or a narrow
   monitor collapses the tab column. And the secondary's signature gate is
   bypassed while it hosts an overlay, because the workspace has far more state
   than a signature can summarise — but the bypass is edge-blind on the way
   out, so `ovl:` is in the signature too. Without it a closed launcher stayed
   painted on the secondary, which is exactly how it was found.
2. ~~**The rest of the secondary's desktop chrome**~~ **Done** — the desktop
   context menu opens on the monitor it was right-clicked on (one state +
   `contextMenuOutputId`, drawn by exactly one tree — the dock/launcher
   sharing shape), and the secondary renders the real wallpaper preset:
   still through the shared texture, animated presets self-animating in its
   own tree (their tickers drive that view's frames past the rebuild gate).
   `.slate` is only the nothing-to-show fallback now.
3. ~~**`activeSpaceByOutput`**~~ **Done** — as `activeSpaceIdByOutput`
   (by space ID, not index: indexes shift on insert/remove). The compat
   anchor is the HOST's `activeSpaceIndex`, and an ABSENT map entry means
   "follow the host", so an output decouples only when a space is first
   switched ON it — N=1 and never-switched N>1 behave exactly as before.
   Visibility rule: a window shows iff its space is active on its OWNING
   output; `visibleWindows` is the per-output union and straddlers then
   render on every screen they touch. Windows dragged across the seam join
   the destination output's active space (user spaces only, both ways).
   Fullscreen's private-space dance, restore-follows-window, new-window
   placement, dock-icon activation and the workspace toggle are all
   output-scoped; the workspace on monitor B now leaves monitor A's desktop
   intact — verified live. `hostChanged(from:to:)` keeps each PANEL on its
   space across a primary-display switch. Focus follows the output that
   switched.
4. ~~**Per-output `_switchToSpace` slide on secondaries**~~ **Built** —
   `_secondarySlides` (shell state, keyed by output) carries fromId/toId/
   dir/curve; each tick pokes that output's force-redraw hook (the gated
   invalidator drops animation-only frames), and `SecondaryOutputScreen`
   renders two wallpaper+windows layers sliding past each other from
   `slideWindows(inSpaceId:onOutput:)`, with other outputs' windows static
   above. The context menu's New Desktop is scoped to the monitor it was
   invoked on. Exercised live without faults; a mid-slide frame capture is
   still owed (SIGUSR1 latency lost the race — worth one shell-drive
   record-start run). Still open: edge-carry dwell from a secondary (carry
   is host-only; its arming correctly ignores seam edges and fires only at
   the virtual desktop's outer boundary).
5. ~~**Mission Control per display**~~ **Done** — invoked-output-scoped:
   `_missionControlOutputId` from the pointer at open, geometry/cards/strip
   all read that output (`_mcW/_mcH/_mcLocalRect` translate the card
   animation's start rects into its local space; the exposé lists only its
   OWNED windows), strip clicks and the MC keyboard retarget switch that
   output's space, the host gates its copy on `mcIsOnHost`, and the
   secondary draws it via `Builder` with the force-redraw hook carrying the
   open/close and relayout animation ticks past the signature gate.
   Verified live: Ctrl+Up on eDP shows the exposé there with no cards for
   HDMI's windows while HDMI's desktop is untouched.
6. **A workspace per output**, if (1) proves it earns the depth.

## Decisions still open

- **Does the active space follow the pointer or the focused window?** macOS
  uses the pointer for "which display am I acting on". Ours has no such notion
  yet and would need one for steps 1, 4 and 5 to feel consistent with each
  other.
- **Where does a launcher launch land** when the launcher is invoked on a
  monitor whose active space differs from the primary's? Almost certainly the
  invoking output's space, but it interacts with the workspace carve-out in
  `_launchFromLauncher`, which already has a "we are in a workspace" branch.
- **Should the space *set* be shared or per-output?** Sharing the list and
  making only the active index per-output (proposed above) is far less
  disruptive, and matches macOS, where a space belongs to a display but the
  numbering is global. The alternative — a genuinely independent list per
  display — makes hotplug ugly: unplugging has to rehome not just windows but
  whole spaces.
- **Hotplug.** When an output appears, which space does it show? The primary's
  is the safe answer, and the layout code already has the "windows come home"
  precedent to follow when one disappears.
