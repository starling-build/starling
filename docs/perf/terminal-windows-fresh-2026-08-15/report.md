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

## The filmed head-to-head (same box, ~10 s per test — a race, not a benchmark)

The Windows counterpart of the Linux and macOS races, same three tests and
same shape: both terminals tiled to halves of the 1280x800 screen, both
verified **43x76**, tests sized from an untimed calibration run so each lasts
about ten seconds on our side — 1.5 GB ascii cat, 1 GB unicode cat, DOOM-Fire
9,600 frames — started together off a shared `GO` file, each printing its own
verdict card at the end.

Matching the grids needed the Windows Terminal equivalent of ghostty's
`window-padding-x`: its cell is relatively wider than ours, so no single font
size hits both 43 rows and 76 columns in the same 640x800 frame. WT runs at
`fontSize 10` with `padding "5,49,5,49"` — small enough to overshoot both
axes, then padded back down to the exact grid.

**Windows Terminal wins this one.**

| | ascii cat | unicode cat | DOOM-Fire | total |
|---|---:|---:|---:|---:|
| ours | 8.96 s | 12.76 s | 987 fps | **37.9 s** |
| Windows Terminal | 8.37 s | 11.51 s | 1,090 fps | **35.1 s** |

Three filmed runs agree: 36.6/41.8, 35.8/38.5, 35.1/37.9 — WT ahead by
2.7-5.2 s every time. This is not in tension with the suite result above, it
is the same result seen from its worst angle: the race is made of exactly the
three tests Windows Terminal already won in the measured round (bigcat ascii
and unicode, DOOM-Fire), and none of the ten suite workloads where we win.
The narrow half-screen grid widens its margin further — 76 columns costs us
more than it costs WT, our ascii throughput falling from 215 MB/s at 39x120
to ~170 MB/s at 43x76.

Two honest readings, then: on a screenful of terminal work at steady state we
finish in 0.84x the time on 0.54x the CPU; on a three-test sprint of cats and
fire, Windows Terminal is 8% faster. Video: `ui/video/terminal-race-windows.mp4`
(not linked from the site). Harness in `film/`.

## Why we lost the cats — a profile, and half the gap closed

Process-level profile of the 500 MB cats (CPU snapshotted either side of each
rep, terminal + console host + writer), then an A/B on the two candidate
causes. The decisive number is that **we were using ~half Windows Terminal's
CPU and still finishing later** — so the deficit was never throughput.

**The console host is the pace-setter.** ConPTY's `OpenConsole` is a
single-threaded stage that needs a fixed ~1.9 CPU-s per 500 MB of ascii and
~4.8 for unicode. The cat cannot finish faster than that, and the only way to
lose is to leave it idle — which happens whenever our ring is full and its
write blocks.

| | wall | host occupancy | our CPU |
|---|---:|---:|---:|
| ours, 512 KB ring | 2.45 / 5.68 s | 0.80-0.88 cores | 0.54-0.87 |
| ours, no repaint | 2.24-2.30 s (ascii) | 0.87-0.88 | 0.35 |
| **ours, 2 MB ring** | **2.31 / 5.27 s** | **0.87-0.92** | 0.57-0.84 |
| Windows Terminal | 2.26 / 5.25 s | 0.86-0.93 | 1.08-1.29 |

Two separate causes, one per corpus:

- **unicode was the ring.** 8x64 KB is 512 KB, which at 220 MB/s is **2.3 ms**
  of slack — any parse or repaint hiccup longer than that stalls the host.
  Raising it to 2 MB takes unicode from 5.68 s to 5.27 s, a dead heat with
  Windows Terminal's 5.25. 8 MB buys nothing further: past the knee the host
  is already saturated. Now the default (`Pty.swift`), overridable with
  `STARLING_TERM_SLOT_KB` / `STARLING_TERM_SLOTS`.
- **ascii is the repaint path.** Suppressing repaints
  (`STARLING_BENCH_NOREPAINT=1`) lands at 2.24-2.30 s against WT's 2.26 —
  i.e. the whole remaining ascii gap is render work stealing drain time. The
  ring fix takes it from 2.45 to 2.31; the last ~2% is still there.

### Spending CPU to close the rest: ported, measured, and it does nothing

The floor is the host's own CPU — ~1.9 s ascii, ~4.8 s unicode — so perfect
draining would finish around 1.95 / 4.85 s, ahead of Windows Terminal on
both. Getting there means driving host occupancy from ~0.9 to 1.0, which is a
latency problem, and Darwin already solves exactly that by spending CPU:
`_startReaderPaced` busy-waits ~1 us before re-arming the read, because an
eager re-arm catches the pty queue empty and pays a writer-wake round trip per
kilobyte. It is worth 29% on the unicode cat there.

