# winshell — performance profile, 2026-08-21

Taken at the end of the sessions that added view modes, This PC, live theme,
mica tint, ShellNew, column resize, and the sidebar/tab interactions — to
know what all of it costs before anything else lands on top. Method,
numbers, what was fixed, and what is worth a later pass.

## Method

External, no instrumentation in the shipped binary: scripted input
(SetCursorPos / mouse_event / keybd_event) drives one scenario for ~5s
while the process's `TotalProcessorTime` delta is read around it. CPU is
reported as % of one core. One-shot helpers were re-benched standalone
(clang -O2, QueryPerformanceCounter) with the same API traffic.

Caveats learned doing it:

- **Process CPU time quantizes at ~15.6ms** — one-shots under ~30ms read
  as 0 or noise; the standalone bench answers those.
- **Run-to-run noise is real and can look like a trend.** A first pass
  showed hover cost "growing" monotonically across runs (0.6% → 28%),
  which pattern-matched to a mouse-tracker annotation leak. A controlled
  interleave (hover / 60-click rebuild storm / hover / storm / hover, one
  process) showed the opposite: 1141 → 563 → 438ms per 4s sweep. That is
  raster/cache warm-up, not a leak; the "growth" was environment (Defender
  scanning each freshly copied exe, indexing). Trust interleaves, not
  sequences of separate runs.
- A scenario can silently miss its target and measure nothing: the
  column-drag script pressed where the divider USED to be after earlier
  runs had moved it, and reported 1% instead of 26%. A perf number that
  improved for no reason deserves the same suspicion as one that
  regressed.

## Interactive costs (Details on C:\Windows\System32, 4661 files, 2x scale)

| scenario                          | cost                                    |
|-----------------------------------|-----------------------------------------|
| idle (Details or This PC)         | 0–0.9% of a core — no polling anywhere  |
| hover sweep, warm plateau         | 0.07-0.2ms per change, Details and grid alike (see the correction below) |
| hover sweep, cold / driven-hard   | 2-5ms per change -- attribution open    |
| wheel scroll, Details             | ~4.6% of a core                         |
| wheel scroll, Medium icons        | ~0.9% (4x fewer builds per pixel)       |
| rubber band, grid                 | ~7.7%                                   |
| column-divider drag               | ~26–29% (≈4ms per move = one full-window rebuild; matches the historical 3.9ms figure — no regression) |
| one selection click               | ~17ms (rebuild + per-selection association lookup + footer scan) |
| Ctrl+A over 4661                  | ~47ms one-shot                          |
| view-mode flip                    | ~86ms one-shot                          |
| launch + list 4661 files          | ~1.6s CPU total (engine boot included)  |
| memory                            | 96 MB WS after Details, 108 MB after grid + 48px textures |

## One-shot helpers (standalone bench)

| helper                              | cost                                  |
|-------------------------------------|---------------------------------------|
| flwin32_shellnew_templates (HKCR)   | 42ms — off-thread once, process-cached |
| flwin32_wallpaper_average           | 59ms cold, 4ms warm — off-thread once |
| SHGetFileInfo display name          | 0.10ms per call                        |
| SHGetFileInfo type name             | 0.075ms per call (already one per TYPE by design) |

## A finding withdrawn

The first pass reported grid hover at ~25x Details hover. Re-measured with
a better protocol -- three consecutive sweeps on one process, keeping only
the plateau -- BOTH modes bottom out in the same sub-millisecond class
(grid 0.07ms/move, Details 0.20ms/move). The multi-millisecond readings
appear on cold processes and on processes that have been driven hard, and
one controlled observation (Details at a stable 2.5ms/move fell to
0.2ms/move after a refresh cleared the selection) hints the escalation is
selection-linked -- but external CPU sampling is at its noise floor here
(sweeps of ~230 events against desktop-wide contention swing +-1.5ms/move)
and cannot attribute it. Do not optimize the ClipRRect on this evidence;
instrument first.

## Fixed during this pass

- `selectedEntry` and the status bar look the selection up in a
  `visibleByPath` dictionary built once per reprojection -- the command
  bar alone asked six times per rebuild, each a full scan of the listing.
- `Win32Files.displayName` is memoized. The sidebar's drive rows and the
  breadcrumb ask on every window rebuild, and a rebuild can run per
  pointer move (column drag) — 0.1ms of shell call per drive per frame
  for an answer that changes only when a volume is relabeled.

## Follow-ups, in value order

1. **Internal frame timing.** Every open question above (what escalates
   hover to milliseconds on a driven process, whether it is
   selection-linked, what a rebuild's chrome/listing split is) dead-ends
   on external CPU sampling's noise floor. A timer around the build/raster
   pass, behind an env var, answers all of them -- and is the same
   plumbing the present-statistics question needs.
2. **The full-window rebuild (~4ms on a big folder) is the unit cost**
   behind column drags and selection clicks. Isolating the listing (or
   headers+listing) into its own rebuild scope would cut drag cost by
   whatever the chrome+sidebar share is; measure before assuming it is
   worth it.
3. **Present-side smoothness is unmeasured** — CPU says nothing about
   frame pacing, and GDI capture cannot see the GL view. Folded into
   follow-up 1: one piece of engine instrumentation answers the frame
   pacing, the idle-present question, and the hover attribution above.
