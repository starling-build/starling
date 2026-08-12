# Two Windows perf fixes that did not work, one profile that found it, and the fix

**Resolved.** `01_light_cells` went **9.36 s -> 4.21 s (-55%)**, which is
**1.01x Windows Terminal** where it had been 2.24x, and the suite went
122.3 -> 116.8 (1.02x WT). The cause was not in our code at all: we were
running a different, much slower console host than WT. Details in
"The profile, and the fix" below — the two failed attempts above it are kept
because the way they failed is the useful part.


2026-08-11, win11 libvirt VM, same protocol as
`../terminal-windows-2026-08-11/` (verified 40x120 both sides, 2 reps,
median, warm VM). Every build below is `8fea923` plus exactly one change, so
each is directly comparable to that report's baseline.

**Nothing here is merged.** This exists so the next person does not spend the
evening re-deriving it.

## What was tried

The corrected Windows report closed with a confident next step:
`01_light_cells` is 2.24x Windows Terminal, that is the workload shape
`ChunkRing` + drain-into-slot fixed on Linux, and the split was never ported
to `PtyWindows`. So port it.

| workload | baseline | reader/parser split | 1 MB output pipe | WT |
|---|---|---|---|---|
| 01_light_cells | 9.36 | 9.50 | 9.35 | 4.18 |
| 02_dense_cells | 7.06 | 7.24 | 7.12 | 6.59 |
| 03_sgr_fg | 17.81 | 18.45 | 17.81 | 17.70 |
| 04_sgr_truecolor | 23.89 | 24.54 | 24.43 | 25.21 |
| 05_unicode | 14.18 | 14.35 | 14.30 | 13.16 |
| 06_cursor_motion | 1.32 | 1.40 | 1.37 | 1.35 |
| 07_alt_screen | 7.77 | 7.94 | 7.76 | 7.65 |
| 08_scroll_region | 16.46 | 16.66 | 16.46 | 16.98 |
| 09_long_lines | 9.25 | 9.44 | 9.63 | 8.80 |
| 10_binary | 15.17 | 15.61 | 15.29 | 13.16 |
| **total** | **122.3** | **125.1 (+2.3%)** | **123.5 (+1.0%)** | **114.8** |
| CPU s | 45.4 | 55.4 (+22%) | 42.8 | 107.6 |

### 1. Reader/parser split over ChunkRing — REGRESSION, do not retry

Ported faithfully from `Pty.swift`: reader and parser threads over the
existing `ChunkRing` (which was already compiled on Windows and unused), plus
drain-into-slot through a new `starling_conpty_avail()` over `PeekNamedPipe`.

Slower on **all ten** workloads, +2.3% wall and +22% CPU.

The reason it cannot help was already in the baseline, one column over:
`01_light_cells` ran **9.36 s wall against 0.46 s of our CPU — 95% of the run
parked in `ReadFile`**. A read/parse split converts `transport + parse` into
`max(transport, parse)`. That is a large win on Linux, where the parse is a
real fraction of the time. Here parse is ~5% of wall, so the transform buys
nothing measurable and charges two thread handoffs and a `PeekNamedPipe`
syscall per chunk.

### 2. 1 MB ConPTY output pipe — NULL, do not retry

`CreatePipe(..., 0)` gets the system default of about 4 KB, and that buffer is
the whole coupling between conhost (producer) and us. The theory: on a flood
conhost fills 4 KB, blocks, waits to be drained — a context-switch round trip
per 4 KB. Raising it to 1 MB lets the producer run ahead.

It changed nothing: `light_cells` 9.35 vs 9.36, `sgr_fg` 17.81 vs 17.81,
`alt_screen` and `scroll_region` likewise flat. The +1.0% total is run-to-run
noise on the workloads that moved.

Verified the change was actually in the binary before believing the null —
object recompiled after the edit, and `0x00100000` present in
`starling_conpty.c.o`. Pipe capacity is not the constraint, which means
conhost is not blocking on pipe backpressure: it paces the stream itself.

## The profile, and the fix

Both failures above came from theorising about our own code. Profiling took
one run: account for the CPU of **every process in the pipeline**, not just
ours. Our benchmark had only ever recorded our own.

`01_light_cells`, one rep, CPU-seconds by process:

