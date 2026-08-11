# test/bench/core — what the emulator core costs, with no rendering

Feeds a captured byte stream straight through the emulator and times it. No
Flutter, no compositor, no PTY: this isolates parse + grid-write cost, which is
the part a C++ port would replace.

    # capture a stream (any terminal program, through a pty at a fixed grid)
    #   -> /var/tmp/bench/doomstream.bin   (see docs/perf/terminal-vs-ghostty-2026-08-04)
    cp ../../../apps/TerminalApp/Sources/TerminalApp/TerminalEmulator.swift .
    swiftc -O -wmo TerminalEmulator.swift bench_main.swift -o bench_swift
    gcc -O2 -std=c99 -D_POSIX_C_SOURCE=199309L bench_c.c -o bench_c
    g++ -O2 -std=c++20 bench_cpp.cpp -o bench_cpp
    ./bench_swift /var/tmp/bench/doomstream.bin 3
    ./bench_c     /var/tmp/bench/doomstream.bin 3
    ./bench_cpp   /var/tmp/bench/doomstream.bin 3

`bench_cpp.cpp` is a deliberate SUBSET — it implements the hot path the streams
exercise (UTF-8 decode, ground printing, ESC/CSI, SGR incl. 256-colour, CUP,
ED/EL, scroll+scrollback) the natural C++ way: flat array, per-character writes,
no run fast path. It is an upper bound on what porting buys, not a replacement.

**Both sides count cell writes so the comparison can be checked rather than
trusted.** On the DOOM-Fire stream they agree to within 54 writes in 3.81 M
(0.0014%); if that number ever diverges, the two are no longer doing the same
work and the MB/s figures mean nothing.

Measured 2026-08-04, Ryzen 7 8845HS, 59.7 MB DOOM-Fire stream at 47x201:

| build                                     | MB/s | vs baseline |
|-------------------------------------------|------|-------------|
| Swift `-O` (what ships)                   |  122 | 1.00x       |
| Swift `-O -enforce-exclusivity=unchecked` |  180 | 1.48x       |
| Swift `-Ounchecked` + exclusivity off     |  240 | 1.97x       |
| C++ `-O2`                                 |  670 | 5.5x        |
| **C `-O2`**                               |  **680** | **5.6x** |

**C and C++ are the same speed** (680 vs 670 MB/s; 1124 vs 1038 on the no-SGR
stream) and produce byte-identical checksums and cell-write counts. There is no
performance argument for C++ here, and the repo bridges Swift to C everywhere
(42 `.c` files to 1 `.cpp` in the shell; every SDK bridge target is C).

**Struct layout, if a C core is ever wired in for real:** Swift's `TermCell` is
size 13, **stride 16**, align 4, offsets `scalar=0 fg=4 bg=8 attrs=12` — and
`CellAttrs.rawValue` is a **`UInt8`**. The matching C struct is therefore

    typedef struct { uint32_t scalar, fg, bg; uint8_t attrs; } Cell;  /* 16 bytes */

`uint32_t attrs` also gives 16 bytes and benchmarks the same, but Swift and C
would then disagree about the 3 bytes after `attrs`. The benchmarks here use the
`uint32_t` form; that is fine for timing and wrong for sharing memory.

The flag builds are not shipping proposals — they bound how much a Swift-side
restructure (flat grid + a buffer pointer held across the feed loop) could
recover. Even with every safety check off, Swift stays 2.7x behind C++, which
is the cost of `[[TermCell]]`'s double indirection and codegen, not of checks.


## Does a faster core reach the user?

`livecat.sh` cats a captured stream through the LIVE terminal so its wall time
can be compared against the offline core on the same bytes and grid. Run it
twice — once normally, once with repaints suppressed — to split the critical
path. Suppressing repaints needs a temporary env gate on `minRepaintInterval`
in `TerminalApp.swift`; it is not a shipping knob.

Measured 2026-08-04 on a 59.7 MB DOOM-Fire stream (ours 56x244):

