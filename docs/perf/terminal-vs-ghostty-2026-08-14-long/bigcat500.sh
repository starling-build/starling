#!/usr/bin/env bash
# 500 MB cats, 3 reps each, from inside the terminal. Args: <label>
set -u
LABEL="${1:-term}"
DIR=/var/tmp/bench-long
HZ=$(getconf CLK_TCK)
pid=$$; term=""; termcomm=""
while :; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] && break
    [ "$ppid" -le 1 ] && break
    comm=$(ps -o comm= -p "$ppid" 2>/dev/null | tr -d ' ')
    case "$comm" in
        bash|sh|dash|zsh|env|sudo|bigcat500.sh) ;;
        *) term="$ppid"; termcomm="$comm"; break ;;
    esac
    pid="$ppid"
done
[ -z "$term" ] && { echo "no terminal" >&2; exec /bin/bash; }
cpu() { awk '{print $14+$15}' "/proc/$term/stat" 2>/dev/null || echo 0; }
OUT="$DIR/bigcat500-$LABEL.txt"
: > "$OUT"
echo "# $LABEL terminal=$term/$termcomm grid=$(stty size | tr ' ' x)" >> "$OUT"
cat "$DIR/ascii_500mb.txt" > /dev/null   # warm page cache
cat "$DIR/unicode_500mb.txt" > /dev/null
for f in ascii_500mb unicode_500mb; do
    for r in 1 2 3; do
        printf '\033[2J\033[H'
        c0=$(cpu); t0=$EPOCHREALTIME
        cat "$DIR/$f.txt"
        t1=$EPOCHREALTIME; c1=$(cpu)
        awk -v f="$f" -v t0="$t0" -v t1="$t1" -v c0="$c0" -v c1="$c1" -v hz="$HZ" \
            'BEGIN{ printf "%s %.3f %.2f\n", f, t1-t0, (c1-c0)/hz }' >> "$OUT"
    done
done
echo "rss_kb $(awk '/VmRSS/{print $2}' /proc/$term/status)" >> "$OUT"
echo "ALL DONE: $LABEL"
sleep infinity
