# The .docx corpus, and Word's printing of it

What Writer is measured against: 775 real Word documents, and for 756 of
them the PDF that Microsoft Word itself prints. The counterpart of
`test/corpus/pptx` and `test/corpus/xlsx`, and meant to work the same way.

    docs/           the documents, as downloaded
    SHA256SUMS      of docs/, to tell a changed document from a changed painter
    word/           NAME-orig.pdf — Word's print of docs/NAME.docx
    baseline.tsv    each document's score at the last recorded painter sweep (8, 2026-10-18, a Mac)
    matched.txt, others.txt   the two groups of that baseline
    roundtrip.tsv   the round-trip gate's score for each document (2026-10-12)
    zh-manifest.tsv where each `zh-*` document was downloaded from

They are in the repository because the second half cannot be downloaded:
Word's PDFs took a Mac with Word and a run over every document, and a
score only means something against the same references.

## The results (2026-10-18)

**The measure is the line match**: for every line of text in Word's
print, does ours set that line on the same page, at the same height
(within 3pt), starting with the same text? It asks whether we break
lines and pages where Word does — layout fidelity. 100% means every line
of the document is where Word has it; a document that slips one line on
page 2 loses every line after, so a small layout fault shows as a large
drop. Higher is better.

Sweep s355, `office` at d0dc0039, on the Mac (`OFFICE_WORD_FONTS=mac`,
lines read by PDFKit):

| | documents | mean | median | at 95% or more | at half or more | Word's page count |
|---|---|---|---|---|---|---|
| Chinese (`zh-*`) | 346 | **94.5%** | 98.4% | 287 | 337 | 340 |
| POI | 111 | **89.8%** | 100% | 97 | 100 | 111 |

    test/docx-line-match.py WORK             # every document: the share of Word's lines set in Word's place
    test/docx-line-match.py WORK zh-3550     # one document: where it first parts from Word, and why

Reading it:

