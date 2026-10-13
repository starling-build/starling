# Sheets — a spreadsheet app beside Writer and Slides

Status: **drafted 2026-09-30, building.** Phase 4 of `docs/plans/office.md`,
given its own revision the way Slides was. The defaults below follow the
calls already made for Slides (one app, macOS first, nothing may break
the wasm or iOS builds of shared code); each is marked **[default]** so
it can be overturned without unpicking anything.

## What "done" means for v1

Someone can open an `.xlsx` a colleague sent — a budget, a list, a
small model — change numbers and formulas, add a row, sort it, format a
column as currency, and send it back; Excel opens it without complaint
and every value the file carried that we did not touch is as it was.
Starting from a blank workbook is the second case: type a table, total
it, format it, chart it.

Not v1: pivot tables, macros/VBA, external links, data validation
dropdowns (kept, not edited), conditional formatting (kept and drawn
for the simple kinds, not edited), array/dynamic-array formulas beyond
reading their cached values, sparklines, slicers, co-authoring. A file
carrying these opens with their cached values and keeps the XML so a
save writes it back.

## Shape of the code

**One app for all three kinds [default].** `apps/OfficeApp` opens an
`.xlsx`/`.csv` as a workbook beside `.docx` and `.pptx`;
`DocumentKind.workbook`, appName "Sheets", untitled "Book1". The shell
for a workbook is its own (`SheetsShell`), keyed by the root exactly as
`SlidesShell` is, and shares the title row, Backstage, File tab and
status bar. All new code lives in `Sources/OfficeApp/Sheets/`; the shared
files gain only the kind and its switch arms — Slides is being built in
the same files at the same time, so the touch is kept to a few lines.

| Layer | Where | What |
| --- | --- | --- |
| Addresses | `Sheets/CellAddress.swift` | A1 / $A$1 / ranges / sheet-qualified refs, parse and print |
| Model | `Sheets/Workbook.swift` | `Workbook`, `Worksheet`, `Cell`, `CellValue`, column widths, row heights, styles |
| Formulas | `Sheets/Formula.swift` | tokenizer, parser to an AST, printer (round-trips the text) |
| Engine | `Sheets/Calc.swift`, `Functions.swift` | evaluation, dependency graph, recalc of what changed, errors, cycles |
| Controller | `Sheets/WorkbookController.swift` | every mutation, one undo stack, selection, fill, insert/delete with reference rewriting |
| Grid | `Sheets/SheetGrid.swift` | the painted grid: headers, cells, selection, scrolling, frozen panes |
| Chrome | `Sheets/SheetsShell.swift`, `SheetsRibbon.swift`, `FormulaBar.swift`, `SheetTabs.swift` | |
| Format | `Sheets/Xlsx*.swift`, `Csv.swift` | SpreadsheetML read/write over the existing `Zip` and `MiniXML`; CSV |

**The grid is painted, not built of widgets.** A screen of cells is
thousands of rectangles; one `CustomPaint` draws the visible window
(headers, gridlines, values, selection) from the model, with text laid
out through a small paragraph cache keyed by (text, style, width). The
framework has no 2D viewport (office.md), so scrolling is the grid's own
offset, moved by wheel/trackpad and keys, and only visible rows and
columns are touched. Editing a cell puts one single-line editor over it;
the formula bar is a second view of the same text.

## The model

```
Workbook
  sheets [Worksheet], active
  styles           a table of CellStyle (font, fill, border, alignment, number format)
  names            defined names → ranges (read, evaluated; edited later)

Worksheet
  name
  cells            sparse: [CellAddress: Cell]
  colWidths        sparse, in characters of the default font (Excel's unit) → points
  rowHeights       sparse, in points
  freeze           top rows / left columns
  merges           [Range]
  kept             XML the model does not understand, written back as is

Cell
  input            what was typed: "12", "=SUM(A1:A3)", "Total"
  formula          parsed AST when input starts with "="
  value            CellValue: number | text | bool | error(#DIV/0!, #REF!, #NAME?, #VALUE!, #N/A, #NUM!, #NULL!) | empty
  style            index into the workbook's styles
```

Numbers are `Double`, as Excel's are; dates are numbers with a date
format (the 1900 serial system, Excel's leap-year bug included, so
serials match). Text typed as `12` is a number, `'12` is text, `TRUE` a
boolean, `1/2/2026` a date in the user's locale order, `12%` 0.12 with a
percent format, `$1,200` 1200 with a currency format — Excel's input
parsing, which is what makes typing feel right.

## The engine

A recursive-descent parser for Excel's grammar: numbers, strings, booleans,
errors, cell and range references (relative/absolute, sheet-qualified,
whole columns/rows), defined names, unary/binary operators with Excel's
precedence (`:` `,`-union, `-` negation, `%`, `^`, `* /`, `+ -`, `&`,
comparisons), function calls. The printer turns an AST back into the
text Excel would show, which is how references are rewritten when rows
and columns move.

Recalculation: each formula cell records the cells and ranges it reads;
a change marks its dependents dirty and they are evaluated in dependency
order. A cycle gives the cells in it Excel's circular-reference warning
and a value of 0. Every evaluation is pure over the model, so the same
engine runs on every platform, the web included.

**Functions for v1** — the ones that cover nearly every real sheet:
SUM, AVERAGE, COUNT, COUNTA, COUNTBLANK, MIN, MAX, PRODUCT, ROUND,
ROUNDUP, ROUNDDOWN, INT, ABS, MOD, POWER, SQRT, IF, IFS, IFERROR, AND,
OR, NOT, SUMIF, SUMIFS, COUNTIF, COUNTIFS, AVERAGEIF, VLOOKUP, HLOOKUP,
XLOOKUP, INDEX, MATCH, CONCAT, CONCATENATE, TEXTJOIN, LEFT, RIGHT, MID,
LEN, UPPER, LOWER, PROPER, TRIM, TEXT, VALUE, FIND, SEARCH, SUBSTITUTE,
TODAY, NOW, DATE, YEAR, MONTH, DAY, EDATE, EOMONTH, NETWORKDAYS, PMT,
FV, PV, NPV, RATE (stretch), ISBLANK, ISNUMBER, ISTEXT, ISERROR, NA.
An unknown function is `#NAME?` and keeps its text, so a file using one
round-trips with its cached value.

