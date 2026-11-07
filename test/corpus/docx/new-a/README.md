# new-a: staging batch A for the Word corpus curation (docs/plans/word-corpus-curation.md, section 3)

NOT in any gate. 170 candidate documents, 1,670 pages (page counts are from our
own render, Windows mode; Word's may differ). `manifest.tsv` has each file's
source URL, licence, SHA-256, language and the feature tokens it adds
(tokens from `docx-features.py` plus a few XML probes; the census tool has not landed).

Sources and licences (each file keeps its owner's copyright):
- LibreOffice core `sw/qa` (MPL-2.0), commit 6b2c10e7ca30: 74 files not in `lo/` and not byte duplicates.
- Open XML SDK (MIT) 13, docx4j (Apache-2.0; the repo has no LICENSE file, its README and pom say Apache v2) 18,
  Apache POI (Apache-2.0) 5, python-docx (MIT) 1, thesis templates (MIT: ucsd_thesis_template, jmu-thesis-template) 2.
- gov.uk (Open Government Licence v3.0): 57 long English reports, consultations and guidance (8-40 pages), each with its
  gov.uk page and asset URL in the manifest. Found through the gov.uk search and content APIs. OGL excludes third-party
  material and logos; not checked per document. Department mailboxes remain in the text; documents naming individuals were removed.
  (85 docxcorp.us documents were dropped on starling-bd's ruling: ODC-BY covers the collection, not the documents.)
- Left out: pandoc test files (GPL-2), mammoth.js (same files as python-mammoth).

Rejected automatically: byte duplicates of the current corpus, our render over 40 pages or failed, DATE/TIME
fields, an e-mail address or phone number in the text, under 300 bytes of text, names that suggest corrupt or
fuzz files. Not checked: that Word for Windows opens each without a repair prompt (needs a Word print).
