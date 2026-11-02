Lab ftr — which size Word for Windows prints for a PAGE field in a footer text box (mc:AlternateContent). NOT for office.
1. python build.py test/corpus/docx/docs/zh-2e7ef069*.docx OUT   -> OUT/ftr-v0..v6.docx (eleven pages each; see build.py's header)
2. Print each in a FRESH Word for Windows (quit between, none open), PDF named ftr-v?.pdf.
3. python meas.py OUT/ftr-*.pdf -> per print and page: the footer's text, size, x range, y. Send that output and the PDFs.
Question: v0 is the corpus file shape; Word printed 9pt " - 10 - " there though every run in the box says 14pt. What changes it: the field switch (v1), the runs (v2), the number format (v3), the box width (v4), wrap (v5), the cached result (v6)? Pages 1..11 of v0 also say whether it is page 10 only.
