#!/usr/bin/env bash
# run-gnome-fs.sh <label> ours|ghostty <binary> — the FULLSCREEN protocol.
#
# Every terminal gets the same monitor mode, the same pixel area, the same
# font at the same rendered size, and therefore the same grid — "window
# size" stops being a per-terminal calibration:
#
#   - Session at 1920x1080 @ scale 1 (set it with mutter DisplayConfig; at a
#     fractional scale the field is TILTED: a GTK3 client renders at integer
#     scale 2 and is downscaled by the compositor while ghostty renders
#     native fractional — neither the pixel areas nor the buffers match).
#   - Both fullscreen: ours via STARLING_WINDOW_FULLSCREEN=1, ghostty via
#     --fullscreen=true (the bare flag form is ignored).
#   - Same font: Roboto Mono, the repo's own TTFs, installed for the bench
#     user (fc-match "Roboto Mono" must resolve). Ours renders 13 logical px;
#     ghostty gets --font-size=9.75 (points at 96 dpi = 13 px).
#   - Same cell: freetype hints the advance to 8.0 px where our shaper keeps
#     the fractional 7.8, so ours runs STARLING_CELL_W=8.0 and ghostty runs
#     --window-padding-x/y=6 so both floors land on the same column count.
#     On this protocol's screen both terminals verify at 238x62.
#   - The corpus is regenerated for that grid (gen-bench.py <dir> 238 62 into
#     /var/tmp/benchfs) so the cell-fill workloads fill every column.
#
# Verify the grid line in meta-<label>.txt before believing any number.
set -u
LABEL="$1"; KIND="$2"; TARGET="$3"
G=/var/tmp/bench/gtkrun
# The corpus dir — regenerated for the protocol's VERIFIED grid (238x62 at
# 1080p, 478x126 at native 4K; gen-bench.py <dir> <cols> <rows>).
B=${BENCH_FS_DIR:-/var/tmp/benchfs}
BENCH_USER=${BENCH_USER:-starling}
BENCH_UID=${BENCH_UID:-$(id -u "$BENCH_USER")}
pkill -x TerminalApp 2>/dev/null; pkill -x ghostty 2>/dev/null; sleep 2
rm -f /var/tmp/bench/res-$LABEL-*.txt /var/tmp/bench/meta-$LABEL.txt
echo "$LABEL" > /var/tmp/bench/LABEL

# Stage the runner pair from the REPO into the corpus dir: bench-in-terminal
# resolves run-bench.sh (and run-bench resolves the corpus) from its own
# directory, so everything the run touches lives in $B.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/../bench-in-terminal.sh" "$SCRIPT_DIR/../run-bench.sh" "$B/"
chmod 755 "$B/bench-in-terminal.sh" "$B/run-bench.sh"

# Both terminals exec their command BEFORE the fullscreen configure lands,
# so the runner first waits for the grid to hold still (the same race made
# an early grid probe read the pre-fullscreen size).
RUNS=${BENCH_RUNS:-3}
cat > $B/wait-grid-then-bench.sh <<EOF
#!/usr/bin/env bash
prev=""; stable=0
for i in \$(seq 1 20); do
  cur=\$(stty size)
  [ "\$cur" = "\$prev" ] && stable=\$((stable+1)) || stable=0
  [ \$stable -ge 3 ] && break
  prev="\$cur"; sleep 1
done
exec $B/bench-in-terminal.sh "\$1" $RUNS
EOF
cat > $B/shell-gnome-fs.sh <<EOF
#!/usr/bin/env bash
exec $B/wait-grid-then-bench.sh "\$(cat /var/tmp/bench/LABEL)"
EOF
chmod 755 $B/shell-gnome-fs.sh $B/wait-grid-then-bench.sh

ENVB=(sudo -u "$BENCH_USER" env XDG_RUNTIME_DIR=/run/user/"$BENCH_UID"
      WAYLAND_DISPLAY=wayland-0 GDK_BACKEND=wayland)

if [ "$KIND" = ours ]; then
    cp "$TARGET" "$G/TerminalApp"
    setsid "${ENVB[@]}" STARLING_APP_GTK=1 LD_LIBRARY_PATH="$G" \
        STARLING_WINDOW_FULLSCREEN=1 STARLING_CELL_W=8.0 \
        STARLING_DEV_SHELL=$B/shell-gnome-fs.sh \
        "$G/TerminalApp" > /var/tmp/bench/log-$LABEL.txt 2>&1 &
else
    setsid "${ENVB[@]}" \
        "$TARGET" --fullscreen=true --font-family="Roboto Mono" \
        --font-size=9.75 --window-padding-x=6 --window-padding-y=6 \
        -e $B/wait-grid-then-bench.sh "$LABEL" \
        > /var/tmp/bench/log-$LABEL.txt 2>&1 &
fi

for i in $(seq 1 240); do
    [ -f "/var/tmp/bench/res-$LABEL-$RUNS.txt" ] && grep -q rss_kb "/var/tmp/bench/res-$LABEL-$RUNS.txt" 2>/dev/null && break
    sleep 5
done
cat /var/tmp/bench/meta-$LABEL.txt 2>/dev/null || { echo "$LABEL: NO RESULT"; tail -8 /var/tmp/bench/log-$LABEL.txt; }
