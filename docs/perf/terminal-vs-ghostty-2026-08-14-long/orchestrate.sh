#!/usr/bin/env bash
# The Linux long round: suite (reps -> minutes/workload), 500 MB cats,
# DOOM-Fire 150k frames x3 — ours (GTK) and ghostty tip, GNOME, Dell@1x,
# grids verified 47x201 every leg, wrong-grid ghostty legs retried.
set -u
B=/var/tmp/bench-long
OURS=/home/starling/dev/starling/apps/TerminalApp/.build-gtk/release/TerminalApp
GH=/var/tmp/ghostty-src-new/zig-out/bin/ghostty
FRAMES=150000
LOG=$B/orchestrate.log
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0

say() { echo "$(date -u +%H:%M:%S)Z $*" | tee -a "$LOG"; }
kill_terms() { pkill -x TerminalApp 2>/dev/null; pkill -x ghostty 2>/dev/null; sleep 2; }

# run_leg <suite|bigcat|doom> <ours|gh> <result-file> <done-key> <timeout-s>
run_leg() {
    local TEST="$1" KIND="$2" RESULT="$3" KEY="$4" TMO="$5" tries=0
    while :; do
        tries=$((tries + 1))
        kill_terms
        rm -f "$RESULT" "$B/meta-$KIND.txt"
        local script args
        case "$TEST" in
            suite)  script=$B/bench-in-terminal-long.sh; args="$KIND" ;;
            bigcat) script=$B/bigcat500.sh; args="$KIND" ;;
            doom)   script=$B/doomfire.sh; args="$KIND 3 $FRAMES" ;;
        esac
        say "leg $TEST/$KIND try $tries"
        if [ "$KIND" = ours ]; then
            cat > "$B/wrap.sh" <<W
#!/usr/bin/env bash
exec bash $script $args
W
            chmod 755 "$B/wrap.sh"
            env -i HOME="$HOME" USER="$USER" PATH=/usr/local/bin:/usr/bin:/bin \
                SHELL=/bin/bash LANG=en_US.UTF-8 \
                XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
                GDK_BACKEND=wayland STARLING_TERMINAL_SINGLE=1 \
                STARLING_WINDOW_W=1624 STARLING_WINDOW_H=823 \
                STARLING_DEV_SHELL="$B/wrap.sh" "$OURS" >/dev/null 2>&1 &
        else
            env -i HOME="$HOME" USER="$USER" PATH=/usr/local/bin:/usr/bin:/bin \
                SHELL=/bin/bash LANG=en_US.UTF-8 \
                XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
                "$GH" --window-width=202 --window-height=50 \
                -e bash "$script" $args >/dev/null 2>&1 &
        fi
        local waited=0 bad=0
        while :; do
            sleep 10; waited=$((waited + 10))
            grep -q "$KEY" "$RESULT" 2>/dev/null && break
            # wrong-grid early abort (the 20-minute-leg saver)
            local g=""
            [ -f "$B/meta-$KIND.txt" ] && g=$(awk '/^grid /{print $2}' "$B/meta-$KIND.txt")
            [ -z "$g" ] && [ -f "$RESULT" ] && g=$(head -1 "$RESULT" | grep -o 'grid=[0-9x]*' | cut -d= -f2)
            if [ -n "$g" ] && [ "$g" != "47x201" ]; then
                say "  wrong grid $g — abort"; bad=1; break
            fi
            if [ "$waited" -ge "$TMO" ]; then say "  TIMEOUT"; bad=1; break; fi
        done
        if [ "$bad" = 0 ]; then say "  done ($(grep -c . "$RESULT") lines)"; return 0; fi
        [ "$tries" -ge 3 ] && { say "  giving up"; return 1; }
    done
}

say "ROUND START ours=gtk-58d5f86 gh=f81dcad"
run_leg suite  ours "$B/res-ours-1.txt"   rss_kb     2400
run_leg suite  gh   "$B/res-gh-1.txt"     rss_kb     2400
run_leg bigcat ours "$B/bigcat500-ours.txt" rss_kb   1200
run_leg bigcat gh   "$B/bigcat500-gh.txt"   rss_kb   1200
run_leg doom   ours "$B/doom-ours.txt"    grid_after 1500
run_leg doom   gh   "$B/doom-gh.txt"      grid_after 1500
kill_terms
say "ROUND COMPLETE"
