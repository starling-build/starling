# Word: a whole section in vertical writing (`sectPr/w:textDirection tbRl`)

Planner: amd-opus, 2026-11-10, for starling-bd. Builder: lenovo-5. This is a
spec only. Every number below was read from Word for Windows' prints in
`/data/corpus-cache/staging/dx2/word-win/` with pymupdf (rawdict origins,
plus ink from 8x renders), on office 496c4bfbe.

## 0. Today

Three dx2 Japanese documents set their whole section vertical, and no
document in 756, lo, xb, xa, xd or xs does. We read the setting and ignore
it, so all three come out horizontal:

| doc | grid (docGrid) | contents | Word pages / ours | v2 today |
|---|---|---|---|---|
| ee0b468e | linesAndChars, linePitch 326, compat 11 | one page of haiku, 12 ruby, exact 13 pt lines | 1 / 2 | 0.0 |
| 934bd3e5 | lines, linePitch 360, Meiryo | 15 pages, 6 continuous sections (all tbRl), 92 ruby, 16 tables, 8 drawings, footer page number | 15 / 14 | 3.3 |
| 4427518d | snapToChars, linePitch 671, charSpace 44083 | an 11-page story, MS Mincho, header page number | 11 / 5 | 3.8 |

**The scorer cannot see these pages either.** Word's PDF writes each upright
character as its own glyph (direction (1,0)), one under the next, so v2 reads
ee0b468e as 649 one-character "lines". That is why phase 0 below is the
scorer.

## 1. What Word does (measured)

1. **The page is not turned.** The PDF page is the pgSz landscape page
   (842 x 595.3, rotation 0). The margins stay physical: top and bottom
   bound each column's length, and left and right bound the run of columns.
   4427518d (all margins 85.05): text area 671.8 wide and 425.2 tall. It
   holds 20 columns of 20 characters: 20 x 33.55 = 671 and 20 x 21.26 = 425.
2. **Columns run right to left.** The first column sits at the right margin,
   and the next page starts when the columns reach the left margin.
   Paragraph "before" spacing is on the right of a column, left indent is
   at its top, right indent at its foot, and a first-line indent pushes the
   first column down (4427518d firstLineChars=100: one 21.26 cell).
3. **The grid carries over unchanged.** linePitch becomes the column pitch
   (33.55 in 4427518d). For snapToChars, the character cell down the column
   is font size + charSpace/4096 = 10.5 + 10.76 = 21.26 (measured 21.2-21.4).
   Line heights snap to the pitch as in horizontal text: 934bd3e5's Meiryo
   lines on an 18 pt grid take 36 (presumably the horizontal rule; lab 1
   checks it). Exact spacing makes columns narrower
   than the pitch (ee0b468e: 12.3 and 13.9 gaps at exact 13).
4. **An upright character sits centred in its cell both ways.** Across:
   em-box centre 740.25 against the column centre 740.1 (4427518d, first
   column; second 706.55 against 706.6). Down: em centre 95.83 against cell
   centre 95.69. The charSpace extra is split half above and half below
   (MS Mincho ascent .859, descent .141).
5. **What stands upright and what turns.** Upright: ideographs, kana,
   full-width forms (full-width digits １２ and ．), and CJK punctuation.
   Turned a quarter clockwise (direction (0,1)): spaces (including U+3000
   in the text layer), Latin text, and in 934bd3e5 all 34 of its "…" and
   "→". A turned run's em box is centred across the column too: its
   baseline sits at x 736.4 in a column centred at 740.1, and
   736.4 - 1.48 to 736.4 + 9.0 is centred.
6. **Punctuation takes its vertical form.** MS Mincho 10.5 in 4427518d
   (clean cells, 2 em apart): the ink of 。 is at x .68-.93 em and
   y .07-.32 em, and 、 at .70-.92 and .08-.29, both in the top-right
   corner. ー is a tall bar (x .42-.54, y .12-.92). That is the Japanese
   vertical alternate, and it is not the Chinese placement: our
   `_verticalFormDrop` (YaHei, zh) moves 、 down .56 em. The text layer
   keeps the horizontal code point (U+3001, not U+FE11). The Meiryo
   readings in 934bd3e5 are blurred by neighbouring glyphs and need lab 3.
7. **Ruby goes on the right of its base.** 934bd3e5 十訓抄 / じっきんしょう:
   the base centre is at 722.95 and the 5 pt ruby centre at 731.8. A base
   shorter than its ruby is spread to the ruby's length: three base
   characters over 35 pt, 11.7 apart.
8. **Headers and footers stay horizontal and physical.** 4427518d's page
   number (Century 11) is set across at the left margin, with its top at
   the header distance (70.9). 934bd3e5's footer "1" is set across near the
   bottom centre (baseline 523.2; footer distance 49.6).
