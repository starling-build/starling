# Terminal vs ghostty, 2026-08-13 — the atlas-default build, matched fonts

The round on the merged `cocoa-verify` pair: the atlas painter is the
default (`27c27b5`) and gate-clean (`8f18ce5` — all 16 pixel-gate rows
pass), fonts are mmap'd not copied (`0be7d02` + engine `17e0d08c00b`),
engine is host_release. Same harness as `terminal-vs-ghostty-2026-08-11`
(windowed 201x47 protocol, 3 runs each, medians), with one addition over
every earlier round: **ghostty runs the same font at the same metrics as
ours** — `font-family = Roboto Mono`, `font-size = 10.5`,
`adjust-cell-height = -8%` via its config file, so the calibration
probes inherit it. That equalises the typeface and, cell-for-cell, the
rastered pixel area. Data in `data-samefont/`.

Two earlier same-day sets (the pre-fix painter, and ghostty on its
default font) were superseded by this one and removed; git history holds
them. What they established survives as two sentences: the attribute
fixes cost ~1.5% of suite wall (in the SGR workloads — the underline
pass scans per-cell even when nothing is underlined), and ghostty's suite
and cat numbers move under 3% between its default font and Roboto Mono —
it is parse-bound, the typeface is irrelevant to it.

## Environment

- Lenovo Slim Pro 7, AC power, quiet box.
- GNOME (ubuntu session) on Wayland; **Dell P2715Q alone at 3840x2160@30,
  scale 1** — the internal panel off for the duration. The 30 Hz refresh
  slows BOTH terminals' absolute walls ~45-50% against the 08-11 rounds:
  ratios transfer across rounds, absolute walls do not.
- ours: GTK TerminalApp from `.build-gtk` (STARLING_APP_GTK=1, release,
  host_release engine), window 1624x823 → grid **47x201 verified**, cell
  exactly 8.00 px (the atlas' whole-pixel cells are visible in the solve).
- ghostty: nightly 1.3.2-dev tip build and 1.3.0-dev, on Roboto Mono at
  the matched metrics (cell 8.15 px), request 202x50 → **47x202** on the
  suite legs (the familiar one-column drift; 202 ≥ 201 so nothing wraps)
  and **47x201 exactly** on the published legs.

## The 10-workload suite (medians of 3)

| workload | ours | ghostty nightly | ratio | ghostty 1.3.0-dev | ratio |
|---|---|---|---|---|---|
| 01_light_cells | 0.586 | 0.497 | 1.18x | 0.478 | 1.23x |
| 02_dense_cells | 0.249 | 0.173 | 1.44x | 0.391 | 0.64x |
| 03_sgr_fg | 0.387 | 1.039 | **0.37x** | 1.432 | 0.27x |
| 04_sgr_truecolor | 0.390 | 0.761 | **0.51x** | 1.464 | 0.27x |
| 05_unicode | 0.334 | 0.316 | 1.06x | 0.744 | 0.45x |
| 06_cursor_motion | 0.022 | 0.034 | **0.65x** | 0.047 | 0.47x |
| 07_alt_screen | 0.117 | 0.135 | **0.87x** | 0.614 | 0.19x |
| 08_scroll_region | 0.510 | 0.457 | 1.12x | 0.617 | 0.83x |
| 09_long_lines | 0.145 | 0.147 | 0.99x | 0.577 | 0.25x |
| 10_binary | 0.479 | 1.624 | **0.29x** | 1.411 | 0.34x |
| **suite wall** | **3.219** | 5.183 | **0.62x** | 7.775 | **0.41x** |

End-of-suite RSS: ours 226 MB, nightly 209 MB, 1.3.0-dev 198 MB. The
08-11 windowed round had ours at +66 MB over the nightly; the font-copy
fix (`0be7d02`) brought it to **+17 MB**.

## Ghostty's published tests (150 MB cats + DOOM-Fire, medians of 3)

| test | ours | ghostty nightly | |
|---|---|---|---|
| ascii cat 150 MB | 0.869 s (cpu 1.16) | 0.829 s (cpu 1.68) | 1.05x wall, **0.69x cpu** |
| unicode cat 150 MB | 0.659 s (cpu 1.32) | 0.815 s (cpu 1.84) | **0.81x wall**, 0.72x cpu |
| DOOM-Fire, 600 frames | **1200 fps** (cpu 1.12) | 701 fps (cpu 1.89) | **1.71x fps, 0.59x cpu** |

Both sides verified `grid=47x201` in the result headers. The ascii cat
stays ghostty's by ~5% — the read(2) pty floor against their io_uring,
same as every prior round. The fire number deserves its qualifier: with
the matched config ghostty's cell shrinks from ~10.5 px to 8.15 px, so
each fire frame rasters ~40% less area than on its default font — this
is the fairest fire comparison of the day (equal font, equal grid, equal
pixels per cell) and it reads **1.71x at 0.59x CPU**.

## The filmed head-to-head (same day, not a measurement)

Both terminals tiled to halves of the 4K screen on GNOME, launched into a
synchronized script (banner → wait for a trigger file → 150 MB ascii cat →
150 MB unicode cat → DOOM-Fire 3000 frames), recorded with GNOME's
screencast (hardware vah264enc). Typography matched end to end: same
Roboto Mono, same rendered size, same 233-column width, row grids aligned
to the pixel — the DOOM test cards' quote bars landed at identical y in
both panes, and the simultaneous start even seeds both DOOM-Fires the
same random quote. On-screen verdicts across takes: ours 802-842 fps vs
ghostty 497-600. These are a RACE on shared cores, not a benchmark — the
`data-samefont/` numbers are the citable ones.

The matching recipe, with its traps:

- Install the sdk's RobotoMono TTFs system-wide (ghostty resolves through
  fontconfig, not paths).
