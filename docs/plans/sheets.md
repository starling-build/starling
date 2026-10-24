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

**Sweep 14 (2026-10-16): mean 1.43%, median 0.39%**, 751 scored, 1 with
a page only one side has, 45 exact (`baseline-mupdf.tsv`). Sweep 9 was
1.50%. **Sweep 7 (2026-10-16): mean 1.55%, median 0.41%**, 751 scored, 5 with a
page only one side has, 43 exact (`baseline-mupdf.tsv`; sweep 4 was 1.93%).

**One workbook at a time, 2026-10-15/16** (Windows, Excel 16 at 200% as
the references; labs printed through `test/xlsx-excel-pdf.ps1`). What
Excel was found to do, each checked on its workbook and its neighbours:

- *Rows.* A row nobody sized is fitted on the screen, in whole pixels, to
  its tallest font, and printed as a set height is (`fittedRow`); where
  the sheet sets its default height, a row whose height is only a fit is
  fitted afresh the same way. A set height prints cut down to whole dots
  of 600 dpi (`setRow`), and a row set to the sheet's default height is a
  set row, not a default one. A sheet with no `<sheetView>` prints its set
  heights halved (bug62181: 83 rows a page).
- *Text.* A cell shows its first 1,024 characters; text runs over its
  neighbours when it is a little too long, not only five times too long,
  and runs on across pages.
- *Fonts and colours.* A theme font (`scheme`) is the theme's face,
  whatever its name; a colour naming a theme slot and an rgb is the
  theme's; `[$-409]` prints nothing; xsd:boolean is "true" as well as "1".