9. **Tables and drawings are not settled.** 934bd3e5 pages 10-12 hold a
   two-column table (gridCols 1400/2848 = 212 pt). Its box is 211 wide in x
   and the full 425 column length in y. The text in its cells runs upright
   down the page, and it has horizontal rules about 19 pt apart. That fits
   neither "the table turned with the text" nor "the table kept across" in
   any way I could check from the print. Lab 8 decides it.

## 2. The model

- `PageSetup` gets `vertical: Bool`, true for `tbRl` and `tbRlV`. Docx
  reads `sectPr/w:textDirection` into each section's setup (`_sectionSetups`
  in RichLayout.swift) and writes it back.
- `btLr`, `lrTbV` and `tbLrV` are kept for writing back but laid out
  across, with a `RuleTrace.hit("word-section-direction-unsupported")`
  so they can be found.
- `test/tools/docx-features.py` gets `section_vertical` (count of vertical
  sectPrs), so `docx-select.py 'section_vertical > 0'` finds every document
  a change can reach.

## 3. Layout and paint

**Lay out in a transposed frame.** For a vertical section, lay the body
out with the page setup turned a quarter: `PageSetup.transposed()` gives
width' = height, height' = width, marginLeft' = marginTop,
marginRight' = marginBottom, marginTop' = marginRight and
marginBottom' = marginLeft. The existing `rotated()` only swaps width and
height, so it is not enough.

All of the line, grid, squeeze, kinsoku, indent and pagination code then
runs unchanged. A "line" is a column, the line length is the column length,
and "page height" is the run of columns. Facts 1-3 are exactly what the
horizontal code already does in that frame. Lab 1 checks that claim.

**Paint each vertical body piece turned.** Wrap each piece in
`canvas.save()`, `translate(pageWidth - marginRight, marginTop)`,
`rotate(π/2)` and `restore()`. This is the transform a `vert` text box
already uses (`RichLayout+HeaderFooter.swift`, the `.down` case near line
322). Inside it, each line goes through the existing upright painter
`_paintUpright(..., mixed: true)` (`RichLayout+Layout.swift:1160`), which
cells (`uprightIdeographs`) and `eaVert` boxes already use. That painter
stands ideographs up one by one and leaves the rest on its side on its
baseline, which are facts 4 and 5. Two changes go into it:

- **centring:** each upright glyph's em box is centred in its character cell
  down the column, so a grid's charSpace splits both sides (fact 4). Across,
  it centres on the line box, which the painter already does;
- **classification:** a fixed table of what stands upright (fact 5 and
  lab 4), in place of today's test `u >= 0x2E80`, which puts …, → and
  half-width katakana on the wrong side.

**Vertical forms.** For Japanese text (lang ja-JP, or a Japanese face in
the eastAsia slot), apply the face's OpenType `vert` feature through
`TextStyle.fontFeatures`, which the engine already passes through. The
bundled Noto CJK faces have it. Use the JP face of the .ttc so the
placements are Japanese (fact 6). Keep the FE10-FE44 table and
`_verticalFormDrop` for Chinese, as measured. ー, small kana and 〜 come
from `vert` too. Word turns … and → instead (fact 5).

**Ruby (fact 7).** In the turned frame, the ruby sits "above" the base,
which is the right side once painted. The spread-base rule is already
horizontal behaviour, so only check it.

**Headers and footers** are laid out with the physical setup, untransposed,
as today (fact 8). They need no change, only a check.

**Anything that reads the physical page** must use the untransposed setup:
positionH/V relative to the page or margin, page borders, line numbers,
header wrap (`_headerWrapLeft`) and the page size the PDF writer gets.
Audit every `pageSetup.width`/`.height` read in RichLayout+Paginate.swift
and RichLayout+Layout.swift. Anchored drawings need their physical
rectangle mapped into the flow frame before wrapping. That is phase 4.

**The editor** (caret, selection, hit testing) maps the pointer through the
inverse transform, as turned cells do (`verticalNeighbour`). It is not
needed for print fidelity and is phase 5.

## 4. Phases (each one lands through land.sh)

Pair with `SETS="756 lo xb xa xd xs dx2"`, because the three documents are
only in dx2. Check that land.sh passes SETS through first. Each phase must
leave every document outside the three level, and the three must not drop.

- **P0, scorer** (`test/docx-line-match.py`, v2; no app change). A page is
  vertical when most of its text glyphs stack: the same origin x, y
  growing, one glyph to an item. On such a page, group glyphs into columns
  by em-centre x (within 0.3 em, upright and turned glyphs alike), order the
  columns right to left, and score each column as a line: same page, x
  within 3 pt, same starting text. Horizontal runs on the same page (the
  header and footer) keep today's grouping. Gates: every score in the
  seven sets is unchanged except the three; and Word's print scored against
  itself gives 100 for each of the three. Rescore dx2 and post the three
  new baselines.
- **P1, model and transposed layout, painted turned whole.** Lay out as
  above, but paint whole lines turned (as `vert`, without the upright
  pass). Expected: page counts 1, 15 and 11, and columns starting where
  Word's do. Even turned sideways, the column starts should already raise
  the three under P0.
