#!/bin/bash
# slides-drift.sh COMBINED_TSV — the DRIFT line of the hourly round (amd-8, 2026-11-22). COMBINED_TSV is a slides-gate combined.tsv
# (name, score, kind) of the current main; the reference is the FIXED set written on the gate engine at 2026-11-22 06:36Z: the first prebuild Slides base render (main 77d06e806, 674 decks; cache pptx-ref-20261122g).
# pptx-ref-20261122g). Lists decks whose combined score moved more than 2 points since, so slow drifts surface though every PR passed.
R=${DRIFT_REF:-/data/corpus-cache/test/corpus/pptx-ref-20261122g}
python3 - "$1" "$R" <<'P'
import sys,glob
def rd(f): return {l.split('\t')[0].rsplit('/',1)[-1]:float(l.split('\t')[1]) for l in open(f) if l.strip()}
n=rd(sys.argv[1]); b={}
for f in sorted(glob.glob(sys.argv[2]+'/lines-*.tsv')): b.update(rd(f))
mv=sorted(((n[k]-v,k,v,n[k]) for k,v in b.items() if k in n and abs(n[k]-v)>2),key=lambda x:x[0])
print("DRIFT: %d of %d decks moved more than 2 points since the 2026-11-22 reference (%d better, %d worse)"%(len(mv),len(b),sum(d>0 for d,*_ in mv),sum(d<0 for d,*_ in mv)))
for d,k,v,x in mv[:15]: print("DRIFT   %s %.1f -> %.1f (%+.1f)"%(k[:40],v,x,d))
P
