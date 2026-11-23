#!/bin/bash
# Our layout of each .xls must equal our layout of Excel's own .xlsx conversion of it
# (xlsx2/xls-as-xlsx/); any difference is a reader bug.
# usage: test/xls-reader-diff.sh <OfficeApp> <outdir> [NAME...]   (NAME = xls-<id>)
APP=$1; OUT=$2; shift 2; mkdir -p "$OUT"
B=/data/corpus-cache/test/corpus/xlsx2
names=("$@"); [ ${#names[@]} -gt 0 ] || names=($(cd $B/books && ls xls-*.xls | sed 's/\.xls$//'))
same=0; diff=0
for n in "${names[@]}"; do
  "$APP" --sheet-layout $B/books/$n.xls > "$OUT/$n.a" 2>"$OUT/$n.err"
  "$APP" --sheet-layout $B/xls-as-xlsx/$n.xlsx > "$OUT/$n.b" 2>>"$OUT/$n.err"
  if cmp -s "$OUT/$n.a" "$OUT/$n.b"; then same=$((same+1)); echo "same $n"; else diff=$((diff+1)); echo "DIFF $n $(diff "$OUT/$n.a" "$OUT/$n.b" | grep -c '^[<>]')"; fi
done
echo "identical $same, different $diff"
