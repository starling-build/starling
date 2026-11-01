Scratch tools of Mac session 7bd18d8e ("macOS-doc"), kept for the amd session that takes over the plain-ideograph fit class. They hard-code Mac paths
(the session's scratchpad, ~/starling-word-check/lab/venv/bin/python, the zh/zh2 worktrees): read them, change the paths, do not expect them to run as they are.
  zhscore.sh OUTDIR id-prefix...   convert zh corpus docs by id prefix (Windows mode, bundled fonts) and score v2 against word-win; max 6 jobs (in zsh pass the list as ${=IDS})
  cmp.py OUT                       compare a score output against /tmp/docx-pair-mac/fix/756.v2
  lines.py OURS.pdf WORD.pdf       per-line bboxes, ours first, then Word's
  census.py / census2.tsv          the line-end census (columns: doc, page, y, wordLastChar, oursLastChar, wordTail, oursTail, nextWordLineFirstChar, wordLast8, oursLast8, fullWordLine, fullOursLine, x);
                                   NOTE ~40 of 57 digit-at-break rows are the NEXT TABLE CELL's text on the same y (not real line ends) -- check wordLast8+next appears contiguously in the paragraph text
  sqdec2.py TRACE WORDPDF [-v]     classify each squeeze decision of a STARLING_RICHTEXT_FIT trace against Word's lines
  para.py DOCX 'substring'         paragraph text lookup; feat.py / wrapflag.txt (197 ids with doNotWrapTextWithPunct) / gridids.txt (43 zh docs with a linesAndChars/snapToChars grid)
  gx.py, autosp2.py               glyph advances / automatic-space widths from a PDF
  pair13.sh                        rebase zh onto origin/office, build base (zh2) and fix (zh), run test/tools/docx-pair.sh (~20 min on the Mac)
Trace: STARLING_RICHTEXT_FIT='<substring of the paragraph>' (empty string = every paragraph) OfficeApp --convert in.docx out.pdf 2>trace  -- needs a real output path,
env STARLING_ICU=$E/icudtl.dat OFFICE_FONT_SOURCE=bundled OFFICE_WORD_FONTS=windows.
