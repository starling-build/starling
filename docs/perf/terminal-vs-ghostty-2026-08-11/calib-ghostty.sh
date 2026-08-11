#!/usr/bin/env bash
# ghostty's --window-width/--window-height are a REQUEST, not the resulting
# grid: 201x47 came back as 200x44 (nightly) and 201x45 (1.3.0). Probe each
# build and solve for the request that lands on 201x47, so the head-to-head
# is cell-for-cell.
set -u
# The GNOME session user (both terminals must run inside one GNOME
# Wayland session; see README.md).
BENCH_USER=${BENCH_USER:-starling}
BENCH_UID=${BENCH_UID:-$(id -u "$BENCH_USER")}
B=/var/tmp/bench
cat > $B/grid-probe.sh <<'EOF'
#!/usr/bin/env bash
stty size > /var/tmp/bench/GRID 2>&1
sleep 1
EOF
chmod 755 $B/grid-probe.sh

probe() {   # probe <binary> <req_cols> <req_rows> -> "rows cols"
    rm -f $B/GRID; sudo pkill -x ghostty 2>/dev/null; sleep 2
    setsid sudo -u "$BENCH_USER" env XDG_RUNTIME_DIR=/run/user/"$BENCH_UID" WAYLAND_DISPLAY=wayland-0 \
        GDK_BACKEND=wayland "$1" --window-width="$2" --window-height="$3" \
        -e $B/grid-probe.sh > $B/log-probe.txt 2>&1 &
    for i in $(seq 1 30); do [ -s $B/GRID ] && break; sleep 2; done
    sudo pkill -x ghostty 2>/dev/null
    cat $B/GRID 2>/dev/null
}

solve() {   # solve <binary> <name>
    local bin="$1" name="$2" rc=201 rr=47 got_r got_c t=0
    read -r got_r got_c <<< "$(probe "$bin" $rc $rr)"
    echo "  $name: request ${rc}x${rr} -> ${got_c}x${got_r}"
    while { [ "$got_c" != 201 ] || [ "$got_r" != 47 ]; } && [ $t -lt 5 ]; do
        rc=$((rc + 201 - got_c)); rr=$((rr + 47 - got_r))
        read -r got_r got_c <<< "$(probe "$bin" $rc $rr)"
        echo "  $name: request ${rc}x${rr} -> ${got_c}x${got_r}"
        t=$((t+1))
    done
    if [ "$got_c" = 201 ] && [ "$got_r" = 47 ]; then
        echo "$rc $rr" > "$B/REQ-$name"; echo "  $name MATCHED at request ${rc}x${rr}"
    else
        echo "  $name UNMATCHED (last ${got_c}x${got_r})"; return 1
    fi
}

solve /var/tmp/ghostty-nightly/bin/ghostty ghn
solve /usr/bin/ghostty gh130
