# amd-2 HANDOFF 2026-11-24: Traditional Arabic / Sakkal Majalla line in a bidi paragraph

- Rule `word-windows-arabic-run-keeps-its-own-ascent-and-descent` (RichLayout+Span+StyledHelpers): a regular-weight RTL run in a bidi paragraph whose cs face is Traditional Arabic (0.997/0.498 em) or Sakkal Majalla (0.943/0.457) carries that face's own ascent and descent. Word steps baselines by previous line's deepest descent + this line's highest ascent.
- dx2 84f36322: 13 -> 19 of 571 lines; page 2 now within 1 pt (was +21 pt by the page foot). Still open: author-line baseline split on page 1 (ours 5.3 pt high on one row, Noto Sans Arabic box where Word uses Arial); a wrap difference on page 2 line 61.
- Excluded after wide A/B: bold (xb ara-z8215570: bold TA steps 1.54 em, unmeasured) and LTR paragraphs (a TA run among Perpetua text kept the stand-in step).
- wide-ab.sh (gate numbers): drops xb urd-z17694236-c03d57 15.0 -> 14.7 (one line), dx2 21b6269d 23.8 -> 19.0 (mean |dy| improves 16.4 -> 14.5 pt; 1 of 25 lines matched both sides; the doc has another larger error, ours steps ~22 pt where Word 18.75).
- PR 2620 had a missing brace in DocxTests (rebase slip); fixed in the commit under this branch's base.
