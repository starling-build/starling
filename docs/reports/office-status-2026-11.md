# Starling Office: status report, November 2026

Writer, Slides and Sheets, measured on 2026-11-26 at main `d10a5afda`.

Every number below was measured for this report or is quoted from a file
that is named beside it. Where something was not measured, section 5 says
so. No document text appears here: documents are named by id and score only.

## Summary

| | Corpus scored | Starling | LibreOffice 26.2 |
|---|---|---|---|
| Writer: share of Word's lines set in the same place, mean per document | 3,980 documents, 9 sets | **93.9%** | 48.6% |
| Writer: documents at 95% or more | 3,980 | **3,354** | 1,232 |
| Slides: combined score against PowerPoint, mean per deck | 552 decks | **98.1** | 77.8 |
| Sheets: share of Excel's lines set in the same place, mean per book | 682 books | **94.6%** | 62.7% |
| Sheets: pixels differing from Excel's print, mean per book | 710 books | **0.64%** | 4.41% |

Both suites ran on the same Linux machine, with the same open fonts and no
Microsoft fonts, over the same files, and were scored by the same scorer
against the same prints from Word, PowerPoint and Excel (section 4).

Other headline facts:

1. The editing-UI round (2026-11-24 to 26) landed all 13 "an edit or a save
   destroys data" items of the plan and 103 further plan items (section 3.3).
2. A save with no edit still drops parts of a file. The save-loss sweep
   counts them by name (section 3.4).
3. The browser build draws the same pages as the native build on 45 of 70
   sampled files (section 2).
4. The weakest area in Writer is right-to-left and Thai text: 73.0 on 256
   right-to-left documents, 70.4 on 56 Thai documents (section 3.5).

## 1. Approach

Starling Office does not render by its own layout model and then accept the
result. The target is the page that Microsoft Office itself prints. A real
document is printed by Word, PowerPoint or Excel on Windows, and our render
of the same file is compared with that print line by line and pixel by
pixel. A difference is a bug in our layout, and the fix is a rule that
states what Office does, checked against a lab file printed by Office.

The pieces:

- **Reference prints.** Each corpus file has a PDF printed by the Office
  application on Windows. The corpus and the prints are kept out of git.
- **Line scorer** (`test/docx-line-match.py`, rule v2). It reads the glyphs
  of both PDFs. A line of the reference is matched when our render has a
  line on the same page, within 3 pt of its height, that starts or ends with
  the same four characters. A document's score is the share of the
  reference's lines that are matched. The same rule scores Slides
  (`test/pptx-line-match.py`) and Sheets (`test/tools/sheets-sweep.py`).
- **Pixel scorer** (`test/pdf-diff.py`). It gives the share of pixels that
  differ per page. Slides and Sheets use it on every page. Writer uses it
  for documents whose print has no text lines (the "combined" score).
- **Render gate** (`test/tools/render-gate.sh`). Every pull request is built
  and rendered on a runner. A document whose score drops blocks the merge,
  unless the drop was approved by document id. The gate has Word, Slides
  (`slides-gate.sh`) and Sheets (`sheets-gate.sh`) steps.
- **Wide A/B** (`~/bin/wide-ab.sh`). The same comparison over every full
  set, base commit against head commit, with the gate's build, engine,
  fonts and scorer. Hourly rounds run it on main and bisect any drop to the
  pull request that caused it.
- **Save-loss sweep** (`test/tools/edit-loss-sweep.sh`). It saves every
  corpus file with no edit and with one small edit, and lists what the
  saved file lacks, by XML element and attribute name.
- **Office open checks.** Files saved by our editor are opened in Word,
  PowerPoint and Excel on the Windows machine.
- **Rules for the work.** A rule is stated by a document property, never by
  a document name. No tolerance is added to win a score. Text that Office
  does not draw is never emitted to raise a score. A separate held-out set
  is never used in development. Microsoft fonts are used as metrics only,
  never as font files.

This differs from other open-source suites, which lay a document out by
their own model and treat Office's result as one of several acceptable
ones. Section 4 measures what that difference is worth on real files.

## 2. Goal: the same page everywhere

