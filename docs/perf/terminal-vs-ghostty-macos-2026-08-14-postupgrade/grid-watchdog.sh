#!/bin/zsh
# Early-abort for wrong-grid ghostty legs in the long round: a 17x49 launch
# otherwise runs 20-40 wasted minutes before the orchestrator's post-hoc grid
# check discards it. Detect the bad grid from the meta/header the runners
# write at START, kill ghostty, and append the done-key so the orchestrator's
# wait loop returns immediately — its own grid check then fires the retry.
# Only ever touches -gh files, only when the grid is provably wrong, and only
# while the result is still incomplete.
set -u
B=/var/tmp/bench
LOG=$B/bench-long.log
while :; do
    grep -q "BENCH-LONG-DONE" "$LOG" 2>/dev/null && exit 0
    # suite leg: meta written at start, rss_kb written at end
    if [ -f "$B/meta-gh.txt" ] && [ -f "$B/res-gh-1.txt" ]; then
        g=$(grep '^grid ' "$B/meta-gh.txt" | awk '{print $2}')
        if [ -n "$g" ] && [ "$g" != "47x201" ] && ! grep -q rss_kb "$B/res-gh-1.txt"; then
            pkill -x ghostty 2>/dev/null
            sleep 1
            echo "rss_kb 0" >> "$B/res-gh-1.txt"
            echo "watchdog: killed suite leg at $g $(date -u +%H:%M:%S)Z"
        fi
    fi
    # bigcat/doom legs: grid in the result header
    for f in bigcat500-gh:rss_kb doom-gh:grid_after; do
        name=${f%%:*}; key=${f##*:}
        r=$B/$name.txt
        if [ -f "$r" ]; then
            g=$(head -1 "$r" | grep -o 'grid=[0-9x]*' | cut -d= -f2)
            if [ -n "$g" ] && [ "$g" != "47x201" ] && ! grep -q "$key" "$r"; then
                pkill -x ghostty 2>/dev/null
                sleep 1
                echo "$key 0" >> "$r"
                echo "watchdog: killed $name leg at $g $(date -u +%H:%M:%S)Z"
            fi
        fi
    done
    sleep 5
done
