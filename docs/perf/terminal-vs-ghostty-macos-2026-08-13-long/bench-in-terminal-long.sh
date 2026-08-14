#!/bin/zsh
# Run the benchmark suite from *inside* a terminal, macOS port.
#
#   bench-in-terminal.sh <label> [runs]
#
# Used as the terminal's shell (STARLING_DEV_SHELL=... for TerminalApp) or as
# its -e command (ghostty). Finds the terminal process by walking up from
# itself to the nearest ancestor that is not a shell wrapper, so neither
# caller has to know the pid in advance — the pid does not exist yet at launch.
#
# Two macOS differences from test/bench/bench-in-terminal.sh:
#
#   - `ps -o comm=` prints a FULL PATH here (/bin/zsh, not zsh), so the
#     shell-wrapper test has to compare basenames. Left as-is it never matches,
#     the walk stops at the first parent, and CPU gets attributed to the login
#     shell instead of the terminal — a wrong number rather than an error.
#   - zsh rather than bash, for $EPOCHREALTIME (see run-bench-long.zsh).
set -u
LABEL="${1:-term}"
RUNS="${2:-3}"
OUTDIR=${BENCH_DIR:-/var/tmp/bench}

pid=$$
term=""
termcomm=""
while :; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] && break
    [ "$ppid" -le 1 ] && break
    comm=$(ps -o comm= -p "$ppid" 2>/dev/null | tr -d ' ')
    base=$(basename "$comm")
    case "$base" in
        bash|sh|dash|zsh|env|sudo|login|bench-in-termi*) ;;
        *) term="$ppid"; termcomm="$base"; break ;;
    esac
    pid="$ppid"
done

if [ -z "$term" ]; then
    echo "bench-in-terminal: could not find the terminal process" >&2
    exec /bin/zsh
fi

# Record what we attributed CPU to, so the report cannot silently measure the
# wrong process.
{
    echo "label $LABEL"
    echo "terminal_pid $term"
    echo "terminal_comm $termcomm"
    echo "grid $(stty size 2>/dev/null | tr ' ' 'x')"
} > "$OUTDIR/meta-$LABEL.txt"

# The runner and its CORPUS come from THIS script's own directory — never
# from $OUTDIR (see the Linux original: resolving through $OUTDIR silently
# replayed a stale corpus at every grid).
SELF_DIR="${0:A:h}"
for i in $(seq 1 "$RUNS"); do
    zsh "$SELF_DIR/run-bench-long.zsh" "$term" "$OUTDIR/res-$LABEL-$i.txt"
done

echo "ALL DONE: $LABEL ($RUNS runs, pid $term / $termcomm)"
exec /bin/zsh
