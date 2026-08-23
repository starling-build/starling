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

### The floor had a cause, and it was ours — 2026-08-22

**Found in source, fixed, and now measured on the box (see below).** The
"unexplained ~1-2%" was not the engine and not a parked tree. Every
Starling process ran an unconditional 8 ms `WM_TIMER`
(`flwin32_host.c`, `SetTimer(host->window, kDrainTimerId, 8, NULL)`)
whose only job was to pump libdispatch's main queue so `@MainActor` and
`DispatchQueue.main.async` work reaches the message thread. Nothing
about it was conditional on there being anything to drain — no widget
tree, hidden window and empty queue all paid it. That is **125 wakeups
a second per process, ~625 across the five surfaces**, and none of them
coalesce with anything because the engine pins the process timer
resolution at 1 ms for its own frame scheduling
(`shell/platform/windows/task_runner_window.cc:50`,
`fml/platform/win/message_loop_win.cc:31`). Windows' own shell
processes, which read 0.0% in the table above, call no such timer.

Both hosts now wait on libdispatch's wakeup handle instead
(`_dispatch_get_main_queue_handle_4CF` — an auto-reset event on
Windows, an eventfd on Linux), so an idle process wakes zero times.
`GpuDmaBufRenderer.swift` had already been polling that fd since the
DRM child renderer was written; the hosts simply never adopted it.

**The Linux desktop paid the same tax, unmeasured** —
`flgtk_host.c` had the identical `g_timeout_add(8, …)`. macOS never
did: CFRunLoop owns that handle for us.

#### Measured — DESKTOP-URK35LH, 2026-08-22

Built and run on the physical box as the real Winlogon `Shell=`
replacement (exe `F6B421ED`, engine `starling` `c52ab20b5e1`), driven
through the supervised `--session` shell. `STARLING_TRACE=1` prints
which path a process took, and both were confirmed from the shipped
binary: `message loop: main-queue drain is event-driven` by default,
`message loop: main-queue drain polls` under
`STARLING_DRAIN_TIMER_MS=8`.

**A 60 s whole-session sample cannot see this effect.** Totals across
the five surfaces came out 3.96 / 4.24 / 5.42% event and 5.16 / 4.35 /
5.18% poll — overlapping, because the saving per process (~0.4 points)
is under the run-to-run spread of a restarted session. Every number in
the table above is a 20 s sample of one such session, which is worth
knowing before trusting a small delta in it.

What separates cleanly, in every single sample, is **context switches
per second per process**: 394-437 event vs 580-635 poll. That is the
~125 Hz timer plus its scheduling, and it is the honest instrument for
this change.

For the CPU number, run the two modes **simultaneously** instead —
two identical `--files` windows of the same binary, side by side, both
idle, one with the env var and one without, sampled over the same 240 s:

| parked Files window | CPU (one core) | context switches/s |
|---|---|---|
| event-driven (default) | **0.447%** | 491 |
| 8 ms poll (old behaviour) | **0.882%** | 670 |

Exactly **2.0x**, −0.435 points and −179 wakeups/s per process. Five
surfaces put the shell's idle saving at roughly **2 points of one
core**, which is the right order for the "~1-2% floor" this started
from.

**But the floor does not go to zero, and the prediction above was too
generous.** A parked window with nothing to do still costs 0.447% with
the drain timer gone. The drain timer was about *half* of the
per-process floor.

#### What is left is the engine's DirectManipulation timer — 62 Hz, per view, forever

Answered by instrumenting the loop itself (a temporary env-gated
histogram of wait returns and dispatched messages, not committed). An
**idle** `--files` window, no pointer over it, nothing to draw:

    [wake] over 5.0s: waits drain=0.0/s input=62.2/s  messages=62.2/s
    [wake]   msg=0x0113 hwnd=00000000001A00FA  62.2/s

Every wakeup is a `WM_TIMER`, all of them to one HWND, and the
libdispatch drain event fires **0.0/s** — the event path is genuinely
silent when nothing is queued, which is the commit's claim, confirmed
from inside the loop. That HWND enumerates as the `FLUTTERVIEW` child of
the host window, and `flutter_window.cc:438` is where it comes from:

    SetTimer(result, kDirectManipulationTimer, 14, nullptr);

