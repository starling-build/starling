#!/bin/zsh
# Terminal benchmark runner, macOS port — runs INSIDE the terminal under test.
#
#   run-bench.zsh <terminal-pid> <results-file>
#
# Same contract as test/bench/run-bench.sh (identical output format, identical
# workload order, identical reset-between-tests discipline) with the three
# Linux-only reads replaced:
#
#   wall clock  $EPOCHREALTIME is a bash 5 builtin and macOS ships bash 3.2.
#               zsh has the same variable via zmodload zsh/datetime and it is
#               likewise a BUILTIN — that matters more than it looks, because
#               06_cursor_motion finishes in ~0.015 s and a `date`/`python3`
#               subprocess (10-30 ms) inside the timed region would be a
#               larger error than the measurement.
#   cpu         /proc/<pid>/stat fields 14+15 -> `ps -o time=`, which reports
#               the process's cumulative user+system CPU as [HH:]MM:SS.ss.
#               Read outside the timed region, exactly as the Linux version
#               reads /proc, so its own cost never lands in wall_s.
#   rss         /proc/<pid>/status VmRSS -> `ps -o rss=` (already KB).
set -u
zmodload zsh/datetime

PID="$1"; OUT="$2"
DIR="${0:A:h}"

# "MM:SS.ss" or "HH:MM:SS.ss" -> seconds.
cpu() {
    local t
    t=$(ps -o time= -p "$PID" 2>/dev/null | tr -d ' ')
    [[ -z "$t" ]] && { print 0; return }
    print -r -- "$t" | awk -F: '{
        if (NF == 3)      { print $1*3600 + $2*60 + $3 }
        else if (NF == 2) { print $1*60 + $2 }
        else              { print $1 }
    }'
}

# Leave the terminal in a known state between tests: attributes off, scroll
# region full, primary screen, cleared. Without this the alt-screen and
# scroll-region workloads bleed into whatever runs next.
reset_term() { printf '\033[0m\033[r\033[?1049l\033[2J\033[H' }

: > "$OUT"
print "# test wall_s cpu_s" >> "$OUT"

for f in "$DIR"/[0-9]*.txt; do
    name=$(basename "$f" .txt)
    cat "$f" > /dev/null            # warm page cache — not timed
    reset_term
    sleep 0.7                       # let the terminal settle/idle first

    c0=$(cpu); t0=$EPOCHREALTIME
    cat "$f"
    t1=$EPOCHREALTIME; c1=$(cpu)

    reset_term
    awk -v n="$name" -v t0="$t0" -v t1="$t1" -v c0="$c0" -v c1="$c1" \
        'BEGIN{ printf "%s %.3f %.2f\n", n, t1-t0, c1-c0 }' >> "$OUT"
done

# Resident set after the whole run — how much the terminal is holding onto
# after 400 MB of output has gone through it.
print "rss_kb $(ps -o rss= -p "$PID" | tr -d ' ')" >> "$OUT"
reset_term
print "BENCH-DONE"
