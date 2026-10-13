# The .docx corpus, and Word's printing of it

What Writer is measured against: 198 real Word documents, and for 179 of
them the PDF that Microsoft Word itself prints. The counterpart of
`test/corpus/pptx` and `test/corpus/xlsx`, and meant to work the same way.

    docs/           the documents, as downloaded
    SHA256SUMS      of docs/, to tell a changed document from a changed painter
    word/           NAME-orig.pdf — Word's print of docs/NAME.docx
    baseline.tsv    each document's score at the last recorded painter sweep (7, 2026-10-13, a Mac)
    matched.txt, others.txt   the two groups of that baseline
    roundtrip.tsv   the round-trip gate's score for each document (2026-10-12)
    zh-manifest.tsv where each `zh-*` document was downloaded from

They are in the repository because the second half cannot be downloaded:
Word's PDFs took a Mac with Word and a run over every document, and a
score only means something against the same references.

## Two measures, and they are not the same

**The painter** — how this app draws a document, against how Word prints
it. `baseline.tsv`, swept by `test/docx-app-render.sh`:

    test/docx-app-render.sh                  # every document, into ~/starling-doc-check/app
    test/docx-app-render.sh WORK             # … into WORK
    python3 test/pptx-corpus-groups.py docx  # matched / others from the baseline
    CORPUS_GROUP=matched test/docx-app-render.sh WORK   # exits 1 if one no longer matches

It needs a release build (`OFFICE_APP` names another binary) and takes
about two minutes; `OfficeApp --convert NAME.docx NAME.pdf` is this
app's side. `WORK/render.tsv` gets a row per document and `WORK/pairs/`
a side-by-side PNG of every page that differs. Sweep 7, 2026-10-13, by
`test/pdf-diff.swift` (CoreGraphics; a sweep by MuPDF off a Mac would be
`baseline-mupdf.tsv` and its own numbers, as in the .pptx corpus):

| | documents | pages | mean | median | ≤ 2% | 2–20% | > 20% | exact |
|---|---|---|---|---|---|---|---|---|
| all | 179 | 1,695 | 7.6% | 4.2% | 80 | 82 | 17 | 3 |
| POI | 111 | 427 | 3.4% | 0.7% | 80 | 26 | 5 | 3 |
| `zh-*` | 68 | 1,268 | 14.3% | 13.6% | 0 | 56 | 12 | 0 |

(Sweep 1, 2026-10-12 and before any of the work it started: 12.6%
over all, POI 4.7%, `zh-*` 25.6%; sweep 6, the same day, 9.0%, 3.8%
and 17.4%. Sweep 7 is the first with the documents' pictures drawn —
until then a converted PDF had a grey box for each — so a page of
pictures set a few points off scores worse than it did.)

A page diff says little about a document that is one line late from its
second page on, so there is a second reading of the same sweep:

    test/docx-line-match.py WORK             # the share of Word's lines set in the same place
    test/docx-line-match.py WORK zh-3550     # where one document first parts from Word

At sweep 7 a POI document has two thirds of Word's lines where Word
has them (mean 67%, median 96%, 55 of 110 at 95% or more) and a
Chinese one as many (mean 66%, median 80%; 22 at 95%, 46 at half or
more, 49 of the 68 with Word's page count); at sweep 1 it was 42% and 5%, at
sweep 6 62% and 45%. A document's score falls at the first paragraph that
breaks differently, and that paragraph is what the second form prints.
(The pixel mean moves less, and not always the same way: a document
that gains or loses a page against Word's count has a page that is
wholly different.)

**The Chinese documents are compared with Word on a Mac, which has few
Chinese fonts.** That Word has 宋体, 黑体, 楷体, 仿宋 and the 明體 pair,
and sets every other name — 仿宋_GB2312, the 方正 faces, 標楷體, which
is most of what government documents are written in — in Microsoft
YaHei, a taller and wider face than any of them. The sweep sets
`OFFICE_WORD_FONTS=mac`, which makes this app measure those names as
that Word does (`OfficeFonts.swift`); without it they are measured as
the square faces their authors had, which is what a reader of the
document should see and is not what these PDFs show.

**The round trip** — Word printing the original and Word printing the
copy this app saves, where the expected score is 0.00 and every
difference is ours to explain. `roundtrip.tsv`, by
`test/docx-word-render.sh` (a Mac with Word; see below). At 2026-10-12,
of the 179: 176 within 1%, 120 with a mean of 0.00, none over 5%
(`delins` 4.45%, which Word prints differently from one run to the next
by itself; `zh-90e0cea8…` 2.58%; `zh-06c46ba9…` 1.17%).
`docs/plans/office.md` has the rounds that got it there.

`roundtrip.tsv` is a record, not something to compare a new run with row
by row: both sides of a round-trip score must come from ONE session of
Word, because Word prints some originals differently from one session to
the next (`heading123`, `delins`, `bug59058`, `drawing` — and which ones
changes). So the gate reprints the originals every time and the PDFs in
`word/` are not its reference. They are the painter's.

## Word's side

`word/` was made on 2026-10-11 and -12 by Microsoft Word for Mac 16.113,
through

    test/docx-word-render.sh IN_DIR OUT_DIR WORK [names…]

which drives Word's print dialog (`test/docx-word-pdf.applescript`: open,
Print, Save as PDF) for the original and the saved copy, writing
`WORK/pdf/NAME-orig.pdf` and `NAME-ours.pdf`. The originals of the last
full pass are what is here. Word needs the folders to be under `$HOME`
(its sandbox), so the documents are copied out of the repository first.

Word prints on the paper of the active printer setup when a document's
own size is within a fraction of a point of it (A4 as 595×842 rather
than 595.28×841.89), and the harness says `paper=differs` when the two
sides came out on different paper. A whole pass that moves by 1–10% with
equal page counts is that, not a regression.

Nineteen documents have no PDF: the two password-protected ones, the
fuzzer and crash files, and four more that Word or this app will not
open (`deep-table-cell`, `ExternalEntityInText`, `truncated62886`,
`unicode-path`). They are kept because `test/docx-corpus.py` reads them
too — eight are expected not to open.

References made with another Word, or on another machine's fonts, are
another set: regenerate all of them or none, record the version here,
and sweep for a new baseline.

## Where the documents come from, and their licences

None of these files is ours. They are copied here unchanged, and each
stays under the licence and copyright it came with:

| names | from | licence |
|---|---|---|
| no prefix (130) | Apache POI, `test-data/document` | Apache License 2.0 |
| `zh-*` (68) | docxcorp.us, topic government, language zh | ODC-BY 1.0 for the collection |

The POI files are what `test/docx-corpus.py` fetches: real documents from
that project's bug reports, plus fuzzer cases that are deliberately
broken.

The `zh-*` files are a seeded sample (one in ten) of 679 Chinese
government documents — policies mostly, with forms, reports, standards
and teaching material — listed by
`https://api.docxcorp.us/documents?topic=government&lang=zh` and fetched
from `https://docxcorp.us/documents/<sha256>.docx`. The name after the
prefix is that hash; `zh-manifest.tsv` has each one's type, the name it
was published under and its address. The collection is offered under
ODC-BY; the documents themselves were published by the bodies that
wrote them, who hold whatever rights there are, and they are here only
as inputs to a test.

If you hold the rights to one of these and want it gone, removing the
document, its PDF and its rows is all it takes; no gate depends on any
one of them.
