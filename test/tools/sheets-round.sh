#!/bin/bash
# sheets-round.sh [BIN] — the Sheets round (amd-8, 2026-11-22): draws every workbook with BIN (default: the newest main binary in the gate cache),
# scores it against Excel's print (test/tools/sheets-sweep.py) and publishes per-page.tsv (last column `features`, from sheets-features.py),
# per-book.tsv and a header line to $OUT (default /data/s/amd-8/sg/sheets-round). ~1 min. Corpus, prints and scores stay out of git.
[ -f "$HOME/bin/office-env.sh" ] && source "$HOME/bin/office-env.sh" >/dev/null 2>&1   # the full pair env: a render without it is silently different (it moved the mean 0.62 to 0.84)
OUT=${OUT:-/data/s/amd-8/sg/sheets-round}; HERE=$(cd "$(dirname "$0")" && pwd); PY=${PYTHON:-$HOME/venv-word/bin/python}
C=${BC:-/data/gate/cache/eng-e166c1cc01}; BIN=$1; [ -n "$BIN" ] || for s in $(git -C "$HERE" log --format=%H -40 origin/main); do [ -x "$C/$s/release/OfficeApp" ] && { BIN=$C/$s/release/OfficeApp; break; }; done   # newest main commit that has a binary; [ -x "$BIN" ] || { echo "sheets-round: no binary"; exit 1; }
sha=$(basename "$(dirname "$(dirname "$BIN")")"); mkdir -p "$OUT"; W=$OUT/work; rm -rf "$W"
OFFICE_FONT_SOURCE=bundled PDFDIFF_NO_PAIRS=1 "$PY" "$HERE/sheets-sweep.py" "$BIN" "$W" -j "${JOBS:-32}" > "$OUT/sweep.log" 2>&1 || { echo "sheets-round: sweep failed"; exit 1; }
python3 -I "$HERE/sheets-features.py" "$W/per-page.tsv" "$W/per-book.tsv"
for f in per-page per-book; do { echo "# main $sha $(date -u +%FT%TZ)"; cat "$W/$f.tsv"; } > "$OUT/$f.tsv.tmp$$" && mv "$OUT/$f.tsv.tmp$$" "$OUT/$f.tsv"; done
awk -F'\t' '!/^#/&&NR>2&&($7=="ok"||$7=="ok-empty"){n++;p+=$4;if($6!="-"){l++;m+=$6}}END{printf "sheets-round: %s: %d books, pixel mean %.2f%%, line match mean %.1f%% (%d books with text)\n","'"$sha"'",n,p/n,m/l,l}' "$OUT/per-book.tsv" | tee "$OUT/summary.txt"