- *Pages.* Repeated title rows take no second room on a page that shows
  them as its own (lo-tdf113271's first page).
- *Number formats.* A fill (`*x`) spans its cell: Accounting's "$" at
  the left, the number at the right. A theme colour's tint moves its
  luminance in HSL, not each channel. A header and footer print at the
  sheet's scale; `&D` has the whole year. Print options written "true"
  are on.
- *More number formats.* General shows eleven characters at most in a
  cell (the sign not counted), whatever the column's width. TEXT()
  refuses a scientific format with a small e (#VALUE!).
- *Paper.* At a stated print scale every row is a whole number of
  printer dots. A page keeps 8 dots free at its foot and at its side:
  rows and columns that fill it exactly, or within 7 dots, go on.
  Every row whose height is only a fit is fitted afresh (Excel keeps no
  such height: a lab of 30 pt rows without customHeight="1" printed at
  12.36), in its fonts' weight — save a row with raised or lowered rich
  text, which keeps the file's fit. A wrapped row is its lines, as our
  wrapping counts them, of its font's fitted line (LIBRE_OFFICE-116306-0's
  105 pt row is six of 14.52 in Excel's print).
- *Fitting a row.* A row fitted afresh is its tallest font's line even
  where that is under the default font's (57523's Calibri 10 rows,
  13.32 pt in a Calibri 11 book; labs: its defaultRowHeight, absent or
  9 or 20, changes nothing). The cells it has no record of count in the
  font they would take — the row's style, else the column's, else the
  default where the column styles stop (bug66675's stop at P: its rows
  of Arial 9 print at 14.52). A merged cell that wraps is not counted;
  one that does not wrap is (Tables' titles). An empty string is one
  line. At 100% too, rows are whole printer dots (13.32 is 111).
- *Wrapping.* A word that does not fit goes to the next line whole; a
  line may end after a hyphen; only a word longer than a line is cut,
  at the last character that fits (lab of long words in columns 5 to 25
  characters: Excel's wrap width is the printed column less 3.0-3.5 pt,
  and ours cuts at the same characters). Cell text is not kerned. The
  spaces a line breaks on go with the break.
- *More rows.* A row with a medium or thick border at its foot or head
  (`thickBot`, `thickTop`) fits one screen pixel taller for each.
- *Tables.* A styled table prints whole, empty or not; an empty header
  cell is "Column" and its place, as Excel refills it on opening. A
  style the file defines (`tableStyles`) is drawn from its dxfs, part
  over part: whole table, column stripes, row stripes, last and first
  columns, header, totals.
- *Headers and footers.* Each of &L, &C, &R starts in the default font
  (lab: Courier New Bold 16 on the left, Calibri 11 in the others); "& "
  is nothing. `blackAndWhite` prints no fills, text and rules black.
- *Packages.* Parts named with backslashes, in any case, and a sheet's
  relationship id under any prefix (49609, lo-tdf131575 open now).
- *Packages.* A part's relationships are found whatever the case of its
  name (chart-tdf100084's Sheet1.xml with _rels/sheet1.xml.rels).
- *Print areas* keep the columns they name, empty or not; only a
  whole-row area is cut to the sheet's columns.
- *Charts on a sheet.* The chart area's own fill and edge; a size the
  chart states printed as stated (only the defaults are three quarters
  of PowerPoint's); pie and doughnut labels with their names, percents,
  positions, moves, boxes and leader lines.
- *Charts.* A 3-D pie with no rotX is tilted 15° and stands in a box its
  file places itself, the room its exploded slices need left over. Its
  labels — name and percent, outside, on leader lines — are not drawn yet.

- *Wrapped text* that fits on one line is its font's line, not a
  measured line and a margin (lo-pivottable_invalid_formats lost a row a
  page to 0.14 pt). On paper its lines are the font's fitted line apart
  (the row it fits), not the face's own: Arial 10's 12.36 pt where ours
  were 11.0, Calibri 11's 14.52 for 13.0 (26 of Excel's prints). The
  line the vertical alignment holds stands where one line would. 97
  workbooks with wrapping styles: 26 better, none worse (CVLKRA-KYC 4.67
  -> 4.16, 52716 4.29 -> 4.04). Open: AverageTaxRates' bold Times New
  Roman 10 headings print 12.72 apart, regular Times' fitted line, where
  the bold face's table entry (34 px on screen) makes 12.36.

**2026-10-17/18, Windows** (each checked on its files against a build of
the same base; the commits give the numbers):

- *Fitting.* A wrapped row is fitted in its column's width on the
  screen (whole pixels at 192 dpi) less the cell's padding (as a General
  number's, 2⌈d/4⌉+1 px: CVLKRA-KYC), narrower than on paper
  (lo-tdf100034's two-line note). A printer's line between measured
  font sizes is the next dot up (49609's Microsoft Sans Serif 8.25).
  A `<col>` width the default's at 96 dpi is still that width in
  characters on paper, not the default: lo-forum-mso-de-104083's D, 11.43
  for a baseColWidth 10, prints 64.3 pt where the default's is 60.2
  (7.08 -> 6.70; 45 such workbooks, 8 better, 51710 +0.49, whose one
  9.14 column Excel prints half a 192-dpi pixel past either).
- *Ligatures.* A cell is set letter by letter, as Excel sets it: Carlito
  joined "ft" and "ti" (151 workbooks whose text has such pairs: 41
  better, 3 worse by 0.01; lo-forum-mso-de-104083 6.70 -> 6.16,
  CVLKRA-KYC 4.16 -> 3.69, lo-tdf113271 6.22 -> 5.75).
- *Printed size.* Excel prints a cell's font a whole number of 600-dpi
  pixels an em (Calibri 11 at 11.04 pt, 92; Arial and Times 10 at 9.96,
  83; at the page's scale), and each character a whole number of those
  pixels on from the last: its advance at that size rounded, or the
  face's own hinted width where its hdmx lists one (Arial's W is 83 at
  83 an em, its 0.9 em being 78.3; `SheetHinting`, generated from the
  Windows faces). Lucida Sans Typewriter 10 steps 50 (49.8), Verdana's
  digits 53 (52.77), Calibri 11's "Open - Not" 61, 48, 46, 48, 21. Ours
  sets each character so (`GridTextStyle.dots`), in what it draws and
  where it wraps, save in scripts that join their letters. All 720
  workbooks against the size alone, drawn grown: 233 better, 61 worse,
  mean 0.906 -> 0.890 (lo-forum-mso-en4-134670 2.60 -> 1.74, 56702 and
  dataValidationTableRange -0.47). Rounded without the hinting, Arial
  lost: FormulaEvalTestData_Copy 2.16 -> 2.60, now 2.20. Open: Verdana
  has no hdmx and its hinting widens some letters ("l" 24, rounded 23;
  1.5 dots in 30 letters).
- *Verdana* is set at its own widths in its stand-in, DejaVu Sans, as
  Word and Slides set it (`OfficeFonts.verdanaAdvances`), in what is
  drawn and in where lines break: 28 workbooks in Verdana, 17 better,
  one 0.01 worse (DateFormatTests 4.90 -> 4.00). A line of 40 letters
  then ends 0.46 pt past Excel's; at the printer's 9.96 it would end as
  far short, so it keeps the font's size.
- *Names that move.* A defined name's relative references are kept
  from A1 and read from the cell that uses it, round the sheet's edge:
  lo-tdf171828's sheet-local `rechne.Restkredit` reads `$G1048576`, the
  row above, and `XFD1`, the column to the left. `Sheet!Name` is a name
  (its `Hitab!Divisor`); it failed to parse, and every name using it was
  #NAME? (5.16 -> 4.89; its #NUM! totals are still open).
- *INDEX is no loop by its area.* It reads the one cell it picks, so
  lo-tdf171828's G13, ISNUMBER(INDEX(G:G, MATCH(…))) in column G, is
  blank in Excel's print, and its "Letzte Rate" the last payment's
  12/31/2044; the static walk for loops took the whole column as read
  and made G13 a loop's 0 (and the date 1/0/1900). The area still
  marks it for recalculation; a pick of its own cell is a loop when
  value() comes back to it. `--xlsx-check` with XLSX_CHECK_EVAL="Sheet!A1
  =formula|…" evaluates formulas as that cell would.
- *Rows past 18 pt.* Excel's print shows Times New Roman 20 fitted at 67
  screen pixels and its bold at 66 (Tables' "Exp2 (2)" at 49%, rows a
  whole printer dot: 99 and 98), where in proportion to 18 they were 68
  and 67 (Tables 6.93 -> 6.66, p2 9.07 -> 6.90). Measured, not modelled:
  carrying 18's row up by the font's own pixel line fits both, but
  predicts 16 from 14 and 18 from 16 no better than proportion (22 of
  76 exact either way).
- *Centred text runs over its empty neighbours*, half what it lacks to
  each side, each side as far as its cells are empty (lo-tdf171828's
  I14, "unter Berücksichtung der Sondertilgungen", 376.8 to 562.7 where
  Excel's is 377.3 to 563.2; ours stopped at its cell). The columns it
  crosses count as printed, as left and right text's do: 45540_classic's
  pie labels then print, but below Excel's (+0.15 each, the chart's own
  layout). A chart draws nothing outside its frame.
- *A face Excel has none of prints in Arial* (HelveticaNeue LightExt,
  Frutiger 45 Light, Clear Sans, FreeSans, GE Inspira Sans,
  BernhardFashion BT in lo-tdf171828's header; "Arial Cyr" too), where
  Word's rule had made it Cambria: 48495 0.76 -> 0.51, 47862 0.19 ->
  0.08, lo-orderOfCNumFmtElements' cells to within 0.01 pt of Excel's.
- *Literals among the digits stay among them.* `###"."###"."##0` puts
  1234567 as "1.234.567", and `#"."##0` puts 0 as ".0" (lo-tdf76115's
  account numbers, which printed "0."); `(###) ###-####` is a phone number,
  `00\ 00\ 00` (lo-tdf81939); the integer fills its placeholders from
  the right, any more digits before the first, the fraction from the
  left. Three such workbooks, all better.
- *Functions to Excel's last digit.* AGGREGATE's options 4-7 keep the
  SUBTOTAL and AGGREGATE cells they cover (0-3 leave them out), and
  0, 2, 4, 6 the filtered rows; its 13 is MODE.SNGL, the first of a
  tie, where ours took MEDIAN. A logical argument of 0 is FALSE
  (NORM.S.DIST(x,0) is the density; ADDRESS's style). A variance is
  taken as one, not a deviation squared. ROUND goes through the
  number's 15 significant digits, as Excel's: an ulp's nudge of the
  scaled number made 939.01382419233744 ...338 at 12 places. Every
  formula of lo-functions-excel-2010 now agrees with Excel's (128
  differed; 4.35 -> 4.19); no other of the 720 changed.
- *A sheet's own names.* A name with a localSheetId is that sheet's:
  each sheet reads its own before the book's, and `Sheet!Name` the
  named sheet's (lo-named-ranges-global's two Local1s, 3 and 5, both
  read 5). On reading, a book-wide name is never overwritten by a
  sheet's of the same name.
- *Header and footer lines.* Excel's header stands 1.2 pt below the
  line of its margin and its footer 1.75 above, measured on the first
  pages of the corpus (a Times 12 header 12.18 under the header margin,
  ours 11.0; a Times 12 footer's baseline 4.64 over the footer margin,
  ours 3.05; Arial 9.96 and Calibri 11.04 the same within 0.15). 94
  workbooks with either: 83 better, 2 worse by 0.02 at most. Open:
  Arial 11.04 footers (5 workbooks) stand 0.65 over Excel's with it.
- *Arrays, element by element.* A one-number function (SIGN, ABS…)
  takes an array element by element in any formula, a range in a
  dynamic one; so do IFERROR and IFNA, MATCH over an array of keys
  (exact keys through a table of first places), IF over an array of
  conditions, and in a dynamic formula ROW and COLUMN of a range.
  lo-forum-mso-en4-134670's distinct counts, SUM(SIGN(FREQUENCY(
  IFERROR(IF(…, MATCH(B:B,B:B,0)),""), ROW(…)))), were 0: 153 cells now
  Excel's. CEILING and FLOOR of a positive number by a negative step
  are #NUM! (lo-ceiling-floor, every cell now Excel's).
- *A hair border is one printer dot*, solid, as Excel prints it
  (0.12 pt; its thin ones 0.96): ours drew 0.96 at half strength, a
  grid of them heavy and black. The 12 workbooks with hair borders: 7
  better, none worse (lo-tdf85617 3.55 -> 0.25, 54206 4.82 -> 1.62).
- *Dashed and dotted borders* print Excel's runs, on and off in printer
  dots (lo-cell-borders, a row of each kind): dotted 4 and 4, dashed 24
  and 8, a dash-dot's dash 72 and dot 24 with gaps of 24, the medium
  kinds the same at 16 dots wide, slantDashDot as mediumDashDot. Ours
  were 25 and 17 for all. Open: mediumDashed starts 33 dots into its
  run in Excel's.
- *Tahoma* prints in Tahoma on Windows, at its hinted widths (it had
  been Liberation Sans): the 38 workbooks in it, 5 better, one 0.01
  worse (Excel_file_with_trash_item 4.71 -> 4.24). Open: bottom-aligned,
  Excel's Tahoma 10 stands on its row's Calibri 11 baseline, a point
  over ours, which puts a cell's descent a point over its foot.
  Segoe UI, Georgia, Consolas, Book Antiqua and Calibri Light print in
  their own faces too (Segoe UI's and Georgia's hinted widths with
  them): the 16 workbooks in them, 3 better, none worse (lo-tdf76115
  4.46 -> 4.03).
  On Windows Verdana is Verdana, not DejaVu Sans at Verdana's widths:
  its 28 workbooks 15 better, 4 worse by 0.05 at most (atp 0.68 ->
  0.16, the format tests 0.03 to 0.24 better).
  Arial and Times New Roman too, though their clones have their
  measures: lo-pivottable_invalid_formats' page of Arial 10 stood within
  half a point of Excel's and 9.9% apart, in the letters. All 720
  workbooks: 98 better, 8 worse by 0.08 at most, 0.864 -> 0.856
  (lo-tdf100034 4.27 -> 3.67, bug62181 4.15 -> 3.56, 46535 1.03 ->
  0.48).
- *A run of one fill down the rows is one rect*, as Excel's page has
  it (54288's grey blocks, one rect each in Excel's print, showed a pale
  seam under every row of ours): all 720 workbooks, 8 better, 4 worse
  by 0.02 at most (lo-tdf105272 2.08 -> 1.22, 54288 3.86 -> 3.43).
- *A turned picture* is drawn turned (`a:xfrm@rot`), its anchor the
  turned box with its sides swapped between 45° and 135°, as a shape's:
  lo-twoCellAnchor_editAs_oneCell's at 240° prints 330 by 352 pt in
  Excel's print, ours had stood upright in 218 by 284. The three such
  workbooks: 4.01 -> 0.17, 0.73 -> 0.00, 0.19 -> 0.05.
- *A merged area centres its text four printer dots higher* than a
  lone cell in its row: 0.48 pt in Excel's prints of nine workbooks,
  at 80% and at 100%, where ours stood level (Tables' "PRSI Liability"
  over "GROSS", simple-monthly-budget, the 45540 forms). Set at the
  foot, a merge stands level. The 33 workbooks with a centred merge:
  the merged text now within 0.2 of Excel's against its row, the pixel
  scores even (5 better, 8 worse by 0.12 at most, 3.735 -> 3.738): the
  45540 forms' rows already stand 0.5 to 0.9 high, and the lift takes
  their merged text with them.
- *A cell's text against its row, by face* (open). Measured in Excel's
  prints, from a cell's own thin bottom border (bottom-aligned) or the
  rule above (top-aligned), unmerged and unwrapped. Ours sits on our
  line's height, which is whole 96-dpi pixels, so it lands in whole
  points: 4.00 for Calibri 11, 3.00 for Arial 10 and the small faces.
  Excel, at the foot (baseline to border): Calibri 11 3.96, Calibri 10
  3.60, Arial 10 3.12, Arial 10 bold 3.60, Times New Roman 7 2.52,
  Lucida Sans Typewriter 10 3.30, Verdana 10 3.10. A point plus the
  face's usWinDescent fits Calibri 11, Arial 10, Times 7 and Verdana to
  0.02, but not Lucida or bold Arial (0.26 and 0.49 short), nor
  bug62181's Arial 9 (0.15 over). Taken whole, it cost bug62181 1.08
  and was taken back. Small text also stands on its row's larger font
  at times: Tahoma 8 and Times 7 at Calibri 11's 3.96 where the row
  has unstyled columns (conditional_formatting_with_formula_on_second_
  sheet, lo-tdf118668), 57523's Calibri 10 on its row's empty Calibri
  11 cells; but 45540_form's Times 7 keeps its own 2.52 beside Times 9
  cells with values. At the head (rule to baseline): Calibri 11 11.04,
  Calibri 10 9.96 (each its em), Verdana 10 10.38 (ours 11.00, the
  format tests' text 0.6 low), Lucida 10.02. A lab of each face at a
  few sizes, set at foot and head, under a border, would settle both.
- *Printed headings' strip* (open). The format tests' columns stand
  0.20 pt left of Excel's, their text with them: whole-dot advances took
  away the extra width that had carried it back over Excel's, and the
  eight format-test workbooks lost 0.07 to 0.93 for it. Excel's frame
  starts at the margin (54.0, 14.16; 0.96 where the margin is 0), ours
  0.48 in; and its strip, to column A's gridline, is three digits and
  4.88 pt in Verdana 10, 4.38 in Calibri 11 (lo-tdf136721), 3.9 in
  Arial 8 (lo-tdf131575) — ours three digits and 0.42 of the size
  (4.2, 4.62, 3.36). No one rule fits the three yet: a lab of the
  strip in a few faces and sizes would.
- *Cells.* A General number on paper holds the column's characters less
  its padding (lo-Sparklines' 3.337809). textRotation 90 and 180 are
  drawn turned; a row of turned text keeps the file's fit. Text runs
  over its neighbours as far as it reaches from its indent. A
  conditional format's numFmt applies. A drawing with
  fPrintsWithSheet="0" is left off the page.
- *Headings* print at their cells' foot, the row-number strip three
  digits and 0.42 of the default size wide.
- *Pivot tables* in PivotStyleLight 15-21. A pivot written without its
  cells (64450, from Google Sheets) is not drawn: Excel lays it out from
  its cache.
- *Charts.* Excel 2016 (`cx:`) clustered columns, box-and-whisker,
  waterfall, funnel, histogram (binned clusteredColumn: Scott's width
  to two figures, "[lo, hi]" then "(lo, hi]", "≤ u" and "> o") and
  pareto, their data read live through hidden names (_xlchart.v1.*);
  sunburst and treemap trees built from the cells (a name's blank
  inherits the row above's); region maps are not drawn yet, nor a
  chartex title's own box fill. A treemap is Excel's strip layout, not
  squarified: each level larger first in rows across its parent, a row
  taking the next node while its boxes' mean aspect does not worsen, and
  the whole next row where one row of both is squarer (2026-10-22:
  chart-treemap's 15 boxes within 0.06 pt, 6.81 -> 0.75). A `cx:`
  title on a sheet stands 8.2 pt under the frame's top, 2.4 lower than
  a `c:` one (eleven prints). On a sheet a `c:` chart's plot starts
  2.57 pt lower under a title (2.05 in a 2007-style chart) and 1.25
  higher with none (1.62), its foot where ours was: 70 column, line and
  scatter charts, their titles already on Excel's baselines. A legend
  below stands 2.2 pt higher and the plot's foot 4.43 (nine prints); a
  data table's plot starts 11.1 pt under the frame, not 11.1 px
  (2026-10-23: 184 chart books 1.237 -> 1.200, 97 better, 24 worse, the
  worst +0.34: chart-tdf114139's 3-D pie, already too small and high).
  Two bar groups on one pair of axes are one
  group; two line groups on two axes are drawn; a gradient chart area;
  a varied single bar series' legend of its points; labels at zero over
  negative values; "Series1"; an empty axis title's room. Open: a
  secondary axis' title. A series that sets no colour takes the theme's
  for its c:idx, not its place (47813's red and green). A point's or
  series' gradFill is drawn in the gradient's mean colour. Categories in
  slots thinner than their font stand upright, one to each font size of
  room (47813's 720: 1, 17, 33…). A 2007-style chart that states no text
  size prints at 10 pt, its title at 18 (ours were 7.5 and 14).
  Pie of pie and bar of pie draw their second plot (split by position,
  value, percent or list; the last third when unsaid); the gap between
  the two is fitted to two prints, not a rule.
  A chart part in the default namespace (openpyxl's) is read with the
  usual prefixes; a title that says nothing of its look is 18 pt, not
  bold, axis titles too (chart-tdf119138, whose four charts were not
  drawn). A title's own box (fill, line, dash) and a pie's series outline
  are drawn. A sheet's chart title (and plot under it) stands 2.5 pt
  lower than PowerPoint's; a pie whose labels stand round it gives them a
  line a side.
  A printed page's cells stand 0.48 pt (four printer dots) in from the
  left and top margins, its drawings not (2026-10-22): Excel's first
  fills at (+0.48, +0.48) from ours in 140 of 210 workbooks, any face
  and size — the rest had a drawing first. Not along an axis the page is
  centred on. Every workbook: 1.148 -> 0.918 (468 better, 83 worse;
  lo-forum-mso-en4-134670 9.76 -> 4.34, NumberFormatApproxTests 12.65 ->
  7.34). Open: lo-tdf58243 (fit to page, centred across) wants no
  vertical inset either (6.81 -> 7.90); lo-tdf91332's border 0.76 low;
  Across a centred page the cells stand 0.48 LEFT of plain centring
  (Excel centres them as if 0.96 wider): the 18 centred workbooks 4.321
  -> 4.198, 11 better, Tables +0.59 and chart-tdf140489 +0.32 worse
  (tdf140489's band 0.38 wider than Excel's at its 90%).
  With the cells in place, right-aligned text keeps the left side's
  margin (0.48 + a quarter digit): the 0.4 pt the right had stood closer
  was measured against cells 0.48 left of Excel's. 0.918 -> 0.902 (277
  better, 20 worse; bug62181 5.53 -> 4.37, 49609 +1.25).
  A drawing's anchor offset on paper is not its share of the cell (as
  from 2026-10-12) but its points scaled as Excel scales its 192 dpi
  screen: across by the printer's digit over the screen's (Calibri 11
  47 dots / 15 px = 1.003, Calibri 10 42 / 14 = 0.96), down by the row
  scale. chart-treemap's and -testCombinedChartAxis's frames now within
  0.3 pt of Excel's (were 0.8 to 2.9 right), 53568's pictures 0.30 ->
  0.04; 277 drawing workbooks mean 1.292 -> 1.206 (161 better, 32
  worse). A one-cell anchor's size is not scaled: scaled, tdf119138's
  and tdf100084's charts printed larger than Excel's.
  Open, fitting: a wrapped word too long for its column breaks inside
  in Excel's screen layout otherwise than in ours, which measures the
  printed face against the screen's width: LIBRE_OFFICE-116306-0's
  "NONKQUB|ELA/NTLO…" fits five lines in Excel, seven in ours; 52716's
  e-mail addresses likewise.
  Open: bug66675's "Nomination Point Name" header rows (ht 18, not
  custom; bold Arial 9, wrapped, bottom-aligned; merged A:D and E:G)
  print 15.24 pt in Excel's print, 127 dots, its centred "Gas" rows and
  its data rows 14.52 — every such page 0.72 pt a table further off.
  Not tried in a lab: the box's display is at 100% now, where a fitted
  Calibri 11 row prints 15.24 (the references were made at 200%).
  Open: chart-fdo78080's chart (LibreOffice's: no c:title, no
  autoTitleDeleted, no varyColors) has no title in Excel's print and a
  legend of its points; ours titles it "col1" as PowerPoint would. One
  file, and chart-fdo54361-1 without varyColors keeps "Series1": not a
  rule yet. chart-tdf140489 is not drawn: an area and a line on hidden
  axes and a scatter series that only sizes the year axis, a combination
  the reader turns down.
  Open: a 3-D chart's series one behind another (chart-tdf111824), and
  a 3-D line chart's axis (LIBRE_OFFICE-128382-0: 0 to 10,000 for data
  to 9,579.5, where the 2-D rule's headroom makes 12,000).
- *Fills and frames* (2026-10-18). A row's run of one fill is one rect,
  as Excel's page has it: cell by cell left pale seams. A shape's
  fillRef reaches the theme's fill style (a gradient of the accent). A
  page printing gridlines or headings is framed, 0.96 pt inside its edge
  at any scale. The POI fuzzer workbook prints on Letter in Excel though
  it asks for A4, every sheet at 0.92 of its scale (87% as 80%, 95%
  as 87%), though neither printerSettings part says so: Excel repaired
  it (sheet8's CRC is bad); not ours to follow. 1_NoIden's reference
  is another machine's: it embeds Dotum, which every other print of a
  돋움 workbook sets in Malgun Gothic, and its narrower columns put D
  on a page of its own.
- *Packages* (2026-10-18). Zip64 sizes and offsets are read
  (lo-tdf82984_zip64XLSXImport). An encrypted package (OLE compound
  file: EncryptionInfo, EncryptedPackage) opens where Excel's built-in
  password "VelvetSweatshop" unlocks it, Standard or Agile (58616).
  Open: asking for a password of the file's own (protected_passtika's
  "tika"; ZipError.passwordRequired reaches the UI as a failed open).
  The zip64 book has no theme part, and Excel fits its Calibri 11 rows
  at 21 screen pixels (15.24 pt printed), not the usual 20 (14.52).
  A full sweep at the tip: 1.225% mean over 756 workbooks, every page
  count Excel's.

(The commit "a row set to the sheet's default height keeps its set
height" says lo-tdf113271 makes twelve pages: it still makes eleven. Its
first page is Excel's now; its later pages hold a row more than Excel's,
whose repeated title seems to take a little more than the row did.)

Tried and taken back, 2026-10-17: printed gridlines drawn as Excel's page
has them, each twice — a one-dot (0.12 pt) rule and a 0.14 pt line over
it, which rasterise darker than our single dot (lo-tdf100034's black
grid against our grey). All nineteen workbooks that print gridlines got
worse, 0.0 to 0.6 (GeneralFormatTests 8.32 -> 8.85): our lines stand a
fraction of a point off Excel's, and a darker line only widens the miss.
Also open: set row heights a printer dot short of Excel's at some
heights (lo-tdf131575's 15 pt rows in Arial 8, 125.93 dots: Excel 126,
ours 125). Not a threshold on the fraction: the set-height labs (h-a10,
h-c11, no sheetView, so halved) have only their 20 pt rows one over, at
fractions .78 and .91, while 40 pt at .82 is cut down — and no cut of a
height linear in h makes 20 pt 81 dots and 40 pt 161. Some intermediate
(the screen's pixels?) is rounded first.

Tried and taken back, 2026-10-16: Lucida Sans Typewriter drawn in
Liberation Mono: the right widths, a serifed face where Excel's is
sans, a little further from Excel's pages. And rows in whole dots at a
fitted scale (cut once, then again at the scale the cut came to):
further from Excel's pages, 165.9 -> 170.1 over the scaled and fitted
workbooks.

Tried and taken back: "any formatted cell widens what prints, though it
does not lengthen it" gave FormatConditionTests Excel's fourth page (29.6%
-> 6.0%) and lo-user_defined_function eleven pages too many — its empty
cells in BE:BG have their column's own format; lo-tdf113271's F3 has a
format its column lacks and does not widen Excel's print either.
Solved 2026-10-17: it was never H7 (a lab without it prints the same
four pages) but row 1's span — a filled row style with spans="1:8"
over cells A-D, whose missing E-H Excel makes cells in the row's fill.
With spans="1:4" Excel prints three pages, as we did.

Tried and taken back, 2026-10-16: placing a cell's baseline from a
table of the cell's face and size. Labs in a Calibri 11 book (gridlines
printed, Excel 16) put every bottom-aligned face to 11 or 12 pt 4.02 pt
(33.5 printer dots) above its row's edge, in rows of 9 to 60 pt, set
or fitted; ours stands 1 pt + the face's descent (3.0 at Calibri 10 or
Arial 10). Top- and centre-aligned baselines came from the same labs,
and all three matched the labs to 0.1 pt once the paragraph's whole-
point rounding of its ascent was allowed for. The corpus got worse
(1.390 -> 1.401%, 2 better, 34 worse), because the drop depends on the
BOOK's default font as well: small fonts stand 4.02 up in a Calibri 11
book, 3.18 in an Arial 10 book, 3.66 in a Calibri 10 or Arial 12 book,
while a Calibri 11 cell stands 4.14 up in every one of those and 4.02
in its own; Arial 12 cells 3.18 in three books, 3.54 in the fourth. A
row printed 4 dots short of its height (some lab rows were) keeps its
text where the full row would have put it. The patch and labs
(mkbase*.py, mkrows.py, baseln*.py) are in that session's scratchpad;
the rule that joins cell font, book font and row is still open.
Second try, 2026-10-17: labs of fitted rows in four books (Calibri 11,
Arial 10, Calibri 10, Arial 12) show a cell whose font's line is no
taller than the default row standing on the DEFAULT font's win descent
plus 1.05 pt (3.18, 3.66, 3.66, 4.02 — within a printer dot), and a
taller font on its own (Calibri 11 4.14, Arial 12 3.18, Calibri 12
4.50-4.62), though Arial 12 as the default stands at 3.18, not 3.59.
That rule alone: corpus neutral (1.435 -> 1.436, 11 better, 13 worse);
the worse are Calibri 11 books whose rows are fitted shorter than the
default (57523's 13.32 pt rows of Calibri 10), where Excel's drop lies
between the rule's and the font's own. A lab of such rows (Calibri 11
book, every column styled Calibri 10, unsized rows): every face stands
9.66 pt below the row's TOP (drop 3.66 in 13.32 rows), where set rows
of any height, 9 pt to 60, keep 4.02 from the bottom; and a row of
Calibri 8 there is 12.84, which neither its own line nor the columns'
Calibri 10 makes. Labs: mkshort.py, mkrows.py, mkbase-fit.py.

Held back, 2026-10-16: drawing and chart parts written in their own
namespace as the default (`<wsDr xmlns="…spreadsheetDrawing">`,
`<chartSpace xmlns="…chart">`, chart-tdf119138 and chart-tdf137734)
read once their element names are given the `xdr:` and `c:` prefixes,
and tdf119138's four charts then draw, from their sheet references, in
the right places — but with no text properties their text comes out at
our defaults, far smaller than Excel's (its title and axis titles about
13 pt, tick labels about 8), and the page scores worse (6.88 -> 9.45).
The reader half waits for those defaults (a lab of a chart with no
txPr and `<c:style val="10"/>`).

Not understood: in 45544's "Hires by Location" Excel prints the page a
footnote runs onto, blank — the run-over text not drawn there — though
in labs and in lo-cell-value it draws it; the column widths decide it,
not their styles, centring or page setup.

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
formatted, empty H7 and not down to formatted, empty D55–D342; 52348's rows at 15.94 pt for a set
15 (a workbook with no cell styles part).

Understood since (2026-10-15): a row holding Lucida Sans Typewriter 10
in a Verdana 10 workbook is 13.32 pt because Excel fits a row nobody
sized on the screen — 34 px — and prints those pixels as it prints a set
height (`SheetPrintMetrics.fittedRow`), not at the font's own printed
line. And text runs over its neighbours when it is a little too long, not
only five times too long (NumberFormatTests' column E, five pages).

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
