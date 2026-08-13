#!/bin/zsh
# Core against core: our C emulator vs ghostty's terminal stream handler,
# through GHOSTTY'S OWN benchmark harness, on both parties' corpora.
#
# No pty, no renderer, no window on either side — this is the parse-and-update
# path alone, which is the only thing the two projects have that is directly
# comparable. It is NOT comparable to the 10-workload suite or the published
# cat tests, both of which include transport and drawing.
#
# Fairness, in four parts, each of which was wrong at some point while
# building this:
#
#  1. SAME I/O SHAPE. ghostty-bench's terminal-stream reads its data file in
#     64 KB chunks INSIDE the timed region. Our usual `bench_st` slurps the
#     file first and times only the feed, which would charge us nothing for
#     I/O. `test/bench/core/bench_stream.c` exists to mirror theirs exactly.
#  2. SAME CLOCK. ghostty-bench discards its own timing (`b.run(.once)` in
#     src/benchmark/cli.zig prints nothing) and their AGENTS.md says to time
#     the process with hyperfine. So both sides are timed from outside, whole
#     process, best of N.
#  3. FLOOR SUBTRACTED. Process start plus a 150 MB read is ~10-14 ms on both
#     sides. Small, but it is also the guard rail: a side that rejects its
#     flags and exits immediately lands exactly on its floor, which is how a
#     silently-broken invocation announces itself here.
#  4. CRLF. Their harness has no line discipline either, so feeding it our
#     LF-only corpus files would staircase THEIR terminal the same way it did
#     ours (see test/bench/core/README.md). Our side of the comparison uses
#     /var/tmp/bench/crlf/*. ghostty-gen already emits CRLF itself.
#
# Build the ghostty tools with, from a ghostty checkout at zig 0.16:
#   zig build -Demit-bench -Doptimize=ReleaseFast -Demit-macos-app=false
# That last flag is also what sidesteps the Xcode package-graph deadlock that
# stopped the 2026-08-12 round building ghostty at all.
set -u
GB=${GB:?set GB to ghostty-bench (zig-out/bin/ghostty-bench)}
GEN=${GEN:?set GEN to ghostty-gen (zig-out/bin/ghostty-gen)}
OURS=${OURS:-/var/tmp/ghbench/bench_stream}
D=${D:-/var/tmp/ghbench}
OURCORPUS=${OURCORPUS:-/var/tmp/bench/crlf}
N=${N:-5}
COLS=${COLS:-201} ROWS=${ROWS:-47}
SIZE=${SIZE:-157286400}          # 150 MiB, identical for every generated file
OUT="${0:A:h}/data"
mkdir -p "$D" "$OUT"

zmodload zsh/datetime
timeit() {                        # best-of-N process wall
    local best=999999 t0 t1 d
    for i in $(seq 1 $N); do
        t0=$EPOCHREALTIME; "$@" > /dev/null 2>&1; t1=$EPOCHREALTIME
        d=$(( t1 - t0 )); (( d < best )) && best=$d
    done
    printf "%.4f" $best
}

# ── corpora ──────────────────────────────────────────────────────────────
# ghostty-gen streams until its pipe closes, so size is set by `head`. Note
# --seed is per-generator and `ascii` has none (their cli.zig has a TODO for
# a global one), so the ascii corpus is not reproducible across runs.
for spec in \
    "gen_ascii.bin:+ascii" \
    "gen_unicode.bin:+styled --seed=42 --weight-two=1 --weight-three=1 --weight-four=0.5 --grapheme-rate=0.1" \
    "gen_styled.bin:+styled --seed=7 --style-rate=0.8"
do
    f="$D/${spec%%:*}"; args="${spec#*:}"
    [ -s "$f" ] || { echo "generating $f"; "$GEN" ${=args} 2>/dev/null | head -c "$SIZE" > "$f"; }
done

# ── floors ───────────────────────────────────────────────────────────────
FLOOR_GH=$(timeit "$GB" +codepoint-width --mode=noop --data="$D/gen_ascii.bin")
FLOOR_US=$(STREAM_NOOP=1 timeit "$OURS" "$D/gen_ascii.bin" $COLS $ROWS)
echo "floors: ours ${FLOOR_US}s  ghostty ${FLOOR_GH}s  (process start + 150 MB read)"

row() {                           # row <label> <file>
    local label="$1" f="$2"
    local sz=$(stat -f %z "$f")
    local o=$(timeit "$OURS" "$f" $COLS $ROWS)
    local g=$(timeit "$GB" +terminal-stream --data="$f" --terminal-cols=$COLS --terminal-rows=$ROWS)
    python3 -c "
o=$o-$FLOOR_US; g=$g-$FLOOR_GH; mb=$sz/1e6
if g <= 0.002 or o <= 0.002:
    print(f'{\"$label\":<18} AT FLOOR — a side exited without working; check its flags')
else:
    print(f'{\"$label\":<18}{o:>9.3f}{g:>9.3f}{mb/o:>11.1f}{mb/g:>11.1f}{o/g:>8.2f}x')"
}

{
    echo "# core vs core, grid ${COLS}x${ROWS}, best of $N, floors subtracted"
    echo "# $(date -u '+%Y-%m-%dT%H:%M:%SZ')  $("$GB" +version 2>&1 | head -1)"
    printf "%-18s %9s %9s %11s %11s %8s\n" corpus ours_s gh_s ours_MBs gh_MBs ratio
    echo "-- ghostty's own generated corpora --"
    row ascii     "$D/gen_ascii.bin"
    row unicode   "$D/gen_unicode.bin"
    row styled    "$D/gen_styled.bin"
    echo "-- our 10-workload corpora (CRLF copies) --"
    for c in 03_sgr_fg 05_unicode 02_dense_cells 09_long_lines 10_binary \
             01_light_cells 04_sgr_truecolor 07_alt_screen 08_scroll_region; do
        [ -f "$OURCORPUS/$c.txt" ] && row "$c" "$OURCORPUS/$c.txt"
    done
} | tee "$OUT/core-vs-core.txt"
