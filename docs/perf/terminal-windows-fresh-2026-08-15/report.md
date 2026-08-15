# The 08-15 Windows long round — a clean box, and a watchdog that never worked

2026-08-15, 00:35–01:45 UTC. Ours (`f2a1e12`, the GUI-subsystem build with
tonight's stderr-fatality fix) against **Windows Terminal 1.24.11911.0** —
the same build the 08-14 win11 round used — on `win11-fresh`, a
freshly-installed Windows 11 25H2 guest with nothing else on it.

The headline: **the suite runs in 0.84x of Windows Terminal's wall time on
0.54x of its CPU**, and holds 29 MB of RSS where Windows Terminal holds
1,043 MB.

## The box, and why it is not the win11 box

The user asked for the long round on the *fresh* VM rather than the dev box,
with everything else shut down. So this is a new series, not a continuation
of `terminal-windows-long-2026-08-14` — that round was on win11 and never
finished (its log stops mid-`doom/wt`).

- 8 vCPU (**1 socket x 8 cores** — the domain had 4 vCPU as 4 sockets, and
  Windows 11 licences by socket, so the guest was only ever using 2), 12 GB.
- Sole guest running: `win11` and `passage-srv2025` were shut down for the
  duration, so the 16-core host was not oversubscribed.
- 1280x800, taskbar auto-hidden, screensaver/lock/sleep disabled.
- Power throttling disabled per-executable on **both** terminals; the onset
  leg verified it took, `VERDICT flat` on both sides.

## Deviation: 39x120, not 40x120

Windows Terminal cannot fit a 40-row window on a 1280x800 panel — it clamps
to 39 — so the round ran at **39x120 on both sides** rather than the 40x120
of the win11 round. Ours was sized to match (`STARLING_WINDOW_H=688`), not
the other way round. Absolute numbers are therefore not comparable to the
win11 round; the ours-vs-wt ratios within this round are.

Getting a taller panel was attempted and abandoned: the QXL DOD driver breaks
`ChangeDisplaySettings` outright, and under both the basic adapter and vmvga
the `DEVMODE` P/Invoke marshals to 124 bytes instead of ~160, so
`EnumDisplaySettings` fails and every mode change returns `BADMODE`. Not
worth more time when matching the grid on both sides is what the comparison
actually requires.

## The grid watchdog has never worked

`Run-Leg` declared `$grid = ''` and then tested `if ($grid -ne $GRID)`.
**PowerShell variables are case-insensitive**, so `$grid` and the script's
`$GRID` target are one variable: the assignment overwrote the value it was
about to be compared against, `-ne` tested a value against itself, and the
check could never fail.

It was hiding a real mismatch here — Windows Terminal at 39 rows against ours
at 40 — which is exactly what the watchdog exists to catch. Fixed (the local
is now `$gridSeen`), and every leg in this round is watchdog-verified at
39x120 both before and after streaming. Prior rounds' grid claims were
unverified; they logged 40x120 for both sides, but nothing was enforcing it.

## Suite — 10 workloads, >=120 s each

| workload | ours s | wt s | ratio | ours cpu | wt cpu | cpu ratio |
|---|---:|---:|---:|---:|---:|---:|
| 01_light_cells | 99.9 | 117.2 | **0.852** | 127.8 | 285.1 | 0.448 |
| 02_dense_cells | 108.8 | 113.0 | **0.963** | 162.4 | 226.6 | 0.717 |
| 03_sgr_fg | 119.3 | 140.9 | **0.846** | 169.2 | 350.3 | 0.483 |
| 04_sgr_truecolor | 120.6 | 136.3 | **0.885** | 181.9 | 317.4 | 0.573 |
| 05_unicode | 120.2 | 114.5 | 1.050 | 194.0 | 263.2 | 0.737 |
| 06_cursor_motion | 125.4 | 147.5 | **0.850** | 186.9 | 350.6 | 0.533 |
| 07_alt_screen | 94.1 | 119.4 | **0.788** | 124.4 | 289.1 | 0.430 |
| 08_scroll_region | 117.3 | 122.5 | **0.957** | 152.8 | 304.1 | 0.502 |
| 09_long_lines | 125.2 | 125.6 | **0.996** | 191.8 | 241.0 | 0.796 |
| 10_binary | 26.4 | 127.0 | **0.208** | 32.4 | 210.6 | 0.154 |
| **TOTAL** | **1057.2** | **1263.9** | **0.836** | **1523.7** | **2837.9** | **0.537** |

Nine of ten workloads at parity or faster; `05_unicode` is the one loss, 5%
behind. `10_binary` is a 4.8x win — worth reading with care, since the rep
plan is precalibrated and gives ours only 26 s of dwell there rather than the
>=120 s the other workloads get. Same reps on both sides, so the ratio stands,
but it is a shorter measurement than the rest.

The CPU column is the more interesting one: **1,524 s against 2,838 s** for
identical work. Note that both figures include the console host — on Windows
the pty host does a large share of the work, and attributing it to nobody
would make our efficiency look better than it is.

## DOOM-Fire — 150,000 frames, 3 reps

| | fps | cpu s | rss |
|---|---:|---:|---:|
| ours | 665.5 | 281.3 | **31 MB** |
| wt | 699.5 | 502.5 | 753 MB |
| ratio | **0.951** | **0.560** | |

The one place Windows Terminal is genuinely ahead on wall clock: 5% more
frames per second. It spends 1.79x the CPU to get them.

## bigcat — 500 MB, 3 reps (rep 1 discarded as warm-up)

| | ours s | wt s | ratio | ours cpu | wt cpu | cpu ratio |
|---|---:|---:|---:|---:|---:|---:|
| ascii | 2.27 | 2.20 | 1.030 | 2.80 | 4.46 | 0.629 |
| unicode | 5.47 | 5.08 | 1.077 | 8.34 | 11.41 | 0.731 |

Windows Terminal is 3–8% faster on a straight 500 MB cat, on 1.4–1.6x the
CPU. RSS 69 MB vs 101 MB.

## Memory

The gap is not subtle, and it grows with the length of the run:

| leg | ours | wt | |
|---|---:|---:|---:|
| suite (10 workloads, ~18 min) | 29 MB | 1,043 MB | **36x** |
| doom (3 x 150k frames) | 31 MB | 753 MB | 24x |
| bigcat (3 GB streamed) | 69 MB | 101 MB | 1.5x |

## What went wrong, and what it cost

- **The first attempt was wrecked by the harness driver, not the harness.**
  Every helper task was created with `schtasks /sc once /st 00:00`; that
  trigger stays live, so at midnight sixteen of them fired at once, spawning
  seven TerminalApp instances on top of the running suite and freezing it at
  workload 1 of 10 for 35 minutes. The round reported here is the clean
  restart at 00:35, with every stray task deleted and `/sd 01/01/2099` on the
  one that remains so it can only ever run on demand.
- **bigcat/wt failed three times in the main sitting** (`BAD GRID ''` — the
  runner never wrote its header, 80 s each) and then succeeded immediately on
  a re-run at 01:44, four minutes after the round ended, with doom/wt having
  worked fine in between. Cause not established; it was transient. The bigcat
  numbers above are therefore from a **separate sitting** from suite and doom
  — ours and wt back-to-back within it, as the protocol requires, but not
  interleaved with the rest of the round.

## Raw data

`data/` holds every result file and both orchestrator logs
(`bench-long-round1.log` is the 00:35 sitting, `bench-long.log` the bigcat
re-run). `h/` holds the harness as run, including the watchdog fix.
