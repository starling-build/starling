Lab vm5 -- the empty continue paragraph of a merged vMerge pair, with an EXACT-spaced restart line (Linux lo5, 2026-11-01).
Background: vm4 (wip/lab-vm4, VM4-WORD.tsv) says an all-YaHei mark (N1, N2) is SNAPPED to the grid and an ascii-仿宋/宋体 mark is UNSNAPPED. But zh-eec0747a's header table
(9 cells, YaHei marks as N1, vAlign center, restart paragraph spacing line=440 lineRule=exact, jc center, row heights 630/624 atLeast, docDefaults by theme) is set by
Word as if its continue line were NOT snapped (our snapped print is 4pt taller; the first row stands 4pt higher in Word). What differs from the lab? This lab adds the one thing the
lab still lacks: the restart paragraph's spacing line=440 exact (22pt), with 1 or 2 text lines in the restart cell.
Same page layout as vm3/vm4 (A4, 1-inch margins, compat 14 + adjustLineHeightInTable, YaHei 12pt docDefaults, 8pt after, grid pitch 312, fixed 2x3000 table, one merged table per page).
Pages per document: T01-T03 restart cell 1 line, two rows, trHeight (0,0) (630,0) (630,630); T04-T06 the same with a restart cell of 2 lines; T07-T08 three rows (0,0,0) (630,630,630), 1 line.
Documents vm5-NN-Y-grid-after8-exact440-MK; the MARK on the empty continue paragraphs:
  M0 none      N1 YaHei ascii/hAnsi/eastAsia + cs 宋体 + color + kern 0 + sz 24 (zh-eec0747a's nine)    N2 YaHei in the three slots, sz 24
  N3 仿宋_GB2312 in the three slots, sz 24     N5 ascii+eastAsia 仿宋, hAnsi absent, sz 24     N1v as N1 and the cells vAlign center
usage: build.py OUTDIR (already built into docx/). Print each with Word for Windows, then analyze.py PDF-or-DIR > table. The number that matters: column 6 (height). Our table: VM5-OURS.tsv.
