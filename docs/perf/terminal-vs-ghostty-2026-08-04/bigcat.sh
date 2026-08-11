#!/usr/bin/env bash
# Reproduce the shape of Ghostty's published test — `time cat 150MB_ascii.txt`
# and the unicode equivalent — from inside the terminal under test.
#
#   bigcat.sh <label> [reps]
#
# Records wall AND the terminal's own CPU per repetition (their post reports
# wall only; CPU is what tells you whether a win is efficiency or parallelism).
set -u
LABEL="${1:-term}"
REPS="${2:-3}"
DIR=/var/tmp/bench
HZ=$(getconf CLK_TCK)

pid=$$; term=""; termcomm=""
while :; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] && break
    [ "$ppid" -le 1 ] && break
    comm=$(ps -o comm= -p "$ppid" 2>/dev/null | tr -d ' ')
    case "$comm" in
        bash|sh|dash|zsh|env|sudo|bigcat.sh) ;;
        *) term="$ppid"; termcomm="$comm"; break ;;
    esac
    pid="$ppid"
done
[ -z "$term" ] && { echo "bigcat: no terminal found" >&2; exec /bin/bash; }

cpu() { awk '{print $14+$15}' "/proc/$term/stat" 2>/dev/null || echo 0; }
reset_term() { printf '\033[0m\033[r\033[?1049l\033[2J\033[H'; }

OUT="$DIR/bigcat-$LABEL.txt"
: > "$OUT"
echo "# file rep wall_s cpu_s   (terminal $term / $termcomm, grid $(stty size | tr ' ' x))" >> "$OUT"

for f in ascii_150mb unicode_150mb; do
    cat "$DIR/$f.txt" > /dev/null          # warm page cache — not timed
    for r in $(seq 1 "$REPS"); do
        reset_term; sleep 0.7
        c0=$(cpu); t0=$EPOCHREALTIME
        cat "$DIR/$f.txt"
        t1=$EPOCHREALTIME; c1=$(cpu)
        reset_term
        awk -v f="$f" -v r="$r" -v t0="$t0" -v t1="$t1" -v c0="$c0" -v c1="$c1" -v hz="$HZ" \
            'BEGIN{ printf "%s %d %.3f %.2f\n", f, r, t1-t0, (c1-c0)/hz }' >> "$OUT"
    done
done
reset_term
echo "BIGCAT DONE: $LABEL"
exec /bin/bash