## Phases

- **X1 — a workbook that calculates.** Model, addresses, parser, engine
  with the v1 functions, controller with undo; the grid (headers,
  scrolling, selection by click/drag/shift/keys, type to replace, F2 /
  double-click to edit, Enter/Tab/arrows to commit), the formula bar
  with the name box, sheet tabs (add, rename, switch), the status bar's
  Sum / Average / Count of the selection; CSV open and save. Backstage
  New → Blank workbook. Gate: engine unit tests against Excel-computed
  values; a driver run on screen.
- **X2 — .xlsx.** Read and write SpreadsheetML: shared strings, inline
  strings, numbers, booleans, errors, formulas with cached values,
  styles (fonts, fills, borders, alignment, number formats), column
  widths, row heights, merges, freeze panes, defined names, multiple
  sheets; unknown parts passed through. Gate: round trips of real files
  with `qlmanage` (Apple's Excel importer) and a check script, as Slides
  does for `.pptx`.
- **X3 — editing like Excel.** Number formats (General, Number,
  Currency, Accounting, Percent, Date, Time, Text, custom codes read
  and drawn), Home ribbon (font, fill, borders, alignment, wrap, merge,
  format buttons), column/row resize by drag and double-click autofit,
  insert/delete rows and columns with reference rewriting, the fill
  handle (copy, series, dates), copy/cut/paste within the app (formulas
  shifted) and with other apps (TSV and HTML), Find and Replace.
- **X4 — tables of data.** Freeze panes, sort (by one or more keys),
  AutoFilter, charts (Slides' `Chart` model and painter, fed from a
  range), print and PDF export with page breaks.
- **X5 — everywhere.** Web (`starling.debug('sheet')` dump beside
  Writer's layout dump), iOS, the Linux desktop.

## Open questions

- One app or three (Writer, Slides, Sheets as separate apps from one
  package)? Default one, as for Slides.
- Function list — anything the user's own sheets need that is missing
  above.

## Where it stands

**Sweep 4 (2026-10-12): mean 1.93%, median 0.40%**, 751 scored, 10 with a
page only one side has, 42 exact (`baseline-mupdf.tsv`). One workbook and
one cause at a time from here, each checked on its own file and the
whole corpus swept now and then from a frozen copy of the build — which
caught two rules that were right for their file and wrong for others
(below).

- *What counts as there to print.* A merged area, though its cells are
  empty (61034). An inline string with nothing in it: a value (52348).
  What an array formula spills (lo-tdf137543). The cell a drawing's far
  corner stands on, edge or not (chart-tdf128634). A turned shape's
  turned outline, not its anchor's cells (lo-testShapeRotationImport).
  Not a cell, or a merge, in a hidden row or column
  (lo-cool14390_chart_external_ref).
- *Blank pages at the end of a sheet's print are left out* (56644,
  MatrixFormulaEvalTestData), but not one between printed pages, and
  none where titles repeat.
- *Sizes.* A printed column is its screen pixels' worth of characters —
  Excel holds a width in whole pixels, so 0.855 characters print as 0.867
  (lo-tdf118668, 167 such columns). A bold default font has its own line
  and digit (lo-tdf100034). A row whose height is a fit, not set, takes
  the sheet's default where the sheet sets one.
- *Drawing.* No gridline through text that runs over its neighbours;
  nothing snapped to pixels on paper; a print area named twice prints
  once.
- *Wrong, and taken back.* "A row someone gave a height is in use" put a
  thousand empty sized rows on paper in five workbooks (the row in 52348
  was its inline strings). "A cell that is only formatted widens what
  prints" explained FormatConditionTests' fourth page and tripled three
  other workbooks'. Neither showed in a one-in-seven sample; both showed
  in a full sweep.

Not understood yet: why Excel prints FormatConditionTests across to a
formatted, empty H7 and not down to formatted, empty D55–D342; what
makes a row holding Lucida Sans Typewriter 10 in a Verdana 10 workbook
13.32 pt (neither face's own line); 52348's rows at 15.94 pt for a set
15 (a workbook with no cell styles part).

**Sweep 3 (2026-10-12): mean 2.81%, median 0.40%**, 750 scored, 27 with a
page only one side has, 42 exact. What the pictures of sweep 2's worst
showed, and what was done about each:

- *Chart sheets* print as Excel prints them: one page, landscape unless
  the sheet says otherwise, the chart filling the room between the
  margins (in from them by the drawing's own 2.7 pt). They printed as an
  empty worksheet with a chart at its screen size, cut across pages.
- *Charts that drew nothing.* A 3-D bar, line, pie or area chart is drawn
  as its flat kind, a pie-of-pie as its pie, a bubble chart as its points;
  a chart with no series keeps its frame and its room on the page; a
  scatter series the file gives a line (or whose chart style has lines)
  is joined by it. Radar, stock, surface and combinations still draw
  nothing.
- *Fit to N pages* is a whole percent, stepped down until the pages asked
  for really hold the sheet — rows and columns do not split, so the
  arithmetic's scale could be a page over — and ignores manual breaks.
- *Rows nobody sized* are as tall as their tallest font's line on the
  printer, and (where the file's writer fits no rows itself) as their
  wrapped text's lines. Excel writes a height for every row it has fitted;
  POI and LibreOffice leave it to the reader.
- *Printed gridlines are black* (they were the screen's grey, and
  invisible at a glance).
- *Borders inside a merged area* are not drawn: only the sides on the
  area's own edge. A form made of narrow columns merged into fields came
  out as a comb.
- *A shape turned past 45°* is anchored to the cells its turned outline
  covers; the shape itself has that rectangle's centre with width and
  height changed over. Half of a fan of rotated bars pointed the wrong
  way.
- *`usePrinterDefaults="false"`*: Excel then takes the printer's paper
  and ignores the sheet's `paperSize` — nine workbooks that say A4 print
  on Letter, with the option that maps paper sizes off.

**The rendering gate runs, and what the first two sweeps found
(2026-10-12).** Excel's side is made (`test/corpus/xlsx/excel`: 757 PDFs
from Excel 16.0 on Windows; 50 workbooks Excel will not open, 3 that hang
it — `test/corpus/xlsx/README.md`), and `test/xlsx-app-render.sh` scores
the Windows build against it. Sweep 1 was mean 11.08% of pixels differing
(705 scored; 144 workbooks with a page one side has and the other does
not; 1 exact match). Sweep 2 is **mean 3.24%, median 0.42%** over
750 scored, 37 with such a page, 43 exact.
What moved it, largest first:

- *The references were on the wrong paper.* Excel prints an A4 workbook
  on Letter when Letter is the region's paper ("Scale content for A4 or
  8.5 x 11" paper sizes", on by default). 252 references were made again
  with the option off; the export script now turns it off and puts it
  back.
- *Excel sizes a printed sheet by the printer's font, not the screen's*
  (`Sheets/SheetPrintMetrics.swift`). A column's width is a count of the
  default font's digits, and on paper a digit is its advance at 600 dpi:
  5.64 pt for Calibri 11 where the screen's 7 px is 5.25 pt, so columns
  print about 7% wider than they show and a page holds fewer of them. Rows
  go by the printer's line height — 14.52 pt for a default Calibri 11 row,
  not 15 — and a height someone set is scaled by printer line over screen
  line. None of this is in the file format's documentation; it was
  measured by having Excel print a ruled grid in 30 faces at 9 sizes and
  reading the rules back from the PDFs. The table is that Excel's, on a
  display at 200% (the default column and the row scale depend on the
  display). Printing now lays the sheet out with these sizes, draws text
  at its true size (the screen draws it 6% small so a digit is 7 px), and
  keeps a drawing's corners at the same share of their cells.
- *The workbook's default font was dropped.* A style with the default
  font kept no name or size, and everything drew — and every column was
  counted — in Calibri 11. POI's files are mostly Arial 10, the Japanese
  and Chinese ones MS PGothic and SimSun 11, whose digit is 8 px. The
  workbook now carries its default font (`Workbook.defaultFontName`/
  `Size`); a column width is read in that font's digit
  (`Workbook.digitWidth`), and a sheet's default width from
  `defaultColWidth` or `baseColWidth`, which were not read at all.
- *Where the printed area ends, and starts.* It starts at A1, however far
  in the first cell is. It takes in every cell a drawing covers (a
  one-cell or absolute anchor counted for nothing, or for its corner),
  the columns a long text runs over, and rows formatted as a whole.
- *Smaller:* a workbook with nothing to print is a match when Excel's PDF
  has no pages either (36); printed row and column headings
  (`printOptions@headings`); A4 Small, A6, B4, B5, Executive and Tabloid
  paper; an anchor offset past its cell stops at the cell's edge; and the
  picture cache no longer empties itself of what a print had just decoded
  (pictures were missing from printed pages since afc6afb8); a drawing
  marked hidden is not drawn and does not count.

- *Embedded objects and controls* (`Sheets/SheetObjects.swift`). An
  embedded object (a PDF, a package, another workbook) and an ActiveX
  control come with the picture Excel last drew of them, an EMF; the
  sheet's `oleObjects`/`controls` entry or the legacy VML shape of the
  same number says where it sits. They are drawn from that picture, an
  object's with the shape's outline round it. The metafile player learned
  the alpha-blended bitmap such a picture's icon is (EMR_ALPHABLEND), and
  a sheet's own pictures that are metafiles are played too — they drew
  nothing before. A form control has no picture: check box, option
  button, button, label, group box, drop-down, list, scroll bar and
  spinner are drawn from their kind, state and caption, found on the
  sheet or (before Excel 2010) only in the VML. One Excel leaves off
  paper (`x:PrintObject` False, a button's default) is left off. All of
  it is display only: nothing is written, moved or clicked, and the
  file's parts are kept as they were. 7 of the 14 workbooks that printed
  nothing print now.

What is left, by what the pictures show: a legacy shape's pixel offsets
(this Excel, at 200%, reads them as its own pixels, so a control placed
only by VML sits up to half a column off its reference), form controls
other than the check box and option button (drawn, but the corpus has
none that prints, so none was compared with Excel's), clicking a
control, charts with no series (Excel draws the frame), East Asian text drawn in a
narrower face than Excel's so long lines end early, a border on an empty
cell that is not drawn (61034), `lo-xf_default_values` (Excel halves its
set row heights; not understood), and the fonts this app has no clone
for. The Mac's `baseline.tsv` for Sheets does not exist yet.

**A rendering gate against Excel, half built (2026-10-11).** The corpus
is in the repository — `test/corpus/xlsx/books`, 810 workbooks (POI's 352
of the oracle rounds below, LibreOffice's `sc` and `chart2` regression
files) — and `OfficeApp --sheet-pdf` prints an entire workbook without a
window (every visible sheet in tab order, pages numbered across them;
`SheetGridState(headless:)`), 736 of the 810. `test/xlsx-app-render.sh`
scores those pages against Excel's as `test/pptx-app-render.sh` does for
Slides. What is missing is Excel's side: Excel for Mac without a licence
neither prints nor saves (File → Print… is disabled; the scripted save
and print answer without error and write nothing), so the references are
to be made on Windows with `test/xlsx-excel-render.sh` (COM,
`ExportAsFixedFormat`), which is written and has never run. Until then
there are no scores. Known before any score: 56 workbooks print nothing
here (to be checked against what Excel prints for them — form controls,
sheets holding only a header or footer, drawings at absolute anchors),
and this app's print stops at the used cells where Excel may also count
shapes.

**Excel as the formula oracle (2026-10-07).** Every formula cell in an
.xlsx carries the value Excel last computed for it, so a real workbook is
a test of the engine: `OfficeApp --xlsx-check file.xlsx…` reads each
file, recalculates every formula, and compares with the cached value
(numbers to 1e-9 relative; a function we lack, an unreadable formula or a
legacy array formula counts as *kept*, and a formula reading NOW/RAND/
OFFSET or a cell that does counts as *volatile*; `XLSX_CHECK_MAX` caps the
diffs printed). Run over Apache POI's `test-data/spreadsheet` corpus (352
.xlsx, downloaded with `gh api repos/apache/poi/contents/…`): 641
differences in 20 files at the start, 40 at the end, in 4 files. The
fixes, all with cases in `SheetsOracleTests`: number formats — conditional
sections, fraction formats (`# ?/?`, `#/8`, Excel's alignment and
zero-value rules), engineering exponents (`##0.0E+0`), `?` placeholders as
spaces, the trailing point in `#.#`, text sections with escapes and
booleans, `ss.000`, elapsed units and plain tokens after them, `m` after
`s`, `a/p` keeping its case, General at ten significant digits in TEXT,
negative elapsed times in TEXT; the engine — DATE's day overflow in serial
days (the phantom 29 Feb 1900), errors passing through DAY/MONTH/YEAR/
ATAN2/CHOOSE/REPLACE/NPER/PMT/FACT, FLOOR(x,0), MEDIAN/AVEDEV/DEVSQ of
nothing, MODE's #N/A, direct-argument coercion in LARGE/MINA/AVERAGEA,
CONCATENATE's implicit intersection (CONCAT takes all), COUNTIF matching
errors, COUNTIFS with an array criterion, SUMPRODUCT evaluating its
arguments as arrays, SUBTOTAL skipping a SUBTOTAL cell given alone, T of a
range, ADDRESS's sheet quoting, a deleted name's #REF!, links into other
workbooks keeping the file's value, Excel's *binary* search in
VLOOKUP/HLOOKUP/MATCH/LOOKUP and XLOOKUP's search modes (unsorted data
lands where Excel's lands), and iterative calculation (`calcPr iterate`,
read and written). What remains differs for reasons the files cannot
settle: an iterative workbook's values depend on the history of
recalculations (ours agree to 1e-8), `FLOOR(beta,1,2)` where Excel reports
the unknown name before the extra argument, and two cells on POI's
"EverythingTests" sheet whose #VALUE! has no visible cause.

**Excel as the writer's oracle, over the same corpus (2026-10-07).**
Every readable named file in POI's corpus round-tripped (`--xlsx-roundtrip`)
and opened in Microsoft Excel (`test/xlsx-excel.sh`), each repair checked
against the original first — most of the "repairs" were the files' own
(deliberately broken fixtures, a pre-release 2006 format, an encrypted
package). Ours, all fixed and under test: a part written with a prefix for
the main namespace (`<x:worksheet xmlns:x="…">`, HCell and some .NET
generators) is normalised to the default namespace on read, since the
fragments kept verbatim and the elements written fresh must agree; a kept
root without `xmlns:r` gets it, for the `r:id`s we write; fonts and xfs
wrapped in `mc:AlternateContent` in styles.xml take their fallback, so the
style tables keep their positions; a table's autoFilter stops above its
totals row; a table column's name is the header cell's text with its
spaces. The Excel driver now dismisses the external-links alert, which
used to stay up and colour every later verdict.

**Published (2026-10-07):** `build/web-deploy.sh OfficeApp --host
sheets.starling.build --repo git@github-starling:starling-build/sheets.git
--args --sheets --title Sheets` pushed the release stage to the new
`starling-build/sheets` site repo, Pages enabled on `main` with the custom
domain set; the page answers for the host (`curl -H "Host:
sheets.starling.build" http://starling-build.github.io/`) and waits only
on the Cloudflare CNAME `sheets` -> starling-build.github.io, then the
certificate and `https_enforced`, as Slides did.

**X5, the browser (2026-10-07).** Sheets opens, edits and saves in the
same page as Writer and Slides (`build/web-app.sh OfficeApp --package
apps/OfficeApp`, started with `--sheets`): ⌘O and File → Open are the
browser's picker, a save is a download named after the workbook, Save
As is save, CSV export is a download, PDF export and printing say they
are not in the browser yet (Writer's limit too). Every shell's picker
now accepts every kind (`OfficeFormats.pickable`), and a pick of another
kind switches shells with the same bytes through `PickedFile` — an
.xlsx picked in Writer opens in Sheets, a .pptx picked in Sheets opens
in Slides. Backstage's Open/Save/Save As rail items and tile hand over
to the picker and the download in a tab, in all three shells. Checked
by `test/sheets-web.sh`: the karma fixture opened through the picker,
E4 typed over, the download reads back natively with the edit, and it
opens clean in Excel. The layout parity gate is `test/sheets-layout.sh`
(in `test/run.sh`): `OfficeApp --sheet-layout book.xlsx` natively and
`starling.debug('sheet')` in the page print the active sheet as laid out
— used column widths and row heights in points, each cell's address,
alignment, shown text, measured text width in pixels, wrapped line
count, #### — and the gate diffs the two, then the saved copy's layout
against the original's. iOS and Linux untested.

**The v1 scenario, driven end to end (2026-10-03).** On a blank book
(`test/scripts/sheets-v1.txt`): type a two-column table, format the
amounts as currency, Sort A to Z by the text column (the header stays —
it used to sort into the data), AutoSum the column (the total now takes
the currency format), insert a column chart (titled by the header,
categories from the first column), undo it. On a copy of a real claims
workbook: change a number, select a row, Home → Insert → Insert Sheet
Rows, type into the new row, ⌘S; openpyxl reads the result without a
warning, the picture and its anchor survive, the data sits one row
down. Both checked in dark and light mode (`OFFICE_DARK=0`). A second
pass over typed values (5%, (1,234.5), 3/4, 9:30 pm, '0042, 1e3), fill
series, merge and wrap, Shift/⌘-arrows, Delete, F2, the View tab, a
cross-sheet formula on a new sheet and the PDF of a 29-column table
found two more: wrapped lines ignored the cell's alignment (a Merge &
Center heading read left-aligned), and renaming a tab appended to the
old name. Both fixed the same day. With Excel itself as the oracle
(`test/xlsx-excel.sh`, 2026-10-06): the three real files' round trips,
the edited claims copy, a chart inserted and saved, a table whose rows
were all deleted and one whose rows were partly deleted all open clean.
One repair found and fixed: a table header cell left empty got a
generated column name in the part but not in the cell, which Excel
repairs — the cell now takes the name on save, as Excel refills it.
Shift-clicking a row or column header extends the selection, as Excel's
does; a header drag selects in either direction.

**X1 nearly done (2026-09-30)**, on branch `sheets`, rebased on `office`
ce3c4af1. Engine (9ed475e1): addresses, model, parser/printer, on-demand
recalculation with cycles, ~110 functions, number formats, input
parsing — 20 tests against Excel's values. Window (3db7f03d): the
painted grid with Excel's Enter/Edit modes, formula bar and name box,
sheet tabs, status-bar Sum/Average/Count, the Home/Formulas/Data/View
ribbon, CSV open/save. Seen on screen through `test/sheets-drive.py`:
typing, formulas, recalculation, range selection and its status
figures, bold, a second sheet.

Left for X1: Ctrl+Enter (fill the selection), F4 (cycle $), clicking
cells into a formula being typed, a dependency graph instead of
whole-workbook recalculation if a real file needs it.

**X3 editing (2026-09-30)**: rows/columns, fill handle and series,
copy/cut/paste with reference shifting, pointing, F4, ⌃Enter (part 1);
frozen panes, merges, wrapped text (part 2); Find & Replace across
sheets (⌘F/⌘H, formulas searched as written, Replace All one undo
step), double-click autofit on header borders, and the right-click
menu for cells, rows and columns (part 3). Seen on screen through
`test/sheets-script.sh` with `test/scripts/sheets-{editing,panes,find}.txt`
— in-process input into a background window, never the OS driver.
Copy and paste with other apps (`Sheets/HtmlTable.swift`): a copy
puts TSV and an HTML table on the pasteboard (character styles on an
inner span, which is where Writer reads them); a paste prefers a table
in the HTML — Excel's class-styled clipboard, Google Sheets' and web
pages' inline styles — and keeps bold, italic, colours, fills and
alignment, as one undo step. Tested on parsed fixtures only: a live
test would overwrite the real pasteboard.

**X4 AutoFilter (2026-10-01)** (`Sheets/Filter.swift`, `FilterPanel.swift`):
⌘⇧L or Data → Filter on the table around the selection; a dropdown per
header cell (a funnel once it filters) opens sort, clear, search and a
tick list; hidden rows are `Worksheet.filteredRows`, apart from
`rowHeights`, so every row keeps its height; arrows and Enter step over
them; the status bar says "N of M records found" and its Sum/Count skip
them. Applied when set or sorted, not on every edit (Excel's rule);
Reapply takes in rows typed under the table. `.xlsx`: value-list filters
are read and written; any other kind (custom, top 10, colour, date
groups, a sortState) keeps the element as written until the filter is
changed here. `GridAxis` is now binary search over prefix sums, cached
per `Worksheet.layoutVersion` — a filter can hide thousands of rows.
Also: Enter after a run of Tabs returns to the column the run began in.
**X4 pictures and charts (2026-10-01)** (`Sheets/Drawings.swift`): read
from each sheet's drawing part for display — the package keeps every
drawing, chart and media part, so a save is untouched. Charts are
Slides' `Chart` through the same `ChartXML.read` and `ChartPainter`, at
0.75 of the pixel scale (Excel's 14/9pt text is exactly three quarters
of PowerPoint's 18.6/12), with the file's theme (`DeckTheme(xlsxTheme:)`;
`PptxTheme`/`ColorContext` in PptxReader.swift lost their `private`).
Series read their cells (`Sheet1!$B$2:$B$5`) live, so a chart follows
edits; the cache stands in when a reference does not resolve. Seen on
the fixture's ten charts and on a logo picture. Shapes and text boxes
(`Sheets/SheetShapes.swift`) are drawn too — preset geometry (rect,
rounded, ellipse, triangles, diamond, block arrows, lines and
connectors), fill and outline set on them or through their style's
theme references, text paragraph by paragraph with runs, alignment and
vertical anchor — and select, move and delete like charts, their XML
kept. Since 2026-10-03: rotation (`xfrm@rot`, text turning with the
shape), linear gradients with all their stops, arrowheads (`headEnd` at
a line's start, `tailEnd` at its end), groups (`xdr:grpSp`, nested, each
member placed by the group's chOff/chExt child space; pictures inside a
group are still not drawn), and every preset Slides' `geometryPath`
knows (hexagon, chevron, braces, stars, callouts…); the rest are
rectangles. Seen on a fixture copy (SheetsShapeTests holds the XML).
Quick Look's thumbnails draw no charts, so they are no reference here.
**X4 print and PDF (2026-10-01)** (`Sheets/SheetPrint.swift`): File →
Export → PDF (or CSV), File → Print and ⌘P, for the active sheet, as
Excel defaults. The used area (values, fills, borders, drawings) is cut
into pages that never split a row or column, numbered down then over;
Letter portrait with Normal margins unless the file's kept `pageSetup`,
`pageMargins`, `printOptions` and `sheetPr/pageSetUpPr` say otherwise
(paper, landscape, scale, fit to N pages, gridlines, centring). A page
is the grid's own region painter in `printing` mode — one pixel per
point, no headers, panes, editor or dropdowns — so it prints what the
screen shows, charts and pictures included. Seen: the fixture as three
Letter pages. The file's print area (`_xlnm.Print_Area`, several
areas each on their own pages) prints instead of the used area, and its
print titles (`_xlnm.Print_Titles`, rows and/or columns) repeat on
every page that does not already show them, their room kept free on
each (seen on a copy of privateschools2223.xlsx). Headers and footers
(`Sheets/HeaderFooter.swift`, 2026-10-03): the file's `<headerFooter>`
strings cut into left/centre/right by `&L`/`&C`/`&R`, with `&P` `&N`
`&D` `&T` `&F` `&A` `&Z`, the bold/italic/underline/strike toggles,
`&"Font,Style"`, `&nn` sizes and `&Kxxxxxx` colours; odd/even/first
variants; drawn at the header and footer margins in the workbook's
default font. Manual breaks (`rowBreaks`/`colBreaks`) start a page
whatever room is left, `pageOrder="overThenDown"` and
`firstPageNumber` are honoured, and page numbers run across several
print areas. Sections overlap when they are too long, as Excel's do.
Checked by exporting a fixture copy (an OFFICE_SCRIPT `pdf PATH` command
writes what File → Export → PDF would) and rasterising it with PDFKit.
Not yet: Page Layout view, `&G` header pictures.

X4 is done but for those.

**Charts made here (2026-10-01)**: Insert → Charts (column, bar, line,
pie, area, scatter) charts the selection or the table around the active
cell, Excel's way — a text top row names the series, a text first column
gives the categories, series run down the longer side, 5 × 3 in beside
the data. With a chart selected the same buttons change its kind. A
click selects a picture or chart (frame and eight handles); drag moves,
a handle resizes, Delete removes, Escape returns to the cells, right
click offers Delete and the other chart kinds; every change is one undo
step. Saving regenerates only an edited sheet's drawing part: anchors
that did not move (and shapes, groups, `mc:AlternateContent` — never
modelled) go back byte for byte with the part's own relationships, a
moved one gets a new `twoCellAnchor`, a new or retyped chart a new
`xl/charts/chartN.xml` (Slides' writer with the real `Sheet!$B$2:$B$5`
references, no embedded workbook, Excel's text sizes and white chart
area), plus content types and the sheet's `<drawing>`/rels when the
sheet had none; deleting the last drawing drops the part. Seen: insert,
move, ⌘S and reopen of the fixture. Not checked in Excel itself (none
here) — the parts follow what Excel writes, and every part parses.

**References stay true on save (2026-10-01).** Inserting or deleting
rows/columns, renaming or deleting a sheet now carries, besides cell
formulas: defined names (a rename used to miss them), every defined
name the file had — print areas and titles, `_FilterDatabase`, sheet-local
names (`Workbook.fileNames`, regenerated on save in the file's order;
a deleted sheet's local names go, later `localSheetId`s move up) — every
chart's `<c:f>` (the file's chart part is rewritten in those references
only, `SheetChart.formulas`), and every drawing anchor, which moves and
sizes with its cells (the file's anchor element kept, its corners
patched). Before this, a file's charts and names kept pointing at the
old cells after a save. The same now holds for the sheet elements kept
as written that name cells (`Sheets/KeptRefs.swift`): conditional
formats, data validations, hyperlinks, ignored errors and protected
ranges move their `sqref`/`ref` and formulas with the cells, and one
left covering nothing is dropped. Not reached: their x14 copies in
`extLst`. A stale
`_xlnm._FilterDatabase` name in a file is kept as written (Excel
rebuilds it).

Script coordinates are view points: the window's 28pt title bar is not
in them, so a screenshot's y (in points) is 28 more than the script's.

**Conditional formatting drawn (2026-10-01)** (`Sheets/ConditionalFormats.swift`):
the kept `<conditionalFormatting>` rules evaluated for the cells on screen
— cellIs, expression (relative to the range's top-left, as stored), the
text rules, blanks, errors, top/bottom N and N%, above/below average,
duplicate/unique, 2- and 3-colour scales (min, max, num, percent,
percentile), solid data bars and icon sets (arrows, traffic lights,
signs, symbols, flags, red-to-black, ratings, quarters; reversed and
icon-only too) — in priority order with stopIfTrue,
fills under the cell's text and dxf fonts over it. Figures over a
range are cached per `WorkbookController.dataRevision`. Date-occurring
rules (`timePeriod`: today, yesterday, tomorrow, last 7 days, this/last/
next week with Sunday weeks, this/last/next month) since 2026-10-03. Not
drawn: x14 rules in extLst (custom icon sets); not editable yet. Seen on a
fixture copy with a scale, bars and a cellIs rule.

**Excel tables kept valid (2026-10-01)** (`Sheets/Tables.swift`): a
table part's range moves with inserted/deleted rows and columns, its
column list follows (new entries for columns inserted inside, dropped
ones removed, positional filters cleared), and on every save its
column names are re-read from the header cells — unique, never empty,
control characters as `_x000a_` — because Excel discards ("repairs") a
table whose names disagree with its header cells. The rest of the part
is written as read; privateschools2223.xlsx's table round-trips byte
for byte. Built-in table styles are drawn by family (`TableStyles`:
Light 1–21, Medium 1–28, Dark 1–11 over the dark colour and six
accents — header, stripes, totals, lines; an approximation of Excel's
presets, seen for Medium 2, Medium 9 and Light 9), under the cells' own
formats. A table deleted with all its rows or columns goes altogether
(2026-10-03): its part, its relationship, its `<tablePart>` and its
content type, so Excel has nothing to repair. Not yet: custom table
styles from the file.

**Structured references (2026-10-01)**: `Table1[Col]`, `Table1`,
`[@Col]`, `Table1[[#This Row],[Col]]`, `[[#Headers],[A]:[B]]`, `#All`,
`#Data`, `#Totals`, with `'` escapes, parse to `FormulaExpr.structured`
— kept as written, so rows moving never touch them and they print back
verbatim — and resolve against the tables when evaluated (by header
text, then the file's column names). Typing a new header renames every
reference to that column, as Excel does, in the same undo step.

**Notes (2026-10-01)** (`Sheets/Notes.swift`): a file's notes show as
Excel's red corner triangle, and on hover as the pale yellow box (its
own bold "Author:" line, text wrapped). Inserting or deleting rows and
columns moves each note's `ref` in `commentsN.xml`, its shape's
`x:Row`/`x:Column` in the VML drawing and a threaded comment's `ref`; a
note whose cell is deleted is removed from all three. Untouched note
parts are written byte for byte. Notes are made, edited and deleted
here too (Review → Notes, the right-click menu; Previous/Next walk
them): a new note is signed with the user's name, as Excel's are; the
file's comments and VML parts are patched (text replaced, notes and
authors appended, shapes added after the file's largest id) or created
with their relationships, content types and `<legacyDrawing>` when the
sheet had none. Threaded comments stay read-only (Excel owns their
replies). Drawings and notes share one relationship list per sheet in
the writer, so a sheet gaining both in one save keeps both links.

The Review tab used to show Writer's Spelling and Word Count for a
workbook (acting on an invisible empty document); it is Sheets' own now.

**Data validation (2026-10-01)** (`Sheets/Validation.swift`): the kept
`<dataValidations>` are read (cached per data revision): a list rule
gives the active cell Excel's arrow (unless `showDropDown="1"`, Excel's
inverted flag) with its choices, inline or from a range; an entry that
breaks a list, whole, decimal, date, time, textLength or custom rule
whose error alert is on is refused — the cell keeps its content and the
status bar shows the rule's message (Excel's Stop alert answered Cancel;
there is no Retry). Formulas typed in are not checked, nor pastes (as
Excel). Since 2026-10-03: a rule's input message (`showInputMessage`,
`promptTitle`/`prompt`) sits in a pale box under the active cell, and
the alert styles differ — Stop refuses, Warning and Information let the
value in and put the title and message in the status bar (Excel's Yes
and OK). Not yet: editing rules.

**Links and array constants (2026-10-01)**: ⌘-click follows a cell's
link (`Sheets/Hyperlinks.swift`) — the kept `<hyperlinks>` (URLs through
the sheet's relationships, `location`s in the workbook) and HYPERLINK()
formulas, now a function; http(s) and mailto open in the browser, a
place is selected. Array constants (`{1,2;3,4}`) parse, print back and
evaluate.

**Dynamic arrays (2026-10-01).** A formula typed here (`Cell.dynamic`),
or an array formula from a file, works as in Excel 365: operators go
element by element (`B2:B6*2`, `B2:B6>15`, a one-row or one-column side
stretching), and an array result spills from its cell into the empty
cells below and right (`Worksheet.spilled`, drawn in those cells'
formats, read by other formulas, outlined when one is selected) —
#SPILL! when something is in the way, back when it is cleared. FILTER
(#CALC! when nothing is kept, or its if_empty), UNIQUE (by column,
exactly once), SORT, SORTBY, SEQUENCE, TRANSPOSE; `A1#` reads a whole
spill; `@x` is implicit intersection (`_xlfn.SINGLE` in files). A
file's other formulas keep implicit intersection, as Excel 365 does for
pre-dynamic formulas. Ordering knows spills: a pass that finds a new
one runs again with it known; typing into a spill, or any edit while a
formula is #SPILL!, takes a full pass; the randomized test covers
spills too. Saved as an array formula over the spill (`t="array"
ref=…`) with the spilled values — every Excel shows them — and with
Excel 365's dynamic-array mark: `cm` pointing at the XLDAPR entry of
xl/metadata.xml (the file's own when it has one; else the part is made,
with its relationship and content type), so Excel 365 opens it as a
spilling formula, not a legacy {array}. A cell's own `vm`/`cm`/`ph` (an image placed
in the cell, a linked data type, other metadata) are kept
(`Cell.keptAttrs`) and written back until the cell is typed over —
they were dropped on every save before, which left such a cell a bare
#VALUE! in Excel. Those images are not drawn here yet.

**Rows and columns keep what the file said (2026-10-01).** `<col>` and
`<row>` were rewritten with width/height and hidden only, so grouped
rows and columns (outlineLevel, collapsed), column and row default
styles (a currency column, a shaded band — privateschools2223.xlsx's
column C lost its style), bestFit and `sheetFormatPr`'s base/default
width and outline levels were dropped on save. They are kept now
(`Worksheet.colAttrRuns`, `rowAttrs`, `formatPrAttrs`), move with
inserted/deleted rows and columns, and a cell typed into a formatted
row or column takes its style, as in Excel; a formatted row's or
column's fill is drawn under its empty cells. Widths are written as the
file had them while unchanged (`colWidthChars`): pixel rounding used to
nudge 17.453125 to 17.42578125.

**Cell formats kept exactly (2026-10-01).** styles.xml was rebuilt from
the simplified style model: border kinds and colours (a total's double
underline), theme font colours and schemes, pattern and gradient fills,
indents, rotation, protection and named cell styles all came back
plainer on save. Now the file's numFmts, fonts, fills, borders,
cellStyleXfs, cellStyles and each cellXfs entry are kept as written
(`Workbook.styleSource`, container tags included) and written first,
verbatim, so every original style index means what it meant; a format
made here records the one it came from (`CellStyle.baseXf`) and reuses
its font, fill, border, number format, alignment, protection and named
style wherever the change left them alone (bolding a double-underlined
total keeps the double underline); undoing the change maps back to the
file's own format. The three real workbooks' styles sections round-trip
byte for byte. Border kinds and colours are also drawn (thin, medium,
thick, double, dashed, dotted, hair).

The 1904 date system (old Mac workbooks, `workbookPr date1904`) is
honoured — serial 0 is 1 January 1904, no phantom 29 February — through
`ExcelDate.system1904`, set for the workbook that loads; before, such a
file's dates showed four years early. A sheet view's other attributes
(zoom, scroll position, showZeros — honoured on screen — right to left,
page layout view) are kept. Sheet protection is enforced as Excel does it
(`Sheets/Protection.swift`): on a protected sheet a locked cell (any
cell unless its format says `locked="0"`) neither opens for editing nor
takes typing, pasting or filling, and formatting, merging, inserting or
deleting rows and columns, sorting and filtering are refused unless the
protection allows each; unprotecting stays Excel's (the password is its). Hidden sheets are hidden here too
(they used to get a tab): Hide Sheet and Unhide in the sheet menu, very
hidden ones left to code as in Excel and written back as veryHidden
(they were demoted to hidden), at least one sheet always visible, never
opened on a hidden one. A workbook's `lockStructure` refuses adding,
deleting, renaming, hiding and showing sheets. Adding a sheet now moves
the later sheets' local names (print areas, filter ranges) along — they
used to attach to the wrong sheet. LET (local names in
`EvalContext.locals`) and the Excel 365 shapers VSTACK, HSTACK, TAKE,
DROP, CHOOSEROWS, CHOOSECOLS, TOCOL, TOROW, WRAPROWS, WRAPCOLS and
TEXTSPLIT work too. The intersection operator (a space between two
references, `SUM(A1:B5 B2:C9)`, #NULL! when they share nothing) reads,
evaluates and prints since 2026-10-03; the tokenizer emits it only
between an operand and the start of another, so `SUM(A1, B1)` and
`A1 + B1` are untouched. A defined name holding a LAMBDA (as Excel 365
writes it, `_xlfn.LAMBDA(_xlpm.x,…)`) is callable by that name, recursion
included, capped at Excel's 1024 deep (#NUM! past it); a bare LAMBDA in
a cell is #CALC!. A cell calling one follows both its arguments and the
cells the body reads. Not yet: calling a LAMBDA inline, `LAMBDA(x,x)(3)`.

**Row outlines (2026-10-01).** `Sheets/Outline.swift`: Data → Outline's
Group/Ungroup (⌘⇧K/⌘⇧J, Excel for Mac's) change selected rows'
`outlineLevel`. A gutter left of the row numbers holds level buttons
1…n+1 and, per group, a bracket and a +/− box at its summary row
(below the rows, or above when `summaryBelow="0"`). Closing a group
hides its rows and marks the summary row `collapsed="1"`. Opening one
keeps its nested closed groups closed. Rows hidden by hand or by an
outline are `Worksheet.hiddenRows`, separate from `filteredRows`, so
they keep their heights and a filter cannot unhide them. They used to be
a height of 0 read from the file, which lost the height and never
reopened. `rowAttrs` and `colAttrRuns` bump `layoutVersion`, and the
gutters' sizes and groups are cached on it. Columns outline the same way
(one `OutlineGroup` model and `WorkbookController.Axis` throughout).
Group on whole selected columns groups them. Their gutter sits above
the letters, their level buttons are stacked beside the row numbers, and
a column's level or collapsed flag is set by splitting the file's
`<col>` run around it, so the run's style survives. Hidden columns are
`Worksheet.hiddenCols`, apart from their widths, as rows are. A file's
`hidden="1"` used to become a width of 0. Hide and Unhide are on the row
and column header menus; Unhide takes in the hidden ones inside the
selection, as in Excel, and hiding every row is refused.
`test/scripts/sheets-outline.txt` shows both directions.

**Functions: 242 (2026-10-01).** `Sheets/MoreFunctions.swift` adds the
everyday rest: LARGE, SMALL, RANK(.EQ/.AVG), PERCENTILE and QUARTILE
(.INC/.EXC), MODE, VAR.P, GEOMEAN, HARMEAN, AVEDEV, DEVSQ, AVERAGEA,
MAXA, MINA, SLOPE, INTERCEPT, RSQ, CORREL, FORECAST, FREQUENCY, the
normal distribution (NORM.DIST, NORM.S.DIST, NORM.INV, NORM.S.INV);
GCD, LCM, FACT, COMBIN, PERMUT, QUOTIENT, MROUND, EVEN, ODD,
CEILING.MATH, FLOOR.MATH, the trigonometry; MAXIFS, MINIFS, SWITCH,
XMATCH, LOOKUP, ADDRESS, OFFSET, INDIRECT, ISFORMULA, ISREF, N, T,
TYPE, ERROR.TYPE, SUBTOTAL (skipping filtered rows and nested
subtotals), AGGREGATE; REPLACE, CLEAN, FIXED, DOLLAR, UNICHAR,
UNICODE, TEXTBEFORE, TEXTAFTER, NUMBERVALUE; WEEKNUM, ISOWEEKNUM,
WORKDAY, DAYS, DAYS360, YEARFRAC, DATEVALUE, TIMEVALUE; NPER, IPMT,
PPMT, CUMIPMT, CUMPRINC, SLN, SYD, DDB, DB, IRR, XNPV, XIRR — each
tested against the value Excel's documentation gives.

**Recalculation (2026-10-01).** Evaluation used to recurse into each
formula's inputs from sheet order, so a running total 15,000 rows long
recursed 15,000 deep and crashed the app (SIGSEGV, stack overflow).
`CalcEngine.recalculate()` now orders the formulas first — an iterative
walk over their static references (cells, ranges as shared nodes,
defined names) — and evaluates inputs first; a 50,000-row chain is a
test. The graph is kept between edits: an edit that changes only values
recomputes what reads the changed cells (by cell, and by ranges indexed
by column) plus volatile formulas (NOW, TODAY, RAND, OFFSET, INDIRECT,
CELL, INFO, table references); a formula typed or removed, or anything
structural, rebuilds it. A randomized test checks every incremental
pass against a full one. A range's values are gathered once per pass
for SUMIF/COUNTIF/AVERAGEIF(S), and the used extent is cached per pass
(writing computed values back used to invalidate the sheet's, so every
whole-column criterion rescanned the sheet). Release build, 30,000
formulas (a running total + 15,000 SUMIFs over 200 cells): a full pass
1.2 s → 0.14 s; editing a cell nothing reads 1.2 s → 0.05 ms; editing
the cell everything reads 0.09 s. `SHEETS_CALC_TRACE=1` prints a full
pass's ordering and evaluation times.

**Fixed 2026-10-01: formulas this engine cannot read were dropped on
save** unless their result was text — the cell kept only its value, so a
table's `=SUM(Table1[Amount])` or `[@Price]*[@Qty]` became a constant.
Every unreadable formula (and each shared formula hanging off one, and
array formulas) now keeps the file's `<f>` element (`Cell.rawFormula`),
written back verbatim with its cached value until the cell is typed
over; a copy elsewhere carries the value, as the formula cannot be
re-addressed; a cut-move keeps it, as Excel's does.

**Fixed 2026-10-01: saves dropped the file's differential formats.**
`styles.xml` is rebuilt from the model, and the rebuild wrote an empty
`<dxfs count="0"/>`, so every conditional format, table style and pivot
format in a saved file pointed at a dxf that no longer existed
(privateschools2223.xlsx lost 111). The file's `dxfs`, `tableStyles`,
`colors` and `extLst` are now kept verbatim (`Workbook.keptStyleParts`,
under the file's own `<styleSheet>` root, whose prefixes they use).

**Traps paid for:**

- This port's `FluentTextBox` fires `onChanged` on programmatic text
  changes (Flutter's does not). The formula bar mirrors the cell
  editor, and without a guard the mirror read as the user typing in
  the bar, which stole the next keystrokes. `SheetsShell._setFormulaText`.
- **Never run a GUI driver while another session is driving the
  screen.** On 2026-09-30 the Slides session was driving its own
  OfficeApp instance (default frame, same as ours); the two drivers'
  "bring my window to front" raced, and `sheets-drive.py`'s keystrokes
  went into the other instance — blank slides added to its deck.
  Check `ps` for a second OfficeApp, and ask, before driving. Headless
  Chrome (`build/tools/web-drive.mjs`) never touches the screen and is
  the safe way to see the app when someone else is at it — once the web
  build compiles again (below).
- The wasm build of OfficeApp is broken by Slides code as of
  ce3c4af1: `Color(0xFF00_0000 | …)` literals overflow a 32-bit Int
  (Chart.swift, DeckController.swift, PptxReader.swift), the layout id
  2147483649 in PptxTemplates.swift, and `.atomic` writes in
  SlidesShell.swift. None is in Sheets/, so the Sheets code type-checks
  for wasm; it cannot be run there until those are fixed.
