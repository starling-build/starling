#!/usr/bin/env bash
# Our terminal core against libghostty-vt on identical payloads.
#
#   mem-vs.sh [cols] [rows] [lines]
#
# Needs a libghostty-vt static lib. Point GHOSTTY at a ghostty checkout that
# has one; build it there with:
#
#   zig build -Demit-lib-vt=true -Doptimize=ReleaseFast -Demit-macos-app=false
#
# (zig 0.16 — the one on PATH is likely 0.10 and cannot build ghostty.)
#
# MATCHED DEPTH IS THE WHOLE POINT. Our core is compiled at -DSB_LIMIT=$LINES
# and libghostty is configured to the same line limit, because our shipping
# 2000-row cap against their effectively-unlimited default is a comparison of
# who keeps less history, not of who stores it better. Neither lands exactly on
# the limit — we trim in batches with slack, they prune at page granularity —
# so the table prints retained rows per side and the per-row/per-cell columns
# are what to read.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SRC="$REPO/sdk/Sources/CTerminalCore"
GHOSTTY="${GHOSTTY:-$HOME/dev/ghostty-bench}"
LIB="$GHOSTTY/zig-out/lib/libghostty-vt.a"
OUT=/var/tmp/bench/mem
COLS="${1:-80}" ROWS="${2:-24}" LINES="${3:-10000}"

[ -f "$LIB" ] || { echo "no libghostty-vt.a at $LIB — see the header" >&2; exit 1; }
mkdir -p "$OUT"
cc -O2 -std=gnu99 -DSB_LIMIT="$LINES" \
   -I "$SRC/include" -I "$GHOSTTY/include" \
   "$SRC/starling_term.c" "$HERE/bench_mem_vs.c" "$LIB" -o "$OUT/bench_mem_vs"

printf 'ours     %s (SB_LIMIT=%s)\n' "$(cd "$REPO" && git rev-parse --short HEAD)" "$LINES"
printf 'ghostty  %s\n' "$(cd "$GHOSTTY" && git rev-parse --short HEAD)"
printf 'grid %sx%s  lines %s\n\n' "$COLS" "$ROWS" "$LINES"
printf '%-8s %-7s %-8s %5s %5s %8s %8s %10s %10s %10s %9s %8s\n' \
    engine mode payload cols rows lines sb_rows heap_B counted_B foot_B B/row B/cell
for p in empty screen plain unicode styled mixed; do
    "$OUT/bench_mem_vs" ours "$p" "$COLS" "$ROWS" "$LINES" "$LINES"
    "$OUT/bench_mem_vs" ghostty "$p" "$COLS" "$ROWS" "$LINES" "$LINES"
    COMPRESS=1 "$OUT/bench_mem_vs" ghostty "$p" "$COLS" "$ROWS" "$LINES" "$LINES"
done
# Evidence for reading `foot` and not `heap`: the allocator vtable cannot see
# libghostty's grid pages. One row is enough to show it.
echo
ALLOC=count "$OUT/bench_mem_vs" ghostty plain "$COLS" "$ROWS" "$LINES" "$LINES"
