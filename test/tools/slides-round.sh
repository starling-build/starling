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