- Ghostty's `--font-size` is NOT 96 dpi points here — measured ~1.65
  px/pt, and the em quantizes in ~2 px steps. Solve empirically with a
  clamp probe: request `--window-width=600` (impossible), read `stty
  size`, divide screen width by columns. 10.5 pt lands the 8.15 px cell
  that gives the same column count as our 8.00 px cell in a half-screen.
- Row height needs `adjust-cell-height`; it quantizes to WHOLE pixels and
  silently ignores fractional values. `-8%` (17.7 px vs our 17.2) is the
  closest quantum; the differing title-bar heights absorbed the residual.
- GNOME's Screencast D-Bus service aborts the moment its calling bus
  connection drops — `gdbus call` produces a 48-byte file ("Sender has
  vanished"). Hold the connection open for the recording's lifetime.

One sighting from a discarded take, worth remembering: the GTK-hosted
TerminalApp ran its whole workload at full speed (fps file written,
timings normal) while its WINDOW stayed frozen on a stale frame for ~6 s
through the cat phase, then snapped forward at the test card. Repaint
stall in the GTK host presentation path, once in ~six runs; the DRM path
never showed it.

## Provenance — exactly what was measured

- **ours**: `cocoa-verify` at `8f18ce5` (gate-clean atlas painter),
  Swift release build against the engine's host_release at
  `0da247b490c` on the paired engine branch.
- **ghostty nightly** (`/var/tmp/ghostty-nightly`): `1.3.2-dev+0000000`,
  channel tip, built from the source tarball fetched 2026-08-11
  (`+0000000` = tarball build, no commit hash embedded; unpacked at
  `/var/tmp/ghostty-src`). Build config from `ghostty --version`:
  **Zig 0.16.0**, ReleaseFast, GTK 4.22.4 runtime, fontconfig/freetype,
  OpenGL renderer, libxev io_uring.
- **ghostty "stable"** (`/usr/bin/ghostty`): `1.3.0-dev+0000000`, also a
  tarball tip build, **Zig 0.15.2**, ReleaseFast — earlier rounds called
  this leg "1.3.0 stable"; strictly it is a 1.3.0-dev source build.
- **DOOM-Fire**: `github.com/const-void/DOOM-fire-zig` at `eb0631b`
  (2025-08-20) plus the harness's 19-line patch to `src/main.zig` (the
  `BENCH` markers: stop after `DOOMFIRE_FRAMES`, report fps on stderr —
  documented in `doomfire.sh`), built with **Zig 0.14** (0.16 does not
  build its `build.zig`; both toolchains live under `/var/tmp`).

## What invalidated a first run — the grid trap, again

The first suite pass of the day came back with ghostty at **41x154**: at
a scale-2 desktop, 201 ghostty columns need more logical width than
exists, so the window clamped and the corpus wrapped — ghostty read 1.6x
slower than its real speed, indistinguishable from a win for us until the
meta grid check caught it. Everything above was taken on the scale-1
config with both grids re-verified. The check is not optional.