The goal is that a document renders identically on macOS, Linux, iPad and
in the browser. One layout engine and one set of bundled fonts and font
metrics run on all four, so a page does not depend on the fonts a machine
happens to have.

What is measured today:

**Browser against native** (audit of 2026-11-25, `docs/plans/web-parity.md`).
Each sampled file was exported to PDF by the native build and by the
browser build, and the pages were compared pixel by pixel.

| App | Files | Pixel-identical |
|---|---|---|
| Writer | 30 | 11 |
| Slides | 20 | 16 (15 before the fix in `d10a5afda`) |
| Sheets | 20 | 18 |

Of the 19 Writer files that differ, 14 are Chinese documents with the same
line breaks but another font face (8 to 16% of pixels on the worst page).
Printing, Save As, autosave, recovery copies, recent files and publishing
are not available in the browser build yet.

**iPad.** The audit of 2026-11-24 (`docs/plans/ipad-first-week-audit.md`)
ran on an iPad Pro 13-inch simulator: open, edit, AutoSave, find, insert
table, slide show, print, Save As, export and Sheets formulas work.
Long-press, pinch, a hardware keyboard, the Files picker and an external
display were not tested on a real device.

**macOS against Linux.** Not measured at one commit for this report (see
section 5). The last committed scores are from different commits and
dates, so they cannot be put side by side.

## 3. Status

### 3.1 Corpus

| App | Scored for this report | Reference |
|---|---|---|
| Writer | 3,980 documents in 9 sets | Word for Windows prints |
| Slides | 555 decks (the gate set) | PowerPoint for Windows prints |
| Sheets | 755 books (the gate set) | Excel for Windows prints |

The Writer sets: `756` (645 Chinese documents and 111 from Apache POI's
tests), `lo` (593 of LibreOffice core's own Writer test documents), `xa`,
`xb`, `xd`, `xs`, `sa1`, `sa2` (109 to 188 documents each) and `dx2`
(1,798 documents in many languages). More evaluation sets exist (legacy
`.doc`, `.ppt` and `.xls` folders and further language folders); they were
not scored for this report.

### 3.2 Scores at main `d10a5afda`

Writer, combined score (lines, or pixels where the print has no text),
swept with `test/tools/docx-pair.sh --seed`, 0 failed renders:

| Set | Documents | Mean | At 95% or more | Word's page count |
|---|---|---|---|---|
| 756 | 756 | 99.5 | 743 | 745 of 746 |
| lo | 593 | 99.1 | 577 | 545 of 551 |
| sa2 | 128 | 98.3 | 118 | 128 of 128 |
| sa1 | 159 | 97.0 | 137 | 157 of 159 |
| xs | 130 | 95.0 | 113 | 128 of 130 |
| dx2 | 1,798 | 90.7 | 1,401 | 1,759 of 1,796 |
| xa | 109 | 88.3 | 73 | 101 of 109 |
| xb | 188 | 88.1 | 137 | 185 of 188 |
| xd | 119 | 85.2 | 55 | 112 of 119 |
| All | 3,980 | 93.9 | 3,354 | |

(The page-count column counts documents whose print has text lines.)

Counted by line instead of by document: Word's prints of these documents
hold 821,584 lines, and Starling sets 91.5% of them in the same place.

For the trend: the hourly round of 2026-11-20 posted dx2 at 87.9 and xd at
76.7 (`docs/plans/board/20261120-125151-amd-8.md`); today they are 90.7 and
85.2.

Slides, 555 decks, the gate's sweep (`test/pptx-app-render.sh`, then the
line and combined scorers): combined mean **97.54**. 366 decks are scored by
text lines (mean 97.9), 186 by pixels (mean 98.3), 3 end in an error and 4
have prints that cannot be scored.

Sheets, 755 books, the gate's sweep (`test/tools/sheets-sweep.py`): 719
books printed, 36 more print nothing in Excel and nothing in Starling, and
none failed. Pixel mean **0.68%** differing. Line match **94.6%** over the
691 books with text, 567 of them at 95% or more. All 719 have Excel's page
count.

### 3.3 The editing-UI round

The plan is `docs/plans/office-ui-gaps.md` (2026-11-24): what each app
draws but cannot edit, ranked by how many corpus files use it. Since
2026-11-24, main has 385 commits that are not board entries.

