# Word corpus curation: fewer look-alikes, more kinds of document

Planner: amd-opus, 2026-11-07, for starling-bd. Spec only: nothing here has
been removed, added, built or landed. Every number below was measured on
office f359f6ecd with the existing feature reader (`test/tools/docx-features.py`)
and some throwaway census scripts, so the census session can check them.

## 0. Why (what the two sets are today)

- 1,349 scored documents: the 756 set (645 `zh-*` Chinese government files
  from docxcorp.us, 508 of them "policies", plus 130 Apache POI test files)
  and the LO set (593 LibreOffice test files).
- **89% of all pages are the 645 Chinese documents** (11,325 of 12,768). The
  other 698 documents are almost all short test files: 665 have 1-4 pages,
  and only 33 have 5 pages or more.
- **Both gates are at their ceiling**: combined 99.95 (756) and 99.98 (LO).
  They still guard against breakage, but they no longer find new work.
- Ordinary documents are missing. There are almost no long English or
  European business or academic documents (with a table of contents,
  numbered headings, captions, footnotes and cross-references), and some
  scripts and features barely appear at all. Witness counts, as
  756/LO documents: Hangul 1/3, Hebrew 0/4, Arabic 2/4, Thai 1/0,
  Devanagari 0/0, kashida 0/2, `thaiDistribute` 0/0, emphasis marks 0/0,
  `snapToChars` grid 0/0, ruby 1/0, drop caps 0/5, decimal tabs 0/5,
  line numbers 1/7, OMML equations 7/4, SmartArt 3/1, columns with a
  separator 2/4, endnotes 2/10, comments 3/10, IF fields 0/3.

So the larger win is in adding new kinds of document. Removing look-alikes
mainly makes room for them within the same sweep time.

## 1. The feature fingerprint

A fingerprint is a set of tokens per document. Two documents with the same
token set should take the same code paths. It has three layers:

**A. Structure** (from the XML; `docx-features.py` already reads ~100 of these).
Count features become presence tokens, with levels where the level changes
the code path: `columns>=2`, `columns>=3`; `table_depth>=2`; `sections>=2`.
Categorical values become one token each: compat `mode=11/12/14/15`, each
compat flag set, `grid=lines/linesAndChars/snapToChars`, `char_spacing=`,
header and footer types, `lang_default_ea=`. The extractor needs these
features added (counts from the census above): field kinds (TOC, PAGE,
NUMPAGES, REF/PAGEREF/NOTEREF, SEQ, IF, MERGEFIELD, DATE family, EQ, form
fields, content controls); kashida and `thaiDistribute`; `bidi`/`bidiVisual`;
`lnNumType`; `pgBorders`; `fitText`; `eastAsianLayout`; emphasis marks;
fixed table layout (348/94); `cantSplit`; header rows; `vMerge`;
`gridSpan`; wrapTight/Through; behindDoc; continuous sections; column
separators; `ptab`; OLE objects; altChunk; auto hyphenation; widow control
off; mirror margins and gutter; tab kinds (right, centre, decimal, bar)
and leaders; caps and small caps; kern; raised and lowered text.

**B. Text** (from the runs). The set of punctuation, symbol and space code points
used (this decides line-end squeeze, kinsoku, hanging and spacing), scripts
present, full-width forms, each font size used, and the faces used *after*
the Word for Windows font map (`word-win-font-map.tsv`). Two authored names
that print as the same face count as one token.

**C. Rules reached.** The set of `RuleTrace.hit` names (203 in the code today) a
document reaches, from one traced sweep (`docx-sweep.sh WORK -t`, which takes
as long as a normal sweep). This is the true code-path layer, but it only
sees rules someone instrumented. That is why it is added to A and B, not
used instead of them.

**How fine is fine enough: a check against history.** The committed score files
(136 versions of 756.v2, 107 of lo.v2) record 224 occasions when some
documents' scores moved. For a candidate drop list, replay that history
and ask: would the documents we keep have shown every one of those moves?
Measured today:

| fingerprint | would leave the gate | moves the kept set would not have seen |
|---|---|---|
| A only (presence tokens) | 469 | 8 of 224 |
| A + B | 244 | 5 of 224 |

Of the 5 under A+B, 4 are fixes aimed at the moved document itself, which was
below 100 at the time and is protected by the rule below. The fifth is a
real side effect: zh-9ef811c8 went from 99.6 to 100 because of an LO
small-caps fix, and nothing else moved. **Acceptance rule: the census
ships a drop list only when every unseen move is a fix aimed at that
document.** Layer C is expected to cover the side-effect cases. Any
document that moved in history while its keeper did not stays in the gate.

## 2. The redundancy rule

