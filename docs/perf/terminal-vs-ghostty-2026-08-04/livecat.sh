#!/usr/bin/env bash
# Cat a captured stream through the LIVE terminal and time it, so the result
# can be compared against the offline core on the same bytes and grid.
set -u
LABEL="${1:-t}"; REPS="${2:-3}"; F="${3:-/var/tmp/bench/doomstream.bin}"
DIR=/var/tmp/bench; HZ=$(getconf CLK_TCK)
pid=$$; term=""
while :; do
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null|tr -d ' '); [ -z "$ppid" ]&&break; [ "$ppid" -le 1 ]&&break
  comm=$(ps -o comm= -p "$ppid" 2>/dev/null|tr -d ' ')
  case "$comm" in bash|sh|dash|zsh|env|sudo|livecat.sh) ;; *) term="$ppid"; tc="$comm"; break;; esac
  pid="$ppid"
done
[ -z "$term" ] && { echo no-term >&2; exec /bin/bash; }
cpu(){ awk '{print $14+$15}' "/proc/$term/stat" 2>/dev/null||echo 0; }
OUT="$DIR/livecat-$LABEL.txt"; : > "$OUT"
echo "# $LABEL term=$term/$tc grid=$(stty size|tr ' ' x)" >> "$OUT"
cat "$F" > /dev/null
for r in $(seq 1 "$REPS"); do
  printf '\033[0m\033[r\033[?1049l\033[2J\033[H'; sleep 1
  c0=$(cpu); t0=$EPOCHREALTIME
  cat "$F"
  t1=$EPOCHREALTIME; c1=$(cpu)
  printf '\033[0m\033[r\033[?1049l\033[2J\033[H'
  awk -v t0="$t0" -v t1="$t1" -v a="$c0" -v b="$c1" -v hz="$HZ" -v sz=$(stat -c%s "$F") \
    'BEGIN{ w=t1-t0; printf "wall %.3f  cpu %.2f  %.1f MB/s\n", w, (b-a)/hz, sz/1e6/w }' >> "$OUT"
done
printf '\033[0m\033[2J\033[H'; echo "LIVECAT DONE"; exec /bin/bash
