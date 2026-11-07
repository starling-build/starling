#!/bin/bash
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
# corpus-cache.sh — the Word corpus sets that live OUT of git (user rule 2026-11-07: "we shouldn't
# check in all the corpus docs into repo, just leave locally").
#
# The documents and Word's reference PDFs sit in a shared cache, $STARLING_CORPUS (default
# /data/docx-corpus-cache), as <set>/docs/<stem>.docx and <set>/word-win/<stem>.pdf. Git keeps only
# the per-set manifest test/corpus/docx/<set>/manifest.tsv (a header row with a "name" (or "file")
# and a "sha256" column; any others are kept) and the score files.
#
#   corpus-cache.sh check SET [SET...]        verify this host's copy against the manifests:
#                                             every manifest row has its .docx, its SHA-256
#                                             matches, nothing extra sits in docs/. Exit 1 on any
#                                             problem. (word-win PDFs: counted, not hashed.)
#   corpus-cache.sh sync HOST SET [SET...]    copy the cache for those sets to HOST (rsync over
#                                             ssh, same path unless STARLING_CORPUS_REMOTE is set),
#                                             then run `check` on HOST. Needs this repo's script on
#                                             HOST at the same relative path (STARLING_REMOTE_REPO,
#                                             default this checkout's path) or it checks by manifest
#                                             over ssh from here.
#   corpus-cache.sh path SET                  print <cache>/<set>
#
# Manifest of set X is read from the repo (test/corpus/docx/X/manifest.tsv), also for a set whose
# manifest is named otherwise: x-stage-b's is test/corpus/docx/x-stage-b/manifest.tsv, kept by
# its directory name; pass that directory name as SET and the cache dir as CACHE_SET=...
# when they differ (cache new-b <-> repo x-stage-b: CACHE_SET=new-b corpus-cache.sh check x-stage-b).
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CACHE=${STARLING_CORPUS:-/data/docx-corpus-cache}
MAN=${STARLING_MANIFESTS:-$ROOT/test/corpus/docx}

usage() { sed -n '5,25p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

# check_local CACHE SET : prints problems, returns 1 if any
check_local() {
  local cache=$1 set=$2 cs=${CACHE_SET:-$2}
  local man=$MAN/$set/manifest.tsv dir=$cache/$cs
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
    [ $# -eq 1 ] || usage; echo "$CACHE/${CACHE_SET:-$1}";;
  sync)
    [ $# -ge 2 ] || usage
    host=$1; shift
    remote=${STARLING_CORPUS_REMOTE:-$CACHE}
    rc=0
    for s in "$@"; do
      cs=${CACHE_SET:-$s}
      [ -d "$CACHE/$cs/docs" ] || { echo "$s: not in the local cache ($CACHE/$cs)"; rc=1; continue; }
      ssh "$host" "mkdir -p '$remote/$cs'" || { rc=1; continue; }
      rsync -a --delete "$CACHE/$cs/" "$host:$remote/$cs/" || { echo "$s: rsync failed"; rc=1; continue; }
      # verify on the far side from the manifest: one hash list over ssh, compared here
      python3 - "$MAN/$s/manifest.tsv" "$s" > "/tmp/corpus-sums.$$" <<'PY'
import csv, sys
for r in csv.DictReader(open(sys.argv[1]), delimiter='\t'):
    n = r.get('name') or r['file']
    n = n[:-5] if n.endswith('.docx') else n
    print(f"{r['sha256']}  docs/{n}.docx")
PY
      if ssh "$host" "cd '$remote/$cs' && sha256sum -c --quiet -" < "/tmp/corpus-sums.$$"; then
        echo "$s: $host verified ($(wc -l < /tmp/corpus-sums.$$) documents)"
      else
        echo "$s: $host FAILED verification"; rc=1
      fi
      rm -f "/tmp/corpus-sums.$$"
    done
    exit $rc;;
  *) usage;;
esac
