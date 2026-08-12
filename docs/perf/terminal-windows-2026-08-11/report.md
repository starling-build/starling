# TerminalApp on Windows — level with Windows Terminal, except on plain cells

> **Superseded for headline numbers.** The figures here were assembled from
> runs taken hours apart. Re-running everything in one sitting showed the
> machine drifts — and in different directions per workload (WT's suite
> +2.5% slower, its DOOM 3.2% faster, same binary). The controlled numbers on
> current `main` are in `../terminal-windows-main-2026-08-12/`: suite 1.04x,
> DOOM 0.92x, cat tests 1.01x / 0.98x. The diagnoses in this document (which
> host, which chunk size, which layout) still stand; only the ratios move.

2026-08-11, the win11 libvirt VM (4 vCPU, QXL display at 1280x800).
Measured at **`8fea923`** — named rather than called "main" because the
floating-pane workspace (`4cdb460`) landed on top of it while this rerun was
in flight, and that commit touches `TerminalView`. Built with
`sdk/tools/build-windows.ps1 -Configuration release` against the Aug-5
host_release engine.

**This report was published earlier the same day with numbers that were
wrong, and the corrections are large.** What that first pass got wrong, and
why, is at the bottom — it is the more useful half of the writeup. The table
here supersedes it entirely.

There is no ghostty on Windows (macOS/Linux only), so the rival is **Windows
Terminal** — the default, and the only other terminal the VM can run:
alacritty installs but needs OpenGL 3.3+, which the QXL adapter does not
provide (WT survives on DirectX/WARP).

Protocol: both terminals at a **verified** 120x40 — ours via
`STARLING_WINDOW_W=960/H=620`, WT via `--size 120,40`, and in both cases the
grid the runner recorded in its own header was checked, not assumed. Corpus
generated for that grid (`gen-bench.py C:\bench 120 40`),
`test/bench/windows-runner.ps1` run inside each terminal via the interactive
scheduled task, `cmd /c type` as the writer, **2 reps, median**, on a VM
warm for hours. Raw: `data/res-ours-warm.txt`, `data/res-wt-warm.txt`.

| workload | ours | Windows Terminal | ours/WT |
|---|---|---|---|
| 01_light_cells | 9.36 | 4.18 | **2.24x** |
| 02_dense_cells | 7.06 | 6.59 | 1.07x |
| 03_sgr_fg | 17.81 | 17.70 | 1.01x |
| 04_sgr_truecolor | 23.89 | 25.21 | **0.95x** |
| 05_unicode | 14.18 | 13.16 | 1.08x |
| 06_cursor_motion | 1.32 | 1.35 | **0.98x** |
| 07_alt_screen | 7.77 | 7.65 | 1.02x |
| 08_scroll_region | 16.46 | 16.98 | **0.97x** |
| 09_long_lines | 9.25 | 8.80 | 1.05x |
| 10_binary | 15.17 | 13.16 | 1.15x |
| **total** | **122.3** | **114.8** | **1.07x** |

| | ours | WT |
|---|---|---|
| CPU seconds, whole suite | **45.4** | 107.6 |
| peak RSS | **36 MB** | 95 MB |

Rep-to-rep spread was under 3% on every workload except our `05_unicode`
(5.1%); most were under 1%.

## What is true

- **On the whole suite we are 7% behind, and one workload is the entire
  gap.** Drop `01_light_cells` and the totals are 112.9 vs 110.6 — **1.02x,
  a dead heat**. `light_cells` alone is 5.2 s of the 7.5 s difference.
- **We win three outright** (`sgr_truecolor`, `cursor_motion`,
  `scroll_region`) and are inside 2% on two more (`sgr_fg`, `alt_screen`).
  The escape-heavy and scrolling workloads — the ones the C core was built
  for — are where we are strongest, which is the result the Linux work
  predicts.
- **We do it on 42% of the CPU and 38% of the memory.** 45.4 CPU-seconds
  against 107.6 is the most interesting number in the table: on a 4-vCPU
  box, wall-clock parity at less than half the CPU means the ConPTY
  pipeline, not the terminal, is holding the clock. `10_binary` is the
  clearest case — WT spends 25.6 CPU-seconds to our 2.6 and still finishes
  ahead on wall.