- **P2, upright pass and centring (facts 4-5, labs 2 and 4).** Expect
  4427518d close to 100: it is plain text on a character grid.
- **P3, vertical forms, ruby and compressPunctuation in vertical
  (facts 6-7, labs 3 and 5).**
- **P4, tables, drawings and notes in a vertical section (lab 8;
  934bd3e5's 16 tables and 8 drawings).** Plus the mixed continuous
  sections of lab 7.
- **P5 (optional; starling-bd decides), editor support.**

## 5. Labs for Word to print (session `windows`)

Build them with `test/lab/vsec/mklab.py`. Each lab gets a settings.xml
(compat 15 unless stated) and a styles.xml: a lab without either never
reaches our squeeze path. Pages are A4 landscape unless stated, MS Mincho
10.5, and every paragraph starts with a marker word so lines can be paired
by text.

1. **vsec-twin**: the three dx2 documents with only the sectPr
   `textDirection` removed. Decides whether the column pitches, wraps and
   page breaks equal the horizontal twin's lines. This is the claim behind
   the transposed frame. Compare column i with line i.
2. **vsec-grid**: one 200-ideograph paragraph, 10 variants: grid none;
   lines 360; linesAndChars 360 with charSpace 0 and with -2048;
   snapToChars 671 / 44083; each at compat 15, and the last three also at
   compat 11. Decides the column pitch, cell centring both ways, and
   characters per column.
3. **vsec-punct**: each mark alone between two 漢, with charSpace giving a
   2 em cell so ink never touches: 、。，．「」『』（）【】〔〕ー〜…‥―—・：；！？,
   ぁぃぅぇぉっゃゅょゎ, ァィゥェォッャュョヵヶ. One paragraph each in
   MS Mincho, MS Gothic, Yu Mincho, Yu Gothic and Meiryo (ja-JP), plus the
   same line in SimSun and Microsoft YaHei (zh-CN) and PMingLiU (zh-TW).
   Decides the vertical form and ink place per face and language.
4. **vsec-mixed**: Latin words; ASCII digits "5", "12" and "2019";
   full-width digits; half-width katakana; ASCII ( ) - / , and a URL; in
   Century and Times New Roman; "12" and "2019" also in tate-chu-yoko
   (`eastAsianLayout vert="1"`); one ASCII run with `w:hint="eastAsia"`.
   Decides upright against turned, and where a turned run sits across the
   column.
5. **vsec-para**: jc left, center, right, both and distribute; ind left,
   right, firstLineChars and hangingChars; spacing before and after of
   6 and 12 pt; exact 13 pt and atLeast 24 pt lines; a tab stop at 100 pt
   with a dot leader; compressPunctuation on and off. Decides how each
   paragraph property maps onto columns.
6. **vsec-hf**: header text left, centre and right; PAGE centred in the
   footer; titlePg; evenAndOddHeaders; a header paragraph with its own
   textDirection tbRl; landscape and portrait. Confirms fact 8.
7. **vsec-flow**: 3 pages with a page break; cols=2 with a column break
   (do section columns become top and bottom bands?); a continuous break
   from vertical to horizontal on one page; a next-page break to a portrait
   vertical section; widow control on. Decides pagination and mixed
   sections.
8. **vsec-objects**: an inline picture; the 934bd3e5 table (gridCols
   1400/2848, two rows); a floating table (tblpPr); a square-wrapped
   picture anchored relative to the page and one relative to the margin; a
   footnote; ruby with a base shorter than its ruby and one longer; a
   single underline; an emphasis dot. Decides fact 9, float coordinates,
   where notes go, the ruby side, and which side underlines are drawn on.

## 6. Risks

- **The scorer.** Column grouping must not touch any horizontal page.
  P0's gate is byte-identical score lines for everything else. Our own PDF
  writes a spacer glyph after each space, and the grouping must ignore it.
- **Stand-in faces.** Noto CJK's vertical alternates are not MS Mincho's
  or Meiryo's in ink. The .ttc face index decides JP against SC
  placements. Some punctuation may need per-face offsets like
  `_verticalFormDrop`, which only lab 3 can give.
- **Speed.** The upright painter makes one TextPainter per glyph. That is
  fine for a cell, but a vertical page has 400-1,000 glyphs. Time
  4427518d's 11 pages, and cache a painter per (style, glyph) if it is slow.
- **The physical page against the flow frame.** Any read of the page size
  missed in the audit puts things in the wrong place without any error.
  Floats (P4) are the largest unknown, and 934bd3e5 needs them.
- **Mixed directions on one page** (a continuous break from vertical to
  horizontal): Word's behaviour is unknown. Until lab 7, start such a
  section on a new page and trace it.
- **Compat 11** (ee0b468e) may grid differently. Lab 2's compat-11
  variants cover it.
- **Wasm.** No Foundation-only string APIs in the new code
  (containsSubstring, OfficeLock).
- **Round trip.** Writing a vertical section back must keep
  `w:textDirection` on sectPr. Check a save and reload of each of the three.
