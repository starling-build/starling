#!/bin/zsh
# Long-run terminal benchmark runner — run-bench.zsh with each workload
# repeated so a leg runs minutes, not fractions of a second (steady state,
# warm-up amortized; see the DOOM 600-vs-6000-frame finding). Repeat counts
# target >=120 s on the slower side (ghostty) from the 08-13-samefont
# medians. Output format gains a 4th column: reps.
set -u
zmodload zsh/datetime

PID="$1"; OUT="$2"
DIR="${0:A:h}"

typeset -A REPS
REPS=(
  01_light_cells   800
  02_dense_cells   830
  03_sgr_fg        190
  04_sgr_truecolor 170
  05_unicode       400
  06_cursor_motion 3200
  07_alt_screen    670
  08_scroll_region 550
  09_long_lines    660
  10_binary        220
)

cpu() {
    local t
    t=$(ps -o time= -p "$PID" 2>/dev/null | tr -d ' ')
    [[ -z "$t" ]] && { print 0; return }
    print -r -- "$t" | awk -F: '{
        if (NF == 3)      { print $1*3600 + $2*60 + $3 }
        else if (NF == 2) { print $1*60 + $2 }
        else              { print $1 }
    }'
}

reset_term() { printf '\033[0m\033[r\033[?1049l\033[2J\033[H' }

: > "$OUT"
print "# test wall_s cpu_s reps" >> "$OUT"

for f in "$DIR"/[0-9]*.txt; do
    name=$(basename "$f" .txt)
    n=${REPS[$name]:-1}
    cat "$f" > /dev/null            # warm page cache — not timed
    reset_term
    sleep 0.7

    c0=$(cpu); t0=$EPOCHREALTIME
    repeat $n cat "$f"
    t1=$EPOCHREALTIME; c1=$(cpu)

    reset_term
    awk -v n="$name" -v t0="$t0" -v t1="$t1" -v c0="$c0" -v c1="$c1" -v r="$n" \
        'BEGIN{ printf "%s %.3f %.2f %d\n", n, t1-t0, c1-c0, r }' >> "$OUT"
done

print "rss_kb $(ps -o rss= -p "$PID" | tr -d ' ')" >> "$OUT"
reset_term
print "BENCH-DONE"
