#!/bin/bash
# test/tools/render-gate.sh BASE_SHA — the GitHub render gate (amd-8, 2026-11-20). Runs in the checkout of the PR head
# (or the merge-queue ref) on a self-hosted runner. It builds OfficeApp from this checkout into the runner's own scratch,
# renders the documents named in the commit messages (BASE_SHA..HEAD) plus the fixed sample, scores them against the
# stored base scores, and fails on any v2 drop that /data/landq/approved.txt does not cover.
# Reads (never writes) /data/landq: approved.txt, sample.txt, sample-dx2.txt and base/linux (scores + STAMP).
# Public log: only a short summary (counts and document stems), no paths or renders.
# Env: JOBS (default 44), GATE_SCRATCH (default $HOME/scratch/gate-$$), GATE_FULL=1 (no subset: the whole sets).
set -u
SELF=$(readlink -f "$0")
export RENDER_GATE=1   # a gate (and a prebuild) runs at normal priority; hand-run builds and A/B runs are niced (build-office-fast.sh, docx-pair.sh)
GS0=$(date +%s); S0=$(date +%s)   # gate start, to report the setup time before the build
BASE_SHA=${1:?usage: render-gate.sh BASE_SHA}
# merge-queue group run: the group's PR bodies (written by the workflow) stand in for PR_BODY, so ACCEPT lines in a PR body still waive (amd-8, 2026-11-23)
if [ "${GITHUB_EVENT_NAME:-}" = merge_group ] && ls "$HOME/scratch/group"/*.body >/dev/null 2>&1; then export GATE_GROUP_DIR=$HOME/scratch/group; export PR_BODY=$(cat "$GATE_GROUP_DIR"/*.body); fi
# On a pull_request run HEAD is GitHub's test merge (main tip + the PR). The event's base.sha is main as it was when the PR was
# opened, so BASE_SHA..HEAD also holds everything that landed on main since (a board-only PR then looked like code, and drops
# from other PRs were blamed on it). The PR's own change is HEAD^1..HEAD: use the merge's first parent as the base.
if [ "${GATE_PREBUILD:-0}" != 1 ] && [ "$(git rev-list --parents -n1 HEAD | wc -w)" = 3 ] && git cat-file -e "HEAD^1^{commit}" 2>/dev/null; then
  echo "render-gate: base $BASE_SHA -> merge first parent $(git rev-parse --short HEAD^1)"; BASE_SHA=$(git rev-parse HEAD^1)
fi
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
export DOC_ALARM=${DOC_ALARM:-300}   # per-document render timeout (s; was 180, raised 2026-11-23: zh-6e7ff83696dc needs 31 s of CPU alone, so a loaded runner starving it to a sixth of a core timed out a Sheets-only PR): a hung render is reported TIMEOUT, never hangs the gate
export SETS="${SETS:-756 lo xb xa xd xs sa1 sa2 dx2 drm}"   # the gate sample draws from these sets too (user focus: es-MX, pt-BR, ko, ja)
umask 002; ROOT=$PWD; JOBS=${JOBS:-44}; W=${GATE_SCRATCH:-$HOME/scratch/gate}; mkdir -p "$W"   # PERSISTENT: the warm build scratches below make the builds incremental (cold 315 s, warm ~90 s)
exec 9>"$W/lock"
# One gate (or prebuild) at a time per scratch. A prebuild only warms the scratch, so a GATE preempts it: kill the
# prebuild (by PID, with its children) and build on from wherever the scratch got to. Another gate holding the lock: wait.
if ! flock -n 9; then
  OP=; OR=; read -r OP OR < "$W/lock.owner" 2>/dev/null || true
  # A prebuild in its last steps (the build log's [a/b] counter within 3 of the end, log touched in the last 30 s) is allowed
  # to finish: killing it would throw away a nearly warm scratch (amd-perf, 2026-11-21).
  if [ -z "${GATE_PREBUILD:-}" ] && [ "$OR" = prebuild ] && [ -n "$OP" ] && kill -0 "$OP" 2>/dev/null \
     && [ $(( $(date +%s) - $(stat -c %Y "$W/build.log" 2>/dev/null || echo 0) )) -lt 30 ] \
     && tail -c 400 "$W/build.log" 2>/dev/null | grep -aoE '\[[0-9]+/[0-9]+\]' | tail -1 | tr -d '[]' | awk -F/ '{exit !($2-$1<=3)}'; then
    echo "render-gate: the scratch lock is held by a prebuild (pid $OP) in its last steps: letting it finish (up to 90 s)"
    flock -w 90 9 || true
    flock -n 9 || true
  fi
  if [ -z "${GATE_PREBUILD:-}" ] && [ "$OR" = prebuild ] && [ -n "$OP" ] && kill -0 "$OP" 2>/dev/null; then
    echo "render-gate: the scratch lock is held by a prebuild (pid $OP): stopping it"
    kill_tree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done; kill -TERM "$1" 2>/dev/null; }
    kill_tree "$OP"
  fi
  # STUCK LOCK (amd-perf, 2026-11-21): a build cancelled by the runner leaves an orphan (swiftc, 30 h old on amd-2) that inherited
  # fd 9 and holds this lock for ever; every gate on the runner then sat in `flock 9` until gate-unstick cancelled it at 25 min,
  # and its rerun hung the same way (8 gates today). When the recorded owner is dead, whoever still holds the lock file is an
  # orphan of ours (same user): kill it by PID and take the lock.
  until flock -w 60 9; do
    OP=; read -r OP _ < "$W/lock.owner" 2>/dev/null || true
    if [ -z "$OP" ] || ! kill -0 "$OP" 2>/dev/null; then
      H=$(fuser "$W/lock" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | while read -r q; do [ "$q" != "$$" ] && [ "$(ps -o ppid= -p "$q" 2>/dev/null | tr -d ' ')" = 1 ] && echo "$q"; done || true)
      [ -n "$H" ] && { echo "render-gate: the scratch lock owner (pid ${OP:-none}) is gone; stopping orphan holder(s) $(echo $H): $(ps -o args= -p ${H%%$'\n'*} | cut -c1-80)"; kill -TERM $H 2>/dev/null; sleep 3; kill -KILL $H 2>/dev/null; }
    fi
  done
fi
echo "$$ ${GATE_PREBUILD:+prebuild}" > "$W/lock.owner"; SL=$(date +%s)
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
# RE-CHECK (amd-8, 2026-11-22): the exact-base rerun after a block against a cached ancestor judges only what was blocked: GATE_RECHECK_DOCS = the Word
# documents that dropped (their stems), GATE_RECHECK_DECKS = file of the Slides decks that were blocked (see the two rerun lines below).
[ -n "${GATE_RECHECK_DOCS:-}" ] && { printf '%s\n' $GATE_RECHECK_DOCS | sort -u > "$ids"; echo "render-gate: re-check of $(wc -l < "$ids") dropped document(s) only"; }
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
SR=$(date +%s); test/tools/corpus-cache.sh restore 2>&1 | tail -3 | cut -c1-200 || echo "render-gate: corpus restore failed"; ER=$(date +%s)
# build HEAD here and BASE_SHA in a worktree; the base binary is cached by sha in the runner's own scratch
. "$TH/bin/office-env.sh" || { echo "render-gate: office-env.sh failed"; exit 2; }
export PATH=$TH/.local/share/swiftly/toolchains/6.2.4/usr/bin:$PATH
export OFFICE_WORD_FONTS=windows OFFICE_FONT_SOURCE=bundled OFFICE_NOW=${OFFICE_NOW:-2026-10-30T12:00:00}   # one fixed clock for base and PR draws
EO=$(readlink -f engine)/src/out/host_release
# the base cache (binary + base scores per sha) is SHARED by every runner on the machine when /data/gate/cache exists (mode 2775, group gatecache, setgid: NOT world-writable or sticky, which makes the kernel refuse another user's lock files (fs.protected_regular)); else per runner
umask 002
if [ -n "${GATE_BASECACHE:-}" ]; then BC=$GATE_BASECACHE; elif [ -d /data/gate/cache ] && [ -w /data/gate/cache ]; then BC=/data/gate/cache; else BC=$HOME/scratch/basecache; fi
# The cache is keyed by the ENGINE commit too (amd-8, 2026-11-22): a base rendered on the old engine must never be compared with a PR rendered on the new one.
# (amd-8, 2026-11-22) safe.directory: the engine checkout belongs to another user, so a plain git refused ("dubious ownership") and every runner keyed its cache "eng-noengine".
ENGSTAMP=$(git -c safe.directory='*' -C "$ENGINE_DIR" rev-parse --short=10 HEAD 2>/dev/null || echo noengine); BC=$BC/eng-$ENGSTAMP
BSHA=$(git rev-parse "$BASE_SHA")
# pull_request checks out the merge of the PR into the CURRENT main: its first parent is what the prebuild cached. The PR's own
# base.sha is usually older (a second build per gate). BASE_SHA stays for the path classification and the named documents.
[ "$(git rev-list --parents -n1 HEAD | wc -w)" = 3 ] && BSHA=$(git rev-parse HEAD^1)
# BASE MISS (amd-perf, 2026-11-21): main moves about once a minute and a prebuild takes minutes, so the exact base is often not
# built yet (a 330 s base build inside the gate). Score against the newest CACHED ancestor instead; only if a document drops
# against it is the exact base built and the gate rerun (GATE_EXACT_BASE=1), so a drop that came from main in between is not
# blamed on the PR. Accepted blind spot: a main commit in between that improved a document the PR then undoes (hourly rounds).
EXACTB=
# amd-8, 2026-11-23: OFF by default (starling-bd): the gate builds and renders the real base (one builder per sha, the others wait on the lock) instead of scoring against an older ancestor,
# which hid a PR's effect of whatever main changed in between. GATE_ANCESTOR_FALLBACK=1 brings the old behaviour back.
if [ "${GATE_ANCESTOR_FALLBACK:-0}" = 1 ] && [ "${GATE_PREBUILD:-0}" != 1 ] && [ "${GATE_EXACT_BASE:-0}" != 1 ] && [ ! -x "$BC/$BSHA/release/OfficeApp" ]; then
  for a in $(git rev-list --max-count=150 "$BSHA" 2>/dev/null | tail -n +2); do
    if [ -x "$BC/$a/release/OfficeApp" ]; then EXACTB=$BSHA; BSHA=$a; echo "render-gate: base ${EXACTB:0:9} not cached; scoring against the cached ancestor ${a:0:9}"; break; fi
  done
fi
mkdir -p "$BC"; chmod 2775 "$BC" 2>/dev/null
find "$BC" -mindepth 1 -maxdepth 1 -user "$(id -u)" -mmin +240 -exec rm -rf {} + 2>/dev/null   # prune what this user wrote more than 4 h ago
touch "$BC/$BSHA.lock" 2>/dev/null; chmod g+w "$BC/$BSHA.lock" 2>/dev/null; exec 8>>"$BC/$BSHA.lock" || exec 8>>"$BC/$BSHA.$(id -u).lock"   # a lock another runner user made without group write (run 44992081171: Permission denied, exit 1) falls back to a lock of our own   # fd 8: one writer per base sha across runners (binary publish and score rows)

# base scores cached per (base sha, document): $BC/$BSHA/rows/<set>.{v2,v1} + REFS + tried.txt. A document the cache lacks is
# rendered once with the base binary (docx-pair --seed) and kept; the prebuild does that for the sample, so a gate renders only HEAD.
RC=$BC/$BSHA/rows
fill_rows() { fill_rows_locked; local r=$?; flock -u 8; return $r; }
fill_rows_locked() {
  mkdir -p "$RC"; flock 8
  # STAMP (amd-8, 2026-11-25): rows are reused only if drawn with THIS base binary and THESE scorer files; otherwise redrawn.
  RSTAMP=$(test/tools/gate-stamp.sh rows "$BASEBIN" 2>/dev/null)
  if [ -n "$RSTAMP" ] && [ "$(cat "$RC/STAMP" 2>/dev/null)" != "$RSTAMP" ]; then echo "render-gate: base rows have no matching stamp (binary/scorer differ); redrawing"; rm -f "$RC"/*.v2 "$RC"/*.v1 "$RC/tried.txt" "$RC/REFS" "$RC/STAMP"; fi
  touch "$RC/tried.txt"
  sort -u "$RC/tried.txt" | comm -23 "$ids" - > "$W/missing.txt"
  [ -s "$W/missing.txt" ] || { echo "render-gate: base scores cached for all $(wc -l < "$ids") documents"; return 0; }
  echo "render-gate: rendering base for $(wc -l < "$W/missing.txt") uncached documents"
  rm -rf "$W/fill"
  SWEEP_ONLY=$W/missing.txt ENGINE_OUT=$EO STAGE=$W/fill BASE_REV=$BSHA SCORES_BASE=/nonexistent test/tools/docx-pair.sh --seed "$BASEBIN" "$BASEBIN" "$JOBS" > "$W/fill.log" 2>&1 \
    || { echo "render-gate: base fill failed (rows not cached)"; return 0; }
  if [ -s "$RC/REFS" ] && ! cmp -s "$RC/REFS" "$W/fill/fix/REFS"; then rm -f "$RC"/*.v2 "$RC"/*.v1 "$RC/tried.txt"; fi   # corpus changed: older rows are stale
  for f in "$W"/fill/fix/*.v2 "$W"/fill/fix/*.v1; do [ -f "$f" ] && cat "$f" >> "$RC/$(basename "$f")"; done
  cp "$W/fill/fix/REFS" "$RC/REFS"; cat "$W/missing.txt" >> "$RC/tried.txt"
  [ -z "$RSTAMP" ] || echo "$RSTAMP" > "$RC/STAMP"
}
T0=$(date +%s); echo "render-gate: setup before the build $(( T0-S0 )) s (lock wait $(( SL-S0 )) s, corpus restore $(( ER-SR )) s)"; echo "render-gate: building"
build_base() {   # builds BSHA into the shared cache once: the sha lock makes a second runner wait for the first instead of building it again
  flock 8
  if [ -x "$BC/$BSHA/release/OfficeApp" ]; then flock -u 8; return 0; fi
  # SEED (amd-8, 2026-11-24, starling-bd): a gate that PASSED kept its PR-side products under $BC/tree-<git tree of its HEAD>; main's new tip has that same
  # tree when amd-10 pushes the gated batch, so its base (binary + Slides results) is taken from there instead of being built and drawn again.
  # A pushed tree that differs from the gated one finds nothing and is built as before. Hard links: cache entries are never edited in place.
  local BT; BT=$(git rev-parse "$BSHA^{tree}" 2>/dev/null)
  if [ "${GATE_SEED:-1}" != 0 ] && [ -n "$BT" ] && [ -x "$BC/tree-$BT/release/OfficeApp" ]; then
    rm -rf "$BC/$BSHA.tmp"; mkdir -p "$BC/$BSHA.tmp" && cp -al "$BC/tree-$BT/release" "$BC/$BSHA.tmp/release" || return 1
    [ -s "$BC/tree-$BT/slides/combined.tsv" ] && [ ! -s "$BC/$BSHA/slides/combined.tsv" ] && cp -al "$BC/tree-$BT/slides" "$BC/$BSHA.tmp/slides"
    mkdir -p "$BC/$BSHA"; rm -rf "$BC/$BSHA/release"; mv "$BC/$BSHA.tmp/release" "$BC/$BSHA/release"
    [ -d "$BC/$BSHA.tmp/slides" ] && { rm -rf "$BC/$BSHA/slides"; mv "$BC/$BSHA.tmp/slides" "$BC/$BSHA/slides"; }
    rm -rf "$BC/$BSHA.tmp"; chmod -R g+rwX,o+rX "$BC/$BSHA" 2>/dev/null; flock -u 8
    echo "render-gate: base ${BSHA:0:9} SEEDED from the passing gate of the same tree ${BT:0:9} (no base build, Slides base $([ -s "$BC/$BSHA/slides/combined.tsv" ] && echo cached || echo not seeded))"; return 0
  fi
  git cat-file -e "$BSHA^{tree}" 2>/dev/null || { echo "render-gate: base tree ${BSHA:0:9} missing in the clone"; return 2; }
  # a stale or broken persistent worktree is dropped and made again (first prebuild: "unable to read tree")
  if { [ -d "$W/basetree/.git" ] || [ -f "$W/basetree/.git" ]; } && git -C "$W/basetree" checkout -q --detach "$BSHA" 2>/dev/null; then :
  else rm -rf "$W/basetree"; git worktree prune; git worktree add -f --detach "$W/basetree" "$BSHA" -q || { echo "render-gate: cannot check out base"; return 2; }; fi
  ln -sfn "$ENGINE_DIR" "$W/basetree/engine"
  ( cd "$W/basetree" && $( [ -x "$HOME/bin/build-slot.sh" ] && echo "$HOME/bin/build-slot.sh" ) test/tools/build-office-fast.sh "$W/basebuild" > "$W/base-build.log" 2>&1 ) || return 1
  local BREL; BREL=$(dirname "$(ls "$W"/basebuild/*/release/OfficeApp | head -1)")
  rm -rf "$BC/$BSHA.tmp"; mkdir -p "$BC/$BSHA.tmp"; cp -a "$BREL" "$BC/$BSHA.tmp/release"
  mkdir -p "$BC/$BSHA"; rm -rf "$BC/$BSHA/release"; mv "$BC/$BSHA.tmp/release" "$BC/$BSHA/release"; rmdir "$BC/$BSHA.tmp"
  chmod -R g+rwX,o+rX "$BC/$BSHA" 2>/dev/null; flock -u 8
}
if [ ! -x "$BC/$BSHA/release/OfficeApp" ] && [ "${GATE_WARM:-0}" != 1 ] && [ "${GATE_LIGHT:-0}" != 1 ]; then   # GATE_WARM=1 (gate-warm.sh): warm the PR scratch only, no base
  # normally the prebuild (GATE_PREBUILD=1 render-gate.sh <sha>, after each main push) has filled the cache and this is skipped
  # (amd-8, 2026-11-23, design D of amd-opus) base FIRST, then the PR: two wide builds at once on a loaded box (-j 30 each) made the 1302 s and 1689 s gate builds
  build_base & BPID=$!; wait $BPID; BRC=$?
