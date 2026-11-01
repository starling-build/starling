Lab fr2 -- where Word for Windows ends the lines beside a frame with borders (LibreOffice tdf154703, lo-60fd9368; Mac 7bd18d8e, 2026-11-01).
Background: the document's frame (w=1134 exact h=2268, hSpace 2552 = 127.6pt each side, borders sz 6 space 7, xAlign right to the margin)
sits at x 290.9..347.6 on a 419.6pt-wide page with 72pt margins. Our model ends the lines beside it at 290.9 - 127.6 = 163.3 (text width
91.3pt from the left margin). Word's print breaks 'not be | happening' on line 8 -- a line whose text ends at 154.7 -- so its limit is
between 153.3 (a line it kept) and 154.7: 9-10pt tighter than ours. Question: is the frame's border (sz + space) taken off the room, once
or on both sides, is hSpace taken from the frame's outer or inner edge, and what does it do with no border?
Method (v2, after windows' first print showed Word ignores a right indent beside the frame, and v1/v2 wrapped 'aaaaaaaaaaaaa b' at 156.0):
6 variants x 21 pages in ONE document, fr2.docx: a 30-'a' word, Courier New 10pt (glyph 6.0pt), character spacing 0..40 twips by 2
(pitch 6.0..8.0pt). The line holds n characters; the limit L satisfies x0+(n-1)p+6 <= L < x0+n*p+6; analyze.py intersects the brackets per
variant. Print fr2.docx to PDF with Word for Windows, then  analyze.py fr2.pdf > fr2.tsv  (needs PyMuPDF). Send fr2.tsv (it ends with L per variant).
Our own print is FR2-OURS.tsv (L 162.5..163.2 for v0-v3: our layout takes no border off the room).