- **`01_light_cells` at 2.24x is the one real deficit**, and it is
  reproducible (1.9% spread). It is also the workload with the least escape
  processing and the most raw line traffic.

  > **Followed up the same day, and the obvious fix is wrong.** The
  > suspicion here was the pre-split serial reader — port `ChunkRing` and
  > drain-into-slot from Linux. That was measured and is a **regression**
  > (slower on all ten workloads, +2.3% wall, +22% CPU), as is visible in
  > this very table: `light_cells` spent 9.36 s wall against **0.46 s of our
  > CPU**, so there was no parse time for a split to hide. Raising the
  > ConPTY pipe buffer to 1 MB was likewise a null. The live lead is that
  > Windows Terminal ships its own newer `OpenConsole.exe` while we bind the
  > inbox `conhost.exe` — we are starved, not slow.
  > See `../terminal-windows-readpath-2026-08-11/`.

Context that keeps these honest: **everything here is 20-1000x slower than
Linux for both terminals** — ConPTY interprets the writer's output into its
own buffer and re-emits a synthesized VT stream, and that pipeline sets the
scale (Linux `sgr_fg`: 0.26 s). Only within-Windows ratios mean anything.
And our Windows path has still had zero performance work; this is what it
does before anyone has optimized it.

## What the first version got wrong, and why

Two errors, one cause: **the pilot was run minutes after the VM booted**,
with Defender still churning through a fresh `winget install`. Its raw data
is kept as `data/res-{ours,wt}-pilot-RETRACTED.txt`. It reported:

- **`03_sgr_fg` at 248.6 s — "13.8x behind"**, and a whole paragraph
  diagnosing it as a pathology: 0.17 MB/s, "quadratic-or-timeout-shaped",
  with per-chunk repaint scheduling and Foundation timer resolution named as
  first suspects. **There is no pathology.** Warm, the same workload runs
  **17.81 s against WT's 17.70 — parity.** The published figure was 14x its
  own true value, and the paragraph of mechanism was reasoning about noise.
- **A grid mismatch the report denied.** It claimed both terminals ran
  "exactly 120x40". The raw data it shipped alongside records ours at
  `45x119` and WT at `40x120` — so the published table compared a 45-row
  terminal against a 40-row one, and said in prose that it hadn't. At the
  same 960x620 request the build now lands on `40x120` three probes running,
  so that too was the first boot's transient, not a calibration error.

Every workload was inflated, not just the headline — `07_alt_screen` by
2.37x, `08_scroll_region` by 2.27x, and the rest by 12-46%:

| workload | published | corrected | inflation |
|---|---|---|---|
| 01_light_cells | 10.46 | 9.36 | 1.12x |
| 02_dense_cells | 8.65 | 7.06 | 1.22x |
| 03_sgr_fg | 248.59 | 17.81 | **13.96x** |
| 04_sgr_truecolor | 34.82 | 23.89 | 1.46x |
| 05_unicode | 18.53 | 14.18 | 1.31x |
| 06_cursor_motion | 1.53 | 1.32 | 1.16x |
| 07_alt_screen | 18.46 | 7.77 | 2.37x |
| 08_scroll_region | 37.44 | 16.46 | 2.27x |
| 09_long_lines | 11.96 | 9.25 | 1.29x |
| 10_binary | 21.60 | 15.17 | 1.42x |

WT's column was inflated too (`light_cells` 4.52 → 4.18, `sgr_truecolor`
27.75 → 25.21), just far less — which is exactly why the ratios looked
plausible enough to publish. The pilot's conclusion, "WT beats us
everywhere", was wrong in both directions at once: we win three and tie two.

Three rules came out of this, all cheap:

1. **The first run after a VM boots is not data.** Nothing about the
   terminal changed between the two runs in this document.
2. **Print the grid and read it.** The runner already recorded the grid in
   its header; the mismatch was sitting in the shipped data file the whole
   time, contradicting the prose one directory away.
3. **Do not write mechanism for a number you have measured once.** The
   pathology paragraph was the most confident-sounding part of the report
   and the only part describing something that does not exist. A second rep
   would have cost 18 seconds.

The port itself is healthy: current main builds, runs, renders PowerShell,
and survives the full corpus — on a third of WT's memory and 42% of its CPU.

(Both runs here also required a manifest fix, `8fea923`: the `TerminalDemo`
product was declared for Windows while its target was appended only under
`#if os(Linux)`, and SwiftPM refuses the entire graph for one dangling
product — so nothing in the package built on Windows at all.)
