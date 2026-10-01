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
the fixture's ten charts and on a logo picture. Not yet: shapes and
text boxes, groups, selecting or moving drawings, and moving anchors
and chart references on row/column insert or delete. Quick Look's
thumbnails draw no charts, so they are no reference here.
Left in X4: print/PDF. A stale
`_xlnm._FilterDatabase` name in a file is kept as written (Excel
rebuilds it).

Script coordinates are view points: the window's 28pt title bar is not
in them, so a screenshot's y (in points) is 28 more than the script's.

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
