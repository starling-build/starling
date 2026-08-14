#!/usr/bin/env bash
# The filmed head-to-head, ~10 s per test. Args: <label> <display name>
L="$1"; NAME="$2"; B=/var/tmp/bench-film
DOOM=/var/tmp/doomfire/zig-out/bin/DOOM-fire
FRAMES=$(cat $B/FRAMES 2>/dev/null || echo 4000)
printf '\033[2J\033[H\n\n   \033[1;44;97m  %s  \033[0m\n\n   three tests, ~10 seconds each — waiting for the start signal\n' "$NAME"
while [ ! -f $B/GO ]; do stty size | tr ' ' 'x' > $B/grid-$L; sleep 0.2; done
banner(){ printf '\033[0m\033[?1049l\033[r\033[2J\033[H\033[1;33m=== %s ===\033[0m\n' "$1"; sleep 0.6; }
start=$EPOCHREALTIME

banner "TEST 1/3: cat ascii.txt ($(du -h $B/ascii_film.txt | cut -f1))"
t0=$EPOCHREALTIME; cat $B/ascii_film.txt; t1=$EPOCHREALTIME
A=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')

banner "TEST 2/3: cat unicode.txt ($(du -h $B/unicode_film.txt | cut -f1))"
t0=$EPOCHREALTIME; cat $B/unicode_film.txt; t1=$EPOCHREALTIME
U=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')

banner "TEST 3/3: DOOM-Fire, $FRAMES frames"
sleep 0.5
DOOMFIRE_FRAMES=$FRAMES "$DOOM" 2> $B/doomout-$L
FPS=$(grep -o 'fps=[0-9.]*' $B/doomout-$L | tail -1 | cut -d= -f2)
end=$EPOCHREALTIME
T=$(awk -v a="$start" -v b="$end" 'BEGIN{printf "%.1f", b-a}')

echo "ascii=$A unicode=$U fps=$FPS total=$T" > $B/times-$L
show(){ printf '\033[0m\033[?1049l\033[r\033[2J\033[H\n\n   \033[1;44;97m  %s  \033[0m\n\n' "$NAME"
  printf '   ascii cat               \033[1m%7s s\033[0m\n' "$A"
  printf '   unicode cat             \033[1m%7s s\033[0m\n' "$U"
  printf '   DOOM-Fire, %s frames  \033[1m%5s fps\033[0m\n\n' "$FRAMES" "${FPS%.*}"
  printf '   \033[1;42;30m  ALL THREE DONE in %s s  \033[0m\n' "$T"; }
show; read -s -t 1.5 -N 1000000 junk 2>/dev/null; show
touch $B/done-$L
sleep infinity
