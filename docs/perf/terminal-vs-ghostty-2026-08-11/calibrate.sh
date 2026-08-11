#!/usr/bin/env bash
# Solve TerminalApp's window-pixels -> grid mapping, then hit 201x47 exactly.
# Two measurements give cell size and chrome padding:
#   cols = floor((W - padX) / cellW)
# so cellW = (W1 - W2) / (cols1 - cols2), padX = W1 - cols1*cellW.
# Matching the other terminal's grid cell-for-cell is the whole point: the
# cell-filling workloads scale with cell count, so an unmatched grid silently
# rewards whichever terminal got the smaller window.
set -u
# The GNOME session user (both terminals must run inside one GNOME
# Wayland session; see README.md).
BENCH_USER=${BENCH_USER:-starling}
BENCH_UID=${BENCH_UID:-$(id -u "$BENCH_USER")}
B=/var/tmp/bench

measure() {   # measure <w> <h> -> "rows cols"
    rm -f $B/GRID
    sudo pkill -x TerminalApp 2>/dev/null; sleep 1
    setsid sudo -u "$BENCH_USER" env XDG_RUNTIME_DIR=/run/user/"$BENCH_UID" WAYLAND_DISPLAY=wayland-0 \
        GDK_BACKEND=wayland STARLING_APP_GTK=1 LD_LIBRARY_PATH=$B/gtkrun \
        STARLING_WINDOW_W="$1" STARLING_WINDOW_H="$2" \
        STARLING_DEV_SHELL=$B/shell-grid.sh \
        $B/gtkrun/TerminalApp > $B/log-grid.txt 2>&1 &
    for i in $(seq 1 30); do [ -s $B/GRID ] && break; sleep 2; done
    sudo pkill -x TerminalApp 2>/dev/null
    cat $B/GRID 2>/dev/null
}

read -r R1 C1 <<< "$(measure 1920 1080)"; echo "1920x1080 -> ${C1}x${R1}"
read -r R2 C2 <<< "$(measure 1280 720)";  echo "1280x720  -> ${C2}x${R2}"

read -r TW TH <<< "$(awk -v w1=1920 -v w2=1280 -v c1="$C1" -v c2="$C2" \
                         -v h1=1080 -v h2=720  -v r1="$R1" -v r2="$R2" 'BEGIN{
    cw=(w1-w2)/(c1-c2); px=w1-c1*cw
    ch=(h1-h2)/(r1-r2); py=h1-r1*ch
    printf "%d %d", int(201*cw+px+0.5), int(47*ch+py+0.5)
}')"
echo "solved: cell ~$(awk -v a=1920 -v b=1280 -v c="$C1" -v d="$C2" 'BEGIN{printf "%.2f", (a-b)/(c-d)}')px wide -> target ${TW}x${TH} for 201x47"

read -r RF CF <<< "$(measure "$TW" "$TH")"; echo "verify ${TW}x${TH} -> ${CF}x${RF}"

# Nudge if rounding left us a cell or two off.
tries=0
while { [ "$CF" != 201 ] || [ "$RF" != 47 ]; } && [ $tries -lt 4 ]; do
    cw=$(awk -v a=1920 -v b=1280 -v c="$C1" -v d="$C2" 'BEGIN{print (a-b)/(c-d)}')
    ch=$(awk -v a=1080 -v b=720  -v c="$R1" -v d="$R2" 'BEGIN{print (a-b)/(c-d)}')
    TW=$(awk -v t="$TW" -v cf="$CF" -v cw="$cw" 'BEGIN{printf "%d", t + (201-cf)*cw}')
    TH=$(awk -v t="$TH" -v rf="$RF" -v ch="$ch" 'BEGIN{printf "%d", t + (47-rf)*ch}')
    read -r RF CF <<< "$(measure "$TW" "$TH")"; echo "  retry ${TW}x${TH} -> ${CF}x${RF}"
    tries=$((tries+1))
done

if [ "$CF" = 201 ] && [ "$RF" = 47 ]; then
    echo "$TW $TH" > $B/OURS_WINDOW
    echo "MATCHED: ${TW}x${TH} gives 201x47"
else
    echo "UNMATCHED after $tries retries — last ${CF}x${RF}"; exit 1
fi
