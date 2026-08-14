#!/usr/bin/env bash
# Linux long-run suite runner: each workload repeated so a leg runs minutes.
# Repeat counts target >=120 s on the slower side from the 08-13-atlas
# matched-font medians. Output row: name wall_s cpu_s reps.
set -u
PID="$1"; OUT="$2"
DIR="$(cd "$(dirname "$0")" && pwd)"
HZ=$(getconf CLK_TCK)

declare -A REPS=(
  [01_light_cells]=210  [02_dense_cells]=490 [03_sgr_fg]=120
  [04_sgr_truecolor]=160 [05_unicode]=360    [06_cursor_motion]=3500
  [07_alt_screen]=900   [08_scroll_region]=240 [09_long_lines]=820
  [10_binary]=75
)

cpu() { awk '{print $14+$15}' "/proc/$PID/stat" 2>/dev/null || echo 0; }
reset_term() { printf '\033[0m\033[r\033[?1049l\033[2J\033[H'; }

: > "$OUT"
for f in "$DIR"/[0-9][0-9]_*.txt; do
    name=$(basename "$f" .txt)
    reps=${REPS[$name]:-1}
    reset_term
    sleep 0.5
    c0=$(cpu); t0=$EPOCHREALTIME
    for ((r = 0; r < reps; r++)); do cat "$f"; done
    t1=$EPOCHREALTIME; c1=$(cpu)
    reset_term
    awk -v n="$name" -v t0="$t0" -v t1="$t1" -v c0="$c0" -v c1="$c1" -v hz="$HZ" -v reps="$reps" \
        'BEGIN{ printf "%s %.3f %.2f %d\n", n, t1-t0, (c1-c0)/hz, reps }' >> "$OUT"
done
echo "rss_kb $(awk '/VmRSS/{print $2}' /proc/$PID/status 2>/dev/null)" >> "$OUT"
