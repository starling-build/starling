#!/usr/bin/env bash
# The three ghostty legs, accepting 47x201 or 47x202 (today's launches all
# drift one column; corpus is 201 wide so nothing wraps).
set -u
B=/var/tmp/bench-long
GH=/var/tmp/ghostty-src-new/zig-out/bin/ghostty
LOG=$B/orchestrate.log
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
say() { echo "$(date -u +%H:%M:%S)Z $*" | tee -a "$LOG"; }
kill_terms() { pkill -x TerminalApp 2>/dev/null; pkill -x ghostty 2>/dev/null; sleep 2; }

run_gh() {
    local TEST="$1" RESULT="$2" KEY="$3" TMO="$4" tries=0
    local script args
    case "$TEST" in
        suite)  script=$B/bench-in-terminal-long.sh; args="gh" ;;
        bigcat) script=$B/bigcat500.sh; args="gh" ;;
        doom)   script=$B/doomfire.sh; args="gh 3 150000" ;;
    esac
    while :; do
        tries=$((tries+1)); kill_terms
        rm -f "$RESULT" "$B/meta-gh.txt"
        say "manual leg $TEST/gh try $tries"
        env -i HOME="$HOME" USER="$USER" PATH=/usr/local/bin:/usr/bin:/bin \
            SHELL=/bin/bash LANG=en_US.UTF-8 \
            XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
            "$GH" --window-width=202 --window-height=50 \
            -e bash "$script" $args >/dev/null 2>&1 &
        local waited=0 bad=0
        while :; do
            sleep 10; waited=$((waited+10))
            grep -q "$KEY" "$RESULT" 2>/dev/null && break
            local g=""
            [ -f "$B/meta-gh.txt" ] && g=$(awk '/^grid /{print $2}' "$B/meta-gh.txt")
            [ -z "$g" ] && [ -f "$RESULT" ] && g=$(head -1 "$RESULT" | grep -o 'grid=[0-9x]*' | cut -d= -f2)
            case "$g" in ""|47x201|47x202) ;; *) say "  wrong grid $g — abort"; bad=1; break ;; esac
            [ "$waited" -ge "$TMO" ] && { say "  TIMEOUT"; bad=1; break; }
        done
        if [ "$bad" = 0 ]; then say "  done grid=$( { awk '/^grid /{print $2}' "$B/meta-gh.txt" 2>/dev/null; head -1 "$RESULT" | grep -o 'grid=[0-9x]*'; } | head -1 )"; return 0; fi
        [ "$tries" -ge 3 ] && { say "  giving up"; return 1; }
    done
}

say "MANUAL GH LEGS START"
run_gh suite  "$B/res-gh-1.txt"      rss_kb     2400
run_gh bigcat "$B/bigcat500-gh.txt"  rss_kb     1200
run_gh doom   "$B/doom-gh.txt"       grid_after 2400
kill_terms
say "MANUAL GH LEGS COMPLETE"