- **Data-loss items (P0).** All 13 have landed: W-P0-1 to 5, S-P0-1 to 4,
  X-P0-1 to 4. Examples: resizing a Writer picture keeps its wrap, crop
  and rotation (`22d5475ba`); moving, resizing or typing in a Slides shape
  patches the file's own XML instead of rewriting the shape (`4f53c48b6`,
  `9976b2f9e`, `db0fbdaf4`); Sheets saves rich text inside cells
  (`0fec85ada`).
- **Further plan items landed**, counted by distinct plan id in commit
  subjects: Writer 36, Slides 23, Sheets 44. They cover table tools,
  paragraph and character dialogs, fields, footnotes and review in Writer;
  arrange, shapes, tables and masters in Slides; Format Cells, conditional
  formats, data tools, charts and print setup in Sheets.
- **Driver check.** A headless test harness drives the real widget tree on
  Linux with no window (`sdk/Sources/Flutter/Testing/WidgetTester.swift`,
  `09306246c`): taps, keys, typing, clicks and drags. 109 test files with
  619 test functions use it.
- **Unit tests.** The latest round figure is 1,923 tests, 20 skipped, 0
  failures on Linux at `9d150e24f` (2026-11-25 17:20,
  `/data/s/amd-8/unitwatch/results.tsv`). On 2026-11-14 the figure was 655.

Not confirmed as landed (commit subjects were checked, not the code):
picture bullets, legacy form fields, and refusing to resize objects that
are not pictures in Writer.

### 3.4 Save loss

The sweep (`test/tools/edit-loss-sweep.sh`) opens every corpus file in the
editor's model and saves it twice: once with no edit, and once after one
small edit. It then lists the XML element and attribute names that the
original has and the saved file lacks.

Full run at `d10a5afda`, 2026-11-26.

| | Writer (.docx) | Sheets (.xlsx) |
|---|---|---|
| Files | 775 | 810 |
| Could not be read or saved | 8 | 13 |
| Names lost by a save with no edit | 400 or more (the list is cut at 400) | 400 or more |
| Most common loss with no edit | bookmarks (554 files) | calculation chain (178 files) |
| Extra names lost by an edit | body text: 22 (most common in 39 files); table cell: 19 (most common in 22 files); header: 0 | cell value: 33; cell fill: 0 |

Before, in the full run on main of 2026-11-25: the most common Writer loss
was the latent style table (745 files), and an edit lost one extra name
(body text 39 files, table cell 8 files). The Sheets figures were the same
as now, within one file.

Reading it:

- The styles part and the numbering part no longer lose anything in the
  list. On 2026-11-25 they held 181 and 18 of the 400 listed names; now
  they hold none. The latent style table is kept.
- The plain save is still where most of the loss is. In the document body
  it still drops bookmarks (554 files; dropping `_GoBack` and duplicate
  names is intended, `docs/plans/board/20261125-093954-amd-5.md`), and it
  still counts fewer run font elements in 494 files (508 before) and fewer
  colour elements in 346 files (349 before). The same save writes fewer
  runs in 522 files, so part of that is runs being merged, not formatting
  being dropped. The sweep does not separate the two.
- An edit now loses more beyond the plain save than it did: in a body edit,
  bold-off marks (39 files), complex-script bold (30), colour (27),
  character spacing (14) and highlight (10); in a table cell edit, colour
  (22), complex-script size (13) and highlight (8). The edited run is
  rewritten from the model, and the run around it is now kept as it was, so
  the difference shows up here.
- Excel's calculation chain is a part Excel rebuilds by itself. The count
  of names overstates the loss a reader would see.

The sweep does not cover `.pptx`. There is no total yet of files that lose
something a reader would see.

### 3.5 Known gaps

Writer, from the scores of section 3.2 grouped by document property
(`test/tools/docx-features.py`):

| Property | Documents | Starling mean |
|---|---|---|
| Arabic script | 171 | 69.4 |
| Thai script | 56 | 70.4 |
| Hebrew script | 56 | 71.8 |
| Right-to-left paragraphs | 256 | 73.0 |
| Equations | 48 | 86.7 |
| Endnotes | 156 | 87.1 |
| WordArt | 55 | 89.1 |
| Footnotes | 327 | 89.2 |
| Content controls | 201 | 89.8 |

