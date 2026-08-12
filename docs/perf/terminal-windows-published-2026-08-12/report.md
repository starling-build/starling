# Ghostty's published `cat` tests on Windows — a 2% tie, and why that is the finding

2026-08-12, win11 libvirt VM (4 vCPU, QXL at 1280x800). Ghostty's two
`time cat 150MB` tests, ours against **Windows Terminal 1.24.11911.0** —
there is no ghostty on Windows (macOS/Linux only), so WT is the rival, as in
`../terminal-windows-2026-08-11/`.

Ours is `measure-openconsole` (b79fc0f), i.e. with its own OpenConsole host.
Both terminals at a **verified 40x120**, 2 reps, `cmd /c type` as the writer,
`bigcat.ps1` run inside each terminal via the interactive scheduled task.
Raw: `data/`.

| test | ours | Windows Terminal | ours/WT |
|---|---|---|---|
| `cat 150MB ascii` | **55.94** | 57.31 | **0.98x** |
| `cat 150MB unicode` | **57.94** | 58.92 | **0.98x** |

| | ours | WT |
|---|---|---|
| CPU, ascii | **5.09** | 46.55 |
| CPU, unicode | **6.36** | 48.16 |
| peak RSS | 43 MB | **30 MB** |

## What it means

- **A 2% spread is the result, not a win.** On Linux this same test spread
  five terminals across 0.70-1.47 s — a 2x range. Here two different
  terminals land within 2% of each other, because on Windows neither is
  doing the work that sets the clock. ConPTY's console host re-synthesizes
  the whole stream, and it is the bottleneck for both. Treat any Windows
  terminal throughput number as a measurement of the host first.
- **The CPU column is where they differ: 5.09 vs 46.55 CPU-seconds on ascii,
  9x.** WT spends about 47 CPU-seconds to finish 2% later. That is the same
  shape as the ten-workload suite (we ran at 42% of its CPU) but far more
  extreme on a pure dump, where there is nothing to do but consume.
- **Unicode is nearly free for us: +3.6% over ascii** (57.94 vs 55.94). Worth
  recording because on Linux the UTF-8 path was our standout weakness —
  last of five terminals and 2.3x behind ghostty in Round 7/8 — before that
  gap was closed. On Windows it barely registers, for the same reason
  everything else is flat: the host dominates.
- **RSS goes the other way here: 43 MB to WT's 30 MB.** The ten-workload
  suite had it 36 MB to WT's 95. Opposite results on different workloads, so
  neither number supports a general memory claim.

## Caveats, before anyone quotes these

- **Not comparable to the Linux numbers.** The corpora are the same shape,
  size and content pools as
  `../terminal-vs-ghostty-2026-08-04/gen-150mb.py`, but wrapped at 119
  columns for this 120-column grid instead of 200 for a 201-column one. And
  ConPTY sets a completely different scale — 150 MB takes ~56 s here against
  ~0.75 s on Linux, ~75x. Only the ours-vs-WT ratio means anything.
- **Rep 1 CPU for ours is startup, not throughput** (36.75 vs rep 2's 5.09):
  the app had just launched and was doing first-paint and font work. The
  table quotes steady state. WT's two reps agree (46.00/47.09), so its
  number needs no such treatment.
- **The third published test, DOOM-Fire, was NOT run.** It needs Zig 0.14
  built on Windows (0.16 breaks its `build.zig`) plus the 19-line
  frame-budget patch from `../terminal-vs-ghostty-2026-08-04/`. That is a
  toolchain build rather than a corpus generation, so it is left open rather
  than half-done.
- Only 2 reps. Rep-to-rep spread was 1.6% and 1.2% for ours, 2.7% and 2.1%
  for WT, so the 2% gap between the terminals is at the edge of that noise —
  which is precisely why the conclusion above is "tie", not "we win".

## Reproducing

    python gen-150mb-win.py C:\bench150 119     # 119 = grid columns - 1
    # then, inside each terminal, at a verified 40x120:
    powershell -File bigcat.ps1 -Label <name> -ProcName <TerminalApp|WindowsTerminal> -Reps 2
