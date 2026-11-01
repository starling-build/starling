Lab vm4 -- the empty continue paragraph of a merged vMerge pair: which MARK shapes leave its line off the grid (Linux lo5, 2026-11-01).
Background: lab vm3 (read: ../vm3/VM3-WORD.tsv, grid pages): the empty continue paragraph is UNSNAPPED (two rows 64.32, not 79.92) when its mark says
M1 = rFonts ascii=仿宋_GB2312 hAnsi=微软雅黑 eastAsia=仿宋_GB2312 + sz 24; it is SNAPPED (79.92) for M0 no mark properties, M2 sz 24 only, M3 all slots 仿宋_GB2312 sz 28.
zh-eec0747a has 15 pairs/blocks (6 with M1', 9 with N1) whose empty continue paragraph is NOT snapped by Word (we match that today only by a rule keyed on the text face, which vm2 says is wrong):
  6 of them carry mark M1' = rFonts ascii=仿宋_GB2312 eastAsia=仿宋_GB2312 hAnsiTheme=minorHAnsi (Calibri) cstheme, sz 24
  9 of them carry   mark N1  = rFonts ascii=hAnsi=eastAsia=微软雅黑 cs=宋体, color 000000, kern 0, sz 24   (all slots YaHei: NOT tested in vm3)
So vm3 left open what decides it. Same page layout, fonts and grid as vm3 (A4, 1-inch margins, compat 14 + adjustLineHeightInTable, YaHei 12pt docDefaults,
8pt after, grid pitch 312, one merged table per page, T01-T03 two rows, T04-T05 three rows). GRID pages only. Documents vm4-NN-Y-grid-after8-Nk,
Nk = what the EMPTY continue paragraphs' mark carries:
  N1  YaHei in ascii/hAnsi/eastAsia, cs 宋体, color 000000, kern 0, sz 24  (zh-eec0747a's nine)
  N2  YaHei in ascii/hAnsi/eastAsia, sz 24 only                              (N1 without cs, color, kern)
  N3  仿宋_GB2312 in all three, sz 24                                         (vm3's M3 was sz 28)
  N4  ascii 仿宋, hAnsi Calibri, eastAsia 仿宋, sz 24                         (M1 with the document's theme Latin face)
  N5  ascii 仿宋, eastAsia 仿宋, hAnsi NOT stated, sz 24
  N6  M1 plus color 000000 and kern 0
  N7  eastAsia 仿宋 alone, sz 24             N8  ascii 仿宋 alone, sz 24
  N9  ascii 宋体 alone, no size              N10 kern 0 alone
Reference from vm3 (grid, T01..T05): snapped 79.92 79.92 79.92 119.64 119.64; unsnapped (M1) 64.32 64.32 72.24 88.44 104.16.
usage: build.py OUTDIR (already built into docx/). Print each to PDF with Word for Windows, then: analyze.py PDF-or-DIR > table (TSV, one row per page). The number that matters: column 6 (height).
Our table (this tip): VM4-OURS.tsv.
