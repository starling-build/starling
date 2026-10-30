Lab frame (asked of `windows`; kit by Linux office1, 2026-10-30; subject: lo tdf147485-forcepoint, lo-e8c1ae371214f133)

Question: where does Word for Windows stand an inline drawing held by a page-anchored, exact-height frame?
The original: one paragraph with <w:framePr w=9851 h=1669 hRule=exact x=1418 y=996 vAnchor=page hAnchor=page wrap=notBeside>, holding a wp:inline
group (136.45 x 88.45pt, effectExtent l=r=9pt) — its picture's own lines are WordArt text on an arch. Page: Letter, top margin 540 twips (27pt),
left 1800, header/footer 0. Word's print of it has the drawn shapes' union at x 70.8..207.3, y 22.8..111.2; the frame says x 70.9, y 49.8 — the
group stands 27.0pt ABOVE the frame's y (the page's top margin, 27pt) and starts at the frame's x with none of the 9pt effect extent (ours: 79.9, 49.8).

Kit: `python3 build.py` writes docx/ (20 documents; each changes ONE thing from v00 except the controls c1-c3, which drop the frame).
 v01-02  frame height 1000 / 2400 twips, exact        v03-04  hRule atLeast (1669 / 1000)
 v05-07  frame y 1500 / 2400 / 400                     v08-10  top margin 1440 / 0 / (1440 with y 2400)
 v11-13  drawing height x0.5 / x1.6 / x0.5 with frame h 1000
 v14-16  effectExtent l=r 0 / 228600, frame x 2000     c1-c3   no frame (flow), top margin 1440, effectExtent 0
Run: print each docx in Word for Windows to PDF (page 1), then `python3 meas.py *.pdf`: the union of the drawn shapes, and the first text lines.
Read: y0 and x0 against the frame's y and x, the page's top margin, the drawing's height; v00 is the control (must print x 70.8, y 22.8).
Pending questions it should answer: is "27pt above" the top margin, the effect extent, the frame's own height minus the drawing's, or the line's
baseline; and the 9pt: whether the effect extent is ignored for a framed inline drawing.
