#!/bin/bash
# slides-gate.sh BIN [JOBS] — the Slides step of the render gate (amd-perf, 2026-11-21).
# Draws every deck of test/corpus/pptx (cache copy) with BIN (`--deck-pdf`), scores each against PowerPoint's print with
# test/pptx-app-render.sh and compares the deck MEAN (% of pixels differing) with test/corpus/pptx/baseline-win.tsv.
# A deck whose mean is more than TOL (default 0.05 pt) worse than the baseline, or that no longer renders, fails the step
# (a stem listed in $LQ/approved.txt is waived). ~70 s for 561 decks at 32 jobs. Exit 0 clean, 1 blocked, 2 not runnable.
# BASE MODE (2026-11-22, amd-8): with BASE_BIN set (render-gate passes the merge-base binary) the PR is compared with a render of the BASE
# drawn on the same runner and engine (cached per main sha + engine in $BASE_CACHE: render.tsv + combined.tsv), so only the PR's own change
# is judged; main's drift no longer blocks later PRs. The fixed baseline files are then only the drift report (hourly round).
BIN=$(readlink -f "${1:?usage: slides-gate.sh BIN [JOBS]}"); JOBS=${2:-32}; TOL=${TOL:-0.05}
ROOT=$(cd "$(dirname "$0")/../.." && pwd); CC=${CORPUS_CACHE:-/data/corpus-cache}/test/corpus/pptx
DECKS=$ROOT/test/corpus/pptx/decks; [ -n "$(ls "$DECKS" 2>/dev/null | head -1)" ] || DECKS=$CC/decks
PPT=$CC/powerpoint-win; BASE=$ROOT/test/corpus/pptx/baseline-win.tsv
[ -d "$DECKS" ] && [ -d "$PPT" ] && { [ -s "$BASE" ] || [ -n "${BASE_BIN:-}" ]; } || { echo "slides-gate: no deck corpus or baseline here; skipped"; exit 2; }
W=${SLIDES_SCRATCH:-${GATE_SCRATCH:-$HOME/scratch/gate}/slides}; rm -rf "$W"; mkdir -p "$W"
T=$(date +%s)
# The pilot decks (real decks of 20-60 slides, ja and ko; amd-8's baseline rows name them) join the SAME sweep so they share the job
# pool; every deck is launched largest first so the longest one never starts last. Without a pilot baseline the sweep is the corpus alone.
PILOT=${PILOT_DIR:-${CORPUS_CACHE:-/data/corpus-cache}/test/corpus/pptx-pilot}; PB=$PILOT/baseline-pilot-win.tsv; STG=${PILOT_STAGING:-${CORPUS_CACHE:-/data/corpus-cache}/staging/pptx-new/pilot}
mkdir -p "$W/in" "$W/ppt"
for f in "$DECKS"/*.pptx; do ln -s "$f" "$W/in/"; done; for f in "$PPT"/*-orig.pdf; do ln -s "$f" "$W/ppt/"; done
BASEALL=$BASE; MISS=""
# A pilot corpus that is present but whose baseline is not, or a baseline row whose deck or print is not, FAILS the step (never a silent skip).
if [ ! -s "$PB" ] && [ -n "$(ls "$PILOT/decks" 2>/dev/null | head -1)" ]; then MISS="$MISS $PB"; fi
if [ -s "$PB" ]; then
  for rel in $(cut -f1 "$PB"); do
    n=${rel##*/}; found=""
    for d in "$PILOT/decks/$rel" "$PILOT/decks/$n" "$STG/$rel"; do [ -f "$d" ] && { ln -sf "$d" "$W/in/$n"; found=1; break; }; done
    [ -n "$found" ] || MISS="$MISS deck:$rel"
    found=""
    for d in "$PILOT/powerpoint-win" "$PILOT/powerpoint-win/${rel%/*}" "$STG/${rel%/*}/powerpoint-win"; do [ -f "$d/${n%.pptx}-orig.pdf" ] && { ln -sf "$d/${n%.pptx}-orig.pdf" "$W/ppt/"; found=1; break; }; done
    [ -n "$found" ] || MISS="$MISS print:$rel"
  done
  { cat "$BASE"; awk -F'\t' 'BEGIN{OFS="\t"} {sub(/.*\//,"",$1); print}' "$PB"; } > "$W/base.tsv"; BASEALL=$W/base.tsv
