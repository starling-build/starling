# Terminal vs Ghostty, round 9 — the lead retaken, the leak fixed, ascii at the floor

2026-08-11, on the same NucBox K8 Plus and GNOME Shell 50.1 (Wayland) session
as the [2026-08-04 report](../terminal-vs-ghostty-2026-08-04/), every terminal
at exactly grid 47x201. Measured builds:

    TerminalApp      this branch (C core + read-path split + leak fixes +
                     drained reader), GTK embedder build (STARLING_APP_GTK=1)
    ghostty nightly  1.3.2-dev, same binary as the 08-04 report
    ghostty 1.3.0    1.3.0~us1-0ubuntu1 (Ubuntu archive)
    alacritty        0.16.1-2ubuntu1
    kitty            0.45.0-1build1

Three findings, in the order they happened.

## 1. The 10-workload suite: 0.58x of the nightly's wall

Best-of-3 per workload, `data/res-*` (post-leak-fix run: `*-new-*`; final
run with the drained reader: `res-ours-drain-*`).

| workload | ours | nightly | ratio |
|---|---|---|---|
| 03_sgr_fg | 0.186 | 0.628 | **0.30x** |
| 10_binary | 0.313 | 1.210 | **0.26x** |
| 04_sgr_truecolor | 0.252 | 0.459 | **0.55x** |
| 06_cursor_motion | 0.015 | 0.019 | **0.79x** |
| 05_unicode | 0.224 | 0.242 | **0.93x** |
| 01_light_cells | 0.406 | 0.404 | 1.00x |
| 09_long_lines | 0.098 | 0.097 | 1.01x |
| 02_dense_cells | 0.165 | 0.136 | 1.21x |
| 08_scroll_region | 0.307 | 0.266 | 1.15x |
| 07_alt_screen | 0.082 | 0.068 | 1.21x |
| **total** | **2.05** | **3.53** | **0.58x** |

On 08-04 (pre-C-core) we were 1.13x *slower* overall and last of five on
unicode. Control: the same nightly binary reproduced its archived numbers to
within 0.97-1.36x across workloads, so the movement is the code, not the box.

## 2. Ghostty's own three published tests: two of three

Their post's tests, five terminals, medians of 3 (`data/bigcat-*`,
`data/doom-*`):

| test | ours | ghn | ala | kitty | gh130 |
|---|---|---|---|---|---|
| `time cat 150mb_ascii.txt` | 0.750 (2nd) | **0.696** | 1.236 | 1.213 | 1.467 |
| `time cat 150mb_unicode.txt` | **0.541** | 0.591 | 1.058 | 1.215 | 1.415 |
| DOOM-Fire-Zig (fps, 600 frames) | **1960** | 1224 | 890 | 374 | 573 |

On 08-04 the nightly swept all three. Our own moves: DOOM 591→1960 fps,
unicode 1.567→0.541 s (was last of five), ascii 0.840→0.750. Our ascii CPU
is 1.15 s to the nightly's 1.38 — we do less work; they finish sooner.

## 3. Why ascii stops at 0.750, exactly

`test/bench/core/ptyread.c` isolates the read path (modes 0-4). On this box,
150 MB through a pty costs **0.74-0.75 s for every read(2)-based consumption
pattern** — the pty returns ~600-byte reads during a flood regardless of
buffer size, and mode 1 (poll + drain), mode 3 (threaded ring) and mode 4
(ring + drain-into-slot) all land on the same wall. That is the floor, and
0.750 sits on it.

The nightly's 0.696 is *below* that floor: strace shows io_uring_enter in
its read path and ~7 KB mean reads to our ~600 B. Matching it is a transport
rewrite (io_uring), not a tune.