| | wall | cpu | MB/s |
|---|---|---|---|
| live, normal              | 0.646 s | 1.32 |  92 |
| live, repaints suppressed | 0.594 s | 0.59 | 100 |
| emulator core alone       | 0.510 s |  --  | 117 |
| ghostty nightly, same stream (45x201) | 0.384 s | 0.81 | 155 |

**Rendering costs 0.73 CPU-s but only 0.05 s of wall** — it is ~93% parallel
with the parse and is 8% of the critical path. The critical path is **79%
emulator core**, so core work translates almost 1:1 into user-visible time. A
serial model predicted the opposite and was wrong; measure this before sizing
any core rewrite.

## The C core, and proving it is a straight port

`apps/TerminalApp/Sources/CStarlingTerm` is the emulator core in C. The claim
that it is a *port* — same behaviour, not just similar — is checked, not
asserted:

    gcc -O2 -std=c99 -c ../../../apps/TerminalApp/Sources/CStarlingTerm/starling_term.c
    gcc -O2 -std=c99 starling_term.o diff_c.c -o diff_c
    # swift side needs the OLD Swift emulator; recover it from git history
    swiftc -O -wmo TerminalEmulator.swift diffmain.swift -o diff_swift
    ./diff_c <stream> <cols> <rows> <chunk>      # both print the same
    ./dif/diff_swift <stream> <cols> <rows> <chunk>
    python3 fuzz.py 200                          # randomised differential

`bench_st.c` is the same timing harness pointed at the real core rather than at
`bench_c.c`'s standalone reimplementation, and `ab.sh <baseline.c>` builds two
cores from source with identical flags and prints both plus the ratio — use it
for any core change, never a before/after of two separately-taken numbers.
`asan_pool.c` is the row-pool stress case (resizes under a full pool), and
`ptyread.c` isolates the read path against a real PTY (see below).

Each prints cols/rows/cursor/modes/scrollback plus an FNV hash of **every cell**
of scrollback and grid and of every response byte emitted. Results 2026-08-04:

- all ten benchmark workloads: identical
- `torture.bin` (wrap edges, CSI quirks, alt screen, OSC, malformed UTF-8) at
  six grids from 5x3 to 244x56 and chunk sizes 1/3/7/4096/65536: **30/30 identical**
- 200 randomised escape-soup streams at random grids and chunks: **200/200 identical**

Chunk size matters: at chunk=1 every multi-byte character is split across a
`feed()` call, which is the only way to exercise the UTF-8 carry-over path.

Core throughput after the port (47x201, best of 3):

| workload | Swift | C | |
|---|---|---|---|
| unicode | 96 | 493 MB/s | 5.1x |
| sgr_fg | 76 | 321 | 4.2x |
| doomstream | 110 | 422 | 3.8x |
| cursor_motion | 110 | 353 | 3.2x |
| sgr_truecolor | 131 | 365 | 2.8x |
| scroll_region | 317 | 557 | 1.8x |
| alt_screen | 354 | 481 | 1.4x |
| light_cells / dense_cells / long_lines | | | 1.3x |
| binary | 118 | 125 | 1.1x |

Live app on the DOOM stream: 92 -> 250 MB/s on 2.8x less CPU. Suite vs Ghostty
nightly at a matched grid: 2.618 s / 3.72 CPU-s against 3.998 / 7.19 — from
1.13x behind to 0.65x ahead.

## Shared blank rows: TRIED, MEASURED WORSE, REVERTED

Ghostty still leads `alt_screen` (1.45x), `long_lines` (1.39x) and
`scroll_region` (1.21x) — all row-movement bound — and `perf` put 29.6% of
`scroll_region` in `memmove`. The obvious read was that the C port gave up the
Swift version's shared-blank-row copy-on-write and pays a fill per scrolled row.

**That was wrong.** Implementing refcounted shared blank rows (differential-clean
on all workloads, the torture stream and 200 fuzz streams, and ASan-clean across
4000 ops with 108 resizes) measured:

| | scroll workloads | hot path |
|---|---|---|
| shared blank rows | alt_screen 1.05x, scroll_region 1.02x, long_lines 1.01x | sgr_fg **0.77x**, unicode **0.72x**, cursor_motion **0.72x**, doomstream **0.77x** |

