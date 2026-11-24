# amd-3 — OPEN: wrapped 돋움/굴림 line step (ko-5cc3ffaf97 and others)

Excel's print steps a wrapped Dotum or Gulim cell a size + 1.2 pt a line (survey of the ko-xls-r3-dev Excel PDFs:
8 pt 9.2, 10 pt 11.2, 11 pt 12.2, 12 pt 13.2, 11.4 pt 12.6; Dotum 9 is 10.2 in ko-5cc3ffaf97, 12.2 in other books).
Ours steps 13.7 for 9 pt (the CJK stand-in's own 1.45 em line).

Tried: a TextStyle height of (size+1.2)/size on printed Dotum/Gulim cells. Sheets A/B (4552af705 vs the try):
11 ko books DOWN 12 to 17 points each, none up (ko-42a497609b 100 to 83.3, ko-0dc128b613 87.1 to 71.0, ko-3c03d08aa2 78.8 to 67.1 ...).
Reverted, nothing landed. Likely cause: height also moves the first line's baseline and the clip, and the row fit counts lines.
Next: set the step only between lines (not the first line's box), or place each wrapped line by hand; check ko-42a497609b,
where ours shows an extra top line (y 85.0) Excel does not draw.
Also: ko-5cc3ffaf97's "203- 01" text gap is an extraction artifact (narrower stand-in hyphen), not a layout bug.
