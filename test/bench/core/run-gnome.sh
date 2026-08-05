#!/usr/bin/env bash
# run-gnome.sh <label> ours|ghostty <binary> [win_w win_h | cols rows]
# Runs the in-terminal suite in the GNOME Wayland session as user starling.
set -u
LABEL="$1"; KIND="$2"; TARGET="$3"; A="${4:-}"; B="${5:-}"
G=/var/tmp/bench/gtkrun
pkill -x TerminalApp 2>/dev/null; pkill -x ghostty 2>/dev/null; sleep 2
rm -f /var/tmp/bench/res-$LABEL-*.txt /var/tmp/bench/meta-$LABEL.txt
echo "$LABEL" > /var/tmp/bench/LABEL

if [ "$KIND" = ours ]; then
    cp "$TARGET" "$G/TerminalApp"
    setsid sudo -u starling env XDG_RUNTIME_DIR=/run/user/1001 WAYLAND_DISPLAY=wayland-0 \
        GDK_BACKEND=wayland STARLING_APP_GTK=1 LD_LIBRARY_PATH="$G" \
        STARLING_WINDOW_W="$A" STARLING_WINDOW_H="$B" \
        STARLING_DEV_SHELL=/var/tmp/bench/shell-gnome.sh \
        "$G/TerminalApp" > /var/tmp/bench/log-$LABEL.txt 2>&1 &
else
    setsid sudo -u starling env XDG_RUNTIME_DIR=/run/user/1001 WAYLAND_DISPLAY=wayland-0 \
        GDK_BACKEND=wayland \
        "$TARGET" --window-width="$A" --window-height="$B" \
        -e /var/tmp/bench/bench-in-terminal.sh "$LABEL" 3 \
        > /var/tmp/bench/log-$LABEL.txt 2>&1 &
fi

for i in $(seq 1 240); do
    [ -f "/var/tmp/bench/res-$LABEL-3.txt" ] && grep -q rss_kb "/var/tmp/bench/res-$LABEL-3.txt" 2>/dev/null && break
    sleep 5
done
cat /var/tmp/bench/meta-$LABEL.txt 2>/dev/null || { echo "$LABEL: NO RESULT"; tail -8 /var/tmp/bench/log-$LABEL.txt; }
