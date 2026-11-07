#!/bin/bash
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
# corpus-cache.sh — the Word corpus sets that live OUT of git (user rule 2026-11-07: "we shouldn't
# check in all the corpus docs into repo, just leave locally").
#
# The documents and Word's reference PDFs sit in a shared cache, $STARLING_CORPUS (default
# /data/corpus-cache), as <set>/docs/<stem>.docx and <set>/word-win/<stem>.pdf. Git keeps only
# the per-set manifest test/corpus/docx/<set>/manifest.tsv (a header row with a "name" (or "file")
# and a "sha256" column; any others are kept) and the score files.
#
#   corpus-cache.sh check SET [SET...]        verify this host's copy against the manifests:
#                                             every manifest row has its .docx, its SHA-256
#                                             matches, nothing extra sits in docs/. Exit 1 on any
#                                             problem. (word-win PDFs: counted, not hashed.)
#   (HOST "local" copies to another directory on this box, STARLING_CORPUS_REMOTE=<dir>: no ssh)
#   corpus-cache.sh sync HOST SET [SET...]    copy the cache for those sets to HOST (rsync over
#                                             ssh, same path unless STARLING_CORPUS_REMOTE is set),
#                                             then run `check` on HOST. Needs this repo's script on
#                                             HOST at the same relative path (STARLING_REMOTE_REPO,
#                                             default this checkout's path) or it checks by manifest
#                                             over ssh from here.
#   corpus-cache.sh restore [--quiet]         copy the corpus binaries from $STARLING_CORPUS/test/corpus (same paths) into this
#                                             checkout and verify them against the SHA256SUMS (the whole office corpus
#                                             is untracked, gitignored; hooks call `restore --quiet` after a pull)
#   corpus-cache.sh install-hooks [CHECKOUT...]  post-merge/post-rewrite/post-checkout hooks that restore
#   corpus-cache.sh path SET                  print <cache>/<set>
#
# Manifest of set X is read from the repo (test/corpus/docx/X/manifest.tsv), also for a set whose
# manifest is named otherwise: x-stage-b's is test/corpus/docx/x-stage-b/manifest.tsv, kept by
# its directory name; pass that directory name as SET and the cache dir as CACHE_SET=...
# when they differ (cache new-b <-> repo x-stage-b: CACHE_SET=new-b corpus-cache.sh check x-stage-b).
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CACHE=${STARLING_CORPUS:-/data/corpus-cache}
MAN=${STARLING_MANIFESTS:-$ROOT/test/corpus/docx}