What the drained reader (Pty.swift) did buy, versus publishing every ~700 B
chunk through the ring: ring passes fell ~80x (ptyread mode 3 → mode 4:
204k feeds → 2.8k), futex traffic fell from 34k calls (50% of strace'd time)
to noise, ascii went 0.780→0.750 wall and **1.42→1.15 CPU**, and
light_cells/long_lines became ties with the nightly.

## The memory leak, fixed the same day

The +20-25 MB-per-styled-dump leak (open since 08-04) is fixed: flat RSS over
14 consecutive `03_sgr_fg` passes (was +20 MB per pass, unbounded). Six
defects, all one species — reference patterns Dart's GC collects and ARC
cannot:

1. `Element._parent` was strong → the element tree was one retain-cycle
   cluster; every dropped subtree leaked wholesale. Dominant (20→5 MB/pass).
2. `InheritedElement._dependents` held dependents strongly and `deactivate()`
   never unregistered them → the live theme pinned every dead Text element
   with its whole span tree. The residual 5 MB/pass.
3. `ParagraphBuilderBridge::Build()` (engine) lacked `SWIFT_RETURNS_RETAINED`
   → every engine-side paragraph got an extra retain and never destructed.
   Fifteen sibling factory methods had the same hole (scene builder, layers,
   images, codecs, semantics) — all annotated.
4. Unmount was not recursive → no descendant's `renderObject.dispose()` ran.
5. `finalizeTree()` had no caller → inactive elements never unmounted at all.
6. `TextLayout._painter` strong back-ref → every laid-out TextPainter
   self-retained; sibling parentData pointers cycled adjacent children.

Benchmark RSS after three suites: 399 MB → 240 MB (ghostty: 171).

## Reproducing

Both terminals run inside one GNOME Wayland session (GNOME refuses synthetic
input, so each terminal *executes* the runner itself — ours via
`STARLING_DEV_SHELL`, the others via `-e`). On a Starling box:
`Session=gnome` in `/var/lib/AccountsService/users/<user>`, then restart
**accounts-daemon and then gdm** — gdm alone reuses the cached session.

1. Stage workloads + runners: `test/bench/gen-bench.py /var/tmp/bench`, copy
   `test/bench/run-bench.sh` and the 08-04 report's `bigcat.sh` /
   `doomfire.sh` there, plus the two 150 MB files and the patched
   DOOM-fire binary (`../terminal-vs-ghostty-2026-08-04/` documents both).
2. Stage the GTK build + its libraries into `/var/tmp/bench/gtkrun`
   (binary, libFlutterShared.so, libflutter_engine.so, libflutter_linux_gtk.so,
   resources — see `test/bench/core/README.md`).
3. `./calibrate.sh` — solves the pixel size that gives TerminalApp exactly
   201x47 (window flags are requests, not grids). `./calib-ghostty.sh` does
   ghostty (201x47 request lands on 200x44; the answer here was 202x50).
   kitty: `initial_window_width=201c` overshoots under fractional scaling —
   194c x 46c landed on 201x47 here. Verify every grid; the cell-filling
   workloads scale with cell count.
4. `./bench.sh` — the 10-workload suite, three terminals.
   `./published.sh` — the three published tests, five terminals.
   `./report.sh` — best-of-3 aggregation.
   `BENCH_USER=<session user>` if it is not `starling`.

Raw data from this machine is under `data/`.

## Addendum: the same suite inside the release-gate VM, GPU tier (virgl)

Same three terminals, same 47x201, inside the `test/vm-harness` VM
(`launch-vm-2604.sh` with an explicit 1920x1080 scanout: 4 vCPUs, 8 GB,
virtio-vga-gl + egl-headless on the host's 780M — guest renderer reports
`virgl (AMD Radeon 780M)`). ghostty runs `--font-size=10` here: at guest DPI
its default cells are ~10.4 px wide and 201 columns do not fit a 1920 px
screen — it pinned at 184 columns whatever was requested. Absolute numbers
are a different machine (4 vCPUs, GL through virgl); only the within-VM
comparison is meaningful. Raw data: `data/vm/`, driver: `vmbench.sh`.

Best-of-3 wall, suite total: **ours 2.75 s, nightly 6.88, 1.3.0 7.07** —
ours at **0.40x of the nightly** (bare metal: 0.58x), winning 8 of 10.
DOOM-Fire: ours 1212 fps, nightly 1220 — a dead heat (bare metal: 1960 vs
1224).

The interesting part is the slowdown each terminal takes moving host -> VM:

|            | suite host | suite VM | slowdown |
|------------|-----------:|---------:|---------:|
| ours       | 2.05       | 2.75     | 1.34x    |
| nightly    | 3.53       | 6.88     | 1.95x    |
| gh 1.3.0   | 5.81       | 7.07     | 1.22x    |

The nightly degrades most — the io_uring transport and render path that beat
us on bare-metal ascii do not survive 4 vCPUs + virgl, and inside the VM the
nightly is barely distinguishable from the 8-months-older 1.3.0. Our repaint
throttle decouples parse throughput from render cost, which is exactly the
property a paravirtualized GPU rewards. DOOM tells the same story from the
other side: our bare-metal 1960 fps is virgl-capped to ~1210 in the VM,
landing exactly on the nightly's ~1220, which was already at that ceiling on
the host.

## Addendum: the suite on the Lenovo dev box (same day)

Lenovo Slim Pro 7 14ARP8 (Ryzen 7 7735HS), kernel 7.0.0-29, GNOME Shell
(Wayland, ubuntu mode) on a forced 4K HDMI scanout — the headless-EDID setup
from CLAUDE.md, GDM autologin. Same branch build (GTK embedder, release
engine), same 10-workload suite, both terminals verified at exactly 201x47
(ghostty 1.3.0-dev needed a 201x49 request here; the calibrated 202x50
answer from probe time drifted a row+column in the real run — verify the
grid in `meta-*`, not the calibration).

The nightly here is **1.3.2-dev+046b8fc**, built from the tip source tarball
published this day (Zig 0.16.0, ReleaseFast) — a newer commit than round 9's
48d85ea. Best-of-3 wall, `data/lenovo-14arp8/`:

| workload | ours | nightly | 1.3.0-dev | vs nightly |
|---|---|---|---|---|
| 10_binary | 0.466 | 1.818 | 1.574 | **0.26x** |
| 03_sgr_fg | 0.327 | 1.254 | 1.710 | **0.26x** |
| 04_sgr_truecolor | 0.449 | 0.927 | 1.747 | **0.48x** |
| 06_cursor_motion | 0.018 | 0.032 | 0.047 | **0.56x** |
| 07_alt_screen | 0.119 | 0.146 | 0.649 | **0.82x** |
| 09_long_lines | 0.143 | 0.168 | 0.618 | **0.85x** |
| 05_unicode | 0.339 | 0.385 | 0.797 | **0.88x** |
| 08_scroll_region | 0.452 | 0.452 | 0.726 | 1.00x |
| 01_light_cells | 0.587 | 0.488 | 0.558 | 1.20x |
| 02_dense_cells | 0.241 | 0.180 | 0.449 | 1.34x |
| **total** | **3.14** | **5.85** | **8.88** | **0.54x** |

**Round 9's headline reproduces on a second machine: 0.54x of the nightly
here, 0.58x there** — against a newer nightly commit. The shape matches too:
we take the escape/parser workloads (sgr, binary, truecolor), the nightly
keeps raw cell-fill (dense_cells 1.34x, light_cells 1.20x — same two it held
on the NucBox). RSS after the run: ours 265 MB, nightly 214 MB, 1.3.0
200 MB. Absolute walls are not comparable to the NucBox tables (different
display pipeline — 4K at 200% vs the NucBox panel); the within-machine
ratios are the result.

### Lenovo: ghostty's own three tests, five terminals

Medians of 3, every terminal verified at 201x47 (ghostty builds via a
201x49 request, kitty via 194c x 46c — the same corrections as the NucBox;
kitty's 201c request overshot to 48x208 here too). alacritty 0.16.1, kitty
0.45.0, both from the Ubuntu archive. Raw: `data/lenovo-14arp8/`.

| test | ours | nightly | 1.3.0-dev | alacritty | kitty |
|---|---|---|---|---|---|
| `time cat 150mb_ascii.txt` | 0.942 (2nd) | **0.927** | 2.455 | 1.648 | 1.380 |
| `time cat 150mb_unicode.txt` | **0.656** | 1.071 | 2.265 | 1.347 | 1.463 |
| DOOM-Fire-Zig (fps, 600 frames) | **1179** | 547 | 347 | 548 | 527 |

The round-9 outcome holds on this box: two of three to us, ascii to the
nightly by 1.6% — consistent with the read(2)-floor analysis (§3); the
nightly's io_uring transport buys it the ascii cat everywhere. DOOM at 2.2x
the nightly (NucBox: 1.6x). The nightly here is tip+046b8fc rebuilt from
source, so "same binary as 08-04" no longer applies — the movement it shows
vs its own 1.3.0 (ascii 2.46→0.93) is seven months of their work plus a
newer commit than round 9 measured.

## Round 10, same day, back on the NucBox: the futex convoy, and §3 retracted

Chasing the two cell-fill losses found that §3's premise was a measurement
artifact, and the real culprit was a lock convoy in our ring. The full
methodology and dead ends (io_uring single-shot and multishot, fixed pacing,
a 256 K linger, adaptive inline parse) are in `test/bench/core/README.md`;
the short version:

- **§3's "below the floor" compared two clocks.** The harness wall is the
  reader's (exec through EOF drain); the bench metric — `time cat` in the
  terminal — is the writer's, which stops at the last accepted write. On the
  writer's clock every read(2) pattern lands within noise of ghostty, whose
  pty data path is itself plain `read(2)` — the io_uring_enter calls in its
  strace are its event loop. Its big reads come from parsing between reads;
  reproducing the batching (pace, linger, 256 K slots) reproduces the batch
  sizes and moves nothing. **There is no transport rewrite to do.**
- **The real gap was ours to fix**: `strace -f -e trace=futex` per-thread
  put the live app at 2.5x ghostty's futex traffic, concentrated in the
  reader+parser pair — ~7 futex ops per ring handoff. `ChunkRing` signalled
  a shared condvar with the mutex held (glibc has no wait morphing: "hurry
  up and wait"), and broadcast where one waiter existed. Wake-flags + signal
  only when the other side waits + signal after unlock cut it to ~2.

Best-of-3, fresh launches, both at 47x201 (`data/*-convoyfix-*`,
`data/*-ghncontrol-*` — the control is the same nightly binary re-run):

| workload | ours r9 | ours r10 | nightly | ratio r10 (r9) |
|---|---|---|---|---|
| 02_dense_cells | 0.165 | 0.153 | 0.138 | **1.11x** (1.21x) |
| 01_light_cells | 0.406 | 0.397 | 0.402 | **0.99x** (1.00x) |
| 07_alt_screen | 0.082 | 0.077 | 0.071 | 1.08x (1.21x) |
| 08_scroll_region | 0.307 | 0.306 | 0.277 | 1.10x (1.15x) |
| **total** | 2.05 | **2.016** | 3.509 | **0.57x** (0.58x) |

Suite CPU 3.34 vs the nightly's 4.44. Escape-heavy workloads unchanged
(sgr_fg 0.173, binary 0.321 — within the ±10-16% layout lottery the core
README documents). What remains of dense_cells (0.153 vs 0.138, with
repaints suppressed we measure exactly our harness's mode-4 number) is the
split design itself — ghostty parses inline on its read thread, so no
second thread perturbs the writer→kworker→reader chain during floods. An
adaptive inline parse (harness mode 10) engages correctly and measures
inside noise; it stays unshipped until a workload justifies it.

## The fullscreen protocol: same pixels, same font, same grid — same verdict

The calibrated-window ritual (solve each terminal's pixel request until the
grids match) leaves two things unequal: the pixel areas, and — discovered
while replacing it — the RENDER RESOLUTION. This session ran 4K at scale
1.5, where a GTK3 client (our bench build) renders at integer scale 2
(5120x2880, compositor-downscaled) while ghostty renders native fractional
3840x2160. Every prior round ran on that tilted field.

`run-gnome-fs.sh` is the replacement, one condition per line: session at
1920x1080 @ scale 1 (mutter DisplayConfig), both terminals fullscreen
(ghostty needs `--fullscreen=true`; the bare flag is ignored), both on the
repo's Roboto Mono (ours 13 logical px, ghostty --font-size=9.75 — points at
96 dpi), ours with `STARLING_CELL_W=8.0` (freetype hints the advance to 8.0
where our shaper keeps the fractional 7.8; letterSpacing makes up the
difference), ghostty with padding 6 so both floors land on the same column.
Both terminals then VERIFY at 238x62, the corpus is regenerated for that
grid (`gen-bench.py /var/tmp/benchfs 238 62`), and the runner waits for the
fullscreen configure before timing (both terminals exec their command at the
pre-fullscreen size — an early probe read 145x45 for exactly that reason).

**Correction (same day):** the first fullscreen runs (`data/*-fsours-*`,
`*-fsghn-*`, `*-fs4kours-*`, `*-fs4kghn-*`) did NOT run the regenerated
corpus. `bench-in-terminal.sh` resolved `run-bench.sh` through `$OUTDIR`
(/var/tmp/bench), whose copy cats its OWN directory's corpus — so every
"fullscreen" run replayed the original 200-col files at the new grid. Both
terminals still ran identical bytes at identical grids, so those ratios are
valid A/Bs of *narrow content on a wide grid*; the tables below are the
corrected runs with the per-grid corpus (`data/*-fs2*`, `*-fs4k2*`). The
runner now lives in the repo and resolves corpus and sub-runner from its own
directory. Caught because a 244 MB alt_screen "catted" in 0.087 s —
2.8 GB/s through a pty; when a bench number beats a kernel floor, the bench
is lying somewhere.

Best-of-3, identical grid and pixels (`data/*-fs2ours-*`, `*-fs2ghn-*`):

| workload | ours | nightly | ratio | calibrated (r10) |
|---|---|---|---|---|
| 10_binary | 0.304 | 1.289 | **0.24x** | 0.26x |
| 03_sgr_fg | 0.195 | 0.733 | **0.27x** | 0.28x |
| 04_sgr_truecolor | 0.283 | 0.533 | **0.53x** | 0.58x |
| 06_cursor_motion | 0.015 | 0.020 | **0.75x** | 0.74x |
| 05_unicode | 0.231 | 0.266 | **0.87x** | 0.93x |
| 01_light_cells | 0.398 | 0.399 | **1.00x** | 0.99x |
| 09_long_lines | 0.107 | 0.099 | 1.08x | 1.08x |
| 02_dense_cells | 0.169 | 0.155 | 1.09x | 1.11x |
| 07_alt_screen | 0.122 | 0.108 | 1.13x | 1.08x |
| 08_scroll_region | 0.298 | 0.251 | 1.19x | 1.10x |
| **total** | **2.122** | **3.853** | **0.55x** | 0.57x |

CPU 3.42 vs 4.91.

### Native 4K, no scaling anywhere: the verdict holds, the margin scales

One scale question remained: this box's "display" is the injected-EDID 27"
4K virtual panel, and mutter's own preferred scale for its 4K mode is
**1.5** — the tilted field of the earlier rounds was GNOME's *default* for
this hardware, not a leftover setting. (For the 1080p mode the preferred
scale is 1.0, so the protocol above is GNOME's own unscaled choice there.)
The remaining variant is native 4K at scale 1.0 — no scaling for anyone,
grid verified **478x126** on both, corpus regenerated
(`gen-bench.py /var/tmp/benchfs4k 478 126`, `BENCH_FS_DIR` selects it).
Best-of-3, `data/*-fs4k2ours-*` / `data/*-fs4k2ghn-*` (corrected corpus):

| workload | ours | nightly | ratio | @238x62 |
|---|---|---|---|---|
| 10_binary | 0.526 | 0.857 | **0.61x** | 0.24x |
| 03_sgr_fg | 0.393 | 1.458 | **0.27x** | 0.27x |
| 04_sgr_truecolor | 0.552 | 1.046 | **0.53x** | 0.53x |
| 06_cursor_motion | 0.014 | 0.021 | **0.67x** | 0.75x |
| 05_unicode | 0.398 | 0.480 | **0.83x** | 0.87x |
| 02_dense_cells | 0.237 | 0.215 | 1.10x | 1.09x |
| 08_scroll_region | 0.295 | 0.259 | 1.14x | 1.19x |
| 07_alt_screen | 0.484 | 0.406 | **1.19x** | 1.13x |
| 09_long_lines | 0.220 | 0.180 | **1.22x** | 1.08x |
| 01_light_cells | 0.544 | 0.406 | **1.34x** | 1.00x |
| **total** | **3.663** | **5.328** | **0.69x** | 0.55x |

Still ours at every protocol — 0.57x calibrated, 0.55x at 1080p, 0.69x at
native 4K — but the 6x grid area concentrates the losses into one cluster:
every row-churn workload scales with ROW WIDTH for us (light_cells 1.00x ->
1.34x, long_lines 1.08x -> 1.22x, alt_screen 1.13x -> 1.19x) while
ghostty's stays pty-bound and flat (their light_cells 0.399 -> 0.406), and
at 4K our CPU advantage disappears (7.36 vs 7.17 CPU-s — the one protocol
where we cost more). The mechanism is harness-proven, not inferred:
`ptyread` mode 4 at 478x126 on light_cells pushes cat to 0.52-0.54 against
a 0.38-0.39 read floor with no compositor in the room — the emulator's
per-line work alone. The candidate: `row_blank` memsets the full row width
on every recycled line — 1.5M line feeds x 478 cells x 16 B = 11.5 GB of
blanking for rows that carry ~7 characters.

### Extent-based row blanking: the 4K cluster closed, same day

Confirmed and fixed (`terminal: blank only what was written`): rows track
their written extent and the background of the blank tail beyond it;
recycling fills only the prefix, erase-to-end shrinks the extent instead of
writing. Memory stays byte-identical (differential + fuzz + sanitizers —
the full battery is in `test/bench/core/README.md`). Live, same protocol,
same ghostty control (`data/*-fs4k3ours-*`, `data/*-fs3ours-*`):

| 4K 478x126 | before | after | nightly | ratio |
|---|---|---|---|---|
| 01_light_cells | 0.544 | **0.406** | 0.406 | **1.00x** (was 1.34x) |
| 10_binary | 0.526 | **0.328** | 0.857 | **0.38x** (was 0.61x) |
| **total** | 3.663 | **3.360** | 5.328 | **0.63x** (was 0.69x) |

`ptyread` mode 4 at 478x126 lands on the read floor (0.52-0.54 ->
0.38-0.39): light_cells is transport-bound again at any width, which is
where it should be. At 1080p the wall is inside session noise (2.173 vs
2.122, against ghostty's own 17% run-to-run swings) and CPU drops 3.42 ->
3.22. Remaining 4K losses: alt_screen 1.18x, long_lines 1.20x,
scroll_region 1.14x, dense_cells 1.13x — row-movement and cell-write bound,
no longer blanking bound.

### Are the tests long enough? The 6x corpus says the short ones were honest

Fair objection: the corpus was sized when "a couple of seconds per workload"
was true, and the terminals have gotten ~4x faster since — most workloads
finished in 0.1-0.4 s, where timer quantization, scheduler luck and settle
effects are a visible fraction of the number. `gen-bench.py` now takes a
SCALE argument (default 1 keeps the standard corpus byte-identical);
`gen-bench.py /var/tmp/benchlong 238 62 6` rebuilds every workload at 6x
(23 MB-800 MB, 0.6-8.8 s per measurement), and `BENCH_RUNS=5` runs five
passes. Median-of-5 at the same 238x62 fullscreen protocol
(`data/*-longours-*`, `data/*-longghn-*`):

| workload | ours med (spread) | nightly med (spread) | ratio | short |
|---|---|---|---|---|
| 10_binary | 1.880 (1.848-1.924) | 8.766 (8.747-8.780) | **0.21x** | 0.24x |
| 03_sgr_fg | 1.334 (1.225-1.394) | 5.121 (5.092-5.222) | **0.26x** | 0.27x |
| 04_sgr_truecolor | 1.885 (1.797-1.991) | 3.738 (3.699-3.871) | **0.50x** | 0.53x |
| 06_cursor_motion | 0.062 | 0.101 | **0.61x** | 0.75x |
| 05_unicode | 1.437 (1.414-1.444) | 1.597 (1.594-1.707) | **0.90x** | 0.87x |
| 01_light_cells | 2.362 (2.346-2.390) | 2.395 (2.381-2.461) | **0.99x** | 1.00x |
| 02_dense_cells | 1.007 (0.997-1.014) | 0.969 (0.951-0.998) | 1.04x | 1.09x |
| 07_alt_screen | 0.741 (0.699-0.778) | 0.701 (0.674-0.781) | 1.06x | 1.13x |
| 08_scroll_region | 1.787 (1.710-1.808) | 1.647 (1.631-1.734) | 1.09x | 1.19x |
| 09_long_lines | 0.645 (0.621-0.649) | 0.592 (0.585-0.623) | 1.09x | 1.08x |
| **total** | **13.140** | **25.627** | **0.51x** | 0.55x |

Median per-workload spread is ~5% for BOTH terminals — on multi-second
measurements that is real machine variance, not timing artifact — and every
short-corpus conclusion reproduces. The drift that does appear runs one
way: the remaining losses SHRINK when the tests get longer (scroll_region
1.19x -> 1.09x, alt_screen 1.13x -> 1.06x, dense_cells 1.09x -> 1.04x),
because startup and settle effects were charged against a 0.1-0.3 s
denominator; the wins deepen for the same reason (binary 0.24x -> 0.21x,
total 0.55x -> **0.51x**). The short suite was, if anything, biased against
us. cursor_motion stays sub-100 ms even at 6x (it is escape-parsing
already covered by sgr_fg) — treat its ratio as indicative only.

### The last four, decomposed — and where the levers stop

Writer-clock floors at 478x126 for the four remaining losses (`ptyread`
mode 2, `PTYREAD_CMD` wrapper), against both live walls:

| workload | read floor | ours live | nightly live |
|---|---|---|---|
| 02_dense_cells | 0.224-0.236 | 0.244 | **0.215 — below the floor** |
| 07_alt_screen | 0.429-0.453 | 0.479 | **0.406 — below the floor** |
| 08_scroll_region | 0.284-0.308 | 0.294 | **0.259 — below the floor** |
| 09_long_lines | 0.176-0.201 | 0.216 | 0.180 — at the floor |

Two components:

1. **Ours-over-floor is the repaint, and it is measurable**: alt_screen
   live with `STARLING_BENCH_NOREPAINT=1` drops 0.515 -> 0.449 (medians of
   5) — onto the floor. At 4K the GTK harness presents ~33 MB per frame
   through a software pixman blit whose memory traffic competes with the
   ldisc copy chain; ghostty renders on the GPU. The lever here is GL
   presentation in the FlutterGTK host — a bench-build artifact in part,
   since the shipping DRM path never pays the blit.
2. **The nightly's below-the-floor residue (~5-8%) is NOT reachable by any
   read strategy we can construct.** Measured on the writer's clock, at
   this grid, on these files: eager (mode 2), paced (6, 8 — catastrophic
   here: sleeping throttles the writer within ~120us at these byte
   rates), 256K-linger (9), adaptive inline (10 — engages, helps
   scroll_region ~5%, cannot reach 0.406), fully serial (0 — parse goes
   ADDITIVE on the big streams: alt 0.635 = 0.43 transport + 0.22 parse),
   and io_uring (5, 7). A matched-cgroup control (the probe run inside the
   bench user's systemd scope) reproduces the same floor, ruling out
   scheduling-weight artifacts. Whatever the nightly's read context does
   for the writer's kernel path — thread placement, turbo residency,
   something else — it is not a consumption-pattern lever, and a
   read-and-discard loop cannot match it. ~170 ms across the four (5% of
   suite wall) is the total on the table; roughly half is component 1.
Note the realistic 4K desktop runs 1.5-2x scale, where the LOGICAL grid is
near the 1080p one — the 478x126 shape is a stress variant, not a user
setting.

## The cluster build on the NucBox — the verdict survives conformance

Back on the NucBox with the merged main (wide cells + grapheme clusters +
extent blanking), fullscreen protocol, medians of 3, same nightly control,
both grids verified (`data/*-nb4k*`, `*-nb1080*`, published tests
`*-nb4kv2*`). Suite totals: **0.55x at 1080p (2.407 vs 4.394), 0.56x at 4K
(3.903 vs 6.941)**. The control ran ~15-30% slower than its own
morning numbers across the board, so cross-round absolute comparisons are
off the table; the within-pair ratios are the result.

What conformance changed, honestly told: the unicode workloads flipped
from wins to small losses (suite 05_unicode 0.87x -> 1.09x at 1080p,
0.83x -> 1.16x at 4K; the published unicode cat went to the nightly here,
0.876 vs 0.750 — on 30% less CPU, 1.25 vs 1.74 s) — correct wide advance
wraps more and pays per-scalar width lookups, the same price the Lenovo
measured. In exchange the 4K row-churn loss cluster is gone outright:
alt_screen 0.92x, long_lines 0.94x, scroll_region 1.03x, dense_cells
0.90x, light_cells 0.95x — every former loss now a win or tie (control
drift flatters these; the direction matches the Lenovo's independent
result). Published tests here: DOOM-Fire decisively ours (544-561 vs
354-371 fps at 2.2-2.7 vs 3.6-3.8 CPU-s), the ascii cat a 1.7% coin flip
(0.797 vs 0.784), the unicode cat theirs on this box — against the
Lenovo's three-of-three with its from-source nightly. Machine and nightly
vintage matter; within-machine, the suite verdict is unchanged at ~0.55x.

### Same commit, both builds, one machine: the Lenovo sweep is the HARDWARE

The NucBox/Lenovo disagreement (three-of-three there, a split here) invited
two explanations: the Lenovo's control was built from source (slower
pipeline?) or the machine treats the two terminals differently. Tested by
building the Lenovo's exact control here — commit 046b8fc, Zig 0.16.0,
ReleaseFast — and racing it against the official nightly binary back to
back at 126x478 (`data/*-nb4kv2gh046*`, `*-nb4kv3ghn*`): ascii 0.788 vs
0.789, unicode 0.723 vs 0.734, DOOM 382 vs 373 fps. **Identical within
noise — the build pipeline explains nothing.** The same commit that does
0.79/0.72/380 here did 1.155/1.166/243 on the Lenovo, a 45-55% drop,
while our terminal drops only 15-20% between the same two machines.
Ghostty's throughput is strongly hardware-dependent; ours is comparatively
flat — the same shape the virgl VM addendum measured (their 1.95x
degradation vs our 1.34x). The Lenovo's all-ten sweep is a true result on
that hardware class, not a build artifact; quote per-machine pairs, never
cross-machine absolutes.
