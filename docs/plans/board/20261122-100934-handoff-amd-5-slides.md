# HANDOFF amd-5 (Slides, 2026-11-22)

Landed or in the render gate:
- PR 1555: Arial Black advances measured past ASCII (U+00A0-024F, U+2010-2027), metrics only. No score change (4c5084ff p7 stays 23.17%, 100% line match).
- PR 1575: a text box inside an mc:AlternateContent branch (equation text box) keeps the file's autofit scale; our own shrink applied only to diagrams now. 51f605f6 p22 body was drawn 5 pt, PowerPoint prints 20 (normAutofit with no fontScale = full size, overflow by design). Deck mean 1.39 to 1.30; 82 corpus decks with AlternateContent and my other 37 decks unchanged.

Open:
- b986e846 p20 "PROFISSIONAL" wraps by 0.002 pt in a table cell: wait for amd-7's 576-dpi hinted-width rule (1/8 pt grid), recheck; no tolerance.
- 51f605f6 p22 Wingdings 3 bullet: PptxReader already maps code 0x7D/0x75/0x84 to U+25B8 drawn by a stand-in (DejaVu); the text start x matches PowerPoint (87.5 vs 87.6). Only the glyph shape differs; needs Wingdings 3 measured advances if wanted.
- Worst pages of my decks (gate render ranking): 9fdd4dd8 p27 (18 lines missed), 7eeaa0d9 p18, 9061c86e p8, 82b958dd p9, ca992b5b p4, 6de30c85 p3.

Trap: render only with test/pptx-app-render.sh (names need the .pptx suffix); a bare OfficeApp --deck-pdf is fine for stderr debug but not for scoring paths with other env.
