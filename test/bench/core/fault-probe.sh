#!/usr/bin/env bash
# Runs INSIDE the terminal: cat the scroll-heavy workloads and record the
# terminal's own minor page faults and CPU, not just wall time. Page-fault work
# is kernel time the process pays for allocator churn; an idle-box wall clock
# hides it, a loaded machine does not.
set -u
LABEL="$(cat /var/tmp/bench/LABEL2 2>/dev/null || echo probe)"
DIR=/var/tmp/bench; HZ=$(getconf CLK_TCK)
pid=$$; term=""
while :; do
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null|tr -d ' '); [ -z "$ppid" ]&&break; [ "$ppid" -le 1 ]&&break
  comm=$(ps -o comm= -p "$ppid" 2>/dev/null|tr -d ' ')
  case "$comm" in bash|sh|dash|zsh|env|sudo|fault-probe.sh) ;; *) term="$ppid"; tc="$comm"; break;; esac
  pid="$ppid"
done
[ -z "$term" ] && { echo no-term >&2; exec /bin/bash; }
stat_f=/proc/$term/stat
flt(){ awk '{print $10}' "$stat_f" 2>/dev/null||echo 0; }
cpu(){ awk '{print $14+$15}' "$stat_f" 2>/dev/null||echo 0; }
OUT="$DIR/faults-$LABEL.txt"; : > "$OUT"
echo "# $LABEL term=$term/$tc grid=$(stty size|tr ' ' x)" >> "$OUT"
echo "# workload wall_s cpu_s minor_faults" >> "$OUT"
for w in 01_light_cells 07_alt_screen 08_scroll_region 09_long_lines; do
  cat "$DIR/$w.txt" > /dev/null
  printf '\033[0m\033[r\033[?1049l\033[2J\033[H'; sleep 1
  f0=$(flt); c0=$(cpu); t0=$EPOCHREALTIME
  cat "$DIR/$w.txt"
  t1=$EPOCHREALTIME; c1=$(cpu); f1=$(flt)
  printf '\033[0m\033[r\033[?1049l\033[2J\033[H'
  awk -v n="$w" -v t0="$t0" -v t1="$t1" -v a="$c0" -v b="$c1" -v f0="$f0" -v f1="$f1" -v hz="$HZ" \
    'BEGIN{printf "%s %.3f %.2f %d\n", n, t1-t0, (b-a)/hz, f1-f0}' >> "$OUT"
done
printf '\033[0m\033[2J\033[H'; echo "PROBE DONE"; exec /bin/bash
