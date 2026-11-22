# lenovo-5 HANDOFF: Slides table rules rebased on main (supersedes #1536)
- Carries: row floor for rowSpan continuation rows (2.0 pt + start-cell top margin, labs 12-14), MS PGothic table glyph box, tall-row anchor trim (first line only), fontAlgn t/ctr/b glyph box (lab tbl-rows7), spanning-cell trim per paragraph.
- Overlap with amd-perf #1573 (fontAlgn ctr = full first line, cellFullFirstLine): both kept; mine adds a baseline drop (cellFontAlignDrop) for t/ctr/b. Row height for ctr follows #1573; the drop only moves the baseline.
- Scores (4 decks, vs round main): 5c820695 95.9 = 95.9, ko-4f5289a9 96.1 = 96.1, ko-ca2dc787 97.8 = 97.8, ko-e114b968 95.4 to 95.8. Unit tests 846, 0 failures.
- Correction: the earlier handoff claim that bold Hangul is narrower was wrong; advances are 8.0 pt.
- OPEN: lab11 "(명)" bracket hang belongs to lenovo-3; lab11 c3 wrap ("안전하다 / 고 / 느껴진다" in Word); fontAlgn b on multi-paragraph merged cell 0.2 pt high.