1. Sort the documents by token count (most first), then pages (most
   first), then the number of committed score files they appear in
   (longest history first), then key.
2. Go down the list. Keep a document unless a document already kept has
   every one of its tokens (the same fingerprint or a superset). If so,
   drop it and record that kept document as its **keeper**.
3. **Witness floor.** Every token keeps at least 2 witnesses in the gate. If
   a drop would leave a token with 1, keep the document.
4. **Never dropped:**
   - documents below 100 combined on the current tip (74 `zh`, 1 LO, plus any POI document below 100);
   - documents named in any board entry that is not DONE or LANDED (CLAIMED,
     OPEN, PARKED, RELEASED as a lead, UNFIXABLE, accepted cancelling-error
     drops, text-layer or scorer artefacts such as lo-a43021ca and
     lo-72e72396). The census reads the entry headers. A bare grep is too
     wide: 154 of the 244 A+B candidates are named somewhere on the board,
     mostly in DONE entries;
   - documents that moved in history without their keeper;
   - documents used by `roundtrip.tsv`, `clock.tsv` or the unit tests
     (grep `apps/OfficeApp/Tests`).
   The canary set is rebuilt after the swap, so it needs no protection.
5. **Expected size.** With A+B and all of the protections, about 90-240
   documents leave the gate (7-18%). My prototype gives 90 after a
   board-name protection that is too wide; the true number lies between.
   This is less than "the zh set is all alike" suggests, because at the
   text level 619 of the 645 Chinese documents differ: different
   punctuation, faces and sizes.
6. **Dropped documents are not deleted on day one.** They move to a
   *reserve* list that amd-8 sweeps nightly and that never blocks a
   landing. After 30 days, if the reserve showed no move the gate missed,
   delete their files and prints from the tree (git history and a tag keep
   them). If it did show one, put that document back in the gate and tighten
   the fingerprint.

**Dedupe report for the user** (`docs/plans/word-corpus-dedupe.md`, plus a TSV):
one paragraph with the counts per source, the pages and sweep minutes saved,
and the history-check result. Then a table of every dropped document, its
keeper and the tokens the keeper adds, and the protected list with the reason
for each.

## 3. Gap sourcing

**Budget.** About 450 new documents and at most 4,000 pages, each document
at most 40 pages. Windows printing takes ~9 s a document, so ~70 minutes
plus re-prints. Repository growth stays under 200 MB (prints are ~4.5x the
size of the documents). **Gate sweep time must not grow:** the dropped
pages (mostly long Chinese documents) pay for the new ones. Today that is
~450 s for the 756 and ~77 s for LO at 4 jobs on the Mac.

**Selection.** Each source gives a candidate pool. Remove byte duplicates
(SHA-256), fingerprint the rest, then pick greedily by "new tokens added"
until each target below is met. Reject:
- documents with personal data;
- documents Word for Windows opens with a repair prompt;
- documents whose visible text prints the date or time (the DATE family
  cannot be fixed);
- documents over 40 pages;
- documents with no licence that lets this public repository carry them.

Every document gets a manifest row with its URL, licence, SHA-256,
language, source and the tokens it adds.

| feature (witnesses wanted) | today 756/LO | target | where |
|---|---|---|---|
| Long English documents: TOC, numbered headings, captions, footnotes, cross-refs, header rows | ~0 real | 80 | gov.uk (OGL v3), US federal agencies (public domain), university thesis templates and theses, journal author templates |
| European Latin (de fr es it pl nl cs hu pt): hyphenation, diacritics, decimal tabs | test files only | 50 | EU Publications Office (CC BY 4.0, all 24 languages); docxcorp.us other languages |
| Cyrillic, Greek | 25 / 16 | 15 | EU publications (bg, el); docxcorp.us |
| Japanese: kana, ruby, vertical text, `linesAndChars`/`snapToChars` grid, emphasis marks | 45 kana, ruby 1 | 50 | e-Gov forms (様式, Government Standard Terms of Use), docxcorp.us lang=ja |
| Korean: Hangul, word-based wrapping, Malgun Gothic/Batang | 4 | 40 | KOGL type 1 (공공누리 제1유형) files on data.go.kr; university thesis templates (Korean government work is mostly HWP, so docx is scarcer) |
| Arabic and Persian: bidi, kashida low/med/high, Arabic-Indic digits | 6 | 40 | Gulf and Egyptian government forms where licensed; docxcorp.us lang=ar/fa |
| Hebrew | 4 | 20 | gov.il forms |
| Thai, Devanagari, other complex scripts; `thaiDistribute` | 1 / 0 | 20 | Indian government (GODL), Thai government; docxcorp.us |
| Multi-column with separators, line numbers, page borders, mirror margins/gutter | 6 / 8 / 21 / 16 | 10 each | theses, journal templates, legal filings (line numbers) |
| OMML equations, SmartArt, charts outside Chinese documents | 11 / 4 / 58 | 20 / 15 / 20 | theses, Open XML SDK test files (MIT), docx4j samples (Apache-2.0) |
| Comments, tracked changes, endnotes | 13 / 30 / 12 | 20 / 20 / 10 | LibreOffice sw/qa (409 already queued in `lo/queue-2.tsv`, filter by token gain), POI test files not yet taken |
| Form fields, content controls, mail merge, IF/SEQ fields | 13 / 62 / 4 / 3 | 20 | government forms; docx4j, python-docx (MIT), pandoc and mammoth (BSD-2) test files |
| Drop caps, text direction tbRl/btLr, altChunk, OLE | 5 / 37 / 2 / 12 | 10 each | LO and POI test files, templates |
| Legacy compat mode 11 | 28 | 10 | old government and academic files |

