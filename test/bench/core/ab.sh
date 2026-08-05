#!/usr/bin/env bash
# A/B the in-tree C core against a baseline copy, best-of-N, same binary flags.
#
#   ab.sh <baseline.c> [reps]
#
# Prints MB/s for both and the ratio. Both are built here from source so the
# only difference is the code.
set -eu
SRC=/home/disheng/dev/starling-build/starling/apps/TerminalApp/Sources/CStarlingTerm
CORE=/var/tmp/bench/core
BASE="$1"
REPS="${2:-5}"
COLS=201 ROWS=47
CFLAGS="-O2 -std=c99 -D_POSIX_C_SOURCE=199309L"

cd "$CORE"
mkdir -p include
cp "$SRC/include/starling_term.h" include/starling_term.h
cp "$SRC/starling_term.c" st_new.c
gcc $CFLAGS st_new.c bench_st.c -o ab_new
gcc $CFLAGS "$BASE" bench_st.c -o ab_base

printf '%-18s %10s %10s %8s\n' workload base new ratio
for f in /var/tmp/bench/0*.txt /var/tmp/bench/10_binary.txt /var/tmp/bench/doomstream.bin; do
    [ -e "$f" ] || continue
    b=$(./ab_base "$f" "$REPS" $COLS $ROWS | awk '{print $1}')
    n=$(./ab_new  "$f" "$REPS" $COLS $ROWS | awk '{print $1}')
    awk -v w="$(basename "$f" .txt)" -v b="$b" -v n="$n" \
        'BEGIN{printf "%-18s %10.1f %10.1f %7.2fx\n", w, b, n, n/b}'
done
