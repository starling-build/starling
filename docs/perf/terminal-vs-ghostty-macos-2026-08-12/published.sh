#!/bin/zsh
# Ghostty's own three published tests on macOS: `cat 150mb_ascii`,
# `cat 150mb_unicode`, and DOOM-Fire-Zig frames-per-second.
#
# The Linux rounds have run these since 2026-08-04 (that round's bigcat.sh and
# doomfire.sh); the macOS round measured them and never wrote them up, which
# is the gap this closes. They matter because they are the set ghostty itself
# advertises, and because they disagree with our 10-workload suite: the suite
# is `cat` throughput at one grid, while DOOM-Fire is a FRAME RATE test and is
# the only thing here that puts the renderer on the critical path.
#
# Same lifecycle as bench.sh: each terminal executes the runner itself (ours
# through STARLING_DEV_SHELL, ghostty through -e), because neither reports a
# grid until its window has been created and resized. Both runners end in
# `exec /bin/zsh`, so completion is detected from the output file, not the
# process exiting.
#
# VERIFY THE GRID. Both scripts record `grid=` in their header and doomfire
# records `grid_after` as a second check; ghostty intermittently comes up at
# 17x49 instead of 47x201 (see report.md), and at 49 columns the fire draws a
# quarter of the cells and the cat wraps four times. A run whose grid is not
# 47x201 is not a measurement, it is a different test.
set -u
B=${BENCH_DIR:-/var/tmp/bench}
OUT="${0:A:h}"
OURS=${OURS:-/Users/dishengsu/dev/starling/starling/apps/TerminalApp/.build/release/TerminalApp}
GHOSTTY=${GHOSTTY:?set GHOSTTY to Ghostty.app/Contents/MacOS/ghostty}
REPS=${REPS:-3}
FRAMES=${FRAMES:-600}
WANT_GRID=${WANT_GRID:-47x201}

read -r WW WH < "$B/OURS_WINDOW"
read -r RC RR < "$B/REQ-gh"

# run_one <test: bigcat|doom> <label> <ours|ghostty>
run_one() {
    local TEST="$1" LABEL="$2" KIND="$3"
    local script done_key
    if [ "$TEST" = bigcat ]; then
        script="$B/corpus/bigcat-mac.sh"; done_key=rss_kb
    else
        script="$B/corpus/doomfire-mac.sh"; done_key=grid_after
    fi
    local RESULT="$B/$TEST-$LABEL.txt"

    pkill -x TerminalApp 2>/dev/null; pkill -x Ghostty 2>/dev/null
    pkill -x ghostty 2>/dev/null; sleep 3
    rm -f "$RESULT"
    echo "=== $TEST/$LABEL ($KIND) $(date -u +%H:%M:%S)Z ==="

    if [ "$KIND" = ours ]; then
        # Ours execs its shell with no arguments, so the label, reps and frame
        # count have to be baked into a per-run wrapper.
        cat > "$B/pub-$LABEL.sh" <<EOF
#!/bin/zsh
exec zsh "$script" "$LABEL" $REPS $FRAMES
EOF
        chmod 755 "$B/pub-$LABEL.sh"
        STARLING_TERMINAL_SINGLE=1 \
        STARLING_WINDOW_W="$WW" STARLING_WINDOW_H="$WH" \
        STARLING_DEV_SHELL="$B/pub-$LABEL.sh" \
        BENCH_DIR="$B" "$OURS" > "$B/log-$TEST-$LABEL.txt" 2>&1 &
    else
        BENCH_DIR="$B" "$GHOSTTY" \
            --window-width="$RC" --window-height="$RR" \
            -e zsh "$script" "$LABEL" $REPS $FRAMES \
            > "$B/log-$TEST-$LABEL.txt" 2>&1 &
    fi

    for i in $(seq 1 300); do
        grep -q "$done_key" "$RESULT" 2>/dev/null && break
        sleep 2
    done
    pkill -x TerminalApp 2>/dev/null; pkill -x Ghostty 2>/dev/null
    pkill -x ghostty 2>/dev/null

    if [ ! -f "$RESULT" ]; then
        echo "  NO RESULT"; tail -12 "$B/log-$TEST-$LABEL.txt" | sed 's/^/  | /'
        return 1
    fi
    local g=$(head -1 "$RESULT" | grep -o 'grid=[0-9x]*' | cut -d= -f2)
    sed 's/^/  /' "$RESULT"
    if [ "$g" != "$WANT_GRID" ]; then
        echo "  *** GRID $g, WANTED $WANT_GRID — NOT A MEASUREMENT, RETRY ***"
        return 1
    fi
}

# Retry the ghostty side until its grid is right; ours has never missed.
run_pair() {
    local TEST="$1"
    run_one "$TEST" ours ours
    for a in 1 2 3 4 5 6; do
        run_one "$TEST" gh ghostty && break
        echo "  (ghostty retry $a)"
    done
}

run_pair bigcat
run_pair doom

echo "=== collecting ==="
mkdir -p "$OUT/data"
cp "$B"/bigcat-ours.txt "$B"/bigcat-gh.txt "$B"/doom-ours.txt "$B"/doom-gh.txt \
   "$OUT/data/" 2>/dev/null
echo "done $(date -u +%H:%M:%S)Z"
