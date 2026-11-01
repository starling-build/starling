Lab vm3 -- the empty continue paragraph of a merged vMerge pair: what decides snapped vs unsnapped (Linux lo5, 2026-11-01).
Background: lab vm2 (read: VM2-WORD.tsv) says that with the empty continue paragraph carrying NO mark properties, Word snaps its line to the
grid for YaHei 12pt exactly as for FangSong (Y == S: grid + after8 plain, two rows 79.92). But zh-eec0747a (pair, empty continue paragraphs whose MARK says
rFonts ascii/eastAsia 仿宋_GB2312, sz 24; cells vAlign center; document default face YaHei by theme) is set by Word with the continue line NOT snapped
(18.02 + 8.52, lab vm), and we landed a YaHei-only rule for it (93ede4f5c). Which of those differences matters?
Same page layout as vm2 (A4, 1-inch margins, 15 pages max, one fully merged table per page, 2 columns of 3000, compat 14 + adjustLineHeightInTable),
YaHei 12pt for everything (docDefaults all four font slots), 8pt after, plain restart line. Pages: T01-T03 two rows, restart 1 text line, trHeight (0,0) (630,0) (630,630);
T04-T05 three rows (0,0,0) (630,630,630).  Documents vm3-NN-Y-GRID-after8-MARK:  GRID = grid (docGrid lines, pitch 312) or nogrid;
MARK = what the EMPTY continue paragraphs carry:
  M0 nothing                                         M1 mark rPr: rFonts ascii=仿宋_GB2312 hAnsi=微软雅黑 eastAsia=仿宋_GB2312, sz 24 (as zh-eec0747a)
  M2 mark rPr: sz 24 only                            M3 mark rPr: all slots 仿宋_GB2312, sz 28
  M4 nothing, but the cells are vAlign center        M5 as M1 and vAlign center
usage: build.py OUTDIR. Print each to PDF with Word for Windows, then: analyze.py PDF-or-DIR > table (TSV, one row per page). The number that matters: column 6 (height).
Our table (this tip): VM3-OURS.tsv. Most useful: the grid documents 01-06.
