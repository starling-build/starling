# Windows terminal vs Windows Terminal, on main, one sitting

2026-08-12, win11 libvirt VM (4 vCPU, QXL at 1280x800), `main` at `a9ac17e`
(bundled ConPTY host + reader/parser split, panes reverted). Grid verified
40x120 on both sides before every run. **Every number here was taken in one
session, ours and WT alternating** — see "why that matters" below.

## Ten-workload suite (2 reps, median)

| workload | main | Windows Terminal | ours/WT |
|---|---|---|---|
| 01_light_cells | 4.36 | 4.38 | **0.99x** |
| 02_dense_cells | 7.04 | 6.97 | 1.01x |
| 03_sgr_fg | 18.36 | 17.50 | 1.05x |
| 04_sgr_truecolor | 27.06 | 26.16 | 1.03x |
| 05_unicode | 14.21 | 14.06 | 1.01x |
| 06_cursor_motion | 1.43 | 1.42 | **1.00x** |
| 07_alt_screen | 8.17 | 7.93 | 1.03x |
| 08_scroll_region | 18.01 | 17.31 | 1.04x |
| 09_long_lines | 9.33 | 8.96 | 1.04x |
| 10_binary | 13.88 | 12.98 | 1.07x |
| **total** | **121.8** | **117.7** | **1.04x** |

Peak RSS **36 MB vs 94 MB**.

## Ghostty's three published tests

| test | main | Windows Terminal | ours/WT |
|---|---|---|---|
| `cat 150MB` ascii (2 reps) | 57.32 | 56.82 | 1.01x |
| `cat 150MB` unicode (2 reps) | 58.12 | 59.14 | **0.98x** |
| DOOM-Fire fps (5 reps) | 711.7 | 777.2 | 0.92x |

## Why the same-session control matters

The previous reports quoted 1.02x on the suite and 0.95x on DOOM. Those were
assembled from runs taken hours apart, and re-running everything showed the
machine had moved underneath them — **in different directions for different
workloads**, on identical binaries:

| WT, same binary and grid | earlier | now | drift |
|---|---|---|---|
| suite total | 114.8 | 117.7 | **+2.5% slower** |
| DOOM-Fire | 752.8 | 777.2 | **-3.2% faster** |

So a cross-session comparison is not merely noisy, it is noisy in a direction
you cannot predict or correct for. The suite drifted slower while DOOM drifted
faster on the same idle VM over the same hours.

Concretely, the earlier figures were wrong in both directions: the suite gap
was overstated by comparing our-now against WT-from-hours-ago (1.06x when
computed that way, 1.04x controlled), and DOOM was understated (0.95x
cross-session, 0.92x controlled).

**Rule this repo already had and this session re-learned: always re-run the
opponent as a control, in the same sitting.** It is in the ghostty rounds for
the same reason. A benchmark number without a same-session control is a claim
about two machines, not two programs.

Raw data in `data/` — five files, all from this run.
