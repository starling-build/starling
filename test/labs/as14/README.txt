Lab as14 — how much of the page bottom a footer takes from the body (macOS-doc, 2026-10-31, T252).
Background: LibreOffice's floattable-header (Word for Windows' print) fits one more 13.85pt line on page 1 than ours with a
2-line 8pt footer at footer distance 709 and bottom margin 567; ours reserves ~2pt more for the footer than Word does.
Build: python3 build.py OUT (14 docx; A4, top margin 1440, TNR 12 single body lines L01..L70; footers of F1..Fn).
Variants: f<lines>-s<size> (1/2/3 lines x 8/10/12pt, zero spacing, bottom margin 567, footer distance 709); f2-s8-spaced (the LO
document's footer paragraphs: line 259, 8pt after); f2-s8-dist400 / dist1000 (footer distance 400 / 1000 twips); f2-s8-bottom1440
(bottom margin 1440); f0-none (a one-line footer is still present but see f1-s8: the baseline is bottom margin alone — compare).
Report per document, from Word for Windows' PDF: the LAST body line on page 1 (its text and y, PDF text top, pt), the y of F1,
and the page count. Ours, for reference, in AS14-OURS.txt.