fi
# The full-corpus subset (amd-8, 2026-11-22): gate-subset.txt in pptx-full (cache) lists ~70 decks, ~1,490 slides over ja ko es pt en rtl, drawn
# with the same sweep and scored against baseline-full-win.tsv / baseline-lines-full-win.tsv (rows named lang/stem; the lang folder is dropped
# as for the pilot). A listed deck, print or baseline row that is missing FAILS the step. FULL_SUBSET=0 turns it off.
FULL=${FULL_DIR:-$CC-full}; FX=""
if [ "${FULL_SUBSET:-1}" != 0 ] && [ -s "$FULL/gate-subset.txt" ]; then
  for rel in $(cat "$FULL/gate-subset.txt"); do
    n=${rel##*/}; s=${n%.pptx}
    [ -f "$FULL/decks/$rel" ] && ln -sf "$FULL/decks/$rel" "$W/in/$n" || MISS="$MISS deck:$rel"
    [ -f "$FULL/powerpoint-win/$s-orig.pdf" ] && ln -sf "$FULL/powerpoint-win/$s-orig.pdf" "$W/ppt/" || MISS="$MISS print:$rel"
    grep -q "^$rel	" "$FULL/baseline-full-win.tsv" && grep -q "^${rel%.pptx}	" "$FULL/baseline-lines-full-win.tsv" || MISS="$MISS baseline:$rel"
  done
  [ -z "$MISS" ] && { FX=1; { cat "$BASEALL"; grep -F -f "$FULL/gate-subset.txt" "$FULL/baseline-full-win.tsv" | awk -F'\t' 'BEGIN{OFS="\t"} {sub(/.*\//,"",$1); print}'; } > "$W/base-all.tsv"; BASEALL=$W/base-all.tsv; }
fi
[ -s "$CC/baseline-lines-win.tsv" ] || MISS="$MISS $CC/baseline-lines-win.tsv"
if [ -s "$PB" ] && ! ls "$PILOT"/baseline-*lines*.tsv >/dev/null 2>&1; then MISS="$MISS $PILOT/baseline-lines-pilot-win.tsv"; fi
[ -z "$MISS" ] || { [ -n "${BASE_BIN:-}" ] && echo "slides-gate: note, fixed-baseline inputs missing (base mode, not needed):$MISS" || { echo "slides-gate: FAILED, missing:$MISS"; exit 1; }; }
DECKS=$W/in; PPT=$W/ppt
[ -n "${BASE_ONLY:-}" ] || PDFDIFF_NO_PAIRS=1 OFFICE_APP=$BIN "$ROOT/test/pptx-app-render.sh" -j "$JOBS" "$DECKS" "$PPT" "$W" $(ls -SL "$DECKS" | grep '\.pptx$') > "$W/run.log" 2>&1
PY=${PYTHON:-$( [ -x "$HOME/venv-word/bin/python" ] && echo "$HOME/venv-word/bin/python" || echo python3)}
SCORE_LINES() {   # SCORE_LINES DIR: lines.txt + combined.tsv in DIR (renders already there)
  PPT_REFS=$PPT PPT_MATCH_JOBS=$JOBS "$PY" "$ROOT/test/pptx-line-match.py" "$1" > "$1/lines.txt" 2> "$1/lines.err"
  "$PY" -I "$ROOT/test/tools/pptx-combine.py" "$1/lines.txt" "$1/render.tsv" "$1/combined.tsv" "$DECKS" "$PPT" | head -1
}
BASEMODE=""
if [ -n "${BASE_BIN:-}" ]; then
  BC=${BASE_CACHE:-}
  if [ -n "$BC" ] && [ -s "$BC/render.tsv" ] && [ -s "$BC/combined.tsv" ]; then
    echo "slides-gate: base render from the cache ($BC)"; mkdir -p "$W/base"; cp "$BC/render.tsv" "$BC/combined.tsv" "$W/base/"; BASEMODE=1
  else
    n=0; while [ ! -x "$BASE_BIN" ] && [ $n -lt 300 ]; do sleep 6; n=$((n+1)); done   # the base binary is still being built by the Word half
    if [ ! -x "$BASE_BIN" ]; then echo "slides-gate: base binary never appeared ($BASE_BIN); not runnable"; exit 2; fi
    mkdir -p "$W/base"
    PDFDIFF_NO_PAIRS=1 OFFICE_APP=$(readlink -f "$BASE_BIN") "$ROOT/test/pptx-app-render.sh" -j "$JOBS" "$DECKS" "$PPT" "$W/base" $(ls -SL "$DECKS" | grep '\.pptx$') > "$W/base/run.log" 2>&1
    [ -s "$W/base/render.tsv" ] || { echo "slides-gate: base render produced no scores"; tail -3 "$W/base/run.log" | cut -c1-200; exit 2; }
    SCORE_LINES "$W/base" >/dev/null
    if [ -n "$BC" ] && [ -s "$W/base/combined.tsv" ]; then mkdir -p "$BC.tmp$$" 2>/dev/null && cp "$W/base/render.tsv" "$W/base/combined.tsv" "$BC.tmp$$/" && { rm -rf "$BC"; mv "$BC.tmp$$" "$BC"; chmod -R g+rwX,o+rX "$BC" 2>/dev/null; }; fi
    BASEMODE=1
  fi
  BASEALL=$W/base/render.tsv; BASELBL=$W/base/combined.tsv
fi
# BASE_ONLY=1 (the prebuild after a main push): only the base render above, cached for the PR gates; nothing to judge.
[ -n "${BASE_ONLY:-}" ] && { [ -n "${BASEMODE:-}" ] && [ -n "${BASE_CACHE:-}" ] && [ -s "$BASE_CACHE/combined.tsv" ] && { echo "slides-gate: base cached ($BASE_CACHE) in $(( $(date +%s)-T )) s"; exit 0; }; echo "slides-gate: base-only run left no cache"; exit 2; }
[ -s "$W/render.tsv" ] || { echo "slides-gate: no scores produced"; tail -3 "$W/run.log" | cut -c1-200; exit 1; }
PXEX=$ROOT/test/corpus/pptx/pixel-excluded.txt python3 - "$BASEALL" "$W/render.tsv" "$TOL" "${LQ:-/data/landq}/approved.txt" <<'P'
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
import os
try: px=set(l.split('\t')[0].strip() for l in open(os.environ['PXEX']) if l.strip() and l[0]!='#')
except OSError: px=set()
for k,v in b.items():
    if v is None: continue
    s=k[:-5]
    if s in px: continue   # scored on lines only (pixel-excluded.txt: PowerPoint had to repair the deck)
    if n.get(k) is None: gone.append(k) if s not in ok else None
    elif n[k]>v+tol and s not in ok: bad.append((n[k]-v,k,v,n[k]))
bad.sort(reverse=True)
print("slides-gate: %d decks scored, %d worse than the base by over %.2f pt, %d no longer render"%(sum(1 for v in n.values() if v is not None),len(bad),tol,len(gone)))
for d,k,v,x in bad[:15]: print("slides-gate:   WORSE %s %.2f -> %.2f"%(k[:-5],v,x))
for k in gone: print("slides-gate:   NO-RENDER",k[:-5])
sys.exit(1 if bad or gone else 0)
P
rc=$?
# The line score beside the pixel mean (docs/plans/slides-corpus.md §5): PowerPoint's text lines matched per deck
# (test/pptx-line-match.py), combined with the visual score for decks whose print has no text (test/tools/pptx-combine.py),
# against baseline-lines-win.tsv in the corpus cache (not in git). A deck more than LTOL (default 1 pt) worse, or newly an error, blocks.
LB=$CC/baseline-lines-win.tsv
PLB=$(ls "$PILOT"/baseline-*lines*.tsv 2>/dev/null | head -1); [ -s "$LB" ] && [ -s "$PLB" ] && { { cat "$LB"; awk -F'\t' 'BEGIN{OFS="\t"} {sub(/.*\//,"",$1); print}' "$PLB"; } > "$W/lines-base.tsv"; LB=$W/lines-base.tsv; }
if [ -n "$FX" ] && [ -s "$LB" ]; then { cat "$LB"; grep -F -f <(sed 's/\.pptx$//' "$FULL/gate-subset.txt") "$FULL/baseline-lines-full-win.tsv" | awk -F'\t' 'BEGIN{OFS="\t"} {sub(/.*\//,"",$1); print}'; } > "$W/lines-base2.tsv"; LB=$W/lines-base2.tsv; fi
[ -n "$BASEMODE" ] && LB=$BASELBL
if [ -s "$LB" ]; then
  SCORE_LINES "$W"
  "$PY" - "$LB" "$W/combined.tsv" "${LTOL:-1}" "${LQ:-/data/landq}/approved.txt" <<'Q' || rc=1
import sys
def rd(f): return {l.split('\t')[0]:(float(l.split('\t')[1]),l.split('\t')[2].strip()) for l in open(f) if l.strip()}
b,n=rd(sys.argv[1]),rd(sys.argv[2]); tol=float(sys.argv[3])
try: ok=set(open(sys.argv[4]).read().split())
except OSError: ok=set()
bad=sorted(((v[0]-n[k][0],k,v[0],n[k][0]) for k,v in b.items() if k in n and v[1]!='unscoreable' and n[k][1]!='unscoreable' and v[0]-n[k][0]>tol and k not in ok),reverse=True)
print("slides-gate: line score: %d decks worse than the base by over %g pt"%(len(bad),tol))
for d,k,x,y in bad[:15]: print("  LINES %s %.1f -> %.1f"%(k,x,y))
sys.exit(1 if bad else 0)
Q
fi
echo "slides-gate: $(( $(date +%s)-T )) s"; exit $rc
