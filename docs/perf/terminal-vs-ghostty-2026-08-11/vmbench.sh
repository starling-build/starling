#!/usr/bin/env bash
# GUEST-side: calibrate all three terminals to 201x47 inside the VM's GNOME
# session (virgl), then run the 10-workload suite and DOOM-Fire for each.
set -u
B=/var/tmp/bench
G=$B/gtkrun
ENVB=(sudo -u tester env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 GDK_BACKEND=wayland)

kill_terms() { sudo pkill -x TerminalApp 2>/dev/null; sudo pkill -x ghostty 2>/dev/null; sleep 2; }

measure_ours() {  # <w> <h> -> "rows cols"
    rm -f $B/GRID; kill_terms
    setsid "${ENVB[@]}" STARLING_APP_GTK=1 LD_LIBRARY_PATH=$G \
        STARLING_WINDOW_W="$1" STARLING_WINDOW_H="$2" STARLING_DEV_SHELL=$B/grid-probe.sh \
        $G/TerminalApp > /dev/null 2>&1 &
    for i in $(seq 1 30); do [ -s $B/GRID ] && break; sleep 2; done
    kill_terms; cat $B/GRID 2>/dev/null
}
measure_gh() {  # <bin> <cols> <rows> -> "rows cols"
    rm -f $B/GRID; kill_terms
    setsid "${ENVB[@]}" "$1" --font-size=10 --window-width="$2" --window-height="$3" \
        -e $B/grid-probe.sh > /dev/null 2>&1 &
    for i in $(seq 1 30); do [ -s $B/GRID ] && break; sleep 2; done
    kill_terms; cat $B/GRID 2>/dev/null
}

echo "=== calibrate ours ==="
read -r R1 C1 <<< "$(measure_ours 1600 900)";  echo "1600x900 -> ${C1}x${R1}"
read -r R2 C2 <<< "$(measure_ours 1200 700)";  echo "1200x700 -> ${C2}x${R2}"
read -r TW TH <<< "$(awk -v w1=1600 -v w2=1200 -v c1="$C1" -v c2="$C2" \
                         -v h1=900 -v h2=700 -v r1="$R1" -v r2="$R2" 'BEGIN{
    cw=(w1-w2)/(c1-c2); px=w1-c1*cw; ch=(h1-h2)/(r1-r2); py=h1-r1*ch
    printf "%d %d", int(201*cw+px+0.5), int(47*ch+py+0.5)}')"
read -r RF CF <<< "$(measure_ours "$TW" "$TH")"; echo "try ${TW}x${TH} -> ${CF}x${RF}"
t=0
while { [ "$CF" != 201 ] || [ "$RF" != 47 ]; } && [ $t -lt 5 ]; do
    cw=$(awk -v a=1600 -v b=1200 -v c="$C1" -v d="$C2" 'BEGIN{print (a-b)/(c-d)}')
    ch=$(awk -v a=900 -v b=700 -v c="$R1" -v d="$R2" 'BEGIN{print (a-b)/(c-d)}')
    TW=$(awk -v t="$TW" -v cf="$CF" -v cw="$cw" 'BEGIN{printf "%d", t+(201-cf)*cw}')
    TH=$(awk -v t="$TH" -v rf="$RF" -v ch="$ch" 'BEGIN{printf "%d", t+(47-rf)*ch}')
    read -r RF CF <<< "$(measure_ours "$TW" "$TH")"; echo "retry ${TW}x${TH} -> ${CF}x${RF}"
    t=$((t+1))
done
[ "$CF" = 201 ] && [ "$RF" = 47 ] || { echo "OURS UNCALIBRATED (${CF}x${RF})"; exit 1; }
echo "$TW $TH" > $B/OURS_WINDOW; echo "ours: ${TW}x${TH}"

