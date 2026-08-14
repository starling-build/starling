#!/bin/zsh
# gh-probe-once.sh <flags...> — launch ghostty with the given config flags plus
# a clamped window, run the cell probe inside it, print "rows cols h_px w_px".
set -u
B=${BENCH_DIR:-/var/tmp/bench}
GH=${GHOSTTY:-/Users/dishengsu/dev/ghostty-tip/Ghostty.app/Contents/MacOS/ghostty}
PROBE=/private/tmp/claude-501/-Users-dishengsu-dev-starling-starling/2c288d3f-9af0-4fb0-989c-609e4e056433/scratchpad/gh-cellprobe.sh
rm -f "$B/GRID" "$B/GHPIX"
pkill -x ghostty 2>/dev/null; pkill -x Ghostty 2>/dev/null; sleep 1
BENCH_DIR="$B" "$GH" "$@" -e zsh "$PROBE" > "$B/log-ghprobe.txt" 2>&1 &
for i in $(seq 1 30); do [ -s "$B/GRID" ] && break; sleep 1; done
pkill -x ghostty 2>/dev/null; pkill -x Ghostty 2>/dev/null
read -r R C < "$B/GRID" 2>/dev/null || { echo "no grid"; exit 1 }
PIX=$(cat "$B/GHPIX" 2>/dev/null)   # "winops 4;H;Wt"
H=$(printf '%s' "$PIX" | cut -d';' -f2)
W=$(printf '%s' "$PIX" | cut -d';' -f3 | tr -d 't')
echo "$R $C ${H:-0} ${W:-0}"
