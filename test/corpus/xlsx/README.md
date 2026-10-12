# The .xlsx corpus

What Sheets is measured against: 810 real workbooks, as downloaded on
2026-10-11. The counterpart of `test/corpus/pptx`, and meant to work the
same way — the workbooks, Excel's own printing of each as a PDF, and a
baseline of how far this app's printing is from it.

    books/         the workbooks, as downloaded
    SHA256SUMS     of books/, to tell a changed workbook from a changed painter
    excel/         NAME-orig.pdf — Excel's print of books/NAME.xlsx, and export.tsv
    baseline-mupdf.tsv   each workbook's score at the first sweep (2026-10-11, Windows, MuPDF's page diff)
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
new baseline.

## The first sweep

    test/xlsx-app-render.sh                  # every workbook, into ~/starling-xls-check/app
    python3 test/pptx-corpus-groups.py xlsx  # matched / others from the baseline

`baseline-mupdf.tsv` is sweep 1, 2026-10-11, the Windows build scored by
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
