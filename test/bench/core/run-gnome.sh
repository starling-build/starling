#!/usr/bin/env bash
# run-gnome.sh <label> ours|ghostty <binary> [win_w win_h | cols rows]
# Runs the in-terminal suite in the GNOME Wayland session as user $BENCH_USER.
set -u
LABEL="$1"; KIND="$2"; TARGET="$3"; A="${4:-}"; B="${5:-}"
G=/var/tmp/bench/gtkrun
BENCH_USER=${BENCH_USER:-starling}
BENCH_UID=${BENCH_UID:-$(id -u "$BENCH_USER")}
pkill -x TerminalApp 2>/dev/null; pkill -x ghostty 2>/dev/null; sleep 2
rm -f /var/tmp/bench/res-$LABEL-*.txt /var/tmp/bench/meta-$LABEL.txt
echo "$LABEL" > /var/tmp/bench/LABEL

# Both terminals run the SAME runner; ours gets it as its dev shell. Written
# here, every run, because a stale /var/tmp/bench copy of this wrapper once
# turned out to be a profiling script from an earlier session — the runner
# then never produced res-*.txt and this loop waited out its full timeout.
cat > /var/tmp/bench/shell-gnome.sh <<'EOF'
#!/usr/bin/env bash
exec /var/tmp/bench/bench-in-terminal.sh "$(cat /var/tmp/bench/LABEL)" 3
EOF
chmod 755 /var/tmp/bench/shell-gnome.sh

if [ "$KIND" = ours ]; then
    cp "$TARGET" "$G/TerminalApp"
    setsid sudo -u "$BENCH_USER" env XDG_RUNTIME_DIR=/run/user/"$BENCH_UID" WAYLAND_DISPLAY=wayland-0 \
        GDK_BACKEND=wayland STARLING_APP_GTK=1 LD_LIBRARY_PATH="$G" \
        STARLING_WINDOW_W="$A" STARLING_WINDOW_H="$B" \
        STARLING_DEV_SHELL=/var/tmp/bench/shell-gnome.sh \
        "$G/TerminalApp" > /var/tmp/bench/log-$LABEL.txt 2>&1 &
else
    setsid sudo -u "$BENCH_USER" env XDG_RUNTIME_DIR=/run/user/"$BENCH_UID" WAYLAND_DISPLAY=wayland-0 \
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
