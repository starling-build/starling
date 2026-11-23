#!/bin/bash
# slides-round.sh — publish the newest main Slides round (per-page.tsv + combined.tsv, sha and time in the first line) to
# $OUT (default /data/s/amd-8/sg/round). The prebuild writes per-page.tsv into the base cache; this copies the newest. (amd-8, 2026-11-22)
# Column 7 `features` (from slides-features.py): chart chartex table smartart picture emf vertical rtl equation 3d, "-" none, "?" deck not found.
C=${BC:-/data/gate/cache/eng-e166c1cc01}; OUT=${OUT:-/data/s/amd-8/sg/round}
f=$(ls -t "$C"/*/slides/per-page.tsv 2>/dev/null | head -1); [ -n "$f" ] || { echo "slides-round: no per-page.tsv in $C yet"; exit 1; }
d=$(dirname "$f"); sha=$(basename "$(dirname "$d")")
cp "$f" "$OUT/per-page.tsv.tmp$$" && python3 "$(dirname "$0")/slides-features.py" "$OUT/per-page.tsv.tmp$$" && mv "$OUT/per-page.tsv.tmp$$" "$OUT/per-page.tsv"
{ echo "# main $sha $(date -u -r "$d/combined.tsv" +%FT%TZ)"; cat "$d/combined.tsv"; } > "$OUT/combined.tsv.tmp$$" && mv "$OUT/combined.tsv.tmp$$" "$OUT/combined.tsv"
echo "slides-round: $sha published to $OUT"
# CJK set r1 (2026-11-22): deck mean by language (zh-, ja-, ko- stems of pptx-cjk-r1), line match per deck from per-page.tsv.
# CJK set r3 (2026-11-23): the same line, for the six folders of pptx-cjk-r3 (decks that have a PowerPoint print).
for set in r1 r3; do
python3 - "$OUT/per-page.tsv" "${CORPUS_CACHE:-/data/corpus-cache}/test/corpus/pptx-cjk-$set" "$sha" "$set" <<'P'
import sys, os, collections, glob
R = sys.argv[2]
st = set()
for f in glob.glob(R + "/decks/*.pptx") + glob.glob(R + "/*/*.pptx"):
    if os.path.exists(os.path.join(os.path.dirname(f), "powerpoint-win" if "/decks/" not in f else "../powerpoint-win", os.path.basename(f)[:-5] + "-orig.pdf")): st.add(os.path.basename(f)[:-5])
if not st: sys.exit(0)
t = collections.defaultdict(lambda: [0, 0])
for l in open(sys.argv[1]):
    f = l.rstrip("\n").split("\t")
    if len(f) >= 6 and f[0] in st and f[1].isdigit():
        t[f[0]][0] += int(f[2]); t[f[0]][1] += int(f[3])
d = collections.defaultdict(list)
for k, (a, b) in t.items(): d[k[:2]].append(100.0 * a / b if b else 100.0)
if d: print("slides-round cjk-%s %s: %s" % (sys.argv[4], sys.argv[3][:9], ", ".join("%s %d decks %.1f" % (k, len(v), sum(v) / len(v)) for k, v in sorted(d.items()))))
P
done
