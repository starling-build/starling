#!/usr/bin/env bash
# Memory baseline for the C core: bytes of terminal state per payload.
#
#   mem-bench.sh [cols] [rows] [lines]
#
# Payloads mirror the ones libghostty was measured on (empty screen, full
# screen, then a deep scrollback of plain / unicode / heavy-styled / mixed)
# so this table and a libghostty table can be read side by side later.
#
# ONE PROCESS PER PAYLOAD. Looping inside one process lets a freed scrollback
# warm the heap for whatever runs next, which quietly shrinks the second
# number for identical state. See bench_mem.c.
#
# Built from sdk/Sources/CTerminalCore — NOT from the stale copy of the header
# in this directory, and not from apps/TerminalApp/Sources/CStarlingTerm, which
# ab.sh still names and which no longer exists since the core moved into sdk/.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SRC="$REPO/sdk/Sources/CTerminalCore"
OUT=/var/tmp/bench/mem
COLS="${1:-80}" ROWS="${2:-24}" LINES="${3:-10000}"
# Scrollback depth to BUILD the core at. Default 2000 is the shipping value,
# so the default run is the product as it ships. Set SB=10000 to measure at a
# depth matching another core's default — a memory comparison at mismatched
# depth is not a comparison, it is a report of who keeps less history.
SB="${SB:-}"
CFLAGS="-O2 -std=gnu99"   # see the note at the top of bench_mem.c
[ -n "$SB" ] && CFLAGS="$CFLAGS -DSB_LIMIT=$SB"

[ -f "$SRC/starling_term.c" ] || { echo "core not at $SRC" >&2; exit 1; }
mkdir -p "$OUT"
cc $CFLAGS -I "$SRC/include" "$SRC/starling_term.c" "$HERE/bench_mem.c" -o "$OUT/bench_mem"

printf 'core %s\n' "$(cd "$REPO" && git rev-parse --short HEAD)"
printf 'grid %sx%s  lines %s  cell %s B  SB_LIMIT %s\n\n' \
    "$COLS" "$ROWS" "$LINES" 16 "${SB:-2000 (shipping)}"
printf '%-8s %5s %5s %8s %8s %10s %10s %10s %10s %7s %8s\n' \
    payload cols rows lines sb_rows new_B total_B foot_B model_B ovh B/cell
for p in empty screen plain unicode styled mixed; do
    "$OUT/bench_mem" "$p" "$COLS" "$ROWS" "$LINES"
done
