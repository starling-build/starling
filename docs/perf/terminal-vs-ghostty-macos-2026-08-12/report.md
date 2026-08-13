# Terminal vs Ghostty on macOS — the first round off Linux

2026-08-12, MacBook Pro (Apple M1 Pro), macOS 26.5, both terminals as ordinary
windows in the same desktop session, both verified at exactly **201x47**
(`meta-*` reports `grid 47x201` for each). Measured builds:

    TerminalApp      this branch, Cocoa host (FlutterCocoa), release, against a
                     locally built engine at 6fcc6d7 (host_debug_arm64)
    ghostty          1.3.2-main+51ed437cd, tip build, Zig 0.16.0, ReleaseFast,
                     Metal renderer, coretext

**On the ghostty build.** The Linux rounds measured `1.3.2-dev+046b8fc`, and
that is the commit this round set out to build. It could not be built on this
machine: `zig build` succeeds for libghostty and the xcframework, but the macOS
app build deadlocks inside `xcodebuild` at `Resolve Package Graph`
(`waitForRemoteSourcePackagesToFinishLoading`, 0% CPU, indefinitely). That is
**not** a ghostty problem and not the network — with the package references
removed entirely the same build compiles immediately, and it hangs identically
for a *local* package reference pointing at an already-checked-out copy. Xcode
26.5 on this box cannot load any Swift package graph. So this round measures
the published tip build instead, which is **24 commits ahead of 046b8fc and 0
behind** — a direct descendant, one day later — built with the same Zig 0.16.0
and the same ReleaseFast mode the Linux round used. Full detail in
*What could not be measured* below.

## The 10-workload suite: 1.35x of ghostty's wall

Best-of-3 per workload (min wall), corpus regenerated at 201x47, `data/res-*`.

| workload | ours | ghostty | ours MB/s | gh MB/s | ratio |
|---|---|---|---|---|---|
| 10_binary | 0.286 | 0.552 | 104.9 | 54.3 | **0.52x** |
| 01_light_cells | 0.112 | 0.150 | 97.2 | 72.6 | **0.75x** |
| 06_cursor_motion | 0.037 | 0.035 | 100.2 | 106.0 | 1.06x |
| 03_sgr_fg | 0.863 | 0.614 | 84.2 | 118.3 | 1.41x |
| 04_sgr_truecolor | 0.955 | 0.663 | 117.9 | 169.8 | 1.44x |
| 05_unicode | 0.475 | 0.290 | 123.8 | 202.8 | 1.64x |
| 02_dense_cells | 0.252 | 0.141 | 120.2 | 214.9 | 1.79x |
| 07_alt_screen | 0.347 | 0.187 | 112.9 | 209.4 | 1.86x |
| 09_long_lines | 0.330 | 0.173 | 121.9 | 232.5 | 1.91x |
| 08_scroll_region | 0.380 | 0.194 | 115.0 | 225.2 | 1.96x |
| **total** | **4.037** | **2.999** | | | **1.35x** |

RSS after the run: ours 174 MB, ghostty 124 MB.

Runs 1 and 2 agree closely (totals 4.062 / 4.070 ours, 3.084 / 3.027 ghostty).
Run 3 is an outlier for *both* terminals (14.19 / 9.82) — the machine was
disturbed mid-run; best-of-3 discards it, which is why the method is best-of
rather than mean. Every per-workload ordering above is consistent across runs
1 and 2, so the shape is not noise.

## We spend LESS CPU and MORE wall time

This is the finding worth keeping:

| | ours | ghostty |
|---|---|---|
| total wall | 4.037 s | 2.999 s |
| total CPU | **7.29 s** | 8.12 s |

