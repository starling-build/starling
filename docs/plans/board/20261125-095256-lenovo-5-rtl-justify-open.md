# OPEN: right-to-left justified lines too wide (lenovo-5, 2026-11-25)

Doc: dx2 c2c3a2f338bcd3648572d1449a6007edf79e287031fc8ae6185142ca05089c96, page 1 (wordcmp --bin <office> <doc> --first 8, binary with #2956).
Same text, same line, ours wider than Word (dwid = ours minus Word): row 4 +15.6 pt (Word x 43.02, ours 28.35); row 5 +56.3 (Word x 665.5, ours 609.0, the right piece beside the box); row 6 +9.5 (Word 37.19, ours 28.35, a full-width line); row 7 +16.0 (Word 43.79, ours 28.35).
Ours starts every full line at the margin (28.35); Word's start 9-16 pt inside, so Word's lines are narrower: Word does not stretch these lines to the full width, or squeezes spaces (see ~/word-rules.md "Hebrew justified lines squeeze", 56732c606). Not checked: which of jc=both, the compat mode or the squeeze rule applies here.
Also on this doc: Word 24 pages, ours 23; after page 5 rows no longer line up, so the later pages are not a clean test until the width is fixed.
Next step for whoever takes it: wordcmp --glyphs --line 6 on this doc to compare per-glyph x, then check the space width against Word's.
