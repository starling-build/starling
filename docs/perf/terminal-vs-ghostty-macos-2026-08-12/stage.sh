#!/bin/zsh
# Stage the runner and its corpus outside the repo.
#
# run-bench.zsh globs its workloads out of its OWN directory, and the corpus is
# ~420 MB, so the scripts are copied next to a generated corpus under
# /var/tmp rather than the corpus being generated into git.
#
# The corpus is regenerated at the MATCHED GRID (201x47 by default), which is
# what the Linux fullscreen protocol does: the cell-filling workloads have to
# fill every column of the grid actually under test.
set -u
B=${BENCH_DIR:-/var/tmp/bench}
HERE="${0:A:h}"
REPO=${REPO:-/Users/dishengsu/dev/starling/starling}
COLS=${TARGET_C:-201}
ROWS=${TARGET_R:-47}
SCALE=${SCALE:-1}

mkdir -p "$B/corpus"
cp "$HERE/run-bench.zsh" "$HERE/bench-in-terminal.sh" "$B/corpus/"
chmod 755 "$B/corpus"/*.zsh "$B/corpus"/*.sh

if [ -f "$B/corpus/10_binary.txt" ] && [ "${FORCE:-0}" = 0 ]; then
    echo "corpus already staged in $B/corpus (FORCE=1 to regenerate)"
else
    echo "generating corpus at ${COLS}x${ROWS} (scale $SCALE) — a few minutes, ~420 MB"
    python3 "$REPO/test/bench/gen-bench.py" "$B/corpus" "$COLS" "$ROWS" "$SCALE"
fi
echo "staged: $B/corpus"
du -sh "$B/corpus"
