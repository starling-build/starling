# Terminal vs ghostty, 2026-08-13 — the atlas-default build

The first round on the merged `cocoa-verify` pair: the atlas painter is the
default (`27c27b5`), fonts are mmap'd not copied (`0be7d02` + engine
`17e0d08c00b`), engine is host_release. Same harness as
`terminal-vs-ghostty-2026-08-11` (windowed 201x47 protocol, 3 runs each,
medians), rerun because both the renderer and the font path changed
underneath the old numbers.

## Environment

- Lenovo Slim Pro 7, AC power, quiet box.
- GNOME (ubuntu session) on Wayland; **Dell P2715Q alone at 3840x2160@30,
  scale 1** — the internal panel off for the duration. This differs from
  08-11 and it matters twice: at the laptop panel's scale-2 the logical
  desktop cannot fit ghostty's 201 columns at all (first attempt landed
  41x154 — see *What invalidated the first run*), and the 30 Hz refresh
  slows BOTH terminals' absolute walls ~45-50% against the 08-11 numbers.
  Ratios transfer; absolute walls do not.
- ours: GTK TerminalApp from `.build-gtk` (STARLING_APP_GTK=1, release,
  host_release engine), window 1624x823 → grid **47x201 verified**, cell
  exactly 8.00 px (the atlas' whole-pixel cells are visible in the solve).
- ghostty: nightly 1.3.2-dev tip build and 1.3.0 stable, request 202x50 →
  **47x202** on the suite legs (the familiar one-column drift; 202 ≥ 201 so
  nothing wraps) and **47x201 exactly** on the published legs.

## The 10-workload suite (medians of 3)

| workload | ours | ghostty nightly | ratio | ghostty 1.3.0 | ratio |
|---|---|---|---|---|---|
| 01_light_cells | 0.595 | 0.503 | 1.18x | 0.489 | 1.22x |
| 02_dense_cells | 0.251 | 0.185 | 1.36x | 0.398 | 0.63x |
| 03_sgr_fg | 0.382 | 1.039 | **0.37x** | 1.451 | 0.26x |
| 04_sgr_truecolor | 0.397 | 0.759 | **0.52x** | 1.467 | 0.27x |
| 05_unicode | 0.332 | 0.325 | 1.02x | 0.704 | 0.47x |
| 06_cursor_motion | 0.020 | 0.033 | **0.61x** | 0.046 | 0.43x |
| 07_alt_screen | 0.124 | 0.121 | 1.02x | 0.591 | 0.21x |
| 08_scroll_region | 0.490 | 0.452 | 1.08x | 0.625 | 0.78x |
| 09_long_lines | 0.136 | 0.160 | **0.85x** | 0.580 | 0.23x |
| 10_binary | 0.498 | 1.635 | **0.30x** | 1.438 | 0.35x |
| **suite wall** | **3.225** | 5.212 | **0.62x** | 7.789 | **0.41x** |

End-of-suite RSS: ours 226 MB, nightly 209 MB, 1.3.0 198 MB. The 08-11
windowed round had ours at 233 MB against the nightly's 167 — the font fix
moved us from +66 MB over ghostty to **+17 MB**, at a bigger absolute grid
of device pixels than that round rendered.

Within-round comparison against 08-11 windowed (`res-ours-drain` /
`res-ghn-new` in that round's data): ratios essentially transfer (0.59x →
0.62x nightly, 0.36x → 0.41x stable). The workload MIX moved, and that is
atlas-relevant: `light_cells`/`dense_cells` are now the only real losses
against the nightly, while the SGR and binary workloads remain 2-3x wins.

## Ghostty's published tests (150 MB cats + DOOM-Fire, medians of 3)

| test | ours | ghostty nightly | |
|---|---|---|---|
| ascii cat 150 MB | 0.878 s (cpu 1.18) | 0.833 s (cpu 1.66) | 1.05x wall, **0.71x cpu** |
| unicode cat 150 MB | 0.655 s (cpu 1.31) | 0.816 s (cpu 1.80) | **0.80x wall**, 0.73x cpu |
| DOOM-Fire, 600 frames | **1181 fps** (cpu 1.16) | 646 fps (cpu 2.05) | **1.83x fps, 0.57x cpu** |

Both sides verified `grid=47x201` in the result headers. The ascii cat
stays ghostty's by ~5% — the read(2) pty floor against their io_uring,
same as every prior round. DOOM-Fire at 1181 vs 646 fps on half the CPU is
the atlas painter's headline: the r9-era windowed numbers had ours ahead
but nowhere near 1.8x.

## Rerun on the gate-clean painter (`8f18ce5`, same day, `data-fixed/`)

The caveat below was real and then resolved: the attribute fixes
(baseline-anchored underline, nearest sampling on exact blits, the
neutral-gamma grey raster) landed as `8f18ce5` with the pixel gate green
on all 16 rows, and the whole set was rerun on the identical protocol.
What correctness cost, measured:

| | broken painter (data/) | fixed painter (data-fixed/) |
|---|---|---|
| suite wall | 3.225 s (0.62x ghn) | 3.274 s (**0.61x** ghn, 0.41x 1.3.0) |
| ascii cat | 0.878 s (1.05x) | 0.890 s (1.10x, cpu 0.74x) |
| unicode cat | 0.655 s (0.80x) | **0.611 s (0.73x, cpu 0.68x)** |
| DOOM-Fire | 1181 fps, cpu 1.16 | **1186 fps (1.87x ghn), cpu 1.17** |
| rss (suite end) | 226 MB | 227 MB |

Suite +1.5% overall, concentrated in `03_sgr_fg`/`04_sgr_truecolor`
(+6-8% — the per-frame underline scan is per-cell even when nothing is
underlined; a per-row attribute summary from the core would buy it back).
DOOM-Fire and the cats are unchanged to slightly better — the fire is all
box sprites and gained the nearest-sampling path. The headline ratios
survive correctness intact.

## Same-font round (`data-samefont/`): ghostty on Roboto Mono too

The matched-video work raised the obvious control: does ghostty's default
font flatter or hurt it? Rerun with ghostty configured (via its config
file, so calibration inherited it) to the video-matched metrics —
`font-family = Roboto Mono`, `font-size = 10.5`, `adjust-cell-height =
-8%` — which equalises the FONT and, at the tiled/calibrated grids, the
rastered pixel area per cell. Ours as control reproduced (3.219 vs
3.274 s). Ghostty, medians of 3, both grids verified:

| | ghostty default font | ghostty Roboto Mono | |
|---|---|---|---|
| suite wall | 5.335 s | 5.183 s (-2.8%) | ours 0.62x either way |
| ascii cat | 0.833 s | 0.829 s | ours 1.05x |
| unicode cat | 0.816 s | 0.815 s | ours **0.81x** |
| DOOM-Fire | 633 fps (cpu 2.05) | **701 fps** (cpu 1.89) | ours 1200 fps (cpu 1.12) → **1.71x on 59% CPU** |

The cats and the suite barely move — ghostty is parse-bound, as every
round has said. DOOM-Fire moves +11%, and that is not the typeface: the
Roboto Mono config shrinks ghostty's cell from ~10.5 px to 8.15 px, so
each fire frame rasters ~40% less area. Cell-for-cell AND pixel-for-pixel
is the fairest fire comparison yet, and it reads 1.71x at 0.59x CPU.

## The original caveat (now historical): the atlas shipped with broken attributes

`test/glyph-pixels.py` on the `data/` build FAILED its four attribute rows
under the default atlas (reverse video and all three underline cases drew
no rule inside the scanned band; the glyph rows all passed). The `data/`
numbers price that incomplete painter; `data-fixed/` is the honest set.

## What invalidated the first run

The first suite pass came back with ghostty at **41x154** — at the
laptop-panel scale-2 desktop, 201 ghostty columns (~10.5 px cells) need
more logical width than exists, so the window clamped and the corpus
wrapped: ghostty read 1.6x slower than its real speed and the "win"
was fake. The meta grid check caught it, again. `calibrate.sh` /
`calib-ghostty.sh` were then re-run on the scale-1 config and both sides
re-verified before anything above was recorded.