So it was ported — `starling_conpty_pace` (QueryPerformanceCounter busy-wait;
Windows will not sleep for a microsecond) plus a pace in the ConPTY reader,
both on a dry pipe and before re-arming. Alternating A/B on the cats, six to
eight reps a side:

| | ascii | unicode |
|---|---:|---:|
| pace off | 2.31 s | 5.41 s |
| pace 1 us | 2.35 s | 5.36 s |

Both differences sit inside a run-to-run spread of 2.25-2.46 and 5.16-5.62.
**It buys nothing here**, and the reason is in `STARLING_PTY_BYTES`: ConPTY
already hands us **~45 KB per read** (61k reads for 2.7 GB) because the reader
coalesces on `PeekNamedPipe`, where Darwin's pty returns ~1 KB no matter the
buffer. The empty-queue round trip the pace exists to avoid is not happening,
so all a busy-wait buys is a spinning core. Shipped **off**, with the knob and
this measurement kept in place so the experiment is not repeated.

(One run showed unicode at 10.7 s with the pace on — twice the host CPU too.
It did not reproduce in eight further runs and was contamination from a
leftover process. Recorded because a single spectacular number is exactly the
kind of thing that gets believed.)

### The whole round, re-run on the shipping build

`data/ring-suite/` is a complete round on the 2 MB ring — suite, cats and
DOOM-Fire, each leg's pair back to back — and it is the one the site quotes.

| | ours | Windows Terminal | |
|---|---:|---:|---|
| ten workloads, wall | 1,064 s | 1,241 s | **1.17x** |
| ten workloads, CPU | 1,566 s | 2,729 s | **1.74x** |
| resident set after them | **32 MB** | 1,035 MB | 32x |
| ascii cat, 500 MB | 2.31 s | 2.25 s | 0.97x |
| unicode cat, 500 MB | 5.30 s | 5.06 s | 0.95x |
| DOOM-Fire, 150k frames | 733 fps | 738 fps | 0.99x |

DOOM-Fire has become a dead heat — 733 against 738 fps, from 0.95x in the
first round — on 0.60x the CPU (276 s against 464 s). The two cats stay 3-5%
behind, which is the repaint path noted above and the only place on this
platform where Windows Terminal is still ahead.

### Where it leaves us

Same-session baseline, 2 MB ring, pace off:

| | ours | Windows Terminal | before |
|---|---:|---:|---|
| ascii cat | 2.305 s | 2.290 s | 2.45 vs 2.26 |
| unicode cat | 5.405 s | 5.192 s | 5.68 vs 5.25 |

Ascii is a dead heat; unicode's deficit halves to 4%. Our CPU is 1.6-2.0 cores
against Windows Terminal's 2.2-2.4 throughout. The remaining unicode gap and
the last of ascii are the repaint path, which `NOREPAINT` shows is worth
~0.5-0.7 CPU-s per 500 MB of drain time — that is the next thing to look at,
not the reader.

### The suite, re-run against the ring change

The caveat above is now closed: both suite legs re-run back to back on the
2 MB ring (`data/ring-suite/`).

| | ours before | ours after | |
|---|---:|---:|---|
| total, ten workloads | 1057.2 s | 1064.2 s | +0.7%, inside drift |
| 05_unicode | 120.2 s | **113.7 s** | **-5.4%** |
| vs Windows Terminal | 0.836x wall / 0.537x CPU | **0.858x / 0.574x** | |

**No regression, and the suite's one losing workload is gone.** `05_unicode`
was the only outright loss in the first round (0.953x) and is now level
(1.011x) — the same path the ring fixed on the unicode cat. Everything else
moves ~1%, which is what this box does between sittings.

Which is the warning attached to these numbers: Windows Terminal's own legs
moved up to 12% between the two rounds (`03_sgr_fg` -12.7%, `06_cursor_motion`
-11.2%, `08_scroll_region` +8.5%) on identical work. **Only within-session
ratios are trustworthy here.** `07_alt_screen` reads +9.1% for us and +7.6%
for Windows Terminal, so it is drift rather than a regression — but it is
exactly the shape a real regression would take, which is why the pair is run
back to back.

## Raw data

`data/` holds every result file and both orchestrator logs
(`bench-long-round1.log` is the 00:35 sitting, `bench-long.log` the bigcat
re-run). `h/` holds the harness as run, including the watchdog fix.
