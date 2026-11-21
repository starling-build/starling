#!/bin/bash
# slides-gate.sh BIN [JOBS] — the Slides step of the render gate (amd-perf, 2026-11-21).
# Draws every deck of test/corpus/pptx (cache copy) with BIN (`--deck-pdf`), scores each against PowerPoint's print with
# test/pptx-app-render.sh and compares the deck MEAN (% of pixels differing) with test/corpus/pptx/baseline-win.tsv.
# A deck whose mean is more than TOL (default 0.05 pt) worse than the baseline, or that no longer renders, fails the step
# (a stem listed in $LQ/approved.txt is waived). ~70 s for 561 decks at 32 jobs. Exit 0 clean, 1 blocked, 2 not runnable.
BIN=$(readlink -f "${1:?usage: slides-gate.sh BIN [JOBS]}"); JOBS=${2:-32}; TOL=${TOL:-0.05}
ROOT=$(cd "$(dirname "$0")/../.." && pwd); CC=${CORPUS_CACHE:-/data/corpus-cache}/test/corpus/pptx
DECKS=$ROOT/test/corpus/pptx/decks; [ -n "$(ls "$DECKS" 2>/dev/null | head -1)" ] || DECKS=$CC/decks
PPT=$CC/powerpoint-win; BASE=$ROOT/test/corpus/pptx/baseline-win.tsv
[ -d "$DECKS" ] && [ -d "$PPT" ] && [ -s "$BASE" ] || { echo "slides-gate: no deck corpus or baseline here; skipped"; exit 2; }
W=${SLIDES_SCRATCH:-${GATE_SCRATCH:-$HOME/scratch/gate}/slides}; rm -rf "$W"; mkdir -p "$W"
T=$(date +%s)
PDFDIFF_NO_PAIRS=1 OFFICE_APP=$BIN "$ROOT/test/pptx-app-render.sh" -j "$JOBS" "$DECKS" "$PPT" "$W" > "$W/run.log" 2>&1
[ -s "$W/render.tsv" ] || { echo "slides-gate: no scores produced"; tail -3 "$W/run.log" | cut -c1-200; exit 1; }
python3 - "$BASE" "$W/render.tsv" "$TOL" "${LQ:-/data/landq}/approved.txt" <<'P'
import re,sys
base,new,tol,appr=sys.argv[1],sys.argv[2],float(sys.argv[3]),sys.argv[4]
def rd(f):
    d={}
    for l in open(f):
        p=l.rstrip('\n').split('\t'); m=re.search(r'mean=([\d.]+)%',l)
        d[p[0]]=float(m.group(1)) if m else None
    return d
b,n=rd(base),rd(new)
try: ok=set(open(appr).read().split())
except OSError: ok=set()
bad=[];gone=[]
for k,v in b.items():
    if v is None: continue
    s=k[:-5]
    if n.get(k) is None: gone.append(k) if s not in ok else None
    elif n[k]>v+tol and s not in ok: bad.append((n[k]-v,k,v,n[k]))
bad.sort(reverse=True)
print("slides-gate: %d decks scored, %d worse than baseline by over %.2f pt, %d no longer render"%(sum(1 for v in n.values() if v is not None),len(bad),tol,len(gone)))
for d,k,v,x in bad[:15]: print("  WORSE %s %.2f -> %.2f"%(k[:-5],v,x))
for k in gone[:10]: print("  NO-RENDER",k[:-5])
sys.exit(1 if bad or gone else 0)
P
rc=$?; echo "slides-gate: $(( $(date +%s)-T )) s"; exit $rc
