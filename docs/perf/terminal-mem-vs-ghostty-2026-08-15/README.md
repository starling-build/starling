# Terminal core memory: ours vs libghostty-vt — 2026-08-15

The comparison the baseline round (`terminal-mem-baseline-2026-08-15/`) was
built to feed. Same six payloads, same bytes, same instrument, both engines in
the same binary, one engine per process.

- ours: `01e0647` (`release-terminal-0.1.0`), compiled `-DSB_LIMIT=10000`
- ghostty: `046b8fcc2`, `libghostty-vt.a`, ReleaseFast
- Apple M4 Max, macOS 26.6.1. Harness: `test/bench/core/bench_mem_vs.c`,
  driven by `test/bench/core/mem-vs.sh`.

## The instrument, and why it is not the obvious one

**libghostty's grid does not pass through `malloc`.** The first run of this
harness reported it holding **21 KB** for 9,977 rows whose footprint was
**7.1 MB** — a 300x error that would have read as a landslide. `PageList`
takes grid pages from Zig's page allocator, and on macOS from a *tagged* mach
VM allocator (`application_specific_1`, so the grid is attributable in vmmap).
A malloc statistic cannot see any of it.

**The allocator vtable does not fix this.** `ALLOC=count` hands libghostty a
counting allocator through its documented `GhosttyAllocator` interface; it
accounts for **19,674 bytes** of that same 7.2 MB state. The vtable sees
ancillary allocations only. Anyone reaching for that interface to count
libghostty will get a number that looks precise and is wrong by two orders of
magnitude. The row is kept in the output as evidence.

So the comparable column is **`foot`** — resident pages, `phys_footprint` — for
both engines, because it is the only probe that sees a malloc-based core and an
mmap-based one alike. Reporting malloc for ours (13.10 MB) against pages for
theirs would have quietly credited us with the 7% of our own footprint that is
allocator slack, on the side of the table where it helps.

**Depth is matched, and retained rows are printed per side.** Our shipping
`SB_LIMIT` is 2000; libghostty's line limit is effectively unlimited by default.
Feeding 10,000 rows to both as shipped would have compared 2,282 of our rows
against 10,000 of theirs and called our quarter of the memory a win. Both are
configured to 10,000 lines here. Neither lands exactly on it — we trim in
batches with slack, they prune at page granularity — so ghostty retains 9,454
rows on the unicode payload where we retain 9,977, and the per-row and per-cell
columns are what to read.

**`foot` carries ±1 page of jitter; `heap` does not.** Re-running the identical
build moves the footprint by exactly 16 KB on some payloads while every malloc
column stays byte-identical — page granularity, not a change. At 13 MB that is
0.1% and can be ignored; on the empty and full-screen rows, where the totals are
80–230 KB, it is 7–20% and cannot. Those two rows are therefore reported as the
range over five runs, not as a single number. This is also why a refactor of the
harness that changed no behaviour showed a one-page difference in the baseline
round's `foot` column and nothing else.

**Compression is driven to completion, not slept on.** In the library it is
caller-driven (`ghostty_terminal_compress`), so a post-feed sample would report
uncompressed bytes while calling it the default configuration — the shipping app
runs the same pass from its idle handler. The `def+z` rows step it until it stops
reporting `PENDING`, which is a deterministic quiesce. Both are reported, because
compressed is what a user gets and uncompressed is what the layout costs.

## 80×24, 10,000 lines, ~9,977 rows retained

`foot`, 1024-based:

| payload | ours | ghostty | ghostty +z | ours/ghostty | ours/+z |
|---|---:|---:|---:|---:|---:|
| empty   |  64–80 KB |  176–192 KB |  176–192 KB | **~0.40** | ~0.40 |
| screen  |  80–96 KB |  208–224 KB |  208–224 KB | **~0.43** | ~0.43 |
| plain   | 13.42 MB | 6.80 MB | 0.73 MB | 1.97 | 18.3 |
| unicode | 13.44 MB | 6.83 MB | 2.16 MB | 1.97 | 6.2 |
| styled  | 13.45 MB | 11.11 MB | 2.62 MB | **1.21** | 5.1 |
| mixed   | 13.44 MB | 10.88 MB | 2.62 MB | **1.24** | 5.1 |

Per cell, over retained rows: ours **17.6 B** flat across every payload;
ghostty **8.9 B** plain, **9.4 B** unicode, **14.6 B** styled.

## 201×47 (the grid the throughput rounds use)

