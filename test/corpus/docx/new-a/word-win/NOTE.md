# Word for Windows prints of corpus batch A (Windows 01QbbApP)

Source: origin/wip/corpus-new-a 38a22daf docs (170), minus the 56 in skip-A.txt = 114 printed.
Method: one fresh Word per document (8 s settle, warm doc first); 70 serial, the rest 4-way (parallel was checked
equal to a fresh serial print on 30 batch B docs). PDFs stay local in ~/starling-doc-check/lab/corpusa/docs.
PAGES-A.tsv: stem, Word page count, PDF sha256 (109 docs).

## Word could not print (identical failure serially and 4-way, so not a parallelism effect)
- lo-2af13d3cd9 — "Call was rejected by callee (RPC_E_CALL_REJECTED)"
- lo-2c2ec58d2a — "The file appears to be corrupted."
- lo-526c0b4970 — "The export failed. The document could not be prepared for exporting."
- lo-b286e0dc69 — "The file appears to be corrupted."
- poi-0c58de6a75 — "The file appears to be corrupted."
No repair prompts or timeouts otherwise.

## Blank-page check (asked for)
Printed from the original docx (lo-9b628b6d46 and th-8202f4ed00 are in skip-A, printed separately):
- lo-9b628b6d46: 3 pages; p1 has one character and no drawings (effectively blank), p2 has the content, p3 is completely empty.
- oxsdk-1c09b12993: 19 pages; no blank page (1,300-1,800 characters on every page).
- th-8202f4ed00: 2 pages; p2 has no text and one drawing (blank-looking).

Note: batch A was printed before the cloud faces were all downloaded (see the batch B drift: Traditional Arabic,
Roboto Mono etc. arrive on first use), so a later reprint may change some of these.
