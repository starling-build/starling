# The post-upgrade rerun — macOS 26.6.1 changes nothing

A rerun of [the 08-14 long round](../terminal-vs-ghostty-macos-2026-08-14-long/)
after the machine moved to **macOS 26.6.1 (25G76)**, same binaries on both
sides: ours at `bbe93b8` (paced reader + atlas defaults, release build against
`host_release_arm64`, dyld-verified), ghostty tip `1.3.2-main+f81dcadc8`,
matched Roboto Mono, all grids 47x201, every leg first-launch clean (the
watchdog never fired). Full environment notes in `meta.txt`.

**Every conclusion of the pre-upgrade round stands.** Our side is flat to
within run noise on all thirteen measurements; ghostty picked up a few percent
on the suite and ~4% on DOOM fps — inside the ~10% cross-session drift band,
and not enough to move any verdict. Ten of ten workloads still at or ahead,
suite 761 vs 974 s (**0.78x**) on **0.44x CPU**, RSS 130 vs 155 MB.

## The suite at steady state (wall s, >= 2 min per workload)

| workload | ours | ghostty | ratio | pre-upgrade |
|---|---|---|---|---|
| 01_light_cells | 53.9 | 96.9 | **0.56x** | 0.55x |
| 02_dense_cells | 92.0 | 96.7 | **0.95x** | 0.91x |
| 03_sgr_fg | 76.9 | 112.4 | **0.68x** | 0.69x |
| 04_sgr_truecolor | 81.1 | 106.5 | **0.76x** | 0.76x |
| 05_unicode | 81.9 | 98.3 | **0.83x** | 0.79x |
| 06_cursor_motion | 70.4 | 71.2 | **0.99x** | 0.96x |
| 07_alt_screen | 88.8 | 88.4 | **1.00x** | 1.00x |
| 08_scroll_region | 90.3 | 96.6 | **0.94x** | 0.94x |
| 09_long_lines | 93.7 | 97.3 | **0.96x** | 0.96x |
| 10_binary | 31.8 | 110.1 | **0.29x** | 0.29x |
| **total** | **760.8** | **974.2** | **0.78x** | 0.77x |
| cpu total | 1081.0 | 2436.0 | **0.44x** | 0.44x |
| rss_kb | 129984 | 154960 | | 136256 / 155232 |

Ours moved -1.3% total (761 vs 771), ghostty -2.6% (974 vs 1000) — both the
right side of zero, both within drift. 05_unicode is the largest single move
(ghostty 103.9 -> 98.3 s); the ratio is still a clear win where it was a
1.15x loss before the width cache.

## 500 MB cats (mean of 3)

| corpus | ours | ghostty | ratio | pre-upgrade |
|---|---|---|---|---|
| ascii_500mb | 1.818 s | 2.010 s | **0.90x** | 0.90x |
| unicode_500mb | 1.761 s | 2.449 s | **0.72x** | 0.70x |

## DOOM-Fire at 150 000 frames (3 reps per side, all 47x201)

| | fps (3 reps) | mean | cpu_s/rep |
|---|---|---|---|
| ours | 1118.4 / 1111.6 / 1127.2 | **1119.1** | ~213.0 |
| ghostty | 1064.6 / 1073.7 / 1073.9 | **1070.7** | ~370.3 |

**1.05x fps at 0.57x CPU** (pre-upgrade 1.09x at 0.57x). The whole change is
on ghostty's side — 1030 -> 1071 fps mean; ours is a statistical replay
(1121.0 pre). No rep-3 stall: the in-process `beginActivity(.latencyCritical)`
assertion survives 26.6.1, and so does ghostty's `NSAppSleepDisabled` defense
— both onset probes ran flat (ours 1.36 s/block through 54.5 s, ghostty
2.56 s/block through 51.3 s; see `meta.txt`).

## The film

`starling-vs-ghostty-postupgrade-demo.mp4` (46 s): the two side by side on
this OS — 500 MB ascii cat, 500 MB unicode cat, DOOM-Fire 15 000 frames,
matched Roboto Mono, both grids 106x57, synchronized start. The simultaneous
run is a demo, not a benchmark (both sides contend for the same cores and
converge to a tie — cards read 4.51/4.66/19.7 s vs 4.36/4.59/19.6 s); the
solo interleaved legs above are the record. Filmed with the checkpoint's
`demo-run.sh` recipe; two new 26.6.1 filming traps (the capture
re-authorization dialog, and the cursor it strands mid-frame) are recorded
in the side-by-side-demo-filming memory.

## What the upgrade actually broke (environment, not terminals)

- `/var/tmp/bench` was wiped — restored from
  `~/dev/starling-bench-checkpoint-20260814/` per its README. The checkpoint
  was missing `doomfire-mac.sh` (committed here now, beside the orchestrator);
  it was reconstructed from the Linux `doomfire.sh` and validated on a
  600-frame leg before the round.
- The upgrade **re-armed the idle screensaver** (`idleTime` 300): the Tahoe
  aerial was animating full-screen over the idle desktop
  (WallpaperAerialsExtension + VTDecoder decoding continuously, WindowServer
  ~20%), and it does not yield to `caffeinate -u` once engaged — it took a
  synthetic Ctrl keystroke via CGEvent to dismiss, and
  `defaults -currentHost write com.apple.screensaver idleTime -int 0` to keep
  it away. An unattended long round with the screensaver armed would have both
  windows occluded — the display-asleep failure mode with a prettier face.
- Post-upgrade indexing churn (ANECompilerService pegged a core for ~30 min,
  then duetexpertd/Spotlight) had to be waited out before the round.
- The TerminalApp binary on disk had been relinked against `host_debug_arm64`
  after the pre-upgrade round's commit — rebuilt with
  `STARLING_ENGINE_OUT=.../host_release_arm64` and dyld-verified before
  measuring. Window calibration (1624x817 -> 47x201) survived the upgrade
  unchanged on both sides.
