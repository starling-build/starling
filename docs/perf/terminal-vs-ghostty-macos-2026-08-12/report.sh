#!/bin/zsh
# Best-of-N per workload (min wall), MB/s, and the ratio against ghostty.
# Best-of rather than mean: this is a throughput ceiling measurement and the
# slow runs are scheduler noise, not signal.
#
# Workload sizes are read from the staged corpus rather than hardcoded — this
# round regenerates the corpus at the matched grid (201x47), so the byte
# counts are not the ones baked into the Linux round's report.sh.
set -u
B=${BENCH_DIR:-/var/tmp/bench}
RUNS=${RUNS:-3}

best() {  # best <label> <workload> <field:2=wall,3=cpu>
    cat $B/res-$1-*.txt 2>/dev/null \
      | awk -v w="$2" -v f="$3" '$1==w {if (m==""||$f<m) m=$f} END{if(m=="")m=0; printf "%.3f", m}'
}

printf '%-18s %9s %9s   %9s %9s   %s\n' workload ours ghostty "ours MB/s" "gh MB/s" "ours vs gh"
printf '%s\n' "---------------------------------------------------------------------------------"
to=0; tg=0
for f in $B/corpus/[0-9]*.txt; do
    w=$(basename "$f" .txt)
    sz=$(stat -f %z "$f")
    o=$(best ours "$w" 2); g=$(best gh "$w" 2)
    to=$(awk -v a=$to -v b=$o 'BEGIN{print a+b}')
    tg=$(awk -v a=$tg -v b=$g 'BEGIN{print a+b}')
    awk -v w="$w" -v o="$o" -v g="$g" -v sz="$sz" 'BEGIN{
        r = (g>0 ? o/g : 0)
        printf "%-18s %9.3f %9.3f   %9.1f %9.1f   %6.2fx %s\n",
               w, o, g, (o>0?sz/o/1e6:0), (g>0?sz/g/1e6:0), r, (r<1 && r>0 ? "WIN" : "")
    }'
done
printf '%s\n' "---------------------------------------------------------------------------------"
awk -v o="$to" -v g="$tg" 'BEGIN{
    printf "%-18s %9.3f %9.3f                           %6.2fx overall\n", "TOTAL wall", o, g, (g>0?o/g:0)
}'
echo
echo "CPU seconds (best-of-$RUNS, total across workloads):"
for L in ours gh; do
    tot=0
    for f in $B/corpus/[0-9]*.txt; do
        c=$(best "$L" "$(basename "$f" .txt)" 3)
        tot=$(awk -v a=$tot -v b=$c 'BEGIN{print a+b}')
    done
    printf '  %-8s %6.2f s\n' "$L" "$tot"
done
echo
echo "RSS (kb, last run):"
for L in ours gh; do
    printf '  %-8s %s\n' "$L" "$(awk '/rss_kb/{print $2}' $B/res-$L-$RUNS.txt 2>/dev/null)"
done
echo
printf 'Grids: '
for L in ours gh; do printf '%s=%s ' "$L" "$(awk '/^grid/{print $2}' $B/meta-$L.txt 2>/dev/null)"; done
echo
