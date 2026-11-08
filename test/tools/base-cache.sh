#!/bin/bash
# test/tools/base-cache.sh — the shared base cache of the landing pair. Every land.sh needs the
# TIP's build and its swept scores as the "base" the fix is measured against; the stored scores
# in the tip's commit are almost never valid (a lander's pair runs on the tip it started from,
# others land meanwhile — 0 of 45 landings on 2026-11-02 matched), so the base used to be
# rebuilt and re-swept by every lander. Whoever builds+sweeps a base now publishes it here, keyed
# by the STAMP of the tree it is (test/tools/stamp.sh), and every later lander on a tree with
# that stamp reuses it.
#   base-cache.sh key REV            print the cache key of REV's tree (hash of its stamp)
#   base-cache.sh get KEY            print the cache dir if complete, else exit 1 (and touch it: LRU)
#   base-cache.sh put KEY BINDIR SCOREDIR   publish BINDIR (OfficeApp + libs + resources) and
#                                    SCOREDIR (756.v2 756.v1 lo.v2 lo.v1, and xb/xa/xd/xs .v2 .v1 when present) atomically; no-op if present
#   base-cache.sh prune [N]          keep the N newest entries (default 12)
# Dir: ${BASE_CACHE:-/data/landlock/cache}. Needs the engine env of land.sh exported (stamp.sh reads it).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); C=${BASE_CACHE:-/data/landlock/cache}; mkdir -p "$C"
case ${1:-} in
  key) cd "$HERE/../.." && "$HERE/stamp.sh" -r "$2" apps/OfficeApp sdk test/docx-line-match.py | sha1sum | cut -c1-20;;
  get) [ -f "$C/$2/DONE" ] && { touch "$C/$2"; echo "$C/$2"; } || exit 1;;
  put) [ -f "$C/$2/DONE" ] && exit 0
       T=$(mktemp -d "$C/.tmp.XXXXXX") || exit 1
       mkdir "$T/bin" "$T/scores" && cp -a "$3"/. "$T/bin/" && cp "$4"/756.v2 "$4"/756.v1 "$4"/lo.v2 "$4"/lo.v1 "$T/scores/" && { for f in "$4"/xb.v2 "$4"/xb.v1 "$4"/xa.v2 "$4"/xa.v1 "$4"/xd.v2 "$4"/xd.v1 "$4"/xs.v2 "$4"/xs.v1; do [ -s "$f" ] && cp "$f" "$T/scores/"; done; true; } || { rm -rf "$T"; exit 1; }
       : > "$T/DONE"; chmod -R a+rX "$T"
       mv -T "$T" "$C/$2" 2>/dev/null || rm -rf "$T";;
  prune) N=${2:-12}; ls -dt "$C"/*/ 2>/dev/null | tail -n +$((N+1)) | while read -r d; do rm -rf "$d"; done;;
  *) sed -n 2,16p "$0"; exit 2;;
esac