The WordArt row first read 300 documents at 89.5: the tool counted every
text box as WordArt (the plain `textNoShape` warp each one carries). Corrected
2026-11-27; no other row changed. The 55 are nearly all text watermarks,
which Starling draws as Word does; their low scores come from other causes.

Every other property measured sits at 90 or above. Open items on the board
(`docs/plans/board/`), each with a measured cause or lab data:

- Right-to-left justified lines come out 9.5 to 56.3 pt too wide
  (`20261125-095256-lenovo-5-rtl-justify-open.md`).
- Vertical Japanese pages with floating boxes: lines are painted twice
  around the picture (`20261124-190528-lenovo-5.md`).
- Autofit tables whose columns ask for more than the text width
  (`20261124-130603-amd-5-e3tbl2-data.md`).
- Floating shapes anchored to a paragraph that a full-width picture pushes
  down (`20261124-130317-amd-1.md`).
- Kashida justification (`docs/plans/kashida.md`) and automatic hyphenation
  are not done.

Slides:

- Legacy `.ppt`: a reader is being built; pictures, tables, notes and
  gradient fills are not read yet (`20261124-160443-amd-9.md`).
- Thai decks: mean 52.4 over 12 decks in the multi-language folders
  (`20261124-130000-amd-8.md`).
- Treemap and box-and-whisker charts (`20261122-075000-amd-10.md`).
- Video, audio, morph, motion paths and ink are listed as not supported in
  `docs/plans/office-overview.md` (2026-10-18; not rechecked for this report).

Sheets:

- Legacy `.xls`: opening landed in the UI round (`846cf5a5a`); 98 of 100
  `.xls` books failed before it (`20261122-230448-amd-8.md`) and the set
  has not been scored since.
- Row heights for some fonts (Verdana 10: Excel 12.6 pt, ours 12.96), so
  pages break early (`20261122-192824-amd-5.md`).
- Wrapped lines in Dotum and Gulim cells
  (`20261124-120500-amd-3-dotum-wrap-pitch-open.md`).
- Indic shaping in print (`20261123-040930-amd-2.md`).
- Pivot tables, sparklines and slicers are listed as not supported in
  `docs/plans/office-overview.md` (2026-10-18; not rechecked for this report).

## 4. Comparison with LibreOffice

### 4.1 Method

- LibreOffice **26.2.7.3** from Ubuntu's packages (`libreoffice-writer-nogui`,
  `-impress-nogui`, `-calc-nogui`), run headless on the same machine:
  `soffice --headless --convert-to pdf`, one process and one fresh profile
  per file.
- **Same files.** Every file of the sets in section 3.1 that has an Office
  print. Nothing was sampled.
- **Same references and same scorer.** LibreOffice's PDFs were put where
  the gate's scorers expect ours and scored by the same scripts at the same
  commit. For Slides and Sheets a small wrapper gave LibreOffice the
  command line of our converter, so the gate's own sweeps ran unchanged.
- **Same fonts.** Neither side has Microsoft fonts. LibreOffice was given
  the system fonts plus the same open font files Starling bundles
  (Liberation, Carlito, Caladea, Noto CJK and the others), through a
  fontconfig file.
- **Same limits.** 300 s per file for both. Sheets PDFs are cut to the
  first 20 pages for both. A file LibreOffice failed to convert counts as
  0 in Writer and Slides and is left out in Sheets (the tables say which).

The scorer measures one thing: whether the page is the page Office prints.
LibreOffice does not aim at that, so these numbers are not a judgment of
LibreOffice as a suite. They measure the cost of rendering by one's own
model when the reader expects Office's page.

### 4.2 Writer

Combined score, mean per document:

