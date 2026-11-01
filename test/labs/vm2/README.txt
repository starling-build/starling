Lab vm2 -- fully merged vMerge row blocks: how tall is a block, by face, grid, space after and exact line (Linux lo5, 2026-11-01).
Background: lab vm (zh-eec0747a's own package, Word for Windows) gave, for a TWO-row fully merged cell in YaHei 12pt on a 15.6pt
grid with 8pt after: restart row alone >= 39.72 (two pitches + 8.52), continue row with an empty paragraph >= 26.54 (18.02 + 8.52,
NOT grid-snapped), total = max(text height, row1 + row2). We landed that for YaHei pairs only (93ede4f5c). Two other documents say
Word SNAPS the empty continue line to the grid: zh-9ba2ead7 (pair, FangSong_GB2312 14pt, WPS defaults, 8pt after, restart line
exact 20pt, trHeight 400/319) and zh-cb56e605 (block of THREE rows, 仿宋 12pt, trHeight 429/407/312, no space after).
Question: what decides snapped vs unsnapped, and what does a block of three rows add up to?
Page A4, margins 1440 (A4 11906 x 16838). Each document = 15 pages, ONE table per page (page break before each), 2 columns of 3000
twips, all cells fully merged (restart row, then continue rows), single borders, compat mode 14 + adjustLineHeightInTable.
  Page label T01..T15 is printed above the table:
    S2-Ln-hA_B   two rows, restart text n lines (n=1: "类别", n=2: "类别" + "分值" as two paragraphs), atLeast trHeight A then B twips (0 = none)
                 h = (0,0) (630,0) (0,630) (630,630) (885,885)         -> T01-T10
    S3-L1-hA_B_C three rows, 1 text line, heights (0,0,0) (630,0,0) (0,630,0) (0,0,630) (630,630,630) -> T11-T15
Documents vm2-NN-F-GRID-AFTER-LINE:  F = Y (微软雅黑 12pt) or S (仿宋_GB2312 14pt), all four font slots set;
  GRID = grid (docGrid type lines, pitch 312 = 15.6pt) or nogrid; AFTER = after8 (docDefaults spacing after 160, single line) or after0;
  LINE = plain, or exact (the restart cell's text paragraphs are line=440 exact, as in zh-eec0747a).
usage: build.py OUTDIR (regenerates docx/). Print each document to PDF with Word for Windows, then: analyze.py PDF-or-DIR > table.
What to send back: that table for the prints (TSV, one row per page), or just the PDFs. Our own is VM2-OURS.tsv (same columns).
Most useful first: documents 01-04 (grid + after8: YaHei plain/exact, FangSong plain/exact), then 05-08 (grid, after0), then the nogrid ones.
Columns: doc, page, label, table_top, table_bottom, height (the number that matters), first cell text top minus table top, marker top
minus table bottom. Needs PyMuPDF. If a font is missing on the box, say which.
