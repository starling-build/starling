#!/usr/bin/env bash
# A/B the same DOOM-fire with only the glyph changed: "▀" (3-byte UTF-8) vs
# "#" (1-byte ASCII). Colours, frame structure and cell count are identical,
# so any difference is the cost of the non-ASCII character path.
#
#   doom-ab.sh <label> [reps] [frames]
set -u
LABEL="${1:-term}"; REPS="${2:-3}"; FRAMES="${3:-600}"
DIR=/var/tmp/bench
HZ=$(getconf CLK_TCK)

pid=$$; term=""; termcomm=""
while :; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] && break; [ "$ppid" -le 1 ] && break
    comm=$(ps -o comm= -p "$ppid" 2>/dev/null | tr -d ' ')
    case "$comm" in
        bash|sh|dash|zsh|env|sudo|doom-ab.sh) ;;
        *) term="$ppid"; termcomm="$comm"; break ;;
    esac
    pid="$ppid"
done
[ -z "$term" ] && { echo "doom-ab: no terminal" >&2; exec /bin/bash; }

cpu() { awk '{print $14+$15}' "/proc/$term/stat" 2>/dev/null || echo 0; }
OUT="$DIR/doomab-$LABEL.txt"
: > "$OUT"
echo "# $LABEL terminal=$term/$termcomm grid=$(stty size | tr ' ' x) frames=$FRAMES" >> "$OUT"

for variant in utf8 ascii; do
    case $variant in
        utf8)  BIN=/var/tmp/doomfire/zig-out/bin/DOOM-fire ;;
        ascii) BIN=/var/tmp/doomfire-ascii/zig-out/bin/DOOM-fire ;;
    esac
    for r in $(seq 1 "$REPS"); do
        printf '\033[0m\033[r\033[?1049l\033[2J\033[H'; sleep 1
        c0=$(cpu)
        echo -n "$variant " >> "$OUT"
        DOOMFIRE_FRAMES="$FRAMES" "$BIN" 2>> "$OUT"
        c1=$(cpu)
        printf '\033[0m\033[r\033[?1049l\033[2J\033[H'
        awk -v c0="$c0" -v c1="$c1" -v hz="$HZ" 'BEGIN{ printf "  cpu_s %.2f\n", (c1-c0)/hz }' >> "$OUT"
    done
done
printf '\033[0m\033[2J\033[H'
echo "AB DONE: $LABEL"
exec /bin/bash
