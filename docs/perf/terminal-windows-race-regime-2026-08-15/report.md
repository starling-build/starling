# The race regime, revisited on the build that closed the cats

2026-08-15, 08:15–09:10 UTC, on `win11-fresh` — same box, same Windows
Terminal 1.24.11911.0, same corpora and film harness as
`../terminal-windows-fresh-2026-08-15/`. Ours is the release-terminal-0.1.0
head (the 2 MB ring as the in-code default), rebuilt three times over the
sitting as two experiments resolved.

The question this round set out to answer: the 08-15 long round left exactly
one loss on the platform — the three-test filmed sprint, "Windows Terminal is
8% faster" — and one attributed mechanism, the repaint path stealing drain
time. Is that still true?

The answer: **no. The sprint verdict was measured on the pre-ring-fix build
and did not survive re-measurement.** On today's build the race is a
coin-flip — ours wins 2 of 6 filmed runs, the mean gap is ~0.7 s in 37
(~2%), inside the run-to-run spread. Two candidate fixes were built, measured,
and shipped **off** as honest null results on the way to finding that out.

## Null result 1: the ConPTY output-pipe buffer

The hypothesis was attractive: `CreatePipe(nSize=0)` gives the pipe
OpenConsole writes into ~4 KB of buffer — 18 µs of slack at cat speed — and
the 2 MB ChunkRing sits *behind* the reader where it can absorb none of it.
Every ring publish is two lock passes and a cond signal on the reader thread;
any gap over 18 µs should stall the host's write.

Measured (`h/ab-pipe.ps1`, alternating launches, 2 rounds x 3 reps, rep 1
discarded, 39x120):

| config | ascii s | unicode s |
|---|---:|---:|
| pipe 4 KB (the old default) | 2.243 | 5.133 |
| pipe 1 MB | 2.285 | 5.172 |
| pipe 4 MB | 2.331 | 5.164 |
| Windows Terminal | 2.256 | 5.136 |

Nothing. The reader evidently re-arms `ReadFile` inside even the 4 KB drain
window, so extra buffer is slack nobody uses. The knob
(`STARLING_CONPTY_PIPE_KB`) ships at the system default with the measurement
in a comment, pace-style.

The table's other reading is the real news of the round: **the cats are a
dead heat in every row** — including the 4 KB one. The 08-15 round's 3–5%
cat deficit (and its "repaint path" attribution) belongs to that round's
build; on this one, at the same grid, on the same box, it is gone. Our CPU
for the tied unicode cat: 8.3 s against Windows Terminal's 11.4.

## The narrow grid: profiled, and also a tie

The race runs at 43x76, where every 119-column corpus line wraps — the
sprint is the *wrap regime*, which the 39x120 rounds never touch. Profiled
solo at that grid (`h/prof-narrow.ps1`, per-process CPU snapshots around each
rep, 3 reps):

| 500 MB, 43x76 solo | ours | ours, no repaint | Windows Terminal |
|---|---:|---:|---:|
| ascii wall | ~2.55 s | ~2.47 s | ~2.55 s |
| unicode wall | ~5.26 s | ~5.09 s | ~5.25 s |
| host occupancy | 0.84–0.92 | 0.84–0.92 | 0.82–0.92 |
| terminal CPU, ascii | 1.4–1.8 s | ~1.0 s | 2.7–2.8 s |

(Ours ran 43x77 — one extra column, ~1% more cells, close enough for the
question being asked.) The host is equally saturated on both sides; the walls
are equal; we do it on ~60% of the CPU. The C core measured on this dev box
confirms the wrap regime is real but irrelevant at ConPTY speed: 946 MB/s at
120 cols falls to 772 at 76 (−18%), against a pipeline that runs at ~200.

DOOM-Fire at the same grid, solo, 30k frames x 2 reps x 2 alternating rounds
(`h/doom-narrow.ps1`): **ours 1164/1197/1167/1176 fps, Windows Terminal
1183/1188/1135/1109** — means 1176 vs 1154, overlapping ranges, on 28–43
CPU-s against its 56–59. A tie, leaning ours.

## The race, re-run: six filmed runs

Same film harness, parameters, and grid verification as the published round
(1.5 GB ascii, 1 GB unicode, 9,600 DOOM frames, both terminals verified
43x76, started off a shared GO, ffmpeg filming throughout).

