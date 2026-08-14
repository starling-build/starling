#!/usr/bin/env bash
# DOOM-Fire-Zig throughput test, run from inside the terminal under test.
#
#   doomfire.sh <label> [reps] [frames]
#
# The upstream program renders until you press a key and prints a running
# average fps to the screen. Two changes were made (see src/main.zig, marked
# BENCH): it stops after DOOMFIRE_FRAMES frames, and it reports the result on
# STDERR. Stdout — the byte stream the terminal actually renders — is
# untouched, and every terminal is asked for exactly the same frame count, so
# fps is a fair function of how fast each one drains and draws it.
#
# Grid must match across terminals: fire size is width x (height*2).
set -u
LABEL="${1:-term}"
REPS="${2:-3}"
FRAMES="${3:-600}"
DIR=/var/tmp/bench-long
BIN=/var/tmp/doomfire/zig-out/bin/DOOM-fire

pid=$$; term=""; termcomm=""
while :; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] && break
    [ "$ppid" -le 1 ] && break
    comm=$(ps -o comm= -p "$ppid" 2>/dev/null | tr -d ' ')
    case "$comm" in
        bash|sh|dash|zsh|env|sudo|doomfire.sh) ;;
        *) term="$ppid"; termcomm="$comm"; break ;;
    esac
    pid="$ppid"
done
[ -z "$term" ] && { echo "doomfire: no terminal found" >&2; exec /bin/bash; }

OUT="$DIR/doom-$LABEL.txt"
HZ=$(getconf CLK_TCK)
cpu() { awk '{print $14+$15}' "/proc/$term/stat" 2>/dev/null || echo 0; }

: > "$OUT"
echo "# $LABEL  terminal=$term/$termcomm  grid=$(stty size | tr ' ' x)  frames=$FRAMES" >> "$OUT"

for r in $(seq 1 "$REPS"); do
    printf '\033[0m\033[r\033[?1049l\033[2J\033[H'
    sleep 1
    c0=$(cpu)
    DOOMFIRE_FRAMES="$FRAMES" "$BIN" 2>> "$OUT"
    c1=$(cpu)
    printf '\033[0m\033[r\033[?1049l\033[2J\033[H'
    awk -v c0="$c0" -v c1="$c1" -v hz="$HZ" \
        'BEGIN{ printf "  cpu_s %.2f\n", (c1-c0)/hz }' >> "$OUT"
done

printf '\033[0m\033[2J\033[H'
echo "grid_after $(stty size | tr ' ' x)" >> "$OUT"
echo "DOOM DONE: $LABEL"
exec /bin/bash
sleep infinity
