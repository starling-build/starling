# The Linux long round — every test at steady state, minutes not seconds

2026-08-14, on GNOME. The Linux counterpart of
`terminal-vs-ghostty-macos-2026-08-13-long`: the same matched-font
configuration as `terminal-vs-ghostty-2026-08-13-atlas` (ghostty on
Roboto Mono 10.5 / adjust-cell-height -8% via its config, ours at the
shipping default cell on the release engine), with every test scaled to
run minutes:

- the 10-workload suite with per-workload repeat counts (75x-3500x,
  targeting >=120 s on the slower side from the atlas-round medians),
- the published cats at **500 MB** (exact 500,000,000-byte corpora),
- DOOM-Fire at **150,000 frames** (~1.5-3 min per rep), 3 reps per side.

Binaries: ours is the GTK TerminalApp from `.build-gtk` (release), main
`58d5f86`, engine `ea78543` host_release; ghostty is tip
**1.3.2-main+f81dcad**, built ReleaseFast from the source tarball the
same day. Machine: Lenovo Slim Pro 7, AC power, quiet box; **Dell
P2715Q alone at 3840x2160@30, scale 1** (internal panel off for the
round, restored after). The 30 Hz refresh slows absolute walls on both
sides against 60 Hz rounds; ratios transfer, walls do not.

## Grids, and the one operational wrinkle

Ours launched at **47x201 exactly, every leg** (window 1624x823, cell
8.00 px). Ghostty launched at **47x202 on every attempt today** — the
familiar one-column drift, but deterministic this time: the orchestrator
retried each ghostty leg three times and got 202 columns nine times out
of nine, while the morning calibration probe of the identical command
had read 201. The corpus is 201 wide, so at 202 nothing wraps and the
extra column is blank; the atlas round accepted such legs on the same
reasoning, and this round does too (the ghostty legs were re-run by
`gh-legs-manual.sh`, which admits both grids — in `data/`, alongside
`round.log`, which records every launch, abort, and retry). The one
place 202 is not free is DOOM-Fire, which fills the width: ghostty's
fire frames are 0.5% larger. That error is in ghostty's favour's
opposite — read its fire fps as at most 0.5% understated.

## The suite at steady state (~159 GB per side)

| workload | reps | ours s | ghostty s | ratio | short ratio | ours vs short | gh vs short |
|---|---|---|---|---|---|---|---|
| 01_light_cells | 210 | 101.2 | 102.0 | **0.99x** | 1.18x | 0.82x | 0.98x |
| 02_dense_cells | 490 | 86.8 | 86.2 | 1.01x | 1.44x | 0.71x | 1.02x |
| 03_sgr_fg | 120 | 34.0 | 108.3 | **0.31x** | 0.37x | 0.73x | 0.87x |
| 04_sgr_truecolor | 160 | 54.2 | 122.8 | **0.44x** | 0.51x | 0.87x | 1.01x |
| 05_unicode | 360 | 97.1 | 107.3 | **0.91x** | 1.06x | 0.81x | 0.94x |
| 06_cursor_motion | 3500 | 49.9 | 74.3 | **0.67x** | 0.65x | 0.65x | 0.62x |
| 07_alt_screen | 900 | 80.8 | 85.9 | **0.94x** | 0.87x | 0.77x | 0.71x |
| 08_scroll_region | 240 | 80.4 | 78.5 | 1.02x | 1.12x | 0.66x | 0.72x |
| 09_long_lines | 820 | 85.0 | 84.3 | 1.01x | 0.99x | 0.72x | 0.70x |
| 10_binary | 75 | 26.7 | 109.9 | **0.24x** | 0.29x | 0.74x | 0.90x |
| **total** | | **696.0** | **959.6** | **0.73x** | | | |

| | ours | ghostty |
|---|---|---|
| suite CPU | **1030 s** (1.48 cores avg) | 1930 s (2.01 cores) — **0.53x** |
| RSS after ~159 GB | 225 MB | **212 MB** |

Two framing notes, both important:

- The 0.73x total is not comparable to the atlas round's 0.62x — the
  rep counts weight the workloads differently. The like-for-like number:
  these reps times the short-run medians predict 934 s vs 1142 s =
  **0.82x**, and the measured steady state came in at **0.73x** — on
  Linux, run length moves the suite *toward us* (ours lands at
  0.65-0.87x of its short-run prediction; ghostty at 0.62-1.02x, with
  three workloads showing no warm-up benefit at all).