- **Compare a document with itself, not a mean across dates.** Fifteen
  samples have been added to the Chinese set since 2026-10-12, so each
  sweep's mean covers different documents. Like for like, the first 68
  Chinese documents went from 66% (sweep 7, 2026-10-13; 49 with Word's
  page count) to **98.6%** now (median 99.0%, 65 at 95% or more, all 68
  with Word's page count).
- **The POI mean is pulled down by a few files, not by most** — its median
  is 100%. Nine have no text to match at all (a crash file, empty and
  picture-only documents); the others are right-to-left Arabic, charts and
  a hand-made content-control file.
- **Some misses are the reader's, not the layout's.** Word's embedded font
  subsets drop glyphs from its PDF's text layer, and PDFKit groups some
  lines differently; such a line counts as missed though it is in place.
  What is left, document by document, and why: `docs/plans/word-gaps-tasks.md`.
- **Word itself is not one reference.** These are Word for Mac 16.113.3's
  prints. Word for Windows sets some of the same files in other faces, and
  Word for Mac itself picks another face for some documents from one session
  to the next (`docs/plans/office.md`, "Word is not one reference"). A
  score is fidelity to these prints, not to every Word.

**The page difference is a secondary check.** It is the share of a page's
pixels that differ from Word's print (lower is better), from
`test/docx-app-render.sh` — useful for catching drawing regressions in
documents whose faces we match, and not a measure of layout: it cannot
reach 0 for Chinese documents, because Word draws faces this app does not
have (方正, 仿宋_GB2312…) and ours are stand-ins of the same widths, so
every glyph differs by some pixels with every line in its place. At sweep
8 (2026-10-18, 417 documents): POI 1.7% (3.4% at sweep 7), Chinese 10.2%,
the first 68 Chinese 9.4% (14.3%). Details below.

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
a side-by-side PNG of every page that differs. Sweep 8, 2026-10-18,
`office` at 6d55b1b1, by `test/pdf-diff.swift` (CoreGraphics; a sweep by
MuPDF off a Mac would be `baseline-mupdf.tsv` and its own numbers, as in
the .pptx corpus):

| | documents | pages | mean | median | ≤ 2% | 2–20% | > 20% | exact |
|---|---|---|---|---|---|---|---|---|
| all | 417 | 6,309 | 7.9% | 8.0% | 89 | 323 | 5 | 4 |
| POI | 111 | 419 | 1.7% | 0.4% | 89 | 21 | 1 | 4 |
| `zh-*` | 306 | 5,890 | 10.2% | 9.6% | 0 | 302 | 4 | 0 |
| `zh-*`, the first 68 | 68 | 1,239 | 9.4% | 8.7% | 0 | 68 | 0 | 0 |

The `zh-*` set has grown from 68 to 306 since sweep 7, so compare its
first 68, which sweep 7 measured too. (Sweep 7, 2026-10-13: all 179 at
7.6% mean and 4.2% median, POI 3.4%, the 68 `zh-*` 14.3% with 12 over
20%. Sweep 1, 2026-10-12 and before any of the work it started: 12.6%
over all, POI 4.7%, `zh-*` 25.6%; sweep 6, the same day, 9.0%, 3.8% and
17.4%. Sweep 7 is the first with the documents' pictures drawn — until
then a converted PDF had a grey box for each — so a page of pictures
set a few points off scores worse than it did.) No Chinese page is
pixel-exact: Word's faces there are embedded subsets, ours are
stand-ins of the same widths, and a glyph drawn by another face never
matches to the pixel; the line match below is the measure for them.

A page diff says little about a document that is one line late from its
second page on, so there is a second reading of the same sweep:

    test/docx-line-match.py WORK             # the share of Word's lines set in the same place
    test/docx-line-match.py WORK zh-3550     # where one document first parts from Word

Today's figures are at the top ("The results"). At sweep 7 it had been 67% for
POI and 66% for the 68 Chinese documents then in the set (49 of them
with Word's page count); at sweep 1, 42% and 5%; at sweep 6, 62% and
45%. A document's score falls at the first paragraph that
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
except the `zh-*` prints, all 645 of which are Word for Mac 16.113.3,
on 2026-10-16 and the third to seventh samples' 98 on 2026-10-17 and the eighth to twentieth samples' 260 on 2026-10-18 and the twenty-first's 20 on 2026-10-19 and the twenty-second to twenty-seventh's 120 on 2026-10-22 and the twenty-eighth's 20, twenty-ninth's 19 and thirtieth's 20 on 2026-10-23 (the first sample's 68 reprinted that day: by then Word set
楷体_GB2312 in Microsoft YaHei, where the 2026-10-12 prints had KaiTi,
so the two halves had disagreed; the old prints are in git history;
`zh-167ee06c…` reprinted alone on 2026-10-18 as well — its batch print
had set hangingChars lines 21.55pt in where Word sets 28, the other
nineteen of its sample reprinting unchanged, so a reference that
disagrees with a lab is worth reprinting before it is believed; and
`zh-5450d509…` the same night, after a fresh launch of Word — its batch
print had set its embedded 仿宋_GB2312 body in SimSun, the fresh one in
YaHei, 10 pages either way: which face Word for Mac takes for a name is
not always the file's to say, see the board),
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
| `zh-*` (645) | docxcorp.us, topic government, language zh | ODC-BY 1.0 for the collection |

A second, separate set sits in `lo/`: 608 of LibreOffice core's own Writer test
documents (`sw/qa`), MPL-2.0, attributed in `lo/LICENSE.md`. It has its own
manifest and checksums and is scored on its own, never in the means above.

The POI files are what `test/docx-corpus.py` fetches: real documents from
that project's bug reports, plus fuzzer cases that are deliberately
broken.

The `zh-*` files are thirty seeded samples of 679 Chinese
government documents: 68 (one in ten, `random.seed(20261011)`, the
first, which the tables above measure) and 20 more added 2026-10-16
(`random.seed(20261016)` among the rest of 15 to 400 KB, a fresh set
of gaps once the first stood at 98%) and 20 more on 2026-10-17
(`random.seed(20261017)`, the same way, once the two stood at 97.5%) and
20 more the same day (`random.seed(20261018)`, once the three stood at
97.6%) and 20 more (`random.seed(20261019)`, the four at 96.8%) and 20 more
(`random.seed(20261020)`, the five at 95.1%) and 18 more
(`random.seed(20261021)`; two of its twenty Word would not print) and 20 more
(`random.seed(20261022)`, the seven at 95.2%) and 20 more
(`random.seed(20261023)`, the eight at 96.2%) and 20 more
(`random.seed(20261024)`, the nine at 96.2%) and 20 more
(`random.seed(20261025)`, the ten at 95.9%) and 20 more
(`random.seed(20261026)`, the eleven at 95.7%) and 20 more
(`random.seed(20261027)`, the twelve at 96.0%) and 20 more
(`random.seed(20261028)`, the thirteen at 95.5%) and 20 more
(`random.seed(20261029)`, the fourteen at 95.2%) and 20 more
(`random.seed(20261030)`, the fifteen at 95.1%) and 20 more
(`random.seed(20261031)`, the sixteen at 95.0%) and 20 more
(`random.seed(20261101)`, the seventeen at 95.1%) and 20 more
(`random.seed(20261102)`, the eighteen at 94.8%) and 20 more
(`random.seed(20261103)`, the nineteen at 95.4%) and 20 more
(`random.seed(20261104)`, the twenty at 95.0%) and 20 more
(`random.seed(20261105)`, the twenty-one at 94.5%) and 20 more
(`random.seed(20261106)`, the twenty-two at 94.8%) and 20 more
(`random.seed(20261107)`, the twenty-three at 95.1%) and 20 more
(`random.seed(20261108)`, the twenty-four at 94.9%) and 20 more
(`random.seed(20261109)`, the twenty-five at 95.3%) and 20 more
(`random.seed(20261110)`, the twenty-six at 95.2%) and 20 more
(`random.seed(20261111)`, the twenty-seven at 95.9%) and the last 19
(`random.seed(20261112)`, the twenty-eight at 95.9%: every one of 15 to 400 KB is in now) and 20 more of 400 to 800 KB
(`random.seed(20261113)`, of the 22 there, the twenty-nine at 96.1%), all — policies mostly, with forms, reports, standards
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
