# The .xlsx corpus

What Sheets is measured against: 810 real workbooks, as downloaded on
2026-10-11. The counterpart of `test/corpus/pptx`, and meant to work the
same way — the workbooks, Excel's own printing of each as a PDF, and a
baseline of how far this app's printing is from it.

    books/         the workbooks, as downloaded
    SHA256SUMS     of books/, to tell a changed workbook from a changed painter
    excel/         NAME-orig.pdf — Excel's print of books/NAME.xlsx   (NOT MADE YET)
    baseline.tsv   each workbook's score at the last recorded sweep  (NOT MADE YET)

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

## Excel's side: still to be made, on Windows

    test/xlsx-excel-render.sh test/corpus/xlsx/books test/corpus/xlsx/excel

drives Excel over COM (`test/xlsx-excel-pdf.ps1`: open read-only, links
not updated, macros off, `ExportAsFixedFormat` of the whole workbook,
first 20 pages) and writes `excel/NAME-orig.pdf` and `excel/export.tsv`.
It has not been run: it was written on a Mac whose Excel (16.113,
unlicensed) opens workbooks read-only with File → Print… disabled, and
whose scripted `save as … PDF file format` and `print out` both answer
without error and write nothing. Expect to fix the script on its first
run. When the PDFs exist:

    test/xlsx-app-render.sh                  # every workbook, into ~/starling-xls-check/app
    python3 test/pptx-corpus-groups.py xlsx  # matched.txt / others.txt from the baseline

and the sweep's `render.tsv`, sorted, is the first `baseline.tsv`. Record
here the Excel version and the printer it had active: Excel cuts pages by
the active printer's metrics, so references from another printer are
another set.

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