cal_gh() {  # <bin> <name>
    local rc=201 rr=47 gr gc t=0
    read -r gr gc <<< "$(measure_gh "$1" $rc $rr)"
    echo "$2 request ${rc}x${rr} -> ${gc}x${gr}"
    while { [ "$gc" != 201 ] || [ "$gr" != 47 ]; } && [ $t -lt 5 ]; do
        rc=$((rc + 201 - gc)); rr=$((rr + 47 - gr))
        read -r gr gc <<< "$(measure_gh "$1" $rc $rr)"
        echo "$2 request ${rc}x${rr} -> ${gc}x${gr}"
        t=$((t+1))
    done
    [ "$gc" = 201 ] && [ "$gr" = 47 ] || { echo "$2 UNCALIBRATED"; return 1; }
    echo "$rc $rr" > "$B/REQ-$2"
}
cal_gh /var/tmp/ghostty-nightly/bin/ghostty ghn || exit 1
cal_gh /usr/bin/ghostty gh130 || exit 1

run_suite() {  # <label> <ours|gh> <bin>
    kill_terms; sudo rm -f $B/res-$1-*.txt $B/meta-$1.txt
    echo "$1" > $B/LABEL
    echo "=== suite: $1 ==="
    if [ "$2" = ours ]; then
        read -r WW WH < $B/OURS_WINDOW
        setsid "${ENVB[@]}" STARLING_APP_GTK=1 LD_LIBRARY_PATH=$G \
            STARLING_WINDOW_W="$WW" STARLING_WINDOW_H="$WH" STARLING_DEV_SHELL=$B/shell-bench.sh \
            $G/TerminalApp > $B/log-$1.txt 2>&1 &
    else
        read -r RC RR < "$B/REQ-${1%%-*}"
        setsid "${ENVB[@]}" "$3" --font-size=10 --window-width="$RC" --window-height="$RR" \
            -e $B/bench-in-terminal.sh "$1" 3 > $B/log-$1.txt 2>&1 &
    fi
    for i in $(seq 1 240); do
        [ -f "$B/res-$1-3.txt" ] && grep -q rss_kb "$B/res-$1-3.txt" 2>/dev/null && break
        sleep 5
    done
    kill_terms; grep '^grid' $B/meta-$1.txt 2>/dev/null || echo "  NO RESULT"
}
run_doom() {  # <label> <ours|gh> <bin>
    kill_terms; sudo rm -f $B/doom-$1.txt
    echo "$1" > $B/LABEL
    echo "=== doom: $1 ==="
    if [ "$2" = ours ]; then
        read -r WW WH < $B/OURS_WINDOW
        setsid "${ENVB[@]}" STARLING_APP_GTK=1 LD_LIBRARY_PATH=$G \
            STARLING_WINDOW_W="$WW" STARLING_WINDOW_H="$WH" STARLING_DEV_SHELL=$B/shell-doom.sh \
            $G/TerminalApp > $B/log-$1.txt 2>&1 &
    else
        read -r RC RR < "$B/REQ-${1%%-*}"
        setsid "${ENVB[@]}" "$3" --font-size=10 --window-width="$RC" --window-height="$RR" \
            -e $B/doomfire.sh "$1" 3 600 > $B/log-$1.txt 2>&1 &
    fi
    for i in $(seq 1 120); do
        c=$(grep -c cpu_s "$B/doom-$1.txt" 2>/dev/null | head -1); c=${c:-0}
        [ "$c" -ge 3 ] && break; sleep 5
    done
    kill_terms; grep BENCHFPS $B/doom-$1.txt 2>/dev/null | head -1 || echo "  NO RESULT"
}

run_suite ours-vm  ours  -
run_suite ghn-vm   gh    /var/tmp/ghostty-nightly/bin/ghostty
run_suite gh130-vm gh    /usr/bin/ghostty
run_doom  ours-vm-doom  ours -
run_doom  ghn-vm-doom   gh   /var/tmp/ghostty-nightly/bin/ghostty
run_doom  gh130-vm-doom gh   /usr/bin/ghostty
echo "VM BENCH DONE"
