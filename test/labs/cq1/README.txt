Lab cq1 -- Lab cq1: does Word hang a closing quote U+201D at a line's end, wrap it to the next line's start, or squeeze it -- and what
decides it (Linux lo5, 2026-11-01). Background: in the official 756 Word hangs a line-ending U+201D 186 times of 388 (48%) and
ours 301 of 447 (67%); for U+300D U+FF09 U+300B the two agree. Two documents show opposite answers:
  zh-b00fef0d (mode 12, rFonts hint=eastAsia, all four fonts 仿宋_GB2312, 16pt, jc both): "...条抓块统" + U+201D, and Word breaks
    BEFORE the quote -- the next line starts with U+201D (ours hangs it 8pt past the margin).
  zh-360c1df1 (mode 14, rFonts hint=default ascii/hAnsi Times New Roman, eastAsia 仿宋_GB2312, 16pt): "...金山银" fills the line,
    "山" + U+201D go down TOGETHER (ours keeps 山 and hangs the quote). There the quote is set in Times New Roman: 7.1pt wide.
Hypothesis: the run's font setting decides which font U+201D is set in, and so whether it is an East Asian mark (kinsoku, hangs/
squeezes) or a Latin quote (no kinsoku, a narrow glyph, no hang).
Page A4 11906 x 16838, margins top/bottom 1440, left = right = 2753 so the column is 6410 twips = 320.5pt = 20 ems of 16pt + 0.5pt.
Each document holds 20 test paragraphs, each followed by a marker paragraph '==NN=='. A test paragraph is K ideographs (K = 19 or
20) + U+201D + a tail; right indent R twips (0, -40, -100, -160, -240: negative = that much more room) ; tail A = 15 ideographs,
tail B = U+201C + 11 ideographs + U+201D + 4 ideographs. Room after the K ideographs is (20-K)*16 + 0.5 + |R|/20 pt.
Documents (NN-fontcode-mode-jc): fontcode F1 = hint eastAsia, ascii/hAnsi/eastAsia/cs all 仿宋_GB2312; F2 = hint default, ascii/hAnsi/cs
Times New Roman, eastAsia 仿宋_GB2312; F3 = no hint, same fonts as F2. All 16pt (sz 32), single spacing, no indents, jc both unless
'left'. Modes 12, 14, 15 (compatibilityMode); 'alt' adds w:useAltKinsokuLineBreakRules.
usage: build.py OUTDIR.  Print each to PDF with Word for Windows, then: analyze.py PDF-or-DIR > table. Report that table.

What to send back: the analyze.py table for each of the 14 prints (it is a TSV, 20 rows a document), or just the files.
Our own table, for comparison, is CQ1-OURS.tsv (same columns). Most useful first: the three F-codes at mode 12 and mode 14, jc both
(documents 01-06), then the rest.
Columns: doc, n, K, R, tail, line1_end (last 3 chars), line1_right_edge_minus_column_right_pt (>0: past the margin), line1_len,
line2_first (first 3 chars), quote_width_pt (the first U+201D), lines in the paragraph.
Needs PyMuPDF (import fitz). If a font is missing on the box, say which one.
