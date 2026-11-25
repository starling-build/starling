#!/bin/bash
# size-check.sh BASE HEAD [LIMIT_MB=10]: refuses (exit 1) if any commit in BASE..HEAD adds or changes a file over LIMIT_MB
# (build dirs, logs, corpus files that slipped in). Run in the repo; prints the offending commit, size and path. (amd-8, 2026-11-25)
BASE=${1:?usage: size-check.sh BASE HEAD [MB]}; HEAD=${2:?}; LIM=$(( ${3:-10} * 1024 * 1024 )); bad=0
for c in $(git rev-list --no-merges "$BASE..$HEAD"); do
  git diff-tree --no-commit-id -r -m --root --diff-filter=AM "$c" | while read -r _ _ _ sha _ path; do
    sz=$(git cat-file -s "$sha" 2>/dev/null || echo 0)
    [ "$sz" -gt "$LIM" ] && echo "size-check: ${c:0:9} $((sz/1048576)) MB $path"
  done
done | tee /dev/stderr | grep -q . && { echo "size-check: REFUSED: a commit is over ${3:-10} MB (see above); remove the file and recommit" >&2; exit 1; }
exit 0
