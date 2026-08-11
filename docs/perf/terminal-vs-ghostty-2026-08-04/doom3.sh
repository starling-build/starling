#!/usr/bin/env bash
# Three variants of the same program: utf8+SGR (upstream), ascii+SGR, utf8 no-SGR.
set -u
LABEL="${1:-t}"; REPS="${2:-3}"; FRAMES="${3:-600}"; DIR=/var/tmp/bench; HZ=$(getconf CLK_TCK)
pid=$$; term=""
while :; do
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null|tr -d ' '); [ -z "$ppid" ]&&break; [ "$ppid" -le 1 ]&&break
  comm=$(ps -o comm= -p "$ppid" 2>/dev/null|tr -d ' ')
  case "$comm" in bash|sh|dash|zsh|env|sudo|doom3.sh) ;; *) term="$ppid"; tc="$comm"; break;; esac
  pid="$ppid"
done
[ -z "$term" ] && { echo no-term >&2; exec /bin/bash; }
cpu(){ awk '{print $14+$15}' "/proc/$term/stat" 2>/dev/null||echo 0; }
OUT="$DIR/doom3-$LABEL.txt"; : > "$OUT"
echo "# $LABEL term=$term/$tc grid=$(stty size|tr ' ' x) frames=$FRAMES" >> "$OUT"
for v in utf8sgr asciisgr nosgr; do
  case $v in
    utf8sgr)  B=/var/tmp/doomfire/zig-out/bin/DOOM-fire ;;
    asciisgr) B=/var/tmp/doomfire-ascii/zig-out/bin/DOOM-fire ;;
    nosgr)    B=/var/tmp/doomfire-nosgr/zig-out/bin/DOOM-fire ;;
  esac
  for r in $(seq 1 "$REPS"); do
    printf '\033[0m\033[r\033[?1049l\033[2J\033[H'; sleep 1
    c0=$(cpu); echo -n "$v " >> "$OUT"
    DOOMFIRE_FRAMES="$FRAMES" "$B" 2>> "$OUT"
    c1=$(cpu); printf '\033[0m\033[r\033[?1049l\033[2J\033[H'
    awk -v a="$c0" -v b="$c1" -v hz="$HZ" 'BEGIN{printf "  cpu_s %.2f\n",(b-a)/hz}' >> "$OUT"
  done
done
printf '\033[0m\033[2J\033[H'; echo "DOOM3 DONE"; exec /bin/bash
