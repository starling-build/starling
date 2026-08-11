#!/usr/bin/env bash
# Best-of-3 per workload (min wall), MB/s, and the ratio against ghostty
# nightly. Best-of rather than mean: this is a throughput ceiling measurement
# and the slow runs are scheduler noise, not signal.
set -u
B=/var/tmp/bench
sizes="01_light_cells 10888890 02_dense_cells 30150000 03_sgr_fg 72300000
04_sgr_truecolor 112020000 05_unicode 58650000 06_cursor_motion 3704506
07_alt_screen 37316000 08_scroll_region 43688900 09_long_lines 40025000
10_binary 30000005"

best() {  # best <label> <workload> <field:2=wall,3=cpu>
    sudo cat $B/res-$1-{1,2,3}.txt 2>/dev/null \
      | awk -v w="$2" -v f="$3" '$1==w {if (m==""||$f<m) m=$f} END{printf "%.3f", m}'
}

printf '%-18s %8s %8s %8s   %9s %9s   %s\n' \
       workload ours ghn gh130 "ours MB/s" "ghn MB/s" "ours vs ghn"
printf '%s\n' "-------------------------------------------------------------------------------"
set -- $sizes
to=0; tg=0; t1=0
while [ $# -gt 0 ]; do
    w=$1; sz=$2; shift 2
    o=$(best ours-new "$w" 2); g=$(best ghn-new "$w" 2); h=$(best gh130-new "$w" 2)
    to=$(awk -v a=$to -v b=$o 'BEGIN{print a+b}')
    tg=$(awk -v a=$tg -v b=$g 'BEGIN{print a+b}')
    t1=$(awk -v a=$t1 -v b=$h 'BEGIN{print a+b}')
    awk -v w="$w" -v o="$o" -v g="$g" -v h="$h" -v sz="$sz" 'BEGIN{
        printf "%-18s %8.3f %8.3f %8.3f   %9.1f %9.1f   %6.2fx %s\n",
               w, o, g, h, sz/o/1e6, sz/g/1e6, o/g, (o<g ? "WIN" : "")
    }'
done
printf '%s\n' "-------------------------------------------------------------------------------"
awk -v o="$to" -v g="$tg" -v h="$t1" 'BEGIN{
    printf "%-18s %8.3f %8.3f %8.3f                         %6.2fx overall\n",
           "TOTAL wall", o, g, h, o/g
}'
echo
echo "CPU seconds (best-of-3, total across workloads):"
for L in ours-new ghn-new gh130-new; do
    tot=0
    set -- $sizes
    while [ $# -gt 0 ]; do
        c=$(best "$L" "$1" 3); tot=$(awk -v a=$tot -v b=$c 'BEGIN{print a+b}'); shift 2
    done
    printf '  %-10s %6.2f s\n' "$L" "$tot"
done
echo
echo "RSS (kb, last run):"
for L in ours-new ghn-new gh130-new; do
    printf '  %-10s %s\n' "$L" "$(sudo awk '/rss_kb/{print $2}' $B/res-$L-3.txt 2>/dev/null)"
done
echo
echo "Grids: $(for L in ours-new ghn-new gh130-new; do printf '%s=%s ' "$L" "$(sudo awk '/^grid/{print $2}' $B/meta-$L.txt)"; done)"
