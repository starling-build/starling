#!/usr/bin/env bash
# Run the benchmark suite from *inside* a terminal, without synthetic input.
#
#   bench-in-terminal.sh <label> [runs]
#
# Used as the terminal's shell (STARLING_DEV_SHELL=... for TerminalApp) or as
# its -e command (ghostty). Finds the terminal process by walking up from
# itself to the nearest ancestor that is not a shell wrapper, so neither
# caller has to know the pid in advance — the pid does not exist yet at launch.
set -u
LABEL="${1:-term}"
RUNS="${2:-3}"
OUTDIR=/var/tmp/bench

pid=$$
term=""
termcomm=""
while :; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] && break
    [ "$ppid" -le 1 ] && break
    comm=$(ps -o comm= -p "$ppid" 2>/dev/null | tr -d ' ')
    case "$comm" in
        bash|sh|dash|zsh|env|sudo|bench-in-termi*) ;;
        *) term="$ppid"; termcomm="$comm"; break ;;
    esac
    pid="$ppid"
done

if [ -z "$term" ]; then
    echo "bench-in-terminal: could not find the terminal process" >&2
    exec /bin/bash
fi

# Record what we attributed CPU to, so the report cannot silently measure the
# wrong process.
{
    echo "label $LABEL"
    echo "terminal_pid $term"
    echo "terminal_comm $termcomm"
    echo "grid $(stty size 2>/dev/null | tr ' ' 'x')"
} > "$OUTDIR/meta-$LABEL.txt"

for i in $(seq 1 "$RUNS"); do
    bash "$OUTDIR/run-bench.sh" "$term" "$OUTDIR/res-$LABEL-$i.txt"
done

echo "ALL DONE: $LABEL ($RUNS runs, pid $term / $termcomm)"
exec /bin/bash