armed once when the view window is created, never killed, and its
handler calls `direct_manipulation_owner_->Update()` on every tick
(`flutter_window.cc:688`). 14 ms rounds to ~62 Hz. It runs per view,
visible or hidden, whether or not a touchpad exists and whether or not
a gesture is in progress — a parked overlay with no widget tree pays it
exactly like a focused window. At 0.447% for 62.2 ticks that is ~72 µs a
tick, against ~35 µs for a drain-timer tick, which is why removing 125
drain ticks and leaving 62 DM ticks lands at half.

**Fixed, and it was worth more than the estimate.** Engine
`2974d27e73f` on branch `winshell-idle-drain` (paired by name with this
repo's branch) arms that timer from the `DM_POINTERHITTEST` that already
calls `SetContact`, and kills it when the viewport settles. Numbers and
the settle rule are below.

#### Gated — measured DESKTOP-URK35LH, 2026-08-22

Same one-binary A/B the drain fix used, and for the same reason:
`STARLING_DM_TIMER=always` restores the free-running timer, so both arms
are the same exe and the same `flutter_windows.dll`. Two identical parked
`--files` windows side by side, sampled over the same 240 s:

| parked Files window | CPU (one core) | context switches/s |
|---|---|---|
| gated (default) | **0.013%** | 1 |
| free-running 14 ms timer | **0.786%** | 98 |

**62.5x**, and 1 context switch a second is a process that is genuinely
asleep rather than merely cheap. The whole five-surface session at idle
now reads **2.92% of one core** (oneview 1.87, run 0.62, banners 0.26,
notifications 0.16, supervisor 0.00), against 3.96-5.42% before, with
per-surface context switches of 4-44/s where the drain fix alone left
394-437/s. Both halves of the floor are gone; what a parked Starling
surface costs now is what it actually does.

**Settle is later than "the user lifted their fingers", and getting that
wrong breaks the *next* gesture, silently.** The viewport runs in
MANUALUPDATE mode, so DirectManipulation advances only while our timer
pumps `Update()` — including the inertia after the fingers leave *and*
the synthesized `ZoomToRect` that resets the transform afterwards.
Stopping at `DIRECTMANIPULATION_READY` would strand
`during_synthesized_reset_` true, and the handler's first branch would
then swallow the next gesture's status change. So the reset counts as
unsettled while it is in flight. A contact that never becomes a gesture
(a tap) reports no status change at all and so never settles: `Update()`
counts idle passes and stops after ~1 s, which also covers the DM error
paths that leave a reset unfinished. A gesture the user holds still also
reports nothing and must NOT be stopped — hence the count is reset by
viewport activity, not by content updates. Three unit tests in
`direct_manipulation_unittests.cc` hold those three cases apart, and the
`DM_POINTERHITTEST` tests in `window_unittests.cc` now assert the arming
as well as the contact.

**No trackpad exists on this box, so the gesture path itself is covered
by unit tests, not by hardware.** That is the one gap in this
verification. Everything else was driven live on the gated build: the
1 Hz clock across a minute boundary, the dock's hover dwell label (cold
and warm), Start via the toggle broadcast and via a real tile click,
typed search, Escape and click-away, the tray chevron flyout, Files
launched from its tile, its full context menu with real verbs, and the
wheel scrolling its listing.

**A scare worth recording: the stuck tray flyout suppresses the dock's
hover labels.** After the fix, the dock's hover label stopped appearing
— and appeared again under `STARLING_DM_TIMER=always`, which reads
exactly like a regression. It is not. The runs that failed had all
followed a tray-chevron click, and the tray overflow flyout that opens
but never dismisses (already known, and present on the old exe) leaves
the dock's hover flyout dead for the rest of that session. Clicking the
chevron and then hovering reproduces it on demand in either mode; a
session restart clears it. Cost about an hour, and it is a second reason
to fix that flyout.

**What it is NOT: libdispatch main-queue timers wake the drain fine.**
The obvious theory for a late hover label was that the event-driven drain
sleeps through `asyncAfter`, with the old 62 Hz DM timer having masked
it. A direct probe says no, on both platforms: schedule a 400 ms
main-queue timer, wait on `_dispatch_get_main_queue_handle_4CF`, and the
handle is signalled at 413 ms on Windows and 400.2 ms on Linux. The
drain design is sound for timers; only nested modal loops (above) still
defer main-queue work.

