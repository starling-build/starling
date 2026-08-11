#!/usr/bin/env bash
# Ghostty's three published tests — 150MB ascii cat, 150MB unicode cat,
# DOOM-Fire-Zig — across five terminals at grid 47x201, on the current
# (leak-fixed) TerminalApp build. Same harness as the Aug-4 report:
# bigcat.sh / doomfire.sh run INSIDE each terminal, no synthetic input.
set -u
# The GNOME session user (both terminals must run inside one GNOME
# Wayland session; see README.md).
BENCH_USER=${BENCH_USER:-starling}
BENCH_UID=${BENCH_UID:-$(id -u "$BENCH_USER")}
B=/var/tmp/bench
read -r WW WH < $B/OURS_WINDOW

# Dev-shell wrappers for ours (STARLING_DEV_SHELL takes no args).
cat > $B/shell-bigcat.sh <<'EOF'
#!/usr/bin/env bash
exec /var/tmp/bench/bigcat.sh "$(cat /var/tmp/bench/LABEL)" 3
EOF
cat > $B/shell-doom.sh <<'EOF'
#!/usr/bin/env bash
exec /var/tmp/bench/doomfire.sh "$(cat /var/tmp/bench/LABEL)" 3 600
EOF
chmod 755 $B/shell-bigcat.sh $B/shell-doom.sh

kill_terms() {
    sudo pkill -x TerminalApp 2>/dev/null; sudo pkill -x ghostty 2>/dev/null
    sudo pkill -x alacritty 2>/dev/null; sudo pkill -x kitty 2>/dev/null
    sleep 2
}

launch() {   # launch <kind> <label> <test:bigcat|doom>
    local KIND="$1" LABEL="$2" TEST="$3"
    local SCRIPT=$B/bigcat.sh EXPECT=6 RESULT=$B/bigcat-$LABEL.txt
    if [ "$TEST" = doom ]; then SCRIPT=$B/doomfire.sh; EXPECT=3; RESULT=$B/doom-$LABEL.txt; fi
    kill_terms
    sudo rm -f "$RESULT"
    echo "$LABEL" | sudo tee $B/LABEL >/dev/null
    echo "=== $LABEL / $TEST $(date -u +%H:%M:%S)Z ==="

    local ENVBASE=(sudo -u "$BENCH_USER" env XDG_RUNTIME_DIR=/run/user/"$BENCH_UID" WAYLAND_DISPLAY=wayland-0 GDK_BACKEND=wayland)
    case "$KIND" in
      ours)
        local SH=$B/shell-bigcat.sh; [ "$TEST" = doom ] && SH=$B/shell-doom.sh
        setsid "${ENVBASE[@]}" STARLING_APP_GTK=1 LD_LIBRARY_PATH=$B/gtkrun \
            STARLING_WINDOW_W="$WW" STARLING_WINDOW_H="$WH" STARLING_DEV_SHELL="$SH" \
            $B/gtkrun/TerminalApp > $B/log-$LABEL.txt 2>&1 & ;;
      ghn)
        setsid "${ENVBASE[@]}" /var/tmp/ghostty-nightly/bin/ghostty \
            --window-width=202 --window-height=50 \
            -e "$SCRIPT" "$LABEL" 3 600 > $B/log-$LABEL.txt 2>&1 & ;;
      gh130)
        setsid "${ENVBASE[@]}" /usr/bin/ghostty \
            --window-width=202 --window-height=50 \
            -e "$SCRIPT" "$LABEL" 3 600 > $B/log-$LABEL.txt 2>&1 & ;;
      ala)
        setsid "${ENVBASE[@]}" alacritty \
            -o window.dimensions.columns=201 -o window.dimensions.lines=47 \
            -e bash "$SCRIPT" "$LABEL" 3 600 > $B/log-$LABEL.txt 2>&1 & ;;
      kitty)
        setsid "${ENVBASE[@]}" kitty \
            -o remember_window_size=no -o initial_window_width=201c -o initial_window_height=47c \
            bash "$SCRIPT" "$LABEL" 3 600 > $B/log-$LABEL.txt 2>&1 & ;;
    esac

    local want=$EXPECT
    for i in $(seq 1 90); do
        local got
        if [ "$TEST" = bigcat ]; then
            got=$(sudo grep -c '^\(ascii\|unicode\)' "$RESULT" 2>/dev/null | head -1)
        else
            got=$(sudo grep -c 'cpu_s' "$RESULT" 2>/dev/null | head -1)
        fi
        got=${got:-0}
        [ "$got" -ge "$want" ] && break
        sleep 4
    done
    sudo head -1 "$RESULT" 2>/dev/null || { echo "  NO RESULT"; sudo tail -5 $B/log-$LABEL.txt | sed 's/^/  | /'; }
}

for t in bigcat doom; do
    launch ours  "ours-$t-r9"  "$t"
    launch ghn   "ghn-$t-r9"   "$t"
    launch gh130 "gh130-$t-r9" "$t"
    launch ala   "ala-$t-r9"   "$t"
    launch kitty "kitty-$t-r9" "$t"
done
kill_terms
echo "ALL DONE $(date -u +%H:%M:%S)Z"
