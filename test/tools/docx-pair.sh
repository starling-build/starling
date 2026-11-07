#!/bin/bash
# test/tools/docx-pair.sh [--seed] BASEBIN FIXBIN [JOBS] — the pair every Word fix lands on:
# sweep the 756 corpus and the LibreOffice set in Windows mode (bundled fonts), score
# them with the official matcher (v2) and v1 beside it, and print the movers of FIXBIN
# against BASEBIN. The scores are COMMITTED, so the base is rarely swept:
#
#   test/corpus/docx/scores/<host>/{756,lo}.{v2,v1} + STAMP     host = mac | linux | windows
#
# STAMP (test/tools/stamp.sh) names the inputs those files were scored from: the git
# hashes of apps/OfficeApp, sdk and test/docx-line-match.py, the engine commit and the
# font setting. If origin/office's stamp (or $BASE_REV's) equals the stored one, the
# stored files ARE the base and BASEBIN is not run at all; otherwise BASEBIN is swept
# and a note says so. The fix is always swept. Its files and stamp go to
# $STAGE (default /tmp/docx-pair-<host>), and a fix is landed by copying them in the
# same commit as the code:
#     cp $STAGE/* test/corpus/docx/scores/<host>/ && git add test/corpus/docx/scores && git commit --amend --no-edit
# (If the rebase before the push changes apps/ or sdk/, the stamp no longer matches:
# re-run. A conflict in scores/: take theirs, re-run.)
# --seed: BASEBIN is FIXBIN's own build; only writes the files (a scores-only commit:
# "scores: <host> at <sha>"). Output is deterministic since be9264e88 (Swift's per-process
# Dictionary order, fixed), so a document that moves with the inputs unchanged is a
# BUG and is named loudly (SWIFT_DETERMINISTIC_HASHING=1 would hide such a bug, not fix it; not set): every mover is converted once more by
# FIXBIN and kept as a mover only if the second print scores the same.
#   SETS (default "756 lo xb"; "lo" alone for a LibreOffice-only check — then do not commit the scores)
#   PYTHON (needs PyMuPDF; default python3)   BASE_REV (default origin/office)   STAGE
#   BASEBIN and FIXBIN must sit BESIDE their build's libFlutterShared.so and *.resources
#   bundles (the release dir): a binary copied away on its own cannot load and fails every
#   document. More than MAXFAIL percent (default 3) failed conversions in a set aborts the
#   run (exit 1, no files in $STAGE/fix) and prints the first failure's stderr.
#   ENGINE_OUT   the engine out dir the binaries were built against (default: the
#                first of engine/src/out/host_release_arm64, host_release)
set -u
BASE_SWEPT=0; NEEDBASE=""; BASE_SWEPT_SETS=""
SEED=0; [ "${1:-}" = "--seed" ] && { SEED=1; shift; }
BASEBIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); FIXBIN=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); JOBS=${3:-4}
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd); cd "$ROOT" || exit 2
case $(uname) in Darwin) HOST=mac;; Linux) HOST=linux;; *) HOST=windows;; esac
PY=${PYTHON:-python3}; BASE_REV=${BASE_REV:-origin/office}; STAGE=${STAGE:-/tmp/docx-pair-$HOST}
SETS=${SETS:-756 lo xb}
INPUTS="apps/OfficeApp sdk test/docx-line-match.py"
for d in ${ENGINE_OUT:-} engine/src/out/host_release_arm64 engine/src/out/host_release; do [ -d "$d" ] && { EO=$(cd "$d" && pwd -P); break; }; done
[ -n "${EO:-}" ] || { echo "no engine out dir (ENGINE_OUT)" >&2; exit 2; }
export OFFICE_NOW_TABLE=$ROOT/test/corpus/docx/clock.tsv
export OFFICE_FONT_SOURCE=bundled OFFICE_WORD_FONTS=windows STARLING_ICU=$EO/icudtl.dat STARLING_ENGINE_OUT=$EO FLUTTER_SWIFT_ENGINE_OUT=$EO
case $HOST in
  mac) export DYLD_LIBRARY_PATH=$EO;;
  linux) export LD_LIBRARY_PATH=$EO;;
  *) export PATH="$EO:$PATH";;   # Windows looks for DLLs on PATH, not LD_LIBRARY_PATH
esac

