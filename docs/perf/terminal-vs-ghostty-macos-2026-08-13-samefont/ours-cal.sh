#!/bin/zsh
# Ours-only half of calibrate.sh: measure cell metrics with the atlas default,
# solve the window for 201x47, write $B/OURS_WINDOW. Also captures which
# engine dylib dyld actually resolves (release vs the leftover debug rpath).
set -u
B=${BENCH_DIR:-/var/tmp/bench}
OURS=/Users/dishengsu/dev/starling/starling/apps/TerminalApp/.build/release/TerminalApp
TARGET_C=201; TARGET_R=47

mkdir -p "$B"
cat > "$B/grid-probe.sh" <<EOF
#!/bin/zsh
sleep 3
stty size > $B/GRID 2>&1
sleep 1
EOF
chmod 755 "$B/grid-probe.sh"

measure_ours() {   # <w> <h> [dyld] -> "rows cols"
    rm -f "$B/GRID"; pkill -x TerminalApp 2>/dev/null; sleep 1
    local dy=""
    [ "${3:-}" = dyld ] && dy=1
    STARLING_TERMINAL_SINGLE=1 STARLING_WINDOW_W="$1" STARLING_WINDOW_H="$2" \
        STARLING_DEV_SHELL="$B/grid-probe.sh" \
        DYLD_PRINT_LIBRARIES=${dy:+1} \
        "$OURS" > "$B/log-grid.txt" 2>&1 &
    for i in $(seq 1 30); do [ -s "$B/GRID" ] && break; sleep 1; done
    pkill -x TerminalApp 2>/dev/null
    cat "$B/GRID" 2>/dev/null
}

echo "=== engine resolution check ==="
read -r R0 C0 <<< "$(measure_ours 1600 900 dyld)"
grep -E "FlutterMacOS|swift_bridge" "$B/log-grid.txt" | grep dyld | head -4
grep -oE "host_(release|debug)_arm64" "$B/log-grid.txt" | sort | uniq -c

echo "=== solving window for ${TARGET_C}x${TARGET_R} ==="
echo "  1600x900 -> ${C0}x${R0}"
read -r R2 C2 <<< "$(measure_ours 1200 700)"; echo "  1200x700 -> ${C2}x${R2}"
if [ -z "${C0:-}" ] || [ -z "${C2:-}" ] || [ "$C0" = "$C2" ]; then
    echo "probe failed"; exit 1
fi
read -r TW TH <<< "$(awk -v w1=1600 -v w2=1200 -v c1="$C0" -v c2="$C2" \
                         -v h1=900 -v h2=700 -v r1="$R0" -v r2="$R2" \
                         -v tc="$TARGET_C" -v tr="$TARGET_R" 'BEGIN{
    cw=(w1-w2)/(c1-c2); px=w1-c1*cw
    ch=(h1-h2)/(r1-r2); py=h1-r1*ch
    printf "%d %d cellW=%.4f cellH=%.4f padX=%.2f padY=%.2f", \
        int(tc*cw+px+0.5), int(tr*ch+py+0.5), cw, ch, px, py
}')" REST
echo "  cell metrics: $REST"
echo "  solved target window ${TW}x${TH}"

read -r RF CF <<< "$(measure_ours "$TW" "$TH")"; echo "  verify ${TW}x${TH} -> ${CF}x${RF}"
tries=0
cw=$(awk -v a=1600 -v b=1200 -v c="$C0" -v d="$C2" 'BEGIN{print (a-b)/(c-d)}')
ch=$(awk -v a=900 -v b=700 -v c="$R0" -v d="$R2" 'BEGIN{print (a-b)/(c-d)}')
while { [ "$CF" != "$TARGET_C" ] || [ "$RF" != "$TARGET_R" ]; } && [ $tries -lt 5 ]; do
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
