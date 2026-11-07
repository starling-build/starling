# new-a: staging batch A for the Word corpus curation (docs/plans/word-corpus-curation.md, section 3)

NOT in any gate. 198 candidate documents, 2,831 pages (page counts are from our
own render, Windows mode; Word's may differ). `manifest.tsv` has each file's
source URL, licence, SHA-256, language and the feature tokens it adds
(tokens from `docx-features.py` plus a few XML probes; the census tool has not landed).

Sources and licences (each file keeps its owner's copyright):
- LibreOffice core `sw/qa` (MPL-2.0), commit 6b2c10e7ca30: 74 files not in `lo/` and not byte duplicates.
- Open XML SDK (MIT) 13, docx4j (Apache-2.0; the repo has no LICENSE file, its README and pom say Apache v2) 18,
  Apache POI (Apache-2.0) 5, python-docx (MIT) 1, thesis templates (MIT: ucsd_thesis_template, jmu-thesis-template) 2.
- docxcorp.us, language en, reports/reference/technical/educational/legal/policies, 5,000-18,000 words (85 files, long
  English): offered under ODC-BY 1.0 as a collection; the documents belong to the bodies that wrote them (same
  basis as the `zh-*` set, see ../README.md). Not individually licensed: starling-bd to decide if that is enough.
- Left out: pandoc test files (GPL-2), mammoth.js (same files as python-mammoth).

Rejected automatically: byte duplicates of the current corpus, our render over 40 pages or failed, DATE/TIME
fields, an e-mail address or phone number in the text, under 300 bytes of text, names that suggest corrupt or
fuzz files. Not checked: that Word for Windows opens each without a repair prompt (needs a Word print).