Landmine while in there: `kDirectManipulationTimer` is **1**, the same
numeric id as `flwin32_host.c`'s `kDrainTimerId`. They live on different
HWNDs today (engine view child vs our host frame), so nothing collides —
but a timer id is only unique per window, and putting either on the
other's window would silently replace it.

Verified live at the same time, all on the event-driven path: the 1 Hz
clock ticks across a minute boundary, the dock's 400 ms hover dwell and
its 4 s auto-dismiss both fire, Start opens on the toggle broadcast and
on a real tile click, typed search filters, Escape and click-away
dismiss, the tray clock opens the notification centre, Files launches
from its tile, right-click draws the full context menu, and the wheel
scrolls it. Layout and paint also stay live *inside* a Win32 sizing
modal loop (a window resized by dragging its edge re-lays out while the
button is held), because engine frames ride the engine's own task
runner, not this queue.

**Found while measuring, and bigger than the timer: `dwm` costs ~5% of
one core at idle, and it is the one-view chrome that makes it.**
Attributed by killing surfaces one at a time on the same idle desktop —
all five surfaces up, dwm 4.93%; only the `--oneview` chrome left,
5.06%; Starling stopped entirely, **0.00%**. It is identical in both
drain modes and on the pre-fix binary, so it is not this change, but it
does mean the shell's real idle cost on this box is ~4% ours plus ~5%
compositor. The table above reads dwm 0.0% with the shell running,
which no longer reproduces; the likely difference is what was on screen
(a full-screen opaque window occludes the 4K colorkeyed chrome layer and
DWM stops composing it). Worth its own pass: it is now the largest
single idle cost in the system, and per-view damage would not touch it.

One caveat the design does carry: a nested modal loop (`DoDragDrop`,
`WM_ENTERSIZEMOVE`, a Win32 menu) pumps messages but does **not** run
this drain, so `@MainActor` work enqueued during one is deferred until
the loop exits — where the 8 ms `WM_TIMER` used to be dispatched by the
nested loop like any other message. No user-visible case was found (the
resize path above is live, and Files does not watch directories, so its
obvious oracle is unavailable), but `SetTimer` on `WM_ENTERSIZEMOVE` /
`WM_ENTERMENULOOP` and `KillTimer` on exit would close it for nothing at
idle.

One residual, separate from this: `GpuDmaBufRenderer.swift`'s poll loop
keeps a **100 ms idle backstop** (10 Hz) alongside the GCD fd. Far
cheaper than 125 Hz and it was never the floor here, but it is not zero
either, and it is the last periodic wakeup left in a parked Linux app.

### The native shell, same method, same box

Windows' own shell family measured identically (20s deltas, idle desktop,
explorer restored and settled):

| process | idle CPU | private | WS |
|---|---|---|---|
| explorer | 0.0% | 49 MB | 37 MB |
| StartMenuExperienceHost | 0.0% | 46 MB | 120 MB |
| SearchHost | 0.0% | 38 MB | 117 MB |
| ShellExperienceHost | 0.0% | 15 MB | 73 MB |
| ShellHost | 0.0% | 7 MB | 39 MB |
| Widgets + WidgetService | 0.0% | 18 MB | 92 MB |
| **total** | **0.0%** | **~173 MB** | ~478 MB |

Read against ours: memory is a wash — ~200 MB private for five engine
processes vs ~173 MB for seven native ones (their WS is triple ours, but
that is shared XAML/framework pages, and the suspended UWP hosts get
compressed under pressure where our pages stay hot). **Idle CPU is not a
wash: they are 0.0% across the board and we are ~11% of a core.** The
native shell is fully event-driven — the UWP surfaces are literally
SUSPENDED between uses — while every one of our residual percents is a
poll or a frame pump: the banner's 2s store read, the dock's tick+tray
read, the hidden caret's two frames a second, and an unexplained ~1-2%
floor that even the tree-less parked notifications process pays. 0.0% is
the honest target, and the floor is the interesting part: a parked
engine with no tree and no timers should cost nothing, and measuring
where its wakeups come from (the present-side frame statistics item
above) is the first step of any pass at this table.
