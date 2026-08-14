#!/bin/zsh
# Ghostty's published `time cat 150MB_ascii.txt` / unicode test, macOS port of
# docs/perf/terminal-vs-ghostty-2026-08-04/bigcat.sh. Same three substitutions
# the suite runner needed: zsh for $EPOCHREALTIME (a builtin here, bash 3.2 has
# none), `ps -o time=` for /proc/<pid>/stat, and a basename compare in the
# ancestor walk because `ps -o comm=` prints a full path on macOS.
set -u
zmodload zsh/datetime
LABEL="${1:-term}"
REPS="${2:-3}"
DIR=${BENCH_DIR:-/var/tmp/bench}

pid=$$; term=""; termcomm=""
while :; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] && break
    [ "$ppid" -le 1 ] && break
    comm=$(ps -o comm= -p "$ppid" 2>/dev/null | tr -d ' ')
    base=$(basename "$comm")
    case "$base" in
        bash|sh|dash|zsh|env|sudo|login|bigcat500-mac.sh) ;;
        *) term="$ppid"; termcomm="$base"; break ;;
    esac
    pid="$ppid"
done
[ -z "$term" ] && { echo "bigcat: no terminal found" >&2; exec /bin/zsh }

cpu() {
    local t
    t=$(ps -o time= -p "$term" 2>/dev/null | tr -d ' ')
    [[ -z "$t" ]] && { print 0; return }
    print -r -- "$t" | awk -F: '{ if (NF==3) print $1*3600+$2*60+$3; else if (NF==2) print $1*60+$2; else print $1 }'
}
reset_term() { printf '\033[0m\033[r\033[?1049l\033[2J\033[H' }

# Wait out the window-resize race before recording the grid (see
# bench-in-terminal-long.sh) — the transient 17x49 was getting good legs
# killed by the watchdog.
sleep 3
OUT="$DIR/bigcat500-$LABEL.txt"
: > "$OUT"
print "# $LABEL terminal=$term/$termcomm grid=$(stty size | tr ' ' x)" >> "$OUT"

for f in ascii_500mb unicode_500mb; do
    cat "$DIR/$f.txt" > /dev/null          # warm the page cache, not timed
    for r in $(seq 1 "$REPS"); do
        reset_term; sleep 1
        c0=$(cpu); t0=$EPOCHREALTIME
        cat "$DIR/$f.txt"
        t1=$EPOCHREALTIME; c1=$(cpu)
        reset_term
        awk -v n="$f" -v t0="$t0" -v t1="$t1" -v c0="$c0" -v c1="$c1" \
            'BEGIN{ printf "%s %.3f %.2f\n", n, t1-t0, c1-c0 }' >> "$OUT"
    done
done
print "rss_kb $(ps -o rss= -p "$term" | tr -d ' ')" >> "$OUT"
reset_term
print "BIGCAT DONE: $LABEL"
exec /bin/zsh
