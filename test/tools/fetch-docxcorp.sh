#!/bin/bash
# Rebuild the docxcorp.us cache from the manifest. The .docx files are NOT in git:
# they carry no per-file licence (ODC-BY covers the collection only).
# Usage: test/tools/fetch-docxcorp.sh [cache-dir]   (default /data/docx-corpus-cache/docxcorp)
# Files are stored as <doc_id>.docx and checked against file_sha256 in the manifest.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
M=$HERE/../corpus/docx/docxcorp/manifest.tsv
D=${1:-/data/docx-corpus-cache/docxcorp}
mkdir -p "$D"; fail=0
tail -n +2 "$M" | while IFS=$'\t' read -r id sha lang url rest; do
  f=$D/$id.docx
  if [ -f "$f" ] && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$sha" ]; then continue; fi
  ok=0
  for try in 1 2 3; do
    curl -sfL -A 'starling-corpus-research/1.0' -o "$f.tmp" "$url" && \
      [ "$(sha256sum "$f.tmp" | cut -d' ' -f1)" = "$sha" ] && mv "$f.tmp" "$f" && ok=1 && break
    sleep 2
  done
  [ $ok = 1 ] || { rm -f "$f.tmp"; echo "FAILED $id" >&2; }
  sleep 0.3
done
echo "cache: $(ls "$D"/*.docx 2>/dev/null | wc -l) files in $D"