usage() { sed -n '5,25p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

# check_local CACHE SET : prints problems, returns 1 if any
check_local() {
  local cache=$1 set=$2 cs=${CACHE_SET:-$2}
  local man=$MAN/$set/manifest.tsv dir=$cache/staging/$cs
  [ -f "$man" ] || { echo "$set: no manifest at $man"; return 1; }
  [ -d "$dir/docs" ] || { echo "$set: no $dir/docs"; return 1; }
  python3 - "$man" "$dir" "$set" <<'PY'
import csv, hashlib, os, sys
man, d, name = sys.argv[1:4]
rows = list(csv.DictReader(open(man), delimiter='\t'))
bad = 0
want = set()
for r in rows:
    stem = r.get('name') or r['file']
    stem = stem[:-5] if stem.endswith('.docx') else stem
    sha = r['sha256']
    f = f"{d}/docs/{stem}.docx"
    want.add(stem + '.docx')
    if not os.path.exists(f):
        print(f"{name}: MISSING {stem}.docx"); bad += 1; continue
    h = hashlib.sha256(open(f, 'rb').read()).hexdigest()
    if h != sha:
        print(f"{name}: HASH {stem}.docx"); bad += 1
extra = sorted(set(os.listdir(f"{d}/docs")) - want)
for e in extra[:10]:
    print(f"{name}: EXTRA {e}")
bad += len(extra)
pdfs = len([x for x in os.listdir(f"{d}/word-win") if x.endswith('.pdf')]) if os.path.isdir(f"{d}/word-win") else 0
print(f"{name}: {len(rows)} documents, {bad} problems, {pdfs} word-win PDFs")
sys.exit(1 if bad else 0)
PY
}

cmd=${1:-}; shift || true
case "$cmd" in
  check)
    [ $# -ge 1 ] || usage
    rc=0; for s in "$@"; do check_local "$CACHE" "$s" || rc=1; done; exit $rc;;
  path)
    [ $# -eq 1 ] || usage; echo "$CACHE/staging/${CACHE_SET:-$1}";;
  sync)
    [ $# -ge 2 ] || usage
    host=$1; shift
    remote=${STARLING_CORPUS_REMOTE:-$CACHE}
    rc=0
    for s in "$@"; do
      cs=${CACHE_SET:-$s}
      [ -d "$CACHE/staging/$cs/docs" ] || { echo "$s: not in the local cache ($CACHE/staging/$cs)"; rc=1; continue; }
      if [ "$host" = local ]; then run() { sh -c "$1"; }; dest="$remote/$cs/"; else run() { ssh "$host" "$1"; }; dest="$host:$remote/$cs/"; fi
      run "mkdir -p '$remote/$cs'" || { rc=1; continue; }
      rsync -a --delete "$CACHE/staging/$cs/" "$dest" || { echo "$s: rsync failed"; rc=1; continue; }
      # verify on the far side from the manifest: one hash list over ssh, compared here
      python3 - "$MAN/$s/manifest.tsv" "$s" > "/tmp/corpus-sums.$$" <<'PY'
import csv, sys
for r in csv.DictReader(open(sys.argv[1]), delimiter='\t'):
    n = r.get('name') or r['file']
    n = n[:-5] if n.endswith('.docx') else n
    print(f"{r['sha256']}  docs/{n}.docx")
PY
      if run "cd '$remote/$cs' && sha256sum -c --quiet -" < "/tmp/corpus-sums.$$"; then
        echo "$s: $host verified ($(wc -l < /tmp/corpus-sums.$$) documents)"
      else
        echo "$s: $host FAILED verification"; rc=1
      fi
      rm -f "/tmp/corpus-sums.$$"
    done
    exit $rc;;
  restore)
    # copy the corpus binaries from the cache into THIS checkout's test/corpus (same paths), then check.
    # --quiet (the git hooks): size-only copy, silent, never fails the git command.
    quiet=0; [ "${1:-}" = --quiet ] && quiet=1
    src=$CACHE/test/corpus/
    [ -d "$src" ] || { [ $quiet = 1 ] || echo "no cache at $src"; exit $((quiet ? 0 : 1)); }
    mkdir -p "$ROOT/test/corpus"
    # only binaries; never the retired Mac sets (they sit in $CACHE/archive), nothing under pdf-text
    rsync -a --size-only --prune-empty-dirs --exclude 'pdf-text/' \
      --include '*/' $(for e in docx pptx xlsx pdf docm dotx xlsm pptm; do printf -- "--include=*.%s " $e; done) --exclude '*' \
      "$src" "$ROOT/test/corpus/" || { [ $quiet = 1 ] || echo "rsync failed"; exit $((quiet ? 0 : 1)); }
    [ $quiet = 1 ] && exit 0
    rc=0
    # every SHA256SUMS in the repo lists the files beside it (or in docs/ / decks/ / books/ for the input lists)
    for f in $(cd "$ROOT" && git ls-files 'test/corpus/*SHA256SUMS' 2>/dev/null); do
      d=$(dirname "$ROOT/$f")
      case "$f" in
        test/corpus/docx/SHA256SUMS) d=$d/docs;; test/corpus/docx/lo/SHA256SUMS) d=$d/docs;;
        test/corpus/pptx/SHA256SUMS) d=$d/decks;; test/corpus/xlsx/SHA256SUMS) d=$d/books;;
      esac
      [ -d "$d" ] || { echo "$f: missing $d"; rc=1; continue; }
      if (cd "$d" && sha256sum -c --quiet "$ROOT/$f" 2>&1 | head -3 | grep .); then rc=1; echo "$f: FAILED"; else echo "$f: ok ($(wc -l < "$ROOT/$f") files)"; fi
    done
    exit $rc;;
  install-hooks)
    # install post-merge / post-rewrite / post-checkout hooks that run `restore --quiet` in each given
    # checkout (default: the one this script is in). Leaves any existing hook of those names in place
    # as <name>.pre-corpus and chains to it.
    [ $# -ge 1 ] || set -- "$ROOT"
    for co in "$@"; do
      gd=$(git -C "$co" rev-parse --git-common-dir 2>/dev/null) || { echo "$co: not a git checkout"; continue; }
      case "$gd" in /*) ;; *) gd=$co/$gd;; esac
      mkdir -p "$gd/hooks"
      for h in post-merge post-rewrite post-checkout; do
        f=$gd/hooks/$h
        if [ -e "$f" ] && ! grep -q corpus-cache "$f"; then mv "$f" "$f.pre-corpus"; fi
        cat > "$f" <<'HOOK'
#!/bin/sh
# corpus-cache: put the (untracked) test corpus back after git removes or rewrites files
HOOKNAME=$(basename "$0")
[ -x "$0.pre-corpus" ] && "$0.pre-corpus" "$@"
top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -x "$top/test/tools/corpus-cache.sh" ] && "$top/test/tools/corpus-cache.sh" restore --quiet >/dev/null 2>&1
exit 0
HOOK
        chmod +x "$f"
      done
      echo "$co: hooks installed in $gd/hooks"
    done;;
  *) usage;;
esac
