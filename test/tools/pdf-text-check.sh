#!/bin/bash
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
#
# test/tools/pdf-text-check.sh — the text of a PDF we write is the text of the document.
# Converts the small documents in test/corpus/docx/pdf-text (Devanagari with conjuncts,
# Arabic, Hebrew with points, Thai with tone marks; each has its source text beside it as
# NAME.txt), reads each PDF back with PyMuPDF and compares it with the source after NFKC
# (so Arabic presentation forms equal their letters) with spaces taken out. Arabic and
# Hebrew read back in visual order, so those are compared word by word, in any order.
# Exits 1 on any difference.
#
#   OFFICE_APP   the binary (default .build-shared release)   WORD_EO/STARLING_ICU  the engine out dir
#   PYTHON       a Python with PyMuPDF (default $HOME/venv-word/bin/python, else python3)
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
APP=${OFFICE_APP:-$ROOT/.build-shared/x86_64-unknown-linux-gnu/release/OfficeApp}
PY=${PYTHON:-$([ -x "$HOME/venv-word/bin/python" ] && echo "$HOME/venv-word/bin/python" || echo python3)}
ICU=${STARLING_ICU:-${WORD_EO:+$WORD_EO/icudtl.dat}}
[ -n "$ICU" ] || { echo "set STARLING_ICU (or WORD_EO, the engine out directory)" >&2; exit 2; }
[ -x "$APP" ] || { echo "no binary at $APP (set OFFICE_APP)" >&2; exit 2; }
OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
export OFFICE_FONT_SOURCE=bundled OFFICE_WORD_FONTS=windows STARLING_ICU="$ICU"
[ -n "${WORD_EO:-}" ] && export LD_LIBRARY_PATH="$WORD_EO"
D=$ROOT/test/corpus/docx/pdf-text
for k in deva arab hebr thai; do "$APP" --convert "$D/$k.docx" "$OUT/$k.pdf" >/dev/null 2>&1 || echo "convert failed: $k"; done
"$PY" - "$D" "$OUT" <<'P'
import sys, re, unicodedata, pymupdf
d, out = sys.argv[1:3]
fold = lambda t: unicodedata.normalize("NFKC", t)
bad = 0
for k in ("deva", "arab", "hebr", "thai"):
    src = open(f"{d}/{k}.txt").read()
    try:
        got = pymupdf.open(f"{out}/{k}.pdf")[0].get_text()
    except Exception as e:
        print(f"FAIL {k}: no PDF ({e})"); bad += 1; continue
    if k in ("arab", "hebr"):
        ok = sorted(fold(src).split()) == sorted(fold(got).split())
    else:
        ok = re.sub(r"\s+", "", fold(src)) == re.sub(r"\s+", "", fold(got))
    print(("ok   " if ok else "FAIL ") + k)
    if not ok:
        bad += 1; print("  source:", fold(src)); print("  pdf:   ", fold(got).strip())
sys.exit(1 if bad else 0)
P
