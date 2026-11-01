#!/bin/bash
# zhscore.sh OUTDIR prefix... — convert zh docs by id prefix with zh's OfficeApp (Windows mode) and score v2
R=$HOME/dev/starling/starling-office-zh; E=$R/engine/src/out/host_release_arm64
D=$1; shift; rm -rf $D; mkdir -p $D/pdf
export STARLING_ICU=$E/icudtl.dat OFFICE_FONT_SOURCE=bundled OFFICE_WORD_FONTS=windows
for p in "$@"; do while [ $(jobs -r | wc -l) -ge 6 ]; do sleep 0.5; done; f=$(ls $R/test/corpus/docx/docs/$p*.docx | head -1); n=$(basename $f .docx)
  $R/apps/OfficeApp/.build/release/OfficeApp --convert $f $D/pdf/$n.pdf >/dev/null 2>&1 & done; wait
cd $R; DOCX_LINE_MATCH=v2 DOCX_WORD_REFS=$R/test/corpus/docx/word-win DOCX_LINE_READER=mupdf ~/starling-word-check/lab/venv/bin/python test/docx-line-match.py $D 2>&1 | cut -c1-110
