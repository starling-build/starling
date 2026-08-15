# Terminal core memory baseline — 2026-08-15

The first memory round. Every earlier round in `docs/perf/` measures how fast
the core drains bytes; this one measures what it costs to **hold** the result:
pure terminal state, no renderer, no pty, no Flutter, no font atlas.

It exists because libghostty published a memory comparison against
`alacritty_terminal` on exactly these payloads (empty screen, full screen, then
a deep scrollback of plain / unicode / heavy-styled / mixed), and a like-for-like
answer for our core needs a baseline that was taken before anyone starts tuning
for it.

Harness: `test/bench/core/bench_mem.c`, driven by `test/bench/core/mem-bench.sh`.
Core at `01e0647` (`release-terminal-0.1.0`), Apple M4 Max, macOS 26.6.1.

## Method, and the two traps it avoids

**One payload per process.** The obvious harness loops the payloads and samples
between them, and it flatters whichever runs first: freeing a 10k-row scrollback
returns rows to the allocator, not the OS, so the next payload fills a warm heap
and reports less memory for identical state. Each payload gets a cold process.

**The corpus is streamed, never materialised.** A generated payload held in one
big `malloc` would sit inside every number. Lines are built into a 64 KB feed
buffer — the app reader's chunk — and flushed, so at sample time the only large
live allocation is the terminal.

Lines are emitted **CRLF**, as a tty's line discipline delivers them. The ONLCR
trap that produced a bogus core outlier in `bench_st.c` bites harder here: bare
LFs staircase, wrap early, and the rows that reach scrollback stop matching the
lines that were fed, so the row count the table reports would be fiction.

Two numbers, answering different questions. `heap` is allocator bytes in use
(`mstats`, which aggregates every zone — `malloc_zone_statistics` on the default
zone misses the nano zone and undercounts a grid of small row buffers by most of
its size). `foot` is `phys_footprint`, what Activity Monitor shows: allocator
slack included, noisier, honest. `model` is computed from the core's own
structures — one `Row` (24 B) plus `cols × 16 B` of cells per retained row — so
`ovh = heap/model` is what the per-row allocation strategy costs.

No settle delay is needed: this core has no idle-time work, so post-feed **is**
steady state. That is not true of a core that compresses cold history in the
background, and the comparison harness will have to quiesce before sampling.

## Results

80×24, 10,000 lines fed, shipping build:

| payload | sb_rows | heap | foot | model | ovh | B/cell |
|---|---:|---:|---:|---:|---:|---:|
| empty   |    0 |  126 KB |  64 KB |  31 KB | 4.13 | 67.3 |
| screen  |    0 |  126 KB |  80 KB |  31 KB | 4.13 | 67.3 |
| plain   | 2282 | 3.35 MB | 3.65 MB | 3.01 MB | 1.12 | 18.2 |
| unicode | 2282 | 3.36 MB | 3.65 MB | 3.01 MB | 1.12 | 18.2 |
| styled  | 2282 | 3.35 MB | 3.67 MB | 3.01 MB | 1.12 | 18.2 |
| mixed   | 2282 | 3.36 MB | 3.65 MB | 3.01 MB | 1.12 | 18.2 |

80×24, same 10,000 lines, built at `SB_LIMIT=10000` so the whole payload is
retained:

| payload | sb_rows | heap | foot | model | ovh | B/cell |
|---|---:|---:|---:|---:|---:|---:|
| empty   |    0 |  318 KB |  64 KB |  31 KB | 10.41 | 169.7 |
| screen  |    0 |  318 KB |  80 KB |  31 KB | 10.41 | 169.7 |
| plain   | 9977 | 13.10 MB | 14.06 MB | 13.04 MB | 1.00 | 16.4 |
| unicode | 9977 | 13.10 MB | 14.07 MB | 13.04 MB | 1.00 | 16.4 |
| styled  | 9977 | 13.10 MB | 14.07 MB | 13.04 MB | 1.00 | 16.4 |
| mixed   | 9977 | 13.10 MB | 14.07 MB | 13.04 MB | 1.00 | 16.4 |

201×47 (the grid every throughput round uses), shipping build:

