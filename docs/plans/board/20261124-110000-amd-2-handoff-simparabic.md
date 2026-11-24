# amd-2 handoff: Simplified Arabic line (2026-11-24)

- Gap: xb ara-z3803947-de4a70 started 0 of 184 lines; ours stood 3.2 pt high at line 1 and the offset grew to 22-48 pt by page 2.
- Lab sp1 (A bold 14pt empty para + text, B 18pt empty regular + text, C text, D both + text), Word prints:
  first baseline 134.42 / 124.46 / 88.58 / 170.30. Text-only line: 16.58 pt under the margin at 14pt = 1.184 em (hhea 2416/2048).
  Empty 18pt regular mark with after=6: pitch 35.88 = 6 + 18*1.658. Additive (D = A + B).
- Rule: windows-arabic-face-own-line sets face.baseline = 2416/2048 for Simplified Arabic (it had the line height 1.658 but not the baseline).
  After: ours 134.32 / 124.37 / 88.53 / 170.16.
- Doc after: 6 of 184 matched, mean |dy| 15.8 to 3.0 pt.
- Left: that doc's remaining rows (wordcmp /data/s/amd-2/lab/c38n.txt); xb next: fas-z22832287-ac7399 (0 of 90; Vazirmatn embedded, 10.5pt rows step 22.8 Word vs 22.4 ours, to check).
