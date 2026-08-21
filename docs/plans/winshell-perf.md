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

## A finding withdrawn, then settled from inside

The first pass reported grid hover at ~25x Details hover; a plateau
protocol shrank that to "same class, noisy"; one observation hinted the
escalation was selection-linked. All three were artifacts of external CPU
sampling's noise floor. The frame timer (below) settled it:

    UI-thread cost per hover-change frame, System32, mean/max us
    Details, no selection:   build  347/ 709  paint  955/1290  total 1406/1811
    Details, selected:       build  354/1324  paint  920/1296  total 1360/2456
    Medium icons:            build  228/ 528  paint 1333/1682  total 1720/2204
    one selection click:     build 3648/6852 (the full rebuild) total ~4.8-7.9ms
    view flip, worst frame:  build to 7.9ms, total to 11.3ms

Hover costs ~1.4-1.8ms of UI thread per change in EVERY mode, paint-
dominated; the grid is +25% in paint (bigger cells), not 25x anything;
selection changes nothing. Nothing here needs optimizing -- a real mouse
crosses ~30 rows/s, ~4% of a core. The external sweep figures scattered
from 0.07 to 2.5ms/move around a signal this size, which is the measure of
that method, not of the code.

## Fixed during this pass

- `selectedEntry` and the status bar look the selection up in a
  `visibleByPath` dictionary built once per reprojection -- the command
  bar alone asked six times per rebuild, each a full scan of the listing.
- `Win32Files.displayName` is memoized. The sidebar's drive rows and the
  breadcrumb ask on every window rebuild, and a rebuild can run per
  pointer move (column drag) — 0.1ms of shell call per drive per frame
  for an answer that changes only when a volume is relabeled.

## Follow-ups, in value order

1. **Internal frame timing: BUILT, both halves.** `STARLING_FRAME_LOG=1`
   logs the UI thread's build / layout / paint / composite / finalize
   split per composited frame (Adapter.swift); `STARLING_PRESENT_LOG=1`
   (engine 319173a327f) logs every present with SwapBuffers duration, gap
   since the previous present, and a raw QPC timestamp external tooling
   can correlate against. Findings: after true idle a click's frame
   presents within milliseconds (the ~600ms idle-repaint mystery was GDI
   capture staleness -- deferred item closed); swap itself is ~350us and
   never vsync-blocked; hover-driven repaints present every 2-5 vsyncs
   (p50 46ms request-to-glass), which is the documented ~40ms
   frame-dispatch latency measured from the present side.
2. **The full-window rebuild (~4ms on a big folder) is the unit cost**
   behind column drags and selection clicks. Isolating the listing (or
   headers+listing) into its own rebuild scope would cut drag cost by
   whatever the chrome+sidebar share is; measure before assuming it is
   worth it.
3. **Frame-dispatch latency is now the whole story.** With presents
   prompt after idle and swap sub-millisecond, the only latency left on
   the table is the ~40ms request-to-begin-frame dispatch (task list,
   deferred section) -- and STARLING_PRESENT_LOG's gap histogram is the
   smoothness gate that scheduler surgery was waiting for.

## Addendum 2026-08-21, later: the five-process shell at idle

Measured after Phase 4 (banners + Run) landed, in the win11-gpu VM (8 GB,
8 vcpu), by sampling each process's `TotalProcessorTime` delta over 20s
with every surface parked and the desktop untouched. Memory is private
bytes (working sets in the guest are trim-happy and lie low).

| process | idle CPU (one core) | private |
|---|---|---|
| dock | 2.7% | ~42 MB |
| notifications | 1.9% | ~40 MB |
| banners | 3.9% | ~26 MB |
| run | 2.4% (was **10.2%**) | ~29 MB |
| files (open, idle) | 0.9% | ~50 MB |

Whole shell: ~11% of one core, ~200 MB private, both roughly flat.

**The 10% was the caret-blink Ticker.** A Ticker holds the engine's frame
loop hot for as long as it runs — TickerScheduler re-schedules a frame
per tick — so one focused FluentTextBox meant a full-rate frame pump to
flip two pixels twice a second, and the Run dialog's field stays focused
while the overlay is hidden. Rewritten as the house deadline timer
(asyncAfter + generation token, TextBox.swift); the residual 2.4% is two
real frames a second still presented into a hidden window. TerminalView
already used the timer pattern; TextBox was the last Ticker-driven blink.

Worth a later pass, in value order:

1. **Unfocus (or stop blinking) when the host window hides** — takes
   run's residual to notification-parity (~1.3%), and is honest anyway:
   a hidden field is not editing.
2. **The banner poll reads the whole store every 2s** (WinRT enumeration,
   ~4%/core). NotificationChanged through the raw ABI replaces the poll
   outright — already on the plan as the instant-arrival follow-up; this
   is the second reason to do it.
3. The dock's ~2.7% predates Phase 4 (1 Hz clock tick + tray read) and
   is the same order as before; nothing new to chase.
