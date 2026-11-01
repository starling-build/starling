#!/bin/bash
# test/tools/stamp.sh [-r REV] PATH… — the STAMP of a set of inputs: one line per
# path with its git tree/blob hash (as of REV, or as the WORKING TREE when no -r is
# given, so a fix can be stamped before it is committed and the stamp equals what
# `git rev-parse HEAD:PATH` says after), then the engine's commit and the font source.
# Scores stored beside a stamp are valid for any tree whose stamp is the same.
# Never put the scores directory itself among the PATHs: committing scores must not
# invalidate them.   ENGINE_REPO (default <repo>/engine), STAMP_FONTS (default bundled/windows)
cd "$(dirname "$0")/../.." || exit 2
REV=""; [ "${1:-}" = "-r" ] && { REV=$2; shift 2; }
if [ -z "$REV" ]; then
  T=$(mktemp -d); export GIT_INDEX_FILE=$T/index
  git read-tree HEAD && git add -A -- "$@" 2>/dev/null
  TREE=$(git write-tree); REV=$TREE
fi
for p in "$@"; do printf '%s %s\n' "$p" "$(git rev-parse "$REV:$p" 2>/dev/null || echo missing)"; done
printf 'engine %s\n' "$(git -C "${ENGINE_REPO:-engine}" rev-parse HEAD 2>/dev/null || echo unknown)"
printf 'fonts %s\n' "${STAMP_FONTS:-bundled/windows}"
[ -n "${T:-}" ] && rm -rf "$T"
exit 0
