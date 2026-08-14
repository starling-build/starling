# Terminal vs ghostty on macOS — matched fonts, release engine

2026-08-13 evening, the macOS counterpart of
`terminal-vs-ghostty-2026-08-13-atlas` (the Linux GNOME matched-font round):
ghostty runs **the same Roboto Mono at the same cell metrics as ours**, so
cell-for-cell the two terminals raster the same pixel area. Same MacBook Pro
as the morning round, macOS 26.5, AC power, quiet box, both terminals
ordinary windows on the internal Retina panel (3456x2234, scale 2). Every
counted run verified at **47x201** on both sides.

Two things are new against the morning round
(`terminal-vs-ghostty-macos-2026-08-13`) besides the font matching:

- **Ours is on a true release engine for the first time on macOS.** All
  prior macOS rounds linked `host_debug_arm64` — optimized C++
  (`is_debug=false`) but `flutter_runtime_mode=debug`. This round generated
  and built `host_release_arm64` (`--runtime-mode release`, LTO,
  `is_official_build`) and dyld-verified the binary loads it.
- **The suite legs run the atlas painter**, now the mainline default; the
  morning suite was the Text path.

So ours-vs-morning deltas fold in release engine + atlas + the day's pulled
commits; the ghostty binary is byte-identical to the morning round's.

## The font matching, and what it took on macOS

Ours: bundled Roboto Mono 13 (logical px), atlas cell snapped to
**8.00 logical = 16 device px** wide, 16.667 logical = 33.33 device tall;
window 1624x817 logical → 47x201 exactly.

Ghostty (`~/.config/ghostty/config`, inherited by every leg):

    font-family = Roboto Mono
    font-size = 13.33
    adjust-cell-height = -5%
    window-save-state = never

- Roboto Mono Regular+Bold from `sdk/Sources/Flutter/Terminal/Fonts/`
  installed to `~/Library/Fonts`; CoreText resolves them immediately.
- Unlike Linux (where px/pt had to be solved empirically at ~1.65), macOS is
  exactly 2 device px per point: 13.33 pt x 0.6001 em x 2 = **16.000 device
  px** advance, confirmed on the first probe.
- `adjust-cell-height` quantizes to whole device pixels: -5% and -6% both
  land 33; -5% is the closest quantum to our 33.33. Residual: ghostty
  rasters 16x33 to our 16x33.33, ~1% less area per cell (the Linux round
  carried ~2% the other way).
- Cell metrics were measured from *inside* each window: XTWINOPS `CSI 14 t`
  reports the text area in device pixels; divided by `stty size` this gives
  the exact cell, no clamp-probe arithmetic. Ghostty answers it; this is
  cleaner than the Linux round's method.
- **macOS saved application state silently overrides ghostty's
  `--window-width/--window-height`** — every launch came up at the previous
  session's size regardless of the request. Deleting
  `~/Library/Saved Application State/com.mitchellh.ghostty.savedState` and
  setting `window-save-state = never` fixed the *persistent* override. It
  did **not** fix the known intermittent 17x49 launch: three consecutive
  bigcat legs came up 17x49 with save-state off (the harness guard discarded
  and retried; the fourth launch was clean). The grid check stays mandatory.

## The 10-workload suite (medians of 3)

| workload | ours | ghostty | ratio |
|---|---|---|---|
| 01_light_cells | 0.111 | 0.149 | **0.74x** |
| 02_dense_cells | 0.129 | 0.145 | **0.89x** |
| 03_sgr_fg | 0.438 | 0.642 | **0.68x** |
| 04_sgr_truecolor | 0.619 | 0.713 | **0.87x** |
| 05_unicode | 0.323 | 0.305 | 1.06x |
| 06_cursor_motion | 0.031 | 0.037 | **0.84x** |
| 07_alt_screen | 0.207 | 0.180 | 1.15x |
| 08_scroll_region | 0.181 | 0.217 | **0.83x** |
| 09_long_lines | 0.163 | 0.181 | **0.90x** |
| 10_binary | 0.189 | 0.545 | **0.35x** |
| **suite wall** | **2.391** | **3.114** | **0.77x** |

| | ours | ghostty |
|---|---|---|
| suite CPU (sum of medians) | **2.38 s** | 8.02 s (0.30x) |
| RSS after suite | **121 MB** | 127 MB |
| RSS after 2x150 MB cats | **120 MB** | 171 MB |

