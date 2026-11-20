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
# Classify the change (BASE_SHA..HEAD): (1) render-relevant paths (test/tools/render-paths.txt) -> the full gate;
# (2) gate tooling (workflows, this script, the pair/combine/scorer tools) -> a quick self-test (2 documents through the new tooling);
# (3) anything else cannot change a render -> pass at once.
MODE=full
if [ "${GATE_PREBUILD:-0}" != 1 ] && git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
  CH=$(git diff --name-only "$BASE_SHA" HEAD)
  if [ -z "$CH" ]; then echo "render-gate: no changed files; no render-relevant change, pass"; exit 0; fi
  PAT=$(grep -vE '^#|^$' "$(dirname "$0")/render-paths.txt" | paste -sd'|')
  if ! echo "$CH" | grep -qE "$PAT"; then
    if echo "$CH" | grep -qE '^\.github/workflows/render-gate|^test/tools/(render-gate|docx-pair|docx-combine|docx-line-match|docx-line-sweep|gen-render-paths)|^test/docx-line-match\.py|^test/tools/render-paths\.txt'; then MODE=selftest
    else echo "render-gate: no render-relevant change ($(echo "$CH" | wc -l) files); pass"; exit 0; fi
  fi
fi
cd "$(dirname "$0")/../.." || exit 2
export BUILD_INCREMENTAL=1   # base and PR build use the same flags (incremental, path-stable scratches)
export SETS="${SETS:-756 lo xb xa xd xs sa1 sa2 dx2}"   # the gate sample draws from these sets too (user focus: es-MX, pt-BR, ko, ja)
ROOT=$PWD; JOBS=${JOBS:-44}; W=${GATE_SCRATCH:-$HOME/scratch/gate}; mkdir -p "$W"   # PERSISTENT: the warm build scratches below make the builds incremental (cold 315 s, warm ~90 s)
exec 9>"$W/lock"; flock 9   # one gate (or prebuild) at a time per scratch
LQ=${LANDQ:-/data/landq}; SB=$LQ/base/linux
trap 'rm -rf "$W/pair"' EXIT
TH=${TOOLS_HOME:-/home/starling}   # the runner user has its own empty HOME: tools live under the machine owner
export PYTHON=${PYTHON:-$TH/venv-word/bin/python}
# documents named in the commit messages
git log --format=%B "$BASE_SHA..HEAD" | grep -oE '[0-9a-f]{6,12}|(zh|lo|xa|xb|xd|xs|ko|ja|hi|bn)-[A-Za-z0-9_.-]+' | sort -u > "$W/named.txt"
# GATE_TARGETS_ONLY=1 (pull_request event): only the named documents, fast feedback; no named docs -> the sample, so the check is never vacuous.
# The merge_group event runs the full gate (named + sample) against the group base.
ids=$W/ids.txt
if [ "$MODE" = selftest ]; then head -2 "$LQ/sample.txt" > "$ids"; echo "render-gate: gate tooling changed: self-test on 2 documents"
elif [ "${GATE_TARGETS_ONLY:-0}" = 1 ] && [ -s "$W/named.txt" ]; then sort -u "$W/named.txt" > "$ids"
else { cat "$W/named.txt"; [ -s "$LQ/sample.txt" ] && cat "$LQ/sample.txt"; } | sort -u > "$ids"; fi
# named ids are prefixes (8 hex) or set-prefixed names; the sweep matches whole stems, so expand each to the corpus stems it names
# (a commit SHA in a message matches nothing and is dropped)
CC=${STARLING_CORPUS:-/data/corpus-cache}
{ cat "$ids"; while read -r t; do [ ${#t} -ge 6 ] || continue
    for d in test/corpus/docx test/corpus/docx/lo "$CC"/staging/*; do ls "$d/docs" 2>/dev/null | grep -E "\.docx$" | grep -F "$t" | sed 's/\.docx$//'; done
  done < "$W/named.txt"; } | sort -u > "$ids.x" && mv "$ids.x" "$ids"
# a fresh runner checkout has no engine link and no corpus: use the machine's engine and the corpus cache
ENGINE_DIR=${ENGINE_DIR:?set ENGINE_DIR in the runner .env}
[ -d "$ENGINE_DIR/src/out/host_release" ] || { echo "render-gate: ENGINE_DIR=$ENGINE_DIR has no src/out/host_release"; exit 2; }
ln -sfn "$ENGINE_DIR" engine   # every run: a clone must never keep pointing at an old engine path
test/tools/corpus-cache.sh restore 2>&1 | tail -3 | cut -c1-200 || echo "render-gate: corpus restore failed"
# build HEAD here and BASE_SHA in a worktree; the base binary is cached by sha in the runner's own scratch
. "$TH/bin/office-env.sh" || { echo "render-gate: office-env.sh failed"; exit 2; }
export PATH=$TH/.local/share/swiftly/toolchains/6.2.4/usr/bin:$PATH
export OFFICE_WORD_FONTS=windows OFFICE_FONT_SOURCE=bundled
EO=$(readlink -f engine)/src/out/host_release
# the base cache (binary + base scores per sha) is SHARED by every runner on the machine when /data/gate/cache exists (mode 1777); else per runner
umask 002
if [ -n "${GATE_BASECACHE:-}" ]; then BC=$GATE_BASECACHE; elif [ -d /data/gate/cache ] && [ -w /data/gate/cache ]; then BC=/data/gate/cache; else BC=$HOME/scratch/basecache; fi
BSHA=$(git rev-parse "$BASE_SHA")
# pull_request checks out the merge of the PR into the CURRENT main: its first parent is what the prebuild cached. The PR's own
# base.sha is usually older (a second build per gate). BASE_SHA stays for the path classification and the named documents.
[ "$(git rev-list --parents -n1 HEAD | wc -w)" = 3 ] && BSHA=$(git rev-parse HEAD^1)
mkdir -p "$BC"
find "$BC" -mindepth 1 -maxdepth 1 -user "$(id -u)" -mmin +240 -exec rm -rf {} + 2>/dev/null   # prune what this user wrote more than 4 h ago
touch "$BC/$BSHA.lock" 2>/dev/null; exec 8>>"$BC/$BSHA.lock"   # fd 8: one writer per base sha across runners (binary publish and score rows)

# base scores cached per (base sha, document): $BC/$BSHA/rows/<set>.{v2,v1} + REFS + tried.txt. A document the cache lacks is
# rendered once with the base binary (docx-pair --seed) and kept; the prebuild does that for the sample, so a gate renders only HEAD.
RC=$BC/$BSHA/rows
fill_rows() { fill_rows_locked; local r=$?; flock -u 8; return $r; }
fill_rows_locked() {
  mkdir -p "$RC"; touch "$RC/tried.txt"; flock 8
  sort -u "$RC/tried.txt" | comm -23 "$ids" - > "$W/missing.txt"
  [ -s "$W/missing.txt" ] || { echo "render-gate: base scores cached for all $(wc -l < "$ids") documents"; return 0; }
  echo "render-gate: rendering base for $(wc -l < "$W/missing.txt") uncached documents"
  rm -rf "$W/fill"
  SWEEP_ONLY=$W/missing.txt ENGINE_OUT=$EO STAGE=$W/fill BASE_REV=$BSHA SCORES_BASE=/nonexistent test/tools/docx-pair.sh --seed "$BASEBIN" "$BASEBIN" "$JOBS" > "$W/fill.log" 2>&1 \
    || { echo "render-gate: base fill failed (rows not cached)"; return 0; }
  if [ -s "$RC/REFS" ] && ! cmp -s "$RC/REFS" "$W/fill/fix/REFS"; then rm -f "$RC"/*.v2 "$RC"/*.v1 "$RC/tried.txt"; fi   # corpus changed: older rows are stale
  for f in "$W"/fill/fix/*.v2 "$W"/fill/fix/*.v1; do [ -f "$f" ] && cat "$f" >> "$RC/$(basename "$f")"; done
  cp "$W/fill/fix/REFS" "$RC/REFS"; cat "$W/missing.txt" >> "$RC/tried.txt"
}
T0=$(date +%s); echo "render-gate: building"
build_base() {   # builds BSHA into the shared cache once: the sha lock makes a second runner wait for the first instead of building it again
  flock 8
  if [ -x "$BC/$BSHA/release/OfficeApp" ]; then flock -u 8; return 0; fi
  git cat-file -e "$BSHA^{tree}" 2>/dev/null || { echo "render-gate: base tree ${BSHA:0:9} missing in the clone"; return 2; }
  # a stale or broken persistent worktree is dropped and made again (first prebuild: "unable to read tree")
  if { [ -d "$W/basetree/.git" ] || [ -f "$W/basetree/.git" ]; } && git -C "$W/basetree" checkout -q --detach "$BSHA" 2>/dev/null; then :
  else rm -rf "$W/basetree"; git worktree prune; git worktree add -f --detach "$W/basetree" "$BSHA" -q || { echo "render-gate: cannot check out base"; return 2; }; fi
  ln -sfn "$ENGINE_DIR" "$W/basetree/engine"
  ( cd "$W/basetree" && test/tools/build-office-fast.sh "$W/basebuild" > "$W/base-build.log" 2>&1 ) || return 1
  local BREL; BREL=$(dirname "$(ls "$W"/basebuild/*/release/OfficeApp | head -1)")
  rm -rf "$BC/$BSHA.tmp"; mkdir -p "$BC/$BSHA.tmp"; cp -a "$BREL" "$BC/$BSHA.tmp/release"
  mkdir -p "$BC/$BSHA"; rm -rf "$BC/$BSHA/release"; mv "$BC/$BSHA.tmp/release" "$BC/$BSHA/release"; rmdir "$BC/$BSHA.tmp"
  chmod -R g+rwX,o+rX "$BC/$BSHA" 2>/dev/null; flock -u 8
}
if [ ! -x "$BC/$BSHA/release/OfficeApp" ]; then
  # normally the prebuild (GATE_PREBUILD=1 render-gate.sh <sha>, after each main push) has filled the cache and this is skipped
  build_base & BPID=$!
fi
[ "${GATE_PREBUILD:-0}" = 1 ] && { [ -z "${BPID:-}" ] || wait $BPID || { echo "render-gate: BASE BUILD FAILED"; exit 1; }
  BASEBIN=$BC/$BSHA/release/OfficeApp; fill_rows; chmod -R g+rwX,o+rX "$BC/$BSHA" 2>/dev/null; echo "render-gate: base $BSHA cached"; exit 0; }
test/tools/build-office-fast.sh "$W/build" > "$W/build.log" 2>&1 || { echo "render-gate: BUILD FAILED"; tail -15 "$W/build.log" | cut -c1-200; exit 1; }
[ -z "${BPID:-}" ] || wait $BPID || { echo "render-gate: BASE BUILD FAILED"; tail -15 "$W/base-build.log" | cut -c1-200; exit 1; }
BASEBIN=$BC/$BSHA/release/OfficeApp
BIN=$(ls "$W"/build/*/release/OfficeApp 2>/dev/null | head -1); [ -x "$BIN" ] && [ -x "$BASEBIN" ] || { echo "render-gate: no binary"; exit 2; }
echo "render-gate: $(wc -l < "$ids") documents (named + sample); build step $(( $(date +%s)-T0 )) s ($([ -n "${BPID:-}" ] && echo base built here || echo base cached))"; T1=$(date +%s)
# both binaries render the same subset (SWEEP_ONLY), so the base needs no stored scores
[ "${GATE_FULL:-0}" = 1 ] || export SWEEP_ONLY=$ids
BSD=
if [ "${GATE_FULL:-0}" != 1 ]; then
  fill_rows
  flock -s 8; if [ -s "$RC/REFS" ]; then BSD=$W/bs; rm -rf "$BSD"; mkdir -p "$BSD"; cp "$RC/REFS" "$BSD/REFS"
    for f in "$RC"/*.v2 "$RC"/*.v1; do [ -f "$f" ] && awk 'NR==FNR{k[$1]=1;next} ($NF in k)' "$ids" "$f" > "$BSD/$(basename "$f")"; done; fi; flock -u 8
fi
[ -n "$BSD" ] && echo "render-gate: base scores from the cache ($BSD)"
BASE_PARTIAL=${BSD:+1} CANARY=${BSD:+0} ENGINE_OUT=$EO STAGE=$W/pair BASE_SCORES=$BSD BASE_REV=$BASE_SHA SCORES_BASE=/nonexistent test/tools/docx-pair.sh "$BASEBIN" "$BIN" "$JOBS" > "$W/pair.log" 2>&1
rc=$?; echo "render-gate: render+compare step $(( $(date +%s)-T1 )) s"
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
echo "render-gate: $NCMP sets compared; clean ($(wc -l < "$W/down.txt") approved drops)"
[ "$MODE" = full ] && [ "${GATE_BLAME:-1}" = 1 ] && { W=$W LQ=$LQ BC=$BC BASE_SHA=$BSHA EO=$EO JOBS=$JOBS timeout 1500 test/tools/render-gate-blame.sh 2>&1 | tail -5 | cut -c1-250 || true; }
exit 0
