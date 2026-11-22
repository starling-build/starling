# lenovo-5 HANDOFF: Slides table row pitch by face (lab tbl-rows3)

- Lab tbl-rows3 (30 faces, 12 pt, 100% and 130%, Word print in lab/tbl-rows/word-win/lab3-orig.pdf, not in git):
  at 100% EVERY face pitches 1.2 em (MS Gothic, Meiryo, Lucida too). The hhea/typo/win sum does NOT set row pitch.
- Above 100% the first line's loss k = max(0, 0.3 - 1.2 x winDescent/(winAscent+winDescent)); 27 faces fit within 0.002 em
  (Arial .072, TNR .065, Calibri .036, Verdana .092, MS Gothic .13, Meiryo and Courier 0). Calibri 1.2207 was a 107% reading.
- Code: SlideFonts.windowsDescentShare (table from measured metrics), PptxReader sets cellDescentShare (larger of text face and end mark face), RichLayout+Layout uses it.
- Result: lab3 60 pages within 0.06 pt except Consolas (measured later: share 0.2143, now within 0.06), lab2 within 0.1, d8e0c8b2 p10 13.58 -> 5.62.
- OPEN: Century Gothic and Segoe UI Semibold have no metrics file (default Arial; Century Gothic happens to fit). Meiryo 11/14/18 pt at 115% is 0.5 to 0.8 pt short (gain 1.98 at 11 pt, linear elsewhere); older gap.
- OPEN: which face governs a CJK line (latin vs ea) in real decks: lab with Arial latin + MS Gothic ea, Calibri + Meiryo ea at 130%.
- Local commit only; PR held by the slow-down order.
