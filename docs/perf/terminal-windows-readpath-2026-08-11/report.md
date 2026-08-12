# Two Windows perf fixes that did not work, and what the data says instead

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

## What the data actually says

We are not slow, we are **starved**. On `light_cells`, Windows Terminal spends
**2.80 CPU-seconds to our 0.46 and finishes 2.2x sooner** — it is doing six
times the work and winning. Nothing on our side of the pipe can fix a deficit
in what arrives through it.

The strongest remaining lead is that **we and Windows Terminal are not talking
to the same ConPTY**. WT ships its own console host inside its package:

    C:\Program Files\WindowsApps\Microsoft.WindowsTerminal_1.24.11911.0_x64__8wekyb3d8bbwe\OpenConsole.exe

Our `CreatePseudoConsole()` binds the inbox `conhost.exe`. Since we are idle
95% of the run waiting on the producer, and the producer is a *different and
much newer binary* in WT's case, "their conhost vs the inbox conhost" is a
candidate that fits every number here — including why the escape-heavy
workloads, where conhost's re-synthesis dominates for both of us, are already
at parity.

**This is a lead, not a finding — it has not been tested.** The way to test it
is to have our shim load WT's `OpenConsole.exe` as the ConPTY provider (which
is the mechanism WT itself uses) and re-run `light_cells`. If the gap closes,
the fix is packaging, not code, and it is worth knowing that before optimizing
anything else on this platform.

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
