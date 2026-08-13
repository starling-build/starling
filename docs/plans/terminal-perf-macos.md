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

Lever 1 is done. Against ghostty 1.3.2-main+51ed437cd, same machine, same
grid, AC power, best of 3:

| | ours | ghostty | |
|---|---|---|---|
| suite wall | **2.505 s** | 2.656 s | **0.94x** |
| suite CPU | **3.85 s** | 4.67 s | 0.82x |

which is the first round we finish ahead. The four we win are 10_binary
(0.40x), 03_sgr_fg (0.75x), 04_sgr_truecolor and 08_scroll_region (0.96x);
the three we lose worst are 05_unicode (1.77x), 07_alt_screen (1.42x) and
01_light_cells (1.40x). Two of those three are the workloads the inline
reader gave up to win the rest — see below — so they are the next lever,
not a surprise.

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

## Lever 2 — the glyph atlas painter (CPU, frame rate, and correctness)

The atlas landed in f3aa62c and nothing calls it yet. On the cat suite it can
win at most the 14% that rendering costs — but that is not why to do it:

- **CPU halves.** 2.5 of our 5.26 CPU-seconds are rendering, and on a laptop
  that is battery and fan, not just a number.
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

## Lever 3 — `01_light_cells`, the core's outlier

Core-alone throughput on this machine, MB/s:

    alt_screen 744   long_lines 652   dense_cells 516   scroll_region 502
    truecolor  352   cursor_motion 339   unicode 336   binary 324   sgr_fg 294
    light_cells 81

`01_light_cells` is 1.5 M short lines — 1.5 M line feeds — and it runs 4x
slower per byte than anything else. On Linux this was the allocator (226 k
minor faults, fixed by the row pool: 25 -> 106 MB/s). At 81 MB/s here the same
workload is still the outlier, so the question is whether the pool's assumptions
survive libmalloc. Profile it on macOS before assuming the Linux fix carries.

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

1. ~~ptyread mode 10~~ and ~~Lever 1~~ — done, `af2d426`.
2. **Lever 2**, the painter. Now the biggest item: the CPU win, the frame
   rate, and the three rendering bugs above.
3. **Lever 3**, `01_light_cells` — and it is now one of the two workloads we
   lose worst (1.40x), so profiling it on macOS matters more than it did.
4. `05_unicode` at 1.77x is our worst ratio. It is the workload the inline
   reader gave up, and the one carrying the per-run paragraph split.

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
