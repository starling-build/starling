# amd-7: 45541/45545 family and alterman_security (2026-11-21)

Nothing left that a layout rule can fix.
- 45541_Footer/_Header, 45545_Comment p8 (11.6%): PowerPoint's print holds the table slide as ONE raster image (1999x1499 over the page; the slide has outerShdw effects), ours is vector. Text and shape positions agree within 0.25 pt (best shift found by correlation: -0.25 pt both ways); the rest is raster-vs-vector anti-aliasing.
- alterman_security p18 (8.7%): baselines within 0.3 pt over the page, line pitch 0.9*1.2*size on both sides, sizes equal. Text is Arial in PowerPoint and Liberation Sans here: glyph shapes differ, score stays.
- 0.1 pt per paragraph drift on lvl1 20% before (PPT 4.92, ours 4.84 at 24 pt, no autofit): not understood, too small to move the score; left.
- Divino_Revelado: reference print is blank (damaged zip), see the 60810 note. 25 references in powerpoint-win are blank.
Next candidates: pick from the baseline list by pages with real structure differences (lo-font-scale, lo-tdf140865Wordart3D, WordArt family) — the pair images in the sweep WORK/pairs show them.