| Set | Documents | Starling | LibreOffice | At 95%+: Starling | LibreOffice | Word's page count: Starling | LibreOffice |
|---|---|---|---|---|---|---|---|
| 756 | 756 | 99.5 | 25.6 | 743 | 84 | 745 | 296 |
| lo | 593 | 99.1 | 73.0 | 577 | 351 | 545 | 512 |
| sa2 | 128 | 98.3 | 64.9 | 118 | 53 | 128 | 109 |
| sa1 | 159 | 97.0 | 50.9 | 137 | 33 | 157 | 119 |
| xs | 130 | 95.0 | 55.1 | 113 | 47 | 128 | 108 |
| dx2 | 1,798 | 90.7 | 52.8 | 1,401 | 626 | 1,759 | 1,418 |
| xa | 109 | 88.3 | 50.7 | 73 | 24 | 101 | 72 |
| xb | 188 | 88.1 | 24.3 | 137 | 11 | 185 | 86 |
| xd | 119 | 85.2 | 18.3 | 55 | 3 | 112 | 30 |
| **All** | **3,980** | **93.9** | **48.6** | **3,354** | **1,232** | | |

LibreOffice did not convert 5 documents within 330 s (4 in `lo`, 1 in
`xb`); they count as 0.

Per document: Starling scores higher by more than 1 point on 2,756
documents, LibreOffice on 95, and 1,129 are within 1 point.

The `lo` set is LibreOffice's own Writer test documents. On those,
LibreOffice matches Word at 73.0 and Starling at 99.1.

**Fonts are part of the gap, and not all of it.** Starling carries the
metrics of the Windows fonts; LibreOffice substitutes a font and takes its
metrics. To separate that, take only the documents that are Latin-script
and name only fonts with a metric-compatible open replacement (Times New
Roman, Arial, Calibri, Cambria, Courier New and their open equivalents).
There are 811:

| Font-controlled group | Documents | Starling | LibreOffice |
|---|---|---|---|
| Mean score | 811 | 97.6 | 75.6 |
| At 95% or more | 811 | 763 | 506 |
| Higher by more than 1 point | 811 | 309 | 24 |
| Plain documents (no tables, drawings, notes, columns or grid) | 345 | 99.0 | 82.0 |

So with the font question removed, LibreOffice still sets about a quarter
of Word's lines somewhere else.

**What kind of miss.** For each of Word's lines that a render does not
match, the same text is either a line on the same page more than 3 pt away,
a line on another page, or not a line at all (the paragraph broke at other
words). As a share of all of Word's lines:

| | Lines | Broke at other words | On another page | Same page, over 3 pt off |
|---|---|---|---|---|
| Starling, all sets | 821,584 | 2.4% | 0.9% | 5.2% |
| LibreOffice, all sets | 821,186 | 29.8% | 21.4% | 20.4% |
| Starling, font-controlled | 44,896 | 1.2% | 0.6% | 2.7% |
| LibreOffice, font-controlled | 44,895 | 8.2% | 4.5% | 18.6% |

With comparable fonts LibreOffice's largest miss is vertical placement:
line heights, paragraph spacing and what sits above the line.

### 4.3 Writer features where the data shows the difference

Mean score of the documents that have the feature, all sets. "Extra gap"
is the gap on documents with the feature less the gap on documents without
it; a feature is listed only when that is clearly above zero.

| Feature | Documents | Starling | LibreOffice | Gap | Extra gap |
|---|---|---|---|---|---|
| Tracked changes | 44 | 97.1 | 10.1 | 87.0 | +42 |
| Distributed alignment | 81 | 98.7 | 11.7 | 87.0 | +43 |
| Document grid (lines, or lines and characters) | 507 | 98.7 | 14.4 | 84.3 | +45 |
| Chinese text | 801 | 98.9 | 17.2 | 81.7 | +46 |
| Korean text | 91 | 97.8 | 19.7 | 78.1 | +34 |
| Japanese kana | 111 | 97.1 | 20.6 | 76.5 | +32 |
| Character spacing or scaling | 802 | 93.3 | 29.1 | 64.2 | +24 |
| Exact line spacing | 1,116 | 95.9 | 31.8 | 64.1 | +26 |
| Equations | 48 | 86.7 | 25.4 | 61.2 | +16 |
| Merged table cells | 1,194 | 93.2 | 32.7 | 60.5 | +22 |
| Charts | 97 | 93.3 | 33.9 | 59.4 | +14 |
| Text boxes | 781 | 91.2 | 34.8 | 56.3 | +14 |
| Tables | 2,134 | 93.5 | 41.2 | 52.3 | +15 |
| Headers and footers | 1,989 | 93.0 | 41.0 | 51.9 | +13 |

