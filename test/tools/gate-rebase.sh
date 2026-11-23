#!/bin/bash
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
# gate-rebase.sh — run in the persistent clone after the checkout of a pull_request merge commit, BEFORE render-gate.sh
# (amd-8, 2026-11-23, starling-bd: gate runs took 40-50 min because main moves every few minutes, so the merge's first parent
# (the base) was almost never cached and every run built and rendered a fresh base).
# If the base (HEAD^1) is not in the shared cache, find the newest ANCESTOR that is, and re-make the test merge on top of it:
# HEAD := merge(that ancestor, the PR's own head). The gate then compares exactly the PR's change against a cached base. What
# the PR meets from main commits newer than that ancestor is not tested here (the hourly rounds bisect any drop to its PR).
# Nothing cached within GATE_REBASE_MAX commits, a merge conflict or a missing object: the clone is left as it was (exact base).
# The whole body is one braces block: the checkout below replaces files of this very script, and bash must have read it all first.
{
  [ "${GATE_REBASE:-1}" = 1 ] || exit 0
  [ "$(git rev-list --parents -n1 HEAD | wc -w)" = 3 ] || exit 0
  : "${ENGINE_DIR:?}"
  EN=$(git -c safe.directory='*' -C "$ENGINE_DIR" rev-parse --short=10 HEAD 2>/dev/null) || exit 0
  if [ -n "${GATE_BASECACHE:-}" ]; then BC=$GATE_BASECACHE; elif [ -d /data/gate/cache ]; then BC=/data/gate/cache; else exit 0; fi
  BC=$BC/eng-$EN
  OLD=$(git rev-parse HEAD); B=$(git rev-parse HEAD^1); P=$(git rev-parse HEAD^2)
  # complete = binary AND the Slides base render (a base with a binary only makes every gate draw ~1300 decks again: 1629 s in run 45233932130)
  full() { [ -x "$BC/$1/release/OfficeApp" ] && [ -s "$BC/$1/slides/combined.tsv" ]; }
  if full "$B"; then echo "gate-rebase: base ${B:0:9} is fully cached"; exit 0; fi
  if [ -x "$BC/$B/release/OfficeApp" ] && ! git rev-list --max-count="${GATE_REBASE_MAX:-60}" "$B" | tail -n +2 | while read -r a; do full "$a" && echo y && break; done | grep -q y; then echo "gate-rebase: base ${B:0:9} is cached"; exit 0; fi
  A=
  for a in $(git rev-list --max-count="${GATE_REBASE_MAX:-60}" "$B" | tail -n +2); do
    full "$a" && { A=$a; break; }
  done
  if [ -z "$A" ]; then for a in $(git rev-list --max-count="${GATE_REBASE_MAX:-60}" "$B" | tail -n +2); do [ -x "$BC/$a/release/OfficeApp" ] && { A=$a; break; }; done; fi
  [ -n "$A" ] || { echo "gate-rebase: no cached ancestor of ${B:0:9} within ${GATE_REBASE_MAX:-60} commits; exact base"; exit 0; }
  G="-c user.name=render-gate -c user.email=render-gate@localhost"
  if git checkout -q --detach "$A" 2>/dev/null && git $G merge -q --no-edit --no-ff -m "render-gate test merge of ${P:0:9} onto ${A:0:9}" "$P" >/dev/null 2>&1; then
    echo "gate-rebase: base ${B:0:9} not cached; test merge remade on the cached ancestor ${A:0:9} ($(git rev-list --count "$A..$B") main commits older)"
  else
    git merge --abort 2>/dev/null; git checkout -q -f --detach "$OLD"; git clean -fdq
    echo "gate-rebase: cannot merge ${P:0:9} onto ${A:0:9}; exact base"
  fi
  exit 0
}
