#!/bin/bash
# One-command edit-and-save loss sweep.
#   edit-loss-sweep.sh docx|xlsx|pptx [--max N] [--base FILE] [--save-base FILE]
# Saves every corpus doc with and without a small edit, then prints what the
# save lost, by element/attribute name with doc counts (top 40 per section),
# and (with --base) the names whose doc count changed against an earlier run
# (run it once on main with --save-base, then on your branch with --base).
set -u
KIND=${1:-}; shift || true
case "$KIND" in docx|xlsx|pptx) ;; *) echo "usage: $0 docx|xlsx|pptx [--max N] [--base FILE] [--save-base FILE]"; exit 2;; esac
MAX=; BASE=; SAVE=
while [ $# -gt 0 ]; do case "$1" in
  --max) MAX=$2; shift 2;; --base) BASE=$2; shift 2;; --save-base) SAVE=$2; shift 2;; *) echo "bad arg $1"; exit 2;; esac; done
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIR=/data/corpus-cache/test/corpus/$KIND/$(case $KIND in docx) echo docs;; pptx) echo decks;; *) echo books;; esac)
SD=${SWEEP_OUT_DIR:-$(dirname "$ROOT")/sweep}; mkdir -p "$SD"
OUT=$SD/run-$KIND-$$.txt
cd "$ROOT" || exit 1
env STARLING_SWEEP_DIR=$DIR STARLING_SWEEP_KIND=$KIND STARLING_SWEEP_OUT=$OUT ${MAX:+STARLING_SWEEP_MAX=$MAX} \
  ~/bin/unit-tests.sh --filter EditLossSweepTests >"$OUT.log" 2>&1
[ -s "$OUT" ] || { echo "sweep produced no result; see $OUT.log"; tail -5 "$OUT.log"; exit 1; }
awk -F'\t' '/^==/{print; n=0; next} n<40 {print; n++}' "$OUT" | cut -c1-110
if [ -n "$BASE" ]; then
  echo; echo "== changed doc counts vs $BASE (old -> new)"
  awk -F'\t' '/^==/{split($1,w," "); s=w[2]; next} {k=s FS $3; if (FILENAME==ARGV[1]) a[k]=$1; else b[k]=$1}
    END{for(k in a) if(!(k in b)||a[k]!=b[k]) print a[k] " -> " (k in b?b[k]:0) "  " k;
        for(k in b) if(!(k in a)) print "0 -> " b[k] "  " k}' "$BASE" "$OUT" | sort -t' ' -k1n | head -60
fi
[ -n "$SAVE" ] && cp "$OUT" "$SAVE" && echo "saved base: $SAVE"
echo "full result: $OUT"
