# The .docx corpus, and Word's printing of it

What Writer is measured against: 476 real Word documents, and for 457 of
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

## The results, in short (2026-10-18)

Two numbers are kept for every document. They measure different things,
and **they move in opposite directions**:

| | **Line match** — is the layout Word's? | **Page difference** — do the pixels look like Word's? |
|---|---|---|
| What it counts | Word's lines that ours sets on the same page, at the same height (±3pt), starting with the same text | the share of a page's pixels that differ from Word's print |
| Good is | **high** (100% = every line where Word has it) | **low** (0% = the page is pixel-identical) |
| Chinese, 306 docs | **95.2%** mean, 98.4% median; 255 docs at ≥ 95%; 298 with Word's page count | 10.2% mean, 9.6% median; no page exact |
| POI, 111 docs | **89.8%** mean, 100% median; 97 docs at ≥ 95%; all 111 with Word's page count | **1.7%** mean, 0.4% median; 4 docs exact |
| Tool | `test/docx-line-match.py` (sweep s353) | `test/docx-app-render.sh` (sweep 8, `baseline.tsv`) |

How to read them together:

- **The line match is the measure of fidelity.** It says whether we break
  lines and pages where Word does. A document at 100% has every line in
  Word's place; one that slips a line on page 2 loses every line after.
- **The page difference cannot reach 0 for Chinese documents, by
  design.** Word embeds the faces they name (方正, 仿宋_GB2312…); this app
  draws stand-ins with the same widths. Every glyph then differs by some
  pixels even when every line is in its place. So the Chinese 10% is
  mostly faces, not layout. The POI documents use faces we match, and
  there the page difference is a fair check of drawing (1.7%).
- **The POI line match is pulled down by a few files, not by most:** its
  median is 100%. The low ones are a crash file with no text, right-to-left
  Arabic, charts and a hand-made content-control file (see the board).
- **Compare a document with itself, not means across dates.** Thirteen
  samples have been added to the Chinese set since 2026-10-12, so its mean
  covers different documents at each sweep. Like for like, the first 68
  Chinese documents: line match 66% at sweep 7 (2026-10-13, 49 with Word's
  page count) and 98.6% now (median 99.0%, 65 at ≥ 95%, all 68 with
  Word's page count); page difference 14.3% then, 9.4% now.
- What is left, document by document, and why: `docs/plans/word-gaps-tasks.md`.

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

On 2026-10-18 (sweep s353, `office` at 66bd69c9) the 306 Chinese
documents have a mean of 95.2% of Word's lines where Word has them
(median 98.4%; 255 at 95% or more, 301 at half or more, 298 with Word's
page count), and the 111 POI documents 89.8% (median 100%; 97 at 95% or
more, all 111 with Word's page count). At sweep 7 it had been 67% for
POI and 66% for the 68 Chinese documents then in the set (49 of them
with Word's page count); at sweep 1, 42% and 5%; at sweep 6, 62% and
45%. A document's score falls at the first paragraph that
breaks differently, and that paragraph is what the second form prints.
(The pixel mean moves less, and not always the same way: a document
that gains or loses a page against Word's count has a page that is
wholly different.)

Means are not comparable across samples, since each of the thirteen
samples added documents; compare a document with itself. What is left,
document by document, is on the board, `docs/plans/word-gaps-tasks.md`.
A good share of the remaining misses is the reader's, not the layout's:
Word's embedded subsets drop glyphs from its text layer, and PDFKit groups
some lines differently.

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
except the `zh-*` prints, all 346 of which are Word for Mac 16.113.3,
on 2026-10-16 and the third to seventh samples' 98 on 2026-10-17 and the eighth to fifteenth samples' 160 on 2026-10-18 (the first sample's 68 reprinted that day: by then Word set
楷体_GB2312 in Microsoft YaHei, where the 2026-10-12 prints had KaiTi,
so the two halves had disagreed; the old prints are in git history;
`zh-167ee06c…` reprinted alone on 2026-10-18 as well — its batch print
had set hangingChars lines 21.55pt in where Word sets 28, the other
nineteen of its sample reprinting unchanged, so a reference that
disagrees with a lab is worth reprinting before it is believed),
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
| `zh-*` (346) | docxcorp.us, topic government, language zh | ODC-BY 1.0 for the collection |

The POI files are what `test/docx-corpus.py` fetches: real documents from
that project's bug reports, plus fuzzer cases that are deliberately
broken.

The `zh-*` files are fifteen seeded samples of 679 Chinese
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
(`random.seed(20261029)`, the fourteen at 95.2%), all — policies mostly, with forms, reports, standards
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
