#!/bin/bash
# test/web-parity-sweep.sh KIND IN_DIR WORK — how the BROWSER build draws
# Slides decks (KIND=pptx) or Sheets workbooks (KIND=xlsx) against how the
# native build draws them: each file is exported to PDF natively
# (`OfficeApp --deck-pdf` / `--sheet-pdf`) and by File → Export → PDF in headless
# Chrome (build/tools/web-drive.mjs pdfs), and test/pdf-diff.py scores each
# page. One painter over two renderers: the expected worst-page score is 0.00.
# Like test/docx-web-render.sh, which does the same for Word. WORK must lie
# under $HOME when Chrome is a snap (it cannot write downloads elsewhere).
# Needs CHROME, PYTHON (pymupdf numpy pillow), a native OfficeApp (OFFICE_APP)
# and the staged web build. Rows already in WORK/render.tsv are skipped.
export OFFICE_FONT_SOURCE="${OFFICE_FONT_SOURCE:-bundled}"
KIND=${1:?kind pptx|xlsx}; IN=$(cd "${2:?in dir}" && pwd); WORK=${3:?work dir}
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
unset LD_LIBRARY_PATH
APP="${OFFICE_APP:-$ROOT/.build-shared/x86_64-unknown-linux-gnu/release/OfficeApp}"
STAGE="$ROOT/.stage-web-OfficeApp"
case $KIND in pptx) FLAG=--deck-pdf;; xlsx) FLAG=--sheet-pdf; export PDF_QUERY=${PDF_QUERY:-book-pdf};; *) echo "kind?" >&2; exit 2;; esac
# Without the pair env (source ~/bin/office-env.sh) the native side loses its
# line breaks silently and every wrapped deck "differs".
[ -n "${STARLING_ICU:-}" ] || { echo "source ~/bin/office-env.sh first (STARLING_ICU unset)" >&2; exit 2; }
[ -x "$APP" ] && [ -s "$STAGE/app.wasm" ] || { echo "need native OfficeApp and staged web build" >&2; exit 2; }
mkdir -p "$WORK/native" "$WORK/web" "$WORK/pairs"; touch "$WORK/render.tsv"
: > "$WORK/web-list.txt"
for f in "$IN"/*.$KIND; do
  n=$(basename "$f"); b=${n%.*}
  grep -q "^$n	" "$WORK/render.tsv" && continue
  [ -s "$WORK/native/$b.pdf" ] || timeout 180 "$APP" $FLAG "$f" "$WORK/native/$b.pdf" >/dev/null 2>&1
  [ -s "$WORK/native/$b.pdf" ] && echo "$f" >> "$WORK/web-list.txt"
done
python3 "$ROOT/build/tools/web-serve.py" "$STAGE" "${WEB_PORT:-8145}" >/dev/null 2>&1 & SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 1
URL="http://127.0.0.1:${WEB_PORT:-8145}/" PORT="${DEVTOOLS:-9345}" CHROME_PROFILE="$WORK/chrome-profile" \
  node "$ROOT/build/tools/web-drive.mjs" pdfs "$WORK/web-list.txt" "$WORK/web" > "$WORK/web-drive.log" 2>&1
kill $SERVER 2>/dev/null
for f in "$IN"/*.$KIND; do
  n=$(basename "$f"); b=${n%.*}
  grep -q "^$n	" "$WORK/render.tsv" && continue
  if [ ! -s "$WORK/native/$b.pdf" ]; then printf '%s\tNATIVE-FAIL\n' "$n"
  elif [ ! -s "$WORK/web/$b.pdf" ]; then printf '%s\t%s\n' "$n" "$(grep "^$n	" "$WORK/web/web.tsv" | tail -1 | cut -f2- | cut -c1-120)"
  else printf '%s\t%s\n' "$n" "$(${PYTHON:-python3} "$HERE/pdf-diff.py" "$WORK/native/$b.pdf" "$WORK/web/$b.pdf" "$WORK/pairs" 1 | tail -1)"
  fi | tee -a "$WORK/render.tsv"
done