docxcorp.us is the cheapest first source: the Chinese set already came from
its API (`api.docxcorp.us/documents?topic=...&lang=...`, ODC-BY), so the
same fetch path serves other languages and topics. For bulk discovery
beyond it, query the Common Crawl URL index for `.docx` by country domain
(.go.jp, .go.kr, .gov.il, .gov.sa, .gouv.fr, .bund.de, .gov.uk). Microsoft's
own Office templates go in only if their licence allows redistribution. If
it does not, leave them out.

New scripts will need Windows stand-in faces (Malgun Gothic, Batang, Meiryo,
Yu Mincho, the Hebrew and Devanagari faces) in the bundled set and in
`word-win-missing-faces-map.txt`. Expect the new documents to score low at
first. That low score is the new work this plan is meant to create.

## 4. Migration

**New set names.** The digit is the corpus version, so that a score is never
compared across two different lists of documents:
- `w1`: the 756 folder, gate list only (`test/corpus/docx/sets/w1.txt`);
- `lo1`: the LO folder, gate list plus the LO queue documents that were taken;
- `x1`: a new folder `test/corpus/docx/x/` with `docs/`, `word-win/`,
  `manifest.tsv`, `SHA256SUMS` and `LICENSE.md`, laid out like `lo/`;
- `w1r` and `lo1r`: the reserve lists, swept nightly, never gating.
Any later change to a list bumps the digit (`w2`, ...) through the same one-commit swap.

**The swap (one commit, under the landing lock, at a quiet moment):**
1. Freeze: copy `scores/*/{756,lo}.*` to `scores/frozen-2026-11/` and tag
   the commit `word-corpus-v0`. The old history stays readable. Nothing
   compares against it any more.
2. Tools: `docx-pair.sh` changes its default to `SETS="w1 lo1 x1"`.
   `corpus()` maps each set to its folder plus a key list, and `sweep`
   filters by that list. `docx-sweep.sh`, `docx-select.py` (several
   folders), `--make-canaries` and the combined and visual scorers learn
   the set names. `land.sh` needs no logic change: it reads the stored
   score files by set name, and `LAND_ACCEPT_DROP` works as before.
3. Reseed: sweep the tip on all three sets and commit
   `scores/linux/{w1,lo1,x1}.{v1,v2,vis,combined}` and `STAMP` in the same
   commit. Headline numbers become the combined mean per set, plus the
   pooled mean.
4. Board: a new header line with the reseed numbers. Every session pulls
   office before its next land. Any wip branch paired before the swap is
   paired again once.

**Who does what** (suggested; starling-bd assigns):
1. **Census and dedupe report:** amd-opus, who already has the prototype.
   Extend `docx-features.py` (layers A and B), add
   `test/tools/docx-census.py` (fingerprints, board reader, history check,
   drop list, report), and write the report. About 1 day.
2. **Traced sweep (layer C):** amd-8, one sweep with `-t` on both sets,
   during a round.
3. **Sourcing:** two sessions. One takes CJK and RTL (ja, ko, ar, fa, he,
   th, hi). The other takes Latin/European, the test suites and templates.
   They fetch into a scratch folder outside the tree, fingerprint, apply
   the rejects and pick by token gain against the kept set. Each delivers
   a candidate manifest. About 1-2 days.
4. **Windows prints:** `windows`. Print each candidate, check that Word
   opened it cleanly and that every face is present or mapped, and drop the
   failures. About 2 hours of the box including re-prints.
5. **Stand-in faces for new scripts:** whoever owns the bundled fonts
   (amd-7 did the last fallback work), before the reseed.
6. **The swap and reseed:** amd-8, which owns the rounds and the score files.
7. **Reserve watch and the day-30 deletion:** amd-8, reported to starling-bd.

Nothing is removed before the user has seen the dedupe report and approved it.
