#!/usr/bin/env bash
# Head-to-head: TerminalApp (GTK build) vs ghostty, same GNOME session, same
# grid (201x47), same in-terminal runner, 3 runs each.
#
# Same shape as test/bench/core/run-gnome.sh, except ours is pointed at
# shell-bench.sh rather than shell-gnome.sh — the on-disk shell-gnome.sh is a
# profiling script that emits PROF-* markers, not the res-*.txt the runner
# waits for. Neither side needs synthetic input, which GNOME refuses anyway.
set -u
# The GNOME session user (both terminals must run inside one GNOME
# Wayland session; see README.md).
BENCH_USER=${BENCH_USER:-starling}
BENCH_UID=${BENCH_UID:-$(id -u "$BENCH_USER")}
B=/var/tmp/bench
OUT=$(cd "$(dirname "$0")" && pwd)
read -r WW WH < $B/OURS_WINDOW

run_one() {   # run_one <label> <ours|ghostty> <binary>
    local LABEL="$1" KIND="$2" TARGET="$3"
    sudo pkill -x TerminalApp 2>/dev/null; sudo pkill -x ghostty 2>/dev/null; sleep 3
    sudo rm -f $B/res-$LABEL-*.txt $B/meta-$LABEL.txt
    echo "$LABEL" | sudo tee $B/LABEL >/dev/null
    echo "=== $LABEL ($KIND: $TARGET) $(date -u +%H:%M:%S)Z ==="

    if [ "$KIND" = ours ]; then
        setsid sudo -u "$BENCH_USER" env XDG_RUNTIME_DIR=/run/user/"$BENCH_UID" WAYLAND_DISPLAY=wayland-0 \
            GDK_BACKEND=wayland STARLING_APP_GTK=1 LD_LIBRARY_PATH="$B/gtkrun" \
            STARLING_WINDOW_W="$WW" STARLING_WINDOW_H="$WH" \
            STARLING_DEV_SHELL=$B/shell-bench.sh \
            "$B/gtkrun/TerminalApp" > $B/log-$LABEL.txt 2>&1 &
    else
        # Calibrated request, not 201x47: ghostty's flags are a request and
        # 201x47 lands on 200x44. See calib-ghostty.sh.
        local RC RR
        read -r RC RR < "$B/REQ-${LABEL%-new}"
        setsid sudo -u "$BENCH_USER" env XDG_RUNTIME_DIR=/run/user/"$BENCH_UID" WAYLAND_DISPLAY=wayland-0 \
            GDK_BACKEND=wayland \
            "$TARGET" --window-width="$RC" --window-height="$RR" \
            -e $B/bench-in-terminal.sh "$LABEL" 3 \
            > $B/log-$LABEL.txt 2>&1 &
    fi

    for i in $(seq 1 300); do
        sudo test -f "$B/res-$LABEL-3.txt" && sudo grep -q rss_kb "$B/res-$LABEL-3.txt" 2>/dev/null && break
        sleep 5
    done
    sudo pkill -x TerminalApp 2>/dev/null; sudo pkill -x ghostty 2>/dev/null
    if sudo test -f "$B/meta-$LABEL.txt"; then
        sudo cat "$B/meta-$LABEL.txt" | sed 's/^/  /'
    else
        echo "  NO RESULT"; tail -12 "$B/log-$LABEL.txt" | sed 's/^/  | /'
    fi
}

run_one ours-new  ours     "$B/gtkrun/TerminalApp"
run_one ghn-new   ghostty  /var/tmp/ghostty-nightly/bin/ghostty
run_one gh130-new ghostty  /usr/bin/ghostty

echo "=== collecting ==="
sudo chmod a+r $B/res-*-new-*.txt $B/meta-*-new.txt 2>/dev/null
mkdir -p "$OUT/results"
cp $B/res-ours-new-*.txt $B/res-ghn-new-*.txt $B/res-gh130-new-*.txt \
   $B/meta-ours-new.txt $B/meta-ghn-new.txt $B/meta-gh130-new.txt "$OUT/results/" 2>/dev/null
echo "done $(date -u +%H:%M:%S)Z"