fi
# base cached: render+score the uncached base documents WHILE the PR builds (the base pass needs only the base binary; the
# build is mostly one thread, so the two overlap). Measured 2026-11-20: the base pass ran after the build and took ~3-4 min.
FPID=
if [ -z "${BPID:-}" ] && [ "${GATE_LIGHT:-0}" != 1 ] && [ "${GATE_WORD:-1}" = 1 ]; then BASEBIN=$BC/$BSHA/release/OfficeApp; ( fill_rows ) > "$W/fillrows.out" 2>&1 & FPID=$!; fi
PREV=$(cat "$W/build.rev" 2>/dev/null); TB=$(date +%s)
$( [ -x "$HOME/bin/build-slot.sh" ] && echo "$HOME/bin/build-slot.sh" ) test/tools/build-office-fast.sh "$W/build" > "$W/build.log" 2>&1 || { echo "render-gate: BUILD FAILED"; tail -15 "$W/build.log" | cut -c1-200; exit 1; }
echo "render-gate: PR build $(( $(date +%s)-TB )) s, load $(cut -d" " -f1-3 /proc/loadavg), -j ${BUILD_JOBS:-default}; compiled: $(grep -aoE "[A-Za-z0-9+_]+\.swift" "$W/build.log" | sort -u | head -12 | tr "\n" " ")"   # the build alone; "build step" below also waits for the base rows/base build
# LIGHT (the pull_request run under a merge queue, amd-8, 2026-11-23): the PR builds, nothing renders; the full render runs once per merge_group
if [ "${GATE_LIGHT:-0}" = 1 ]; then echo "render-gate: light run: the PR builds; the full render runs in the merge queue's group run"; exit 0; fi
# Slides step (full gate), started the moment the PR binary links (2026-11-22, amd-perf): it needs only that binary, so it no longer waits for the base build/base rows; it runs alongside them and the Word pair. every deck drawn by the PR binary, deck means vs baseline-win.tsv (test/tools/slides-gate.sh, ~80 s), run
# alongside the Word pair (different documents). Skipped when the change is Word-reader-only (Docx.swift, WordWindowsFaces.swift):
# shared text/layout code (OfficeText, Slides, sdk, build files) still runs it.
SLPID=""
if [ "$MODE" = full ] && [ "${GATE_SLIDES:-1}" = 1 ] && [ "${GATE_PREBUILD:-0}" != 1 ]; then
  SHO=$(echo "$CH" | xargs python3 test/tools/sheets-only.py 2>/dev/null); [ -n "$SHO" ] || SHO=/nonexistent   # Sheets files only the Sheets path uses (test/tools/sheets-only.py)
  if [ -n "${CH:-}" ] && ! echo "$CH" | grep -vE '^(docs/|test/(tools|corpus)/|apps/[A-Za-z]+/Tests/|apps/OfficeApp/Sources/OfficeApp/Docx\.swift$|apps/OfficeApp/Sources/(OfficeApp|OfficeText)/WordWindowsFaces\.swift$)' | grep -vxF "$SHO" | grep -q .; then
    echo "render-gate: Slides step skipped (change touches only Word-reader, Sheets-only, docs or test-tool files)"
  else
    SLIDES_ONLY=${GATE_RECHECK_DECKS:-} LQ=$LQ BASE_BIN=$BC/$BSHA/release/OfficeApp BASE_CACHE=$BC/$BSHA/slides test/tools/slides-gate.sh "$(ls "$W"/build/*/release/OfficeApp | head -1)" "${JOBS:-32}" > "$W/slides.out" 2>&1 & SLPID=$!
  fi
