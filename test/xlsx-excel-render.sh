#!/bin/bash
# test/xlsx-excel-render.sh IN_DIR OUT_DIR [names…] — Excel's own printing
# of every .xlsx in IN_DIR, as OUT_DIR/NAME-orig.pdf: the references the
# Sheets painter gate (test/xlsx-app-render.sh) scores this app against.
# OUT_DIR/export.tsv gets a row per workbook (name, verdict: "pdf", "pdf
# repaired" or "error: …"); rows already there are skipped, so an
# interrupted run resumes. Each PDF is the entire workbook — every visible
# sheet — and stops at 20 pages (XLSX_MAX_PAGES), which is also where the
# gate stops this app's.
#
#   test/xlsx-excel-render.sh test/corpus/xlsx/books test/corpus/xlsx/excel
#
# It runs on WINDOWS, under Git Bash, with Excel driven over COM
# (test/xlsx-excel-pdf.ps1) — from a shell that is NOT elevated. Not on a
# Mac for now: Excel for Mac without a licence opens workbooks read-only
# with File → Print… disabled, and both the scripted `save as … PDF file
# format` and `print out` answer without error and write nothing (16.113,
# 2026-10-11). With a licensed Excel for Mac the scripted save would do;
# the references would then be that Excel's, and a baseline its own.
IN=$1; OUT=$2; shift 2; HERE=$(cd "$(dirname "$0")" && pwd)
[ -d "$IN" ] && [ -n "$OUT" ] || { echo "usage: $0 IN_DIR OUT_DIR [names]" >&2; exit 2; }
case "$(uname)" in
  Darwin|Linux) echo "Excel's PDFs are made on Windows (see the header of $0)" >&2; exit 2 ;;
esac
mkdir -p "$OUT"
# (Read by line: a workbook's name may have spaces in it, "54084 - Greek -
# beyond BMP.xlsx", and word-splitting made five workbooks of that one.)
names=("$@"); [ ${#names[@]} -gt 0 ] || mapfile -t names < <(cd "$IN" && ls *.xlsx | grep -v '^~\$')
touch "$OUT/export.tsv"
for n in "${names[@]}"; do
  n=$(basename "$n"); base=${n%.xlsx}
  grep -q "^$n	" "$OUT/export.tsv" && continue
  # 180 s: Excel recalculates on open, and a workbook that hangs it must
  # not hang the run. Its instance is then left behind — kill EXCEL.EXE.
  r=$(timeout 180 powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$HERE/xlsx-excel-pdf.ps1")" \
        "$(cygpath -w "$IN/$n")" "$(cygpath -w "$OUT/$base-orig.pdf")" "${XLSX_MAX_PAGES:-20}" 2>&1 | tr -d '\r' | tail -1)
  [ -n "$r" ] || r="error: timed out"
  printf '%s\t%s\n' "$n" "$r" | tee -a "$OUT/export.tsv"
done