- **Both short-run losses converge to parity at steady state.**
  01_light_cells (1.18x short) and 02_dense_cells (1.44x short) — the
  two workloads ghostty won by real margins — land at 0.99x and 1.01x
  over 86-102 s of sustained load. 05_unicode flips from 1.06x to a
  0.91x win. At steady state the worst cell in our column is
  08_scroll_region at 1.02x; everything else is a win, five of them by
  1.5-4x. The macOS long round's two named losses (07_alt_screen 1.40x,
  05_unicode 1.15x there) do not exist in the GTK build — 0.94x and
  0.91x here.

## Cats at 500 MB (medians of 3)

| test | ours | ghostty | ratio | CPU ours/gh |
|---|---|---|---|---|
| ascii cat 500 MB | 2.971 s | 2.792 s | 1.06x | 3.92 / 5.56 (71%) |
| unicode cat 500 MB | **2.883 s** | 5.152 s | **0.56x** | 5.44 / 10.95 (50%) |

The ascii cat stays ghostty's by ~6% — the read(2) pty floor against
their io_uring, unchanged through every round and every length. The
unicode cat does **not** flip with length on Linux the way it did on
macOS (1.06x there at 500 MB): ours holds a 1.8x advantage at exactly
the scale where their macOS build catches up. RSS after the cats: ours
225 MB, ghostty 256 MB.

## DOOM-Fire at 150,000 frames: no convergence on Linux

Three reps per side, all verified (ours 47x201, ghostty 47x202):

    ours:    1608.3  1610.3  1611.7 fps   at ~169.8 cpu_s per rep
    ghostty:  837.1   830.0   827.7 fps   at ~378.9 cpu_s per rep

| frames | ours fps | ghostty fps | ratio |
|---|---|---|---|
| 600 (atlas round, 08-13) | ~1200 | ~701 | 1.71x |
| 150 000 | ~1610 | ~830 | **1.94x** |

This is the sharpest divergence from the macOS long round, where both
terminals rose to a shared ~1065-1084 fps transport ceiling and the
race ended in a statistical tie. On Linux there is no shared ceiling in
sight: both sides gain from steady state, ours gains more, and the gap
*widens* to **1.94x fps at 0.45x CPU** — 1610 fps on ~1.8 cores against
830 on ~2.1. The three ours reps agree within 0.2%.

## What the round establishes

On Linux, length is our friend everywhere it matters: the suite ratio
improves from its rep-weighted 0.82x prediction to 0.73x, the two
short-run suite losses dissolve into parity, the unicode cat holds
0.56x at 500 MB, and DOOM-Fire widens to 1.94x. Cost separates the same
way it did on macOS: **CPU 0.53x on the suite, 0.45x on DOOM, 50-71% on
the cats.** Ghostty keeps exactly two numbers: the ascii cat (+6%, the
pty read floor) and end-of-suite RSS (212 vs 225 MB — reversed after
the cats, 256 vs 225). The durable Linux summary: at steady state ours
is never behind by more than 6% anywhere, wins most workloads outright,
and does everything on half the CPU.

## Provenance

Harness in this dir: `orchestrate.sh` (per-leg launch, done-key polling,
and a 10 s wrong-grid abort — the macOS round lost 19 minutes to a bad
ghostty launch; this rig killed each one within seconds),
`gh-legs-manual.sh` (the ghostty re-runs accepting 47x202),
`run-bench-long.sh` / `bench-in-terminal-long.sh` / `bigcat500.sh` /
`doomfire.sh` (runners; terminal-pid discovery by ancestor walk, CPU
from `/proc/<pid>/stat`, walls from `$EPOCHREALTIME`), `dell-only.py`
(the display swap, `restore` to undo). Corpora in `/var/tmp/bench-long/`
(suite regenerated at 201x47 by `test/bench/gen-bench.py`, 500 MB cats
exact). DOOM binary is the same 2-line-patched DOOM-fire-zig as every
prior round (`DOOMFIRE_FRAMES`, fps on stderr). Raw results and the
full launch/abort log: `data/`. Short-run baselines for the "vs short"
columns are the `terminal-vs-ghostty-2026-08-13-atlas` matched-font
medians; ours' binary has moved since that round (the glyph-coverage
work landed in between), ghostty's tip moved a day — the columns are
regime comparisons, not same-binary A/Bs.
