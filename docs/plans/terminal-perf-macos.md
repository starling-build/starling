# Where the macOS terminal's time goes, and what to do about it

A plan, written against measurements taken 2026-08-12 on the M1 Pro at 201x47
after the reader linger (c54f02e) and the unicode run path (4934555) landed.
The round it follows is `docs/perf/terminal-vs-ghostty-macos-2026-08-12/`.

Every number here was taken on **AC power, on a quiet box**. Both matter and
neither is pedantry — see *Measuring at all* at the end, which cost this round
three invalid suites before the first valid one.

## The decomposition

The suite is 442 MB of corpus through ten workloads. Three measurements of the
same ten, on the same machine and grid:

| | wall | what it includes |
|---|---|---|
| emulator core alone (`bench_st`, no pty, no UI) | **1.24 s** | parse + grid writes |
| live, repaints suppressed (`STARLING_BENCH_NOREPAINT=1`) | **2.76 s** | + the PTY read path |
| live | **3.20 s** | + rendering |

Read down the column and the shape of the problem is plain:

- **Rendering is 14% of wall and 48% of CPU** (5.26 CPU-s live against 2.76
  with repaints off). It runs on the main thread in parallel with the parse
  thread, so it costs far more energy than time. A *perfect* renderer — zero
  cost — would take the suite from 3.20 s to 2.76 s and no further.
- **The emulator core is 1.24 s**, 39% of wall.
- **Everything else — ~1.5 s, the largest single term — is the PTY read
  path.** Not parsing the bytes: fetching them.

That last line is the finding this plan is built on, and it is the same
finding as the last round's, one layer down: the macOS pty hands back ~1 KB per
`read(2)` no matter the buffer size, so the cost is per-syscall and per-handoff,
not per-byte.

## Where it ended up

Levers 1 and 3 are done. Against ghostty 1.3.2-main+51ed437cd, same machine,
same grid (both `meta-*` verified at `grid 47x201`), AC power, best of 3:

| | ours | ghostty | |
|---|---|---|---|
| suite wall | **2.230 s** | 2.961 s | **0.75x** |
| suite CPU | **3.52 s** | 8.00 s | 0.44x |

We take nine of ten, and burn 44% of the CPU doing it:

    10_binary 0.32   03_sgr_fg 0.70   01_light_cells 0.72   02_dense_cells 0.80
    08_scroll_region 0.85   09_long_lines 0.86   04_sgr_truecolor 0.88
    06_cursor_motion 0.97   05_unicode 1.00   07_alt_screen 1.13

`07_alt_screen` is the only loss. `01_light_cells` was 1.40x before the
sliding grid window and is 0.72x after it; `05_unicode` was 1.77x when this
plan was written, 1.42x after Lever 1, and is a tie now.

**Ghostty's own three published tests, same session, are three of three** —
ascii cat 0.90x, unicode cat 0.98x, DOOM-Fire 1.11x, on 40-60% of their CPU.
That set is the one that found the width-cache bug below; the suite did not.
See `docs/perf/terminal-vs-ghostty-macos-2026-08-12/report.md`.

The ghostty side had to be retried once: it came up at **17x49** instead of
47x201, which at a corpus generated for 201 columns wraps 4x and makes ghostty
read ~2.4x slow — indistinguishable from a win without reading `meta-gh.txt`.
`bench.sh` still does not enforce this; check it every round.

## Lever 1 — collapse the reader/parser split on Darwin — DONE

`test/bench/core/ptyread.c` runs a real pty, a real `cat` and the real core
through each transport shape. Best of the run, 201x47:

| mode | 03_sgr_fg | 08_scroll_region | whole suite |
|---|---|---|---|
| 0 — blocking reads, **inline parse, one thread** | **0.418** | **0.164** | **2.345** |
| 1 — poll + non-blocking drain, one feed per batch | 0.587 | 0.233 | 3.342 |
| 9 — ring + drain + linger — **what ships** | 0.575 | 0.253 | 2.901 |
| 4 — ring + drain, no linger (before c54f02e) | 0.740 | 0.361 | — |

