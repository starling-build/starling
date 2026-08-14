#!/bin/zsh
# DOOM-Fire-Zig throughput, macOS port of
# docs/perf/terminal-vs-ghostty-2026-08-14-long/doomfire.sh — same three
# substitutions as the other mac runners: zsh, `ps -o time=` for /proc, and a
# basename compare in the ancestor walk. Reconstructed 2026-08-14 after the
# macOS upgrade wiped /var/tmp/bench (the checkpoint missed this one file);
# output format matches terminal-vs-ghostty-macos-2026-08-14-long/data/.
#
#   doomfire-mac.sh <label> [reps] [frames]
set -u
zmodload zsh/datetime
LABEL="${1:-term}"
REPS="${2:-3}"
FRAMES="${3:-600}"
DIR=${BENCH_DIR:-/var/tmp/bench}
BIN=$HOME/dev/doomfire-bench/zig-out/bin/DOOM-fire

pid=$$; term=""; termcomm=""
while :; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] && break
    [ "$ppid" -le 1 ] && break
    comm=$(ps -o comm= -p "$ppid" 2>/dev/null | tr -d ' ')
    base=$(basename "$comm")
    case "$base" in
        bash|sh|dash|zsh|env|sudo|login|doomfire-mac.sh) ;;
        *) term="$ppid"; termcomm="$base"; break ;;
    esac
    pid="$ppid"
done
[ -z "$term" ] && { echo "doomfire: no terminal found" >&2; exec /bin/zsh }

cpu() {
    local t
    t=$(ps -o time= -p "$term" 2>/dev/null | tr -d ' ')
    [[ -z "$t" ]] && { print 0; return }
    print -r -- "$t" | awk -F: '{ if (NF==3) print $1*3600+$2*60+$3; else if (NF==2) print $1*60+$2; else print $1 }'
}
reset_term() { printf '\033[0m\033[r\033[?1049l\033[2J\033[H' }

# settle before recording the grid (window-resize race, see the other runners)
sleep 3
OUT="$DIR/doom-$LABEL.txt"
: > "$OUT"
print "# $LABEL terminal=$term/$termcomm grid=$(stty size | tr ' ' x) frames=$FRAMES" >> "$OUT"

for r in $(seq 1 "$REPS"); do
    reset_term; sleep 1
    c0=$(cpu)
    DOOMFIRE_FRAMES="$FRAMES" "$BIN" 2>> "$OUT"
    c1=$(cpu)
    reset_term
    awk -v c0="$c0" -v c1="$c1" 'BEGIN{ printf "  cpu_s %.2f\n", c1-c0 }' >> "$OUT"
done

print "grid_after $(stty size | tr ' ' x)" >> "$OUT"
reset_term
print "DOOM DONE: $LABEL"
exec /bin/zsh
