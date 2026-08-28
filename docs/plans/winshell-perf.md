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
`2974d27e73f`, on the engine's mainline `starling`, arms that timer from
the `DM_POINTERHITTEST` that already calls `SetContact`, and kills it when
the viewport settles. Numbers and
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
followed a tray-chevron click, and the tray overflow flyout that opened
but never dismissed left the dock's hover flyout dead for the rest of
that session — `flyoutContent` gives way to any open flyout, so a flyout
that cannot close takes the labels with it. Clicking the chevron and then
hovering reproduced it on demand in either mode; a session restart
cleared it. Cost about an hour. **That flyout is fixed now** (see
winshell-tasks.md): the panel holds activation while a flyout is down, so
click-away arrives as its own deactivation.

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

### What was left was not floor, it was frames — 2026-08-22

With both timers gone the question became "why is a parked shell still
2.3% of a core", and the answer is that it was still DRAWING. Per
surface, same binary, 60 s each, with the framework's own
`STARLING_FRAME_LOG=1` counting frames before any present:

| parked surface | cpu | ctxsw/s | frames/s |
|---|---|---|---|
| an ordinary window (`--files`) | **0.000%** | 1.0 | 0.00 |
| banners | 0.26% | 32 | 0.00 |
| run | 0.31% | 18 | **1.92** |
| the one-view chrome | 0.31%* | 27 | **2.07** |

\* standalone; in the live session the chrome read 1.64%.

An ordinary parked window at 0.000% and one wakeup a second is the
proof that the floor really is gone — everything above it is work
somebody asked for.

**The dock asked for two frames a second to change nothing.** Its state
is observed, so *assigning* is what rebuilds: the 1 Hz tick assigned
`state.now = Date()` and then six status fields, each rebuild being the
whole 3840x2160 chrome (~800 µs of build alone). But the clock reads
`h:mm` — **no seconds** — so 59 of every 60 rebuilds painted the
identical string, and the status poll's answer (network, power, volume,
theme, night light, energy saver) is the same for hours at a time.
Assigning only when the displayed *minute* moves, and only the status
values that actually moved, took the chrome to ~0.03 frames/s — and then
the shape itself was wrong, which making the tick cheap had only hidden.
**The widget that draws the time is the only thing that knows what
cadence the time needs.** `DockClock` now schedules itself to the next
minute BOUNDARY and rebuilds that leaf alone (the rebuild-scope
discipline the hover flyout already used), so a format that grows
seconds gets a one-second cadence with no other change. What stays in
the bloc's tick is what is genuinely periodic and belongs to nobody in
particular — the native-taskbar guard and the tray revision check — at
5 s, with Quick Settings asking for a fresh read when it opens rather
than living off the background poll. The chrome at idle, in three steps:

| the dock's chrome, idle | cpu | ctxsw/s | frames/s |
|---|---|---|---|
| 1 Hz tick, unconditional assigns | 1.64% | 27 | 2.07 |
| assign-on-change | 0.44% | 20 | ~0.03 |
| widget-owned clock, 5 s tick | **0.13%** | 7 | ~0.03 |

The end state for the three status reads is events rather than polling:
WM_POWERBROADCAST, an IAudioEndpointVolume callback, and NLM's network
notifications each replace one.

**The Run dialog blinked a caret in a window nobody could see.** It
parks rather than closes so Win+R is instant, but a focused field flips
its caret every 530 ms — 1.9 frames a second, for the life of the
process, which was that process's entire idle cost. The field is now
disabled while the dialog is off screen, and `FluentTextBox` only arms
the blink while a caret is actually *drawn* (a read-only or disabled
field paints none, so blinking one was always a frame to change
nothing). Hidden 0.000%, open 0.416%, closed 0.000% — the caret parks
with the window and comes back with it.

Whole session at idle, five surfaces: **2.34% → 0.31-0.73% of one
core**, and the chrome is now the *smallest* of them. What is left is
the two notification surfaces' polls.

**And dwm went from ~5% of a core to 0.05%.** The earlier section
guessed the compositor was paying for the colour-keyed 4K layer's
existence and that per-view damage would not touch it. Wrong on both
counts: it was recompositing that layer twice a second because we kept
redrawing it. Stop drawing and DWM stops too.

### The last of it: what has to ask, and how often — 2026-08-22

Three polls were left, and they are not the same question.

