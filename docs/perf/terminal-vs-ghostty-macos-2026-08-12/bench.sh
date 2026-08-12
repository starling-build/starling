#!/bin/zsh
# Head-to-head on macOS: TerminalApp (Cocoa host) vs ghostty, same desktop,
# same grid (201x47), same in-terminal runner, 3 runs each.
#
# Same shape as the Linux round's bench.sh, minus everything that was there to
# get two terminals into one GNOME Wayland session as another user: on macOS
# both are ordinary windows owned by the invoking user, so there is no sudo,
# no XDG_RUNTIME_DIR, no WAYLAND_DISPLAY, no setsid.
#
# Ours runs with STARLING_TERMINAL_SINGLE=1 — the pre-pane, full-window
# TerminalView with no chrome. Without it the app draws the floating-pane
# workspace and the terminal is a BOX INSIDE the window, so the grid would not
# be the window's and the two terminals would not be comparable.
set -u
B=${BENCH_DIR:-/var/tmp/bench}
OUT="${0:A:h}"
OURS=${OURS:-/Users/dishengsu/dev/starling/starling/apps/TerminalApp/.build/release/TerminalApp}
# The binary INSIDE the app bundle: Ghostty.app/Contents/MacOS/ghostty. Run
# that and it launches the GUI and honours -e, exiting when the command does,
# which is exactly the lifecycle the runner wants.
#
# Do not be fooled by a bare `ghostty` on PATH: a standalone copy of that
# executable outside its bundle is only the helper CLI and prints usage ("To
# launch the terminal directly, please launch the graphical app"). Nor is
# `open -na Ghostty.app --args ...` right here — it launches detached, so the
# run cannot be waited on or attributed.
GHOSTTY=${GHOSTTY:?set GHOSTTY to Ghostty.app/Contents/MacOS/ghostty}
RUNS=${RUNS:-3}

read -r WW WH < "$B/OURS_WINDOW"
read -r RC RR < "$B/REQ-gh"

run_one() {   # run_one <label> <ours|ghostty>
    local LABEL="$1" KIND="$2"
    pkill -x TerminalApp 2>/dev/null; pkill -x Ghostty 2>/dev/null; pkill -x ghostty 2>/dev/null; sleep 3
    rm -f "$B"/res-$LABEL-*.txt "$B/meta-$LABEL.txt"
    echo "=== $LABEL ($KIND) $(date -u +%H:%M:%S)Z ==="

    if [ "$KIND" = ours ]; then
        # Our terminal execs its shell with no arguments, so the label and run
        # count are baked into a per-label wrapper.
        cat > "$B/shell-$LABEL.sh" <<EOF
#!/bin/zsh
exec zsh "$B/corpus/bench-in-terminal.sh" "$LABEL" $RUNS
EOF
        chmod 755 "$B/shell-$LABEL.sh"
        STARLING_TERMINAL_SINGLE=1 \
        STARLING_WINDOW_W="$WW" STARLING_WINDOW_H="$WH" \
        STARLING_DEV_SHELL="$B/shell-$LABEL.sh" \
        BENCH_DIR="$B" "$OURS" > "$B/log-$LABEL.txt" 2>&1 &
    else
        BENCH_DIR="$B" "$GHOSTTY" \
            --window-width="$RC" --window-height="$RR" \
            -e zsh "$B/corpus/bench-in-terminal.sh" "$LABEL" $RUNS \
            > "$B/log-$LABEL.txt" 2>&1 &
    fi

    for i in $(seq 1 300); do
        [ -f "$B/res-$LABEL-$RUNS.txt" ] && grep -q rss_kb "$B/res-$LABEL-$RUNS.txt" 2>/dev/null && break
        sleep 5
    done
    pkill -x TerminalApp 2>/dev/null; pkill -x Ghostty 2>/dev/null; pkill -x ghostty 2>/dev/null
    if [ -f "$B/meta-$LABEL.txt" ]; then
        sed 's/^/  /' "$B/meta-$LABEL.txt"
    else
        echo "  NO RESULT"; tail -12 "$B/log-$LABEL.txt" | sed 's/^/  | /'
    fi
}

run_one ours ours
run_one gh   ghostty

echo "=== collecting ==="
mkdir -p "$OUT/data"
cp "$B"/res-ours-*.txt "$B"/res-gh-*.txt "$B"/meta-ours.txt "$B"/meta-gh.txt \
   "$OUT/data/" 2>/dev/null
echo "done $(date -u +%H:%M:%S)Z"