| process | ours | Windows Terminal |
|---|---|---|
| wall | **9.73 s** | **4.34 s** |
| the terminal | 0.41 | 2.97 |
| **conhost** | **7.27** | 0.00 |
| **OpenConsole** | 0.00 | **2.23** |

Three things fall out at once. We and WT **run different console hosts** —
each is exactly zero in the other's run. The same byte stream costs the inbox
`conhost` **7.27 CPU-seconds against OpenConsole's 2.23, 3.3x** — and that is
the whole gap. And WT "burning 6x our CPU" was never a mystery: 2.97 s of it
is its own rendering, running in parallel with a cheap host, while we sat
blocked behind an expensive one.

`OpenConsole.exe` is the same console host built from microsoft/terminal, years
newer than the inbox one. WT reaches it because its statically linked
`winconpty` looks for `OpenConsole.exe` beside its own module. Nothing
redirects the inbox `CreatePseudoConsole` at a different host — dropping
`OpenConsole.exe` into System32 was tried and does nothing — so
`starling_conpty.c` now does what `winconpty` does and starts the host itself:
ConDrv server handle, a reference handle under it, a signal pipe, and the host
with all four handles inherited and named on its command line. The struct
handed back matches the inbox `HPCON` layout, so CreateProcess's
`PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` still understands it.

| workload | conhost (base) | OpenConsole | change | WT | new vs WT |
|---|---|---|---|---|---|
| 01_light_cells | 9.36 | 4.21 | **-55.1%** | 4.18 | 1.01x |
| 02_dense_cells | 7.06 | 6.75 | -4.5% | 6.59 | 1.02x |
| 03_sgr_fg | 17.81 | 17.16 | -3.7% | 17.70 | 0.97x |
| 04_sgr_truecolor | 23.89 | 26.34 | **+10.3%** | 25.21 | 1.04x |
| 05_unicode | 14.18 | 13.88 | -2.1% | 13.16 | 1.05x |
| 06_cursor_motion | 1.32 | 1.41 | +6.6% | 1.35 | 1.04x |
| 07_alt_screen | 7.77 | 7.85 | +0.9% | 7.65 | 1.03x |
| 08_scroll_region | 16.46 | 17.01 | +3.4% | 16.98 | 1.00x |
| 09_long_lines | 9.25 | 8.80 | -4.8% | 8.80 | 1.00x |
| 10_binary | 15.17 | 13.44 | -11.4% | 13.16 | 1.02x |
| **total** | **122.3** | **116.8** | **-4.4%** | **114.8** | **1.02x** |

Every workload now sits between 0.97x and 1.05x of Windows Terminal. The one
real deficit on this platform is gone.

Honestly, the costs: **four workloads got slightly worse**, `sgr_truecolor`
most at +10.3%, and **CPU rose 45.4 -> 54.6 s** because we now spend the run
working instead of blocked. Neither cancels a 55% win on the target workload,
but neither is noise, and `sgr_truecolor` deserves its own look. RSS is
unchanged at 37 MB against WT's 95.

**Not shippable yet.** This was measured against WT's copy of
`OpenConsole.exe`; shipping means building our own from microsoft/terminal
(MIT) and staging it beside the app. The path is opt-in and fails soft — no
`OpenConsole.exe` beside the exe means the inbox `CreatePseudoConsole` runs
exactly as before, and a failed spawn falls back rather than refusing to open
a terminal. Both paths were verified **on screen**, which mattered: the first
version of the change looked **2.5x faster and rendered a blank window**,
because the host was spawned without std handles and so had nowhere to write.
The writer finished early into a void. A timing harness alone would have
called that a triumph.

## The methodological note

The first attempt at this measurement compared a build on current `main`
against the `8fea923` baseline, and `light_cells` "improved" 9.36 -> 8.75.
That was not the change. `4cdb460` (floating panes) had rewritten
`TerminalApp` so the terminal renders inside a pane, giving a **28x105** grid
instead of 40x120 — a smaller terminal doing less work. Caught by the runner's
own grid header, which is the second time in one day that header caught a
comparison that prose would have gotten wrong.

Both real experiments were therefore run on branches off `8fea923` itself, one
change each, grid re-verified at 40x120 before every run.