**The notification centre is user-triggered**, so it has nothing to keep
current while parked. Its 5 s tick claimed to be paid "only while the
panel is on screen" and half was: the store read was gated on
visibility, the `setState` above it was not, so a hidden overlay rebuilt
its tree every five seconds forever. It now starts on show and stops on
hide — 0.000% hidden, 0.625% open, 0.000% closed.

**The banner is the one surface no gesture brings up**, so it must hear
about a toast on its own. `UserNotificationListener` has that event, and
it is now wired through the raw ABI — a hand-written COM object with the
parameterized IID derived from WinRT's signature rule. **Windows refuses
it: `add_NotificationChanged` answers ERROR_NOT_FOUND to a process with
no package identity.** The registration stays (a packaged Starling would
get it) but polling is the mechanism, so the question became what an ask
costs:

| asking the notification service | wall | CPU |
|---|---|---|
| full read of 5 toasts | 36-60 ms | ~6.2 ms |
| the toast ids alone | 24 ms | ~6.2 ms |

The same CPU either way — the price is the cross-process RPC, not the
per-toast walk — so there is no cheap "has anything changed" to poll on.
The ids-only variant was written, measured and deleted. What is left is
frequency, and the honest rule is presence: two seconds while somebody is
at the machine, fifteen while nobody has touched it for a minute (the
toast is in the centre when they return). `GetLastInputInfo` costs
microseconds.

**And the finding that dwarfed both.** `Task.detached { while true { try?
await Task.sleep(…) } }` costs **~46 context switches a second** on
Windows in a process that is otherwise asleep — the parked Run dialog
next to it wakes zero times. That loop, not the poll, was most of what
the banner process spent. A libdispatch timer replaces it: the kernel
holds the deadline and nothing runs until it fires. Worth grepping for
elsewhere; on this platform `Task.sleep` is not a free way to wait.

Whole session at idle, five surfaces, 60 s samples:

    2.34%  →  0.65%  →  0.08% of one core
                        (chrome 0.03, banners 0.05, the rest 0.00)

with `dwm` at 0.03%. A parked Starling desktop now costs about a tenth of
one percent of one core, compositor included.

#### And then the chrome's tick went too — 2026-08-23

Three polls were left after the above: the chrome's 5 s tick, the banner
store, and the supervisor's 5 s wait on its children. **The first is
gone.** Its three jobs each had a notification behind them, and
`Win32Status.watch` (flwin32_status.c) subscribes to all of them on one
thread:

| what moved | how Windows says so |
|---|---|
| battery, AC/battery | `WM_POWERBROADCAST` + `RegisterPowerSettingNotification` |
| theme | `WM_SETTINGCHANGE` |
| explorer's taskbar came back | it broadcasts `TaskbarCreated` itself |
| Wi-Fi association and signal | `WlanRegisterNotification` |
| anything with a cable | `NotifyIpInterfaceChange` |
| the tray's promoted/hidden split | `RegNotifyChangeKeyValue` |

**The trap, and the reason the watcher owns a window:** a power or
settings broadcast reaches TOP-LEVEL windows only. A message-only window
gets neither, and the failure is silence.

Volume, night light and energy saver are deliberately absent: the STRIP
does not show them. They live in Quick Settings, which asks for a fresh
read when it opens. Nothing on screen is stale and nothing is on a timer.