A 1-5% gain where it was supposed to help, and a **23-28% loss** everywhere else,
because `put_scalar` then tests `row->shared` on *every character* while the run
fast path only pays it once per run. Net worse; reverted. Do not retry it in
this shape.

The Row-array rotation *was* part of it: a call-graph profile splits
`scroll_region`'s 30% memmove into 19% `grid_rotate_in` (the rotation) and 7%
`row_blank` (the cell fill). But neither was the biggest cost — see below.

## The scroll cost was the ALLOCATOR, not the copying

`01_light_cells` — 1.5 M short lines, so 1.5 M line feeds — ran at **25 MB/s**
while every other workload managed 270-560. Profiling it puts **62% of the run
in the kernel** and only 12% in the emulator: `do_anonymous_page`,
`kernel_init_pages`, `handle_mm_fault`. It took **226,305 minor page faults** to
push 10.9 MB through.

Every line feed frees one row buffer and allocates another of the same width.
When the freed row goes to scrollback the two are separated by ~2000 intervening
rows, so glibc cannot pair them: the FIFO churn across that ~6 MB working set
makes it grow and trim the heap, and each trip back costs a fault plus a
kernel-side page zero.

The fix is a **row-buffer pool** (`row_release`/`row_take`) — released buffers of
the current width go on a stack instead of to `free`, and `row_blank` takes from
it. Two details are load-bearing:

- **Size it to `SB_SLACK`, not to the steady state.** Scrollback trims in
  batches: 512 rows are freed at once and the next 512 line feeds each want one
  back. A 64-slot pool absorbed an eighth of the batch and bought only 8%; at
  `SB_SLACK + 64` the same change is 4.3x.
- **Keep the pool off the struct.** A `Cell *pool[576]` array inline in
  `StarlingTerm` measured 6-10% *slower* on workloads that never scroll.

Result (best of 5, `-O2`, 47x201) — faults on light_cells: 226,305 -> **4,773**:

| workload | before | after | |
|---|---|---|---|
| light_cells | 24.8 | 105.6 MB/s | **4.26x** |
| dense_cells | 260.4 | 628.4 | 2.41x |
| alt_screen | 475.3 | 947.1 | 1.99x |
| long_lines | 433.0 | 854.2 | 1.97x |
| binary | 123.3 | 229.3 | 1.86x |
| sgr_truecolor / scroll_region / sgr_fg | | | 1.14-1.16x |
| unicode / cursor_motion / doomstream | | | 0.98-1.08x |

Differential-clean against the Swift original on all 12 streams, the torture
stream at 30 grid/chunk combinations, and 200 fuzz streams; ASan/UBSan/LSan
clean over 60 k ops with 618 resizes that change the width under a full pool.

## The scroll cost, part two: blanking scales with WIDTH — extent tracking

The pool fixed the allocator; the memset it left behind scales with row
width. At 478 columns (native-4K fullscreen protocol), light_cells' 1.5 M
line feeds moved 11.5 GB of blanking for rows carrying ~7 characters, and
ptyread mode 4 put the emulator alone 40% past the pty read floor — the
live 1.34x loss reproduced with no compositor in the room.

Each row now carries `used` (its written extent) and `tail_bg`, with the
invariant that `cells[used..cols)` are exactly the blank cell at `tail_bg`.
Pool entries keep both; recycling fills only `[0, used)` and skips even
that when the pooled tail's background matches the requested one.
Erase-to-end SHRINKS the extent instead of writing (two branches — the
matching-background one stores only up to the old extent; the differing one
must store the full span and can only pull the tail down to the cursor,
because below it may sit old-background blanks that are content now).
Memory stays byte-identical to the full-width code: 10 workloads x 3
grids, the 478-col corpus, torture at 30 grid/chunk combos and 400 fuzz
streams hash identical; ASan/UBSan/LSan clean through the pool-resize
stress.

