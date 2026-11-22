#!/bin/bash
# gate-warm.sh SHA — keep this runner's PR build scratch warm on current main (amd-8, 2026-11-22, amd-perf's idea).
# Run detached at the end of every gate job ON THE RUNNER, by the runner's own user. A PR gate compiles what changed since
# THIS scratch was last built; after another PR's gate that is the other PR's files plus every main merge since. Building
# main here while the runner is idle leaves a PR only its own diff to compile (amd-perf: the PR build is 65% of a gate).
# It is the prebuild's PR-build step alone (GATE_PREBUILD=1 GATE_WARM=1: no base build, no rows), under the scratch lock
# as a "prebuild", so a starting gate kills it (render-gate.sh) and builds on from wherever it got to.
# The workflow's clone step also kills a running warm (pid in $W/warm.pid) before it checks out the PR.
SHA=${1:?sha}; C=$HOME/clone; W=${GATE_SCRATCH:-$HOME/scratch/gate}; mkdir -p "$W"
echo $$ > "$W/warm.pid"
cd "$C" || exit 1
git checkout -q -f --detach "$SHA" 2>/dev/null && git clean -fdq || exit 1
export JOBS=${GATE_JOBS:-$(cat "$HOME/.gate-jobs" 2>/dev/null || nproc)}; export BUILD_JOBS=$(( JOBS / 2 )); [ "$BUILD_JOBS" -lt 30 ] && BUILD_JOBS=30
[ "$JOBS" -gt 170 ] && JOBS=170
GATE_PREBUILD=1 GATE_WARM=1 nice -n 10 test/tools/render-gate.sh "$SHA" > "$W/warm.log" 2>&1
rm -f "$W/warm.pid"