The chrome now reads **0.00% of one core and 2 context switches a
second**, and the whole session 0.10%. Verified with the events rather
than only the CPU: promoting a hidden tray icon in the registry (what
Windows' own Settings writes) puts it on the strip in **1.2 s** where the
poll could take five, and flipping `AppsUseLightTheme` with an
`ImmersiveColorSet` broadcast turns Quick Settings dark and back.

Two polls remain, and both are honest: the banner store (Windows refuses
an unpackaged process the arrival event) and the supervisor's 5 s timeout
on a blocking wait over its children's handles, which costs 0.00% and
only re-parks an overlay that died.

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

---

# Addendum, 2026-08-23 — latency vs the native shell, and the P0 it found

## What was measured

Keystroke-to-pixels against the Windows shell, on the physical box, warm,
medians of 6:

| | first pixels | usable |
|---|---|---|
| Start menu — Starling | 67 ms | **67 ms** (same frame, no animation) |
| Start menu — Windows 11 | 183 ms | **300 ms** (fades in over ~4 frames) |
| File manager — Starling Files | 317 ms | **500 ms** |
| File manager — Windows Explorer | 366 ms | **1149 ms** |

Re-run at **n=20**, both launched by the same `CreateProcessW` and both on
OUR shell — which is the honest question, since that is where a user of this
desktop actually opens a file manager (Explorer then cold-starts rather than
handing off to a resident instance):

| | first pixels | usable | p25-p75 (usable) |
|---|---|---|---|
| Starling Files | **300 ms** | **483 ms** | 467-500 |
| Windows Explorer | 567 ms | **1400 ms** | 1308-1400 |

**2.9x to a usable window, and the distributions do not touch**: our slowest
of twenty (600 ms) still beats Explorer's fastest (1300 ms).

The two Explorer numbers are not inconsistent, and the difference is worth
understanding before quoting either. `explorer.exe` is ONE binary with two
roles -- the shell (taskbar, Start, desktop, tray) and the file manager
(`CabinetWClass` folder windows) -- and which one is running decides what a
folder window costs:

- **Explorer as the shell**: folder windows are hosted inside the already
  running shell process. Opening one creates no process at all. 1149 ms, and
  most of that is its own content load.
- **Explorer NOT the shell** (i.e. our desktop): there is no host instance, so
  each folder window becomes its OWN process. Verified on the box --
  `SeparateProcess = 0` and yet two folders gave two explorer processes,
  **197 MB each**, one `CabinetWClass` in each. 1400 ms.

So the "on our shell" comparison is not a stacked deck: it is that on a
desktop where Starling is the shell, Windows' file manager has no resident
host to attach to, for the same reason our Files pays a full process launch
every time. Both sides pay process creation. We are 2.9x faster anyway.

**4.5x to a finished Start menu; 2.3x to a usable file window** — the latter
while starting a whole process, which Explorer (already running as the shell)
never does.

And against a hand-written native file manager, like-for-like (same desktop,
same `CreateProcessW`, same rig): **Starling Files 449 ms vs File Pilot 0.8.3
515 ms**, while drawing 1.9x the pixels from a 49.7 MB exe against its 2.5 MB
one. A native app is not faster here because a cold launch is not dominated by
framework overhead — see the budget below.

Method, and how the comparison films are made: `test/bench/win-latency/README.md`.

## Where a file-explorer launch actually goes

By process uptime, from `STARLING_TRACE=1`:

| phase | cost |
|---|---|
| process create + DLL load + Swift runtime | ~30 ms |
| `FlutterDesktopEngineCreate` | **110 ms** |
| ...of which `egl::Manager::Create` | **109.5 ms** |
| view controller + first `WM_PAINT` | ~22 ms |
| DWM's window-open animation | **~100 ms** |

`egl::Manager::Create` is one `eglInitialize`, and that is essentially
`D3D11CreateDevice`: **113 ms cold, ~62 ms warm** on this AMD 780M, with no
flag, feature-level list or adapter trick that makes it cheaper (WARP does it
in 11 ms, but software rendering is not the trade). It is charged **per
process**, which is the whole asymmetry with Explorer. Pre-warming does not
help: `d3d11.dll` and `dxgi.dll` were already loaded before the 113 ms call,
so the cold/warm gap is driver and kernel setup, and there is only ~38 ms of
our own startup to hide it behind.

DWM's open animation is ~100 ms of the wall clock and both shells pay it —
turning it off takes our 500 ms to 399 ms.

Engine instrumentation for all of this is committed behind `STARLING_TRACE`
(engine `89ec060db2d`, `164b0d6c8da`, `3ad2d4f97f8`): constructor phases,
ANGLE bring-up step by step, and per-task timing with kind.

## Two things fixed on the way

- **The listing stopped waiting on the sidebar** (`178c4e9`). Opening with no
  directory argument — Win+E and the dock tile — did not start the directory
  read until `places()` + `drives()` + `oneDrive()` + `quickAccessPins()` had
  all returned. Quick Access alone is **160 ms**; the read it was blocking is
  **3 ms**. Quick Access is cached across runs now too.
- **The caption is claimed before the window exists** (`7cca01e`). Files takes
  the caption for its tabs, and doing that after a view controller exists is a
  client-area *resize* — which the embedder answers by blocking the platform
  thread in `OnWindowSizeChanged` until the raster thread returns a frame at
  the new size, plus a `DwmFlush`. On a 29 Hz panel: **~90 ms of waiting**.
  Claimed at `host_create` time there is nothing to resize.

Together these take everything the window draws from ready-at-413 ms to
ready-at-195 ms. The wall clock does not move, because the window's
*appearance* is gated by ANGLE and DWM, not by our data — but the first frame
the compositor shows now contains the file list instead of being empty.

## The P0 it uncovered

Benchmarking File Pilot, its window would not appear under our shell. It was
not File Pilot: **open an app, close it, open another, and the second one is
invisible** — a real window, `IsWindowVisible` true, correct rect, not
cloaked, sitting under our full-screen desktop surface. 21 of 24 launches.

The desktop clamps itself to `HWND_BOTTOM` in `WM_WINDOWPOSCHANGING`, which
only ever sees moves of our own window; nothing tells it when Windows inserts
a foreign window *below* us, which is what happens when the launching app
cannot take the foreground — and closing the last app window hands the
foreground to the desktop itself. Fixed in `a667a8b` with a WinEvent hook on
`EVENT_SYSTEM_FOREGROUND..EVENT_OBJECT_SHOW` that sinks the desktop whenever
another top-level window is shown. 0 of 24 after, idle unchanged.

`test/bench/win-latency/zorder-stress.ps1` is the regression test. **A single
launch passes even when the bug is present** — the sequence that matters is
launch → close → launch, repeated.


## Addendum, 2026-08-25: re-measured after the minimize / packaged-app work

Everything below is the physical box, one session, same binary, after the
changes of 2026-08-24 (the minimize target, the file explorer's title and show
path, and the opt-in explorer service).

### Idle

60 s sample, nothing on screen, per process:

| | CPU (of one core) | working set |
|---|---|---|
| shell processes | **0.31%** | 142 MB (settled) |
| explorer service, when on | 0.05% | 227 MB |
| dwm | 0.00% | — |

Against the 0.08–0.18% recorded before, and the regression was found and
fixed in the same sitting: **the supervisor had gone from 0.00% to 0.23%**,
because its five-second tick asked "is explorer alive" with a Toolhelp
snapshot — a walk of every process on the machine, twenty times a minute, to
answer a question whose answer is almost always yes. It holds a handle to the
process it started and asks `WaitForSingleObject(…, 0)` instead; back to
0.00%.

What is left is **banners at 0.26%**, which is the notification-store poll
this document already describes: Windows refuses the arrival event to a
process with no package identity, so it asks, and asking costs ~6.2 ms of RPC
whatever you ask for. Unchanged, not a regression.

**Explorer costs 227 MB and 0.05%** when the service is on. That is the price
of Store apps, and the reason it is opt-in is not this — it is the work area
(below).

### Win+E → the file explorer, drawn

20 reps, ddagrab, 0.999× timeline, 64×64 signature, n=14 usable:

**median 146 ms** (min 49, max 195). First pixels equals done in every single
rep — the window arrives fully painted in one composited frame rather than
appearing and then filling in.

Against 110 ms recorded for the hosted file explorer. The quantum is 33 ms and
this document's own rule is that anything under ~2 frames is unmeasured until
it survives a proper A/B; 36 ms is one frame. Not called a regression, and not
called unchanged either — it wants the A/B against the explorer service off,
which is the obvious suspect and was not completed.

**The rig was stale and reported nothing wrong.** `capture-launch-winE.ps1`
looked for the file manager as `FlutterSwiftWin32Host`, which is what it was
when it had its own process. It is a surface view inside the shell now
(`StarlingSurfaceView`), so every rep logged "window up: False", nothing was
closed between reps, and the numbers were of a window that was already open.
Fixed to know all three shapes. Any bench that identifies a window by class is
a bench that expires.

### The one that is not fixed: the work area, with explorer alive

With the explorer service on, after a shell restart, **the dock's strip stops
being reserved** — the work area goes back to full height and maximized
windows run underneath a dock that is still drawn. Four attempts did not hold
it: re-assert at startup, re-assert on TaskbarCreated, a watcher that
re-registers whenever the work area disagrees, and all three at once.

That re-registering is not the missing piece is the tell. The reservation
appears only when something makes explorer recompute of its own accord —
activating a packaged app did it once. Our tray owns the `Shell_TrayWnd`
class, so `SHAppBarMessage` resolves to US before explorer (both windows
exist; FindWindow returns ours first), and with explorer alive two shells are
computing the work area. The fix probably belongs in the appbar service: own
the work area explicitly rather than asking whoever answers to do it.

Until then the explorer service is **opt-in**, `STARLING_EXPLORER_SERVICE=1`,
and `test/win/run-gate.sh` skips the two checks that depend on it rather than
failing on the shipping configuration.


# Addendum, 2026-08-27 — all three latencies re-measured at n=20, on the CPU settings the box actually ships with

This supersedes the head-to-head numbers in the 2026-08-23 addendum and the
Win+E figure in the 2026-08-25 one. Same rig, same box, `ddagrab`, calibration
0.9998-0.99993, **20 reps a side**, each shell registered as THE shell while it
was filmed.

| | first pixels | finished | ratio (finished) |
|---|---|---|---|
| Start menu — Starling | 100 ms | **100 ms** | — |
| Start menu — Windows 11 | 167 ms | **300 ms** | **3.0x** |
| Right-click menu — Starling | 67 ms | **67 ms** | — |
| Right-click menu — Windows Explorer | 233 ms | **267 ms** | **4.0x** |
| Win+E file manager — Starling Files | 83 ms | **83 ms** | — |
| Win+E file manager — Windows Explorer | 367 ms | **1116 ms** | **13.4x** |

First pixels equals finished on our side of all three: the surface arrives
complete in the frame it appears. Windows fades the Start menu in over four
more frames, and Explorer's folder window is a frame with "Working on it..."
for two thirds of a second before the file list lands.

**The Win+E comparison is now like-for-like, and that is why the number moved.**
Ours is a view inside the running shell, and this take has Explorer running as
the shell, so it hosts folder windows inside itself -- its best case. Neither
side pays process creation. The 2026-08-23 pairing (500 vs 1149 ms) had ours
starting a whole process and said so; removing that caveat widened the gap
rather than narrowing it. The 146 ms of 2026-08-25 was the same code measured
before the CPU cap was understood (below), and is superseded, not contradicted.

**The distributions do not touch, with room to spare.** Win+E: ours 33-133 ms
across twenty, Explorer 1066-1200. Our *slowest* complete open (133 ms) lands
before Explorer's *fastest first pixel* (333 ms).

**Why the Start menu reads 100 ms here and 67 ms in the older numbers.** The
67 ms baseline was measured with the CPU pinned to High Performance. That mode
hangs this box under sustained load (three hangs on 2026-08-26), so the machine
is left on its as-shipped cap -- min 80 / max 50 / boost off, Balanced -- and
every number above is on that cap. 100 ms is the honest figure for a box anyone
can leave running; 67 ms is what the hardware can do in a mode we do not ship
and cannot keep up. Quote 100.

## The films, and three things they claimed that the measurements did not

`test/bench/win-latency/compose-{menu,ctxmenu,launch}.py`, re-rendered from
this take. Each carried a number that had not been updated with the rest:

- **The context-menu summary bar was still drawn at 300 ms** while every label
  beside it read 267. A bar chart is a claim; this one overstated the gap in
  our favour by a visible 10% of bar width.
- **The Start-menu film contradicted itself** -- an in-film caption still said
  "4.5x sooner" from the old 67 ms baseline while its own summary card said 3x.
  That version had already been rendered and sent.
- **The launch card said "our slowest open still beat Explorer's fastest by
  200 ms"**, which against the film's own definition of usable reads as
  Explorer's fastest usable window (1066 ms, so 933 ms). The 200 ms is against
  its first *pixels*. Reworded to say which.

The lesson is the cheap one: when a re-measurement moves a headline number,
grep the whole film for every other number derived from it. Two of these three
survived a re-render because only the card was checked.

**Post-script, later that day.** The native Start-menu capture above had a
File Explorer window (left over from the Win+E arm) sitting open behind all
20 reps — invisible in the numbers, glaring in the film. Re-captured with a
clean desktop after flipping the box's shell back to explorer for the take:
the medians reproduced exactly (first 167, settled 300), which doubles as
evidence the background window never influenced the measurement. The films
and the site use the clean take; both analyses are in
`docs/perf/winshell-latency-2026-08-27/`.
