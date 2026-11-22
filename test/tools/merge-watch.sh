#!/bin/bash
# merge-watch.sh SHA — after a prebuild of main (amd-8, 2026-11-22). Compares SHA's cached Slides combined.tsv with the nearest earlier main
# commit that has one, and appends every deck that dropped more than 1 point (and the PR(s) merged between the two) to $LQ/to-coordinator.log.
# Reuses the prebuild's output: no render. Needs GH_TOKEN for the PR numbers (falls back to the commit subjects).
SHA=$(git rev-parse "$1") || exit 0; LQ=${LQ:-/data/landq}; C=${BC:-/data/gate/cache/eng-e166c1cc01}; LOG=$LQ/to-coordinator.log
N=$C/$SHA/slides/combined.tsv; [ -s "$N" ] || exit 0
grep -qs "MERGE-WATCH $SHA" "$LOG" && exit 0
PREV=; for p in $(git rev-list --first-parent -n 60 "$SHA^" 2>/dev/null); do [ -s "$C/$p/slides/combined.tsv" ] && { PREV=$p; break; }; done
[ -n "$PREV" ] || exit 0
D=$(python3 - "$C/$PREV/slides/combined.tsv" "$N" <<'P'
import sys
def rd(f): return {l.split('\t')[0].rsplit('/',1)[-1]:float(l.split('\t')[1]) for l in open(f) if l.strip()}
b=rd(sys.argv[1]); n=rd(sys.argv[2])
for d,k in sorted((n[k]-v,k) for k,v in b.items() if k in n and n[k]-v<-1): print("  %s %.1f -> %.1f (%+.1f)"%(k[:44],b[k],n[k],d))
P
)
[ -n "$D" ] || exit 0
PRS=
for c in $(git rev-list "$PREV..$SHA"); do
  n=$(curl -s -m 20 -H "Authorization: Bearer ${GH_TOKEN:-}" "https://api.github.com/repos/${GITHUB_REPOSITORY:-starling-build/starling}/commits/$c/pulls" 2>/dev/null | python3 -c 'import sys,json
try: print(" ".join("#%d"%x["number"] for x in json.load(sys.stdin)))
except Exception: pass' 2>/dev/null)
  PRS="$PRS $(git log -1 --format='%h' "$c")${n:+($n)}"
done
{ echo "MERGE-WATCH $SHA $(date -u +%FT%TZ): Slides decks that dropped more than 1 point against $PREV; $(git rev-list --count "$PREV..$SHA") commits in between (hash, PR):$PRS"; echo "$D"; } >> "$LOG" 2>/dev/null
exit 0