The East Asian rows include the font effect of section 4.2, because those
documents name Windows-only fonts. The same table inside the
font-controlled group (Latin text, replaceable fonts) is free of it:

| Feature, font-controlled group | Documents | Starling | LibreOffice | Gap | Extra gap |
|---|---|---|---|---|---|
| Charts | 32 | 97.2 | 21.9 | 75.3 | +56 |
| Endnotes | 21 | 97.2 | 41.3 | 55.9 | +35 |
| Exact line spacing | 53 | 98.1 | 50.2 | 47.9 | +28 |
| Character spacing or scaling | 54 | 94.5 | 54.7 | 39.9 | +19 |
| VML shapes | 124 | 95.0 | 59.8 | 35.2 | +16 |
| Footnotes | 37 | 96.7 | 61.8 | 35.0 | +14 |
| Text boxes | 78 | 95.0 | 62.2 | 32.8 | +12 |
| Headers and footers | 201 | 96.6 | 65.1 | 31.5 | +13 |
| Inline drawings | 118 | 94.8 | 64.0 | 30.8 | +10 |

Where the data shows **no** extra difference, or LibreOffice is closer:

- Cyrillic documents (295): gap 26.6, well under the average 45.
- In the font-controlled group, nested tables (27 documents, LibreOffice
  87.5), floating tables (82, 85.7) and documents in
  an older compatibility mode (112, 86.8) show a smaller gap than average.
- LibreOffice scores higher than Starling on 95 documents, 70 of them in
  `dx2`, by a median of 13 points. 11 of the 95 are right-to-left.
- Starling's own weak area, right-to-left text (73.0 on 256 documents), is
  still ahead of LibreOffice's 19.6 there, but it is where Starling is
  furthest from Word.

### 4.4 Slides

555 decks, the gate's sweep and scorers.

| | Starling | LibreOffice |
|---|---|---|
| Combined mean, gate rule | 97.54 | 77.34 |
| Mean over the 552 scoreable decks (a failed render counts 0) | 98.07 | 77.76 |
| Decks at 95 or more | 525 | 373 |
| Decks scored by text lines (366): mean | 97.93 | 71.29 |
| Decks scored by pixels (186): mean | 98.34 | 90.51 |
| Decks that end in an error | 3 | 6 |

Starling is higher by more than 1 point on 177 decks, LibreOffice on 8,
and 367 are within 1 point.

Of PowerPoint's text lines, Starling misses 1.3% (5,779 lines) and
LibreOffice 25.3% (5,617 lines): 9.8% broke at other words and 15.1% sit
more than 3 pt away on the same slide.

Features where the gap is clearly larger with the feature than without
(from the corpus census, `/data/s/amd-8/census/`):

| Feature | Decks | Starling | LibreOffice | Gap | Gap without it |
|---|---|---|---|---|---|
| SmartArt | 73 | 99.3 | 47.6 | 51.7 | 15.4 |
| Embedded objects | 33 | 99.7 | 58.6 | 41.1 | 18.9 |
| Text shrunk to fit its box (normAutofit) | 40 | 99.4 | 64.4 | 34.9 | 19.0 |
| Bullets and numbering | 45 | 99.2 | 71.1 | 28.1 | 19.5 |

No extra difference: flipped shapes (29 decks, gap 0.7), connectors (28,
gap 2.0), groups (32, gap 5.9), custom geometry (25, gap 6.6) and rotated
shapes (40, gap 7.2). LibreOffice draws these about as PowerPoint does.

### 4.5 Sheets

755 books, the gate's sweep and scorers.

| | Starling | LibreOffice |
|---|---|---|
| Books that failed to print | 0 | 9 (4 of them over 300 s) |
| Line match, mean over the 682 books both printed with text | 94.6% | 62.7% |
| Pixels differing, mean over the 710 books both printed | 0.64% | 4.41% |
| Excel's page count, of those 710 | 710 | 659 |

On line match Starling is higher by more than 1 point on 383 books,
LibreOffice on 10, and 289 are within 1 point.

