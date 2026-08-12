#!/bin/zsh
# Solve both terminals onto EXACTLY the same grid (201x47, the grid every
# archived Linux round used), macOS port of calibrate.sh + calib-ghostty.sh.
#
# Matching cell-for-cell is the whole point: the cell-filling workloads scale
# with cell count, so an unmatched grid silently rewards whichever terminal
# got the smaller window.
#
# Ours takes window PIXELS, so two measurements give cell size and chrome
# padding:  cols = floor((W - padX) / cellW).
# ghostty takes a CELL request that it does not honour exactly, so that side
# is solved by iterating the request until stty size reports 201x47.
#
# No sudo, no GNOME/Wayland plumbing: on macOS both terminals are ordinary
# windows owned by the invoking user.
set -u
B=${BENCH_DIR:-/var/tmp/bench}
HERE="${0:A:h}"
OURS=${OURS:-/Users/dishengsu/dev/starling/starling/apps/TerminalApp/.build/release/TerminalApp}
# App bundle, not binary — see bench.sh.
GHOSTTY_APP=${GHOSTTY_APP:?set GHOSTTY_APP to the built Ghostty.app}
TARGET_C=${TARGET_C:-201}
TARGET_R=${TARGET_R:-47}

mkdir -p "$B"

# The grid probe. Our terminal execs its shell with NO arguments (see
# Pty._shellPath), so anything it must know has to be baked into the script.
#
# The leading sleep is load-bearing. The shell starts on a pty created at its
# INITIAL 80x24 and TerminalView issues resizeProcess() from its first build,
# so reading stty size immediately is a race the probe usually wins — and when
# it wins it reports 80x24, which the solver then reads as "both window sizes
# gave the same grid" and divides by zero. Ghostty needs the same grace: its
# window is also sized after the child is spawned.
cat > "$B/grid-probe.sh" <<EOF
#!/bin/zsh
sleep 3
stty size > $B/GRID 2>&1
sleep 1
EOF
chmod 755 "$B/grid-probe.sh"

measure_ours() {   # measure_ours <w> <h> -> "rows cols"
    rm -f "$B/GRID"; pkill -x TerminalApp 2>/dev/null; sleep 1
    STARLING_TERMINAL_SINGLE=1 STARLING_WINDOW_W="$1" STARLING_WINDOW_H="$2" \
        STARLING_DEV_SHELL="$B/grid-probe.sh" \
        "$OURS" > "$B/log-grid.txt" 2>&1 &
    for i in $(seq 1 30); do [ -s "$B/GRID" ] && break; sleep 1; done
    pkill -x TerminalApp 2>/dev/null
    cat "$B/GRID" 2>/dev/null
}

probe_ghostty() {  # probe_ghostty <req_cols> <req_rows> -> "rows cols"
    rm -f "$B/GRID"; pkill -x Ghostty 2>/dev/null; pkill -x ghostty 2>/dev/null; sleep 1
    open -na "$GHOSTTY_APP" --args --window-width="$1" --window-height="$2" \
        -e "$B/grid-probe.sh" > "$B/log-probe.txt" 2>&1
    for i in $(seq 1 30); do [ -s "$B/GRID" ] && break; sleep 1; done
    pkill -x Ghostty 2>/dev/null; pkill -x ghostty 2>/dev/null
    cat "$B/GRID" 2>/dev/null
}

echo "=== ours: solving window pixels for ${TARGET_C}x${TARGET_R} ==="
read -r R1 C1 <<< "$(measure_ours 1600 900)"; echo "  1600x900 -> ${C1}x${R1}"
read -r R2 C2 <<< "$(measure_ours 1200 700)"; echo "  1200x700 -> ${C2}x${R2}"
if [ -z "${C1:-}" ] || [ -z "${C2:-}" ] || [ "$C1" = "$C2" ]; then
    echo "  probe failed (no grid, or the two sizes gave the same grid)"; exit 1
fi

read -r TW TH <<< "$(awk -v w1=1600 -v w2=1200 -v c1="$C1" -v c2="$C2" \
                         -v h1=900 -v h2=700 -v r1="$R1" -v r2="$R2" \
                         -v tc="$TARGET_C" -v tr="$TARGET_R" 'BEGIN{
    cw=(w1-w2)/(c1-c2); px=w1-c1*cw
    ch=(h1-h2)/(r1-r2); py=h1-r1*ch
    printf "%d %d", int(tc*cw+px+0.5), int(tr*ch+py+0.5)
}')"
echo "  solved target window ${TW}x${TH}"

read -r RF CF <<< "$(measure_ours "$TW" "$TH")"; echo "  verify ${TW}x${TH} -> ${CF}x${RF}"
tries=0
while { [ "$CF" != "$TARGET_C" ] || [ "$RF" != "$TARGET_R" ]; } && [ $tries -lt 5 ]; do
    cw=$(awk -v a=1600 -v b=1200 -v c="$C1" -v d="$C2" 'BEGIN{print (a-b)/(c-d)}')
    ch=$(awk -v a=900 -v b=700 -v c="$R1" -v d="$R2" 'BEGIN{print (a-b)/(c-d)}')
    TW=$(awk -v t="$TW" -v n="$TARGET_C" -v g="$CF" -v cw="$cw" 'BEGIN{printf "%d", t+(n-g)*cw}')
    TH=$(awk -v t="$TH" -v n="$TARGET_R" -v g="$RF" -v ch="$ch" 'BEGIN{printf "%d", t+(n-g)*ch}')
    read -r RF CF <<< "$(measure_ours "$TW" "$TH")"; echo "  nudge -> ${TW}x${TH} = ${CF}x${RF}"
    tries=$((tries+1))
done
if [ "$CF" = "$TARGET_C" ] && [ "$RF" = "$TARGET_R" ]; then
    echo "$TW $TH" > "$B/OURS_WINDOW"; echo "  ours MATCHED at ${TW}x${TH}"
else
    echo "  ours UNMATCHED (last ${CF}x${RF})"; exit 1
fi

echo "=== ghostty: solving the cell request for ${TARGET_C}x${TARGET_R} ==="
rc=$TARGET_C; rr=$TARGET_R; t=0
read -r got_r got_c <<< "$(probe_ghostty $rc $rr)"
echo "  request ${rc}x${rr} -> ${got_c}x${got_r}"
while { [ "${got_c:-0}" != "$TARGET_C" ] || [ "${got_r:-0}" != "$TARGET_R" ]; } && [ $t -lt 5 ]; do
    rc=$((rc + TARGET_C - got_c)); rr=$((rr + TARGET_R - got_r))
    read -r got_r got_c <<< "$(probe_ghostty $rc $rr)"
    echo "  request ${rc}x${rr} -> ${got_c}x${got_r}"
    t=$((t+1))
done
if [ "${got_c:-0}" = "$TARGET_C" ] && [ "${got_r:-0}" = "$TARGET_R" ]; then
    echo "$rc $rr" > "$B/REQ-gh"; echo "  ghostty MATCHED at request ${rc}x${rr}"
else
    echo "  ghostty UNMATCHED (last ${got_c:-?}x${got_r:-?})"; exit 1
fi
echo "=== both solved ==="