`ab.sh` (same flags, best of 5): light_cells 1.29x at 201 cols, **1.62x at
478**; binary 1.74x / **5.7x** (it was blank-fill bound at width); scroll
region 1.06/1.16x, alt_screen 1.08/1.13x, dense 1.08/1.01x; sgr/unicode
inside the layout lottery below. Live: 4K-native suite 3.663 -> 3.360 s
(0.63x of the nightly), light_cells a dead tie at the pty floor (0.406 vs
0.406, was 1.34x); 1080p wall unchanged, CPU 3.42 -> 3.22.

### Beware: ±10-16% of this benchmark is code LAYOUT, not code

The first measurement of the pool showed `doomstream` at 0.87x and
`cursor_motion` at 0.93x — apparent regressions on workloads the change cannot
touch. Rebuilding the *identical* code with `ROW_POOL_MAX 0` reproduced them,
which rules out the pooling. Adding `-falign-functions=64 -falign-loops=32`
turned both into gains, and moved the *baseline* by up to 10% in each direction.

`starling_term_feed` is one big inlined byte-dispatch loop, and its performance
moves with where the linker happens to put it. Pin alignment on both sides before
believing any single-digit difference here. Do not ship the align flags to chase
it: they helped this binary and hurt the baseline, which is the signature of a
layout lottery, not an optimization.

## Where the time actually goes in the live app — it is NOT the core any more

**Compare terminals in GNOME, not on the Starling desktop.** `run-gnome.sh` runs
the suite in a GNOME Wayland session for either terminal: ours through the GTK
build (`STARLING_APP_GTK=1`, so it is an ordinary Wayland client like the one it
is measured against), Ghostty with `-e`. Running ours on the Starling shell and
Ghostty somewhere else compares two compositors as much as two terminals. The
grid is part of the workload and must match: size ours with
`STARLING_WINDOW_W/H` and Ghostty with `--window-width/--window-height` (cells,
and it lands a few cells short — calibrate against the `grid` line each run
records in `meta-<label>.txt`) until both report 47x201.

The core wins above are real and do **not** reach the user. Measured that way —
`data/res-g{base,pool,ghnight}-*.txt`:

| | ours, before | ours, after | ghostty nightly |
|---|---|---|---|
| suite wall | 2.481 s | 2.470 s | 3.546 s |
| suite CPU | 3.53 | 3.51 | 4.49 |

A 4.3x core win moved the end-to-end suite by **1%**. The reason is that `cat`
and the pty line discipline, not the terminal, set the floor on exactly the
workloads the pool helps. Catting each stream through a pty into a null drain
(`script -qec 'cat …' /dev/null`) costs:

| workload | pty floor | ours | ghostty |
|---|---|---|---|
| light_cells | 0.40 s | 0.439 | 0.404 |
| scroll_region | 0.32 | 0.316 | 0.270 |
| long_lines | 0.10 | 0.134 | 0.090 |
| alt_screen | 0.09 | 0.108 | 0.068 |
| sgr_fg | 0.18 | 0.299 | 0.630 |

`light_cells` and `scroll_region` are pty-bound for **both** terminals — 1.5 M
newlines through `n_tty` with ONLCR is the cost, and no emulator can win it back.
Comparing the offline core against live wall time at the same grid gives the
core's real share of the critical path:

| escape-heavy (sgr_fg, truecolor) | row-churn (light_cells, scroll_region, alt_screen, long_lines) |
|---|---|
| core is **68-71%** of live time | core is **22-36%** |

So the earlier "critical path is 79% emulator core" no longer holds: the C port
plus this change moved the bottleneck off the core for row-churn work. **Further
core optimization for scrolling has nowhere to land.**

## The read path: reading and parsing on one thread cost transport PLUS parse

`ptyread.c` isolates the read path — a real PTY, a real `cat`, the real core, no
compositor — so the terminal's own cost can be separated from the transport's.
Its modes are: `2` read and discard (the transport floor), `0` what TerminalApp
did (read, then parse, on one thread), `3` reader thread + parser thread over a
bounded ring.