We burn 10% less CPU over the suite and still finish 35% later. Whatever costs
us the wall time on macOS is therefore **not** parser or cell-fill work — we do
measurably less of that than ghostty does. It is time not spent computing:
frame pacing, present, or the hop from the reader thread to the composite. The
same signature appeared on Linux for the ascii cat ("we do less work; they
finish sooner"), where it was chased to the read(2) transport floor; here it
covers the whole suite and has not been chased yet.

The workload split says the same thing from the other side. The two we win are
the two whose cost is dominated by *parsing* — `10_binary` (random bytes with
stray escapes, the parser's worst case; we are ~2x ahead) and `01_light_cells`.
The eight we lose are the ones dominated by *drawing* — cell fill, scroll
regions, alt-screen repaints, long-line wrap — where ghostty's Metal renderer
is 1.8-2.0x our compositing path.

## How this compares to Linux, and how it does not

Round 9 on Linux put us at **0.58x** of the ghostty nightly over the same 10
workloads. Here we are at **1.35x**. The headline reversed, but the two numbers
are not measuring the same thing and should not be subtracted:

- **Different rendering stacks on each side.** On Linux both terminals drew
  through one GNOME Wayland compositor, so the comparison isolated the
  terminals. Here it is our Cocoa host (Flutter engine, Metal) against
  ghostty's native AppKit/Metal renderer — two different pipelines, and the
  gap includes whatever our embedder costs relative to theirs.
- **Different machines.** M1 Pro laptop here; NucBox K8 Plus / Lenovo there.
  Absolute walls were never comparable across rounds, only within one.
- **The parser result survives the move.** `10_binary` was 0.26x on Linux and
  is 0.52x here — still a clear win on both platforms, which is consistent
  with the C core being the thing that carries across and the drawing path
  being what differs.
- **`03_sgr_fg` did not survive.** 0.30x on Linux, 1.41x here: the single
  biggest swing in the table, and the obvious first place to look.

## What could not be measured

**ghostty at exactly 046b8fc.** Seven approaches to the Xcode package-graph
deadlock all hung at the same point: plain `zig build`;
`xcodebuild -resolvePackageDependencies`; a fresh `-clonedSourcePackagesDirPath`
(which did fetch and check out Sparkle 2.9.0, then still hung);
`-disableAutomaticPackageResolution`; `-skipPackageUpdates` with
`-IDEPackageSupportUseBuiltinSCM=YES`; a full environment rather than
`env -i`; and resolving through the Xcode GUI first and then building from the
CLI. Killing `XCBBuildService`/`SourceKitService` and clearing the package
cache did not help either. Ghostty's own docs say nothing about Sparkle and
offer no flag to disable it — but Sparkle is not the cause: any package graph
hangs, and removing all package references lets the build proceed. Reproducing
the exact commit needs either a working Xcode on the host or ghostty's
published build for that commit.

**Keyboard/interactive load.** The suite is `cat` throughput only, as on Linux.

**ghostty 1.3.1 stable** is installed on this machine and was not run; the
Linux rounds carried a stable build alongside the nightly and this round has
only the tip build.

## Running it

    stage.sh                      # scripts + corpus at the target grid, ~420 MB
    GHOSTTY=<Ghostty.app>/Contents/MacOS/ghostty calibrate.sh
    GHOSTTY=<...>/ghostty bench.sh
    report.sh

Three things the macOS port had to fix, each of which produces a *wrong number*
rather than an error:

- `run-bench.sh` timed with `$EPOCHREALTIME`, a bash 5 builtin; macOS ships
  bash 3.2. Ported to zsh, where it is also a builtin — a `date`/`python3`
  subprocess would add 10-30 ms inside the timed region and
  `06_cursor_motion` runs in 0.035 s.
- CPU and RSS came from `/proc/<pid>/{stat,status}` → `ps -o time=,rss=`.
- `ps -o comm=` prints a **full path** on macOS, so the runner's
  shell-wrapper test never matched, the walk up to the terminal stopped at the
  first parent, and CPU would have been attributed to the login shell. Fixed
  with a basename compare; `meta-*` records what was actually measured.

And two launch traps: the grid probe must sleep before reading `stty size`
(the shell starts on the pty's initial 80x24 and the view resizes it from its
first build — reading immediately reports 80x24, which the calibrator then
reads as two identical grids and divides by zero), and ghostty must be started
as `Ghostty.app/Contents/MacOS/ghostty`, not `open -na` (detached, unwaitable)
and not a stray `ghostty` on `PATH` (a copy outside its bundle is only the
helper CLI and prints usage). Ghostty's first launch also shows Sparkle's
"Check for updates automatically?" dialog, which blocks the terminal window
from ever opening; the harness expects it suppressed.

## Addendum, same day: ghostty's own three published tests

The Linux rounds have run ghostty's advertised set since 2026-08-04; this
round measured it and never wrote it up. Closing that, with `published.sh`
(added here), against the same tip build, both terminals verified at 47x201
for every run. Best of 3 — walls are `time cat` **inside** the terminal, so
this is the writer's clock, the metric those rounds settled on.

| test | ours | ghostty | | our CPU | gh CPU |
|---|---|---|---|---|---|
| `cat 150mb_ascii` | **0.570 s** | 0.634 s | **0.90x** | 0.56 | 1.49 |
| `cat 150mb_unicode` | **0.745 s** | 0.761 s | **0.98x** | 1.32 | 2.16 |
| DOOM-Fire-Zig, 600 frames | **1099 fps** | 990 fps | **1.11x** | 1.28 | 1.62 |

**Three of three, on 40-60% of the CPU** (RSS 143 MB to their 171). The Linux
rounds took two of three on the NucBox and three of three on the Lenovo, so
this is the first macOS result of the set and it agrees with the Lenovo's.

### It was two of three an hour earlier, and the unicode cat found a real bug

Run before the width-cache fix below, same session:

| test | ours | ghostty | |
|---|---|---|---|
| `cat 150mb_ascii` | 0.580 | 0.654 | 0.89x |
| `cat 150mb_unicode` | **1.300** | 0.762 | **1.71x** |
| DOOM-Fire | 1107 fps | 948 | 1.17x |

The unicode cat was 1.71x, and worse than the same test measured before this
branch's correctness fixes (0.832 s) — a 56% regression that the 10-workload
suite did not show, because `05_unicode` is one line of mixed script among ten
workloads while this corpus is 150 MB of nothing else.

**It was not the renderer.** `STARLING_BENCH_NOREPAINT=1` put it at 1.242 s
against 1.300 live: rendering is 4.5% of it (and half the CPU, the same
signature as the suite). `ptyread_mac` reproduced it off the app entirely —
1.115 s for unicode against 0.555 s for ascii at the *same read count*,
147 849 against 148 882 — so it was the core, on identical transport.

**The cause was `width_lookup`'s eight-entry MRU cache**, 43.6% of the whole
core on this corpus. Eight entries hold every script a mixed line touches, so
the structure looks right; but a line does not touch its scripts once, it
CYCLES them, and MRU handles a cycle worst of all — each script is evicted to
the back exactly in time for its next use. This corpus is that case in the
extreme (Latin, Cyrillic, Greek, CJK, kana, Hangul, Arabic, symbols, emoji in
runs of two to five), so nearly every lookup missed, paid both binary searches
over ~460 intervals, and then shifted seven entries.

Direct-mapped on the codepoint's 512-wide block instead — 128 slots, the whole
BMP alias-free, each slot re-checking the interval it stored so a collision
can only cost a recompute:

    core, MB/s          before   after
    unicode_150mb        282.3   458.8   +62.5%
    05_unicode           381.7   480.5   +25.9%
    every other workload             within ±2%

Live, that is the unicode cat 1.300 -> 0.745 s (**-43%**) and suite
`05_unicode` 0.356 -> 0.282 s, which takes it from 1.22x to **1.00x** — it
was 1.77x when `docs/plans/terminal-perf-macos.md` was written. Output is
byte-identical to the previous core across all twelve corpora (`gridstate.c`,
plus conformance and ASan).

The lesson is about the benchmark, not the cache: **the suite and the
published tests disagreed, and the published test was right.** A workload that
is 100% of one hard thing finds what a ten-workload average buries.

### Suite, after both of this session's core changes

Same protocol as the table at the top, both grids verified:

| | ours | ghostty | |
|---|---|---|---|
| suite wall | **2.230 s** | 2.961 s | **0.75x** |
| suite CPU | **3.52 s** | 8.00 s | 0.44x |

Nine of ten, the lone loss `07_alt_screen` at 1.13x; `05_unicode` is a tie and
`10_binary` is 0.32x. The two changes are the sliding grid window and the
width cache — see the plan.

### Running it

    GHOSTTY=<Ghostty.app>/Contents/MacOS/ghostty ./published.sh

`published.sh` retries the ghostty side until it reports the requested grid.
That guard is not decorative: it fired on this very run — ghostty came up at
**17x49**, where the fire draws a quarter of the cells and the cat wraps four
times. Both of `bigcat-mac.sh` and `doomfire-mac.sh` record `grid=` in their
header, and doomfire records `grid_after` as a second check, because the
window is resized a moment after the shell starts.

DOOM-Fire needs the upstream binary with the archived BENCH patch (stop after
`DOOMFIRE_FRAMES`, report on stderr) plus a Zig 0.16 port — upstream pins
0.14, which cannot link the macOS 26 SDK. `DOOM_BIN` points at it.