**Doing less work in parallel is 19% faster.** The thread split exists to
overlap transport with parse, and on this platform it pays a condition-variable
round trip per kilobyte to overlap a kilobyte of parse: at a 1 KB batch the
parse is a few microseconds and the handoff is tens.

Two workloads go the other way — `01_light_cells` and `05_unicode` — and they
are exactly the two where the core is slowest per byte (81 and 336 MB/s against
500-750 for the rest), so there is enough parse work to be worth overlapping.

**The obvious fix for that does not work, and this was measured twice.** Parse
inline while the parser keeps up, hand to the ring when it does not:

- `ptyread` mode 10 flips per slot on a cheap proxy (drain ended dry and the
  ring is empty). It came out **worse than either fixed choice** on all five
  workloads tried — 03_sgr_fg 0.431 against inline's 0.402 and the ring's
  0.552.
- A hysteretic one-way handover on measured cost — time the read and the feed,
  switch once a 512 KB window says parse is the larger term — collapsed onto
  the ring's numbers live (suite 2.878 s against the ring's 2.931 and inline's
  2.514), because with data always queued a read returns instantly and the
  parse always looks dominant.

And the signal itself has no predictive power. Median parse/read ratio over
512 KB windows, against which design actually wins:

    03_sgr_fg        1.81   inline wins by 28%
    01_light_cells   1.47   ring wins by 37%
    05_unicode       1.00   ring wins by 21%
    08_scroll_region 0.95   inline wins by 29%
    02_dense_cells   0.86   inline wins by 28%

The workload with the highest parse share is one inline wins outright. So
Darwin ships the fixed inline reader and keeps the two regressions; whatever
separates those two workloads, it is not the balance between reading and
parsing, and a switch rebuilt on that signal will fail the same way.

Shipped as `af2d426`: suite 2.931 -> 2.478 s (-15.5%), CPU 4.99 -> 3.86
(-23%). Shutdown moved to a SIGUSR2 sent to the reader thread, installed via
`sigaction` with sa_flags 0 — `signal(2)` on Darwin sets SA_RESTART, which
resumes the blocking read instead of failing it with EINTR.

The live app's parse-only wall matches the harness workload for workload —
03_sgr_fg 0.562 live against mode 9's 0.575, 08_scroll_region 0.251 against
0.253 — so the harness is predictive, and mode 0's numbers are what the app
would land on.

Risks to hold in mind, none of them showstoppers:

- Parsing on the reader thread takes the emulator lock per read. Contention
  with the UI's grid snapshot measured 9 samples in 11 226 last round, so this
  is cheap — but it is per ~1 KB now, not per 256 KB.
- `onExit` ordering: the ring guarantees every byte is parsed before the exit
  message. An inline parser has to keep that property.
- Linux and Windows keep the ring; this is a Darwin path.

Expected: the suite's parse-only wall 2.76 s toward mode 0's 2.35 s, i.e. the
live suite from 2.99 s to roughly 2.6 s.

## Re-measured after Lever 1 — and two of the levers below moved

Everything from here down was written against the 2026-08-12 morning numbers.
Three of its premises did not survive re-measurement on the same machine that
evening, so read this section before acting on any of them.

**The decomposition is no longer 39/14/47.** Same suite, same grid, AC power,
best of 3, with the inline reader in:

| | wall | share |
|---|---|---|
| live | **2.420 s** | |
| repaints suppressed (`STARLING_BENCH_NOREPAINT=1`) | 2.366 s | |
| → rendering | **0.054 s** | **2.2% of wall, 48% of CPU** |
| core alone, per workload, summed | ~1.01 s | 42% |
| → PTY read path | ~1.36 s | 56% |

