# Core against core, through ghostty's own benchmark harness

2026-08-13, MacBook Pro (M1 Pro), AC power, quiet box. The first measurement
in this repo that compares the two emulator cores **directly** — no pty, no
renderer, no window on either side — using ghostty's own `ghostty-bench`
tool and its own generated corpora, as well as ours.

    ours      this branch's C core (sdk/Sources/CTerminalCore), -O2,
              driven by test/bench/core/bench_stream.c
    ghostty   1.3.2-HEAD-+046b8fcc2, zig 0.16.0, ReleaseFast,
              `ghostty-bench +terminal-stream`

Grid 201x47 on both, best of 5, each side's floor subtracted. Driver: `run.sh`.

## What ghostty-bench actually is

Worth stating, because it is not what the name suggests and it is not
comparable to anything else in `docs/perf/`.

- **Two binaries by design.** `ghostty-gen` writes synthetic corpora to stdout;
  `ghostty-bench` consumes a pre-generated file. Their `src/benchmark/AGENTS.md`
  forbids piping one into the other — that would fold generation cost into the
  measurement — and requires that branch comparisons replay the *same* files.
- **The runner reports nothing.** `Benchmark.zig` has `once` and `duration`
  modes and returns iterations + nanoseconds, but `benchmark/cli.zig` calls
  `_ = try b.run(.once)` and discards it. You are expected to time the process
  from outside with hyperfine. Both sides here are timed the same way.
- **Fourteen benchmarks at three isolation levels**: `terminal-stream` (the
  full stream handler, real state updates — the analogue of our `bench_st`),
  `terminal-parser` / `osc-parser` / `apc-parser` (parsing only), and
  data-structure cases (`terminal-resize`, `screen-clone`, `page-compression`,
  `scrollback-compression`, `terminal-formatter`, `terminal-snapshot`,
  `hyperlink-map`) plus Unicode primitives (`codepoint-width`,
  `grapheme-break`, `is-symbol`).
- **`terminal-stream` reads in 64 KB chunks because that is their real IO
  thread's `buffer_capacity`** — the harness is pinned to the app's own
  chunking, and says so in a comment.
- **The Unicode benchmarks carry a `noop` mode** that reads the file and does
  nothing, so the I/O floor can be subtracted from the algorithm. That is the
  idea this round borrowed for both sides.

Building it needs zig 0.16 (`~/dev/zig-0.16.0`, not the 0.10.1 on `PATH`):

    zig build -Demit-bench -Doptimize=ReleaseFast -Demit-macos-app=false

`-Demit-macos-app=false` is also what sidesteps the Xcode package-graph
deadlock that stopped the 2026-08-12 round from building ghostty at all.

## The result

MB/s, floors subtracted; ratio is ours/theirs, so **below 1.00 is ours**.

| corpus | ours | ghostty | ratio | before the run store |
|---|---|---|---|---|
| 10_binary | 508 MB/s | 74 | **0.14x** | 0.13x |
| styled (theirs, `--style-rate=0.8`) | 329 | 49 | **0.15x** | 0.15x |
| 03_sgr_fg | 319 | 136 | **0.43x** | 0.40x |
| 01_light_cells | 400 | 186 | **0.47x** | 0.44x |
| 04_sgr_truecolor | 363 | 204 | **0.56x** | 0.55x |
| unicode (theirs, mixed + graphemes) | 112 | 62 | **0.56x** | 0.56x |
| 07_alt_screen | 1187 | 669 | **0.56x** | 0.76x |
| 08_scroll_region | 1025 | 831 | **0.81x** | 1.05x |
| 05_unicode | 494 | 463 | 0.94x | 0.94x |
| 02_dense_cells | 1269 | 1243 | 0.98x | 1.38x |
| 09_long_lines | 1134 | 1282 | 1.13x | 1.47x |
| ascii (theirs, unstyled) | 955 | **1313** | 1.37x | 1.78x |

**The split was clean and it was the same on both parties' corpora**: every
workload carrying escape sequences or non-ASCII text was ours, often by
multiples; every workload that was plain unstyled ASCII cell-fill was theirs.
That is exactly the shape the Linux rounds reported from the *live* suite —
"we take the escape/parser workloads, the nightly keeps raw cell-fill"
(`terminal-vs-ghostty-2026-08-11`, §1) — confirmed at the core with the
transport and the renderer removed from the room, on their corpora and through
their harness.

