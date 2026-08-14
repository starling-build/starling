# The long round — every test at steady state, minutes not seconds

2026-08-14 (overnight from 08-13), the same matched-font bench configuration
as `terminal-vs-ghostty-macos-2026-08-13-samefont` (same binaries, same
Roboto Mono metrics via the ghostty config, ours on the release engine at
the shipping default cell, grids verified **47x201** on every counted leg),
with every test scaled to run minutes:

- the 10-workload suite with per-workload repeat counts (170x-3200x,
  `run-bench-long.zsh`) targeting >=2 minutes per workload,
- the published cats at **500 MB** (exact 500,000,000-byte corpora),
- DOOM-Fire at **150,000 frames** (~2.3 minutes per rep), 3 reps.

Why this round exists: the 6000-frame DOOM rerun in the samefont report
showed ghostty's numbers rise with run length. This round asks what both
terminals do at genuine steady state.

## It took three attempts, and the two failures are data

**Round 1** ran unattended; ten minutes in, macOS put the display to sleep
and engaged the lock. Everything measured after that point is a different
system state: ours' 05_unicode read 3x its clean rate, ghostty's
02_dense_cells 3.2x, and *both* terminals fell to 139-181 fps on DOOM (from
~1080/~1065 clean) with CPU pegged the whole time. Preserved in
`data-display-asleep/` as a record of display-off throughput — interesting,
but not a terminal benchmark.

**Round 2** relaunched under `caffeinate -disu`, which woke the display —
into the **lock screen with the animated aerial wallpaper** (WindowServer
at 31% compositing aerials over occluded terminals). Numbers up to 10x off;
discarded entirely.

**Round 3** (this report) ran on an unlocked desktop with `displaysleep 0`
and `sysadminctl -screenLock off`, under `caffeinate -disu`, and every
number is clean: all twenty suite legs land at 0.60-0.93x of their
short-run per-byte prediction — steady state is mildly *faster* than the
short rounds everywhere, exactly the warm-up amortization you'd expect,
on both terminals.

Operational notes that made the round practical: a watchdog
(`grid-watchdog.sh`, in this dir) reads the grid each runner records at
start and kills a wrong-grid ghostty launch within seconds — the known
intermittent 17x49 launch otherwise costs a full 20-40 minute leg before
the post-hoc check discards it (round 1 lost 19 minutes to exactly that).
Round 3 happened to need no retries.

## The suite at steady state (~30 GB per side)

| workload | reps | ours s | ghostty s | ratio | ours vs short | gh vs short |
|---|---|---|---|---|---|---|
| 01_light_cells | 800 | 80.4 | 93.4 | **0.86x** | 0.91x | 0.78x |
| 02_dense_cells | 830 | 95.1 | 96.7 | **0.98x** | 0.89x | 0.80x |
| 03_sgr_fg | 190 | 76.6 | 113.3 | **0.68x** | 0.92x | 0.93x |
| 04_sgr_truecolor | 170 | 96.3 | 107.1 | **0.90x** | 0.92x | 0.88x |
| 05_unicode | 400 | 114.5 | 99.7 | 1.15x | 0.89x | 0.82x |
| 06_cursor_motion | 3200 | 65.7 | 71.4 | **0.92x** | 0.66x | 0.60x |
| 07_alt_screen | 670 | 128.7 | 91.8 | 1.40x | 0.93x | 0.76x |
| 08_scroll_region | 550 | 89.2 | 98.4 | **0.91x** | 0.90x | 0.82x |
| 09_long_lines | 660 | 99.2 | 98.3 | 1.01x | 0.92x | 0.82x |
| 10_binary | 220 | 36.8 | 109.1 | **0.34x** | 0.89x | 0.91x |
| **total** | | **882.5** | **979.0** | **0.90x** | | |

| | ours | ghostty |
|---|---|---|
| suite CPU | **828 s** | 2451 s (0.34x) |
| RSS after ~30 GB | **121 MB** | 155 MB |

The "vs short" columns are this run's wall against (short-run median x
reps): both terminals beat their short-run rates everywhere, ghostty by
more — so the steady-state ratio (0.90x) is tighter than the short-run
round's 0.77x. Both numbers are honest; they measure different regimes,
and the short-run table carries relatively more of both terminals' warm-up.

Where the losses sharpened, work lives: **07_alt_screen 1.40x** (was 1.15x
short-run) is now the clearest optimization target in the file, with
05_unicode (1.15x) second. Everything else holds or improves; 10_binary
remains 3x in our favour.

## Cats at 500 MB (medians of 3)

| test | ours | ghostty | ratio | CPU ours/gh |
|---|---|---|---|---|
| ascii cat 500 MB | 1.908 s | 2.049 s | **0.93x** | 1.77 / 4.75 (37%) |
| unicode cat 500 MB | 2.536 s | 2.396 s | 1.06x | 3.87 / 6.42 (60%) |

At 500 MB the unicode cat flips to ghostty by 6% (it was 0.98x at 150 MB)
— their per-byte rate improves more with length, same as everywhere else.
Ascii stays ours. RSS after the cats: ours 121 MB, ghostty 177 MB.

## DOOM-Fire at 150,000 frames: fps converges, CPU separates

Three reps per side, ~2.3 min each, all six verified 47x201:

    ours:    1083.0  1084.8  1085.2 fps   at ~148.3 cpu_s per rep
    ghostty: 1060.5  1067.8  1066.5 fps   at ~371.6 cpu_s per rep

The full run-length curve, one sitting each:

| frames | ours fps | ghostty fps | ratio |
|---|---|---|---|
| 600 | ~1025 | ~845 | 1.21x |
| 6 000 | ~1058 | ~960 | 1.10x |
| 150 000 | ~1084 | ~1065 | **1.02x** |

At steady state the fps race is a statistical tie at what is evidently the
transport ceiling — and the differentiator is **CPU: 148 vs 372 s per rep
(0.40x)**. Ours holds 1084 fps on ~1.07 cores; ghostty holds 1065 on ~2.6.
The samefont report's fire ratios (1.21x, then 1.10x) are warm-up
gradients, real but transient; this is the asymptote.

## What the round changes about the standing conclusions

Every fps-shaped ratio tightens toward a shared ceiling as runs lengthen:
suite 0.77x -> 0.90x, ascii cat 0.88x -> 0.93x, unicode cat 0.98x -> 1.06x,
DOOM 1.21x -> 1.02x. What does NOT tighten is cost: **CPU 0.34x on the
suite, 0.40x on DOOM, 0.37-0.60x on the cats, and RSS 121 vs 155-177 MB.**
At steady state the two terminals deliver comparable throughput and ours
does it on a third of the CPU — that, plus the per-workload wins and the
two named losses (07_alt_screen, 05_unicode), is the durable summary.

## Provenance

Identical to `terminal-vs-ghostty-macos-2026-08-13-samefont` (starling
`main` 5156a9c + engine `starling` ea78543 host_release_arm64, dyld
verified; ghostty tip 1.3.2-main+51ed437cd; Roboto Mono matched metrics;
`STARLING_TERMINAL_SINGLE=1`, no STARLING_CELL_H). Harness in this dir:
`bench-long.sh` (orchestrator), `grid-watchdog.sh`;
`run-bench-long.zsh` / `bench-in-terminal-long.sh` / `bigcat500-mac.sh`
archived beside the corpus in `/var/tmp/bench/corpus/`. AC power
throughout, `pmset` logged at start and end of each round. Raw:
`data/` (round 3, clean), `data-display-asleep/` (round 1).