Rendering was 14% of wall before Lever 1 and is **2.2%** after it. Nothing
about the renderer changed: the inline reader put parse on the reader thread,
so rendering now overlaps it almost entirely, and the 60 Hz repaint cap was
already keeping frame count off the critical path. A *perfect* renderer would
take the suite from 2.420 s to 2.366 s and no further.

**The pty's 1 KB grain is a hard kernel limit.** `ptyprobe` (in this round's
data) histograms every read: `max=1024` on all ten workloads, mean 1009-1024.
The 442 MB suite is therefore ~432 000 producer/consumer round trips and no
buffer size changes that. Putting the pty slave in **raw mode (OPOST off) makes
the transport 1.8x faster** — 3.79 µs/read against 6.76 — because the tty's
output path goes bulk instead of character-at-a-time. It is not a lever we
have: the shell sets its own termios the moment it starts, and ONLCR is
required for correctness. Ghostty pays the identical floor.

## Lever 2 — the glyph atlas painter (CPU, frame rate, and correctness)

**It cannot move the benchmark.** Rendering is 2.2% of the suite's wall (above),
so a free renderer is worth 0.054 s. Do it for the other three reasons, which
are undiminished — and do not schedule it expecting a throughput result:

- **CPU halves.** 1.80 of our 3.77 CPU-seconds are rendering — 48%, unchanged
  as a share even though the wall cost collapsed — and on a laptop that is
  battery and fan, not just a number. The atlas landed in f3aa62c and nothing
  calls it yet.
- **Frame rate.** DOOM-Fire is 803 fps against ghostty's ~940-1030, and a
  sample puts 72.9% of that wall inside the paragraph shaper — re-shaping a
  monospace grid whose answers are all known in advance.
- **It makes the grid structural.** Today the row is one shaped paragraph and
  the shaper places every glyph by the advance of whatever font it resolved
  in. That is why CJK walked off the grid (below). Per-cell placement cannot
  drift by construction.

The atlas as committed deliberately excludes wide characters, clusters, colour
emoji, underline and reverse — which is precisely the set that is broken today.
So the painter needs both halves: the atlas fast path for ordinary cells, and a
fallback that still places by cell rather than by advance.

### Does the atlas earn its second texture? Yes — measured 2026-08-13

