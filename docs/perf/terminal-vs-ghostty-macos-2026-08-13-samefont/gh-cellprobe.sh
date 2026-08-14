#!/bin/zsh
# Runs INSIDE ghostty. Reports the text-area pixel size (XTWINOPS 14) and the
# grid (stty size) so the caller can compute exact cell metrics.
sleep 3
B=${BENCH_DIR:-/var/tmp/bench}
exec </dev/tty
oldstty=$(stty -g)
stty raw -echo min 0 time 20
printf '\e[14t' > /dev/tty
resp=""
while read -r -k 1 ch; do
    resp+="$ch"
    [[ "$ch" == "t" ]] && break
done
stty "$oldstty"
# resp looks like ESC [ 4 ; height ; width t
clean=$(printf '%s' "$resp" | tr -d '\033[' )
echo "winops $clean" > "$B/GHPIX"
stty size > "$B/GRID" 2>&1
sleep 1
