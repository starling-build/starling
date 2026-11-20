#!/bin/bash
# test/tools/render-gate.sh BASE_SHA — the GitHub render gate (amd-8, 2026-11-20). Runs in the checkout of the PR head
# (or the merge-queue ref) on a self-hosted runner. It builds OfficeApp from this checkout into the runner's own scratch,
# renders the documents named in the commit messages (BASE_SHA..HEAD) plus the fixed sample, scores them against the
# stored base scores, and fails on any v2 drop that /data/landq/approved.txt does not cover.
# Reads (never writes) /data/landq: approved.txt, sample.txt, sample-dx2.txt and base/linux (scores + STAMP).
# Public log: only a short summary (counts and document stems), no paths or renders.
# Env: JOBS (default 44), GATE_SCRATCH (default $HOME/scratch/gate-$$), GATE_FULL=1 (no subset: the whole sets).
set -u
BASE_SHA=${1:?usage: render-gate.sh BASE_SHA}
cd "$(dirname "$0")/../.." || exit 2
ROOT=$PWD; JOBS=${JOBS:-44}; W=${GATE_SCRATCH:-$HOME/scratch/gate-$$}; mkdir -p "$W"
LQ=${LANDQ:-/data/landq}; SB=$LQ/base/linux
trap 'rm -rf "$W/pair" "$W/build"' EXIT
export PYTHON=${PYTHON:-$HOME/venv-word/bin/python}
# stored base scores must belong to the base commit's code, else the comparison is meaningless
WANT=$(cat "$SB/STAMP" 2>/dev/null); HAVE=$(test/tools/stamp.sh -r "$BASE_SHA" apps/OfficeApp sdk test/docx-line-match.py 2>/dev/null)
if [ -z "$WANT" ] || [ "$WANT" != "$HAVE" ]; then echo "render-gate: base scores do not match the base commit's code yet (retry after the next round)"; exit 3; fi
# documents named in the commit messages
git log --format=%B "$BASE_SHA..HEAD" | grep -oE '[0-9a-f]{6,12}|(zh|lo|xa|xb|xd|xs|ko|ja|hi|bn)-[A-Za-z0-9_.-]+' | sort -u > "$W/named.txt"
ids=$W/ids.txt; { cat "$W/named.txt"; [ -s "$LQ/sample.txt" ] && cat "$LQ/sample.txt"; } | sort -u > "$ids"
# a fresh runner checkout has no engine link and no corpus: use the machine's engine and the corpus cache
[ -e engine ] || ln -s "${ENGINE_DIR:?set ENGINE_DIR in the runner .env}" engine
test/tools/corpus-cache.sh restore >/dev/null 2>&1 || echo "render-gate: corpus restore failed"
# build
. ~/bin/office-env.sh >/dev/null 2>&1 || { echo "render-gate: office-env.sh failed"; exit 2; }
export OFFICE_WORD_FONTS=windows OFFICE_FONT_SOURCE=bundled
EO=$(readlink -f engine)/src/out/host_release
echo "render-gate: building"
test/tools/build-office-fast.sh "$W/build" > "$W/build.log" 2>&1 || { echo "render-gate: BUILD FAILED"; tail -15 "$W/build.log" | cut -c1-200; exit 1; }
BIN=$(ls "$W"/build/*/release/OfficeApp 2>/dev/null | head -1); [ -x "$BIN" ] || { echo "render-gate: no binary"; exit 2; }
echo "render-gate: $(wc -l < "$ids") documents (named + sample)"
SUBSET_IDS=$([ "${GATE_FULL:-0}" = 1 ] || echo "$ids") BASE_SCORES=$SB ENGINE_OUT=$EO STAGE=$W/pair \
  test/tools/docx-pair.sh "$BIN" "$BIN" "$JOBS" > "$W/pair.log" 2>&1
rc=$?
if [ $rc != 0 ]; then echo "render-gate: pair failed (exit $rc)"; grep -aE "ABORT|failed|no engine" "$W/pair.log" | head -5 | cut -c1-200; exit 1; fi
# v2 drops: lines "  DOWN <stem> ..." inside "== <set> v2" sections
awk '/^== /{v2=($0 ~ / v2$/)} v2 && /^ *DOWN /{print}' "$W/pair.log" > "$W/down.txt"
DROPS=""
while read -r line; do
  stem=${line##* }; s=$(basename "${stem%.docx}"); grep -qE "^${s}[ .]" "$LQ/approved.txt" 2>/dev/null || DROPS="$DROPS $s"
done < "$W/down.txt"
if [ -n "$DROPS" ]; then echo "render-gate: BLOCKED, v2 drops not approved:$DROPS"; exit 1; fi
echo "render-gate: clean ($(wc -l < "$W/down.txt") approved drops)"; exit 0
