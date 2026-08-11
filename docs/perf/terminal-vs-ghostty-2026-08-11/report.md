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