The engine already has a glyph atlas (Impeller's typographer), so ours is a
second one layered over it. `STARLING_TERM_ATLAS=2` tested the obvious
alternative: cache one laid-out `Paragraph` per distinct glyph and Paint it at
each cell — engine rasterisation, engine atlas, our placement, no second
texture. What it gives up is batching (a draw op per cell instead of one
`drawRawAtlas`) and it pays a bounded saveLayer + srcIn colour filter per cell
to tint a white glyph, because a paragraph bakes its colour in.

DOOM-Fire, 600 frames x 3 reps x 2 interleaved rounds, on battery (so compare
across the arms, not against other days' numbers):

    Text path (off)   1.45 1.46 1.38 / 1.52 1.48 1.48   mean 1.46 CPU-s
    atlas      (=1)   0.88 0.89 0.90 / 0.90 0.92 0.92   mean 0.90 CPU-s
    paragraphs (=2)   1.55 1.38 1.35 / 1.70 1.60 1.60   mean 1.53 CPU-s

Mode 2 renders correctly (probe diff vs mode 1: 0.097% of pixels, all of it
the ▓▒░ shades drawn from the font's dither glyphs instead of our procedural
greys) — and loses exactly as predicted: the per-cell layer costs more than
the whole second texture, landing back at the Text path's CPU. The mode stays
in-tree as the recorded answer; do not re-run it expecting otherwise. If the
second texture ever has to go, the path is the engine's positioned-glyph op —
`DlCanvas::DrawText(std::shared_ptr<DlText>)` exists, but the Swift bridge
would need a new entry point taking glyph ids and positions, giving per-cell
placement AND the engine's atlas with neither a second texture nor a per-cell
layer.

## Lever 3 — `01_light_cells` — DONE, and it was never the allocator

The premise was wrong twice over, and both errors are worth keeping.

**The 81 MB/s was a harness artifact.** `bench_st` fed the corpus file
verbatim, but a corpus file holds bare LFs and the core never sees those live:
a pty's line discipline expands LF to CRLF on the way out. Fed raw, every LF
moved down a row without returning to column 0, so the text staircased
diagonally and left each row ~100 columns wide instead of ~7 — a different
workload on the same bytes, reported as a core throughput number. Corrected,
the same core does **196 MB/s**, not 81. `bench_st` now applies ONLCR itself
(`BENCH_RAW=1` opts out, for a capture taken *from* a pty); see
`test/bench/core/README.md`.

**What was actually slow was `grid_rotate_in`.** Every line feed outside a
scroll region removed row 0 and memmoved the whole `Row` array down one —
1128 bytes per feed, 1.7 GB over this workload's 1.5 M feeds, and a profile put
68% of the run inside that one memmove. The grid is now a **sliding window**
into a block with `GRID_SLACK` rows of headroom, so the whole-screen scroll is
a pointer bump and the move happens once per 1024 feeds. Scroll *regions* still
move rows: sliding would drag the rows outside the region with it.

Core throughput, corrected corpus, before → after:

    light_cells 196 -> 315 (+60%)   long_lines 700 -> 745   binary 426 -> 450
    unicode     365 -> 383           dense_cells 708 -> 730
    the rest within ±1%

Live suite **2.420 -> 2.335 s (-3.5%)**, every workload flat or better:
01_light_cells -18.3%, 05_unicode -7.7%, 06_cursor_motion -6.9%.

## The reader question is closed — inline wins everywhere now

Lever 1 shipped the inline reader knowing it lost two workloads, and this plan
recorded that the parse/read ratio did not predict which. It did not, because
the split was never about the transport: **it was the core's cost on those two
streams**, and the sliding window removed it. Re-measured through
`test/bench/core/ptyread_mac.c` (real pty, real `cat`, real core) against the
faster core:

    workload           inline    ring    spin
    01_light_cells      0.099   0.091   0.094
    05_unicode          0.302   0.315   0.299
    07_alt_screen       0.194   0.218   0.219
    03_sgr_fg           0.399   0.538   0.562
    08_scroll_region    0.156   0.253   0.268

05_unicode has flipped to inline (it was the ring by 21%), and 01_light_cells
has narrowed from 37% to 8%. Do not reopen the adaptive-switch idea.

**And the condvar was never the ring's cost.** `ptyread_mac` mode 11 is a
lock-free SPSC byte ring — two atomic indices, release/acquire, a bounded
spin, an 8 MB buffer, no condition variable anywhere in the hot path. It lands
*on top of* the condvar ring's numbers, workload for workload. The reason is
visible in its own counters: mean feed 1088 B and millions of empty polls. The
consumer starves because the pty delivers 1 KB at a time, so there is nothing
to overlap. What actually separates the designs is **pacing**: an eager reader
returns to `read(2)` instantly and blocks on an empty queue every time (the
`ptyprobe` read-and-discard floor is *slower* than read-and-parse), while the
inline reader's parse gives the writer exactly long enough to refill.

## Lever 4 — engine-side, not chased

354 `CVDisplayLink` threads created in a 15 s sample, one per start/stop of the
embedder's display link. Idle, so little CPU, but each start is a thread spawn
and up to a frame of latency. Worth knowing before anyone reads a frame-pacing
number on this platform.

## Lever 2 also has correctness riding on it

Since this plan was written, three rendering bugs were fixed by hand in the
row painter, and all three are the same bug underneath — the row is one shaped
paragraph, so the text engine decides where each glyph lands:

- Wide glyphs came back at the fallback font's own advance (CJK at 1 em
  against our 1.2 em cell pair), so every column after a CJK character was
  wrong. Fixed with a measured per-scalar `letterSpacing` (`b0dc7d5`).
- Fallback resolution inside a paragraph is monotonic, so a row needing two
  families in descending order lost everything from the first fallback glyph
  on — which is why `cat`ing our own 05_unicode corpus showed no CJK at all.
  Fixed by giving each run its own paragraph (`c2ecbf3`), at +7.8% on
  05_unicode.
- Upstream's braille face is 0.7324 em against a 0.6001 em grid, so a spinner
  still shifts the rest of its row.

None of these can happen to a painter that places each cell itself, and the
`letterSpacing` correction and the per-run paragraph split both come back out
when that lands. The remaining visible defect — a wide glyph sits
left-aligned in its two columns, so CJK reads spaced-out rather than tight —
needs per-cell placement to fix at all.

## Ordering

1. ~~ptyread mode 10~~, ~~Lever 1~~ (`af2d426`), ~~Lever 3~~ (the sliding grid
   window) and ~~`05_unicode`~~ (the width cache) — done.
2. **Lever 2**, the painter — for CPU, frame rate and the three rendering bugs.
   Not for the suite: it is worth 0.054 s (see above). DOOM-Fire is the test
   that would move, and we now lead it 1099 fps to 990.
3. `07_alt_screen` at 1.13x, the only loss left. Its core is already 763 MB/s,
   so there is ~0.024 s in it at most — it is transport, not compute.

Everything else we win or tie: 10_binary 0.32x, 03_sgr_fg 0.70x,
01_light_cells 0.72x, 05_unicode 1.00x.

## `05_unicode` — DONE, and the suite is what hid it

`width_lookup`'s eight-entry MRU span cache was **43.6% of the whole core** on
ghostty's published unicode corpus. Eight entries hold every script a mixed
line touches at once, which is why the structure looked right — but a line
does not touch its scripts once, it CYCLES them, and a cycle is what MRU
handles worst: each script is evicted to the back exactly in time for its next
use, so every transition missed, paid both binary searches over ~460
intervals, and shifted seven entries. Now direct-mapped on the codepoint's
512-wide block: 128 slots, the whole BMP alias-free, each slot re-checking its
stored interval so a collision costs a recompute and never a wrong answer.

    core, MB/s        before   after
    unicode_150mb      282.3   458.8   +62.5%
    05_unicode         381.7   480.5   +25.9%
    everything else               ±2%

Live: suite `05_unicode` 0.356 -> 0.282 s (1.22x -> **1.00x**, from 1.77x when
this plan was written), and ghostty's published unicode cat 1.300 -> 0.745 s.

**The 10-workload suite could not see this.** It ranked `05_unicode` a 1.22x
also-ran while the published unicode cat — 150 MB of nothing but mixed script
— was at 1.71x and had regressed 56% behind this branch's own earlier build.
One line of mixed script among ten workloads averages the cost away. When the
two disagree, the concentrated test is the one telling the truth; run
`docs/perf/terminal-vs-ghostty-macos-2026-08-12/published.sh` alongside the
suite, not instead of it.

## Measuring at all

Three suites were thrown away today before one was valid, each for a reason
worth writing down, because each produced a *plausible wrong number* rather
than an error:

- **The wrong ghostty.** `/Applications/Ghostty.app` is 1.3.1 stable; the round
  measures the 1.3.2-main tip build in `~/dev/ghostty-tip`. The stable build
  reads ~2.4x slower, which looks exactly like a win.
- **Battery.** The machine dropped to battery mid-session. Ghostty, at 3x our
  CPU per byte, degrades far harder than we do — the ratio moved 2x with no
  code change.
- **A neighbour's build.** Another session started an iOS engine build on the
  same box; every core was busy and both terminals read 2.4x slow.
- **Ghostty's grid.** Ghostty came up at 49x17 once instead of 201x47. The
  corpus is generated for 201 columns, so at 49 it wraps 4x and ghostty reads
  2.4x slower — again, indistinguishable from a win without checking `meta-*`.

The harness should record what it measured rather than trusting the operator:
ghostty's `--version`, the power source, and a hard failure (not a warning) when
either side's grid is not the requested one.