| payload | sb_rows | heap | foot | model | ovh | B/cell |
|---|---:|---:|---:|---:|---:|---:|
| empty   |    0 |  263 KB |  224 KB |  149 KB | 1.77 | 28.5 |
| screen  |    0 |  263 KB |  240 KB |  149 KB | 1.77 | 28.5 |
| plain   | 2259 | 9.28 MB | 10.72 MB | 7.47 MB | 1.24 | 20.0 |
| unicode | 2259 | 9.28 MB | 10.72 MB | 7.47 MB | 1.24 | 20.0 |
| styled  | 2259 | 9.28 MB | 10.72 MB | 7.47 MB | 1.24 | 20.0 |
| mixed   | 2259 | 9.28 MB | 10.72 MB | 7.47 MB | 1.24 | 20.0 |

## What it says

**Our memory is content-independent, and `styled` proves it.** Heavy styling —
a distinct truecolor fg and a 256-colour bg on every cell — costs *byte for byte
exactly* what plain ASCII costs (13,096,448 both). It has to: fg, bg and attrs
live inline in every `Cell` whether they are used or not, so a styled screen and
a blank one are the same 16 bytes per cell. Unicode adds 2,144 B for the whole
10k rows — the grapheme pool, and nothing else. This is the mirror image of a
core that interns styles per page: theirs pays a table and saves per cell, ours
pays per cell and has no table. Their `styled` payload should move; ours cannot.

**16.4 B/cell is the number to compare.** At matched depth the model is exact
(`ovh` 1.00): 16 bytes of cell plus ~0.4 B/cell of `Row` and allocator. Against
libghostty's 8-byte `Cell` that is ~2x before compression, and against LZ4'd cold
history at their stated 10–30% it is closer to 6–10x on the scrollback portion.
Nothing here is a tuning problem — it is the layout.

**The empty terminal is not free, and it scales with the scrollback *limit*, not
with use.** 126 KB at 80×24 shipping, 318 KB at a 10k limit, 263 KB at 201×47.
The scrollback ring's `Row` array is allocated up front (`(SB_LIMIT + SB_SLACK) ×
24 B` — the 8000-row difference between the two 80×24 builds is 192 KB of exactly
that), plus `GRID_SLACK` rows of grid headroom. An idle tab pays for the history
it is allowed to keep. This is the one row of the table where we would lose badly
to a core that allocates history in pages on demand.

**`screen` costs nothing over `empty`.** The live grid's cells are allocated at
create, so filling them is free. Right result, worth stating: it means our
"full screen" number is really the create number.

**The row pool shows up as overhead once trimming starts.** `ovh` is 1.00 when
nothing is trimmed (10k limit, 9,977 rows) and 1.12–1.24 when the cap is hit,
because `ROW_POOL_MAX` (576) recycled rows are held on the free list. At 201×47
that is up to 1.85 MB parked — 559 rows' worth in this run. Occupancy depends on
where in the trim cycle the sample lands, so it varies between 0 and 576 rows.
It is a deliberate throughput trade (see `test/bench/core/README.md`: shrinking
the pool brought the allocator churn straight back), but it is real held memory
and a memory-side comparison will be charged for it.

## The blocker for a like-for-like comparison

**We retain 2,282 of 10,000 rows.** `SB_LIMIT` is 2000 (+`SB_SLACK`), so the
shipping build simply drops 77% of the history the payload feeds it. Comparing
that 3.35 MB against another core holding all 10,000 rows is not a memory win, it
is a report of who keeps less scrollback — the single easiest way for this
comparison to produce a flattering, wrong number.

`starling_term.c` now guards the define (`#ifndef SB_LIMIT`), default unchanged
at 2000, so a bench build can be compiled at any depth without editing the file.
`SB=10000 mem-bench.sh` is the matched-depth run above. Any cross-core table must
state the retained row count on both sides, not the configured limit.

## Reproducing

    test/bench/core/mem-bench.sh [cols] [rows] [lines]       # shipping depth
    SB=10000 test/bench/core/mem-bench.sh 80 24 10000        # matched depth

Deterministic — the payloads are generated from the line index, and the allocator
path is the same every run. Re-run rather than trusting these numbers after any
change to `Row`, `Cell`, `SB_*`, `GRID_SLACK` or `ROW_POOL_MAX`.

Note for whoever touches the harnesses next: `test/bench/core/ab.sh` still points
at `apps/TerminalApp/Sources/CStarlingTerm`, which has not existed since the core
moved into `sdk/`. `mem-bench.sh` builds from `sdk/Sources/CTerminalCore`.
