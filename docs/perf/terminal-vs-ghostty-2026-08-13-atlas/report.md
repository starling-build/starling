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

## Caveat: the atlas ships with broken attributes

`test/glyph-pixels.py` on this exact build FAILS its four attribute rows
under the default atlas (reverse video and all three underline cases draw
no rule; the glyph rows all pass). These numbers therefore price a painter
that is not yet drawing underline/reverse — closing that gap will add some
cost to attribute-heavy content. The suite's SGR workloads exercise color,
not underline/reverse, so the wins above should survive, but re-run this
round when the attribute half lands.

## What invalidated the first run

The first suite pass came back with ghostty at **41x154** — at the
laptop-panel scale-2 desktop, 201 ghostty columns (~10.5 px cells) need
more logical width than exists, so the window clamped and the corpus
wrapped: ghostty read 1.6x slower than its real speed and the "win"
was fake. The meta grid check caught it, again. `calibrate.sh` /
`calib-ghostty.sh` were then re-run on the scale-1 config and both sides
re-verified before anything above was recorded.
