#!/bin/bash
# sheets-gate.sh BIN BASE_BIN BASE_CACHE [JOBS] — the Sheets step of the render gate (amd-8, 2026-11-22).
# Draws every workbook Excel printed (cache copy of test/corpus/xlsx, 757 books, ~40 s at 32 jobs) with BIN and with BASE_BIN (the merge base;
# the base side is cached per main sha in BASE_CACHE/per-book.tsv, with score-cache.tsv: a PR book whose PDF is byte-identical to the base's takes the base's score, no rescoring) and compares the two per BOOK (test/tools/sheets-sweep.py: pixels and
# text lines against Excel's print). A book blocks when its pixel mean is more than TOL (0.05 pt) worse, its line match drops more than
# LTOL (0.5 pt), or it printed before and now does not. A book in $LQ/approved.txt is waived only for a PR whose own commit message or body
# names its full name (as for Slides decks). Exit 0 clean, 1 blocked, 2 not runnable. BASE_ONLY=1 renders and caches the base only.
BIN=$(readlink -f "${1:?usage: sheets-gate.sh BIN BASE_BIN BASE_CACHE [JOBS]}"); BASEBIN=$(readlink -f "$2"); BC=$3; JOBS=${4:-32}
TOL=${TOL:-0.05}; LTOL=${LTOL:-0.5}
ROOT=$(cd "$(dirname "$0")/../.." && pwd); CC=${CORPUS_CACHE:-/data/corpus-cache}/test/corpus/xlsx
[ -d "$CC/books" ] && [ -d "$CC/${SHEETS_EXCEL:-excel-20261122}" ] || { echo "sheets-gate: no xlsx corpus here; skipped"; exit 2; }
PY=${PYTHON:-$( [ -x "$HOME/venv-word/bin/python" ] && echo "$HOME/venv-word/bin/python" || echo python3)}
W=${SHEETS_SCRATCH:-${GATE_SCRATCH:-$HOME/scratch/gate}/sheets}; rm -rf "$W"; mkdir -p "$W"; T=$(date +%s)
export OFFICE_FONT_SOURCE=bundled PDFDIFF_NO_PAIRS=1
REUSE=
SWEEP() { SHEETS_REUSE=$REUSE "$PY" "$ROOT/test/tools/sheets-sweep.py" "$1" "$2" -j "$JOBS" > "$2.log" 2>&1; [ -s "$2/per-book.tsv" ]; }
STAMP=$("$ROOT/test/tools/gate-stamp.sh" sheets "$BASEBIN" 2>/dev/null)   # binary + scorer sha the base is drawn with
if [ -n "$BC" ] && [ -s "$BC/per-book.tsv" ] && [ -n "$STAMP" ] && [ "$(cat "$BC/STAMP" 2>/dev/null)" = "$STAMP" ]; then echo "sheets-gate: base render from the cache ($BC)"; cp "$BC/per-book.tsv" "$W/base.tsv"; REUSE=$BC
else
  [ -x "$BASEBIN" ] || { echo "sheets-gate: no base binary; not runnable"; exit 2; }
  SWEEP "$BASEBIN" "$W/b" || { echo "sheets-gate: base render produced nothing"; tail -3 "$W/b.log" | cut -c1-200; exit 2; }
  cp "$W/b/per-book.tsv" "$W/base.tsv"; REUSE=$W/b
  if [ -n "$BC" ]; then mkdir -p "$BC.tmp$$" 2>/dev/null && cp "$W/b/per-book.tsv" "$W/b/per-page.tsv" "$W/b/score-cache.tsv" "$BC.tmp$$/" && echo "$STAMP" > "$BC.tmp$$/STAMP" && { rm -rf "$BC"; mv "$BC.tmp$$" "$BC"; } 2>/dev/null; fi
fi
[ -n "${BASE_ONLY:-}" ] && { echo "sheets-gate: base cached ($BC) in $(( $(date +%s)-T )) s"; exit 0; }
SWEEP "$BIN" "$W/p" || { echo "sheets-gate: no scores produced"; tail -3 "$W/p.log" | cut -c1-200; exit 1; }
ACC=$W/accepted.txt; : > "$ACC"
MSGS="${PR_BODY:-}"$'\n'$(git -C "$ROOT" log --format=%B "$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null || echo HEAD)..HEAD" 2>/dev/null || true)
# an id counts the same with or without its .xls/.xlsx/.docx/.pptx suffix, in approved.txt and in the message alike (starling-bd, 2026-11-27):
# the waiver list gets every spelling, so the scorer's own key (bare or suffixed) always finds it
for t in $(cat "${LQ:-/data/landq}/approved.txt" 2>/dev/null); do b=$t; case $t in *.xls|*.xlsx|*.docx|*.pptx) b=${t%.*};; esac
  case "$MSGS" in *"$b"*) printf '%s\n' "$b" "$b.xls" "$b.xlsx" "$b.docx" "$b.pptx" >> "$ACC";; esac; done
python3 -I - "$W/base.tsv" "$W/p/per-book.tsv" "$TOL" "$LTOL" "$ACC" <<'P'
import sys
base, new, tol, ltol, acc = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), sys.argv[5]
def rd(f):
    d = {}
    for l in open(f).read().splitlines()[1:]:
        p = l.split("\t"); d[p[0]] = p
    return d
b, n = rd(base), rd(new); ok = set(open(acc).read().split())
def f(x):
    try: return float(x)
    except ValueError: return None
bad = []; ot = []; worse = better = 0
for k, p in b.items():
    q = n.get(k)
    if p[6].startswith("ERROR"): continue
    if q is None or q[6].startswith("ERROR"):
        if k not in ok:
            st = q[6] if q else 'missing'
            # a render that timed out or has no row is the STEP running out of time on a loaded box (amd-8, 2026-11-23, #2451 under load 369), not a drop: say so, rerun the gate
            if q is None or "timeout" in st or "Terminated" in st or "Killed" in st: st += "  [STEP RAN OUT OF TIME / box overloaded, not a drop: rerun the gate]"; ot.append(k)
            bad.append((99, f"{k}: printed before, now {st}"))
        continue
    px0, px1, l0, l1 = f(p[3]), f(q[3]), f(p[5]), f(q[5])
    if px0 is not None and px1 is not None:
        if px1 > px0 + tol: worse += 1
        elif px1 < px0 - tol: better += 1
        if px1 > px0 + tol and k not in ok: bad.append((px1 - px0, f"{k}: pixels {px0:.2f} to {px1:.2f}"))
    if l0 is not None and l1 is not None and l1 < l0 - ltol and k not in ok: bad.append((l0 - l1, f"{k}: lines matched {l0:.1f} to {l1:.1f}"))
    elif l0 is None and l1 is not None and False: pass
nb = sum(1 for v in n.values() if v[6] == "ok" or v[6] == "ok-empty")
print(f"sheets-gate: {nb} books scored; pixels worse {worse}, better {better}; blocked {len(bad)}")
if ot: print(f"sheets-gate: WARNING {len(ot)} book(s) timed out or have no result: the step was cut short by load, these are not drops")
for _, m in sorted(bad, reverse=True)[:15]:
    print("sheets-gate: BLOCKED-BOOK " + m.split(":")[0] + "   " + m)
sys.exit(1 if bad else 0)
P
rc=$?; echo "sheets-gate: done in $(( $(date +%s)-T )) s"; exit $rc
