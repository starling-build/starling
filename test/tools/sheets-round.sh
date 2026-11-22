#!/bin/bash
# sheets-round.sh [BIN] — the Sheets round (amd-8, 2026-11-22): draws every workbook with BIN (default: the newest main binary in the gate cache),
# scores it against Excel's print (test/tools/sheets-sweep.py) and publishes per-page.tsv (last column `features`, from sheets-features.py),
# per-book.tsv and a header line to $OUT (default /data/s/amd-8/sg/sheets-round). ~1 min. Corpus, prints and scores stay out of git.
[ -f "$HOME/bin/office-env.sh" ] && source "$HOME/bin/office-env.sh" >/dev/null 2>&1   # the full pair env: a render without it is silently different (it moved the mean 0.62 to 0.84)
OUT=${OUT:-/data/s/amd-8/sg/sheets-round}; HERE=$(cd "$(dirname "$0")" && pwd); PY=${PYTHON:-$HOME/venv-word/bin/python}
C=${BC:-/data/gate/cache/eng-e166c1cc01}; BIN=$1; [ -n "$BIN" ] || for s in $(git -C "$HERE" log --format=%H -40 origin/main); do [ -x "$C/$s/release/OfficeApp" ] && { BIN=$C/$s/release/OfficeApp; break; }; done   # newest main commit that has a binary; [ -x "$BIN" ] || { echo "sheets-round: no binary"; exit 1; }
sha=$(basename "$(dirname "$(dirname "$BIN")")"); mkdir -p "$OUT"; W=$OUT/work; rm -rf "$W"
OFFICE_FONT_SOURCE=bundled PDFDIFF_NO_PAIRS=1 "$PY" "$HERE/sheets-sweep.py" "$BIN" "$W" -j "${JOBS:-32}" > "$OUT/sweep.log" 2>&1 || { echo "sheets-round: sweep failed"; exit 1; }
~/venv-word/bin/python -I "$HERE/sheets-features.py" "$W/per-page.tsv" "$W/per-book.tsv"
for f in per-page per-book; do { echo "# main $sha $(date -u +%FT%TZ)"; cat "$W/$f.tsv"; } > "$OUT/$f.tsv.tmp$$" && mv "$OUT/$f.tsv.tmp$$" "$OUT/$f.tsv"; done
X2=${CORPUS_CACHE:-/data/corpus-cache}/test/corpus/xlsx2/features.tsv; [ -f "$X2" ] || X2=/dev/null   # the headline is the first set only (comparable with earlier rounds); the second set follows below
awk -F'\t' 'NR==FNR{sub(/\.xlsx$/,"",$1);s[$1]=1;next} !/^#/&&FNR>2&&!($1 in s)&&($7=="ok"||$7=="ok-empty"){n++;p+=$4;if($6!="-"){l++;m+=$6}}END{printf "sheets-round: %s: %d books, pixel mean %.2f%%, line match mean %.1f%% (%d books with text)\n","'"$sha"'",n,p/n,m/l,l}' "$X2" "$OUT/per-book.tsv" | tee "$OUT/summary.txt"
# Second set (xlsx2, 2026-11-22): mean by language, from its features.tsv (books that printed OK; .xls books are not readable yet and show as ERROR rows).
"$PY" -I - "$W/per-book.tsv" "${CORPUS_CACHE:-/data/corpus-cache}/test/corpus/xlsx2/features.tsv" "$sha" <<'P' | tee -a "$OUT/header.txt" | head -3
import sys, collections
try: lang = {l.split("\t")[0]: l.split("\t")[1] for l in open(sys.argv[2])}
except OSError: sys.exit(0)
d = collections.defaultdict(lambda: [0, 0.0, 0, 0.0])
for l in open(sys.argv[1]).read().splitlines()[1:]:
    f = l.split("\t")
    if len(f) < 7 or f[6] != "ok": continue
    k = lang.get(f[0] + ".xlsx")
    if not k: continue
    d[k][0] += 1; d[k][1] += float(f[3])
    if f[5] != "-": d[k][2] += 1; d[k][3] += float(f[5])
n = sum(v[0] for v in d.values()); m = sum(v[2] for v in d.values())
if n: print("sheets-round xlsx2 %s: %d books, line match %.1f%%; by language: %s" % (sys.argv[3][:9], n, sum(v[3] for v in d.values()) / max(m, 1), ", ".join("%s %.1f" % (k, v[3] / max(v[2], 1)) for k, v in sorted(d.items()))))
P
