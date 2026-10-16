# The .xlsx corpus

What Sheets is measured against: 810 real workbooks, as downloaded on
2026-10-11. The counterpart of `test/corpus/pptx`, and meant to work the
same way — the workbooks, Excel's own printing of each as a PDF, and a
baseline of how far this app's printing is from it.

    books/         the workbooks, as downloaded
    SHA256SUMS     of books/, to tell a changed workbook from a changed painter
    excel/         NAME-orig.pdf — Excel's print of books/NAME.xlsx, and export.tsv
    baseline-mupdf.tsv   each workbook's score at sweep 14 (2026-10-16, Windows, MuPDF's page diff)
    matched-mupdf.txt, others-mupdf.txt   the two groups of that baseline

## What works today

    OfficeApp --xlsx-check test/corpus/xlsx/books/*.xlsx     # the formula oracle
    OFFICE_APP=… python3 test/xlsx-corpus.py                 # read, save, read again
    OfficeApp --sheet-pdf BOOK.xlsx OUT.pdf                  # this app's print of a workbook

The formula oracle needs nothing but the files: every formula cell
carries the value Excel last computed for it, and `--xlsx-check`
recalculates and compares (`docs/plans/sheets.md` has the numbers).
`--sheet-pdf` prints the entire workbook — every visible sheet, in tab
order, cut into pages by the file's page setup — without a window; of the
810, 736 print, 56 have nothing this app finds to print, and 18 are files
it does not read (broken on purpose, encrypted, or not workbooks).

## Excel's side

`excel/` was made on 2026-10-11 by Excel for Windows 16.0 (build 20430),
with "Microsoft Print to PDF" as the active printer, through

    test/xlsx-excel-render.sh test/corpus/xlsx/books test/corpus/xlsx/excel

which drives Excel over COM (`test/xlsx-excel-pdf.ps1`: open read-only,
links not updated, macros off, `ExportAsFixedFormat` of the whole
workbook, first 20 pages) and writes `excel/NAME-orig.pdf` and
`excel/export.tsv`, a verdict per workbook. Of the 810: 757 have a PDF
(2,097 pages), 50 Excel will not open at all, and 3 hang it past the
180 s limit (`chart-tdf81396`, a `crash-*` file, and
`protected_passtika`, which wants a password). The 50 are mostly the
fuzzer and proof-of-concept files, with some LibreOffice test files
Excel refuses even to repair (`lo-formats`, `lo-tdf100709`…): a plain
open and an open with `CorruptLoad = xlRepairFile` both fail with
0x800A03EC. `export.tsv` names every one.

Run it from a shell that is not elevated (a scheduled task with
`-RunLevel Limited` does, from an elevated session). It takes about an
hour: Excel starts afresh for every workbook. A workbook that times out
leaves its hidden Excel behind, sitting on a dialog — kill `EXCEL.EXE`
afterwards. Two exports failed once with `RPC_E_CALL_REJECTED` and went
through on a second run; delete such a row from `export.tsv` and run
again, since rows already there are skipped.

Excel cuts pages by the active printer's metrics, so references made
with another printer, or another Excel, are another set: regenerate all
of them or none, record the version and printer here, and sweep for a
new baseline. Two more things about the machine are in these pages:

- **The paper is the workbook's.** Excel's "Scale content for A4 or
  8.5 x 11" paper sizes" (on by default) prints a workbook set up for A4
  on Letter where Letter is the region's paper — the first run did that to
  252 workbooks. The script turns the option off for the export and puts
  it back (`MapPaperSize`); those 252 were made again on 2026-10-12.
- **The display was at 200%.** Excel sizes a printed sheet by the
  printer's font metrics, not the screen's, but two things still come from
  the screen: the default column (taken up to a multiple of 8 screen
  pixels) and the scale of a row height someone set (the printer's line
  over the screen's). At 200% the default column of a Calibri 11 workbook
  prints 51.1 pt wide and a 20 pt row 20.3 pt high; at 100% they would be
  about 51.6 and 19.4. `Sheets/SheetPrintMetrics.swift` holds the measured
  numbers and says how they were measured.

A PDF with no pages is Excel's answer for a workbook with nothing to
print (36 of them); the sweep scores that as a match when this app also
finds nothing.

## The first sweep

    test/xlsx-app-render.sh                  # every workbook, into ~/starling-xls-check/app
    python3 test/pptx-corpus-groups.py xlsx  # matched / others from the baseline

Sweep 1 was 2026-10-11, the Windows build scored by
`test/pdf-diff.py` (MuPDF; a Mac's sweep would be `baseline.tsv`, by
CoreGraphics, and its own numbers — see the .pptx corpus's README). It
takes about eleven minutes. Of the 757 workbooks Excel printed:

| | workbooks |
|---|---|
| scored | 705 (1,997 pages) |
| "nothing to print" here, where Excel printed something | 46 |
| not read by this app | 6 |

Over the 705: mean 11.1% of pixels differing, median 1.1%; 404 at or
under 2%, 159 between 2 and 20, 142 over 20. One workbook matches Excel
exactly on every page. The mean is carried by page counts: 144
workbooks have at least one page that is 100% — a page Excel has and
this app does not, or the other way — so where the pages are cut is the
first thing to look at, ahead of anything drawn on them.

## Sweep 2

2026-10-12, after 252 references were made again on their own paper and
the app learned how Excel sizes a sheet for the printer, and to draw
embedded objects and controls (`docs/plans/sheets.md` has the list). Of the 757:

| | workbooks |
|---|---|
| scored | 750 |
| not read by this app, or nothing found to print where Excel printed | 7 |

Over the 750: mean 3.24% of pixels differing, median 0.42%; 577 at or
under 2%, 143 between 2 and 20, 30 over 20; 37 have a page only one side
has. 43 match exactly, 36 of them workbooks neither side prints a page
of. The first sweep's figures above are kept for the comparison.

## Sweep 3

Later the same day: chart sheets, 3-D and empty charts, fit-to-pages,
rows fitted to their fonts and wrapped text, black gridlines. Over the
same 750: mean 2.81%, median 0.40%; 583 at or under 2%, 145 between 2 and
20, 22 over 20; 27 have a page only one side has; 42 exact (an empty
chart's frame is drawn now, 0.02% from Excel's).

## Sweep 4

The same day again, one workbook and one cause at a time
(`docs/plans/sheets.md` lists them). 751 scored, 6 not read or with
nothing found to print: mean 1.93%, median 0.40%; 594 at or under 2%,
150 between 2 and 20, 7 over 20; 10 have a page only one side has; 42
exact.

## Sweep 7

2026-10-16, after a day and a night of the same (`docs/plans/sheets.md`,
"One workbook at a time"). 751 scored: mean 1.55%, median 0.41%; 600 at
or under 2%, 149 between 2 and 20, 2 over 20; 5 have a page only one side
has; 43 exact.

## Sweep 14

The same day, later (`docs/plans/sheets.md`). 751 scored: mean 1.43%,
median 0.39%; 604 at or under 2%, 146 between 2 and 20, 1 over 20 (the
not-understood FormatConditionTests); 1 has a page only one side has;
45 exact. This is `baseline-mupdf.tsv`.

## Where the workbooks come from, and their licences

None of these files is ours. They are test data that two projects
publish, copied here unchanged, and each stays under the licence and
copyright it came with:

| names | from | licence of the source repository |
|---|---|---|
| no prefix (352, 19 of them fuzzer or proof-of-concept files) | Apache POI, `test-data/spreadsheet` | Apache License 2.0 |
| `lo-*` (303) | LibreOffice core, `sc/qa/unit/data/xlsx` | Mozilla Public License 2.0 |
| `chart-*` (155) | LibreOffice core, `chart2/qa/extras/data/xlsx` | Mozilla Public License 2.0 |

The prefixes were added on download to keep the sources apart; strip
`lo-` or `chart-` for the upstream name. Many are attachments from those
projects' bug reports; their authors hold the copyright, and they are
here only as inputs to a test, as they are upstream. The `clusterfuzz-*`,
`crash-*` and `poc-*` files are deliberately broken.

If you hold the rights to one of these and want it gone, removing the
workbook (and its PDF and baseline row, once there are any) is all it
takes; no gate depends on any one of them.
