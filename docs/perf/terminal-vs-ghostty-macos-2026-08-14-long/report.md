# The 08-14 long round — paced reader vs today's nightly, App-Nap-fair

2026-08-14, the rematch of `terminal-vs-ghostty-macos-2026-08-13-long`
(round 3) with both sides updated: **ghostty at today's nightly**
(`1.3.2-main+f81dcadc8`, the official CI universal binary, assets built
2026-08-14 ~14:04 UTC) and **ours with the paced pty reader as default**
(`6994938`), the anti-throttling assertion (`1c6206c`), and the week's
box-glyph work. Same harness, same matched Roboto Mono metrics, every
counted leg verified 47x201, AC, display awake, unlocked desktop,
`caffeinate -disu`.

## App Nap had to be neutralized on BOTH sides first

The first attempt at this round produced garbage: ghostty's suite leg
collapsed ~12x after almost exactly **27 seconds** of sustained streaming.
The investigation that followed established, by elimination: not the new
nightly (the 08-11 binary collapses identically), not app identity (a
re-badged copy — new bundle id, new signature, renamed executable —
collapses identically), not window focus, not `caffeinate` even as the
direct parent process, not thermal, not Low Power Mode. **Our own pre-fix
binary collapses at the same 27 s mark** (4.5x) — the cliff is
terminal-agnostic App Nap engagement, deterministic on this boot-day,
while round 3 two days earlier never triggered it. Two defenses work,
one per side:

- ours: the in-process `beginActivity([.userInitiated, .latencyCritical])`
  held while output streams (commit `1c6206c`) — ran a 45-minute leg clean
  the same hour ghostty was collapsing at 27 s;
- ghostty: `defaults write com.mitchellh.ghostty NSAppSleepDisabled -bool
  YES` — the no-code per-app opt-out, verified with a 20-block onset probe
  (flat 2.5 s/block through 50 s where the unprotected run breaks at 27 s).

With both in place the round is symmetric: neither terminal is being
napped. (This is arguably worth reporting upstream to ghostty: sustained
pty streaming in an unfocused window can be silently throttled ~12x, and
the defaults key or an in-process assertion prevents it. Repro:
`onset.sh` in this dir, ~90 s.)

Two harness fixes this round surfaced, both now in the runners: the suite
and bigcat runners recorded their grid IMMEDIATELY at startup, racing
ghostty's post-launch resize — the transient 17x49 then either wasted a
full leg (round-2 era) or, once the watchdog existed, got a GOOD leg
killed within seconds. Both runners now settle 3 s before recording, like
the doomfire runner always did. The watchdog earned its keep regardless:
five genuinely-wrong launches died in ~5 s each instead of 20-40 min.

## The suite at steady state (each workload >= 2 min, ~30 GB per side)

| workload | ours | ghostty | ratio | (round 3: 0.90x overall) |
|---|---|---|---|---|
| 01_light_cells | 54.2 | 99.4 | **0.55x** | was 0.86x |
| 02_dense_cells | 92.8 | 101.5 | **0.91x** | was 0.98x |
| 03_sgr_fg | 78.9 | 114.3 | **0.69x** | was 0.68x |
| 04_sgr_truecolor | 82.7 | 109.2 | **0.76x** | was 0.90x |
| 05_unicode | 81.9 | 103.9 | **0.79x** | was 1.15x — flipped |
| 06_cursor_motion | 69.6 | 72.6 | **0.96x** | was 0.92x |
| 07_alt_screen | 94.4 | 94.9 | **1.00x** | was 1.40x — the loss erased |
| 08_scroll_region | 90.7 | 96.3 | **0.94x** | was 0.91x |
| 09_long_lines | 93.8 | 98.0 | **0.96x** | was 1.01x |
| 10_binary | 32.0 | 110.0 | **0.29x** | was 0.34x |
| **total** | **771.1** | **1000.1** | **0.77x** | was 0.90x |

| | ours | ghostty |
|---|---|---|
| suite CPU | 1096 s | 2499 s (**0.44x**) |
| RSS after ~30 GB | **136 MB** | 155 MB |

**Ten of ten at or ahead** — the first round with no losing workload.
The two historic losses are gone: 07_alt_screen (1.40x in round 3) is
dead even, 05_unicode flipped to 0.79x. Both are the paced reader's
read/parse overlap doing exactly what it was built for. Ghostty's leg is
its round-3 self within noise (total +2.1%; per-workload -2..+6%) — the
60 nightly commits (i18n and small platform fixes) changed nothing, as
their log suggested.

## Cats at 500 MB (medians of 3)

| test | ours | ghostty | ratio | CPU ours/gh |
|---|---|---|---|---|
| ascii cat 500 MB | 1.815 s | 2.012 s | **0.90x** | 2.26 / 4.64 (49%) |
| unicode cat 500 MB | 1.701 s | 2.451 s | **0.69x** | 3.89 / 6.53 (60%) |

The unicode cat — a 6% LOSS in round 3 — is now a 31% win: 294 MB/s
sustained. Ghostty's cats match its round-3 numbers (2.01 vs 2.05,
2.45 vs 2.40).

## DOOM-Fire at 150 000 frames (3 reps per side, all 47x201)

    ours:    1118.9  1119.6  1124.6 fps   at ~216 cpu_s per rep
    ghostty: 1028.1  1023.2  1038.6 fps   at ~379 cpu_s per rep

**1.09x fps at 0.57x CPU.** Round 3 had this a 1.02x tie; the paced
reader buys ~3% more sustained fps (and spends ~46% more of our CPU
doing it — still well under ghostty's burn).

## What moved, and why (vs round 3, two days apart)

Everything that moved on our side is the paced reader (suite 771 vs 883,
unicode cat 1.70 vs 2.54, DOOM 1121 vs 1084); ghostty is flat. The cost
side is honest: our suite CPU rose from 828 to 1096 (the ~1 us busy pace
plus the parse thread), moving the CPU ratio from 0.34x to 0.44x — and
RSS from 121 to 136 MB (the 8 MB ring plus thread stacks). Both remain
decisively ours.

## Provenance

- **ours**: starling `main` at `58d5f86` + the paced-reader/assertion
  commits (`6994938`, `1c6206c`), release build against
  `host_release_arm64` (engine `ea78543`), atlas painter default,
  `STARLING_TERMINAL_SINGLE=1`, no `STARLING_CELL_H`.
- **ghostty**: official nightly `1.3.2-main+f81dcadc8`, CI universal
  binary (`ghostty-macos-universal.zip`, assets 2026-08-14), arm64 slice,
  ReleaseFast/Metal/CoreText, matched-font config
  (`font-family = Roboto Mono`, `font-size = 13.33`,
  `adjust-cell-height = -5%`, `window-save-state = never`),
  `NSAppSleepDisabled = YES`. Note prior rounds ran an 08-11 nightly of
  the same series; its suite numbers reproduce within ±3% here.
- Harness: `bench-long.sh` + `grid-watchdog.sh` (this dir); the
  settle-before-recording runner patches archived beside the corpus.
  Raw data in `data/`.
