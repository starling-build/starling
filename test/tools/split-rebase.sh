#!/bin/bash
# test/tools/split-rebase.sh — move your unlanded commits across the RichLayout.swift split.
#
# RichLayout.swift was cut into RichLayout+*.swift by test/tools/split-richlayout.py (a pure move). A plain
# `git rebase origin/office` of work that edits RichLayout.swift would conflict everywhere, because the code
# it edits is no longer in that file. This script re-expresses your work instead: it splits your branch's base
# and your tip the same way (the split is a deterministic function of the text), merges the two against
# origin/office with a real 3-way merge, and puts the result on top of origin/office as ONE commit.
# Needs: a clean tree (commit first), git >= 2.38.   Result: your branch = origin/office + your work.
# Your old tip is kept as refs/backup/pre-split-<time>. On a conflict nothing is changed and the files are listed.
#   test/tools/split-rebase.sh [--onto REV]     (REV defaults to origin/office, fetched)
set -eu
cd "$(git rev-parse --show-toplevel)"
RL=apps/OfficeApp/Sources/OfficeText/RichLayout.swift
ONTO=origin/office; [ "${1:-}" = "--onto" ] && ONTO=$2
[ "$ONTO" = origin/office ] && git fetch -q origin office
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "commit or stash your changes first"; exit 2; }
# the commit that did the split: the one that added RichLayout+Paginate.swift on the way to ONTO
SPLIT=${SPLIT_COMMIT:-$(git log "$ONTO" --diff-filter=A --format=%H -n 1 -- apps/OfficeApp/Sources/OfficeText/RichLayout+Paginate.swift)}
[ -n "$SPLIT" ] || { echo "$ONTO has no split yet: just rebase as usual"; exit 2; }
if git merge-base --is-ancestor "$SPLIT" HEAD; then echo "your branch already contains the split: plain 'git rebase $ONTO'"; exit 0; fi
BASE=$(git merge-base HEAD "$SPLIT^")
[ "$(git rev-list --count $BASE..HEAD)" -gt 0 ] || { echo "no commits of yours past the split's base: 'git reset --hard $ONTO' is all you need"; exit 0; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git show "$SPLIT:test/tools/split-richlayout.py" > "$TMP/split.py"   # the very script that made the split
SPLITPY=$TMP/split.py
split_tree() {   # REV -> tree hash of REV with RichLayout.swift split
  local rev=$1 d=$TMP/$(echo "$1" | tr -c 'a-zA-Z0-9' _); mkdir -p "$d/$(dirname $RL)"
  git show "$rev:$RL" > "$d/$RL"
  ( cd "$d" && python3 "$SPLITPY" ) >&2
  local idx=$TMP/idx.$$; rm -f "$idx"
  GIT_INDEX_FILE=$idx git read-tree "$rev"
  for f in "$d"/$(dirname $RL)/*.swift; do
    h=$(git hash-object -w "$f"); GIT_INDEX_FILE=$idx git update-index --add --cacheinfo 100644,$h,"$(dirname $RL)/$(basename $f)"
  done
  GIT_INDEX_FILE=$idx git write-tree
}
SB=$(split_tree "$BASE"); ST=$(split_tree HEAD)
if M=$(git merge-tree --write-tree --merge-base="$SB" "$ONTO" "$ST" 2>"$TMP/err"); then :; else
  echo "CONFLICT merging your work with the split; nothing changed. Conflicted:"; git merge-tree --write-tree --name-only --merge-base="$SB" "$ONTO" "$ST" 2>/dev/null | sed -n '2,$p' | sort -u | head -20; exit 1
fi
MSG=$(git log --reverse --format='%s%n%n%b' "$BASE..HEAD")
NEW=$(printf '%s\n' "$MSG" | git commit-tree "$M" -p "$(git rev-parse "$ONTO")")
BK=refs/backup/pre-split-$(date +%H%M%S); git update-ref "$BK" HEAD
git reset -q --hard "$NEW"
echo "done: $(git rev-list --count "$ONTO"..HEAD) commit on top of $ONTO (your old tip: $BK). Build, then land as usual."
