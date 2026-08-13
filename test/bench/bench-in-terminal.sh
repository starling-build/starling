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

# The runner and its CORPUS come from THIS script's own directory — never
# from $OUTDIR. The fullscreen protocol stages a regenerated corpus per
# grid; resolving run-bench.sh through $OUTDIR silently replayed
# /var/tmp/bench's original 200-col corpus at every grid (caught when a
# 244 MB alt_screen "catted" in 0.087 s — 2.8 GB/s through a pty).
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# A codepoint with no glyph in any loaded face paints nothing — and painting
# nothing is cheaper than shaping and rasterising, so a coverage gap arrives
# as a BETTER number with no other check objecting (the core battery compares
# the grid, where the cell is correct). Gate the corpus before timing it, and
# refuse to produce numbers that would flatter us for not drawing.
#
# Captured rather than piped: `cmd | tail` reports TAIL's exit status, so the
# obvious spelling of this check passes on every failure it exists to catch.
if ! gate=$(python3 "$SELF_DIR/glyph-gate.py" "$SELF_DIR" 2>&1); then
    echo "$gate" | tail -20
    echo "bench-in-terminal: corpus has characters this build cannot draw —" >&2
    echo "  the numbers would reward the gap. Fix the fallback chain first." >&2
    exec /bin/bash
fi
echo "$gate" | tail -2

for i in $(seq 1 "$RUNS"); do
    bash "$SELF_DIR/run-bench.sh" "$term" "$OUTDIR/res-$LABEL-$i.txt"
done

echo "ALL DONE: $LABEL ($RUNS runs, pid $term / $termcomm)"
exec /bin/bash