# xb: the admitted batch-B documents that have a Windows print (interim set before the corpus swap; lives in the cache,
# not in git: $STARLING_CORPUS/staging/xb/{docs,word-win}, stems listed in test/corpus/docx/xb/manifest.tsv)
corpus() { case $1 in 756) echo "$ROOT/test/corpus/docx";; lo) echo "$ROOT/test/corpus/docx/lo";; xb) echo "${STARLING_CORPUS:-/data/corpus-cache}/staging/xb";; esac; }
# base_ok SET FILE — stored/cached base scores usable for the set? xb's membership has changed (a base with another
# number of rows than the set has prints would show every new document as missing), so its row count must match.
base_ok() { [ "$1" = xb ] || return 0; local C n; C=$(corpus xb); n=$(ls "$C"/word-win/*-orig.pdf 2>/dev/null | wc -l)
  [ "$(grep -c '%  lines ' "$2" 2>/dev/null)" = "$n" ]; }
# sweep BIN WORK SET → WORK/match-v2.txt, match-v1.txt
sweep() {
  local BIN=$1 WORK=$2 SET=$3 C; C=$(corpus "$SET"); mkdir -p "$WORK/pdf" "$WORK/err"; : > "$WORK/fail.txt"
  ( cd "$C/docs" && ls *.docx | while IFS= read -r n; do
      [ -f "$C/word-win/${n%.docx}-orig.pdf" ] && [ ! -s "$WORK/pdf/${n%.docx}.pdf" ] && printf '%s\0' "$n"; done |
    xargs -0 -P "$JOBS" -I{} sh -c 'n="$1"; perl -e "alarm 300; exec @ARGV" "$2" --convert "$n" "$3/pdf/${n%.docx}.pdf" >/dev/null 2>"$3/err/${n%.docx}.txt" || echo "FAIL $n"' _ {} "$BIN" "$WORK" >> "$WORK/fail.txt" )
  local nf nd; nf=$(wc -l < "$WORK/fail.txt"); nd=$(ls "$C/docs"/*.docx | wc -l)
  if [ $(( nf * 100 )) -gt $(( nd * ${MAXFAIL:-3} )) ]; then
    f=$(head -1 "$WORK/fail.txt" | sed 's/^FAIL //'); echo "ABORT: $nf of $nd conversions failed in set $SET with $BIN — nothing written to $STAGE/fix" >&2
    echo "first failure ($f), its stderr:" >&2; head -20 "$WORK/err/${f%.docx}.txt" >&2
    echo "(is the binary beside libFlutterShared.so and the *.resources bundles? a copied binary needs its whole release dir)" >&2
    rm -rf "$STAGE/fix"; exit 1
  fi
  score "$WORK" "$C"
}
score() {  # WORK CORPUSDIR — v2 and v1 side by side, each over MATCH_JOBS processes (the matcher's output is the serial one's)
  export DOCX_MATCH_JOBS=${MATCH_JOBS:-$JOBS}
  DOCX_LINE_MATCH=v2 DOCX_WORD_REFS=$2/word-win $PY -W ignore -I "$ROOT/test/docx-line-match.py" "$1" > "$1/match-v2.txt" 2>"$1/match-v2.err" &
  DOCX_LINE_MATCH=v1 DOCX_WORD_REFS=$2/word-win $PY -W ignore -I "$ROOT/test/docx-line-match.py" "$1" > "$1/match-v1.txt" 2>"$1/match-v1.err" &
  wait
}

# vis_set SET FIXWORK BASEWORK — the VISUAL-scored documents (Word's print has no text lines: lines 0/n in v2) are scored
# from the pages instead (test/tools/docx-combine.py; 100 at worst page <= 1% of pixels, 0 at 10%). Both sides are rendered
# or reused from their sweep, then scored by test/docx-visual.py over just those documents. Writes $FIX/$S.{vis,combined};
# $BASE/$S.{vis,combined} too when BASEWORK is given. The "vis v2" section's header ends in " v2" on purpose: land.sh blocks
# on a DOWN there like on any v2 drop, and LAND_ACCEPT_DROP names them the same way.
vis_side() {  # SET WORKDIR(with pdf/) V2FILE OUTDIR LABEL [BIN]
  local S=$1 W=$2 V2=$3 OUT=$4 L=$5 BIN=${6:-} C names v n; C=$(corpus "$S")
  names=$($PY "$HERE/docx-combine.py" select "$V2") || return 1
  local VW=$STAGE/work/vis-$L-$S; rm -rf "$VW"; mkdir -p "$VW/pdf" "$VW/refs"
  for n in $names; do
    ln -s "$C/word-win/$n-orig.pdf" "$VW/refs/$n-orig.pdf" 2>/dev/null
    if [ -s "$W/pdf/$n.pdf" ]; then ln -s "$W/pdf/$n.pdf" "$VW/pdf/$n.pdf"
    elif [ -n "$BIN" ]; then ( cd "$C/docs" && perl -e "alarm 300; exec @ARGV" "$BIN" --convert "$n.docx" "$VW/pdf/$n.pdf" >/dev/null 2>&1 ); fi
  done
  DOCX_CORPUS=$C $PY -W ignore "$HERE/../docx-visual.py" "$VW" "$VW/refs" "$VW/visual" >"$VW/visual.log" 2>&1 || { echo "visual scoring failed for $L $S (see $VW/visual.log)" >&2; return 1; }
  $PY "$HERE/docx-combine.py" combine "$V2" "$VW/visual" "$OUT/$S.vis" "$OUT/$S.combined" "$L $S"
}

# The sets are swept side by side (JOBS each; the LibreOffice set is short, the 756's slowest document sets the wall time):
# wait_sets LABEL — wait for every background sweep; if one aborted, so does the run.
wait_sets() { local bad=0 j; for j in $(jobs -p); do wait "$j" || bad=1; done
  [ $bad = 0 ] || { echo "ABORT: a $1 sweep failed (see above) — nothing written to $STAGE/fix" >&2; rm -rf "$STAGE/fix"; exit 1; }; }

rm -rf "$STAGE"; mkdir -p "$STAGE/work"
# the base: stored scores, if their stamp is the base revision's
BASE=$STAGE/base; mkdir -p "$BASE"
STORED=test/corpus/docx/scores/$HOST
want=$(test/tools/stamp.sh -r "$BASE_REV" $INPUTS)
have=$(git show "$BASE_REV:$STORED/STAMP" 2>/dev/null || true)
if [ $SEED = 0 ] && [ -n "${BASE_SCORES:-}" ]; then
  # BASE_SCORES: a directory holding <set>.{v2,v1} of the base — the shared base cache (test/tools/base-cache.sh)
  echo "base: scores from $BASE_SCORES (shared cache) — base sweep skipped"
  for S in $SETS; do if [ -s "$BASE_SCORES/$S.v2" ] && base_ok $S "$BASE_SCORES/$S.v2"; then for v in v2 v1; do cp "$BASE_SCORES/$S.$v" "$BASE/$S.$v" || exit 2; done; else NEEDBASE="$NEEDBASE $S"; fi; done
elif [ $SEED = 0 ] && [ "$want" = "$have" ]; then
  echo "base: stored scores of $HOST match $BASE_REV's stamp — base sweep skipped"
  for S in $SETS; do if git cat-file -e "$BASE_REV:$STORED/$S.v2" 2>/dev/null && { git show "$BASE_REV:$STORED/$S.v2" > "$BASE/$S.v2"; base_ok $S "$BASE/$S.v2"; }; then git show "$BASE_REV:$STORED/$S.v1" > "$BASE/$S.v1"; else NEEDBASE="$NEEDBASE $S"; fi; done
elif [ $SEED = 0 ]; then
  echo "base: no stored scores for $HOST at $BASE_REV's stamp (stored: $( [ -n "$have" ] && echo different || echo none )) — sweeping BASEBIN"
  # (swept beside the fix below, not before it: both are waited for together)
  for S in $SETS; do ( sweep "$BASEBIN" "$STAGE/work/base-$S" $S >/dev/null ) & done
  BASE_SWEPT=1
fi
# a set with no stored/cached base scores yet (a new set, xb) gets its base swept here
if [ $SEED = 0 ] && [ -n "$NEEDBASE" ]; then
  echo "base: no stored scores for set(s)$NEEDBASE — sweeping BASEBIN for them"
  for S in $NEEDBASE; do ( sweep "$BASEBIN" "$STAGE/work/base-$S" $S >/dev/null ) & done
  BASE_SWEPT_SETS="$NEEDBASE"
fi
# the fix
FIX=$STAGE/fix; mkdir -p "$FIX"
for S in $SETS; do ( T0=$(date +%s); sweep "$FIXBIN" "$STAGE/work/fix-$S" $S && echo "$(( $(date +%s)-T0 )) s" > "$STAGE/work/fix-$S.time" ) & done
wait_sets fix
[ "${BASE_SWEPT:-0}" = 1 ] && for S in $SETS; do for v in v2 v1; do cp "$STAGE/work/base-$S/match-$v.txt" "$BASE/$S.$v"; done; done
[ -n "${BASE_SWEPT_SETS:-}" ] && for S in $BASE_SWEPT_SETS; do for v in v2 v1; do cp "$STAGE/work/base-$S/match-$v.txt" "$BASE/$S.$v"; done; done
for S in $SETS; do
  echo "fix $S: $(cat "$STAGE/work/fix-$S.time"), failures $(wc -l < "$STAGE/work/fix-$S/fail.txt")"
  for v in v2 v1; do cp "$STAGE/work/fix-$S/match-$v.txt" "$FIX/$S.$v"; done
done
for S in $SETS; do vis_side $S "$STAGE/work/fix-$S" "$FIX/$S.v2" "$FIX" fix || { echo "ABORT: visual scoring (fix, $S)" >&2; exit 1; }; done
test/tools/stamp.sh $INPUTS > "$FIX/STAMP"
if [ $SEED = 1 ]; then echo "seed written to $FIX (cp $FIX/* $STORED/)"; exit 0; fi
# movers (and the nondeterministic ones)
for S in $SETS; do for v in v2 v1; do
  echo "== $S $v"; $PY "$HERE/docx-cmp.py" "$FIX/$S.$v" "$BASE/$S.$v" > "$STAGE/cmp-$S-$v.txt"; cat "$STAGE/cmp-$S-$v.txt"
done; done
# the visual-scored documents: base rendered (or reused) and scored beside the fix; movers in a "vis v2" section
for S in $SETS; do
  bw=$STAGE/work/base-$S; [ -d "$bw/pdf" ] || bw=$STAGE/work/none
  vis_side $S "$bw" "$BASE/$S.v2" "$BASE" base "$BASEBIN" || { echo "ABORT: visual scoring (base, $S)" >&2; exit 1; }
  echo "== $S vis v2"; $PY "$HERE/docx-cmp.py" "$FIX/$S.vis" "$BASE/$S.vis" > "$STAGE/cmp-$S-vis.txt"; cat "$STAGE/cmp-$S-vis.txt"
done
# re-print every mover with FIXBIN once more; a different score the second time is noise
echo "== nondeterminism check"
for S in $SETS; do
  C=$(corpus "$S"); names=$(grep -hE '^\s+(UP|DOWN|CHANGED)' "$STAGE/cmp-$S-v2.txt" "$STAGE/cmp-$S-v1.txt" | awk '{ if ($0 ~ /CHANGED\(same ratio\)/) { match($0, /CHANGED\(same ratio\) [^: ]+/); split(substr($0,RSTART,RLENGTH),a," "); print a[2] } else print $NF }' | sort -u)
  [ -n "$names" ] || continue
  W=$STAGE/work/again-$S; mkdir -p "$W/pdf"
  printf '%s\n' $names | xargs -P "$JOBS" -I{} sh -c 'f=$(ls "$1/docs/$2"*.docx 2>/dev/null | head -1); [ -n "$f" ] && perl -e "alarm 300; exec @ARGV" "$3" --convert "$f" "$4/pdf/$(basename "${f%.docx}").pdf" >/dev/null 2>&1' _ "$C" {} "$FIXBIN" "$W"
  score "$W" "$C"
  for n in $names; do k=$(basename "$(ls "$C/docs/$n"*.docx | head -1)" .docx)
    a=$(grep " $k\$" "$W/match-v2.txt"); b=$(grep " $k\$" "$STAGE/work/fix-$S/match-v2.txt")
    [ "$a" = "$b" ] || echo "!!! NONDETERMINISTIC $k: the same binary scored $(echo $b | cut -d' ' -f1) then $(echo $a | cut -d' ' -f1) — a BUG (an iteration-order dependence), not a mover; tell macOS-doc"
  done
done
echo "fix files and stamp: $FIX — to land: cp $FIX/* $STORED/ && git add $STORED && git commit --amend --no-edit"
