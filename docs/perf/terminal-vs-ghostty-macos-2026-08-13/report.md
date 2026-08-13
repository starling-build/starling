# Terminal vs Ghostty on macOS — the full rerun after the core and painter work

2026-08-13, same MacBook Pro as the 08-12 round, macOS 26.5, **AC power**,
quiet box (the iOS simulator that was running earlier was stopped first).
Both terminals as ordinary windows in the same session, every suite and cat
run verified at **201x47** — one ghostty bigcat launch came up 17x49 (the
documented intermittent) and was discarded and rerun. Measured builds:

    TerminalApp      main at 04c5b11, Cocoa host, release, engine 3fdc652
                     (host_debug_arm64). Text path unless marked ATLAS.
    ghostty          1.3.2-main+51ed437cd, tip build, ReleaseFast, Metal —
                     the same binary the 08-12 round measured.

The 08-12 round ended 1.35x of ghostty's wall. Since then mainline gained the
sliding grid window, the width cache, the inline reader, and the atlas
painter. This is the round that records the turnaround.

## The 10-workload suite: 0.72x of ghostty's wall, on 45% of its CPU

Best-of-3 per workload (min wall), corpus at 201x47, raw in `data/res-*`:

| workload | ours | ghostty | ours MB/s | gh MB/s | ratio |
|---|---|---|---|---|---|
| 10_binary | 0.109 | 0.552 | 275.2 | 54.3 | **0.20x** |
| 03_sgr_fg | 0.469 | 0.682 | 154.9 | 106.5 | **0.69x** |
| 01_light_cells | 0.112 | 0.153 | 97.2 | 71.2 | **0.73x** |
| 04_sgr_truecolor | 0.652 | 0.802 | 172.7 | 140.4 | **0.81x** |
| 08_scroll_region | 0.195 | 0.239 | 224.0 | 182.8 | **0.82x** |
| 02_dense_cells | 0.131 | 0.157 | 231.3 | 193.0 | **0.83x** |
| 09_long_lines | 0.174 | 0.209 | 231.2 | 192.5 | **0.83x** |
| 06_cursor_motion | 0.033 | 0.039 | 112.4 | 95.1 | **0.85x** |
| 05_unicode | 0.346 | 0.333 | 169.9 | 176.6 | 1.04x |
| 07_alt_screen | 0.214 | 0.204 | 183.0 | 192.0 | 1.05x |
| **total** | **2.435** | **3.370** | | | **0.72x** |

| | ours | ghostty |
|---|---|---|
| total CPU (best-of-3) | **3.92 s** | 8.70 s |
| RSS after the run | 195 MB | 130 MB |

Eight of ten outright; the two losses are 4-5%, and 07_alt_screen — the 08-12
round's 1.86x — is now even. Wall is down and CPU is less than half of
ghostty's, but RSS remains 1.5x theirs, unchanged in shape from 08-12.

## Ghostty's published tests: three of three

`cat` of the 150 MB corpora (best-of-3, `data/bigcat-*`), and DOOM-Fire-Zig:

| test | ours | ghostty | ratio | CPU ours/gh |
|---|---|---|---|---|
| ascii cat 150 MB | 0.658 s | 0.773 s | **0.85x** | 0.63 / 1.76 s (36%) |
| unicode cat 150 MB | 0.899 s | 0.936 s | **0.96x** | 1.58 / 2.43 s (65%) |
| DOOM-Fire (Text path) | ~970 fps | ~960 fps | ~1.01x | 1.39 / ~1.80 s (77%) |
| DOOM-Fire (ATLAS=1) | ~1030 fps | ~960 fps | **~1.07x** | 0.90 / ~1.80 s (50%) |

## DOOM-Fire in full, because ghostty was bimodal

600 frames x 3 reps per launch. Our numbers are stable across five launches;
ghostty's CPU came up in two distinct modes with nothing changed between
launches — same binary, same grid (verified 47x201 every time), same power:

    ghostty, per launch (mean fps / mean cpu_s):
      763 / 2.02    756 / 2.03    1029 / 1.00 (outlier)    965 / 1.79    954 / 1.80
    ours Text, per launch:
      981 / 1.39    975 / 1.37    956 / 1.41
    ours ATLAS=1, per launch:
      981 / 0.88    982 / 0.87    1070 / 0.90    1095 / 0.92

Treating ghostty's typical launch as ~960 fps / ~1.8 CPU-s: the atlas painter
runs at or above ghostty's frame rate on **half its CPU**, and even the Text
path matches its frame rate on ~77%. The single 1.00-CPU ghostty launch is
real (raw in `data/doom-gh-r3` numbers within `doom-gh-r5.txt`'s
predecessors) but did not recur in two follow-up launches bracketing an ours
run; best-vs-best still favours the atlas (1126 vs 1056 fps).

The ATLAS arm paints 196 columns to everyone else's 201 (the device-pixel
snap costs 2.5% of columns); the Text-path arm at the identical grid carries
the comparison unaided.

## Method notes

- All arms interleaved in this one sitting; nothing compared against another
  day's numbers. The earlier-in-the-day battery measurements of the same
  binaries read 5-10% slower on every arm — cross-condition drift remains
  larger than most effects, as the 08-12 round also found.
- One ghostty bigcat launch at 17x49 was discarded (`grid=` line checked on
  every run, per the harness notes). Its numbers were within 1% of the
  correct-grid rerun on this content, but the discard rule stands.
- Ghostty DOOM CPU bimodality is unexplained; we report the mode, keep the
  outlier in the data, and note that it changes no ordering.
