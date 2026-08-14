#!/usr/bin/env bash
# Long suite from inside the terminal under test. Args: <label>
set -u
LABEL="${1:-term}"
OUTDIR=/var/tmp/bench-long
pid=$$; term=""; termcomm=""
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
[ -z "$term" ] && { echo "no terminal found" >&2; exec /bin/bash; }
{
    echo "label $LABEL"
    echo "terminal_pid $term"
    echo "terminal_comm $termcomm"
    echo "grid $(stty size 2>/dev/null | tr ' ' 'x')"
} > "$OUTDIR/meta-$LABEL.txt"
bash "$OUTDIR/run-bench-long.sh" "$term" "$OUTDIR/res-$LABEL-1.txt"
echo "ALL DONE: $LABEL"
sleep infinity