(Best-of-3 gives the same ratio: 2.366 vs 3.079 = 0.77x — comparable to the
morning report's min-wall statistic.)

Eight of ten. The two losses are the same pair as every recent round
(05_unicode, 07_alt_screen), both within 6-15%. And **RSS, the one axis we
had always lost, flipped**: the morning round read 195 MB to ghostty's 130;
the release engine plus the font-mmap fix put us at 120-121 MB, under
ghostty on the suite and 30% under it after the cats.

## Ghostty's published tests (medians of 3)

| test | ours | ghostty | | CPU ours/gh |
|---|---|---|---|---|
| ascii cat 150 MB | 0.611 s | 0.692 s | **0.88x** | 0.57 / 1.59 (36%) |
| unicode cat 150 MB | 0.806 s | 0.826 s | **0.98x** | 1.26 / 2.21 (57%) |
| DOOM-Fire, 600 frames | **~1025 fps** | ~845 fps | **1.21x** | 0.85 / 1.90 (45%) |

DOOM-Fire in full, because ghostty's DOOM CPU was bimodal in the morning
round — today it was not. Per launch (median fps / median cpu_s of 3 reps):

    ghostty: 850/1.89    831/1.92    842/1.88     (9 reps, 806-894 band)
    ours:    1029/0.86   1014/0.83                (6 reps, 1008-1038 band)

Every launch verified `grid=47x201` in both header and `grid_after`.

### Frame count matters: 600-frame runs understate ghostty ~12%

Rerun the same night (same grid, same configs, verified 47x201) at **6000
frames** per rep, two launches interleaved per side, after the side-by-side
film showed ghostty's long contended runs beating its own short solo ones:

    ghostty: 896/975/965 then 943/962/963 fps, ~16.1 cpu_s  → ~960 typical
    ours:    1107/1110/405* then 1057/1059/1059 fps, ~6.3 cpu_s → ~1058

Ghostty amortizes warm-up (renderer pipeline, atlas population, the fire's
own ramp) over the longer run and lands ~960 where 600 frames read ~845;
ours moves 1025 → ~1058. **The durable fire numbers are ours ~1058 vs
ghostty ~960 — 1.10x fps at 0.39x CPU** — and the 600-frame table above
carries the warm-up penalty in ghostty's column. (*) One of our six reps
stalled to 405 fps / 14.8 cpu_s and recovered; once, launch-local, the
other five reps within 0.4%. Recorded as a sighting beside the Linux
round's GTK repaint stall; second launches raw in `data/doom-6000-*.txt`
(the first launches' files were overwritten in place; their numbers are
the ones above).

## Ghostty is font-sensitive on macOS

The Linux round found ghostty parse-bound — under 3% between its default
font and Roboto Mono. The macOS build is not (same binary, same grid,
best-of-3 vs best-of-3 against the morning round on its default font):

- ascii cat 0.773 → 0.691 (~10% faster on the smaller matched cell)
- unicode cat 0.936 → 0.822 (~12% faster)
- DOOM-Fire ~960 → ~840 fps (~12% *slower*)

The cats got faster and the fire got slower on the same cell change, so
this is not simple raster-area scaling; we record the observation and move
on. Fairness of this round is unaffected — both sides raster the same font
at the same metrics.

## Provenance

- **ours**: starling `main` at `5156a9c`, TerminalApp Cocoa host, Swift
  release build, `STARLING_TERMINAL_SINGLE=1`, atlas painter (default).
  Engine: starling-engine `starling` at `ea78543`, `host_release_arm64`
  generated this round (`gn --mac-cpu arm64 --runtime-mode release`, LTO),
  runtime load of the release `FlutterMacOS.framework` and
  `libswift_bridge.dylib` verified with `DYLD_PRINT_LIBRARIES`. (The
  TerminalApp link also carries a stale `host_debug_arm64` rpath from
  SwiftPM's manifest cache; it is ordered after the release dir and loses.)
- **ghostty**: `1.3.2-main+51ed437cd`, channel tip,
  `~/dev/ghostty-tip/Ghostty.app`, Zig 0.16.0, ReleaseFast, CoreText,
  Metal renderer, libxev kqueue — the same binary as the 08-12 and morning
  08-13 rounds.
- **DOOM-Fire**: the Zig 0.16 port of `DOOM-fire-zig` with the BENCH patch,
  `~/dev/doomfire-bench/zig-out/bin/DOOM-fire` (upstream pins 0.14, which
  cannot link the macOS 26 SDK).
- Harness: `bench.sh` (this dir, from the morning round) and `published.sh`
  (from the 08-12 round), `RUNS=3`/`REPS=3`, `FRAMES=600`. Raw data in
  `data/`, including the extra DOOM launches
  (`doom-gh-launch{2,3}.txt`, `doom-ours-launch2.txt`).
