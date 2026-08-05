#!/usr/bin/env bash
# Repeat ONE workload N times, sampling RSS after each pass.
#
# Distinguishes an unbounded leak (RSS climbs every pass) from a one-time
# high-water mark / allocator retention (RSS plateaus after the first pass).
#
#   repeat-probe.sh <terminal-pid> <workload-file> <passes> <out-file>
set -u
PID="$1"; F="$2"; N="$3"; OUT="$4"

rss() { awk '/VmRSS/{print $2}' "/proc/$PID/status"; }
reset_term() { printf '\033[0m\033[r\033[?1049l\033[2J\033[H'; }

: > "$OUT"
cat "$F" > /dev/null          # warm
reset_term; sleep 1
echo "pass0 $(rss)" >> "$OUT"

for i in $(seq 1 "$N"); do
    cat "$F"
    reset_term; sleep 1.5
    echo "pass$i $(rss)" >> "$OUT"
done
reset_term
echo "REPEAT-DONE"