| workload | floor | serial | split | ghostty (live) |
|---|---|---|---|---|
| alt_screen | 0.069 | 0.101 | 0.078 | 0.068 |
| long_lines | 0.086 | 0.115 | 0.094 | 0.090 |
| sgr_truecolor | 0.239 | 0.463 | 0.317 | 0.463 |
| sgr_fg | 0.155 | 0.336 | 0.241 | 0.630 |
| light_cells | 0.382 | 0.400 | 0.391 | 0.404 |
| binary | 0.291 | 0.318 | 0.320 | 1.224 |

**Ghostty sits exactly on the transport floor** where we did not (alt_screen
0.068 vs a 0.069 floor; long_lines 0.090 vs 0.086). It is not parsing faster —
our core beats it 2-4x offline — it is parsing *while* the PTY drains. A single
thread that reads then parses stops draining the PTY while it parses, so the
shell blocks on a full buffer and wall time is transport **plus** parse.

Splitting the reader from the parser (`ChunkRing` in `Pty.swift`, 8 x 64 KB
slots, blocking both ways so backpressure is unchanged) makes it
max(transport, parse). Live, GNOME, 47x201, best of 3:

| | serial | split | ghostty nightly |
|---|---|---|---|
| suite wall | 2.470 s | **2.199** | 3.546 |
| suite CPU | 3.51 | 4.12 | 4.49 |

**0.89x wall overall**, and the workloads with headroom move most:
sgr_truecolor 0.70x, cursor_motion 0.75x, sgr_fg / long_lines 0.77x, alt_screen
0.78x. Nothing regressed. Against Ghostty we go 0.70x -> **0.62x wall**, and its
two biggest leads shrink: alt_screen 1.59x -> 1.24x, long_lines 1.49x -> 1.14x.

**The trade is CPU: +17% (3.51 -> 4.12 CPU-s)**, because the same work now runs
on two cores plus ~9,000 handoffs. Still below Ghostty's 4.49, but the margin
there went from 22% to 8%. Worth knowing before assuming this is free.

Two things that did NOT work, both measured before being believed:

- **Draining the PTY to EAGAIN and feeding once per batch** (mode `1`) coalesces
  feeds 5-900x and is *slower on every workload* (alt_screen 0.104 -> 0.108,
  truecolor 0.471 -> 0.533). A faster drain means more, smaller reads: mean batch
  fell from 11 KB to 60 B on light_cells. Batch size is an *output* of how fast
  the reader keeps up, not a knob.
- **A bigger read buffer.** The kernel caps a PTY read at `N_TTY_BUF_SIZE`; an
  `strace` of the live app found 8,545 of 8,676 reads returned <=4096 B despite a
  64 KB buffer. The buffer size is nearly irrelevant.

## Where it ends: within ~7% of the kernel's floor, and the repaint is 6%

With the split in, the read path is done. Best of 3 at 47x201:

| workload | transport floor | split (no compositor) |
|---|---|---|
| alt_screen | 0.068 | 0.073 |
| long_lines | 0.089 | 0.090 |
| dense_cells | 0.148 | 0.158 |
| scroll_region | 0.298 | 0.290 |

Reading and parsing now costs **within ~7% of reading and discarding**, and
Ghostty sits on that same floor (alt_screen 0.068, exactly the floor). Its
remaining leads are that last few percent plus the repaint, not a faster parser.
**There is no large lever left in the read path** — the terminal is transport
bound, which is where it should be.

## The "below the floor" ghostty number was a clock artifact — and the real
## live gap was a futex convoy in the ring (2026-08-11, round 10)

Round 9 read ghostty's dense_cells/ascii walls as *below* the read(2) floor
and concluded its io_uring transport buys what no read(2) pattern can. Both
halves of that were wrong, and the error was the CLOCK:

- The harness's wall starts before `cat` execs and ends when the READER sees
  EOF. The bench metric — `time cat` inside the terminal — is the WRITER's
  wall: it stops at the last accepted write, before the final drain, and
  contains no exec. The two differ by ~5-10 ms on a 30 MB stream.
- Re-measured on the writer's clock (`PTYREAD_TIME=1`, or `PTYREAD_CMD=` a
  wrapper that stamps `$EPOCHREALTIME` — 2 dp from `/usr/bin/time` is not
  enough), modes 2, 4 and 8 are all 0.14-0.16 on dense_cells: identical to
  ghostty live. **No consumption pattern beats another on the writer's
  clock, and nothing is below the floor.**
