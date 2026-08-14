#!/usr/bin/env bash
# Launch both terminals and tile them: ours left, ghostty right.
set -u
B=/var/tmp/bench-film
OURS=/home/starling/dev/starling/apps/TerminalApp/.build-gtk/release/TerminalApp
GH=/var/tmp/ghostty-src-new/zig-out/bin/ghostty
pkill -x TerminalApp 2>/dev/null; pkill -x ghostty 2>/dev/null; sleep 2
rm -f $B/GO $B/grid-* $B/done-* $B/times-*
env -i HOME="$HOME" USER="$USER" PATH=/usr/local/bin:/usr/bin:/bin \
    SHELL=/bin/bash LANG=en_US.UTF-8 \
    XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
    GDK_BACKEND=wayland STARLING_TERMINAL_SINGLE=1 \
    STARLING_WINDOW_W=1880 STARLING_WINDOW_H=2000 \
    STARLING_DEV_SHELL=$B/wrap-ours.sh "$OURS" >/dev/null 2>&1 &
sleep 5
sudo python3 $B/keytap.py super+left
sleep 2
env -i HOME="$HOME" USER="$USER" PATH=/usr/local/bin:/usr/bin:/bin \
    SHELL=/bin/bash LANG=en_US.UTF-8 \
    XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
    "$GH" --window-width=230 --window-height=110 \
    -e bash $B/race.sh gh "GHOSTTY 1.3.2 NIGHTLY" >/dev/null 2>&1 &
sleep 5
sudo python3 $B/keytap.py super+right
sleep 3
echo "grids: ours=$(cat $B/grid-ours 2>/dev/null) gh=$(cat $B/grid-gh 2>/dev/null)"
