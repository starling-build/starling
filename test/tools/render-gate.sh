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
# documents named in the commit messages
git log --format=%B "$BASE_SHA..HEAD" | grep -oE '[0-9a-f]{6,12}|(zh|lo|xa|xb|xd|xs|ko|ja|hi|bn)-[A-Za-z0-9_.-]+' | sort -u > "$W/named.txt"
ids=$W/ids.txt; { cat "$W/named.txt"; [ -s "$LQ/sample.txt" ] && cat "$LQ/sample.txt"; } | sort -u > "$ids"
# a fresh runner checkout has no engine link and no corpus: use the machine's engine and the corpus cache
[ -e engine ] || ln -s "${ENGINE_DIR:?set ENGINE_DIR in the runner .env}" engine
test/tools/corpus-cache.sh restore >/dev/null 2>&1 || echo "render-gate: corpus restore failed"
# build HEAD here and BASE_SHA in a worktree; the base binary is cached by sha in the runner's own scratch
. ~/bin/office-env.sh >/dev/null 2>&1 || { echo "render-gate: office-env.sh failed"; exit 2; }
export OFFICE_WORD_FONTS=windows OFFICE_FONT_SOURCE=bundled
EO=$(readlink -f engine)/src/out/host_release
BC=${GATE_BASECACHE:-$HOME/scratch/basecache}; BSHA=$(git rev-parse "$BASE_SHA"); mkdir -p "$BC"
echo "render-gate: building"
if [ ! -x "$BC/$BSHA/release/OfficeApp" ]; then
  git worktree add -f --detach "$W/basetree" "$BSHA" -q || { echo "render-gate: cannot check out base"; exit 2; }
  ln -s "$(readlink -f engine)" "$W/basetree/engine" 2>/dev/null
  ( cd "$W/basetree" && test/tools/build-office-fast.sh "$W/basebuild" > "$W/base-build.log" 2>&1 ) &
  BPID=$!
fi
test/tools/build-office-fast.sh "$W/build" > "$W/build.log" 2>&1 || { echo "render-gate: BUILD FAILED"; tail -15 "$W/build.log" | cut -c1-200; exit 1; }
if [ -n "${BPID:-}" ]; then
  wait $BPID || { echo "render-gate: BASE BUILD FAILED"; tail -15 "$W/base-build.log" | cut -c1-200; exit 1; }
  BREL=$(dirname "$(ls "$W"/basebuild/*/release/OfficeApp | head -1)"); rm -rf "$BC/$BSHA"; mkdir -p "$BC/$BSHA"; cp -a "$BREL" "$BC/$BSHA/release"
  git worktree remove --force "$W/basetree" 2>/dev/null
fi
BASEBIN=$BC/$BSHA/release/OfficeApp
BIN=$(ls "$W"/build/*/release/OfficeApp 2>/dev/null | head -1); [ -x "$BIN" ] && [ -x "$BASEBIN" ] || { echo "render-gate: no binary"; exit 2; }
echo "render-gate: $(wc -l < "$ids") documents (named + sample)"
# both binaries render the same subset (SWEEP_ONLY), so the base needs no stored scores
[ "${GATE_FULL:-0}" = 1 ] || export SWEEP_ONLY=$ids
ENGINE_OUT=$EO STAGE=$W/pair BASE_SCORES= BASE_REV=$BASE_SHA SCORES_BASE=/nonexistent test/tools/docx-pair.sh "$BASEBIN" "$BIN" "$JOBS" > "$W/pair.log" 2>&1
rc=$?
if [ $rc != 0 ]; then echo "render-gate: pair failed (exit $rc)"; grep -aE "ABORT|failed|no engine" "$W/pair.log" | head -5 | cut -c1-200; exit 1; fi
# a gate that compared nothing must not pass
NCMP=$(awk '/^== /{v2=($0 ~ / v2$/)} v2 && /^NEW: [1-9]/{n++} END{print n+0}' "$W/pair.log")
[ "$NCMP" -gt 0 ] || { echo "render-gate: nothing was compared (see runner log)"; exit 1; }
DN=$(awk '/^== /{v2=($0 ~ / v2$/)} v2 && /^up .* down [1-9]/{n++} END{print n+0}' "$W/pair.log")
# v2 drops: lines "  DOWN <stem> ..." inside "== <set> v2" sections
awk '/^== /{v2=($0 ~ / v2$/)} v2 && /^ *DOWN /{print}' "$W/pair.log" > "$W/down.txt"
DROPS=""
while read -r line; do
  stem=${line##* }; s=$(basename "${stem%.docx}"); grep -qE "^${s}[ .]" "$LQ/approved.txt" 2>/dev/null || DROPS="$DROPS $s"
done < "$W/down.txt"
if [ -n "$DROPS" ]; then echo "render-gate: BLOCKED, v2 drops not approved:$DROPS"; exit 1; fi
[ "$DN" = 0 ] || [ -s "$W/down.txt" ] || { echo "render-gate: drops reported but not parsed"; exit 1; }
echo "render-gate: $NCMP sets compared; clean ($(wc -l < "$W/down.txt") approved drops)"; exit 0