- strace of the live nightly during the cat: its pty data path is plain
  `read(2)` on its termio thread — the 3.1k `io_uring_enter` calls are its
  event loop, not the transport. Its 6.3 KB mean reads come from parsing
  *between* reads (natural pacing); replicating the batching artificially
  (modes 6, 8, 9) reproduces the batch sizes and moves the wall nowhere.
- Modes that are dead ends, measured: single-shot io_uring reads (0.164 vs
  the 0.143 read(2) floor — the io-wq punt path costs more than it saves,
  `IOSQE_ASYNC` doubles batch size and stays slow), multishot
  `IORING_OP_READ_MULTISHOT` (never posts a CQE on a pty — no
  `FMODE_NOWAIT`; the harness now kills `cat` on abnormal exit so this
  fails visibly instead of wedging `waitpid`), fixed pacing ≥50us (batches
  pin at the 4 KB ldisc buffer and throughput becomes 4096/pace — there is
  no big kernel buffer to exploit, only ~68 K of flip-buffer runway).

What WAS real: the live app measured ~10 ms/cat over its own harness pattern
on the writer's clock. A per-thread futex census (`strace -f -e trace=futex`)
put the surplus in the reader+parser pair — ~7 futex ops per ring handoff
against the ~2 a handoff needs. That is the glibc "hurry up and wait" convoy:
`ChunkRing` signalled with the mutex HELD, so the woken thread immediately
blocked on the mutex (glibc dropped wait morphing years ago). Fix: track
whether the other side is actually waiting, signal only then, and signal
AFTER unlock. dense_cells live went 0.163 -> 0.157 (same-session 5-sample
medians); with repaints suppressed the app now measures 0.153 — exactly the
mode-4 harness number, i.e. the app adds nothing over its own architecture.

What remains vs ghostty (~0.143-0.151 fresh-launch) is the split design
itself: they parse inline on the read thread, so no second thread perturbs
the writer->kworker->reader chain during floods. Mode 9 (256 K slots + a
~300us linger, 4x fewer handoffs) proves handoff COUNT is not the cost —
batches grew to 261 KB and the wall did not move. Mode 10 (adaptive inline:
parse on the reader thread when the drain went dry and the ring is empty,
publish when the slot fills first) engages correctly — dense runs mixed,
sgr_fg goes 100% through the ring — but its gain is inside run-to-run noise,
so it is NOT wired into the app. The shipping change from this round is the
wake discipline alone; `STARLING_BENCH_NOREPAINT=1` is now a permanent
diagnostic gate in TerminalApp so the parse/render split stays measurable
without a patched build.

The repaint was measured by gating `_scheduleRepaint` on an env var, building
both ways and running the suite on each — **on the shipping DRM host**, not
through the GTK harness, because GTK presents through a software pixman blit
that the dma-buf path does not pay (8.9% of wall through GTK vs 6.4% on DRM;
profile the GTK host and ~a third of the "repaint" is that blit).

Starling DRM host, 60x244, best of 3: **repaint is 0.134 s of 2.099 s wall
(6.4%) and 1.09 of 3.93 CPU-s (28%)** — i.e. mostly parallel with the parse, as
it has been since the 60 Hz cap. It is not evenly spread: `sgr_fg` **20.7%**,
`long_lines` 11.8%, `sgr_truecolor` 10.1%, but `unicode` 0.9% and
`scroll_region` ~0. The expensive ones are the style-heavy streams, where a row
becomes many `TextSpan`s and the text layout scales with the run count.

So the ceiling on any repaint work is ~6% of wall overall, and the widget build
itself is only ~6% of process CPU (`BeginFrame` subtree; `_rowWidget` 0.9%,
TextStyle copy/compare/destroy ~1.5%). Worth doing only if `sgr_fg`-shaped
workloads matter specifically; a content-keyed row-widget cache is the obvious
shape, but note the SDK remounts elements rather than updating them, so returning
an identical `Widget` may not short-circuit anything — measure that assumption
before building on it.
