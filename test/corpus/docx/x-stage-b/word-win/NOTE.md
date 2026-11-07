# Word for Windows prints of corpus batch B (Windows 01QbbApP)

Source: origin/wip/corpus-new-b 7bd94723 (241 docs) plus the 22 later-added docs lenovo-5's cut keeps.
Method: print.sh — one fresh Word per document, 8 s settle, warm doc first; PDFs stay local on the Windows box
(~/starling-doc-check/lab/corpusb/docs and corpusb2), not in git.

- PAGES-B.tsv: stem, Word page count, PDF sha256 — 240 of the 241 (all but the one below).
  kor-z23967513 and docx-ab94b38c were printed before they were removed from the branch; they are still in the table.
- PAGES-B22.tsv: the same for the 22 later docs.

## Refused / repair / timeout
- Refused to open: **jpn-z19987559-2cbb2b** — "Word experienced an error trying to open the file". The docx is an intact
  zip (SHA matches SHA256SUMS, testzip clean, 26 entries, with explicit `word/` and `docProps/` directory entries).
  No PDF was made.
- Repair prompts: none seen (every other print ended "ok"; the worker would log an error otherwise).
- Timeouts: none.
