#!/usr/bin/env bash
# Which workload grows the terminal's RSS? Cat each one alone and sample
# RSS (and the emulator's scrollback-bounded share) after each.
#
#   rss-probe.sh <terminal-pid> <out-file>
set -u
PID="$1"; OUT="$2"
DIR="$(cd "$(dirname "$0")" && pwd)"

rss() { awk '/VmRSS/{print $2}' "/proc/$PID/status"; }
reset_term() { printf '\033[0m\033[r\033[?1049l\033[2J\033[H'; }

: > "$OUT"
reset_term; sleep 1
echo "start $(rss)" >> "$OUT"

for f in "$DIR"/[0-9]*.txt; do
    name=$(basename "$f" .txt)
    cat "$f" > /dev/null
    reset_term; sleep 0.5
    cat "$f"
    reset_term; sleep 1.5          # let any deferred free happen
    echo "$name $(rss)" >> "$OUT"
done

sleep 5
echo "after_idle_5s $(rss)" >> "$OUT"
reset_term
echo "PROBE-DONE"
