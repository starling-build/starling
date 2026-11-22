HANDOFF lenovo-5 (2026-11-22) ko-e114b968 p18 header height: NOT reproduced by labs 8 and 9, parked after 2 lab rounds.
- lab8 (plain multi-line cells, Arial/Malgun, 8/12 pt, regular/bold, 1-4 lines): ours within 0.05 pt of Word. No change.
- lab9 (rowSpan 2/3 and empty gridSpan cells over an h=0 row, rows 13.25/0/19.9, fontAlgn b on/off): header block bottom Word 79.5 = ours 79.48 in all 8 slides. Merged cells do NOT explain the p18 gap (Word 35.9 vs ours 33.6 pt in the real deck).
- Only lab9 residual: fontAlgn b on a 2-paragraph rowSpan-2 Malgun 8 pt cell, ours 0.2 pt high (Word 63.0/72.6, ours 62.8/72.4).
- Next idea for p18: the gap is in the deck, not the lab pattern: check wrapping (real text width in the 3-line "안전하다고 느껴진다" cell, a line that wraps in Word but not ours) or a cell font/size we resolve differently (theme font, inherited sz). Compare line counts per cell on p18 first.
- 5f748a0e p5 (claimed): the "（" start offset is a text-layer artifact (Word's char box is the right half of the full-width cell; pen positions agree), do not tune. Real gap: 14 pt lines in some cells are 0.97 pt higher in ours (others 0.00); not yet diagnosed.
