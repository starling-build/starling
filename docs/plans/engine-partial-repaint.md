# Engine partial repaint (per-view damage) — investigation and design

Written 2026-08-22, after the one-view shell's CPU profile showed its one
real cost: hover-driven repaints raster the full 3840x2160 chrome view for
a 34pt tile highlight — 12.4% of one core against the old strip-window
dock's 7.6%. This doc is the "take a look" pass: what exists, what blocks
it, the design that would work, and what it would buy.

## What the engine already has

The damage machinery in `shell/common` and `flow` is COMPLETE and
per-view: `Rasterizer::DrawToSurfaceUnsafe` builds a `FrameDamage`, seeds
it with `GetLastLayerTree(view_id)` (layer-tree diffing via DiffContext —
DisplayList deep-compare, so naively re-recorded identical content diffs
to empty), clips the raster to the damage, and hands frame/buffer damage
to the submit. The embedder API exposes the hooks
(`populate_existing_damage`, `FlutterBackingStorePresentInfo`). The Swift
runtime's scenes are ordinary flow LayerTrees, so they diff.

## What blocks it on our Windows path

Every view renders through the EMBEDDER COMPOSITOR
(`FlutterCompositor` → `EmbedderExternalViewEmbedder`), and the
rasterizer force-disables partial repaint there when the raster thread is
merged — which single-thread swift-mode always is:

    // Disable partial repaint if external_view_embedder_ SubmitFlutterView
    // is involved - ExternalViewEmbedder unconditionally clears the entire
    // surface ...

Concretely, per frame per view today: full clear + full Skia raster into
an offscreen backing-store FBO (`EmbedderExternalView::Render`,
clear_surface=true), then `CompositorOpenGL::Present` does a full-screen
glBlitFramebuffer to the window framebuffer and swaps. Three full-area
passes; the CPU cost is display-list recording + ANGLE command
translation + blit + present (GPU pixel work itself is <1%).

## The design that would work

Stage A — raster clip (the big win):
- New `ExternalViewEmbedder::SupportsPartialRepaint()` (default false).
  `EmbedderExternalViewEmbedder` returns true for frames with ZERO
  platform views (always, for this shell) behind an env flag
  (`STARLING_PARTIAL_REPAINT=1`) while it proves itself.
- Narrow the rasterizer's force_full_repaint accordingly.
- THE ORDERING PROBLEM: damage must be known at RASTER time, but the
  backing-store render target is chosen from `EmbedderRenderTargetCache`
  at SUBMIT time — and targets rotate, so "existing damage" depends on
  which target comes back. Fix: per-view damage HISTORY (a ring of the
  last K frame damages, K = cache depth); existing_damage = union over
  the frames since the returned target was last used. Conservative and
  correct; requires tagging targets with a frame sequence number.
- `EmbedderExternalView::Render` clears only the damage region (scissored)
  and replays the (already clipped) recording.

Stage B — blit/present clip (smaller):
- Forward frame damage through `FlutterBackingStorePresentInfo.paint_region`
  to `CompositorOpenGL::Present`; blit only the damaged rect.
- SAFE ONLY IF the window backbuffer is preserved across swaps. ANGLE on
  D3D11 may give age-1 semantics (offscreen backbuffer texture) or
  support eglPostSubBufferNV; must be verified against our ANGLE build
  first. If not preserved, keep the full blit — Stage A's raster clip is
  the bulk of the win anyway.

## What it would buy, honestly

- Hover CPU: 12.4% → est. ~8-9% of one core (the raster-area share; the
  per-frame fixed costs — build, recording, scheduling, present — remain).
- The launcher layer's caret blinks while Start is open, the clock tick,
  and every small badge update stop paying full-screen raster.
- NOT a latency win: click-to-Start is 93ms and frame-COUNT dominated;
  damage does not remove frames.

## Risk and cost

- shell/common + shell/platform/embedder surgery: the SAME code paths run
  the LINUX desktop (fl_drm uses the embedder compositor for multi-view),
  so the blast radius is both shipping shells. Needs the Linux gates
  (test/run.sh, a run-desktop pass, multi-monitor sanity) in addition to
  the Windows benches and the hover-sweep gap-histogram smoothness gate.
- The render-target damage-history bookkeeping is subtle (rotation,
  resize invalidation, cache clears on layer-count change).
- Estimate: one to two focused sessions, engine-only, behind an env flag;
  promote the flag only after both platforms' gates pass.

## Cheap mitigations if the 5%-while-hovering is not worth that yet

- None needed today: idle is a wash and GPU is <1%; the cost exists only
  during pointer motion over tiles.
- App-side: hover-state could damage less by design (e.g. no full-tree
  rebuild on hover) — but that fights the framework's grain for the same
  ~4% and buys nothing else. The engine fix is the real one.

## Outcome (2026-08-22, implemented on the box)

Both stages landed behind `STARLING_PARTIAL_REPAINT` and both WORK —
`STARLING_DAMAGE_LOG` shows per-frame union rects of ~1.5-3% of the screen,
the blit clips to them, ANGLE's `EGL_BUFFER_PRESERVED` was accepted and
verified — and the hover number did not move: 13.9% → 12.5%. The estimate
above was wrong about where the cost lives. A per-thread profile split it:
of the ~13%, the raster thread ran ~3% (already-clipped raster + preserved
swap) and the platform/UI thread ~8%, and an in-tile oscillation (same
event rate, no tile crossings) costs 5% — so the sweep's real bill was
per-crossing FRAME PRODUCTION: full-tree rebuild + full-view display-list
re-record (no interior repaint boundaries in the Swift port — the KNOWN
GAP), diff, and dispatch. Damage clipping cannot help a cost that is paid
before rasterization.

What actually fixed it, in the app (`Dock.swift`, winshell-oneapp):
1. **Scoped rebuild** — `hovered` became a plain var; the flyout
   (label/preview/tray tooltip) is its own stateful leaf (`DockFlyoutSlot`)
   the root pokes. A tile crossing no longer rebuilds the chrome tree.
   Bought ~1% alone (re-record still full-view) but is the right shape.
2. **Show dwell, 400ms** — native behaviour (Windows taskbar labels do not
   appear on a grazing pass) and the real win: a sweep produces ZERO flyout
   frames until the pointer rests. Once a flyout is up it follows tiles
   immediately (native reshow). Sweep: **13.8% → 5.2%**, at the event
   floor (in-tile oscillation 4.8%; idle 1.9%).
3. **4s auto-dismiss** (also native) — and it fixed a real pre-existing
   bug the pixel oracles caught: hover events only arrive while the
   pointer moves over opaque pixels, and there is no leave event on this
   surface, so a pointer that jumped from a tile into the colorkey hole
   stranded the label on screen forever.

Verified by pixel oracle on the box: flick-across-tiles shows nothing
(diff 0), rest 900ms shows the label (24.1), tile-to-tile reshow is
immediate (86.8), park 5s erases (0).

Keep the engine work: it is correct, env-gated, and it is what makes the
1/s clock tick and the Start-open caret cheap (damage-clipped raster +
blit instead of full 4K). The remaining ceiling — full-view display-list
re-record per dirty frame — is the Swift port's missing interior repaint
boundaries, which is the named follow-up if flyout-visible tracking or
richer chrome animation ever makes per-frame cost matter again.