fi
# Sheets PDF determinism (2026-11-24, amd-8): three books printed three times each in fresh processes must give the same bytes (a paint loop over a
# Dictionary reseeds per process and made the gate noisy). About 20 s; GATE_DETERMINISM=0 skips it.
if [ "$MODE" = full ] && [ "${GATE_DETERMINISM:-1}" = 1 ] && [ "${GATE_PREBUILD:-0}" != 1 ]; then
  OFFICE_APP=$(ls "$W"/build/*/release/OfficeApp | head -1) test/sheet-pdf-determinism.sh > "$W/determinism.out" 2>&1 || { echo "render-gate: Sheets PDF determinism FAILED (same book, different bytes run to run; sort what a paint loop walks):"; grep -E "DIFF|FAIL" "$W/determinism.out" | head -5; exit 1; }
  echo "render-gate: Sheets PDF determinism ok"
fi
[ "${GATE_PREBUILD:-0}" = 1 ] && { echo "render-gate: PR build alone $(( $(date +%s)-TB )) s; changed since this scratch's last build: $( [ -n "$PREV" ] && git diff --name-only "$PREV" HEAD 2>/dev/null | wc -l || echo unknown) files (prev ${PREV:0:9})"; git rev-parse HEAD > "$W/build.rev"; [ "${GATE_WARM:-0}" = 1 ] && { echo "render-gate: scratch warm on $(git rev-parse --short HEAD)"; exit 0; }
[ -z "${BPID:-}" ] || [ "${BRC:-0}" = 0 ] || { echo "render-gate: BASE BUILD FAILED"; exit 1; }
  BASEBIN=$BC/$BSHA/release/OfficeApp; [ "${GATE_WORD:-1}" != 1 ] || fill_rows; chmod -R g+rwX,o+rX "$BC/$BSHA" 2>/dev/null; echo "render-gate: base $BSHA cached"
  # the Slides BASE render too (amd-8, 2026-11-22): the same sweep the PR gate would otherwise draw for its base, cached per main sha + engine, so the PR gate draws only its own side
  if [ "${GATE_SLIDES:-1}" = 1 ] && [ "${GATE_WARM:-0}" != 1 ] && [ -x "$BASEBIN" ]; then
    S0=$(date +%s); BASE_ONLY=1 LQ=$LQ BASE_BIN=$BASEBIN BASE_CACHE=$BC/$BSHA/slides test/tools/slides-gate.sh "$BASEBIN" "${JOBS:-32}" > "$W/slides-base.out" 2>&1; echo "render-gate: slides base $BSHA rendered in $(( $(date +%s)-S0 )) s ($(tail -1 "$W/slides-base.out" | cut -c1-120))"
    chmod -R g+rwX,o+rX "$BC/$BSHA" 2>/dev/null
  fi
  # the Sheets BASE too (amd-8, 2026-11-23, coordinator): sheets-gate.sh BASE_ONLY writes $BC/$BSHA/sheets/per-book.tsv, so a PR gate never draws it (only 9 of 14 cached shas had it)
  if [ "${GATE_SHEETS:-1}" = 1 ] && [ "${GATE_WARM:-0}" != 1 ] && [ -x "$BASEBIN" ]; then
    BASE_ONLY=1 LQ=$LQ test/tools/sheets-gate.sh "$BASEBIN" "$BASEBIN" "$BC/$BSHA/sheets" "${JOBS:-32}" > "$W/sheets-base.out" 2>&1; echo "render-gate: sheets base $BSHA: $(tail -1 "$W/sheets-base.out" | cut -c1-120)"
    chmod -R g+rwX,o+rX "$BC/$BSHA" 2>/dev/null
  fi
  exit 0; }
[ -z "${BPID:-}" ] || [ "${BRC:-0}" = 0 ] || { echo "render-gate: BASE BUILD FAILED"; tail -15 "$W/base-build.log" | cut -c1-200; exit 1; }
BASEBIN=$BC/$BSHA/release/OfficeApp
[ -z "$FPID" ] || { wait $FPID; cat "$W/fillrows.out"; echo "render-gate: base rows ready at $(( $(date +%s)-T0 )) s"; }
BIN=$(ls "$W"/build/*/release/OfficeApp 2>/dev/null | head -1); [ -x "$BIN" ] && [ -x "$BASEBIN" ] || { echo "render-gate: no binary"; exit 2; }
echo "render-gate: files compiled: PR $(grep -o "[A-Za-z0-9+_]*\.swift" "$W/build.log" | sort -u | wc -l), base $(grep -o "[A-Za-z0-9+_]*\.swift" "$W/base-build.log" 2>/dev/null | sort -u | wc -l) (a cold build lists ~210)"
echo "render-gate: $(wc -l < "$ids") documents (named + sample); build step $(( $(date +%s)-T0 )) s ($([ -n "${BPID:-}" ] && echo base built here || echo base cached))"; T1=$(date +%s)
# both binaries render the same subset (SWEEP_ONLY), so the base needs no stored scores
[ "${GATE_FULL:-0}" = 1 ] || export SWEEP_ONLY=$ids
# GATE_WORD=0 (amd-8, 2026-11-27, LANDING-RULES "Faster pre-land checks"): the Word step is skipped; ~/bin/gate-scope sets it only for a batch whose
# changed files the Word path cannot reach (Slides-only or Sheets-only files, the web build); the Slides and Sheets steps below still run.
BSD=; DN=0; DROPS=""; NCMP=0
if [ "${GATE_WORD:-1}" != 1 ]; then echo "render-gate: Word step skipped (GATE_WORD=0)"; : > "$W/down.txt"; else
if [ "${GATE_FULL:-0}" != 1 ]; then
  [ -n "$FPID" ] || fill_rows
  flock -s 8; if [ -s "$RC/REFS" ]; then BSD=$W/bs; rm -rf "$BSD"; mkdir -p "$BSD"; cp "$RC/REFS" "$BSD/REFS"
    for f in "$RC"/*.v2 "$RC"/*.v1; do [ -f "$f" ] && awk 'NR==FNR{k[$1]=1;next} ($NF in k)' "$ids" "$f" > "$BSD/$(basename "$f")"; done; fi; flock -u 8
fi
[ -n "$BSD" ] && echo "render-gate: base scores from the cache ($BSD)"
BASE_PARTIAL=${BSD:+1} CANARY=${BSD:+0} ENGINE_OUT=$EO STAGE=$W/pair BASE_SCORES=$BSD BASE_REV=$BASE_SHA SCORES_BASE=/nonexistent test/tools/docx-pair.sh "$BASEBIN" "$BIN" "$JOBS" > "$W/pair.log" 2>&1
rc=$?; echo "render-gate: render+compare step $(( $(date +%s)-T1 )) s"
if [ $rc != 0 ]; then echo "render-gate: pair failed (exit $rc)"; grep -aE "ABORT|failed|no engine" "$W/pair.log" | head -5 | cut -c1-200; exit 1; fi
# a document whose render timed out (DOC_ALARM s) or crashed is not scored: name it and fail, never hang or pass silently
TO=$(grep -aE '^(TIMEOUT|RENDER-FAIL) ' "$W/pair.log" | sort -u | head -20 | sed 's/ (not scored)//')
if [ -n "$TO" ]; then echo "render-gate: FAILED, render timed out (over ${DOC_ALARM} s) or crashed for:"; echo "$TO" | sed 's/^/  /'; exit 1; fi
# a gate that compared nothing must not pass
NCMP=$(awk '/^== /{v2=($0 ~ / v2$/)} v2 && /^NEW: [1-9]/{n++} END{print n+0}' "$W/pair.log")
[ "$NCMP" -gt 0 ] || { echo "render-gate: nothing was compared (see runner log)"; exit 1; }
DN=$(awk '/^== /{v2=($0 ~ / v2$/)} v2 && /^up .* down [1-9]/{n++} END{print n+0}' "$W/pair.log")
# v2 drops: lines "  DOWN <stem> ..." inside "== <set> v2" sections
awk '/^== /{v2=($0 ~ / v2$/)} v2 && /^ *DOWN /{print}' "$W/pair.log" > "$W/down.txt"
DROPS=""
# a waiver holds only for the PR that names the doc in its PR body (PR_BODY env) or a commit message (amd-8, 2026-11-22): approved.txt is permanent
# a re-run replays the ORIGINAL event payload, so PR_BODY can be stale: read the current body through the API when a PR number is known (fall back to PR_BODY)
if [ -n "${PR_NUMBER:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] && command -v gh >/dev/null 2>&1; then
  CUR_BODY=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" --jq .body 2>/dev/null || true); [ -n "$CUR_BODY" ] && PR_BODY=$CUR_BODY
fi
MSGS="${PR_BODY:-}"$'\n'$(git -C "$ROOT" log --format=%B "$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null || echo HEAD)..HEAD" 2>/dev/null || true)
while read -r line; do
  stem=${line##* }; s=$(basename "${stem%.docx}")
  if grep -qE "^${s}([ .]|$)" "$LQ/approved.txt" 2>/dev/null && case "$MSGS" in *"$s"*) true;; *) false;; esac; then :; else DROPS="$DROPS $s"; fi
done < "$W/down.txt"
# the rerun re-renders only what was blocked: the Word drops, and the Slides decks that were blocked in this same pass (the Slides step is waited for, not killed;
# a Slides step that passed is not run again). GATE_RECHECK_DOCS and GATE_RECHECK_DECKS are not inherited from an earlier re-check (a re-check never re-checks).
RECHK() { dk=""; src=0; if [ -n "${SLPID:-}" ]; then wait "$SLPID"; src=$?; if [ "$src" = 1 ]; then dk=$W/recheck-decks.txt; sed -n 's/^slides-gate: BLOCKED-DECK //p' "$W/slides.out" | sort -u > "$dk"; [ -s "$dk" ] || dk=""; fi; fi
  echo "render-gate: re-check: Slides $([ -z "${SLPID:-}" ] && echo "not run" || { [ "$src" != 1 ] && echo "clean, not run again" || { [ -n "$dk" ] && echo "$(wc -l < "$dk") blocked deck(s) only" || echo "blocked, no decks named: all"; }; })"
  exec env GATE_RECHECK_DOCS="$1" GATE_RECHECK_DECKS="$dk" GATE_SLIDES=$([ "$src" = 1 ] && echo 1 || echo 0) GATE_EXACT_BASE=1 "$SELF" "$BASE_SHA"; }
if [ -n "$DROPS" ] && [ -n "$EXACTB" ]; then echo "render-gate: drops against the cached ancestor ($DROPS ); rerunning against the exact base"; RECHK "$(echo $DROPS)"; fi
if [ -n "$DROPS" ]; then
  # (amd-8, 2026-11-23, #2426: a block that printed no numbers could not be checked) every blocking doc with its v2 before/after and line counts, and the base it was compared with
  echo "render-gate: v2 drops (base ${BSHA:0:9}$([ -n "$EXACTB" ] && echo ", the cached ancestor of ${EXACTB:0:9}" || echo ", exact") binary $BC/$BSHA/release/OfficeApp; each line is the pair's own: v2 base -> PR, lines matched/total):"
  for d in $DROPS; do grep -hE "(^| |/)${d}([ .]|$)" "$W/down.txt" | head -2 | cut -c1-220 | sed 's/^/render-gate:   /'; grep -hE "(^| |/)${d}([ .]|$)" "$W"/pair.log 2>/dev/null | grep -vE '^ *DOWN' | head -2 | cut -c1-220 | sed 's/^/render-gate:   pair: /'; done
  if [ -n "${GATE_GROUP_DIR:-}" ] && ls "$GATE_GROUP_DIR"/*.body >/dev/null 2>&1; then
    echo "render-gate: this is a merge-queue group of PRs: $(ls "$GATE_GROUP_DIR" | sed -n 's/\.body$//p' | tr '\n' ' ')"
    for d in $DROPS; do echo "render-gate:   $d: PR(s) whose commit or body names it: $(for f in "$GATE_GROUP_DIR"/*.body; do grep -qF "$d" "$f" && basename "$f" .body; done | tr '\n' ' ')(none named: any PR of the group; the queue removes the failing one and retries the rest)"; done
  fi
  echo "render-gate: BLOCKED, v2 drops not approved:$DROPS"; exit 1; fi
[ "$DN" = 0 ] || [ -s "$W/down.txt" ] || { echo "render-gate: drops reported but not parsed"; exit 1; }
fi   # GATE_WORD
# Slides step result (started before the Word pair, see SLPID): block on decks worse than the BASE render (same runner and engine; the fixed baselines are the drift report only)
if [ -n "${SLPID:-}" ]; then
  wait "$SLPID"; src=$?; tail -20 "$W/slides.out"
  # the Slides base was the newest cached ANCESTOR (EXACTB set): decks other PRs changed on main since are charged to this PR, so rerun against the exact base like the Word drops above (amd-8, 2026-11-22: 3 PRs blocked on eb013aed/3f8a480a)
  [ "$src" = 1 ] && [ -n "$EXACTB" ] && [ -z "${GATE_RECHECK_DECKS:-}" ] && { echo "render-gate: Slides decks worse against the cached ancestor; rerunning against the exact base ${EXACTB:0:9}, only the blocked decks"; dk=$W/recheck-decks.txt; sed -n 's/^slides-gate: BLOCKED-DECK //p' "$W/slides.out" | sort -u > "$dk"; [ -s "$dk" ] || dk=""; exec env GATE_RECHECK_DECKS="$dk" GATE_EXACT_BASE=1 "$SELF" "$BASE_SHA"; }
  [ "$src" = 1 ] && { echo "render-gate: BLOCKED, Slides decks worse than the base (above)"; exit 1; }
fi
# Sheets step (amd-8, 2026-11-22): every workbook Excel printed, drawn by the PR binary and by the base (base cached per main sha in $BC/$BSHA/sheets),
# compared per book on pixels and text lines (test/tools/sheets-gate.sh, ~40 s a side). GATE_SHEETS=0 turns it off. Skipped for Word-reader-only changes, as Slides.
if [ "$MODE" = full ] && [ "${GATE_SHEETS:-1}" = 1 ] && [ "${GATE_PREBUILD:-0}" != 1 ] && ! { [ -n "${CH:-}" ] && ! echo "$CH" | grep -vE '^(docs/|test/(tools|corpus)/|apps/[A-Za-z]+/Tests/|apps/OfficeApp/Sources/OfficeApp/Docx\.swift$|apps/OfficeApp/Sources/(OfficeApp|OfficeText)/WordWindowsFaces\.swift$)' | grep -q .; }; then
  LQ=$LQ test/tools/sheets-gate.sh "$BIN" "$BASEBIN" "$BC/$BSHA/sheets" "${JOBS:-32}" > "$W/sheets.out" 2>&1; shrc=$?; tail -8 "$W/sheets.out" | cut -c1-200
  [ "$shrc" = 1 ] && { echo "render-gate: BLOCKED, Sheets books worse than the base (above)"; exit 1; }
fi
echo "render-gate: BASE-CACHE word=$([ -n "$BSD" ] && echo cache || echo own) slides=$(if grep -qs "base render from the cache" "$W/slides.out"; then echo cache; elif [ -s "$W/slides-base.out" ]; then echo own; else echo none; fi)"
echo "render-gate: total $(( $(date +%s)-GS0 )) s before the blame step"
# SEED the next base (see build_base): only a whole PASSED full gate, never a prebuild, a light/warm run or a recheck of some decks.
if [ "$MODE" = full ] && [ "${GATE_SEED:-1}" != 0 ] && [ "${GATE_PREBUILD:-0}" != 1 ] && [ "${GATE_LIGHT:-0}" != 1 ] && [ "${GATE_WARM:-0}" != 1 ] && [ -z "${GATE_RECHECK_DECKS:-}" ] && [ -z "${EXACTB:-}" ]; then
  ST=$(git rev-parse "HEAD^{tree}" 2>/dev/null); SBIN=$(ls "$W"/build/*/release/OfficeApp 2>/dev/null | head -1); SD=$BC/tree-$ST
  if [ -n "$ST" ] && [ -x "$SBIN" ] && [ ! -x "$SD/release/OfficeApp" ]; then
    rm -rf "$SD.tmp$$"; mkdir -p "$SD.tmp$$" && cp -a "$(dirname "$SBIN")" "$SD.tmp$$/release" \
      && { [ -s "$W/slides/seed/combined.tsv" ] && cp -a "$W/slides/seed" "$SD.tmp$$/slides"; :; } \
      && { chmod -R g+rwX,o+rX "$SD.tmp$$" 2>/dev/null; mv "$SD.tmp$$" "$SD" 2>/dev/null || rm -rf "$SD.tmp$$"; } \
      && echo "render-gate: seeded tree-${ST:0:9} for the next base ($([ -s "$SD/slides/combined.tsv" ] && echo "binary + Slides" || echo "binary only"))"
  fi
fi
echo "render-gate: $NCMP sets compared; clean ($(wc -l < "$W/down.txt") approved drops)"
[ "$MODE" = full ] && [ "${GATE_BLAME:-1}" = 1 ] && [ "${GATE_WORD:-1}" = 1 ] && { W=$W LQ=$LQ BC=$BC BASE_SHA=$BSHA EO=$EO JOBS=$JOBS timeout 1500 test/tools/render-gate-blame.sh 2>&1 | tail -5 | cut -c1-250 || true; }
exit 0
