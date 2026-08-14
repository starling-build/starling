#!/bin/zsh
# The LONG round: every test runs minutes, not fractions of a second.
#   - 10-workload suite with per-workload repeat counts targeting >=120 s
#     on the slower side (run-bench-long.zsh; ~17 min ours, ~20 min ghostty)
#   - 500 MB cats, 3 reps (bigcat500-mac.sh)
#   - DOOM-Fire 150 000 frames, 3 reps (~2.5 min per rep)
# Same bench configuration as terminal-vs-ghostty-macos-2026-08-13-samefont:
# matched Roboto Mono via the ghostty config file, grids verified 47x201 on
# every leg, ours at the shipping default cell (no STARLING_CELL_H).
set -u
B=${BENCH_DIR:-/var/tmp/bench}
OUT="${0:A:h}"
OURS=${OURS:-/Users/dishengsu/dev/starling/starling/apps/TerminalApp/.build/release/TerminalApp}
GHOSTTY=${GHOSTTY:-/Users/dishengsu/dev/ghostty-tip/Ghostty.app/Contents/MacOS/ghostty}
FRAMES=150000

read -r WW WH < "$B/OURS_WINDOW"
read -r RC RR < "$B/REQ-gh"

pmset -g batt | head -1
echo "start $(date -u +%H:%M:%S)Z"

kill_terms() {
    pkill -x TerminalApp 2>/dev/null; pkill -x Ghostty 2>/dev/null
    pkill -x ghostty 2>/dev/null
}

# run_leg <test: suite|bigcat|doom> <label> <ours|ghostty> -> 0 ok, 1 bad grid
run_leg() {
    local TEST="$1" LABEL="$2" KIND="$3"
    local RESULT done_key script args
    case "$TEST" in
        suite)  script="$B/corpus/bench-in-terminal-long.sh"; args="$LABEL 1"
                RESULT="$B/res-$LABEL-1.txt"; done_key=rss_kb ;;
        bigcat) script="$B/corpus/bigcat500-mac.sh"; args="$LABEL 3"
                RESULT="$B/bigcat500-$LABEL.txt"; done_key=rss_kb ;;
        doom)   script="$B/corpus/doomfire-mac.sh"; args="$LABEL 3 $FRAMES"
                RESULT="$B/doom-$LABEL.txt"; done_key=grid_after ;;
    esac
    kill_terms; sleep 3
    rm -f "$RESULT"
    [ "$TEST" = suite ] && rm -f "$B/meta-$LABEL.txt"
    echo "=== $TEST/$LABEL ($KIND) $(date -u +%H:%M:%S)Z ==="

    if [ "$KIND" = ours ]; then
        cat > "$B/long-$TEST-$LABEL.sh" <<EOF
#!/bin/zsh
exec zsh "$script" $args
EOF
        chmod 755 "$B/long-$TEST-$LABEL.sh"
        STARLING_TERMINAL_SINGLE=1 \
        STARLING_WINDOW_W="$WW" STARLING_WINDOW_H="$WH" \
        STARLING_DEV_SHELL="$B/long-$TEST-$LABEL.sh" \
        BENCH_DIR="$B" "$OURS" > "$B/log-long-$TEST-$LABEL.txt" 2>&1 &
    else
        BENCH_DIR="$B" "$GHOSTTY" \
            --window-width="$RC" --window-height="$RR" \
            -e zsh "$script" ${=args} \
            > "$B/log-long-$TEST-$LABEL.txt" 2>&1 &
    fi

    # suite legs run ~20 min; wait up to 45 min, others up to 25 min
    local tries=540
    [ "$TEST" = suite ] && tries=900
    for i in $(seq 1 $tries); do
        grep -q "$done_key" "$RESULT" 2>/dev/null && break
        sleep 3
    done
    kill_terms

    if [ ! -f "$RESULT" ]; then
        echo "  NO RESULT"; tail -8 "$B/log-long-$TEST-$LABEL.txt" | sed 's/^/  | /'
        return 1
    fi
    local g
    if [ "$TEST" = suite ]; then
        g=$(grep '^grid ' "$B/meta-$LABEL.txt" 2>/dev/null | awk '{print $2}')
    else
        g=$(head -1 "$RESULT" | grep -o 'grid=[0-9x]*' | cut -d= -f2)
    fi
    sed 's/^/  /' "$RESULT" | head -16
    if [ "$g" != "47x201" ]; then
        echo "  *** GRID $g, WANTED 47x201 — NOT A MEASUREMENT, RETRY ***"
        return 1
    fi
}

# ours first, then ghostty with grid retries — one sitting, interleaved pairs
run_pair() {
    local TEST="$1"
    for a in 1 2 3; do run_leg "$TEST" ours ours && break; echo "  (ours retry $a)"; done
    for a in 1 2 3 4 5 6; do run_leg "$TEST" gh ghostty && break; echo "  (ghostty retry $a)"; done
}

run_pair suite
run_pair bigcat
run_pair doom

echo "=== collecting ==="
mkdir -p "$OUT/data"
cp "$B/res-ours-1.txt" "$OUT/data/res-long-ours.txt" 2>/dev/null
cp "$B/res-gh-1.txt"   "$OUT/data/res-long-gh.txt" 2>/dev/null
cp "$B/meta-ours.txt" "$B/meta-gh.txt" \
   "$B/bigcat500-ours.txt" "$B/bigcat500-gh.txt" \
   "$B/doom-ours.txt" "$B/doom-gh.txt" "$OUT/data/" 2>/dev/null
mv "$OUT/data/doom-ours.txt" "$OUT/data/doom-150k-ours.txt" 2>/dev/null
mv "$OUT/data/doom-gh.txt"   "$OUT/data/doom-150k-gh.txt" 2>/dev/null
pmset -g batt | head -1
echo "BENCH-LONG-DONE $(date -u +%H:%M:%S)Z"
