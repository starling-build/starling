# Ghostty's three published tests on Windows — two ties and a loss

2026-08-12, win11 libvirt VM (4 vCPU, QXL at 1280x800). All three of
ghostty's published tests — `time cat 150MB` ascii and unicode, plus
DOOM-Fire-Zig — ours against **Windows Terminal 1.24.11911.0**. There is no
ghostty on Windows (macOS/Linux only), so WT is the rival, as in
`../terminal-windows-2026-08-11/`.

Ours is `measure-openconsole` (b79fc0f), i.e. with its own OpenConsole host.
Both terminals at a **verified 40x120**, driven by `bigcat.ps1` /
`doomfire.ps1` run inside each terminal via the interactive scheduled task,
`cmd /c type` as the writer for the dumps. Raw: `data/`.

| test | ours | Windows Terminal | ours/WT |
|---|---|---|---|
| `cat 150MB ascii` (s) | **55.94** | 57.31 | **0.98x** |
| `cat 150MB unicode` (s) | **57.94** | 58.92 | **0.98x** |
| DOOM-Fire (fps, higher better) | 598.8 | **752.8** | **0.80x — we lose** |

| | ours | WT |
|---|---|---|
| CPU, ascii | **5.09** | 46.55 |
| CPU, unicode | **6.36** | 48.16 |
| CPU, DOOM-Fire | **1.33** | 1.91 |
| peak RSS (cat) | 43 MB | **30 MB** |

DOOM-Fire is 3 reps of 600 frames, medians; the `cat` tests are 2 reps.
Both terminals were **screenshotted mid-run** to confirm the fire actually
renders rather than trusting fps — see the note on blank-window artifacts in
`../terminal-windows-readpath-2026-08-11/`.

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
- **DOOM-Fire is a real loss: 598.8 fps to WT's 752.8, 1.26x.** It is the one
  test of the three that is not a bulk dump — 600 small frames, each a full
  repaint of a 120x80 fire in truecolor SGR with cursor addressing. So it
  measures per-frame turnaround rather than drain throughput, and the host
  can pipeline much less of it. That lines up with the only regression the
  OpenConsole switch introduced in the ten-workload suite
  (`sgr_truecolor` +10.3%), which is essentially the same shape of work.
  We do it on 1.33 CPU-seconds to WT's 1.91, so it is not that we are
  burning more to go slower — there is latency in our frame path that the
  bulk tests never expose. **This is the clearest open lead on Windows now.**
  For scale, the same test on Linux gives us 1960 fps against ghostty
  nightly's 1224, so Windows costs us ~3.3x here.

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
- **DOOM-Fire needed no Windows toolchain in the end.** DOOM-fire-zig already
  has native Windows support (`getTermSzWin`, `SetConsoleMode`,
  `SetConsoleOutputCP(CP_UTF8)`), and Zig cross-compiles, so the exe was
  built on the Linux box with `zig build -Dtarget=x86_64-windows`. The only
  source change beyond the existing BENCH patch is
  `doom-fire-windows.patch`: `std.posix.getenv` is a *compile error* on
  Windows (environment strings are WTF-16), so the DOOMFIRE_FRAMES lookup
  goes through `std.process.getEnvVarOwned` on a fixed buffer instead. The
  glyph is the same `▀` on both platforms.
- The `cat` tests are only 2 reps. Rep-to-rep spread was 1.6% and 1.2% for
  ours, 2.7% and 2.1% for WT, so the 2% gap between the terminals is at the
  edge of that noise —
  which is precisely why the conclusion above is "tie", not "we win".

## Reproducing

    python gen-150mb-win.py C:\bench150 119     # 119 = grid columns - 1
    # then, inside each terminal, at a verified 40x120:
    powershell -File bigcat.ps1 -Label <name> -ProcName <TerminalApp|WindowsTerminal> -Reps 2

DOOM-Fire, built on the Linux box and copied over:

    cd DOOM-fire-zig && git apply doom-fire-bench.patch doom-fire-windows.patch
    zig build -Doptimize=ReleaseFast -Dtarget=x86_64-windows   # zig 0.14
    # then, inside each terminal, at a verified 40x120:
    powershell -File doomfire.ps1 -Label <name> -ProcName <proc> -Reps 3 -Frames 600
