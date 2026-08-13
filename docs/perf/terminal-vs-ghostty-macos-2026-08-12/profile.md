# Where the macOS wall time goes — profile of the 1.35x

Follow-up to `report.md`, same machine and grid. Two measurements: a 15 s
thread sample of TerminalApp streaming `03_sgr_fg` in a loop, and
`test/bench/core/ptyread.c` (ported, see below) isolating the read path on the
same 72.7 MB file.

## 1. The reader/parser split does not coalesce on macOS

This is the finding. `ptyread`, best of 3, `03_sgr_fg` (72.7 MB), grid 201x47:

| mode | what it is | wall | feeds | mean batch |
|---|---|---|---|---|
| 0 | blocking 64K reads, single-threaded, parses | **0.400** | 72050 | 1009 B |
| 2 | transport floor: read and discard, no parse | 0.474 | 71366 | 1019 B |
| 9 | ring + drain + ~2 ms linger on EAGAIN | 0.545 | **278** | **261 KB** |
| 4 | ring + drain-into-slot — **what Pty.swift ships** | 0.684 | 71762 | 1013 B |

Live for comparison: ours 0.863 s, ghostty 0.614 s.

**The macOS pty hands back ~1 KB per read regardless of buffer size** — every
mode above lands on a ~1010 B mean batch. That is the same species as the
Linux ~600 B finding, and it is why no amount of buffer sizing helps.

What is new is that **the drain-into-slot optimisation is inert here**. On
Linux it collapsed 204k ring passes into 2.8k (mean batch ~54 KB) and bought
ascii 0.780 -> 0.750 s and 1.42 -> 1.15 CPU. On macOS it publishes 71762 times
for 71847 reads — one ring handoff per ~1 KB read, no coalescing at all. The
drain loop publishes on the first EAGAIN, and on this pty there is *always* an
EAGAIN between ~1 KB reads, so the slot never fills.

The cost is not theoretical: our shipped pattern (mode 4, 0.684 s) is **71%
slower than simply doing blocking reads on one thread** (mode 0, 0.400 s). The
thread split we added to parallelise transport and parse is, on this platform,
paying a condition-variable round trip per kilobyte to parallelise ~1 KB of
parse work.

Mode 9 shows the fix is cheap: adding a short linger on EAGAIN — keep filling
the slot while data is still arriving, publish on slot-full or quiescence —
takes feeds from 71762 to 278 (mean batch 261 KB) and wall from 0.684 to
0.545 s. Mode 0 is faster still.

So on macOS the read path, not the renderer, is the first lever, and the
Linux-tuned design is actively counterproductive. Closing mode 4 -> mode 0 on
this workload is ~0.28 s; our live wall is 0.863 s against ghostty's 0.614.

## 2. The main thread is ~77% busy, almost all of it rebuilding widgets

15 s sample at 1 ms, streaming `03_sgr_fg` continuously (11226 main-thread
samples):

| phase | % of wall |
|---|---|
| frame callback total (`SwiftRuntimeController::BeginFrame`) | 77.4% |
| — build phase (`buildScopeWithCallback`) | **70.1%** |
| — flushPaint | 5.1% |
| — flushLayout | 1.9% |
| — compositeFrame | ~0% |
| text layout (`Paragraph`) | 14.8% |

The build phase is an `Element.updateChild` cascade down the row tree — the
terminal rebuilds its visible rows every frame. Layout, paint and composite
together are under 8%: the expensive part is reconciling the widget tree, not
drawing it.

**This does not gate the data path.** The PTY threads were idle waiting for
data ~70% of the time (reader blocked in `poll`, parser blocked in
`ChunkRing.nextForRead`), and lock contention between the parser's
`emulator.feed` and the view's grid snapshot is 9 samples out of 11226 — noise.
Rendering and transport are genuinely decoupled here; they are two independent
costs, and §1 is the one that bounds throughput.

## 3. CVDisplayLink thread churn

354 distinct `CVDisplayLink` threads were created during the 15 s sample —
~24/s, each living ~30 ms, all of them parked in `CVDisplayLink::waitUntil`.
They are created by `DisplayLinkManager::RegisterDisplayLink` inside
FlutterMacOS: the embedder starts the display link to get a vsync callback and
stops it when no further frame is pending, and stopping one tears down its IO
thread. The threads are idle, so this costs little CPU, but each start pays a
thread spawn and up to a frame of latency before the first callback.

Not chased further — §1 dominates — but it is engine-side behaviour worth
knowing about before anyone reads a frame-pacing number on this platform.

## Reproducing

The sample:

    STARLING_TERMINAL_SINGLE=1 STARLING_WINDOW_W=1585 STARLING_WINDOW_H=817 \
      STARLING_DEV_SHELL=<loop cat 03_sgr_fg> TerminalApp &
    sample <pid> 15 1 -f prof.txt

`ptyread.c` needs four edits to build on macOS, none of which change what it
measures: `<pty.h>` -> `<util.h>`, `<sys/prctl.h>` and `<liburing.h>` guarded
out (modes 5 and 7 are io_uring, Linux-only), `prctl(PR_SET_TIMERSLACK)`
no-oped, and `ppoll` shimmed onto `poll`. The shim is millisecond-granular, so
mode 9's default 300 us linger rounds to zero — the numbers above use
`PTYREAD_LINGER_US=2000`. A real macOS linger wants `kevent` or `nanosleep`,
not this shim.
