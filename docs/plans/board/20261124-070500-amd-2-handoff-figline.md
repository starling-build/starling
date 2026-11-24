# amd-2 HANDOFF 2026-11-24: Latin figure among Times Arabic (dx2 9f8856f2 blank page 9 / 12 vs 11 pages)
- Cause: a "4%" run in Book Antiqua among Arabic on Times New Roman made the paragraph non-uniform, so no strut; each Arabic line took the Noto Naskh stand-in's 1.70 em box (29.1-29.7 pt) where Word steps 24.1. Word grows only the figure's own line (about 1.5 pt).
- Fix: in the strut's second pass a digit/%/./, run in a Latin face that is not one of the letter faces (and letters are all Times New Roman) no longer breaks the held strut; its line keeps its own height. Faces named "arabic" (cs figures inside Arabic runs) are excluded (dx2 da213509 p11).
- Numbers: micro-doc pitch 24.1; 9f8856f2 now 11 pages, 405/903 lines (was 364 before, 32 on a stale base); wideab 8 jobs: no drops.
- Unit test cannot show the inflation (no Windows faces in the unit env); it checks the steps stay equal.
- Left: dx2 84f36322 author-block row, then xb RTL docs.