Of Excel's lines, Starling misses 5.6% and LibreOffice 71.4% (39.1% on the
same page more than 3 pt away, 18.2% broken at other words, 14.1% on
another page). The offsets are not one constant shift (median 23 pt): row
heights and column widths differ and the error adds up down the page.

Features where the gap is clearly larger with the feature than without:

| Feature | Books | Starling | LibreOffice | Gap | Gap without it |
|---|---|---|---|---|---|
| Line charts | 36 | 88.3 | 30.2 | 58.1 | 30.5 |
| Bar charts | 70 | 88.6 | 32.4 | 56.3 | 29.2 |
| Merged cells | 55 | 95.4 | 41.3 | 54.1 | 30.0 |
| Any chart | 165 | 86.9 | 34.9 | 52.1 | 25.5 |
| Frozen panes | 25 | 93.4 | 41.8 | 51.6 | 31.2 |
| Cell borders | 85 | 96.1 | 47.6 | 48.5 | 29.6 |
| Print titles or print areas | 26 | 96.5 | 48.4 | 48.1 | 31.4 |
| Wrapped text | 75 | 97.1 | 51.7 | 45.4 | 30.3 |

No extra difference: conditional formats (70 books), tables (55), outline
grouping (72) and pie charts (25) show a gap at or below the average.
Charts are Starling's weakest area in Sheets too: 86.9 on the 165 books
with a chart, 79.1 on the 25 with a pie chart.

### 4.6 Limits of this comparison

1. **No Microsoft fonts on either side.** This is the case Starling is
   built for (Linux, iPad, the browser). LibreOffice on a Windows machine
   with Office's fonts installed would score higher than here, most of all
   on East Asian documents. That was not measured: this project does not
   use Microsoft font files. The font-controlled group in 4.2 is the
   closest measurement without them.
2. **Dates.** Starling pins the clock for the 7 Writer documents and the
   decks and books that print today's date; LibreOffice printed the real
   date. Only lines that hold a date field are affected.
3. **Defaults.** LibreOffice ran with its default export settings. No
   option was tuned for either side.
4. **The corpus was used to develop Starling.** These are evaluation sets:
   Starling's rules were found on them, LibreOffice's were not. The
   held-out set exists for that reason, and it was not used here.
5. **The scorer rewards Office's page**, by design. A render that is
   pleasant but breaks lines elsewhere scores low.

## 5. Not measured

- macOS against Linux at one commit. The committed score files are from
  2026-11-01 (macOS) and 2026-11-15 (Linux) at different commits.
- How many files saved by the editor open in Office without a repair
  prompt. Workers check single files (231 check files are on disk); no
  total is recorded.
- Save loss for Slides: the sweep covers `.docx` and `.xlsx` only.
- LibreOffice with Microsoft fonts (section 4.6).
- The legacy `.doc`, `.ppt` and `.xls` sets and the further language
  folders, for either suite.
- The held-out set, which only the coordinator runs.

## Appendix: how the comparison was run

    # Starling, main d10a5afda, the gate's build, engine, fonts and scorers
    ~/bin/wide-ab.sh d10a5afdad d10a5afdad xs          # builds the binary
    SETS="756 lo xb xa xd xs dx2 sa1 sa2" test/tools/docx-pair.sh --seed BIN BIN 8
    OFFICE_APP=BIN test/pptx-app-render.sh -j 32 DECKS PRINTS WORK
    SHEETS_SETS=xlsx test/tools/sheets-sweep.py BIN OUT -j 32

    # LibreOffice, same files; fonts.conf adds Starling's bundled font folder
    FONTCONFIG_FILE=fonts.conf soffice -env:UserInstallation=file://PROFILE \
        --headless --norestore --convert-to pdf --outdir OUT FILE
    DOCX_LINE_MATCH=v2 DOCX_WORD_REFS=PRINTS test/docx-line-match.py WORK
    # Slides and Sheets: the two sweeps above with BIN = a wrapper that
    # accepts "--deck-pdf IN OUT" / "--sheet-pdf IN OUT" and calls soffice

Feature flags per document come from `test/tools/docx-features.py` (Writer)
and the census in `/data/s/amd-8/census/` (Slides, Sheets). The scripts,
PDFs and score files of this run are in `/data/s/amd-opus/report/`; none
of them is in git.