**The last column is why that is past tense.** The first run of this round put
their ASCII path at 1.78x ours, and the disassembly said why: our run store
wrote one character per iteration — `ldrb; str; stur d; strb` plus index
arithmetic, about nine instructions per cell, no vectorisation. A Cell is
exactly four 32-bit lanes, so `vst4q_u32` lays down four whole cells in one
instruction. With that, plain cell-fill went 746 -> 955 MB/s and the cluster
of losses collapsed: `02_dense_cells` to a tie, `08_scroll_region` and
`07_alt_screen` from losses to wins, `09_long_lines` to within 13%, and their
own ascii corpus from 1.78x to 1.37x.

What remains of their ASCII lead is real and is the same 16 bytes per cell we
have to write either way: theirs is smaller, because ghostty interns styles
per page and stores a style id where we store fg, bg and attrs inline. That is
an ABI change on our side (`StarlingTermCell` is layout-shared with Swift), not
a tuning one.

## What it explains

Yesterday's two headline results looked like they disagreed, and this is why
they do not:

- We win the **10-workload suite** 0.75x, because that corpus is
  escape-and-Unicode-heavy — the half of the space our core owns.
- We win **`cat 150mb_ascii`** live (0.570 s to their 0.634) *even though
  their core was 1.78x ours on exactly that content*, because through a real
  pty the transport dominates: the macOS pty hands back at most 1024 bytes per
  read, so 150 MB is ~147 000 round trips and neither core is the bottleneck.

So the core comparison is the one place their ASCII throughput shows up
undiluted, and the only place ours can be read without the pty floor on top.

**The corollary is worth stating plainly, because it cuts against the change
above**: making the core 30% faster on cell-fill moved the live suite by
-0.3% and the live ascii cat by 0.002 s — both inside noise, measured by
interleaving two builds in one sitting rather than comparing across runs. On
`cat`-shaped workloads through a pty this is invisible. It is worth having
anyway — it is the scoreboard here, it halves the instruction count per cell,
and consumers that feed the core without a pty in the middle (termd's remote
sessions, replay) get all of it — but nobody should expect it to show up in a
terminal benchmark, and an earlier cross-run comparison that appeared to show
it *regressing* the suite by 1.3% was drift, not signal.

## Where ours is weak, and what to do about it

`gen_unicode` — mixed Latin-Extended, CJK, emoji, 10% combining marks — is the
slowest thing either core does: 112 MB/s for us, 62 for them. Both are 4-7x
below their own plain-text rates, so grapheme clusters are expensive for
everyone; we are simply less slow. It is still our worst absolute number and
the natural next target after the width cache (see the plan).

`codepoint-width`'s own doc comment records that ghostty found their width
function was **30% of every character print** — the same class of bug this
branch fixed yesterday at 43.6%. Their answer is a codegen'd **3-level lookup
trie** (`src/unicode/lut.zig`, 256-codepoint blocks, deduplicated), which is
O(1) with no misses at all. Ours is now a direct-mapped cache that still falls
back to two binary searches on a cold slot or a collision. If width shows up
hot again, the trie is the known-better structure and they have published the
shape.

## Traps hit while building this

- **Their harness has no line discipline either.** Feeding it our corpus files
  as-is would staircase *their* terminal exactly as it did ours — bare LFs, no
  ONLCR. The comparison uses `/var/tmp/bench/crlf/*`; `ghostty-gen` emits CRLF
  itself, which is the better fix and the one to copy.
- **`--seed` is not global.** `ghostty-gen`'s `cli.zig` has a `TODO: Make this
  a command line option` and seeds from the clock; only some generators
  (`styled`) take their own `--seed`. `+ascii --seed=42` is an `InvalidField`
  error and writes nothing, which looks exactly like a generator that produced
  an empty file.
- **A rejected flag lands on the floor, silently.** zsh does not word-split
  unquoted parameters, so a `set -- $grid` in an early driver passed
  `--terminal-cols="201 47" --terminal-rows=` — ghostty rejected it, exited in
  10 ms, and reported as *infinitely fast*. Only the floor subtraction caught
  it (as a divide-by-zero). `run.sh` now fails loudly when either side lands on
  its floor.
- **Ratios are grid-independent**, checked rather than assumed:
  `02_dense_cells` 1.32x at 201x47 and 1.30x at their default 120x80;
  `03_sgr_fg` 0.40x and 0.41x.
