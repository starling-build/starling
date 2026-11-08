#!/bin/bash
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
# dx2-round.sh BIN TIP PREV [JOBS] — tier 2 of the Word gate: the whole dx2 set (about 1,800 docxcorp documents in 65
# languages, test/corpus/docx/dx2), REPORT ONLY. Sweeps it with BIN (the tip's OfficeApp, in the pair's Windows
# settings), scores v2 against Word's prints, compares with the stored scores (test/corpus/docx/scores/linux/dx2.v2,
# or $BASELINE), and prints: the per-language means, every document that went down (language, type, change), and
# the blame: the commits that touched apps/ or sdk/ between PREV and TIP. A drop here never blocks a landing; the
# author of a listed commit is told by the tip watcher. Writes $STAGE/dx2.v2 (the new stored scores: copy to
# scores/linux/dx2.v2 and commit it, in the round's board push).
#   Needs PYTHON (venv with the matcher's modules) and ENGINE_OUT (as docx-pair.sh).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd); cd "$ROOT" || exit 2
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); TIP=${2:?tip}; PREV=${3:?prev}; JOBS=${4:-16}
PY=${PYTHON:-python3}; STAGE=${STAGE:-/tmp/dx2-round}; BASELINE=${BASELINE:-$ROOT/test/corpus/docx/scores/linux/dx2.v2}
C=${STARLING_CORPUS:-/data/corpus-cache}/staging/dx2
for d in ${ENGINE_OUT:-} engine/src/out/host_release; do [ -d "$d" ] && { EO=$(cd "$d" && pwd -P); break; }; done
[ -n "${EO:-}" ] || { echo "no engine out dir (ENGINE_OUT)" >&2; exit 2; }
export OFFICE_NOW_TABLE=$ROOT/test/corpus/docx/clock.tsv OFFICE_FONT_SOURCE=bundled OFFICE_WORD_FONTS=windows
export STARLING_ICU=$EO/icudtl.dat STARLING_ENGINE_OUT=$EO FLUTTER_SWIFT_ENGINE_OUT=$EO LD_LIBRARY_PATH=$EO
W=$STAGE/work; mkdir -p "$W/pdf" "$W/err"; : > "$W/fail.txt"
( cd "$C/docs" && ls *.docx | while IFS= read -r n; do
    [ -f "$C/word-win/${n%.docx}-orig.pdf" ] && [ ! -s "$W/pdf/${n%.docx}.pdf" ] && printf '%s\0' "$n"; done |
  xargs -0 -P "$JOBS" -I{} sh -c 'n="$1"; perl -e "alarm 300; exec @ARGV" "$2" --convert "$n" "$3/pdf/${n%.docx}.pdf" >/dev/null 2>"$3/err/${n%.docx}.txt" || echo "FAIL $n"' _ {} "$BIN" "$W" >> "$W/fail.txt" )
nf=$(wc -l < "$W/fail.txt"); nd=$(ls "$C/docs"/*.docx | wc -l)
echo "dx2: $nd documents, $nf conversion failures"
[ $(( nf * 100 )) -gt $(( nd * 3 )) ] && { echo "ABORT: too many conversion failures with $BIN" >&2; exit 1; }
export DOCX_MATCH_JOBS=$JOBS
DOCX_LINE_MATCH=v2 DOCX_WORD_REFS=$C/word-win $PY -W ignore -I "$ROOT/test/docx-line-match.py" "$W" > "$STAGE/dx2.v2" 2>"$W/match-v2.err" || { echo "matcher failed"; tail -3 "$W/match-v2.err"; exit 1; }
$PY - "$ROOT/test/corpus/docx/dx2/manifest.tsv" "$STAGE/dx2.v2" "$BASELINE" "$TIP" "$PREV" <<'PY'
import csv, re, subprocess, sys, collections
man, newf, oldf, tip, prev = sys.argv[1:6]
ROW = re.compile(r'\s*([\d.]+)%\s+lines (\d+)/(\d+)\s+pages (\d+)/(\d+)\s+(\S+)')
def load(p):
    d = {}
    try:
        for l in open(p):
            m = ROW.match(l)
            if m: d[m.group(6)] = (float(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5)))
    except FileNotFoundError: pass
    return d
new, old = load(newf), load(oldf)
meta = {r['name']: r for r in csv.DictReader(open(man), delimiter='\t')}
lang = collections.defaultdict(list)
for k, v in new.items():
    lang[meta.get(k, {}).get('language', '?')].append((v[0], old[k][0] if k in old else None))
tot = [v[0] for v in new.values()]
print(f"DX2 {tip[:9]}: {len(new)} documents scored, mean {sum(tot)/max(1,len(tot)):.2f}"
      + (f"; stored base has {len(old)} rows" if old else "; no stored base: this run SEEDS it"))
print("per-language mean (now, change vs stored):")
rows = []
for l, v in lang.items():
    now = sum(x[0] for x in v) / len(v)
    ch = [x for x in v if x[1] is not None]
    d = (sum(x[0] for x in ch) / len(ch) - sum(x[1] for x in ch) / len(ch)) if ch else None
    rows.append((now, l, len(v), d))
print("  " + "; ".join(f"{l} {n} docs {m:.1f}" + (f" ({d:+.2f})" if d else "") for m, l, n, d in sorted(rows)))
if old:
    dn = sorted(((new[k][0] - old[k][0], k) for k in new if k in old and (new[k][0] < old[k][0] or (new[k][0] == old[k][0] and (new[k][1], new[k][3]) < (old[k][1], old[k][3])))))
    up = sum(1 for k in new if k in old and new[k][0] > old[k][0])
    print(f"vs stored: up {up}, down {len(dn)}, new docs {len(set(new)-set(old))}, missing {len(set(old)-set(new))}")
    for dv, k in dn[:40]:
        m = meta.get(k, {})
        print(f"  DOWN {old[k][0]:5.1f} -> {new[k][0]:5.1f}  {m.get('language','?')} {m.get('type','?')}  {k}")
    if dn:
        log = subprocess.run(['git', 'log', '--format=%h %an: %s', f'{prev}..{tip}', '--', 'apps', 'sdk'], capture_output=True, text=True).stdout.strip().splitlines()
        print(f"blame: {len(log)} code commit(s) between {prev[:9]} and {tip[:9]}" + (" (one commit: it is the cause)" if len(log) == 1 else " (bisect with bins/<sha> if no author claims it)"))
        for l in log[:12]: print("   " + l[:140])
PY
echo "new stored scores: $STAGE/dx2.v2 (copy to test/corpus/docx/scores/linux/dx2.v2)"