| payload | ours | ghostty | ghostty +z | ours/ghostty |
|---|---:|---:|---:|---:|
| empty   |  240 KB |  176 KB |  192 KB | 1.36 |
| screen  |  256 KB |  256 KB |  256 KB | 1.00 |
| plain   | 39.58 MB | 16.77 MB | 0.61 MB | 2.36 |
| unicode | 39.58 MB | 16.66 MB | 2.56 MB | 2.38 |
| styled  | 39.60 MB | 22.09 MB | 2.39 MB | 1.79 |
| mixed   | 39.56 MB | 21.95 MB | 4.02 MB | 1.80 |

Per cell: ours **20.6 B** flat; ghostty **8.8 B** plain, **11.5 B** styled.

The `screen` row here is a tie within one page and should be read as such; the
`empty` row's 64 KB gap is four pages and is real. Single runs, unlike the
80×24 small rows above — treat both as ±1 page.

## What it says

**We win the empty and full-screen rows at 80×24, by more than 2x.** 64–80 KB
against 176–192 KB, and 80–96 KB against 208–224 KB over two sets of five runs
— a margin six pages wide, so the ±1 page of jitter does not touch the
conclusion. libghostty pays a fixed page-pool floor that
an 80×24 screen never amortises; we allocate a scrollback ring array up front
(326 KB at a 10k limit) but never touch most of it, so it is virtual and not
resident. At 201×47 the floor is amortised and the advantage is gone. This is
the opposite of what the baseline round predicted from structure alone, and it
is the row that matters for "how much does an idle tab cost".

**On deep plain scrollback they are ~2x, exactly as the layouts predict.**
8.9 B/cell against our 17.6 — an 8-byte `Cell` with an interned `style_id`
against our 16-byte cell with fg/bg/attrs inline, plus per-row overhead on both
sides. There is no tuning in this gap; it is the struct.

**Heavy styling nearly closes it, and that was the prediction to test.** Their
per-cell cost goes 8.9 → 14.6 B when every cell carries a distinct truecolor fg
and 256-colour bg, because interning has to store a table entry per distinct
style; ours does not move at all, because fg/bg/attrs are already in every cell
whether used or not. 1.97x becomes **1.21x**. Style interning is a bet that
styles repeat, and `styled` is the payload that calls the bet. The effect is
grid-dependent — at 201×47 it is 8.8 → 11.5 B/cell and the ratio only falls to
1.79x — so it is not a fixed penalty, it is a function of how many distinct
styles land in a page.

**Compression is worth 3–18x on top, and it is highly payload-dependent.**
Plain repeating ASCII compresses ~9x (0.73 MB for 10k rows); unicode and styled
only ~4–5x. Quoting the plain number as "compression saves 90%" would be
choosing the friendliest corpus — their own docs say 70–90% for text-heavy
history, which the unicode and styled rows land under. Note also that the
compressed *heap* number rises (185 KB → 1.86 MB on styled) as the LZ4 output
lands in malloc while the pages are returned: compression moves memory between
the two probes as well as shrinking it.

**Their unicode retention is lower (9,454 vs our 9,977 rows).** Page granularity
with graphemes in the page. The totals are therefore not directly comparable on
that row; the per-row column corrects for it (1408.9 vs 755.4 B/row).

## Where this leaves us

Uncompressed, at matched depth, on the styling-heavy payloads a real terminal
actually produces, we are within 1.2–1.8x. On plain text we are 2x. Against
compressed history we are 5–18x, and that gap is not a layout problem — we have
no compression at all.

Two things follow, neither of which is a tune:

1. **The 16-byte cell.** Halving it means interning styles, which is an ABI
   change across the Swift boundary (`StarlingTermCell` is layout-compatible
   with Swift's `TermCell`), and the `styled` column says the payoff is
   1.97x on plain text and 1.21x on styled — smaller than it looks.
2. **Cold-history compression.** This is where the real gap is, it is
   independent of the cell layout, and libghostty's own numbers show the win is
   large even against their better cell. Our scrollback is a ring of per-row
   `Cell*` allocations, so the page-granular approach they compress does not
   map onto it directly.

Also worth stating plainly: our 2000-row shipping cap means the *product* today
holds 3.35 MB where this table holds 13.42 MB. That is a smaller number for a
smaller feature, not a win, and it should never be quoted against another
terminal's default.

## Reproducing

    # once, in a ghostty checkout, with zig 0.16:
    zig build -Demit-lib-vt=true -Doptimize=ReleaseFast -Demit-macos-app=false

    test/bench/core/mem-vs.sh [cols] [rows] [lines]      # GHOSTTY=<checkout>

Deterministic on both sides. `data/` holds the raw runs for both grids.
