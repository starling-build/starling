#!/bin/zsh
zmodload zsh/datetime
sleep 3
: > /var/tmp/bench/ONSET
t0=$EPOCHREALTIME
for b in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    repeat 20 cat /var/tmp/bench/corpus/01_light_cells.txt
    t1=$EPOCHREALTIME
    awk -v b=$b -v a=$t0 -v t=$t1 'BEGIN{printf "block%02d +%.1fs\n", b, t-a}' >> /var/tmp/bench/ONSET
done
echo done >> /var/tmp/bench/ONSET
sleep 1