| run | ours total | wt total | delta |
|---|---:|---:|---:|
| 1 | 37.0 | 36.0 | wt +1.0 |
| 2 | 37.4 | 36.0 | wt +1.4 |
| 3 | **38.1** | 38.5 | **ours +0.4** |
| 4 (boost) | 36.2 | 35.3 | wt +0.9 |
| 5 (boost) | **36.6** | 36.7 | **ours +0.1** |
| 6 (boost) | 37.3 | 36.0 | wt +1.3 |

Published round, same harness, pre-ring-fix build: 41.8/38.5/37.9 against
36.6/35.8/35.1 — Windows Terminal ahead by 2.7–5.2 s, *every* run. Today:
mean 37.1 vs 36.4, ours ahead twice, the delta smaller than the run-to-run
spread of either side. Per-leg means across the six: ascii dead even
(−0.04 s), unicode −0.44 s (−3.7%), DOOM −36 fps (−3.5%) — the residual
lives only in the two tests that saturate the box for the longest, and only
under contention; solo, both are ties (above).

## Null result 2: boosting the drain threads

Runs 4–6 carry the second experiment: the reader and parser threads at
`THREAD_PRIORITY_ABOVE_NORMAL`, on the theory that with both terminals plus
ffmpeg saturating 8 vCPUs, every hop in reader → ring → parser waits in the
ready queue, and each delayed wake is drain time the host spends idle.

The deltas say otherwise: −1.0/−1.4/+0.4 unboosted, −0.9/+0.1/−1.3 boosted —
the same distribution. (Both sides ran ~0.8 s faster in the second sitting;
that is the box drifting between sittings, not the boost — Windows Terminal
cannot benefit from our thread priorities.) Shipped **off** behind
`STARLING_TERM_BOOST=1`, comment carrying the numbers, same policy as the
pace.

## Shipping-config validation

The final binary (pipe at system default, boost off) re-paired on the
watchdogged bigcat leg and the 43x76 DOOM pair (`data/ship-*`):

| shipping build | ours | Windows Terminal |
|---|---:|---:|
| ascii cat, 39x120 (reps 2–3) | 2.32 s | 2.27 s |
| unicode cat, 39x120 (reps 2–3) | **5.14 s** | 5.25 s |
| DOOM-Fire 43x76, 4 reps mean | **1162 fps** | 1156 fps |
| DOOM CPU per 30k frames | 28–41 s | 57–58 s |

One cat leg each way by ~2%, DOOM level — the shipping config is the
measured-parity config, not a variant of it.

## Where the platform stands

| | ours | Windows Terminal |
|---|---|---|
| ten-workload suite (08-15 long round) | **0.86x wall, 0.54x CPU** | |
| 500 MB cats, 39x120 and 43x76, solo | dead heat, ~0.6–0.7x CPU | |
| DOOM-Fire, 39x120 and 43x76, solo | dead heat, ~0.6x CPU | |
| RSS after the suite | 29–32 MB | ~1 GB |
| 3-test sprint, saturated box + recorder | ours 2 of 6, mean −2% | wt 4 of 6 |

The one regime where Windows Terminal still edges ahead on average is the
filmed sprint — both terminals racing while ffmpeg encodes the screen — and
there only in unicode and DOOM, by ~2%, inside noise. The published race
video (`ui/video/terminal-race-windows.mp4`) shows the old build's 2.8 s
loss; `race-boost-2`/`race-newbuild-3` on the box show today's builds
winning. Neither is linked from the site.

## What to keep from this round

- **A published loss is a measurement of a build, not a property of the
  product.** The 8% sprint verdict outlived the build it measured by one
  day; re-measuring cost an hour, and half this round's work was
  un-attributing mechanisms (repaint, wrap costs, pipe slack) from a gap
  that no longer exists.
- **Two null knobs beat one lucky guess.** Both hypotheses were plausible,
  cheap to build, and wrong; both are now unrepeatable-by-accident, each
  carrying its measurement in the comment beside the off switch.
- The grid your corpus was built for is load-bearing: 119-column lines make
  76 columns the wrap regime and 120 the no-wrap regime — different code
  paths, different per-byte costs (−18% in the core), same file.

Raw data in `data/` (per-leg result files, orchestrator logs, per-process
profiles), harness as run in `h/`.
