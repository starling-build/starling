# Word gaps — shared task board

Two sessions work on how Writer draws Word documents against Word's own
prints, on the `office` branch. This file is how they split the work:
**claim a task before starting it, by editing its `Owner` line and pushing
that edit alone first**, so the other session sees it on its next fetch.
Release a claim the same way if you drop it. The rules each fix found go
in `office.md` ("The painter against Word"); this file only says who does
what next and how to check it.

## How a fix is checked

The steering number is `test/docx-line-match.py WORK`: the share of
Word's lines our PDF sets on the same page at the same height (±3pt).
x positions are not compared, so a horizontal fix can be right and move
no score. The loop that has worked:

1. `python3 test/docx-line-match.py WORK KEY 8` (or
   `~/starling-word-check/lab/tools/missed.py WORK KEY` on the Mac) names
   the first line that parts from Word.
2. Read that paragraph's XML and its style; read glyph positions off both
   PDFs (PyMuPDF `get_text("rawdict")`, `get_image_info()` for pictures,
   `get_drawings()` for table rules).
3. When the rule is not obvious, build a lab document from the
   document's own package (`lab/tools/mklab2.py SRC OUT BODY`) and print
   it with Word (`osascript test/docx-word-pdf.applescript IN OUT`; Mac
   only). Labs are named in `office.md`.
4. Sweep the whole corpus, compare per document with the previous
   sweep, and keep only changes where nothing goes down (or say why).
   Convert with `OFFICE_WORD_FONTS=mac`. On macOS there is no `timeout`
   command: a sweep loop using it converts nothing.
5. `test/run.sh --office` (or the release Office tests plus the repository
   checks). As of 2026-10-22 all 454 Office tests pass on the Mac; the old
   LineHeightTests failure came from missing font resources under XCTest.
   Keep the bundled-font startup test passing; do not waive that failure.
6. One fix per commit; fetch and rebase on `office` before every push.

On the Windows box the line match reads the PDFs with PyMuPDF (c4a931e5),
and its numbers sit within a point or two of the Mac's once Chinese text
falls back to YaHei (9ecd33ea) — before that every line drawn there was
JhengHei UI and Yu Gothic UI, and the sample scored 59%. Build and run
as in its memory notes: `STARLING_ENGINE_OUT` to link, the engine's
out-dir on `PATH` and `STARLING_ICU` to run.

Standing, at 92c1b88a (2026-10-14): Chinese sample 79.6% of Word's lines
(median 92.9%, 57 of 68 with Word's page count); POI set 66.6%.


### Note from the Mac (2026-10-22): 96 楷体_GB2312 references reprinted — one Word setup for all
lenovo (Linux b2, 01JsizVV) found the "drifting" 楷体_GB2312 fallback is one switch on the printing Mac,
2026-10-18 ~20:57 (PDF CreationDate): prints before it set 楷体_GB2312 in Microsoft YaHei, prints after it in
Arial Unicode MS, and nothing in the files differs. No font, asset or Word update on the Mac explains it (Word
16.113.3 throughout). The user chose to reprint: the 96 checked-in zh references printed before the switch whose
packages use 楷体_GB2312 were printed again (Mac 0fcba326) and replace the old ones — 80 now embed
ArialUnicodeMS, 16 never set 楷体 text on the page; page counts unchanged but zh-608e661b (5 -> 4, Word's own).
Re-scored on n386: mean 95.1 -> 94.9; 19 down where ours still sets 楷体 as YaHei (zh-c5b5087b 94.4 -> 53.0 [Linux b2 01JsizVV, measured, released — wants a lab: the reprint differs from the old print from p5's "第十八条  县级储备粮轮换…" on (kinsoku 0, compressPunctuation, its text's East Asian language en-US from Normal): the old print squeezed its commas to take 28 characters a line, the new one squeezes none in that paragraph and sets 27, justified 16.4 apart, with "。" opening a line. Yet the same print still squeezes commas in many other en-US paragraphs of the file (p2-p5, 13.1 and 10.2). Treating en-US as giving nothing took the file 53.5 -> 26.8, 11 pages, so that is not it. Lab c5 (Mac, ~/starling-word-check/lab/c5): the footer's two floats together — its wrapNone 144pt page-number box and its wrapNone line — turn the squeeze off, on pages 3 and after only; either one deleted, or no header/footer, and the paragraph squeezes as the old print did; the header's object and the PAGE field do not matter. Not modelled: 38 references with compressPunctuation and two or more footer floats score 99-100 squeezing on every page (zh-01071d55, zh-f3802561, zh-e2dc2598…), so it is no general rule; released],
zh-dc9cfa34 97.6 -> 56.9, zh-e37f8d40 100 -> 67.6 [Mac], zh-0aac9d1a 99.4 -> 69.5 [Linux b2 01JsizVV: 69.5 -> 79.7 — its 楷体_GB2312 headings' curly quotes are Arial Unicode MS's own, 0.345 em with no blank beside them (5.52 at 16pt in Word's print), where ours set them full-width; the rest not looked at, released], zh-3cdafcc9/e076bb5a/160a5e81 97.6
-> 85.1 …), 4 up (zh-608e661b 7.3 -> 100, zh-92373179 65.9 -> 71.3, zh-007ca091 93.0 -> 96.4, zh-c2f6d17a 93.6
-> 96.7). Next: one rule, 楷体_GB2312 -> Arial Unicode MS under OFFICE_WORD_FONTS=mac (lenovo, 1.74 em lines) [DONE Linux b2 01JsizVV 2026-10-22: 楷体_GB2312 is Arial Unicode MS under OFFICE_WORD_FONTS=mac, a 1.742 em line (its hhea 1.069 + 0.271 at Word's 1.3), baseline 1.270, Arial's Latin, emboldened 1/50 em; the face named "Arial Unicode MS" takes the same (was 1.75). Linux 657: 94.91 -> 95.12, 15 up (zh-4feaa34c 41.3 -> 99.5, zh-dc9cfa34 55.8 -> 99.2, zh-4e5fe46f 85.3 -> 94.7, zh-360c1df1 89.8 -> 98.4, zh-e7bdb543 88.1 -> 95.2, zh-232090e0 93.3 -> 97.8 …), zh-b24b396a 91.9 -> 90.8. Not moved by it: zh-c5b5087b 53.5, zh-e37f8d40 60.1, zh-0aac9d1a 69.5 — they set little or no 楷体 text, so their drops after the reprint are something else].
Earlier "released: drifting fallback" entries (zh-4e5fe46f, zh-884c6e3e, zh-875759ff, zh-4feaa34c) are now on
one reference setup.

Seven of the 96 restored to their old prints (Mac 0fcba326): zh-32f4ad9f, zh-540dc149, zh-70094a34,
zh-7b5b3de2, zh-92373179, zh-c2f6d17a, zh-e37f8d40. Their packages embed fonts, and today's Word prints those
without a Unicode map — 50-85% of their text reads as NUL (zh-e37f8d40: 5278 of 6182 characters, 0 in the old
print), so the scorer matched nothing; the line geometry was the old print's. Their old references stand.

### T144. zh-6a4fc013 gained a page (26 -> 27) at 58b0cbd8 (T135/T136) — DONE, confirmed on the Mac (2026-10-22)
Owner: Linux office1 01Ak4ibJ (lenovo-3). (Two T144s on this board: the other is zh-344a8d08's footnote.)
Bisected on the Mac (OFFICE_WORD_FONTS=mac, the one document):
97f8a42b 54.2% 26/26 pages, 58b0cbd8 51.5% 27 pages (Word 26). The Thai
document (TH Sarabun New / 標楷體, mode 15, compressPunctuation) first
parts on page 16 (0-based), y -670: an answer paragraph after "ตอบ:"
wraps a word earlier, and the drift adds a page.
It was T135, not T136: the answers open "ตอบ :<tab><tab>…", and T135 held what stands before any tab to a left
stop, default stops too — where squeezing the label may move the tab a stop back. T135 now holds only what stands
before the tab that takes a first line's label to its hanging indent (zh-499adba6's "（六）<tab>"). Same-base
sweep, 597 documents: nothing moves on Linux's fonts (zh-499adba6 / zh-9932bd83 hold 27.0; zh-6a4fc013 is 26/26
pages here either way) — the Mac's fonts are the ones that show the page.
Mac 0fcba326 at 6ee23008 (OFFICE_WORD_FONTS=mac, PDFKit): zh-6a4fc013 54.2%, 614/614 lines, 26/26 pages
(n383: 51.5, 27); zh-499adba6 and zh-9932bd83 unchanged at 26.8 (99/96 pages).

### T145. A number that fits may part after its hyphen under East Asian layout — DONE (2026-10-22)
Owner: none (Linux office1 01Ak4ibJ built it)
Documents: zh-b58b4f0c (39.6%), zh-875759ff (34.9%).
zh-b58b4f0c's cell "…8年(104-111年)計畫" ends a line "（104-" in Word's print, the next "111年）計畫"; ours kept
"(104-111年)" whole (T-hy3 left East Asian layout out on zh-64044a1d's phone numbers alone). Word's prints part
after a hyphen between a letter or digit and a digit some seventy times in the corpus — "106-" / "109 年",
"《2018-" / "2020 年", "電話：02-" / "87897530", "GB 32100-" / "2015", "（2019-" / "2021 年）". Not in a document
of mode below 15 that compresses punctuation: zh-0104b952 (mode 14) keeps "电话0571-85455244" whole with room for
"0571-", zh-10eab555 "（GB12268-2012）", zh-15428325 "国贸路811-819号", zh-64044a1d (mode 11) its phone numbers —
every print that parts is of mode 15 or of a document that compresses nothing. A word wider than the line is
parted where the line ends, as before. (`_fittingWordHyphens`, in the span and the fitter.) Same-base sweep, 597
documents: zh-875759ff 34.9 -> 99.2, zh-b58b4f0c 39.6 -> 99.8, zh-dd4c6e05 96.3 -> 100, zh-489ac253 99.0 -> 100,
zh-344a8d08 25.5 -> 26.8, zh-b2e0f286 +0.7, four more +0.1-0.2; nothing down (the first try, every document,
cost the three above 0.2-0.8).

### T143. POI gaps after n377 — split across sessions (2026-10-22)
Coordinator: starling-bd (session 011uWpmCQYr9neyJ1V1gzrrb, Mac).
Sweep n377 at afd9a7ac: text-bearing POI 98.7%, 111/111 page counts.
Each item is claimed by editing its line below and pushing that alone.
Word prints happen only on the Mac: ask before printing, one at a time.
- a. delins 76.7%: balloon order for field-code/formatting changes.
  Owner: none (starling-bd looked, released). Word's groups go F, FC, F
  for the first three hyperlink paragraphs, then F, F, FC; ours F, FC, F
  throughout (same 23 F and 10 FC). Office.md's 2026-10-21 labs say the
  order depends on context beyond the paragraph itself. Word for Windows
  (Windows 01QbbApP, 2026-10-22, exported with markup, balloons) prints
  the same 33 balloons in another order: by y, Mac FCF FCF FCF FFFC FFC
  FFC FFC FFC FFFFC, Windows FFFC FFC FFC FFC FFC C FFFFC FFC FFC FFFFC.
  The order is not the file's alone; the Mac print is one Word's. Not
  worth chasing.
- b. bug57031: DONE (starling-bd). Its one missed line (p2's formula)
  stands where Word's does to 0.5pt; PDFKit groups our math font's
  glyphs with the line above. But its footer's right `w:ptab`, the line's
  first tab, stopped at the centre stop: fixed (53e00211), x 281 -> 490.
- c. chartex 78.9%: sunburst drawn natively (T15). DONE 2026-10-22
  (session 01QbbApP, Windows box): chartex 77.8 -> 100. Sheets'
  chart-sunburst.xlsx passed to starling-office-2.
- d. TestTableColumns: measured (starling-bd), nothing to build. Every
  rule within 0.4pt of Word's (row pitch 14.25/14.79 vs 14.4/14.16). The
  visible difference is colour: "auto" rules are our soft-black ink
  0x1B1B1B (the app's screen text colour) where Word prints black.
- e. 60316's header divider: DONE (starling-bd, 429fe822). A line sized
  105% of the margins (wp14:sizeRelV) and centred on the page, accent2:
  now y 36.9..753.3 grey, as Word's print. Boxes that fit their text
  (a:spAutoFit) ignore the share.
- f. drawing.docx p9: nested-table banner 5.4pt right (T142's autofit
  parent). Owner: Linux 017F2GnT (lenovo-2), 2026-10-22 — DONE, 6705abb1:
  a nested table in an autofitting parent that already spans its page's
  text keeps its saved grid, its content overflowing; the banner is at
  391.55-552.8 (Word 391.55-552.72); a parent with room still grows with
  its child (nested-minima's 241.5 untouched); no line score moved. Left:
  Word clips a picture to the cell it overflows (the 175.5pt picture
  ends at 552.72, the logo at 381.12 in Word's print); ours draws them
  whole. Owner: Windows 01QbbApP, 2026-10-22 — DONE: cut at the cell's
  edge (not the text's), sideways only; the logo now ends at 381.2 and the
  picture at 552.8. Lab dr/clip1 (Word for Windows): fixed cells match to
  0.5pt. Left: an autofit cell grows to its picture in Word (lab C: 339pt)
  while our _minContent counts only text.
- g. Near-100 (form_footnotes 97.7, bib-chernigovka 99.6, bug59058
  99.9): read the geometry; say which are PDFKit grouping and which are
  layout. Owner: Linux 017F2GnT (lenovo-2), 2026-10-22. Findings: under
  PyMuPDF (the Linux scorer) bib-chernigovka and bug59058 are 100.0 —
  every line Word prints we set at its place, so the Mac's misses there
  are PDFKit's grouping. form_footnotes is 98.8 here, one line missed,
  and it is ours: p2's "☐ Yes ☐ No" (and every checkbox) is a text "☐"
  in ours, a drawn 9.36pt square with no text in Word's print — so our
  line's text opens with "☐" where Word's opens with "Yes" — and Word's
  auto-sized FORMCHECKBOX advances 11.5pt at 10pt (1.06 + 9.36 + 1.08)
  where our glyph advances 8.96 (11.87 in the table cells of p2), "Yes"
  2.5pt left of Word's. A fix draws the box as a square object of that
  advance, not a character: only form_footnotes and checkboxes carry
  FORMCHECKBOX in the corpus. Not built; released.
- h. form_footnotes' FORMCHECKBOX as a drawn 11.5pt box (from g).
  DONE (Mac 0fcba326, 2026-10-22; the user chose Word's look). Not a model
  change: the "☐"/"☒" stays in the text (and saves as the field) and the
  layout, under Word's rules, hides it and sets a box after it — 9.36pt
  square stroked 0.72 at 10pt, 1.06 before and 1.08 after, 8.4 over the
  baseline, ticked crossed corner to corner. All 29 of form_footnotes'
  boxes stand within 0.2pt of Word's x; n386 vs n385: form_footnotes
  97.7 -> 98.9, checkboxes 6/8 -> 6/6 lines, nothing else moved.
- i. An autofit table cell holding only a picture grows its column to the
  picture plus the cell margins in Word (lab dr/clip1 case C: 339pt);
  ours keeps the column and cuts the picture, because _minContent and
  _autofit count only text. Owner: Windows 01QbbApP, 2026-10-22 — DONE:
  a picture alone in its paragraph and a nested table count toward their
  column's narrowest; past the column's room Word shares it in proportion
  (labs dr2/g, h, k). Lab C 339.8 (Word 339.77); drawing p9 within 0.3pt;
  of the 12 nested-table docs, zh-291fcea7 went 31.4 -> 32.4 and the rest
  are unchanged. NestedTableLayoutTests: 3/3 pass on the Mac (macOS-doc; full OfficeApp suite 620/0). Note:
  drawing.docx --convert segfaults about 4 runs in 5 on Windows, after
  the PDF is written; the base binary does the same and Linux is clean.
- Test note: the font-bundle test failures were fixed by macos-ios;
  457 Office tests pass on starling-bd's checkout.
- 60329 12.6% is Word's clipped print of landscape content, not ours.

### T144. A note's raised number is no character of its line — DONE (2026-10-22)
Owner: none (Linux office1 01Ak4ibJ built it, from Linux 017F2GnT's measure and the Mac 01Xgpbk5's lab fn344)
Documents: zh-344a8d08 (footnote 2, p4).
"2 「嚴重特殊傳染性肺炎(COVID-19)…裁罰規定」之相關規定。" (style afa 10pt, jc both; the file is mode 15, its Normal
overflowPunct 0) is one line in Word's print, "「", "」" and "。" squeezed by ~4 each. Ours sent "定。" on: the space
after the raised "2" made it a line with a word space, where corner brackets give nothing (lab `sq-sp`), and the "「"
was the line's opener, which keeps its blank half. A raised (superscript) run a line opens with now counts as no
character of it. Lab fn344 (Mac): the hang seen was this squeeze — T119's lab `lp` is mode 14 and stands. Same-base
sweep, 577 documents: nothing else moved; zh-344a8d08 25.9 -> 25.5, its note 2 now one line as Word's, because ours
then fits all three lines of note 3 on p4 where Word carries the third to p5 — our notes stand 17.7pt higher than
Word's under the separator, the placement residual Linux 017F2GnT has on the board and is taking next (agreed: land
it as is).

### T142. Nested-table sizing — fixed-parent fix landed; remaining work released
Owner: none — Codex Mac released remaining investigation, 2026-10-22
Worktree: starling, branch office; baseline e0edc780.
Word labs found and separated a fixed-parent bug: nested tables widened
for oversized content and computed percentages from their saved grids.
3429a7ae keeps explicit child widths and resolves percentages against the
parent's cell width. Nine Word lab cases match marker edges within 0.06pt;
all seven lab pictures match bounds within 0.01pt. Three regressions added;
454 Office tests and repository lint pass. Full 577-document sweep has
zero conversion failures and unchanged per-file line scores, page counts,
image counts and image bounds. POI text-bearing mean remains 98.7%.
Final sweep: /tmp/starling-poi-fixes/nested-table/sweep.

The original drawing page 9 banner remains 5.4pt right of Word: that parent
autofits. Its parent and nested minimum/preferred widths need coordinated
sizing; a universal nested-table or page-width cap fails other Word labs.
Evidence, scripts and measurements: /tmp/starling-poi-fixes/nested-table.

### T141. POI picture layout — two fixes landed; remaining work released
Owner: none — Codex Mac released remaining investigation, 2026-10-22
Worktree: starling, branch office. Baseline ebf9faf6; same engine and
OFFICE_WORD_FONTS=mac throughout.

- c4b68617: picture-only tab rows use spacing placeholders. The first
  body image in issue_51265_3 moves y213.31 ->121.55 (Word121.40), all
  seven images retained. Opaque VML objects retain text-tab metrics;
  the first broader attempt regressed zh-7773163d and was rejected.
- 7b3b98b6: retain and lay out horizontal inline effect extents, including
  character borders. All 1/2/7 images in issue_51265_1/2/3 match Word's
  bounds within 0.05/0.11/0.36pt. Border labs agree within 0.25pt.

451 Office tests and lint pass. Each fix has a full 577-document sweep;
line scores, physical page counts and image counts are unchanged. POI
text-bearing mean remains 98.7%; nine textless files remain N/A. Final
artifacts: /tmp/starling-poi-fixes/picture-header/sweep-scoped and
/tmp/starling-poi-fixes/picture-effects/sweep. Reports and Word lab inputs
are retained; redundant earlier generated PDFs were deleted after a
full disk interrupted a sweep, then all 577 conversions were rerun.
Browser/WASM was not validated.

Remaining visual tradeoff, not claimed: drawing page 9's nested percentage
table shifts its right-aligned banner 1.5pt further right when a neighbour's
picture effect enters the width measure (error 3.90 ->5.40pt). Word's
zero-horizontal-effects lab keeps that banner's right edge fixed. The
picture extent rule is verified; the nested-table width/overflow rule
still needs work. See office.md and picture-effects/drawing-*. Do not
summarize this batch as free of visual regressions. Other open POI gaps
remain listed in T140; T15's existing chart owner still applies.

### T140. POI matching — four fixes landed; remaining work released
Owner: none — Codex Mac released remaining investigation, 2026-10-21
Worktree: starling, branch office. Latest renderer fix: 8ac6515c.

Landed, each swept against all 577 Word references with verified fonts
and OFFICE_WORD_FONTS=mac:
- 55966: named inline placeholder reuse, 33.3 -> 100% (f8e83879).
- 60316: drawing-position compatibility fallback, 97.0 -> 100%
  (a4393667); sidebar no longer overlaps the body.
- rtl: complex-script face and fallback, nine garbled lines -> seven
  readable lines, all matched (32c23c52).
- bug65649: short cells centred/bottom-aligned in a split row's kept
  lines, all 6,674 reference lines matched (8ac6515c). Also improves
  14 Chinese documents; no score regresses.

The RTL matcher correction (0a319fd0) was checked independently on the
old PDFs: only rtl changes, 71.4 -> 0, because null Arabic text no longer
matches arbitrary letters. The renderer then takes it to 100%. Its new
edge comparison accepts PDFKit's visual and Skia's logical bidi order.
This remains a page/height/edge-text metric, not full visual equivalence.

Current: 111 POI files, mean 90.7% including nine textless references;
98.7% over the 102 text-bearing files, median 100%, 99 at least 95%.
All 111 physical page counts match. Chinese mean 94.5%, median 98.4%,
386 at least 95%, 458/466 page counts match. No line-score regressions
across the full corpus. Artifacts: /tmp/starling-poi-fixes/split-cell/sweep;
comparison.json records the latest delta. Initial audit:
/tmp/starling-word-audit-20261021; corrected baseline: matcher-baseline
under /tmp/starling-poi-fixes.

Validation: 445/445 Office tests, four matcher tests, repository lint.
Font resources now load under nested SwiftPM/XCTest bundles (af3cac2b),
so the old LineHeightTests failure passes without changing its assertion.
Broader Mac checks still fail at termd's PTY session, terminal auto-answer's
child process, and the missing swift-6.4-RELEASE_wasm SDK; these are not
waived. Browser/WASM parity was not validated in this batch.

Remaining, not claimed here:
- delins 76.7%: field-code/formatting balloon order. Original Word print
  reproduced; isolated, mark-removed and prefix variants rule out using
  the paragraph's own mark alone. See office.md and balloons lab.
- chartex 78.9%: native sunburst labels, still a fallback image. T15 has
  an existing owner; coordinate there before taking that implementation.
- 60329 12.6%: clipped portrait reference print of landscape content.
  Keep that oracle defect separate from renderer defects.
- Near-100: PDFKit grouping in bug57031, bug59058, bib-chernigovka and
  form_footnotes; inspect geometry before treating these as layout bugs.
- Visual: 60316's relative-height/vertically aligned header divider and
  TestTableColumns borders/positions still need work. T141 fixes the
  issue_51265 image/header gaps and records a remaining nested-table
  banner alignment tradeoff. Nine textless files are N/A, not line-match
  successes; initial contact sheet: textless-comparison.png.


## Done on 2026-10-14 (session 011uWpmCQYr9neyJ1V1gzrrb)

Each has its entry in `office.md`.

- Table placement by alignment and compatibility mode; bold-face space
  width; a Latin word at a cell line's end (9f61ce99)
- Floating pictures that text wraps round, rotation (e9ad2983)
- Fixed-layout tables keep their grid; grid lines may hang past the
  page foot (8d854de9)
- Cell-ruled tables: unstated sides unruled (35cdc651)
- Picture lines in cells keep to the grid (dee02ae9)
- `leftChars` counts from the hanging line (e4a5cf77)
- Lone page-break mark holds its page before mode 15 (444b6614)
- Page numbers per section (aaeca4fd)
- `w:topLinePunct` at a paragraph's start (b4f5393e)
- Embedded faces are not swapped for YaHei (d5c74cec)
- Declared-Latin unknown faces set in Calibri (55b60b0e)
- Space after stays at the page foot (a0237668)
- Outside/inside alignment by page side (607bfce9)
- Justified mode-15 spaces give a quarter each (fe308378)
- Font-table `w:altName` for faces Word lacks (551ad92d)
- Gridded multi-line paragraphs use the tallest strut (02e1c405)
- Fit-to-text text boxes shrink to their text (92c1b88a)
- Lists over one definition share their numbers (c2ec89d9)
- A centred cell is set in its parted row's part on the page (c2542ff6)
- Kept runs: moved from their start, carried through kept table rows,
  over from a page's middle whatever their length (f67d5ba6, f774a736)
- Text-anchored floating tables stand their `tblpY` lower (dd1ad844)

## Done on 2026-10-15 (session 01Xgpbk5jLzrCcB28yZBzYHN, Mac, starling-ios worktree)

Each has its entry in `office.md`; every one swept against a clean
baseline at the same tip, nothing down.

- Embedded East Asian faces drawn (T8, 12684c7f); exported PDFs' text
  reads ideographs, not radicals (starling-engine a0cbed78)
- A no-break space is an em in a square face (c7c1610a)
- Theme fonts by script, and in headers/footers/footnotes (7a5bf43c):
  zh-1a3c7aa0 78.0 -> 91.7
- A header's/footer's fit-to-text box keeps its first page's width
  (36ecdfb8): zh-a4b0f6ea +6, zh-5901e2b0 -> 100
- "At least" rows add their cells' margins; hidden-mark empty cells ask
  nothing (afe8a68e)
- A document background brings a phantom header and footer (b18da088):
  bib-chernigovka 0 -> 90.3
- A line of spaces and tabs is its mark's line (f4cc1940):
  IllustrativeCases 76 -> 100
- A shape's text in its preset's text rectangle (78eabee3):
  shapes-with-text 37.5 -> 62.5

Leads measured and left (office.md): T1 autofit (released); text in
group shapes (5 files); a page-anchored floating table Word breaks
after its first row (zh-a4b0f6ea p20); frames with wrap="around" let the
next paragraph flow beside them (lab fr1; only 2 files have body frames);
drawing's nested HTML tables (flattened, T9's limit).

## Open tasks

Two sessions now share the Mac and its one Word. Word prints (labs,
`docx-word-render.sh`) must not overlap: before printing, check
`pgrep -fl "[o]sascript"` and that no other print is mid-dialog.
Sweeps are per checkout (`lab/tools/sweep.sh` run from inside the
worktree writes `~/starling-doc-check-<worktree>`), so they never clash.

Ranked roughly by lines at stake. "Known" is what has been measured;
start from there.

### T129. Windows rules: an uninstalled face is its fontTable altName, as Word for Windows draws it — DONE (2026-10-19)
Owner: none (Windows 01QbbApP built it, released)
Built as the Mac (011uWpmC) decided: the default stays the author's faces,
with the 方正 Song titles at their own 1.51-em line (8f250d91); Word for
Windows' altName fallbacks are a mode of their own, OFFICE_WORD_FONTS=windows,
for comparing with its prints: 13 of them, 64.5% -> 84.8 (zh-6cd1befe 100,
zh-dc9cfa34 98.4, zh-ec1b6f63 99.7, zh-34a6519a 86.5). Mac output identical.
Left under `windows`: zh-875759ff 31.6, zh-e7bdb543 4.9 (楷体_GB2312 -> KaiTi).
Looked (Windows 01QbbApP, 2026-10-19): zh-875759ff under `windows` matches Word for
Windows' print to its p8; its first miss is a p9 line end — Word keeps "的70%" on
"…人均生活消费支出的70%", ours wraps "70%" (a Latin word at a line's end, the
fitter's, not KaiTi's; Word's print names that body face TimesNewRoman, linked).
zh-e7bdb543's KaiTi form lines differ by 楷体 glyphs drawn in YaHei bold (no KaiTi
bundled). Comparison-mode only; released.
Word for Windows follows w:altName for a face it lacks (仿宋_GB2312 -> 仿宋 -> FangSong;
方正小标宋_GBK -> 微软雅黑): zh-f59a76e9's empty 方正小标宋_GBK line and
zh-6cd1befe's p50 title are YaHei in its prints, ours `square` under the
Windows rules. Gated off under OFFICE_WORD_FONTS=mac (Word for Mac ignores
altName). Checked against Word for Windows prints (~/starling-doc-check/lab/fsw).

### T127. zh-73534289 p27: a table row Word moves whole to the next page — DONE (2026-10-19)
Owner: none (Windows 01QbbApP measured it, 2026-10-18)
Documents: zh-73534289 (about 44 misses a page over pp28-33). Row 91
("強化資金規劃運用能力 | 其它 | 提供資金協助…") starts at 698 of 748 and Word
sends it whole to p28 though it parts this table's other rows; labs
to find what keeps it whole.
Labs (Word for Windows, which prints pp27-28 as the Mac reference does;
~/starling-doc-check/lab/rw on the Windows box, each the whole document
with row 120 — the 121st w:tr — changed): the row is never parted, and
none of these parts it: its vMerge off (v1), vMerge off rows 118-120
(v6), w:widowControl 0 in its paragraphs (v2), w:hideMark off (v7), the
long cell made Web style or wordWrap on (W2, W3), the long text in the
Web cell instead (W4), the last cell 4-6 lines with 3 of room (L12-L20;
2 and 3 lines fit whole, L6/L10), and with row 119 cut to 2 lines, 5
lines of room and a cell of 7-10 (R4, R5) — Word leaves the room empty
and starts p28 with it. Rows 73, 78 and 92 of the same table, built the
same way (an empty vMerge cell with no w:p, single-paragraph cells, a Web
cell fourth; 78 the last of its merge too), are parted in the Web cell
with 3 to 7 lines of room. Not found: what the parted rows have that 120
lacks. Next to try: row 73's cells pasted into row 120's place, then
halved until it stops parting.
Done, and it changes the question: row 73 is "模性導入…" alone — the
rows that looked parted (73, 78, 92, …) are rows of their own in the
file, cut where its source's pages broke. Word parts NO row of this
table anywhere: every page of Word's print opens at a row's start.
Ours parts rows, so the question is what makes the whole table's rows
unbreakable. Ruled out, table-wide: w:divId off every row (v9), an empty
w:p in paragraph-less cells (v10), outset borders as single (v11). Not
yet: the compat flags (doNotSnapToGridInCell, growAutofit,
doNotUseEastAsianBreakRules…), the repeated header row (tblHeader), the
exact 16pt cell lines, a fresh table built in this package.
Then (Windows 01QbbApP, 2026-10-19, labs ~/starling-doc-check/lab/rw2): it is the
footer, not the table. In zh-73534289's package even a fresh one-row table a page
and a half tall (M73c) skips page 1's 33 free lines and parts from page 2; in
zh-eb54d3b0's package the same body parts on page 1. Bisected: its settings (X1,
X2) and styles (X3) change nothing; its section does (X4). Within the section:
no footer (X5) parts; margins of 1984 (X6) part; footer 200 twips up parts;
bottom margin 1100 parts, 980 does not. Within the footer (a framePr paragraph
holding "8-PAGE", w:w=11907 hAnchor=page x=1 y=-2 wrap=around vAnchor=text, then
an empty Footer paragraph): the frame removed parts (X7); the frame without w:w,
page x=1 y=-2, parts; w:w=3000 at page x=1 or centred on the margin, y=-2, does
not; w:w=11907 with y=1 parts. So an explicitly sized footer frame raised above
its anchor, reaching over the bottom margin, stops Word parting rows at the page's
foot. Built as "a footer with any frame over the margin" it cost ~40 zh documents
(100 -> 11-48: their page numbers are auto-sized frames, y=1, centred on the
margin), so the exact trigger (sized frame, its top over the margin by how much)
is open. zh-73534289 went 82.7 -> 99.6 with it. Patch kept at the Windows box's
scratch foot2.patch; not landed.
Landed narrowed to a sized (w:w), raised (y < 0) footer frame over the margin
(Windows 01QbbApP): zh-73534289 82.7 -> 99.6; the five other docs with such
frames (zh-33d025f6, zh-3550642e, zh-6cd1befe, zh-749cb15a, zh-e0ca7252) as
before; no other document has one.
Then: the four compat flags off (v12) still moves row 120 whole. With the
repeated header row off (v13) or every vMerge off (v14) the pages shift
and row 120 no longer meets a page foot needing to part, so neither
says anything yet; to test them, pad the text above until it does.

Tried, reverted (patch kept by starling-office1-df): in the fitter, a piece right after a tab, in a paragraph with a
right stop, over the margin with the tab starting inside, got its last advance shortened by the overrun (as a
hanging mark's is) and nothing squeezed. The engine then breaks before "20" all the same — the shortened advance of
a Latin digit at a line's end does not hold the line as a mark's does — and the file went 12.0 -> 7.9, two lines
more. Needs: a way to let a Latin run overflow (or the tab to give its width first), and for case (b) a break
opportunity before a tab, which UAX14 (BA) forbids. Also seen: our TOC page starts 33pt lower than Word's.

### T126. zh-2f9463d6 (95.9% on Windows): a cell's text before a trailing U+3000 makes its row a line taller — DONE (2026-10-18)
Owner: none (Windows 01QbbApP built it, released)
Documents: zh-2f9463d6 (p20-21, 28 of its 29 misses). Its table row
"……　" (12pt, Times/仿宋, centred) is 26.6pt in Word's print and 39.7 in
ours. Lab `el` (Word for Windows, its own rows): "AB　", "——　" alike;
"……", "…" and a lone "　" are not.
95.9 -> 99.9, nothing else moved (306 zh, 110 POI): a space or U+3000
sets no line where the line holds anything else (office.md "A space
sets no line"). Also found (Mac 011uWpmC agrees): Word for Windows maps
仿宋_GB2312 through fontTable w:altName (仿宋 -> FangSong, a 1.000-em
Office cloud font); Word for Mac does not.

### T125. zh-eb54d3b0 (95.4% on Windows, twelfth sample): line ends on p1 run a character short of Word's — DONE (2026-10-18)
Owner: none (Windows 01QbbApP built it, released)
Documents: zh-eb54d3b0. p1's "到2025年总体目标：一是产业规模升级，" takes "级，"
in Word's print and not in ours; every line after it runs one or two
characters behind to p2's paragraph end.
95.4 -> 98.0, Word's 16 pages, nothing else moved (306 zh): on a
character grid the character taken is its cell (e8ac71eb), and a mark
closed up there is half its cell (b9ed28f7, labs og2-og4). Left: p10's
"…补助0.8万元、0.3" takes a Latin word Word leaves — labs lw-lw4 say a
word of two or more characters needs T86's start rule whatever the
marks; with lenovo-3 (01Ak4ibJ), after T119. And even pages' "- 2 -"
footers: Word's text layer joins them to the empty footer paragraph
beside them (the reader's, not layout).

### Regression (Mac 011uWpmC, 2026-10-17 night): fdceb326 takes zh-3c055c9b 76.7 -> 33.5 on the Mac — FIXED (645e5e65)
Same-base sweep on the Mac (s299 -> s300, the tip with fdceb326 "a run's
character spacing falls back to its style's, then Normal's"): zh-3c055c9b
76.7 -> 33.5, every page; nothing else moved. With fdceb326's
RichLayout change alone reversed on e3c3b781 the document misses 137
lines, with it 391. (The commit's note gives 44.9 -> 61.4 against s124,
a build before T85's grid squeeze, so the two disagree on the base.)
zh-3c055c9b is mode 15 on a linesAndChars grid of 17.0pt at 16pt; its
styles' spacing is probably double-counted with the grid's own addition.
For session 01QbbApP (fdceb326's) or whoever holds T85.
Fixed by 645e5e65 (Windows, 01QbbApP): the opposite of double-counting.
Off the grid by its paragraph (表標題, `w:snapToGrid` 0) Word still gives
ideographs the grid's addition, and ours left it out, so the style's
spacing took them 1pt under Word's (lab `sp`; office.md "Ideographs off
the grid keep its addition"). zh-3c055c9b 91.7; T85's p2 and p8 lines
unchanged; of the 148 nothing fell.

### T102. zh-e0ca7252: 52 pages where Word's are 51 — DONE (2026-10-17)
Owner: session 017F2GnT (Linux)
Documents: zh-e0ca7252 (41.9%, sixth sample). 42.0 -> 98.0, Word's 52
pages, nothing else moved: ringed-number EQ fields, a mode-15 Latin word
taken at the line's end, a Latin ")" hanging, leftChars beside a twips
hanging, lrTbV cells horizontal, a section's last paragraph of a
floating box taking no room (office.md, 2026-10-17).

### Note from the Mac (2026-10-17, night): the scorer measures lines from the page's top — rebuild your cached pdf-text
Word's print through the dialog puts a page that is nearly a standard
size on that paper: zh-8f9b19f4's 11860x16700-twip pages (835pt) come
out on A4 (842), its content from the top as ours. The line matcher
measured heights from the page's foot, so every line of such a page
stood the difference (7pt, over its 3pt) off ours. pdf-text.swift and
the matcher's PyMuPDF reader now give y up from the page's top
(negative). Rescoring the same PDFs moves only zh-8f9b19f4 (14.1 ->
47.4) and POI's 60329 (0.0 -> 12.6); every other score is the same.
**sweep.sh caches the compiled reader as `$D/pdf-text` — delete it**
(`rm ~/starling-doc-check-*/pdf-text`) so the next sweep compiles the new
one, else the two sides of a comparison read differently.
Also T101 (one column where sections disagree) is in for zh-8f9b19f4,
and labs `pa` (Word 16): its WPS styles with no pPrDefault do give 8pt
after, as ours — that rule holds.

### Test failure (Mac 011uWpmC, 2026-10-18): ChartTests.testEveryKindSurvivesItsOwnXML
Fails on the tip from 5165c01a ("charts: Excel 2016 clustered columns…",
session 01EUwing) on: the line chart's round trip through its own XML
no longer compares equal (ChartTests.swift:23). It fails with or without
the Mac's own changes. For whoever owns charts.
Linux (slides session), 2026-10-18 10:25: passes at 193b1c32, and has
since 0239c797 ("a shown line's \"none\" marker is no marker, as
before"), an hour after this was posted — likely the fix. Mac: please
re-run at the tip and close this if it passes there too.
Linux 017F2GnT, 2026-10-19 01:45: failing again on the tip, now on the
pie chart's round trip (ChartTests.swift:23, "Chart(type: …pie, title:
Sales…"), with and without the layout change being tested. Charts owner,
please look.

### Lead (Mac 011uWpmC, 2026-10-18): a long word after a space under East Asian layout
8498b68f briefly let a word of 20+ characters after a SPACE open a line of
its own under East Asian layout too (7184c8a6 took that back, as
testABodyWordWiderThanTheLineOpensALine says Word parts such a word where
it stands). With it, zh-76d361b2 missed 1 line where it misses 5, and
zh-454e2e29 7 where 8; nothing else moved. So Word may move some such
words after all — the test's case is "Note: " + 80 underscores. Needs a
lab: a long URL/underscore run after a space, East Asian layout on, in
Word 16. Done (Mac 011uWpmC, lab `ww`, zh-76d361b2's package): after a
space that follows an ideograph, 80 underscores open a line of their own
in Word's print; after "Note: " they part where they stand. Built that
way; no document moved (s327 -> s328), and zh-76d361b2's own case is
something else.

### Looked at (Mac 01Xgpbk5, 2026-10-19): zh-d8247da5 91.9 — released: 3 of 37 lines, all in its landscape form's dense cells ("房屋坐落門牌編號…", "減半使用執照用途別"), where the reader groups neighbouring cells' text differently; not layout

### Looked at (Mac 01Xgpbk5, 2026-10-22): zh-340d52e9 75.6 → 76.2, released
a58ab590: a cell's text past its exact row (page 5's 48.8pt "其他里內公共區域認養之必要支出" row, the page's last) now runs on down the page as in Word's print. Left: pages 6-9's repeated header row reads "地點明備註" in Word's print and "地點明" in ours (the reader grouping two cells by a hair), and page 6's lower half ("潔維護" against our "▓3.其他經區公所核可之"), not looked at.
zh-afdd4a7e 93.6 — looked, released: reader, not layout. Its table cells match Word's to 0.8pt, but PDFKit reads ours with text repeated ("查\n調" four times where "調查" stands once per row, "%%%%"); every glyph is drawn once (get_texttrace). Ours are Skia's Type3 fonts, FontMatrix [.001 0 0 -.001] and FontBBox like [35 105 965 -828], y running down, and PDFKit mis-groups them across rows; Word's embedded PMingLiU reads clean. The same repeats show in ~10 more of our PDFs (zh-e49d7943, zh-05315c2a, zh-57d7a0ea, zh-86aae09f…) and would in Preview's copy and paste too. A fix would be in the engine's Skia PDF backend (starling-engine), not here.

### Note from the Mac (2026-10-23): the zh corpus is 606 documents — a twenty-eighth sample
Twenty more (`random.seed(20261111)` among the 39 unprinted, 15 to 400 KB, drawn by
docxcorp id, all printed), checked in. It starts at 89.0% (median 98.4), 18 of 20 page counts
Word's. Its low ones, unclaimed: zh-694447ca 11.1 [DONE Mac 01Xgpbk5 2026-10-23: 86.6 — the rest of a page-split paragraph takes no first-line indent (fb7a6d8a), a floating table raised over the table before it goes over whole (one document's evidence, kept narrow). Left: the footer's framed folio stands 66pt above Word's on every page (frame w:y=1 anchored to an empty 9pt footer paragraph, snapToGrid 0) — the scorer skips folios, so no score; and a negative tblpY at a page's head is not applied (4pt)],
zh-8628cfbe 26.0 (45/46 pages) [CLAIMED Linux b2 01JsizVV 2026-10-23], zh-17ac8aa2 75.0 [CLAIMED Mac 0fcba326 2026-10-23], zh-31d580df 93.9 [CLAIMED Mac 01Xgpbk5 2026-10-23], zh-13552a3a 94.6,
zh-bbbb2e6a 95.2 (16/15 pages) [DONE Mac 01Xgpbk5 2026-10-23: 98.2, 15 pages — an unstated cell side takes the table's or its style's width, not the cells' most common one; zh-505b9619 80.9 -> 96.4 and zh-ad224275 91.9 -> 96.9 with it].

### Note from the Mac (2026-10-22): the zh corpus is 586 documents — a twenty-seventh sample
Twenty more (`random.seed(20261110)` among the 59 unprinted, 15 to 400 KB, drawn by
docxcorp id, all printed), checked in. It starts at 89.0% (median 98.1), 17 of 20 page counts
Word's. Its low ones, unclaimed: zh-b5359de4 2.3 (14/25 pages) [Mac 01Xgpbk5 → 77.9, 14 pages: a cover's sections of other columns no longer set the file in one column (8368f4e8); in columns a page or section break goes to the next page, not the next column (5099d7c0); a section begun down a page counts that page its first (7801acb4). RELEASED, left: Word BALANCES a section's columns on its last page at a continuous break — p4: the preface section's last lines (para 74) stay in column 1, its empty para 75 (YaHei bold 14pt, 1.5 lines) goes to column 2's head, and the next section (TOC heading, 目录) starts under the balanced block, 44.3pt higher than ours; the cover's continuous two-column empties balance on p1 too. Ours has no column balancing (slots of page*columns, filled in turn). Then pp8-13's table rows across columns, not looked at],
zh-6e6b9821 56.8 (4/5 pages) [DONE Mac 01Xgpbk5 2026-10-23: 99.2, 4/4 pages — blank paragraphs beside a centred floating table (5e452e14), each box of a VML group at its place in its shapetype's textboxrect; zh-e9f256c1 -> 100 too. Left: the group's arrows and box outlines are not drawn (VML shapes in a group print as nothing; text only)], zh-505b9619 71.3 [Linux office1 01Ak4ibJ (lenovo-3) 2026-10-23: 74.4 -> 98.8 — "）。" hangs half an em on a line with word spaces (labs u5/u6, Mac); "%" starts a line by the document's own Taiwan list. RELEASED, left: p6 "…傳真機電話號|碼" (Word wraps "碼"), p15 "…招標時載|明；"; u5 with its blanks as "某" (no word spaces) is Word's at the same limit and ours lower — not found], zh-3ab8a2fb 78.0 (28/27 pages) [DONE Linux b2 01JsizVV → 99.2 on Linux, pages right: a continuous section on paper of another size (its landscape "附件2" table after portrait) starts a page], zh-d3d3f266 93.7 [DONE Linux b2 01JsizVV → 99.3 on Linux: an exact line set w:textAlignment "bottom" ends the text's own line at its foot — 22pt YaHei titles in 28pt lines, baselines 18.06 down in Word's print; also zh-5ff074a9 97.8 → 98.3].

### Note from the Mac (2026-10-22): the zh corpus is 566 documents — a twenty-sixth sample
Twenty more (`random.seed(20261109)` among the 79 unprinted, 15 to 400 KB, drawn by
docxcorp id, all printed), checked in. It starts at 92.0% (median 99.5), every page count
Word's. Its low ones, unclaimed: zh-c15af02e 41.9 [Mac 01Xgpbk5: 勵 U+F97F is Noto's (all 122 Noto compat ideographs now are, 5560cf54) and a Noto joiner no longer holds a gridded paragraph's lines (46.2 -> 45.7, 5620f6ea); pages now Word's to p4's foot. p4 fitter DONE (Linux office1 01Ak4ibJ, 2026-10-23: its runs are off the grid and were weighed at the grid's 17 a character; "發" now taken, 14.4 -> 15.3); page 5's foot DONE (Linux 017F2GnT, 5c8d7006: a note with no line's room under its mark takes the line over; 15.3 -> 52.0, zh-344a8d08 27.8 -> 65.9). p6 DONE too (1a8fc19a: a grid line's overhang does not reach into the notes; 52.0 -> 66.5, and zh-344a8d08 65.9 -> 99.8). p11 DONE (cfe1f15b: the foot line reaches by its own faces; 66.5 -> 79.7). Pages now Word's to p36. NEXT, for the fitter (unclaimed): [p37 CLAIMED Linux office1 01Ak4ibJ (lenovo-3) 2026-10-23] p37's "〈2〉依該市社會經濟發展、交通運輸狀況、車輛持有率預測…" (style 6, kinsoku, jc both, runs snapToGrid 0, 16pt 標楷體) — Word's first line holds 23 characters with the number, ending "車輛持" at 524.58; ours 24, "…車輛持有" at 524.45: ours takes one more over its two 、. Was: RELEASED to the fitter (lenovo-3): p4 "12點規定：直轄市、縣（市）主管建築機關對於已核|發" (mode 15, compressPunctuation, zh-TW, 16pt justified, snapToGrid 0, 374.15pt) — Word takes "發" 13.58pt over off ：、（） (3.40 each), ours refuses (need/count 3.40 > width−x 2.42; STARLING_RICHTEXT_FIT=對於已核發); fits lab zz's ~3.67/mark limit. Also left: p3 "：「" — ours squeezes 「 3.7, Word gives it the full grid cell], zh-a031fa16 55.9 [DONE Mac 0fcba326 → 89.0: an embedded SimSun with bitmaps (EBDT) under another face's name is drawn an em a glyph, ASCII too, bold unwidened — lab `emb`; see office.md],
zh-9462c6d6 58.6 [handed to Linux b2 01JsizVV by the Mac: p1's foot — Word keeps the first line of "（二）促進有線廣播電視普及發展…" at 774 under "…服務品質。" (759) and runs its second on p2; ours sends the whole paragraph to p2, every page after a line early — Linux b2 measured: Word leaves an orphan (one line of three, 29.6pt left for 15.6pt lines) where nothing states w:widowControl; turning it off for every file whose defaults are silent took Linux 95.4 -> 91.7 (zh-c4491c11 100 -> 19.6, same compat and Normal), so the default is on and something here turns it off — w:divId on every paragraph, or Normal (Web)? Labs wc, wc2, wc3 (Mac): not the divs, the Web style or the compat flags — a footer frame raised over the footer's top (framePr w:y -15) turns widow control off for the body; y 0 or 1, or no footer, and the paragraph moves whole. DONE: 59.5 -> 66.4 (also zh-73534289, y -2, 99.5 -> 99.9; the 36 with frames at y 1-8 unmoved). Left, measured, released: p3's foot — our table row "四保護消費者…" parts with its first line at 787 (box to ~790.3) where Word starts the row on p4; Word's foot under this footer is ~784.3 (lab wc2: the raised frame lifts it; 798 with no footer), ours ~789.6 (the footer's empty 12pt line from 790.4). Lab wc4: the foot rises by the frame's raise point for point (foot = footer top + its negative y) — Linux b2 checked, released: we do that already (`frameRise`): footer 15.61 + raise 0.75 + 36 = foot 789.64, inside wc4's bounds at y -60 (786.9) and -120 (783.9) but at -15 Word's is under 789.4, so 0.25+ higher than ours. And our row's first line (baseline 787, box to ~790.3 by PMingLiU's line) ends past our own foot, so the row-split path lets it in by some other measure — that, not the foot, is where to look; not chased], zh-0daa510e 94.8, zh-63a571aa 95.0 (Mac 0fcba326: 96.5 and 97.9 under PyMuPDF; zh-63a571aa p5's "…供垃圾車及店鋪使|用。」，" is taken by ours with its three marks squeezed and wrapped by Word — likely the 0.455-em limit lenovo-3 is building; re-check both after it lands).

### Note from the Mac (2026-10-22): the zh corpus is 546 documents — a twenty-fifth sample
Twenty more (`random.seed(20261108)` among the 99 unprinted, 15 to 400 KB, drawn by
docxcorp id, all printed), checked in. It starts at 89.3% (median 98.0), every page count
Word's. Its low ones, unclaimed: zh-9ef811c8 26.3 (Mac 01Xgpbk5 measured, released: pp1-3 match glyph for glyph; from p4 its landscape table parts its "监督检查" row (row 3, every cell vAlign center and itself merged down over rows 3-6) at another line. In Word's print the short cells stand centred in the part on p4 (397-482) and only the channels' list parts, after 5 lines; ours centres each in the whole merged span, so they start low and every one parts, the list after 6. The parted-row centring rule (setWhole) skips them for rowSpan > 1 with cuts in the part; letting a merged cell that fits be centred in the part sank zh-e37f8d40 100 -> 67.6 and did not lift this one, so not that: reverted. Its PDFKit text also repeats glyphs ("其他他他他") — reader; CLAIMED Windows 01QbbApP 2026-10-22, labs on Word for Windows; 27.0 -> 37.9 under PyMuPDF: a row whose merged-down rows hold nothing parts only at one of their tops (lab mg). Next: the merged label centred in its part on the page, and the bulleted cell. Then 37.9 -> 39.3: a cell merged only over the row's ghosts whose text fits the part is set whole in it, and the part keeps the ghost bound's height (bullets 402.8/449.6, Word 403.7/450.5)), zh-fea6e23a 54.7 [DONE Mac 0fcba326 → 100: an autofit cell a hair over its column (0.23pt, "11:30-") is widened as Word widens it, and from 2013's layout a too-wide "29-30" parts after its hyphen; also zh-e329b438 85.1 → 89.7, zh-7dd5643e 88.2 → 90.0], zh-05699f05 77.7 [Windows 01QbbApP 2026-10-22: DONE -> 100 (PyMuPDF), PMingLiU's "–" is an em (lab ds); left: PMingLiU's "×" is 0.5 em (6.0 at 12pt, ours 7.01) but set alone it cost zh-e061a08e and 31 others a line, for a reason not yet found. Lab nb (Word for Windows, zh-05699f05's package, left-set): PMingLiU's space is 3.12 (ours 2.82), a no-break space between Latin letters 3.14, beside ideographs or after "）" zero ("甲 乙" is 12.0 from 甲 to 乙). zh-e061a08e's "（…實徵數）×100%" holds no no-break space (one run, hint eastAsia, wordWrap off, justified); the " " 2.82 wide in our PDF between "）" and "×" is a gap our layout inserts there, Word sets none (lab A: "）" to "×" 12.02). Open: that gap, then "×" at 6.0],
zh-7eba7349 78.5 [Windows 01QbbApP 2026-10-22, looked, released: 76.2 under PyMuPDF, and all 49 missed lines (pp1-2, 7-11) are, by kind: (a) one-NUL lines — a glyph Word prints with no text (likely a full-width space in an otherwise empty paragraph or cell) where ours draws a space the scorer drops: 6 of p8's 10, p1's -208 and -521; (b) the title, whose print maps two glyphs to "!" and '"' (U+0000 matches anything, other characters do not); (c) a few table-head lines PyMuPDF groups otherwise. Corrected after macos: NULs alone are no bar; (a) is the bulk, for the scorer], zh-727812d5 83.3 (Linux 017F2GnT, 2026-10-22: 100.0 under PyMuPDF on the tip, 30 of 30 lines — the Mac's misses are PDFKit's grouping; released), zh-e329b438 85.1 (Linux office1 01Ak4ibJ (lenovo-3) 2026-10-22, released: autofit's narrowest piece leaves out the automatic space after it, and a line-opening piece gives that space up — the label column is 28.09 against Word's 28.08 and "度" a line alone; lab e3w (Mac) puts Word's "30" whole from 28.08, so Word's 28.0 parts it and ours, a pixel up, does not — a 0.1pt edge; 90.3 on Linux, the rest that cell's centring).

### Note from the Mac (2026-10-22): the zh corpus is 526 documents — a twenty-fourth sample
Twenty more (`random.seed(20261107)` among the 119 unprinted, 15 to 400 KB, drawn by
docxcorp id, all printed), checked in. It starts at 91.2% (median 98.3), every page count
Word's. Its low ones, unclaimed: zh-5bfac68f 47.6 (DONE, 100 — Linux office1 01Ak4ibJ (lenovo-3) 2026-10-22: from 2013’s layout a justified line’s automatic spaces give for an ideograph by the share test marks keep, lab `as`; same-base sweep of 637: zh-5bfac68f 50.2 -> 100, zh-81aa310b 98.4 -> 99.7, zh-d9563f2f 99.4 -> 100, zh-147bdae0 +0.1, nothing down; Mac 01Xgpbk5 measured, sent to lenovo-3 — the fitter: p2's "…推動虛擬型態i僑卡作為數位僑務服務基礎，並" (mode 15, zh-TW, no grid, PMingLiU 12pt, jc both) is 501.1pt natural in 498.3 of room; Word sends "並" on and stretches, ours takes it by squeezing the two automatic spaces round "i" from 3.0 to 1.6 apiece, every mark whole. Lab 5b: unjustified, ours = Word to 0.02. The rest cascades, plus reader grouping of its "類別實施內容" heads), zh-61aaad09 50.0 (Mac 01Xgpbk5 looked, released to charts (lenovo-3): p1's pie labels are "109646, 15.85%" and "582054, 84.15%" in Word's print — value and percent to two places — where ours draws "16%" and "84%", and Word's legend wraps "实体投诉/举报"; its body lines match, p3's one-line shift likely follows from the chart's parts), zh-b0401810 81.3 (Linux b2 01JsizVV: 93.0 under PyMuPDF, 19/19 pages; most misses are a tbRlV merged cell, "职业资格证书、职业技能等级证书" 方正仿宋_GBK with spacing 51, whose characters stand 3pt lower and 4pt right of Word's, so the matcher joins them with the next column's names; handed to windows, released; CLAIMED Windows 01QbbApP 2026-10-22: fa888b3a draws its "、" as Word's "︑" (vertical forms, +0.56em down); then 93.3 -> 97.4 under PyMuPDF: a spaced vertical run's glyph starts its place, as lab vs shows. NOTE, same-base exception: zh-f2835e26 76.4 -> 75.8 in that sweep, but its ink moved to Word's (p6 287.8 / Word 288.0 / before 289.5); the drop is our SimSun stand-in's taller glyph box under the scorer. Then the column's 3.3pt across offset: text reading down has no left margin (labs vs/v2, v3), x 101.9 / Word 101.3. Now 97.4 (PyMuPDF), released. Left: (a) left-set spaced runs start one spacing late (lab vs), no document needs it yet; (b) the 35 missed lines are the reader's merges: the vertical column's characters 1-2pt from the code column's baselines, and name cells (方正仿宋_GBK stand-in, textAlignment center; "*" at 16pt in Times) whose baseline Word sets 3-4pt under the row's codes and ours 2-3pt under, so the matcher joins ours into one line (p9 "*供应链管理师S", p12 "农机驾驶操作员"); sub-point baseline work)
(1115 lines against Word's 1286) [CLAIMED Windows 01QbbApP 2026-10-22], zh-4e5fe46f 86.0 (Linux 01JsizVV: 85.3 under PyMuPDF. Its p7-p9 tables stand in wrapNone text boxes; p7's, anchored in a one-line paragraph that opens the page with its space before dropped, was cut to that line and drew one row of eleven — fixed (a piece that left only its space before behind is whole; also draws zh-147bdae0's two "附件" labels, as in Word's print). Left, released: the box stands 40pt high because the empty Body Text paragraph before it stays at p6's foot by 0.1pt in ours; Word's 10pt marks there are 楷体_GB2312 in Arial Unicode MS, lines 20.16 (1.74 em x 278/240) to our YaHei 19.87 — the drifting fallback, not modelled), zh-7dd5643e 88.2 (Linux 01JsizVV: 98.1 under PyMuPDF, 103/104 lines — the Mac's 88.2 is reader grouping; released).

### Note from the Mac (2026-10-22): the zh corpus is 506 documents — a twenty-third sample
Twenty more (`random.seed(20261106)` among the 139 unprinted, 15 to 400 KB, drawn by
docxcorp id, all printed), checked in. It starts at 80.9% (median 97.9). Its low ones,
unclaimed: zh-19dde9e7 0.0 (DONE Mac 01Xgpbk5 → 100, 3 pages: a page-anchored table parts after its first row only where its second does not fit whole — lab pa19 — and stands over the top margin when it opens the page; also zh-0513f641 43.7 → 87.5, zh-77bd4900 68.5 → 94.8, zh-291fcea7 31.9 → 38.9; Linux 017F2GnT ff44e692 → 40.2: its flow chart's labels, text boxes anchored in the form's cells, are drawn now — they were cut to their rows), zh-5f9b6549 0.0 (DONE Mac 01Xgpbk5 → 100: under w:background a header ends in one more empty Normal paragraph — labs 5f, bisected to the background; also zh-4adfcce2 0 → 99.4, zh-5dc5ce34 19.5 → 95.9; and YaHei's "‧" U+2027 is 0.2407 em), zh-045c5a75 24.9 (38 pages against Word's 37) [Mac 0fcba326: 58.7, 37/37 — a continuation no taller than the foot when its text fits, and the invisible wrapper keeps its cell margins/spacing; left: zh-TW cell punctuation squeeze, released; Windows 01QbbApP 2026-10-22, labs ~/starling-doc-check/lab/sq on Word for Windows, released: the squeeze is not it. Lab s: 28 full-width characters with k "、" before a final "。", over by 1-12pt: the final "。" alone never gives, one "、" gives up to 6.5 (fits at 6pt over, not 7), two or more cover 12; ours = Word in every case. Lab s2: the exact sentence "…縣 (市) 主管機關申請生活扶助。" in body text fits from 380pt in both. What differs is the cell: our column 3 text starts 2.56pt left of Word's (135.68 / 138.24) and reaches about 2.3 further right, so ours holds the line Word wraps. Lab t (this table: 85% pct, centred, 15-twip cell spacing and margins, auto cells, grid 1375/146/7571): Word autofits it, a one-row copy shrinking column 1 till "第10條" breaks per character, where ours keeps the grid (our _autofit skips cell-spaced tables, and keeps a grid nothing overflows). Fixed, Word draws the spaced table ~2pt wider each side; our column 3 text 1.4pt right of Word's. Next is Word's autofit of auto tables, sharing widths by content (dr2/g's G1 too), not a squeeze rule. Aside, lab s2 c: with full-width "（市）" Word fits from 371pt, ours from 377: Word squeezes "（" "）" as well (lenovo-3 fixed it: 45d8d302). Lab sp (Windows 01QbbApP, Word for Windows, fixed tables, grids not Word's own): before mode 15 a pct table's share is of the column plus its side outdents (85% of 534.85 with 0.75pt margins = 455.98; with 15-twip spacing ~458.9), in mode 15 of the column. Applied to every pct table it cost 6 documents (zh-f5a71d87 100 -> 18.9: a fixed 100% table whose grid is Word's own fit) and was dropped: a Word-saved grid already holds it. Only a grid that disagrees with its share would need it],
zh-015abfaf 62.4 (15 against 16) [Mac 0fcba326 looked, released: pages 1-9 match; from p10 its lines "NN.名称<tab>16 spaces（某某区）" (16pt on a linesAndChars grid of -1032, mode 14, zh-CN, the middle spaces hint eastAsia) keep "区）" in ours, the line exactly full after the fit (448.84 -> 440.94 of 440.95), where Word sends "区）" down and spreads the rest; three such lines a page. Not the hang: limiting "）" to half an em on a grid changed nothing here and cost zh-eb54d3b0 98.5 -> 91.8, Word hanging a whole "】" there. Look at what gives the 7.9pt — the spaces or "（"], zh-77bd4900 68.5 (58 pages; Linux 017F2GnT: 96.4 after macos-ios's b06bb67b, 97.4 after fccea2b0 — a page's part of a table closes with the table's bottom line where that is heavier; left a few lines on pp14-16 and 20-21; released), zh-8f70b676 88.2 (Linux 017F2GnT, 2026-10-22: 98.0 under PyMuPDF on the tip — 50 of 51 lines; the one missed is a narrow cell's "17:00-18:30" wrapped "…18:" / "30" in Word's print, ours a line less; the rest of the Mac's 88.2 is likely PDFKit's grouping; released).

### Note from the Mac (2026-10-22): the zh corpus is 486 documents — a twenty-second sample
Twenty more (`random.seed(20261105)` among the 160 unprinted, 15 to 400 KB, drawn by
docxcorp id, all printed), checked in. It starts at 84.7% (median 98.9). Its low ones,
unclaimed: zh-2b21a9d4 32.8 (DONE Mac 01Xgpbk5 → 100: a page-anchored table whose row opens with a page break stands on the page the break opens, not over the page before), zh-20d0e98f 37.2 (DONE Mac 01Xgpbk5 → 98.6, 13/13 pages: a line may part after "%" before an opening mark — "…）×100%" / "【107年："), zh-b58b4f0c 37.8 (T145, Linux office1 01Ak4ibJ: 99.8 now — a number that fits parts after its hyphen; released),
zh-4feaa34c 41.3 (11/10 pages; Mac 01Xgpbk5 looked, released: the drifting fallback again — Word sets every 楷体_GB2312 run in Arial Unicode MS, the bold header's at 12.24pt a character, so "序号" (24.5pt) wraps in its 24.45pt cell, and the taller header row repeats on every page; a reprint today agrees, and zh-78729cf9 reprinted alongside is Arial Unicode too where its 10-17 reference is YaHei; nothing to model), zh-f2ca3070 65.2 (37 pages; DONE Linux 017F2GnT 2026-10-22, fd6955c4 → 98.5: a right-set list number ("i." lvlJc right) ends where its line starts, its tab going on from there), zh-74b34f3b 92.6 (Mac 01Xgpbk5 looked, released: every miss is p6's vertical "東引鄉活動中心2樓" cell, its glyphs within 4pt of Word's; PDFKit groups ours as one line, Word's as one per character).

### Note from the Mac (2026-10-19): the zh corpus is 466 documents — a twenty-first sample
Twenty more (`random.seed(20261104)` among the 180 unprinted, 15 to 400 KB, all
printed), checked in. It starts at 71.5% (median 91.4). Its low ones, unclaimed:
zh-d97c5474 2.2 (Mac 01Xgpbk5 looked, released: zh-8d72961c's kind — a Greek/Italian/… notice in Nunito Sans, Word for Mac's cloud font (embedded in its print, lines 16.3pt apart at 12pt), which we lack (Carlito, 14.6)), zh-9932bd83 20.0 (99/96 pages; Linux 017F2GnT: the same book as zh-499adba6, word for word — its text, 14 tables and 11 footnotes; it goes with zh-499adba6, whose next is p17's line end, handed to lenovo-3; released), zh-0513f641 31.6 (T136, Linux office1 01Ak4ibJ: 42.4 now — its body style's East Asian language is x-none, so no mark gives (lab c0513, Mac); zh-499adba6's p17 was T135, a mark before a tab; released; Linux 017F2GnT measured, handed to lenovo-3: T131's family again, mid-line — zh-TW 標楷體 14pt, mode 14, compressPunctuation, jc both, numbered (ind 1134/567): p5's "(一)<tab>對地方政府之撥付：本計畫主要補助項目為人事費及基本" ends at "本" in Word's print with "：" its full em (261.5 -> 275.8, every character 14.35 apart, the line stretched), where ours squeezes "：" to 8.3 and takes "維"; every page from p2 is off by such lines, 22/23; released; 22/23
pages), zh-01bbcd4d 33.2 (T139, Linux office1 01Ak4ibJ: 86.6 now — a spaced ideograph is over the margin by its em and half its spacing; Mac 01Xgpbk5: font table's repeated 方正仿宋简体 fixed — its East Asian entry wins; released the rest to the fitter: p2 line 1, compressPunctuation, Word squeezes "范（" to 8.6 and "）》" to 8.5 and takes 28 characters with "理。" — ours squeezes only the pair and sends "理。" down, which cascades; sent to lenovo-3), zh-db07d44e 33.8 (70 pages; back at 41.6 after Windows' d24260ae (an equation alone in a cell asks no width); it had REGRESSED 41.6 -> 16.7, 78 pages, by 3a40f13d (Linux 017F2GnT, 2026-10-22: reverting that commit alone restores 41.6 and 70 pages; its cells hold no pictures, but three Office Math equations, set as inline objects — p22's unwrapped display formula, ~400pt, now widens its column; reported to Windows 01QbbApP); Linux 017F2GnT: 36.8 after 0241bf96 — a merged cell that states no top takes the table's line, pp3-7 Word's now. Left, released: (a) p22's display equation, five fractions in a delimiter ("實績值=(實際取得籌設許可量/預計取得籌設許可量×1/3+…)×100%"), which Word breaks at its "+"s over four rows ~135pt tall and ours sets on one row, ~25pt, over the cell's edge — WriterMath has no line breaking; pages realign after it, so worth a line or two a page there; (b) the fitter, handed to lenovo-3: mode 15, zh-TW, compressPunctuation, 標楷體 12pt, jc both, p30's cell line "範圍內每增(減)10%，加(減)1 分。" (cell 3545 twips) is one line in Word's print with "，" and "。" 9pt each (0.75 em), the ideographs 12 apart; ours keeps both at 12 and sends "分。" on — many of its cells' lines are the same), zh-b378d8c4 36.7 (DONE Linux 017F2GnT 2026-10-22, e007b15b → 100: a parted row's part over the page keeps its cells' margins on top of its stated height — p13's foot is 专栏5's row, at least 132.05 with 15-twip margins, parted over pp12-13 — its part on p13 is 134.4 in Word's print, 133.0 in ours; Windows 01QbbApP: the leading spaces held, x as Word's, no score moved — its misses are p13's foot, a 22pt exact line ending 0.4pt past the 1985 margin that ours keeps and Word sends on; released; Mac 01Xgpbk5 → 39.1: no break at an em dash between digits; released the rest, measured: paragraphs opening with four Times spaces ("    1.城市内涝…") — Word keeps them, 7pt each, from the margin on every line; ours widens them by letter spacing, so a left-aligned line starts 1.8pt in (the engine moves a line by half its first character's spacing) and a JUSTIFIED one collapses them to one space at -5.2pt, the line taking characters Word does not. Engine-level; likely in other documents too),
zh-e2dc2598 53.6 (Linux 017F2GnT, 2026-10-19: 100.0 on the tip without a change of mine — fixed by a landing since; its footer's extra "X" in ours is FAFAFA, near-white; released. Mac 01Xgpbk5 measured: it cascades from p8, where Word keeps "第四章 丧事活动…" (atLeast 28.5 on a 15.6 grid: 31.2, overhang 5.2) at the foot and ours misses by 0.2pt — our footer stands 0.5pt taller ("-8-" at 731.0 to Word's 731.5, "隆阳区人民政府发布" 768.3 to 768.8). Its footer: a "- PAGE -" box paragraph, then two header-style paragraphs with pBdr none (space 1/4) and first lines indented past the margin (lab `ind`), the second empty; one of those is 0.5 taller in ours), zh-9ba2ead7 73.0 (DONE Mac 011uWpmC → 91.3: a numbered item whose level and paragraph state no indents sets its number at the paragraph's left, the text straight after it), zh-e49d7943 78.4 (Linux 017F2GnT, 2026-10-22, p16 measured, not built: the calendar (autofit, tblW auto, cells tcW auto, grid 736/1351/1205/1271…) heads with "星期二" at 16pt 標楷體 (YaHei to Word, 16.0 an em) in its 1205-twip (60.25pt) column; 48pt of text and the default 5.4pt margins fit, yet Word's print wraps it "星期" / "二" and its header row stands 8.6pt taller, every row under it lower; the columns stand where the grid puts them in both prints (星期二 centred at 185.4 in Word's, 185.8 in ours) — answered by Word's own print, no lab: its column edges (49.9/87.1/156.2/214.1/277.0/339.8/402.7/474.7/542.6) make 星期二's column 57.9, not the grid's 60.25 — an all-auto table (tblW auto, every tcW auto) Word redistributes by its content, the total the grid's 492.7 (37.2/69.1/57.9/62.9/62.8/62.9/72.0/67.9 for the grid's 36.8/67.55/60.25/63.55×3/70.0/67.45); ours keeps the grid where no cell overflows. Autofit — for Windows 01QbbApP's T143i line; the "附件3" box is drawn since ff44e692; released. Earlier: 82.4 after 87946e40 — the picture after the "…演習編組表" title keeps to the grid, 666 not 660.7, and with lab `e49`'s footer (Windows: the 17.15 YaHei footer raises the foot to 782.35) the 演習日程規劃表 title row goes to p16 as in Word's print; the "附件2" box is drawn since someone else's landing; released; Windows 01QbbApP lab `e49` (~/starling-doc-check/lab/e49, Word for Windows, which prints p15/p16 as the reference): it is the footer. Deleting X's line shape, the 附件3 box, or the table's rows after the title changes nothing; deleting X, or X exact 34pt and less, keeps the title on p15, X exact 35 sends it to p16. The title row stands 756.82-781.54 at X=34 (24.72: its 2.16 top rule, exact 22 line, 0.48 rule under) — so the foot is between 781.54 and 782.54, not the margin's 785.3: the footer, 850 twips up (bottom 799.4), is one 10pt 標楷體 line in style footer (snapToGrid 0) — YaHei's 1.715 em, 17.15 — so its top at 782.25 takes the body's foot up 3.05pt; Mac 01Xgpbk5 looked, released: scattered — p14's "附件2" label is a wps text box (wrapNone, 30.65pt above its paragraph) anchored in the title paragraph "105年全民防衛…演習編組表", which also holds a 431x660pt inline picture and so parts across pages; Word draws the box above the title, ours draws it nowhere. Also p16/p20's tables (calendar, county columns) and p18's lines, not looked at), zh-5be7e156 89.1 (Mac 01Xgpbk5 measured, released: p1's justified lines, Normal with w:spacing -6 under balanceSingleByteDoubleByteWidth + compressPunctuation — Word's automatic space after "〔2021〕46" before "号" is ~7.6pt, ours 3.4, and ours takes a character more a line. Lab `asp` (~/starling-word-check/lab/asp, the file with Normal's spacing varied): the step from "6" to "号" is 14.65 at -12, 15.25 at -6 — each exactly the line's ideograph pitch, as if digit and gap fill one cell — and 12.75 at 0 (pitch 15.79); +6 moved the break. The lines are justified, so the gap is not isolated: a lab on an unjustified line would settle it).

### Note from the Mac (2026-10-19): the zh corpus is 446 documents — a twentieth sample
Twenty more (`random.seed(20261103)` among the 200 unprinted, 15 to 400 KB, all
printed), checked in. It starts at 74.1% (median 95.5). Its low ones, unclaimed:
zh-202582e2 8.6 (15/14 pages; DONE Mac 01Xgpbk5 → 97.8: FangSong_GB2312 by its English name is YaHei to Word on a Mac, an ASCII FZXiaoBiaoSong SimSun, and curly quotes in an East Asian face an em without useFELayout), zh-344a8d08 19.8 (Linux 017F2GnT, 2026-10-22: 26.5 after 0be8be8f — a raised mark's line is its neighbour's, and its foot the line's whole grid pitches, so note 3 parts on p4 as in Word's print (with lenovo-3's T144). (2026-10-22: 27.8 with T145, whose hyphen rule fixes p4's "COVID-" line; DONE 2026-10-23, 99.8 (5c8d7006 + 1a8fc19a: a grid line's overhang no longer reaches into the notes — that was the 13th line). Was: p5's foot keeps a 13th body line, "案，並於110年10月14日…", that Word sends to p6 — p5's notes (note 3's carried line and note 4, 3 lines, under the continuation rule) should leave room for 12; a reservation log shows 97.6pt reserved, 12 lines' room, but it mixes the layout's passes and the final page keeps 13 — not found.) Earlier: p4's last line "…嗣因國內COVID-" (16pt, linesAndChars, balanceSingleByteDoubleByteWidth) — Word fits "COVID-" and breaks before "19", ours is a hair too full and takes "COVID-19" down; the hyphen break itself exists (3ab630b1). Earlier: 25.9 after f9000d0e — a note parts under its mark, a paragraph going on over a page takes there only the notes it marks there; our separator (27.44) and note lines (17.15) now measure as lab T's. What is left on pp4-5 is a fitter line, handed to lenovo-3: footnote 2, "「嚴重特殊傳染性肺炎(COVID-19)第二級疫情警戒標準及防疫措施裁罰規定」之相關規定。" (zh-TW, 標楷體 10pt, mode 14, compressPunctuation, ind hanging 220), is one line in Word's print, "定" in and "。" hung to 516.0 over a 512.1 margin; ours sends "定。" to a second line, the notes a line taller and the page a body line shorter; released; footnote labs, Windows 01QbbApP, ~/starling-doc-check/lab/fn: its package, Word for Windows — which sets 標楷體 in YaHei, so heights are YaHei's. (1) The separator's rule stands 12.2-12.5pt above the first note line's top whatever the grid and the note's length (F1/F3 with the footnote style's snapToGrid 0; F1g/F3g without), and its paragraph is no grid pitch: ~29pt from the body's last line to the first note's top (one 16pt line, not 22.85 or 45.7). Notes under snapToGrid 0 are their face's line (17.16 at 10pt YaHei); without it they take whole 22.85 pitches. (2) Word keeps ONE note line under its mark: P13, the mark in the last (only) line of the page's last paragraph, sets line 1 of a 3-line note on p1 and lines 2-3 on p2 under a continuation rule, the rule 25.1 over the first baseline on both pages); the separator's own height, lab `T` (Windows 01QbbApP, same package, footer off): 14 body lines exact 40pt then the marked paragraph exact H, the largest H kept on its page with its note bisected — 108.89 - H is the separator: Normal 10pt 16.9-18.9, 16pt 26.9-28.9, 22pt 36.9-38.9, with the docGrid and without alike — one single-spaced line of Normal's face off the grid (YaHei's 1.715 em here: 17.15, 27.44, 37.73), its rule 0.55 of that line down from its top, zh-12f87285 27.4 (T134, Linux office1 01Ak4ibJ: 100 now — a row parted at the foot keeps room for its cell's bottom margin; released), zh-291fcea7
30.9 (Windows 01QbbApP, lab `sr`: a parted row's top rule on the next page now on the page's head line (zh-f43c9edf 71 -> 100 with it); zh-291fcea7 stays 31.4 — in its package our cell text stands 0.65pt lower under each row's top line than Word's (labs T1/T2, ~/starling-doc-check/lab/sr), which is what ends its p3 table 0.85 low; released. Tried: PMingLiU's own baseline (0.8008 + half the line's 0.3, 0.951 em) moves glyphs only, not rows — zh-291fcea7 unchanged, zh-06c46ba9 -0.4 (its "※" cell lines, 新細明體 marks in 標楷體 text, 5pt higher), three +0.2-0.7, net +0.002 over 466: not landed; Mac 01Xgpbk5 measured, released: all of it cascades from page 3, where 28 empty 12pt 標楷體 paragraphs (YaHei, two 18pt pitches each) end a table — Word fits 14 on p3, ours 13, the 14th 0.35pt short at the foot (the footer pushes the foot 4.4pt in both; its overhang is the East Asian 7.7). The 0.35 is the table: a row split from p2 resumes on p3 with its top line at 56.64 in Word, 57.45 ours, the continuation 28.56 tall in Word, 28.12 ours, the table ending 0.9pt lower; a lab on split-row continuations at a page top would settle it), zh-b3e887f7 47.2 (DONE Mac 01Xgpbk5 → 54.7: a time range wider than its cell parts after its hyphen, and autofit counts it so; released the rest: Word widens its 46.8pt time columns to 47.1 for "11:30-" (36.2pt in 36.0), 0.2 over, inside our autofit tolerance of a point (bug57031 needs it), so our "11:30-13:00" cells drop the hyphen to a line of its own), zh-9f24d3eb 53.8 (DONE Mac 01Xgpbk5 → 100: a paragraph whose mark is hidden — a style separator — runs on into the next), zh-447f1d5c 61.8 (98 pages; DONE Mac 01Xgpbk5 → 98.4: w:doNotUseIndentAsNumberingTabStop — a label's tab goes to the first of the next default stop and the hanging indent),
zh-f43c9edf 70.8 (DONE Mac 01Xgpbk5 → 100: spaces before a mark no line may start with are no break — "提取    %" parts before 取), zh-5c7787f5 79.5 (Mac 01Xgpbk5 measured, released: reader, not layout — every row matches Word to 0.7pt, but its numbers are drawn in our 仿宋 stand-in Liberation Mono at 8.7pt where Word draws FangSong 10.6, and PDFKit groups Word's "31" with the name cell's first line and not ours), zh-e4ef4c4d 93.3 (Mac 01Xgpbk5 measured, released: p5's borderless two-column table holds a picture anchored in each cell (wrapTight, layoutInCell); the right one, 184pt in a ~216pt cell, leaves no room beside it, and Word sets its paragraph's text below it — ours draws the picture in Word's place but sets the text over it. Needs text wrapping round a picture floating in a cell; Windows 01QbbApP 2026-10-22: DONE -> 100, a cell paragraph goes under a wrapped picture of its that leaves it no room (lab wc: exact lines step down whole lines). Then, no score: a wrapped picture anchored above its cell stands at the cell's top, as Word's p4/p5 have it (wrapNone ones not: zh-e49d7943's 附件5). (A sampling note: the
corpus names a document by its docxcorp id, the cache's file name — not by a
hash of its bytes, which differs; a draw that excludes by content hash picks
documents already in the corpus.)

### Note from the Mac (2026-10-19): the zh corpus is 426 documents — a nineteenth sample
Twenty more (`random.seed(20261102)`, all printed), checked in. It starts
at 83.0% (median 98.1). Its low ones, unclaimed: zh-3fe252ff 15.0 (94/95
pages; Linux 017F2GnT, DONE 2026-10-19, 0eb88e8b: its Wingdings "Ø" bullets were measured at the "➢" stand-in's width and the text face's scaled size, so the text went to the 63pt stop, not 42; now 98.6 on Linux, 94 pages), zh-7b125a21 21.3 (105 pages; DONE Mac 01Xgpbk5 → 85.3: a grid line may reach a twip past its overhang. The rest is its CESI宋体-GB13000 body, which Word sets in SimSun at 13.611pt lines for 10.5pt, not 1.3 em (13.65); the only corpus document with that face, left), zh-289155d6 46.1 (DONE Mac 01Xgpbk5 → 99.7: lab `ef` — Word's foot test is ≤ in binary float, so exact lines of whole quarter points may end on the foot; `pf`'s 20.85pt cannot), zh-0b48a0db 50.7 (DONE Mac 01Xgpbk5 → 99.3: a cell paragraph of no style takes Normal's own pPr over the table style's),
zh-e9616b2b 63.1 (6/10 pages; DONE Mac 011uWpmC → 93.8, 6/6: an invisible one-column wrapper round tables is read as the body, kept for the save; earlier, Mac 01Xgpbk5 measured, released: the whole document is in a 1-column, 2-row table with no visible borders (tblBorders insideV only), its three tables nested in the cell; pp1-4 match Word's, then the nested 35-row checklist (exact 17pt rows, can't split) is flattened as nested tables are (Docx.swift ~943) and runs four pages where Word's fits one. Reading such an invisible one-column wrapper as body would fix it but loses the wrapper on save; the real fix is laying out nested tables), zh-147bdae0 89.3 (DONE Mac 01Xgpbk5 → 90.7: in a table of separated borders the row above's bottom line is not taken again in the cell under it; the rest is repeated header rows ~1.2pt high and the reader grouping their centred cells),
zh-9bcea239 93.2 (DONE Mac 01Xgpbk5 → 95.1: VML fit-to-text boxes are sized once too, and a fitted box's paragraph with an East Asian face stays whole only by halving its spaces — lab `vf`, office.md; the rest is page 11's scoring table).

### Note from the Mac (2026-10-19): the zh corpus is 406 documents — an eighteenth sample
Twenty more (`random.seed(20261101)`, all printed), checked in. It starts
at 90.0% (median 98.1). Its low ones, unclaimed: zh-884c6e3e 47.2 [RELEASED by Linux office1 01Ak4ibJ (lenovo-3) 2026-10-23, rule not found: labs zz–zz5 (Mac, Windows agrees) put Word's limit for "征" after "被" (16pt, mode 14, zh-CN, two marks) at 7.30 taken / 7.35 refused, whatever the line's length, the leading "2.", the first-line indent or the doNotWrapTextWithPunct / doNotUseEastAsianBreakRules switches; ours, half the character before, takes it to 8. Not a flat 0.455 em: zh-6cd1befe (mode 14, zh-CN, 16pt spaced -0.5) takes 7.5 over in Word. Not a per-mark cap (≈3.65): zz's three-mark line ("２．") stops at 7.3 too, unless "．" gives nothing there; Mac 0fcba326 measured, released to the fitter (lenovo-3 asked): first miss p2, "2.商业用房临时安置费标准。选择期房产权调换的，按被|征" (mode 14, compressPunctuation, zh-CN, 16pt justified): labs `zz`/`zz2` (Word 16 Mac, this package, right indents) — Word takes "征" up to 7.30pt over with 。 and ， giving ~3.7 each, refuses from 7.35; ours takes it to 8 (legacy need/count ≤ width−x, 10.67 with two marks, which fit lab `mh`). Files ~/starling-word-check/lab/zz] (5
pages; Mac 01Xgpbk5 measured, released to lenovo-3; Linux office1 01Ak4ibJ looked 2026-10-19, released: Word's print draws every 楷体_GB2312 run in Arial Unicode MS, the drifting fallback, and the bold ones emboldened 0.32pt a character (step 16.645 against YaHei's 16.325 on the same justified line) — that is the natural width the line lacks in ours (12 bold characters, ~4pt). Converted with the runs renamed Arial Unicode MS, ours still takes "征", now ~7.5 over against half of "被" (8): within a point of the legacy rule's edge, on a face Word does not always take. Nothing to build; everything after p2 cascades from that line. Earlier: p2's "2.商业用房…按被" — ours squeezes "。" and "，" 2.1pt each to take "征", Word sends it on, though lab `lq3` in its own package takes the next ideograph up to half an em with "，，", "。，", and a leading "2." alike — so the line differs in its natural width somewhere, not the rule), zh-e74dd0a1 52.1 (134/132 pages; Linux 017F2GnT, DONE 2026-10-19, d5bbcc42: a break-only paragraph then one opening with its own break left Word's blank p63 out — the two breaks merged; now 99.4, 134 pages, lab `bb` from the Mac agrees),
zh-c9f4d690 62.8 (Mac 01Xgpbk5 measured, handed to lenovo-3: under wordWrap 0 a paragraph ending "…等部门。 " — the "。" hanging past the margin — puts its ONE closing space on a line of its own in Word's print; `_looseWordOffsets` wraps closing spaces only from two, so p14 on runs a line early), zh-cfb32050 73.7 (Mac 01Xgpbk5 measured, sent to lenovo-3: zh-TW 標楷體, mode 14, compressPunctuation — Word squeezes no mid-line "、" or "，" (all 16.4 apart on p3's "…得獎名"), ours squeezes both to 8.3 to take "額" and hang "。"; the T119 family, mid-line), zh-e64d4997 84.2 (Mac 01Xgpbk5 looked: zh-TW cell lines a character long in ours, "…歲出成" — likely the same squeeze as zh-cfb32050; released).

### Note from the Mac (2026-10-19): the zh corpus is 386 documents — a seventeenth sample
Twenty more (`random.seed(20261031)`, all printed), checked in. It starts
at 94.0% (median 98.4). Its low ones, unclaimed: zh-875759ff 30.8 (58
pages; Mac 01Xgpbk5 measured, released: Word's print sets its contents entries' 楷体_GB2312 in Arial Unicode MS — the drifting fallback, see the note below; zh-78729cf9 reprinted the same day now has 545 such characters where its 2026-10-16 print has none — so each 16pt entry is 0.6pt taller than ours in YaHei, and the pages slip from p2 on. Nothing to model while the fallback drifts), zh-8415d258 85.5 (Mac 01Xgpbk5, 98.2 now — a run of plain and no-break spaces is half an em from its first plain space on, lab `nb`; released), right-set; Word's print steps them 4.44 then 7.5pt each — half an em at 15pt — over two lines and a part, "水利部办公" / "厅"; ours sets them at the stand-in's 4.3, as `balancesSpaceWidth` takes plain spaces only and each plain one sits between two no-break ones. Widening every space of a mixed run took it to 92.4 but sank 17749c13, 903376c0, d0bfd38c (100 -> 5-8), c6ab068c and 621d8756 — zh-0aac9d1a has 26 such mixed runs Word keeps narrow — so the rule is narrower than that; a lab on runs that open a paragraph is next; the space-run hang to the paper's edge is not it, lab `sp` (ours = Word's)), zh-81aa310b 93.9 (Mac 01Xgpbk5 looked: glyphs at Word's; the reader groups its "人員審查意見" cells apart; released),
zh-77079ee8 94.5 (Mac 01Xgpbk5 looked: a turned cell and the reader; released), zh-6e7ff836 94.5 (979/1141 lines; Mac 01Xgpbk5 looked: table cells the reader groups apart, and p20 opens a block early; released).

### Note from the Mac (2026-10-18, late): the zh corpus is 366 documents — a sixteenth sample
Twenty more (`random.seed(20261030)`, all printed), checked in. It starts
at 87.4% (median 96.3). Its low ones, unclaimed: zh-a78d52e7 6.1 (26
pages; Mac 01Xgpbk5, 97.1 now — a page-anchored top-and-bottom float bands its page, and a VML box fitted to its text is its text's height; released), zh-6e653ca0 53.6 [DONE Mac 0fcba326 with Linux b2 → 100 (and zh-e2dc2598): the trailing-space joiner has height only where the spaces run past the line and wrap (zh-c5b5087b's), none where they fit; zh-ae79c618 88.4 → 99.2 with it] (Mac 01Xgpbk5 measured, released: our baselines are Word's to 0.9pt on every page; the loss is p8's "第四章" heading, whose 31.2pt grid line (at least 28.5, SimHei over a 仿宋 mark) ends at 722.2 in Word's print, 5.0pt past Word's body foot at 717.2 (the footer's top, read off its "- 8 -" box) and within the 5.2pt grid overhang SimHei's 20.8pt line leaves; ours, with a footer 0.5pt taller (75.6: an empty and a box-only paragraph each 1pt over their lines for style 9's "none" border spaces, and an 18.6pt bold 宋体 line, against Word's 75.1), is 5.5 over and sends it on. Lab `fz` (Mac, Word 16.113.3): style 9's none-border spaces are 1.92pt of Word's footer (ours 2.0) and the trailing spaces after "发布" change nothing; Word's bold 14pt 宋体 line is 18.2 (1.3 em) where ours is 18.6 with the 16pt "X" line above it (no strut: the paragraph is not uniform) — quieting the spaces did not move it, so it is the run's own face metrics under the engine; earlier look: p8's "第四章" heading fits at the foot in Word's print (695) and goes over in ours; our lines on p8 stand 2-3pt low of Word's from the page top though p3 is 1pt — the drift between, and the heading's line on the 15.6 grid, are where to look), zh-86547e97 54.3 (Windows 01QbbApP, 75.9 -> 99.5 there — over single spacing a bold run sets the line its regular text does; zh-d746674a 81.9 -> 91.9 with it; released; Mac 01Xgpbk5 looked, released: p1 "第一章　总　　则" (Normal (Web), 1.5 lines, snapToGrid 0, bold 楷体_GB2312 16pt) to "第一条" is 41pt in Word's print, 54 in ours; both lines are 1.5 × YaHei's 16pt and Word's body pitch is 41.2, so something adds 13 to our first line of "第一条" — a bold Strong-style run and a bold space start it),
zh-ae79c618 88.4 (Mac 01Xgpbk5 looked: one paragraph at p10's foot a line apart; released), zh-360c1df1 89.2 (Mac 01Xgpbk5 looked, released: lines at the fit's edge — p7's "2.自然资源…金山银山”" is 394.2pt natural against ~394.3 of room, and Word breaks before "山”", ours takes it; 12 runs of the kind), zh-ee9d81b3 89.6 (Mac 01Xgpbk5 looked: one run at p5's foot, 11pt; released).

### Note from the Mac (2026-10-18, late): the zh corpus is 346 documents — a fifteenth sample
Twenty more (`random.seed(20261029)`, all printed), checked in. It starts
at 82.4% (median 98.2). Its low ones, unclaimed: zh-e8d4c046 2.7 (1 page;
Mac 01Xgpbk5, 97.3 now — an embedded face taller than its em is measured
by its own hhea; released), zh-5450d509 15.5 (Mac 01Xgpbk5 looked,
released: its 1.5-spaced 12pt body is 仿宋_GB2312, embedded as a
FangSong_GB2312 of 7580 glyphs; Word's print draws all of it in SimSun,
one pitch a line ×1.5 = 23.4, where ours, falling back to YaHei for what
the subset lacks (as zh-92373179's print does), takes two pitches. The
same batch printed zh-e8d4c046 just before it, whose "仿宋_GB2312" embed is
really SimSun. REPRINTED after relaunching Word: the body is YaHei, as
ours, and ours scores 94.8 against it (and again YaHei after a print of
zh-e8d4c046, so it is not that file's face carried over by name). The
fresh print replaces the reference), zh-27a874b7 37.4 (Mac 01Xgpbk5 looked: p1 matches; p2 4pt and p3's chart labels (charts are lenovo-3's); released), zh-de073ee5
55.2 (Mac 01Xgpbk5, 100 now — a wide word measured at its face's advances; released), zh-c2229d4a 75.1 (Mac 01Xgpbk5 looked: Word's text layer drops most glyphs of its embedded subset — the reader; released), zh-785e46f8 88.2 (Linux 017F2GnT claimed 2026-10-18: curly quotes under hint "default" in the Times hAnsi, 7.1pt where ours set an em; Mac 01Xgpbk5 had built the same unclaimed and pushed it first, fff07cdb, 90.2 now — sorry; the rest is line ends the fitter fits a character short), zh-7fd860f9 89.6 (Linux 017F2GnT looked: table cells grouped apart by the reader).

### Note from the Mac (2026-10-18, late): Word for Mac's face for a missing 方正 name is not reproducible
Thirteen of the corpus's prints draw some 方正小标宋 runs in **Arial Unicode
MS** (line ~1.75 em, so an 18pt line takes three 15.6 pitches where YaHei
takes two): zh-01071d55, 30d86fcf, 4a90bb2f, 51af781b, 5dc5ce34 (table
headers only), 608e661b, 8186c98d, ab1ea005, c10532da, c25d08c5, c8eb6e92,
dc25c47e and f2835e26. Nothing in the file decides it — not the name, its
altName, panose, w:sig, w:family, the run's rFonts or the document's
language: zh-1563bd74 has the same fontTable entry and title run and its
checked-in print is YaHei. Reprinted on the Mac at ~12:00 (Word relaunched
at 11:48 after a wedge): zh-1563bd74's title is now Arial Unicode, and
**zh-1a3c7aa0 went from YaHei to Arial Unicode and from 90 pages to 92**;
zh-c599aaa1 and zh-4c4b1af8 printed as before. So for these documents the
reference print depends on Word's state when it was made. Don't model the
choice from the docx, and treat a miss on a 方正 title's line pitch with
suspicion until the print has been reproduced.

### Note from the Mac (2026-10-18, late): the zh corpus is 326 documents — a fourteenth sample
Twenty more (`random.seed(20261028)`, all printed), checked in. It starts
at 84.6% (median 98.3). Its low ones, unclaimed: zh-608e661b 7.3 (4/5
pages; Mac 01Xgpbk5 looked, released: its 18pt 方正小标宋_GBK title is in
Arial Unicode MS in Word's print, three 15.6 pitches a line where ours,
in YaHei, takes two — and see the note below: which face Word takes is
not the file's to say), zh-6043ad90 28.4 (8/9 pages; Mac 01Xgpbk5, 100 now — a break under a table takes its page unless the table left under a quarter line; released), zh-0243e7fc
58.4 (Mac 01Xgpbk5, 80.7 now — an exact row is its height and its bottom margin, lab `rh`; left: cells' reading order; released), zh-e1b09977 65.4 (Mac 01Xgpbk5 looked: its rows, two exact 17pt lines, are 34.5 in Word and 36.25 in ours — the 2.25pt left line its vMerge-continued first cells state takes room above and below in ours (7ca4dd65's rule, lenovo-3's), and none in Word; asked lenovo-3), zh-f10c8f34 74.4 (Linux 017F2GnT, back from lenovo-3 2026-10-18: its runs' `<w:bdr w:val="none"/>` doubled the automatic spaces under balanceSBDB, 4pt where Word sets 2 — 100 now (d5d5856c), released; earlier, handed to lenovo-3 for T119: p1's "…布局合理、" (mode 14, 8pt, compressPunctuation) — Word takes "理、", ours 4.7 over past the hang with 9 marks giving 40 and refuses it by the half-a-character rule (4); every line after runs a character behind), zh-65e6c317 77.0 (Mac 01Xgpbk5, 84.0 now — a turned merge is centred down to the foot through a row that parts there; left: Word's text layer has ︵︶ for its turned brackets; released), zh-d0a207ac
95.0.

### Note from the Mac (2026-10-18, night): the zh corpus is 306 documents — a thirteenth sample
Twenty more (`random.seed(20261027)`, all printed), checked in. It starts
at 84.0% (median 95.3). Its low ones, unclaimed: zh-ab1ea005 9.2 (68/67
pages; Mac 01Xgpbk5, 12.0 now — its dots drawn in reading order (e2270403,
zh-cd8987db 87.2 -> 89.9 too); the rest is the fitter's, handed to lenovo-3:
a right-stop tab whose unsqueezed start is before its stop stays on its
line and what follows overflows the margin unsqueezed ("…？20" to 523.5,
4.3pt past), one whose start is past the stop breaks before itself and the
line before it is fitted as a line end; the whole contents runs a line
behind from entry 54, and the body a page), zh-499adba6 9.5 (96/99 pages;
Mac 01Xgpbk5 looked, handed to lenovo-3: mode 14, compressPunctuation —
Word takes "…同時訂定1976年至1985" on a 415.3pt line, 16.2pt over, about 4pt
off each of its four marks; ours sends "1985" on; its page count, 96 for Word's 99: Linux 017F2GnT f05a09f2, a row's footnotes go with the part of the row that marks them (the book is a one-column table, a chapter a row; notes 1-8 were reserved at p3, where the row began), 9.8 -> 20.1, pp1-16 Word's; next, p17's "（六）<tab>推動…部分負擔制度，" (mode 14, compressPunctuation, 標楷體 12pt, jc both, hanging 958): ours squeezes to keep "度，" on the line, Word sends it on — the fitter's, handed to lenovo-3 (starling-office1-df); released), zh-5251dd23
67.4 (Mac 01Xgpbk5, 89.2 now — a table side its own tblBorders leave out
keeps its style's width (aa548444): Table Grid's 0.5pt insideH under a
2.25pt frame; released; Mac 011uWpmC looked, released: what is left is p17 and p19's calendar, rows of trHeight 687 (atLeast 34.35) holding one or two exact 17pt lines (line 340, 14pt), no cell margins — Word's rows step 37.4-37.7, ours 39.1, so the table drifts 1.5pt a row and p17 misses 28 of 39 lines; both are over the 34-34.85 the XML gives, so it needs a lab of one such row; Mac 011uWpmC, 96.8 now — lab `cal`: a cell's 2.25pt side line is no room over or under its row in Word (34.8 a row, ours 36.6), and zh-cec9d337's rows that rule once explained were its 22pt "○" lines held to an em after the grid snapped them (lab `g44`: Word two 18pt pitches); zh-cec9d337 84.2 → 88.2, zh-e1b09977 65.4 → 81.4, zh-20c1d74a 88.0 → 89.9, none down; released), zh-5d635acc 76.6 (Mac 01Xgpbk5, 100 now — firstLineChars counted from the first run with text, not a drawing's anchor (b4380e86); released), zh-60173bb6 77.4 (16/15 pages;
Linux 017F2GnT: 97.5 now, Word's 15 pages — text set under a parted page-placed table stays on its page (dbc3d86f); released; Mac 01Xgpbk5 looked, released: "附件1"'s table is placed on the page
(tblpY 4970) above its own title paragraphs; Word sets its first row on
p12 at 252, the title at p12's foot (626-685) below it, and the rest of the
rows on p13; ours takes the title to p13 and the table to p14), zh-0978dee9 90.2 (Linux 017F2GnT, 2026-10-19: 97.2, 322 pages as Word's — 4adc64df (an empty line keeps its paragraph's strut: 仿宋 cells with digits stood 13.86 a line) and f77c9186 (a row taller than its page sets its long centred cells from the top); what is left is 3-9 lines on a score of pages, and p297 (21 of 57) and p311-p321 (7-28 a page), released. Earlier, measured 2026-10-18, released: its drift starts at p155's row 41, a 147.2pt cell (3160 twips less 108 a side, no grid) whose line "《中华人民共和国河道管理条例》（2018" is 120 + 8 + four Courier New digits at 8pt (1229/2048 em, 4.80078) = 147.203 — 0.003 over, and Word wraps "（2018"; ours keeps it within the fitter's 0.005pt hair and the engine's glyph positions. An exact Courier table for the mono stand-in changes nothing; the fitter's hair down to 0.002pt does it, 90083467 — zh-1b82f5d7 98 -> 100, zh-785d6dff 97.5 -> 99.5 with it; the rest of its drift is later rows)
(323/322 pages; Mac 01Xgpbk5 looked: a 323-page table whose cells stand 1-2pt off Word's, the scorer grouping them apart; released), zh-ad1e59ac 90.5 (Mac 01Xgpbk5 looked: its misses are the reader's order within table cells, glyphs where Word's are; released), zh-38758b14 91.0 (23/22 pages; Mac 01Xgpbk5, 100 now — empty paragraphs after a floating table go beside it on its last page (b4380e86), zh-10eab555 75.6 -> 99.7 with it; released).

### Note from the Mac (2026-10-18, evening): the zh corpus is 286 documents — a twelfth sample
Twenty more (`random.seed(20261026)`, all printed), checked in. It starts
at 88.0% (median 97.9). Its low ones, unclaimed: zh-9db183d5 6.6 (12/11 pages; Mac 01Xgpbk5, 95.0 now, Word's 11 — a frame placed on the page stands there past the foot; released), zh-8186c98d 17.1 (Mac 01Xgpbk5, 100 now — an at-least line on the grid keeps the grid's overhang; released; Linux: 100 on Linux too at the current head (an earlier Linux 17.2 was a stale sweep; a mono-stand-in theory about it was wrong), zh-d746674a 81.1 (Mac 01Xgpbk5, looked, released: style L3 (標楷體 for ascii too, 14pt, 1.5 lines) — Word draws its "(一)" brackets in the YaHei it sets 標楷體 in, ours in Liberation Sans 14.4, and the line of two faces stands 11pt lower in ours (pp12-17, 7 runs); the Latin face for an East Asian ascii name),
zh-20c1d74a 86.5 (Mac 01Xgpbk5, looked, released: forms — p18's table rows a few points short of Word's (rules 433/457/480/504 to 436/460/483/507) and its last 14pt long, the note under it with it; p15-16 header labels in boxes and checkbox lists the reader interleaves; no single cause), zh-9e8c1a98 92.7 (Mac 01Xgpbk5, 100 now — a box fitted to its text keeps its paragraph's right indent; released).

### Note from the Mac (2026-10-18, later): the zh corpus is 266 documents — an eleventh sample
Twenty more (`random.seed(20261025)`, all printed), checked in. It starts
at 86.4% (median 98.0). Its low ones, unclaimed: zh-8d72961c 4.3 (1/2
pages; Mac 01Xgpbk5, looked, released: not Chinese — a Greek/Turkish/Arabic notice in "Nunito Sans Light", which Word for Mac has (a cloud font; NunitoSans-Light embedded in its print, a 1.36 em line, 16pt pitch at 11pt x 1.07) and we do not (14.4pt pitch, other breaks); page 2's Arabic is a picture's text in Word's print), zh-10eab555 5.0 (136/135 pages; Mac 01Xgpbk5, 75.6 now, Word's 135 pages — text after a table placed down the page flows round it; left: p100's org chart (VML boxes match Word's to the point) leaves the paragraph after it 104pt low, its anchored "北岙街道各行政村、单位" box with it, and pp100-110 run late; released), zh-f3802561 69.4 (Mac 011uWpmC, 99.8 now — a no-break space after an ordinary one is the space's half em; released), zh-7b5b3de2
84.5 (Mac 01Xgpbk5, looked, released: the tables lay out as Word's — the same column edges to 0.4pt, the same lines — and Word's text layer drops characters in them, "序号", "项目名称"'s 目名, "面积"'s 积), zh-2e7ef069 87.5 (Mac 01Xgpbk5, looked, released: its footer box (wrap none, spAutoFit, sized by "- 1 -", the dashes inside the PAGE \\* MERGEFORMAT result) prints "-10-" whole in Word, where ours wraps the closing dash on every two-digit page — sent to Mac 011uWpmC beside lab ftD — Mac 011uWpmC, 89.0 now: lab `ft` (the file's footer over 11 pages, and with the dashes typed round a plain PAGE) prints "- 10 -" whole either way, so a fitted box's paragraph with no East Asian character is one piece; the rest is form cells' "（签章）"/"年月日" a few points off).

### T133. Shapes anchored in a table cell (zh-291fcea7 p5's flowchart) — measured, released
Owner: Mac 011uWpmC (session starling-bd), from 2026-10-19
Documents: zh-291fcea7 (30.9; p5 holds 18 of 23 lines missed there).
Known: the flowchart is wps shapes (a hexagon, rounded boxes) anchored to paragraphs inside a one-column
table's cell, layoutInCell 1, positionH relativeFrom column, positionV paragraph. Word sets them side by side
across the cell (the hexagon's "1.人事人員審核教師" at x 242); ours drops the hexagon's text and stacks the
other boxes down the page at the cell's left.
Measured (Mac 011uWpmC, lab `cellfloat`: the flowchart table copied whole, and its first row alone): the
anchored shapes are fine — the hexagon's text stands at x 242 as Word's with the first row alone. Two things
are not: (1) the boxes "2.初任教師…", "2.教師取得較高學歷…", "2.代理教師敘薪" are floating tables NESTED in the cell
(tblpPr horzAnchor page, tblpX 585, vertAnchor text, tblpY 515), which Word places from the cell (text at 96,
not 29pt from the page) side by side; ours reads them as nested blocks in the flow and stacks them. Only
zh-291fcea7 (4) and zh-ad224275 (1) in the corpus have such tables. (2) With the whole table, the hexagon's
fill is drawn and its text is not; with its row alone both are. Released: (1) needs a nested table read as a
floating box (ImageFloat, x/y from tblpPr against the cell, the box growing to fit), (2) a paint-order look. (Later: the text is lost only when row 0 — the flowchart's one tall row, nested tables
and all — parts across pages; cut so that it fits one page, the hexagon's text is drawn. A float in a row that
parts is where to look.)

### Note from the Mac (011uWpmC, 2026-10-18): zh-0243e7fc's p11 floating form — done (98.9)

tblpXSpec center on the margin now centres the table, and its tblpY holds on the
page its first row moves to; see office.md. Also looked, released: zh-92373179
and zh-7b5b3de2, Word's text layer (embedded subsets) and not layout.

### Note from the Mac (2026-10-18, morning): the zh corpus is 246 documents — a tenth sample
Twenty more (`random.seed(20261024)`, all printed), checked in. It starts
at 87.0% (median 97.7). Its low ones, unclaimed: zh-18cb2079 20.0 (Mac 01Xgpbk5, 99.1 now — a linesAndChars grid without charSpace keeps whole cells; released), zh-6a4fc013 38.3 (26/29 pages; Mac 011uWpmC sweeping a Thai character class + Cordia's ASCII advances (2026-10-18); Linux 017F2GnT after it: Noto Sans Thai at 0.66 (8ba41688), Word's 614 lines on 26 pages on Linux, released; Mac 011uWpmC, measured, released: a Chinese–Thai Q&A, its Thai in runs of "TH Sarabun New" marked `<w:cs/>` (19,801 Thai characters). Word for Mac has no face of that name (its DFonts thsarabun.ttf is named only "TH SarabunPSK") and draws them, and the runs' digits, in Browallia New, embedded in the print and found nowhere on disk (a cloud font?). Browallia's widths are Cordia New's (DFonts cordia.ttc) to 0.5%: digits 0.3645 em, Thai 0.298 em on average over this text, and a 47-character line measures 255.9 against Word's 257.1. Ours falls back to Carlito for the digits (0.507) and Thonburi for the Thai (0.552, 1.8x), so every Thai line runs long: 693 lines on 29 pages to Word's 614 on 26. No Mac face is that narrow (Silom 0.391, Sathu 0.407). `otherAdvances` would set Cordia's spacing but would draw Thonburi's glyphs over each other. A fix needs the stand-in drawn narrower too: a Thai class in `classScales`, or a scale per face, set per platform against its Thai fallback. Built later the same day, Mac 011uWpmC: 54.2 now, Word's 614 lines on 26 pages — Cordia's ASCII table and a Thai class scale, 0.75 against Thonburi, 0.729 against Leelawadee UI; Linux's fallback unscaled — and released to lenovo-2 for per-character Thai advances on top), zh-c2f6d17a 54.9 (Mac 01Xgpbk5, looked, released: outside-aligned footer frames now alternate as Word's do; the rest is Word's text layer — its embedded faces drop glyphs ("累计过120" for "累计雨量超过120毫米") and garble headings ("1.4\"#") — not layout; Mac 011uWpmC: but p21-37 stood a line behind by layout — a paragraph that takes itself off the grid keeps its Latin on it, 318ae37e, 93.5 now),
zh-12c4f07a 78.5 (Mac 01Xgpbk5, measured, released: line ends again, legacy mode with compressPunctuation, but the other way — Word takes "委" with ours over 7.75 against one mark's 6.5 (its "前，" about 3.8pt shorter); sent to lenovo-3 beside the three cases where Word takes less), zh-7773163d 83.4 (Mac 01Xgpbk5, 87.5 now — footer boxes placed from the page, PAGE results in the code's look; left: scattered line ends and 4pt offsets in a PDF-converted file of a section a page, and a second number box at x 488 on pp3-4; released), zh-cd8987db 86.6 (Mac 01Xgpbk5, 87.2 now — the cover's drop-down form field shows its entry; left: TOC lines, which match in place but are read out of order — ours paints the leader after the whole line, so PDFKit sees the page number before the dots; released).

### Note from the Mac (2026-10-18, night): the zh corpus is 226 documents — a ninth sample
Twenty more (`random.seed(20261023)`, all printed), checked in. It starts
at 85.3% (median 96.1). Its low ones, unclaimed: zh-8699644f 9.5 (Mac 01Xgpbk5, 94.6 now — paragraphs fill a text-anchored floating table's offset; released), zh-c25d08c5 55.3 (Mac 01Xgpbk5, 99.1 now — a style's rPr snapToGrid 0 keeps runs off the character grid; released), zh-15f60bac 64.6 (Linux 017F2GnT, 2026-10-19: 97.8 after 3ab630b1 — Word breaks after the hyphen of "CNS11643-2", which Unicode's rules keep with the digit; the reader part below is the rest. Mac 01Xgpbk5, measured, released: reader, not layout — table cells' baselines match Word's to 0.1pt, but PDFKit reads Word's "6" and "呂家華", 13.7pt apart in one row, as one line (Word draws them in one text run) and ours as two; Type3 boxes widened to the face's line (tried as a skia patch) move nothing under PDFKit and +1.0 under PyMuPDF, withdrawn), zh-60c80728 65.9
(35/37 pages; Mac 01Xgpbk5, 97.0 now, Word's 35 pages — a break's empty paragraph under a table, a 31680 left indent; released), zh-73534289 80.5 (Linux 017F2GnT measured 2026-10-18, released: p27's row 91 ("強化資金規劃運用能力 | 其它 | 提供資金協助…細部計畫。 | 協助中小企業…轉型發展", its first cell a vMerge continuation, the third a "Web" paragraph, no cantSplit) starts at 698.15 of 747.74 with 80.75pt of content; Word ends p27 after the row before (740pt, ~2 lines left — its text area ends where ours does, 766-773 on full pages, so not the footer frame) and moves the row whole, though it splits this table's rows on pp20-22 and 24-25. Which property keeps this row whole wants a lab (strip the vMerge, then the Web style); Mac 01Xgpbk5, measured, released: most misses are the reader's — the KPI table head as in zh-f2441f00, repeated squeezed text (T117); the one layout miss: p1's "（二）各機關中程歲出…" ("Normal (Web)", w:divId, widow control said nowhere) keeps one line at the foot in Word's print, ours none. Widow control off where unsaid (the format's rule) cost drawing 100->8.6, bug59058 99.9->50.4 and a dozen zh; off for divId paragraphs alone cost zh-f2441f00 97.9->82.6, zh-05315c2a 97.5->80.4 — both reverted; Word applies it there, so the trigger is elsewhere), zh-b24b396a 82.0 (91.3 now: Mac 011uWpmC 1a5cf392, an anchors-only paragraph whole to the next page; Windows 01QbbApP, the cover title's Chars indent at w:w and vert270 text boxes; left: p13's clipped "30" boxes and extra A/B/C labels; released), zh-51af781b 83.3 (Mac 011uWpmC, 83.6 now and Word's 65 pages — w:gridBefore read; left: the reference prints two landscape sections on portrait paper, clipped, and p57's "；" kept whole where ours squeezes it, 11pt of drift after; released; Mac 01Xgpbk5, looked, released: a print artefact — its landscape sections (pgSz 16850x11910, a hair over A4) come out of Word's print dialog on A4 PORTRAIT paper, text from x 0, and Word's 65 pages to ours 70 follow from that; p1-53 match but for reader repeats. Needs a reference printed on landscape paper before it measures anything)
(65/70 pages), zh-749cb15a 87.2 (Mac 01Xgpbk5, measured, released: line ends — legacy mode, compressPunctuation; ours squeezes ，、 to take "等，" (over 16.45 of 21.6) and takes "ECA" at over 17.15 of 7.2 room, Word neither; with zh-167ee06c and zh-30d86fcf the third legacy-mode case where Word squeezes less; sent to lenovo-3; Mac 011uWpmC, 90.2 now — a different miss: under overflowPunct off a paragraph's last mark gives its half (p49, p74, p83 runs); released).

### Note from the Mac (2026-10-18, night): exact lines' baseline is 0.80, not 13/16 — measured, not built
Word for Mac 16.113.3 (labs ~/starling-word-check/lab/tools/ex: 仿宋, 宋体,
Times at 12 and 16pt, exact 11-60pt) and Word for Windows 16 (windows'
labs: seven faces, 12-36pt, 15-60pt lines, modes 14 and 15) both set the
baseline 0.797-0.803 of an exact line down; `lineBox` says 13/16. Swapped
in alone (s108 -> s109) it gains zh-5ff074a9 +0.6 (a page's last line
fits), zh-8f7aa519 +0.4 and loses zh-454e2e29, zh-32f4ad9f -0.7,
zh-cec9d337 -0.4, POI 60316 -3.1 — line tops elsewhere tuned against
13/16 (60316's 36pt line follows an anchored group, so its top is not the
margin). Open: find the compensating tops, then take 0.8.
Also: the engine counted a run's baseline shift twice in its line
(starling-engine 7f57bb77e56, patches/skia-run-shift-once.patch, now
fixed); with that, w:position in auto lines (zh-f2835e26) is a patch in
waiting — f2835e26 +2.2 but zh-10e3a42be -1.4, zh-64044a1d -0.7: a line
raised whole needs the paragraph mark's depth (Word counts the unraised
mark) and Word's own pitch for whole-raised multi-line paragraphs.

### Note from the Mac (2026-10-18): zh-167ee06c (72.9) looked at, released
p2's "七、經同意…為必要" (legacy mode, compressPunctuation, bold JhengHei
UI Light 14pt): ours squeezes 、 and ， to take 要 (over 4.7 of 14), Word
leaves 要 alone on the next line, marks unsqueezed at 14.32. Its bold
title prints 421pt in a 415.3 column, so the emboldening is drawn, not
fitted; fake bold for JhengHei UI (1/48) wraps the title and drops the
file to 0.4 — don't. Sent to lenovo-2 as squeeze data.

### Note from the Mac (2026-10-18): the zh corpus is 206 documents — an eighth sample
Twenty more (`random.seed(20261022)`, all twenty printed), checked in.
It starts at 85.5% (median 98.0). Its low ones, unclaimed:
zh-10e3a42be 2.1 (28/31 pages; Mac 01Xgpbk5, 96.4 now — w:position raised text, line multiples under single shared above and below, a Latin altName set in 宋体; the TOC lines are the page-number artefact; released; Linux 017F2GnT: 99.8 on Linux now — a right stop after a line opening with negative spacing (a4088a88), and the gap was mostly the scorer: PyMuPDF read Word's raised text 10.5pt low, fixed dfd8f53d; left: p1's first raised line; released), zh-ff93733d 22.8 (Mac 011uWpmC, 96.2 now — a long word after an ideograph opens a line; released), zh-cec9d337 71.8 (Mac 011uWpmC, 84.1 now — Times' ○ keeps its line; left: p6's ˇ rows 8pt off, p19 4pt; released; Linux 017F2GnT built the Mac's lab `tr` (bfaa6a4a: a turned cell squeezes nothing, hangs its closing mark, starts 2.25 short of its ind; zh-f2835e26 72.8 -> 76.1, zh-cec9d337 83.9), released; earlier: p4's list tab fixed (aa9328a7, a number past its indent tabs to the paragraph's next stop); measured and released, p5's turned header cells (tbRlV, ind 113/113, trHeight 2768 atLeast, 12pt): Word sets "宜蘭縣（震災，內政部）" whole, every mark a full 12pt, 132pt down a 139pt row (rules 121.2/260.2), the column starting 3.9 under the top rule — centred, or 4.3 over its 127.7 shared at both ends; ours squeezes "（" and "，" 2.4 each to fit 127.1 and the row still grows to 140.6, so every row under it is 1.6-5pt low. Taking the indents out of the turned length (no squeeze, no growth) cost zh-cec9d337 0.3 — needs a lab on where the line starts and what length it wraps at),
zh-f2835e26 73.1 (Mac 01Xgpbk5, measured, released: p5's table head "评价指标" is raised 7.5pt by w:position in a single (auto) line, and Word makes the line that much taller — lab pos4 (~/starling-word-check/lab/tools): a line holding a run raised 10.5pt stands 10.56pt further from the line before, the raised text where an unraised one would be; ours sets the shift (d972fe9f) but keeps the line's height, the head row 52.2pt to Word's 62.9 and 33 lines after it miss. Tried: dropping the strut in both of `_layout`'s passes (the second, "tallest on every line", re-applies one) lets the engine count the shift, but a mixed line then grows 2× the raise where Word's grows 1× and a line raised whole stands r low — zh-f2835e26 74.2 -> 74.7, zh-64044a1d 98.3 -> 97.6; reverted. Word's rule from pos4: the line's ascent is the most of each run's ascent plus its raise, its descent the most of each's descent less it, the paragraph mark (unraised) counted. Mac 011uWpmC, 2026-10-18, tried and reverted: the raise as room above a one-line paragraph on a multiple never fires here — the head cell's paragraphs ("评" "价" … raised 7.5, w:spacing line 240 auto) read as a 21.95pt line, and by that rule an 11.5pt line raised 7.5 is ~19pt, under it; so the +10.7 Word gives the head row is not that rule alone), zh-f2441f00 73.5 (Mac 01Xgpbk5, measured, released: its 9-column 100% table of auto cells, outset 0.75 lines and no side margins is re-fitted by content in Word — columns 81.9/81.8/35.8/269.5/42.2 at p17, ours 81.4/81.3/35.6/268.1/44.5, the table 1.1pt further right — so the last column holds "ulture)使" in ours and not in Word, a row ends a line short and the next row's first line stays on p17; every page after misses from there. T1's open sharing question; the 。。。。 and 查查查查 misses are the reader's, not ours), zh-264d7516 [Mac 011uWpmC now on its turned merged cell] 93.6 (Mac 01Xgpbk5, measured, released: p19's turned merged cell "被征地农户人员信息" (tbRlV, vMerge) is drawn whole on the page its rows part from, off the foot — lab ~/starling-word-check/lab/tools/l264/s16; sent to Mac 011uWpmC beside a0fcb76c), zh-30d86fcf 94.7,
zh-5ff074a9 94.9.
Also: zh-f2441f00 (an HTML-style autofit table; Windows 01QbbApP, 2026-10-18: 75.2 -> 99.5 — autofit's narrowest piece parted where wordWrap off parts a word; released).

### Note from the Mac (2026-10-17, late): the zh corpus is 186 documents — a seventh sample
Eighteen more (`random.seed(20261021)`; two of the twenty Word would not
print), checked in. It starts at 89.9%. Its low ones, unclaimed:
zh-007ca091 35.4 (T109, 93.0 now, 11 pages), zh-0b87285b 77.9 (Mac 011uWpmC, 98.0 now — a page-placed table whole while it ends above the footer; released), zh-701eda18 (98.0 now, Mac 01Xgpbk5 — Word reserves a merged cell's stated part bottom above the next row; released. zh-c8eb6e92's rise to 97.5 in the same sweep is not from it. Earlier note, Mac 011uWpmC: p4's form tables (mode 14, compound thinThickSmallGap/thickThinSmallGap sz24 table borders, exact rows of 11pt exact lines, vAlign center) set every line 2-4pt off Word's — row 1's text 1.9pt low in ours (Word centres in the stated exact height with the top border in it; ours adds the border over it), rows 2-4 then ~3pt short; 40 of 47 lines miss by offset, not breaks)
83.0, zh-043aab43 84.4 (Mac 011uWpmC, measured, released: p3's justified cell lines (mode 14, PMingLiU 12, wordWrap 0, the run hinted eastAsia) — Word sets "÷ " in "（歲入成長率÷ 歲出" with the space ~6pt (half an em, PMingLiU's) less justification's 1.01, ours 2.9 (the Latin space), and takes one character more on the line; lab `hs` (Word 16, 2026-10-17): the hint does nothing — Word sets PMingLiU's own Latin widths (space 0.2598 em, "÷" 0.5908, from the mingliu.ttc Word carries), ours the serif stand-in at 0.94 (space 2.82 at 12pt for 3.12). Taking PMingLiU's whole ASCII table broke zh-190d730c 97.8 -> 43.4, zh-ec01ed87 99.1 -> 77.4, zh-073c9234 97.7 -> 81.4 and zh-340d52e9: those files' widths are the stand-in's in Word's print, so which of PMingLiU's widths Word uses is still open — reverted), zh-021b8feb 85.6 (18/19; Mac 011uWpmC, 98.6 now, Word's 18 pages — a break followed by floats alone is a break (lab ab, 4aef5f9d), a row with a turned cell parts (a0fcb76c); released), zh-8f7aa519 87.7 (97.4 now on the Windows box — others' fixes; nothing large left, released),
zh-c8eb6e92 91.2.

### T124. zh-4ea36aa8 p13-14: the automatic space beside PMingLiU digits — measured, released
Owner: none (Linux 017F2GnT measured it, 2026-10-18)
Documents: zh-4ea36aa8 (19 of its misses on p14).
A cell line (mode 15, doNotCompress, its run 新細明體 for every script,
East Asian zh-TW over en-US defaults) ends "…國小部32班（含" in Word's
print; ours leaves "（含" 9pt over. Word sets 1.5pt beside each digit
("部" to "1" 13.5, "2" to "班" 7.1 with digits 5.6), ours 3.0 (a quarter
of an em, `averageCharWidth` 0.5 for an East Asian face). Taking PMingLiU
at an eighth of an em fixed it and broke 30 other zh-TW files (zh-ca3ab35c
99.1 -> 49.3), so the eighth is this file's alone. Windows 01QbbApP's lab `as`
(Word for Windows 16, this package, 21 lines over faces 新細明體/宋体/微软雅黑,
languages zh-TW/zh-CN/none, doNotCompress or not, modes 14 and 15) sets
every automatic space a quarter em, 3.0pt; Windows' PMingLiU has
xAvgCharWidth 0.5. So the 1.5 is the Mac reference print's, not the
file's — leave it.

### T123. zh-cb56e605 (93.1%, 7 pages): a form's label cells a few points off — measured, released
Owner: none (Linux 017F2GnT measured it, 2026-10-18)
Documents: zh-cb56e605.
Nothing to fix that shows: p6's form looks the same in both prints. Its
misses are the second lines of label cells ("2022年是否获" / "得关税配额",
"种类、数量及贸" / "易方式", 10.5pt on a 15.6 grid under
adjustLineHeightInTable), clipped away by their rows in Word's print and
in ours alike. Word's text layer still places them (4pt higher than our
clipped lines), so the line match counts them.

### T110. zh-ea70c30e: a zh-TW line Word does not squeeze — DONE (2026-10-18, b62eedc7)
Owner: none (Linux 017F2GnT built it)
Built from the Mac's lab `sq-sp`: from 2013's layout, on a line with a
U+0020, the corner brackets 「」『』 give nothing toward the next
ideograph; every other mark still gives (zh-5b7ae054's and
zh-e0ca7252's "（）", zh-c2c92639's "《》（）" lines are taken in Word's
print, and "no mark gives" cost them 0.1-5 points). zh-ea70c30e
98.3 -> 99.3 on a same-base sweep, nothing else moved. (It was already
98.3 at the tip from 7184c8a6.) The rest of this note is history.
Documents: zh-ea70c30e (60.1%, sixth sample).
Both its lines with word spaces go by the fallback test (`lineOther`: a
U+0020 on the line), which takes a character when its need over the
marks that give is under the room left (lab `mh`). On p2 "…是指人數至少達
10,000 名的說" Word leaves "有" 8.3pt over with three brackets to give
(ours takes it); on p1 "…Dymally-Alatorre 雙語服務法案)規定地方公共" Word
takes "機" 3.5 over with one comma. Tried: no squeeze on a justified line
with spaces (p2 right, p1 wrong); at most half an em there (both right,
but zh-c2c92639 77.4 -> 64.9 and four others down a little, this one
level). So the rule is neither; more lines with spaces are needed.

### T111. zh-b00fef0d (93.5%, 24 pages) — 97.2, released
Owner: none (Linux 017F2GnT built c2740356; Mac 011uWpmC built p5's "“1”": a Latin word's own curly quotes give nothing before 2013's layout)
Built: under kinsoku off no mark hangs; the layout's zero-width breaks
carry no run spacing (zh-8f9b19f4 51 -> 72 with it). Left, three page
starts (p5, p7, p11). p5: "…统筹推进大综合执法。其中" then "“1”" (mode 12,
kinsoku off, 16pt 仿宋_GB2312): ours takes the word 29.4pt over with
32 of room from four marks — two of them its own quotes — where Word
sends all of "“1”" to the next line; the legacy Latin-word tests (lab
`dg`'s room, `ab32`'s start half a character in) both pass it. Perhaps
a word's own marks give nothing, or the room is the marks before it.

### T112. zh-5c6ff0d7: 3 pages where Word's are 2 — DONE (2026-10-18, 682e9c19)
Owner: none (Linux 017F2GnT built it from the Mac's lab `rb`: an exact last row's thin bottom line stays inside its height; 97.8 -> 100, Word's 2 pages; zh-06c46ba9 -0.3)
It is 3 twips, not 15.6pt: the closing note's 312-twip line starts at
12444 of 12756 in our flow, so it ends exactly on the foot and the `pf`
rule sends it on; in Word's print table 2 ends 0.14pt higher (726.96,
ours 727.08) and the note fits. Our exact rows are right (28.35); the
two header rows are not: ours 29.85 apiece centre to centre, Word's
29.28 and 29.76 — row 0's cells top 1.5pt (sz 12) over a bottom 1pt
(sz 8) meeting row 1's 1.5 top, row 1's bottom 0.5, insideH `outset` sz
6, no tblBorders outside. The text between the tables is 0.95pt shorter
in ours. And ours draws a top rule at p2's head (105.3) Word does not.
A lab of those borders (which width a shared edge takes, and how much of
it the atLeast height holds) would settle it.
Lab `rb` (Mac 011uWpmC, 2026-10-18, mode 14, rule centres): rows 0-1 at
least 567 step 29.76 and 29.52 in Word (the shared edge drawn 1.44, the
sz12), ours 29.79 and 29.86; the last row, exact 567 with its own bottom
sz4, 28.32 in Word, ours 28.84 — that 0.5 is the last row's hung bottom
line (kept outside on purpose, zh-ae655121's double line); taking rules
out of exact rows changes nothing (they have none). All sz4: Word 28.8,
28.8, 28.32; ours 28.8, 28.85, 28.85. Left: row 1's extra 0.34 (its top
sz12 meeting row 0's bottom sz8) and the hung line's width for a single
rule.
Documents: zh-5c6ff0d7 (97.8%; the Mac's measure in the fifth-sample note:
a row parted from p1 stands 15.6pt lower in the flow than drawn).

### Note from the Mac (2026-10-17, night): the zh corpus is 168 documents — a sixth sample
Twenty more (`random.seed(20261020)`, Word 16.113.3 prints), checked in;
compare per document across it. It starts at 76.6%. Its low ones,
unclaimed unless marked: zh-8f9b19f4 0.0 (Word 14 pages, ours 7; T101 + the scorer from the top, 47.4 now, 16 pages — its 2- and 3-column sections set in one), zh-117cf7c6 39.2 (3/4 pages; Linux 017F2GnT measured 2026-10-18, released: p3's one-line "※" item (12pt 標楷體 runs, snapToGrid 0, no rPr on its mark, Normal 14pt) stands 22pt under the exact 20pt line before it in Word's print, ours 19 — a 3pt drift to the page's end. Setting the label in Normal's 14pt changed nothing (the label is not in our line's height): it is the label's or the mark's 14pt making the line taller, not yet told apart; Mac 011uWpmC, 98.6 now — table text off the grid without adjustLineHeightInTable; released), zh-e0ca7252 41.9
(52/51; T102, 98.0 now), zh-340d52e9 48.9 (T103, 75.6 now), zh-d62da4dd 55.7 (4/5; Mac 011uWpmC: Word's 4 pages now — empty lines beside wrapped charts; left: the charts' own labels, released), zh-ea70c30e 59.1 (T110 measured, released; Mac 01Xgpbk5 measured — squeeze ground: mode 15, compressPunctuation, zh-TW PMingLiU 12.5pt, justified; p2 "「多數說有限英語人士團體」或「團體」是指人數至少達 10,000 名的說" ends there in Word, unsqueezed at 12.51 a character, while ours squeezes "」", "「", "」" to 9.74 and the spaces round "10,000" (17.37 -> 15.44 incl. 達, 10.74 -> 8.81) to take "有"; every line after one character early),
zh-5b7ae054 64.4 (44 pages; Windows 01QbbApP, 98.0 now — a compatibility ideograph's Noto joiner kept "能力" together; released), zh-82b166b4 72.8 (T105, 98.4 now), zh-54e91165 75.4 (T106, 97.4 now),
zh-8d6f702e 88.0 (Linux 017F2GnT measured p23 (digits off their share of the -0.21 grid) and built it the same hour as 5e502677, which landed first — dropped as a duplicate; released; Mac 01Xgpbk5, T107 for its p21-22; the rest — lines of ours a character longer than Word's on its grid of -0.21 — released; Windows 01QbbApP: YaHei's em dash, 88.4 now; what is left is the squeeze — Word gives two commas a quarter em each where ours gives none, and none to brackets where ours takes three in, office.md "YaHei's em dash"; released).

### Note from the Mac (2026-10-17, evening): the zh corpus is 148 documents — a fifth sample
Twenty more (`random.seed(20261019)`, Word 16.113.3 prints), checked in;
compare per document across it. It starts at 78.5%. Its low ones,
unclaimed unless marked: zh-4adfcce2 0.0 (6 pages; Mac, measured, released — see below),
zh-424775e4 7.6 (13; Mac 011uWpmC, 96.2 now — STXinwei's line, a footnote on its mark's page; released), zh-c2c92639 9.5 (54 pages; Linux 017F2GnT: 97.8 now — a half-hung mark's blank half gives from mode 15 (173a29a1); left p39; released; zh-51af781b p57 (Linux 017F2GnT, 454eac2e): its Table Text style is East Asian en-US, so a Latin ")" after an ideograph may open a line — 85.5 -> 94.3, released; Windows: right tab past the margin 353c5984, 91.3 now with Word's 54 pages — left: its 14 equations, OMML, office1's; released), zh-92373179
41.6 (11; T96 — Word's text layer is garbled on its table pages), zh-c399c91a 64.3 (7; Mac 011uWpmC, 100 now — LinTimes is Calibri; released), zh-7cf85f15 76.5 (3; Mac 011uWpmC, 98.5 now — a closing mark's piece takes half an em of autospace; released), zh-74ef1528 94.1 (Mac 01Xgpbk5, looked: the lines match — distributed header cells and text-layer glyphs the matcher pairs apart),
zh-5c6ff0d7 97.8 (2 pages, Word 3; Mac 01Xgpbk5, measured, released: Word fits the closing note "注释：…" at 741.4 under the table on p2, the body's foot 742.7; ours draws the table ending where Word's does (727.1) but its pagination has the last row's cell at 727.1-742.7, the page full, and the note goes to p3 — the row parted from p1 (a tall merged column) is placed 15.6pt lower in the flow than drawn, and ours draws a top rule at the page head Word does not. The parted-row ground; Mac 011uWpmC, measured, released: not the parted row now — p2's flow and drawing agree, table 2 ending 622.2pt down a 637.8pt body (16838 - 2098 - 1984 twips) and the note one 15.6 grid line, so 312 px left for 312: no spare at all, and lab `pf` (a line goes over unless a twip is to spare) sends it on. Word sets it, ending exactly on its foot, so Word's foot is lower here or its rows shorter: its PDF pages are 842pt tall, 2 twips more than the file's 16838; lab `ph` settles it: printed at 16838 twips the note stays on p2, at 16837 down to 16834 it goes to p3, so Word has a twip or more to spare where ours has none. It is the rows, not the page: table 2's top rule stands 0.78pt LOWER in Word's print than ours and its foot 0.12 HIGHER, the table 0.9 shorter, all of it in the two header rows, which are "at least" 567 twips with cells' own 1.5pt top border (sz 12) — Word's first is 29.28 tall and its second 29.76, ours 29.85 and 29.80. How Word counts a cell's own top border in an at-least row is the open question; not built).

### Note from the Mac (2026-10-17, later): the zh corpus is 128 documents — a fourth sample
Twenty more (`random.seed(20261018)`, the unprinted rest of 15-400 KB,
Word 16.113.3 prints) are checked in; compare per document across it.
It starts at 82.5%. Its low ones, unclaimed: zh-32f4ad9f 10.3 (T86, 83.6 now),
zh-5dc5ce34 20.3 (21; Windows: spacing from styles fdceb326, 22.7; the rest is a 16pt header line only Word for Mac sets, office.md — for the Mac, released), zh-167ee06c 55.4 (14; T88, 72.9 now; 71.9 against a reprint, 2026-10-18 — the old print set hangingChars lines 21.55 in, a fresh one 28; 87.2 now, Mac 011uWpmC — Word for Mac emboldens JhengHei UI Light 1/50 em wider, lab `bw`; p2's "要" was the bold, not the face, lab `sqf`), zh-21421b7d 69.2 (2; Mac 011uWpmC, 97.4 now — slash break, parted centred cell),
zh-70094a34 70.8 (19; Mac, looked: Word's text layer drops glyphs, the lines match), zh-621d8756 82.4 (52; Mac looked, released — see the wordWrap note below; Linux 017F2GnT: 99.5 now — a bracket after an ideographic space gives (55c54a9b); released), zh-34a6519a 84.0 (53; Mac, looked: the TOC matches — Word's page numbers are drawn but not in its text layer, so the matcher splits our lines),
zh-830ef10d 89.2 (3; Mac 011uWpmC, 97.3 now — a line too narrow for a character), zh-fb482d33 89.7 (T89, 95.7 now, 6 pages), zh-ad224275 93.2 (Mac, looked: the lines match — the misses are text-layer, a Wingdings bullet and pdf-text grouping).

### Note from the Mac (2026-10-17): the zh corpus is 108 documents now — a third sample
Twenty more (`random.seed(20261017)`, the unprinted rest of 15-400 KB,
Word 16.113.3 prints) are checked in; means are not comparable across
that commit, compare per document. The sample started at 80.9% (the
second started at 74.5). Its low ones, unclaimed unless marked:
zh-f6686f89 6.0 (T75, done), zh-547fc43c 13.2 (17 pages, Word
16), zh-a5745784 26.5 (T77, 99.7 now), zh-540dc149 34.3 (T76, done),
zh-fec5fa30 84.7 (55, Word 56; T78, Mac), zh-9e020c95 89.3 (T80, done), zh-268f8d15 93.0 (T84, 98.8 now),
zh-de3410bd 93.2 (Mac, looked: p1 holds a two-line paragraph Word sends on — the zh-e061a08e page foot, same footer, same margins, PMingLiU; within a point), zh-fe536967 94.0 (T83, 99.0 now). zh-d89c3840 was T70.

### T87. Fractional line heights (zh-de3410bd and three more) — DONE (2026-10-17)
Owner: session 017F2GnT (Linux)
Built: engine `skia-fractional-line-heights.patch` (skparagraph's
`ParagraphStyle::setFractionalLineHeights`; the Swift bridge sets it from
bit 13 of the encoded paragraph style), and `TextPainter.
fractionalLineHeights`, which the layout sets for a Word document's
paragraphs only. **Other boxes: pull the engine's `starling`, rerun
`scripts/apply_engine_patches.sh` and rebuild the engine before a
sweep** — without the patch the flag does nothing and the four below go
back. zh-de3410bd 93.9 -> 100, zh-d35cbbdb 89.7 -> 100, zh-232090e0 95.6
-> 100, zh-e061a08e 94.3 -> 99.8, zh-6d1afa56 +0.2 (239 documents, the
tip of 03e2ab23). With it: a face Word lacks and draws in Cambria is
Cambria's ascent over Times's descent (bug59058), a row at a page's foot
in a file of mode below 15 asks room for half the line under it
(zh-1a3c7aa0 p13), and Balloon Text is kept (delins's balloons are
Tahoma 8pt, 15.06 apart). Left: delins 80 -> 45 — its first balloon, for
two deleted paragraphs, stands 6.6pt under Word's, which lifts it into
the gap above its line; the other three prints with balloons put the
first at its line's top, as ours does. Claimed: Mac (starling-ios-5c's session), 2026-10-17.
Follow-up (Linux, 2026-10-17, engine cac609985ae, office 2c9d512a): the
bridge reports a fractional paragraph's lines unrounded, and a Word
paragraph's height, space before and shared space are exact — the Mac's
testWebSpacingPartsTwoLists (15.23 for 14) passes. **Rebuild the engine
again** for it. The half-line reserve is now mode 12 only (mode 14 asks
the whole line: zh-d68ac84a p36). Engine 3e20c0daee6: a fractional paragraph's line
height is the line's advance, not the runs' ascent + descent — on the
Mac YaHei's 1.5-spaced lines reported 644.8 for an advance of 617.4, and
zh-34a6519a's page 5 drew page 6's first line (fixed, the Mac confirms). That changed what a line's
`height` meant under the layout's picture rules, so the advance is now a
call of its own (`ComputeLineAdvances`, `TextPainter.computeLineAdvances`),
used for a Word paragraph's line bottoms only, and `height` is ascent +
descent again (engine after 3e20c0daee6; the sdk's vendored headers and
the web bridge have it).

### T78. zh-fec5fa30: 56 pages where Word's are 55 — DONE (2026-10-17)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac), from 2026-10-17
Documents: zh-fec5fa30 (84.7%, third sample).
Built (Mac, 2026-10-17): body text under "內文2", a style not based on
Normal, takes the defaults' zh-TW rather than Normal's en-US, so its
lines keep the East Asian rules ("，" no longer opens a line). 84.7 ->
86.1, nothing else moved.
T76's a309c7a1 (a fixed table keeps a grid wider than its share) also
fixes the 附件 forms here, which say 105.3% of the column (513pt) over a
524.5pt grid: 86.1 -> 88.8 measured on the Mac (s286). It also lifted
zh-547fc43c 13.2 -> 88.7 (Word's 17 pages) and zh-a5745784 79.3 -> 99.7.
Built (Mac, 2026-10-17): a repeated header of stated rows at their own
height (merged cells cut there), and an autofit cell's first piece
measured from the first line's start (the 附件2 calendar keeps its
grid). 88.8 -> 94.2 with Word's 55 pages (the title had it backwards:
ours were 56). Nothing else moved. Left: p47-48's header (51.2pt in
Word, ours 44.7) and p54's calendar 3pt low; T78 released after this.

### T76. zh-540dc149: 9 pages where Word's are 10 — DONE (2026-10-17)
Owner: the Windows box (011ZXp8e), 2026-10-17 (claimed first by 017F2GnT, Linux, who handed it over)
Documents: zh-540dc149 (35.9%, third sample).
Built by the Windows box (011ZXp8e), whose claim crossed this one: a fixed
table keeps a grid wider than its pct share (Word rules the form's 638.6pt
grid, ours scaled it to 98%), and a centred merged cell with no cut in a
parting row's part is set whole there (row 3 parted at page 5's foot as
Word does). 35.9 -> 97.5, 10 pages. Left: p1's "(JTG H10-2009)" wrap.

### T91. zh-621d8756: a table set in a frame — DONE (2026-10-17); closing spaces under wordWrap off — DONE but the colon (Windows 01QbbApP, 2026-10-18: 84.2 -> 95.5; Word's "：" squeeze before the spaces left, released)
Owner: session 017F2GnT (Linux)
Built (0be4a9a6): a table whose every cell paragraph carries one
text-anchored, notBeside `w:framePr` stands the frame's y below the
text's place and centred where it says (p15, Word's table 17.1pt under
its paragraph). 82.3 -> 83.9, nothing else moved. Released: pp 21-27's
closing spaces (the wordWrap note below). Measured on p21: Word's and
our advances agree (space 8.1, ideograph 15.6 at 15pt with 0.3 spacing),
so it is the breaking, not the widths: a paragraph-final space may
straddle the margin ("执法人员：…" ends at 509.1, margin 505.2) where a
space with text after it goes to the next line ("陈述申辩人：（…）" stops at
501.0), and Word squeezes a "：" before spaces on a full line (152.4 ->
164.0, 11.6 where ours is 15.6). The space-only lines end at
498.8-506.9, not on a multiple of 8.1 from the margin.

### T97. zh-92373179: an embedded subset's missing characters are YaHei's — DONE (2026-10-17)
Owner: session 017F2GnT (Linux)
Built (79646c80): a subset's characters outside its `cmap` are set in the
face the name has unembedded (YaHei for 仿宋_GB2312 on a Mac), their line
and its baseline that face's: the 1.5-spaced paragraphs from p3 are
41.2pt a line as Word's, and stand where Word's do (to 0.1pt). 39.9 ->
46.1, nothing else moved. Left: the matcher's — Word's text layer maps
its 招 to U+0000, and nearly every line says 招标; the lines match.

### T109. A cell stretch no line can hold gives its closing marks' halves — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
zh-007ca091's unit cells, "套（台）" in a column of 23.6pt for text: Word
sets "套" / "（" / "台）", the "）" half an em narrower; ours took "（台）"
as one stretch (nothing parts after "（" or before "）"), no line could
hold it, and the engine parted it "（" / "台" / "）" — every such row a
line taller, and the document a page longer. Now in a cell a stretch
wider than the whole line gives its full-width closing marks' halves
first, and the engine's parting lands as Word's. zh-007ca091 35.4 ->
93.0 (11 pages, Word's), zh-8f7aa519 87.7 -> 96.3, zh-d62da4dd now at
Word's 4 pages; nothing fell.

### T107. On a character grid a Latin word at a line's end is taken by T86's start rule — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
On a character grid the Latin-word branch was off altogether
(zh-d68ac84a's "给予50" left at 11pt over). zh-8d6f702e (mode 12, a grid
of -0.21): "…面雨量达150" is taken by Word, "150" starting 7.9pt inside
the margin — half "达" — with its "；" and four automatic spaces giving;
"…雨量达60" is left, "60" starting 3.95 inside with three marks to give.
So on a grid T86's start rule decides, whatever the marks (off a grid,
T106's exception for comma-like marks stands). zh-d68ac84a 98.6 ->
98.9, zh-8d6f702e's p21-22 as Word's; nothing fell.

### T106. T86's start rule only where brackets are all a line has to give — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
zh-54e91165 (mode 14, compressPunctuation): "…有效期详见附件1。" — Word
takes "1。", "1" starting 5.6pt inside the margin, with "。" and "、"
on the line giving 5.3pt apiece and the last "。" hanging; T86's rule (a
Latin word starts half the character before inside the margin) left it
a line down. T86's lab had only brackets (《》（) on its line. Now the
start rule holds only where the line has no comma, stop, enumeration
comma, semicolon, colon or mark of exclamation or question to give;
with one, the word is taken wherever the marks can give, as before T86.
zh-54e91165 75.4 -> 97.4, zh-20ff844e 95.8 -> 99.1; zh-32f4ad9f (T86's)
held; nothing fell.

### T105. Autofit's narrowest piece parts a full-width mark from a Latin word — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
zh-82b166b4's five-column autofit table (100%, its grid the page's
width): Word keeps the grid (last column 51.1pt) and parts "（WebHR）"
as "（W" / "ebHR）"; ours measured "（WebHR）" as one 50pt piece — the
brackets glued to the word as the line fitting glues them — and widened
the column to 61, every row of the table re-wrapping. To autofit a
full-width opening or closing mark beside a Latin letter now starts a
piece of its own (the line breaking is as it was). zh-82b166b4 72.8 ->
98.4; nothing else moved.

### T103. A table row of exact height goes to the next page whole — DONE (2026-10-17)
Follow-up (Mac 011uWpmC, 2026-10-18, from lenovo-2), tried and released: p3's table going on at a page's head has its top border (thinThickSmallGap sz 12) drawn there by Word, the row under its room. Built as "the top line's room less the inside line's, at a page's head with no header to repeat" and the line drawn across the head (rules 60.3 to Word's 60.2, the head's lines 22.0/23.9 to 21.4/23.5): zh-340d52e9 stays 75.6 (its p3 is within the scorer's reach either way) and zh-cec9d337 fell 84.1 -> 67.3 (27 pages), whose tables' top lines are single sz 18 with no insideH stated — Word does not set those down. Reverted; needs the rule for which tops Word repeats (compound only? only with insideH stated?).
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
zh-340d52e9's 347pt "守望相助" row is `w:hRule` exact; with 58pt left on
page 5 Word carries it whole to page 6, where ours parted it like any
row and everything after ran early. A row of exact height that a page
can hold is now not parted (as `w:cantSplit`). zh-340d52e9 48.9 ->
75.6; nothing fell. (zh-117cf7c6 39.2 -> 98.6 in the same sweep is
4a950e13's, the Mac 011uWpmC session's, not this.)

### T101. Sections that disagree on their columns are set in one — DONE (2026-10-17), zh-8f9b19f4 still open
(Linux 017F2GnT, 2026-10-18, 170afc5c: its last section, continuous, three columns filled by column breaks, set a page a column — T2's columns-as-row reading now covers the document's own last section; 16 pages -> 15, Word's 14, no line moves. Left, released: that row — "填报人：" | "审核人：" | "负责人：", 宋体/KaiTi 14.5pt at 0.77-0.91 lines, the column breaks in 1pt paragraphs of 14/240 lines — parts over page 14's foot, 33.3pt tall from 541.6 of 573. Each of its cell paragraphs is 8pt taller than its spacing before plus its line: the styles part has no w:pPrDefault, so the reader gives every paragraph Word's own Normal, 8pt after (the WPS rule, Docx.swift); this file is a PDF conversion, and whether Word gives it that 8pt here is what a lab would settle — without it the row is ~25pt and would fit; Word's print holds it on page 14.)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
zh-8f9b19f4 (sixth sample, a PDF conversion): thirteen sections, all one
column but for three of the last four; the layout has one column count
for the whole document and took the last section's three — Word's 14
pages came out as 7 of three columns each. Now, where the sections
disagree, every section is set in one column (the multi-column ones
then run long — still T2's open ground). zh-8f9b19f4 0.0 -> 14.1 (16
pages to Word's 14); nothing else moved.

### T98. Before 2013's layout a cell's text keeps its margin whatever its side lines — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
From the Mac's zh-e029cf49 note (its cell text 0.25pt right of Word's).
Lab `cb` (Word 16, zh-e029cf49's package, a two-cell table ruled 0.5, 1
and 3pt, 108-twip margins): in mode 14 "AAAA" starts at 76.56 in all
three, the rules where they were; in mode 15 at 82.08, 82.56, 83.52 —
half the line in, as lab `cb3` (bug65649, mode 15) had it. Ours set
the half-line inset in every mode. Now from mode 15 only. zh-e029cf49's
table text 110.9 -> 110.65 (Word's 110.64); no score moved, nothing fell.

### T96. A floating table's place across (`w:tblpX`) — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
zh-92373179's 507pt roster floats, horzAnchor page, tblpX 1129 twips:
Word's left rule stands at 50.6, the place less its cell margin (mode
12); ours was at the column's (71.2), 20pt right. The left now comes
from tblpX against the page, the margin or the column. Its rules are
within 0.5pt of Word's now; no score moved — that document's table
pages are garbled in Word's text layer, and the corpus's six others
with tblpX did not move. (Text wrapped beside a narrow floating table
is still not done.)

Regression seen in the same sweep, not mine: zh-3c055c9b 76.7 -> 33.5
since fdceb326 (a run's spacing from its style, then Normal's) together
with T85 — a one-file A/B reverting fdceb326 alone gives 76.7 again.
Reported to the Windows box and lenovo-3.

### T90. delins: whole paragraphs deleted, their balloon above the line they mark — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
From lenovo-2's T87 note: Word's first balloon in delins (two deleted
whole list items) stands 6.6 page-points above its anchor line, and
every balloon under it follows. Labs `dl` (Word 16, delins's package):
its box top is 6.27 page-points under the line before the deletion
("the subcommentaries") whether the space after that line is 10, 14 or
28pt and whatever space the anchor line ("March 2009") has over it, and
at the anchor line's top once that is nearer (space after 0); the
deleted paragraphs' size does not move it. Now a "Deleted:" balloon
holding paragraph marks stands at the nearer of its line's top and
6.27pt under the line before. delins 45.0 -> 76.7; nothing else moved.

- zh-4adfcce2 (0.0%, fifth sample; Mac, measured, not built): every page's
  body stands 10.5pt lower in Word's print than ours, the lines
  otherwise alike. Its header is two empty 10pt paragraphs (style af3,
  snapToGrid 0) 42.55pt down; the margin is 72. Labs `hd` (Word 16, its
  package; ~/starling-word-check/lab/hd on the Mac): the header's lines
  stand where ours do (an "X" in each: 52.08 and 64.32 in both), but the
  body's first line on p2 is at 87.6 with one header paragraph (as ours),
  98.16 with two, 110.4 with three, 87.6 with two at 5pt — Word starts
  the body 15.5pt under the header's last line once that passes the
  margin, where ours starts it at the header's foot. Built generally
  (a line of Normal's under every header) it took zh-4adfcce2 to 98.9
  and broke ~30 documents with ordinary headers (POI's header tests 100
  -> 30): so something in this file sets that gap, not found — the
  header part has nothing but the two paragraphs; the first body
  paragraph holds a square-wrapped text box at the page top.
  (Later: in layout px, its header is 851 + 488 and an empty Normal line
  312 — that sum, 1651, is Word's body top to the point. The broad build
  had a probe error, but the rule is wrong all the same: Bug51170's
  header, one empty paragraph 1800 tall (no space after), pushes the
  body by its own height in Word's print, no line added; ThreeColHead,
  HeaderFooterUnicode, sample and 61991 end in a paragraph with 10pt
  after and would not be pushed either way.)
  (Windows 01QbbApP, 2026-10-18: Word for **Windows** prints zh-4adfcce2
  as ours does — the body at 87.6 on p2, no line under the header — so
  this is Word for Mac's alone, as is zh-5dc5ce34's 21.6pt (a 16pt
  Normal mark under its one-paragraph header, lab `c5e`). Of the 186 zh
  prints only these two start their pages more than 8pt under ours (bar
  zh-8f9b19f4's columns), so the trigger is rare. No settings, header
  or Normal feature belongs to both and to no other of the 36 files
  with headers. Both Mac marks stand at the left margin at Normal's
  size: an empty Normal paragraph, in the header or at the body's top.
  Needs a Word for Mac lab that cuts the two files down.)
  (Mac 011uWpmC, 2026-10-18, lab `hd5` on zh-5dc5ce34's package, Word
  16 for Mac, four prints: as is / the header's pBdr removed / an "X" in
  the header paragraph / the header paragraph in Normal rather than
  style 6): every one prints the extra empty line at the left margin
  ~20pt under the header's line (101.1, 101.8, 101.1; 107.6 with the
  Normal header), and the body's first line at 132.3–138.5. So the
  header paragraph's border, text and style are not the trigger; the
  extra mark is not the header's. Next lab: cut the body (its first
  paragraphs, any frame/anchor at the page top) and the section's
  settings. Released.)
  (Second lab, same package: section 1 given the body's docGrid (E),
  its header distance 851 for 1587 (F), its footer reference dropped
  (G), its header reference dropped (H). E, G and H print as before —
  even with NO header reference, Word for Mac prints the centred 9pt
  header line at 81.4 and the extra left-margin line at 101.8, and the
  body at 133.0; so Word for Mac gives section 1 that header from
  somewhere (header1.xml is the file's only header). F moves both lines
  up (44.4, 64.4) and the body starts at the margin, 110.4: the body is
  pushed only because the two lines end past the 104.9pt margin. So the
  gap is: Word for Mac's header here is two lines (its 9pt paragraph and
  a ~16pt empty Normal line under it), ours one. The header part holds
  one paragraph and nothing else (WPS file, customXml item1). Next: where
  the second line comes from — a header part with no final empty
  paragraph after a bordered one? Released.)
  (Mac 011uWpmC, 2026-10-18: lab `hd`'s four prints all fit "Word for Mac
  reserves one empty Normal line under the header's last", and so does
  zh-5dc5ce34. Built for every East Asian document (an empty Normal
  paragraph's height added to the header's in `_bodyInsets`), it took
  zh-5dc5ce34 19.5 -> 93.3 and broke about forty files to single figures,
  zh-4adfcce2 unmoved. Our probe line was also 22.9pt where lab `hd` needs
  15.5. The counter-case that decides it is zh-8e8d4c40, 100% as it
  stands: one empty header paragraph in "header" style a5 (snapToGrid 0,
  10pt, based on "Standard (user)"), 42.55 down with a 45.4 margin, its
  body at 54.75 in Word's print with no line under it. a5 is zh-4adfcce2's
  af3 almost to the attribute; af3's base sets an explicit pBdr of
  "none" on every side, and zh-5dc5ce34's header paragraph sets its
  bottom to "none". But hd5's print without that pBdr kept the line, so
  borders are not the trigger either. Reverted; not found.)
  (Mac 011uWpmC, later: lab `hl` (zh-4adfcce2's package, a five-line
  Normal body). Two empty af3 header lines from 42.55pt end at 67, and the
  body starts 15.6 under them, not at the 72pt margin: 22.6 with Normal
  at 20pt, 6 with Normal at 8pt; at the margin with one header line or
  the header 15pt down. None of these change it: the header's text (an X
  in each), the explicit "none" pBdr on its base style or on Normal,
  dropping the docGrid. Built as "a header that ends above the margin
  keeps an empty Normal line under it" (East Asian layout), it took
  zh-4adfcce2 0 -> 100 and broke the same ~40 files (zh-021b8feb mode 15,
  two header paragraphs, header ending just above its 70.9 margin, 99.6
  -> 3.0). zh-5dc5ce34 did not move, so its case is another. Reverted.
  Still to separate: the lab's body is itself Normal, so "Normal's line"
  and "the body's own first line" read alike. A body that opens with a
  paragraph of another size would tell them apart, and zh-021b8feb's
  header and first paragraph are the next thing to diff against
  zh-4adfcce2's.)
  (Then lab `hl` N and O, same header, the body opening with a run of
  its own size, 20pt or 8pt, Normal untouched: no push. Their second
  lines stand 1.8pt from ours, as the unpushed variants do, where A's
  stood 11.7 off. So the extra is neither Normal's line nor the first
  line's height. It comes when the body's first paragraph's runs say no
  size and take Normal's. Next: check zh-021b8feb's first body paragraph
  for an explicit size.)
  (Lab `hl` P/Q/R: the push is decided page by page, by the page's first
  paragraph: a sizeless one is pushed, one opening with a 20pt run is not.
  An explicit 12pt run (Normal's own size) IS pushed. So the trigger is a
  first line in Normal's size, not a run with no size. G and H fit that
  too (Normal 20 or 8 with the body at Normal's). zh-021b8feb's first
  paragraph is 20pt against its Normal, and it is not pushed. Still to
  try as a rule: when a page's first line is in Normal's size, the body
  starts no higher than one ungridded Normal line under a header that
  ends above the margin. The earlier probes used a gridded line, 31.2pt
  in zh-1563bd74's grid, which by itself would push files Word leaves.)
  (Built that way: per page, ungridded Normal line from the header's own
  document, Normal's paragraph style. Lab `hl` then pushes exactly the
  pages Word does, 2-5pt short. In the corpus it took zh-4adfcce2 0 ->
  36.2 but cost zh-007ca091 93 -> 11.9, zh-e37f8d40 100 -> 27.9,
  zh-799c91cd 99.2 -> 51.8 and zh-20c1d74a 86.5 -> 78.4 (s353 -> s354).
  zh-007ca091 is the clean counter-case: one empty header paragraph,
  Normal 16pt, the header ending above its 70.85 margin with room for a
  Normal line to pass it, and Word does not push. So zh-4adfcce2's
  package still holds the trigger. Its Normal names Liberation Serif, a
  LibreOffice face Word for Mac lacks; its styles are LibreOffice's
  "Standard". Next lab: swap that face for one Word has. Reverted.)
  (Lab `hl` S/T: with Liberation Serif, or every face of the styles,
  swapped for Times New Roman and 宋体, the body is still pushed (81.7
  and 80.7, against 73.9 unpushed). So the face is not it either. Left
  for a fresh look: cut zh-007ca091's package to the lab's shape and see
  which of its parts stops the push.)
  (Lab `h7`, zh-007ca091's package with the lab's five-line Normal body:
  with its one empty header paragraph (V1), and with that paragraph
  doubled (V2), Word starts the body at 72.3 both times, unpushed. Ours
  sets V1 at 74.4 and V2 at 85.4: our empty header lines there are
  taller than Word's, a difference of its own. What makes zh-4adfcce2's
  two empty af3 lines push, and these not, is still open.)
  (Correction to the above: our header there is right, 10.98pt a line
  and 21.96 for two, so its foot (64.5) is inside the 70.85 margin.
  What sets V2's body 13pt low in ours is not the header's height. The
  likely suspect is the body's line grid (linePitch 437, 21.85pt), whose
  first line ours places from somewhere other than the margin when a
  header ends near it. Unchecked.)
  (zh-5dc5ce34's extra line, read off its print: on every page a
  TimesNewRomanPSMT 16.1pt blank at 101.1-118.9, under the 9pt header line
  at 81.4. A real empty line in Normal's size, not the Arial Unicode
  fallback some of its runs take in Word for Mac's prints.)

### T89. A table floating against the text: its anchor paragraph stands where the table began — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
zh-fb482d33's landscape roster is `w:tblpPr` vertAnchor text, tblpY 430
twips, full width; after it an empty 12pt paragraph, another, and the
section's mark. Ours set the table its offset down and all three under
it, and the last two took a page of their own (7 pages to Word's 6).
Labs `fb` (Word 16, its package): with "Y" in the first empty paragraph
and "X" in the second, Word sets "Y" at the table's place — the
paragraph after a floating table is its anchor, and the table stands
its offset below that paragraph's top — and "X" under the table. Now the
anchor paragraph, where it fits in the offset on the table's page, is
set at the table's start and the text goes on under the table.
zh-fb482d33 89.7 -> 95.7 (6 pages), zh-34a6519a 84.0 -> 86.4; nothing
fell; all 128 zh documents have Word's page count.

### T88. zh-167ee06c: an alternate name of JhengHei, and JhengHei UI's line — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
Its 華康雅風體W3(P) has `w:altName` "Microsoft JhengHei UI Light", and
Word's print draws that face (embedded); ours took YaHei, its 1.5-spaced
bold 14pt lines 36.3pt apart to Word's 34.7. An alternate naming JhengHei
is used now, and JhengHei UI has a line of its own: ascent 2080, descent
521 in 2048 (from the embedded subset), 1.3 of it = 1.651 em, Word's
34.67 / 21 to the point. Not emboldened wider: 1/57 em a character ran
the file a page long (0.4%). zh-167ee06c 55.4 -> 72.9; nothing fell.
Left there (hangingChars: Windows 01QbbApP, 2026-10-18, measured, released — Word for **Windows** sets these lines 28pt in, as ours, and "助。" under firstLineChars 250 at 35.1: on the Mac a character of this face (華康雅風體W3(P) → embedded JhengHei UI Light, 14pt bold) is 10.8pt, 0.771 em — 21.6 and 26.9 — on Windows the run's 14; not its xAvgCharWidth (2024/2048), not Normal's 12; needs a Mac lab): "hangingChars" 200 sets its lines 21.6pt in where ours
stand 28 (two of the 14pt ems); its first line's "、" squeezed to take
"系", which Word leaves.
**Settled (Mac 011uWpmC, 2026-10-18): the 21.6 was the reference print's,
not Word for Mac's.** Lab `lab_hc`: the paragraph alone, with Normal's size
changed and with the face changed, sets its lines 28 in. 10pt runs set them
20 in, so the count is of the run's size, as ours. The file's first five
paragraphs set them 28 in, and so does a fresh print of the untouched file
on the same Word (16.113.3). The print checked in at de552be5 (2026-10-17
21:04Z) set them 21.55 in — Word carried something over from the batch.
It is reprinted now. zh-167ee06c scores 72.9 -> 71.9 against it, from the
same layout; the misses left are p2's squeeze (above) and the forms from p4
on. The other 19 of that sample were reprinted too, and none moved by
layout: zh-621d8756's p15-20 headings by 3pt, zh-5dc5ce34 by 1pt, and
zh-32f4ad9f and zh-70094a34 only in text extraction (U+0000 for some
glyphs). **A reference that disagrees with a lab is worth reprinting
before it is believed.**

### Note (Mac 011uWpmC, 2026-10-17): `w:wordWrap` off wraps a paragraph's closing spaces
zh-621d8756 pp 21-27 run a line or two short, every page after p21 late:
its forms end paragraphs in long runs of underlined spaces under
`w:wordWrap w:val="0"`. Lab `ws` (Word 16, p21's paragraphs, four
variants: as is / wordWrap on / no underline / both): the underline does
nothing; wordWrap does. On, the closing spaces hang past the margin out
to the page's edge (lines to x 596 on a 595pt page) and only then wrap,
as ours do. Off, they wrap at the margin as characters do, the last
space straddling it (lines end at 498.8-509.1, margin 505.2):
"陈述申辩人：（…）" and 56 spaces is two lines, a paragraph of 102
spaces two. Tried: holding the closing spaces (no-break, a zero-width
break between each) and plain spaces with the breaks — both overran,
the fitter counting the spaces ~8pt wider over a line than Word and no
space allowed to straddle. Not built; lab in the Mac's scratchpad.
The 8pt is the colons: under `compressPunctuation` (and
noPunctuationKerning) Word sets "：" before a space 11.6pt wide at 15pt
with 0.3 spacing (15.6 in ours), so "执法人员：" + 18 spaces + "执法证号："
+ 15 spaces ends at 509.1 (one space straddling the 505.2 margin) where
ours ends 8.4pt further. Both halves — that compression, and closing
spaces that wrap with one straddling — are needed before the wrap can
be built. Released.

### T86. A Latin word at a body line's end starts half an em inside the margin — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
zh-32f4ad9f (mode 14, 16pt 仿宋_GB2312, zh-CN): "…（国务院令第711" — ours took
"711" 17.75pt over with three marks giving, Word wraps it; so on the
next lines. Lab `ab32` (`lab/tools/abthresh.py`, its line alone at a
bisected indent, Word's threshold and ours on the same files): "…第71"
and "…第711" are taken while they start 8.0pt or more inside the margin
(half of "第") and not nearer, whatever the marks could give; "…第71111"
and "…第7111111" stop at a need of 19.1 either way (a cap, two points
only — not built). Ours took the word wherever the marks could give, if
it started inside the margin at all; now it must start half the
character before it inside. zh-32f4ad9f 10.3 -> 83.6, zh-5a9a85c6 95.7
-> 98.7, zh-547fc43c 94.9 -> 97.0; nothing fell.

### T84. A paragraph's `w:snapToGrid` 0 takes its characters off the character grid too — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
zh-268f8d15 (linesAndChars, charSpace -5544): its footer's "- 1 -", in a
text box fit to its text, its style `w:snapToGrid` 0, is set at Times's
own widths in Word's print; ours took each character 1.3pt in by the
grid — only a run's own snapToGrid 0 was read for the characters, the
paragraph's for its lines — and the box, sized so, lost its closing
dash on every page. Both the text and a list number honour the
paragraph's now. zh-268f8d15 93.0 -> 98.8, zh-3c055c9b +0.3; nothing
fell.

### T83. zh-fe536967: a frame set inline is a paragraph in the flow — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
Its footer paragraph's own `w:framePr` (`w:w` 0, `hRule` auto,
`yAlign` inline) over its style's framed box (exact 581 twips, y -164):
ours took it out of the flow as a frame, and the page-number text box
anchored in it stood 21pt low on all 40 pages. Word sets it as a
paragraph. A frame `yAlign` inline with no width and no exact height is
none now. zh-fe536967 94.0 -> 99.0; zh-90e0cea8 (the only other) did
not move; nothing fell.

### T80. zh-9e020c95: a first line indented past the margin holds a character — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
Its footer's paragraphs are indented 5472 twips with a 6400-twip first
line, past the right margin: the page-number box and "X隆阳区人民政府发布"
stood 18-20pt high on every page. Lab `ind` (Word 16, its package): such
a paragraph, right- or left-aligned, sets its first character on the
first line, off the page, and the rest from the second; ours left the
indent's box alone on the first (skparagraph parts a too-wide word by
clusters, a joiner does not hold it) and the footer took two lines
more. The box now stops an em short of the margin. zh-9e020c95 89.3 ->
100; nothing fell.

### T77. zh-a5745784: a Taiwanese mark that ends its paragraph neither hangs nor gives — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
zh-TW, mode 14, compressPunctuation, 12pt 標楷體 (YaHei), left-aligned.
Its "…資格者，…志工資格：" ends a paragraph 15.7pt over and "…大隊長代理。"
10.7; ours hung the final mark, Word sends both down. Lab `hang`
(`lab/tools/hanglab.py`: the line alone at a bisected indent, Word 16):
the final "：" or "。" with one comma on the line keeps its ideograph to
6.0pt over, with two commas to 12.0; with text after the colon to 18.0
(its hang and half the character before, as ours had); with no commas
12.0. So where there is no zh-TW `w:noLineBreaksBefore` list, before
2013's layout, a centred mark that ends a body paragraph neither hangs
nor gives, the line's other marks giving their halves — not in cells
(lab `pe`), not in justified paragraphs (zh-06c46ba9 97.2 -> 70 with
them), not where no punctuation is compressed (zh-6c6adfde, zh-503983e4
fell). (A first build, 8bc6e27c, kept the hang and stopped the commas;
it got the two-comma line right for the wrong reason.) zh-a5745784
26.5 -> 99.7, zh-ae655121 93.1 -> 93.6, zh-15728c84 99.5 -> 100; nothing
fell.

### T75. zh-f6686f89: a square face's Latin is exactly half an em — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
宋体's Latin stand-in is Liberation Mono at 5/6, but its advance is
1229/2048 em, not 0.6: each character 6.00098pt at 12pt. The bank's
questions end "…（TSG S7001-2013）…。（      ）", and twenty such characters
put the "）" 0.02pt past the margin and a line down, where Word's ends
on it; every question after slipped. Scale 1024/1229 now. zh-f6686f89
6.0 -> 100, zh-a0e932c2 98.5 -> 99.2, nothing fell.
Also (Linux, 017F2's sweep without e4ff8b67): a309c7a1's fixed-grid rule
alone takes zh-f6686f89 5.6 -> 99.6 (22 pages like Word's), and zh-fec5fa30
83.8 -> 85.7. Both fixes hold together; nothing to redo here.

### T70. Kerning in a stand-in set to the original's advances (YaHei's "TC") — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
Documents: zh-d89c3840 (third sample, 96.5%), p2: "（TC）、…（SC）秘".
Known: a face set from an advances table (YaHei, YaHei UI, JhengHei,
DengXian, Verdana, ...) has its kerning switched off, the stand-in's
pairs being wrong. Word kerns those runs by the original's own table:
Normal's `w:kern` 2, YaHei's T-C pair -99/2048, and Word's print sets
"T" 8.4pt where its advance is 9.17. Ours, 0.77 wider, ends the line
8.21pt short of "秘", past the mode-14 half of "）" (8.0), and both lines
of p2 that hold "（TC）…（SC）" leave "秘" a line down.
Built: YaHei's (and YaHei UI's, the same), its bold's and JhengHei's
ASCII pairs from the `kern` tables of the faces Word for Mac carries
(`RichResolvedFace.kerns`), set where the run kerns at its size. The
corpus's Word prints agree: 23 of the 33 YaHei pairs over 0.3pt are
kerned, the rest in runs that do not kern. zh-d89c3840 96.5 -> 100;
nothing else moved (zh 97.5, POI 88.0). DengXian has GPOS pairs only
and no `kern` table; left until a print shows Word kerning it.

### T1. Autofit tables — DONE (2026-10-15)
Owner: session 017F2GnTfScURKYZPmRxVQvW (Linux dev box, no Word)
Built as office.md's "Autofit tables" has it (b7b42101): a cell whose
narrowest setting (its longest unpartable piece — spaces after a no-break
space joined — plus margins and side indents, negative ones too) is a
point or more over its grid columns is exactly that wide; the others give
way toward their own narrowest; the table grows only when they need it.
zh-0aac9d1a 63.3% -> 100% on Linux, nothing else moved. Why only its
first form re-fits: its stamp line is in 仿宋 (no-break space an em, a
444pt piece); the other three are 仿宋_GB2312, YaHei on a Mac, whose
no-break space is narrow. Still open, needs Word: how a span is shared
among its columns (ours 34.5/183.0/109.5/163.5 against Word's
34.6/187.6/110.5/156.4 — no line moves here). Lab: a span over three
columns of unequal grid and content, its narrowest varied.

### T2. Per-section column layouts — narrow case DONE (2026-10-15)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box)
A section of columns filled by column breaks and followed by a
continuous section is read as a borderless table row (office.md):
zh-a0e932c2 22.6 -> 100%, zh-6cd1befe 85.2 -> 93.3. Still open: a
section of columns that runs over whole pages (zh-6cd1befe's seventh
section, two columns) is set in one column.
Documents: zh-a0e932c2 (23%, 7 pages to Word's 5).
Known: a section of three unequal columns filled by column breaks,
then a one-column continuous section on the same page. The layout has
one column count for the whole document (`pageSetup.columns`, slots of
`page * columns`). A larger change to pagination.

### T3. `w:mirrorIndents` — DONE (2026-10-14)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb
Built as measured (entry in `office.md`), with a relayout pass after
paging. Moves little: zh-06c46ba9's paragraphs hang by their left
indent. Its real gap is T10.

### T4. Heading spacing at a page's top — DONE (2026-10-14)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb
Space kept at a page's top is less the previous paragraph's space after
(entry in `office.md`). zh-64044a1d 27 -> 33, zh-6d1afa56 16 -> 36.
zh-64044a1d still runs 119 pages to Word's 103: the next difference is
open for anyone.

### T5. zh-6d1afa56: headings led by breaks
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box, Word for Windows only), from 2026-10-14
Documents: zh-6d1afa56 (16%), zh-1a3c7aa0 (24%).
Known: break-led headings came out at three different heights — likely
the T4 rule (re-check after it); in
zh-1a3c7aa0 the second (landscape) section starts pages earlier than in
Word, and the odd-page footer stands 8pt lower than Word's.
Note for the Mac session (parted rows are yours): zh-1a3c7aa0 page 14's
last row parts over the page with its centred name cell's first line
on 14; Word's part is 40pt (156.8 to 116.9) with that line centred in
it, ours runs to the page's foot with the line at the part's top, 4pt
high. c2542ff6 covers a cell whose text all fits; this one's does not.
Progress (Windows box): zh-6d1afa56 16% -> 97.9% (line-opening marks,
merged cells over a page foot, the blank page after an over-full page,
with T4's rule); zh-1a3c7aa0 10% -> 29% (YaHei fallback, its footer's
height, the odd/even blank page, the section mark's own page). Still
open in zh-1a3c7aa0: from page 13 the annex tables run long (93 pages
to Word's 90); even pages' "- 10 -" prints as "-10" in Word (its box).

### T6. Body pictures on the line grid — DONE (2026-10-14)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb
Snapped in the body as in cells (lab `pg`, entry in `office.md`).
zh-90e0cea8 now runs a page long from drift earlier on its last page
(ours 17.6pt below Word's there): open for anyone.

### T7. zh-abe7e063, zh-25c4de17, zh-799c91cd, zh-190d730c — DONE (2026-10-18: 100 / 100 / 99.2 / 97.8 at s348, by the fixes since; released)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac, has Word), from 2026-10-14
- zh-abe7e063: done (symbols an em in square faces), 32.8 -> 91.7.
- zh-799c91cd: page 1 drifts about 2.5pt low by its foot, so its last
  line goes over. Word's 12pt lines step 20.64/20.4 (a 0.24pt raster,
  mean 20.58 = YaHei's 1.3198 em x 1.3); ours a steady 20.65. Tried
  and reverted: the tallest-run strut for every multi-line paragraph
  (no change here, two documents lost 24-32 points) and YaHei's height
  1.72 -> 1.7157 (no change here, slightly negative overall). Not the
  list label, the Latin run nor the 「」 quotes (tested by removing
  each). Open.
- zh-190d730c: its first difference is a scorer artefact (a justified
  line drawn out of order splits PDFKit's line). Not looked at further.
- zh-25c4de17: done (the column gap stated on w:col), 36.5 -> 100.
zh-799c91cd's page-1 drift found (Mac, 2026-10-14): the second line of
"（二）共同申請人同意由" stands 21.55pt under the first where Word's is
20.64 — its first line holds two runs of eight spaces in Times New
Roman (no hint); a copy without them sets 20.65. Word sizes the line by
its text. Two fixes tried and reverted: spaces set in the East Asian
face at Times' width (zh-33aa9899 98.6 -> 39.2, zh-e37f8d40 -15), and
spaces at a line height of 1.0 (zh-c3dd22c4 100 -> 14, zh-4b8e0abc
-31). Other documents' lines depend on what such runs do now; the rule
has to say which spaces Word leaves out of the line's height (at the
line's end? between East Asian text?), from a lab.
Solved (81b392cd, 96f82ce8): it was the zero-width space put in after
the held spaces, in the East Asian style, whose glyph came from the
Latin base family; and then YaHei's 1.715-em pitch. zh-799c91cd 82.3%
-> 91.2%.

### T8. Load embedded fonts — DONE (2026-10-15)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
East Asian embedded faces are loaded and drawn (office.md);
zh-e37f8d40 94.0 -> 96.6, nothing else moved. Latin embedded faces are
left to the clones on purpose. Found on the way and fixed in the engine
(a0cbed78): exported PDFs' text read radicals (⼈⺠) for ideographs in
every Chinese document. zh-e37f8d40's remaining misses: a line Word
does not squeeze to take "民" (p3, compressPunctuation, mode 14) and
table header cells.
Documents: zh-e37f8d40 (already 92.8% with the square model),
saut_page.
Known: `word/fonts/*.odttf`, obfuscated with the `w:fontKey` GUID
(XOR of the first 32 bytes). Not loaded; the name only keeps the square
face model.

### T9. Nested tables with hidden text — DONE (2026-10-15)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box)
Documents: zh-454e2e29 (49%), row 2. Now 96.1%: a cell centres its text
with the text boxes anchored in it (ada8880e), two lines in one
(`w:combine`, 37a4a534), and a small nested table set as a table, a
block in its cell (223b723e). Still flattened: nested tables over 15
rows or 600 characters (a block cannot part across pages; 60329's
protocol is one), and any that nest further (drawing).

### T10. A section of one empty paragraph: a page or none? — DONE (2026-10-14)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb
Always a page, unless a page break just before is the same break
(entry in `office.md`, lab `es`). zh-06c46ba9 0.7 -> 47.2.

### T11. zh-90e0cea8: drift on its last page — DONE (2026-10-14)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac, has Word), from 2026-10-14
Documents: zh-90e0cea8 (67%, 11 pages to Word's 10).
Known: Word's last picture ends exactly at the page's usable foot, its
line's descent past it; ours now allows that (entry in `office.md`),
which took zh-6d1afa56 from 41% to 97% — note for T5's owner. This
document still needs about 1.3pt more: ours starts the picture's line
about 2pt below Word's, from drift earlier on that page. Open.
Progress (Mac): numFmt "none" levels (297b0f60) took it 67.5% -> 88.5%.
Left: page 10's text runs 0.54pt below Word's from the top, and the
last picture then misses the foot. The cause is the header: style 63,
ascii 黑体 / hAnsi 宋体, and its "—" is SimSun in Word's print but
Liberation Sans in ours (a taller ascent: the header's baseline 1.09pt
lower). Routing hAnsi characters to an East Asian hAnsi face works (it
resolves 宋体) but our 宋体 stand-in has no U+2014 and falls back to
Liberation Sans all the same — tried and reverted, no score moved.
Now 88.5% -> 67.8% after the list-number rule of 2026-10-14 (its 6.1.1
paragraph wraps as Word's, and 6.1.3 then misses page 5's foot by that
half point): fixing the header's "—" would recover both. The East
Asian style's family is the Latin stand-in (Liberation Sans) with CJK
glyphs from the system fallback; a glyph the stand-in has (U+2014)
comes from it with its metrics. The fix is in the face resolver: an
East Asian style whose family is a real CJK face, so its symbols and
their metrics are that face's.
Tried (Mac, 2026-10-14): the East Asian style's family set to PingFang
SC outright. The header's "—" then comes from the CJK face, zh-799c91cd
91.2 -> 96.0 and zh-9c5d0c3f 55.9 -> 66.7 — but every ASCII character
in an East Asian-hinted run comes from PingFang too, at its own widths:
zh-457a8d62 94.7 -> 19.9 (its "(許志堅子)" parens), zh-06c46ba9 -7.3,
zh-7dc3afad -4.0. Reverted; the narrow version (only the dashes and
ellipsis routed to the CJK face) is in — zh-9c5d0c3f 55.9 -> 66.7 — and
zh-90e0cea8's header line still stands 1.09pt under Word's with its "—"
from the CJK face. So the drift is not the dash: the 黑体 run's mono
stand-in (Liberation Mono at 5/6, baseline 1.005) is the next suspect.
Found: the header sub-layout took the body's line grid and centred its
10.5pt line in the 15.6pt pitch (11.44 under the top; Word 10.35).
Headers and footers now keep to no grid: 67.8% -> 83.9%, Word's 10
pages (commit after 49beaff9). Then its empty 0.7pt counter paragraphs
(zero in ours, 0.7 each in Word) — 83.9% -> 92.3%. What is left: the
cover page (frames) and page 2's table of contents, whose lines match
Word's glyph for glyph but whose leader dots the matcher's text
extraction groups otherwise.

### T12. Squeezing marks to fit a character: the limit on a character grid — DONE (2026-10-15)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box). zh-d68ac84a 80 -> 99.2%:
the hang half (299b2ecd) and the squeeze's tolerance, which now stands
only off a character grid (on one ours are Word's widths exactly).
Documents: zh-d68ac84a (80%, first parting page 10).
Windows box, 2026-10-15 (299b2ecd): the hang half of this. Word hangs a
final mark to its em exactly (no hair), and keeps a character-counted
indent in whole twips (200 hundredths at 14.6465 = 586 twips): lab `hc`
on this document's grid; zh-d68ac84a 81.4 -> 83.8 (page 22). Rounding
each grid character to twips was tried and is wrong (75.6). The squeeze
case below is untouched.
Found (labs `pqgrid1`–`6`, `pqkin1`–`3`, `pqvar1`, `pqthr1` in
`~/starling-word-check/lab`, 2026-10-14): Word squeezes 。、，（） alike
on a grid of `linesAndChars` with negative `w:charSpace`, and its
first-line indent does not stop it. On the real paragraph Word takes
"学" with the line made 0.1pt wider and leaves it at the stated width;
our fitter puts that line 7.318pt over against a limit of 7.323 plus a
0.045 tolerance, and takes it. The difference is under a hundredth of a
point, below what our widths match Word's to: probably Word measures in
twentieths (the indent as 586 twips, not 2 × 14.646). Not worth chasing
without a model of Word's rounding.

### T13. zh-89385c94: cell lines and a page's foot — DONE (2026-10-14)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-14
Result: 99.3% on Windows (2ffeece2, 3605f11c, with 37fdff4b).
Documents: zh-89385c94 (16% on Windows).
Known: page 2's cells take "考，" on a line Word ends a character
earlier, and the page's foot holds one line more than Word's.
Note from the Mac session (37fdff4b, pushed before this claim was
seen — sorry for the overlap): the extra line at page 2's foot came
from the carried-over row part at the page's top, which stood 0.4pt
above Word's for want of its top rule; with that, zh-89385c94 went
16.3% -> 51.0% on the Mac. The "考，" line break is untouched and
yours, as is the rest of the document. The Mac session will stay off
zh-89385c94 from here.

### T14. zh-06c46ba9: body lines two characters short from page 5 — DONE (2026-10-18: 97.1, Word's 72 pages, at s348, by the fixes since; released)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac, has Word), from 2026-10-14
Documents: zh-06c46ba9 (47%, Word's 72 pages).
Known: page 5's body lines end two characters before Word's.
Progress (Mac): mirrorIndents parity by `doNotFlipMirrorIndents`
(5a7f5332), compound cell rules (91ca3fcf), footnotes laid out
(c7ffdfc9), an autofit grid wider than its share kept (fc60d952):
47% -> 75.9% (with 4b562bc1, list numbers' Latin digits). Page 5's
figure is SmartArt (word/diagrams), drawn as an empty box; the only
such document in the corpus. Pages 25 on: the footnotes and their room
match Word's to 0.1pt (separator 14.65, note lines 17.2), but table 9
on page 24 runs ~0.1pt a row taller than Word's — 1.35pt by its foot —
so the page's last line (exact 25pt) misses by 0.36 and goes over. Word
puts every line on a 1/300in raster (0.24pt); that is the open
question, not the notes.

Note for the Windows session: on the Mac, 2ffeece2 moved zh-9e08ed28
from 56.7% to 47.4% (Word's 22 pages: 21 -> 23); the sweep that showed
it held nothing else that touches that document.

Note for the Windows session (Mac sweep, clean baseline either side):
62ba13ec + 9491b2ba together moved zh-64044a1d 72.8% -> 67.1% while
taking zh-9e08ed28 47.4 -> 81.0, zh-e6d54ae4 64.2 -> 82.4 and
zh-89385c94 53.1 -> 98.9.

### T15. Charts in Writer
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-14
Documents: 61745 (two charts, nothing else), chartex, zh-37b6536f (p3).
Known: a chart (`c:chart` in a drawing) is kept as an empty box of its
size. Slides reads and paints charts (`ChartXML.read`, `ChartPainter`);
the plan is to paint them in Writer through a hook in RichLayout.
Progress: drawn (61745 0 -> 15/17 lines, zh-37b6536f 31% -> 96%), the
automatic title of an unnamed lone series, `cx:` charts by their
Fallback pictures, charts in a line of text (chartex: 3 pages as Word's).
Left: radar charts (Slides reads none; chartex's stays a grey box).
2026-10-16: stock charts read as their lines (735f39f0); a 2013-style
bar chart's plot top, ticks taking no room in a 2013-style chart, a
line's 19.2pt legend key (f9c1e61e..599f460a): 61745 100%, chartex 50.
Then a top legend's place, a radar's circle and labels (e80a1e35,
1148fce3) and box-and-whisker charts drawn from their chartex part:
chartex 76.4%, pages 1 and 2 all but one line. Left on chartex: its
sunburst (p3, 16 of 27 lines) is still its Fallback picture.
(Mac 011uWpmC, 2026-10-18, looked, for this task: zh-d62da4dd p4, 55.7%,
41 of its 45 misses on that page, is two 3-D pies (`c:pie3DChart`, rotX
30, perspective 30) whose every data label has a `c:dLbl/c:layout/
c:manualLayout` and `showLeaderLines` 1. Word's print sets each label
outside its slice with a leader line, in a bordered chart area; ours
sets them on and over the slices (PieLabels keeps a 3-D pie's best-fit
labels inside, and the moves start from there), with no area border.
The moves are fractions of the chart's frame from the default place, so
that default (outside for these) decides every label.)

### T17. zh-9c5d0c3f: road-sign table rows — DONE (2026-10-16)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-14
Documents: zh-9c5d0c3f (54%).
Note from the Mac (2026-10-14): 49beaff9 (dashes and ellipses in East
Asian runs set in the CJK face) moved zh-9c5d0c3f 55.9% -> 66.7% on the
Mac — found through T11, not taken from this task; what is left of it
is yours.
Windows box, 2026-10-15: its signs now stand centred in their cells
(c69db236) and the tables where Word sets them (2ff0daed: before 2013's
layout a spaced table is set out by its first cell's text inset). The
signs' rows a pitch tall: settled by 59fc1ee5 (a picture's line is as many grid pitches as the
picture is tall, its descent not counted): 81.6% -> 90.8. Left: page
6's continued row stands 5pt high (parted rows); p3's "停車再開"
(a 75pt sign and its caption in one paragraph, the caption wrapped
under it, "at least" 19.2) 9pt high; p4's "車道縮減" (snapToGrid off,
"at least" 11) 21pt high.

### T18. bug59058: a bordered run's picture line — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box, no Word; starling-office1 worktree), from 2026-10-15
Documents: bug59058 (73.9% on Linux, 53 pages to Word's 52).
Known: from p27 its "tab1"/"tab2" pictures are inline in runs with a
character border (`w:bdr` single, sz 6, space 0, CCCCCC, frame). Word's
picture lines are 75 and 31.56pt for pictures of 72.75 (+0.75 effect
extent) and 30 — the border's 0.75 above and below; ours 72.75 and 30,
with no border drawn. Text runs with borders (zh-06c46ba9, 42) are left
alone until measured.
Built (office.md): the line holds the border and the effect extent,
the border is drawn. p27 within 0.3pt; bug59058 73.9 -> 74.9% (Linux),
nothing else moved. Its next parting is p38: the references drift about
0.1pt a paragraph lower than Word's (2.3pt by the page's foot).

### T19. bug59058 p38: lines mixing Times and Cambria — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: bug59058 (74.9% on Linux).
Known: its references are 13pt Times, "at least" 15pt, with MinionPro
journal titles (Cambria in Word, Caladea here). Word steps a line with
Cambria on it 15.24 (on its 0.24 raster: 15.12/15.36), a Times-only
line 15.0; ours 15.45 and 15.0 — the engine's even leading puts half
of Times's padding under the baseline, so the mixed line is Cambria's
ascent plus that deeper descent. 2.3pt by p38's foot.
Built (office.md, "Times and Arial keep their line gap over the
text"): Writer draws Liberation Sans/Serif with the gap moved over the
ascent. bug59058 74.9 -> 89.1%, Word's 52 pages; nothing else moved
(form_footnotes -1.2 is the matcher joining a footnote mark to its
line). The browser build's copies (web-app.sh) were not built here.

### T20. Vertical text in cells (zh-2b955411) — DONE (2026-10-15)
Owner: session 017F2GnTfScURKYZPmRxVQvW (Linux dev box), from 2026-10-15
Documents: zh-2b955411 (89.7% on Linux; pages 26-28 lose 45 lines).
Known: `w:textDirection` tbRlV and tbLrV cells ("评估目的", "经济行为类型"):
Word stacks the ideographs upright, one a character's advance below the
other (9pt at 9pt). The reader turns tbRlV sideways (`.down`) and reads
tbLrV as horizontal, so that row is three lines tall, 6.7pt over Word's,
and the 282pt stamp row after it goes to the next page.
Done: tbRl/tbRlV/tbLrV read as turned with upright ideographs, drawn a
character at a time, distribute spread along the cell (office.md,
"Vertical writing in a cell"). zh-2b955411 89.7 -> 98.0%, nothing else
moved. Left: a turned paragraph with Latin in it is drawn turned whole.
`w:jc` distribute for horizontal text: built the same day (office.md,
"Distributed paragraphs"), no line moved, characters within 0.4pt.

### T20. bug59058 p45: an empty `<w:pict/>` — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: bug59058 (89.1% on Linux).
Known: the paragraph before p45's table holds a run of nothing but an
empty `<w:pict/>`; Word draws nothing and gives it no room, ours a
300 x 200 grey stand-in, and the table stands 187pt low.
Skipped now: bug59058 89.1 -> 91.7%, nothing else moved. Next parting p48
("New Cases, Deaths and 5-Year Relative Survival", 4pt low).

### T21. bug59058 p48: Lucida Sans Unicode's line — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: bug59058 (91.7% on Linux), the only one with the face.
Known: Word's print embeds Lucida Sans Unicode: hhea 2246/-901, no gap
(1.537 em, baseline 1.097 down); its 9.5pt single lines step 14.52 (on
the 0.24 raster). Ours set it in the sans clone's 1.15 em: p48's
fact-sheet heading and table stand 1.4 to 5pt high.
Built: the face's own line and baseline; the table within 0.2pt,
bug59058 91.7 -> 92.2%. Next parting p49 ("Béatrice Lauby-Secretan").

### T22. bug57031: math letters are boxes on Linux — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: bug57031 (87.0% on Linux).
Known: its formulas are runs of Mathematical Alphanumeric Symbols
(𝑆 U+1D446, 𝛼) in Cambria Math; on Linux nothing named draws them, so
they print as missing-glyph boxes and their lines read as nothing
(p2 "Sti±z1−α/2∙seSti", p3 "H0:S1(t)=S2(t)…"). Placement already
matches Word's to 0.3pt.
Built: math faces among the Linux fallbacks; 87.0 -> 87.3%. Its next
parting is p11/p12's two-line "Note:" row (the Windows box's lead
below; parted rows are the Mac's).

### T23. Endnotes are not set — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: endnotes (92.9%), Bug54849 — the two with a real endnote.
Known: endnotes.xml is kept for the save and never drawn. Word sets
them after the body's last paragraph: the separator (a 144pt rule at
426.1 in endnotes' print) and the note ("i XXX", the mark in the
endnote numbering's lowerRoman).
Built (office.md): set after the last paragraph when they fit on its
page. Bug54849 95.7 -> 100%. Left: a superscript's raise (Word's 0.36-
0.37 of the full size, ours 0.3) — endnotes' "i" and its body mark.

### T24. A superscript's raise in Word — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: endnotes, footnotes, table_footnote, Bug54849, bug65649,
form_footnotes (every note mark).
Known: Word's prints raise a superscript 3.6pt over 10pt text and 4.08
over 11 and 12pt (Calibri and Times alike, 51 marks): 0.355 of the
full size within the 0.24pt raster. Ours raise it 0.3 of it, as
measured on PowerPoint's page.
Built: 0.355 under Word's rules; marks within 0.07-0.26pt. Still
open: endnotes' body paragraph holding its mark stands 1.6pt low.

### T25. A paragraph holding a note mark stands low — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: endnotes (its "A pendant worn…" paragraph, 1.6pt low).
Known: a superscript run makes the paragraph's runs unequal, so it
gets no strut and no baseline correction (`_inkShift`): the engine's
even share of the 1.15 multiple's extra stands its lines low; the
paragraph's height is right (the next one is in place).
Built: such a paragraph takes the correction; within 0.2pt, no score
moved anywhere.

### T26. PageSpecificHeadFoot: a footer's floating table — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: PageSpecificHeadFoot (p2's footer, the Windows box's lead).
Known: the footer's page-number table floats (`w:tblpY` 1 twip, anchored
to the text); Word lays it over the footer's line, which stands where it
would with no table. Ours laid the table in the flow above the line.
Built: in a header or footer such a table takes no room; 90 -> 100%.

### T27. tika-3388: an icon's caption in empty boxes — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: tika-3388 (an attachment icon's EMF caption in MS Gothic).
Built: a metafile's text takes the documents' fallback faces; 50 -> 100%.
Looked at and left the same night: 60329 (0%) is Word printing a
landscape-sized page with no `w:orient` onto portrait paper, its sides
cut (office.md, "one attribute: landscape"): a print artifact, not a
layout to copy. rtl (0%) is Arabic in Times New Roman, which this box
has no face for, and our PDF writes right-to-left runs in visual order
where Word's reads in logical order, so no line matches by its text.

### T28. drawing: a block's margins under a banner — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (p15, an article 4.4pt high).
Built: a paragraph naming an HTML block (`w:divId`) takes the block's
top and bottom margins; 82.5 -> 86.7%. Still off: p9-p11 (the "Cbonds"
article, tables nested three deep: T9's limit) and p1.

### T29. A cell's paragraphs share their spacing — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (p1, two headings in a cell 3pt apart too far).
Built: between paragraphs of one cell, the larger of the space after and
the space before alone, as in the body. Five documents up, zh-06c46ba9
down 2.3 (its drift from p41 on lands differently; see office.md).

### T30. Bug51170: the footer's page number at the wrong side — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: Bug51170 (every page's footer), zh-457a8d62.
Built: a floating frame of no stated width is set at the side it is
aligned to; both 100%.

### T31. A merged cell centred over rows that part across pages — DONE (2026-10-16)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-16
(taken at the Linux session's request).
Documents: zh-91e44bcb p4 ("三、本年度办理结果" 21pt low), zh-84702a67
p8 ("是否存在转包、挂靠行为", continued from p7), zh-90e0cea8 p8 (the
"行政审批各阶段帮办服务内容" column 8.6pt low: half a row), zh-1a3c7aa0
p19.
Known: a vMerge cell with vAlign center whose rows go over a page break
is centred by Word in the part on each page. Ours lifts the text by
half of what the rows left behind would give (`lift` in the paging).
Progress (Windows): 00c7eb5f (rows counted with their rules:
zh-90e0cea8 93.8 -> 96.6), f890c12b (a row of no cells of its own takes
no room — zh-84702a67 from 95pt off to 5; the part of a row that parts
inside the span is counted — zh-abe7e063 -> 100).
Then (Windows, this commit): the span's last row counts its part too,
unless its stated height has no room — zh-6cd1befe's last row
"重污染天气事件" (at least 43.65pt, 33 left) goes over whole, so gives
nothing; zh-91e44bcb 96.4 -> 97.1. And a parting row's centred cells
give the part their own height (zh-84702a67 98.2 -> 100). All four
documents' merged cells now stand where Word's do; zh-1a3c7aa0 p19 is
the parted rows' (its row's part runs to the foot), not this.

### T32. A line parted after a stroke before a Cyrillic letter — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: bug65649 (p69's "ИО102-20/А2М"), form_footnotes.
Built: no break after "/" (and "?", "!", "|", closing brackets) before
any non-East-Asian letter or digit. bug65649 99.8%, form_footnotes 97.7.
Next in bug65649: p122, its lines 3-4pt under Word's from "сотрудниками
объекта единовременно." on (not looked into).

### T33. bug65649: a list number's size sets its line's height above only — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: bug65649 (p122's "3.1.x." paragraphs, 14pt numbers over
12pt text).
Known: Word's first line of such a paragraph stands 15.72 under the
line above (the 14pt number's height above the baseline) and the next
line 13.8 under it (the 12pt text's depth below). Ours makes the first
line a whole 14pt line (b879226a's zero-width space), 0.45pt deeper:
each numbered paragraph adds that, 3pt by the page's foot.
Built: the number's height above the baseline only, off a line grid;
p122 within 0.2pt. Next in bug65649: p123, around "3.2.1.2." (not
looked into).

### T34. bug65649: a list number's tab passes the paragraph's own stops — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: bug65649 (p123's "3.2.1.x." paragraphs).
Known: a level-4 number ("3.2.1.3.", first-line indent 567, no hanging)
ends at 67.6pt; the paragraph has stops at 284, 709, 1134 and 1843 twips.
Word starts the text at the 1843 stop (177.1pt); ours went to the next
default stop (155.9), and the line held a word more than Word's.
Built: with no hanging indent, the paragraph's next stop past the
number, however far; bug65649 99.9%. Next there: p132, a form of
underscore lines a line higher in ours (not looked into).

### T35. bug65649: a body word wider than the line opens a line of its own — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: bug65649 (p132, "Замечания: " and 142 underscores).
Known: Word sets "Замечания:" alone and the underscores on the next two
lines; ours parts the underscores right after the label, one line
short. c488db0d does this in cells under 150pt only.
Built: in the body too, off East Asian layout, for words of twenty
characters or more; p132 as Word's. Next in bug65649: p140, a table of
switchgear specifications (not looked into).

### T36. bug59058: Lucida Sans Unicode at its own widths — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: bug59058 (p48's "SEER 9 Incidence…" note, two lines in Word's
print and one in ours; pages 49-52 a line off after it).
Known: Word's PDF embeds the face with /Widths for the 41 characters it
set in it (all digits 632/1000; space 316, hyphen 579; lower case 5-37%
wider than Arial's). The stand-in is Liberation Sans at Arial's widths.
Built: those widths as the face's advances (the rest estimated);
bug59058 92.2 -> 100%, all 52 pages.

### T37. shapes-with-text: a group's text boxes apart from each other — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
(the Mac, which built the stacked case in cabe6fad, offline).
Documents: shapes-with-text (its group: an arrow with text and a text
box under it, two stars without).
Known: only boxes stacked at one width are read whole; here the first
box's text is set at the group's left (79.2pt to Word's 164.6) and the
second's is never read.
Built: each box's text in its own column and from its own top;
shapes-with-text 62.5 -> 100%. Not built: boxes side by side whose
texts overlap in height (they still stack).

### T38. drawing: a line holding only a picture is as tall as its text — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (every article's masthead: p9 and on, 5pt).
Known: the masthead's right cell is tiny pictures and line breaks in
8.5pt Arial — "IMG 0.8x1.5, br, IMG 161x12.8, br, IMG 0.8x2.2". Word's
band is 32pt (three lines of at least the text's 9.8); ours 17, each
line only its picture's height.
Built: a picture alone between breaks, narrower than the line, has its
run's text height; drawing 87.4 -> 89.7%. Still off there: p9-p11's
"Cbonds" article in tables nested four deep (T9's limit).

### T39. drawing: the mark under a flattened nested table takes no room — tried, not kept (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (p8's foot: three cell-end marks under its nested
"Cbonds" tables are 0.5pt lines in Word's print and 10-15pt in ours, and
p9's first empty paragraph goes over).
Known: the rule of 2026-10-15 ("the mark under a nested table takes no
room") covers nested tables kept as a block; the flattened ones' marks
are ordinary paragraphs. Flattened cells now carry their margins and
spacing (the reader), which the earlier try lacked.
Tried: the reader marked the empty paragraph that ends a cell right
after a nested table, and the layout drew no line for it, its spacing
(the flattened cell's margins) kept. Page 9 went from 21pt low to 5pt
high, page 11 from partly right to 15pt off; drawing 89.7 -> 86.8, so
it was taken back out. Word's print sets those marks as lines in a
0.5pt face, 2.2-4.6pt apart with the margins — not nothing; what sets
their size is not known (the paragraphs say Verdana 8.5). A lab with
Word would settle it.

### T40. zh-06c46ba9 p39: a list heading under a table keeps its space before — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
(T14 is the Mac's; the Mac is offline, and this is one rule of it.)
Documents: zh-06c46ba9 (78.9%; pages 39-46 a line ahead of Word's).
Known: "（二）現況分析" (List Paragraph, numbered, 6pt before,
contextual) under a table whose last paragraph is a List Paragraph
numbered in another list: Word sets it 9pt below the line box (the
table's 3 and its 6), ours 3. Our same-style test holds two numbered
items alike across a cell's edge because their kinds match.
Built: two list items either side of a cell's edge are not alike
(plain neighbours still are). zh-06c46ba9 78.9 -> 89.5%, zh-84702a67
98.2 -> 99.6, zh-abe7e063 98.0 -> 100. Left in zh-06c46ba9: p52-55
(reference lists breaking lines elsewhere; Word starts one with "，"),
p70-72 (T41).

### T41. A paragraph's first-line count in characters replaces its style's hanging one — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: zh-06c46ba9 (p70's division-of-work table, rows 30pt left of
Word's), zh-64044a1d (37 such paragraphs).
Known: style "一" (afb) says hangingChars 200; the cells' paragraphs say
firstLineChars 0 and firstLine 0. The reader keeps both counts, and the
layout reads hangingChars first, so each line hangs two characters out.
Built: naming either count drops both inherited ones; p70's rows at
Word's x. No score moved (the match is by height). Left on p70-72: the
page starts ~80pt higher than Word's, after a group of text boxes on
p69 whose text Word's PDF does not carry (shapes: the Mac's).

### T42. A line of ideographic spaces alone is its mark's line — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: zh-64044a1d (p100, the lead "rows whose cells hold only
U+3000" in the Mac's notes below; costs p100's foot and p101).
Known: reproduced on Linux in a paragraph alone (the table's own style
"．表文", 11pt 標楷體 over Times, on an 18pt line grid): "　" is two
pitches in ours, " " and an empty paragraph one; Word's print sets the
U+3000 rows as the empty ones (18.5). The space rule (spaces set no
line's height) counts U+0020 and tabs only, and U+3000 is set in the
East Asian face, whose 11pt line takes two pitches.
Built: U+3000 counts as a space for the rule, and on a line of spaces
alone is set in the run's Latin face. zh-64044a1d 95.7 -> 97.9%,
zh-90e0cea8 96.0 -> 97.5, zh-84702a67 -> 100, zh-69bbcc3c -> 99.5.
Left in zh-64044a1d: p97's form is a VML text box holding a table, which
the reader skips (tables in text boxes are not read: the only such
document); p17.

### T43. Ruby text (w:ruby) is read, drawn and saved — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: 61470 (0%: "東京" with "とうきょう" over it).
Known: the reader skips `w:ruby` whole, base text and all, so the page
is blank and a save loses it. Word's print: the ruby at its own size
(`w:hps` 11 half-points), its baseline `w:hpsRaise` (20 half-points)
above the base's; the base "東京" spread across the ruby's width
(distributeSpace: 2.75pt between, half that at either end); the line
two pitches of its 18pt grid.
Built (office.md, "Ruby"): read onto the base's style, the base spread,
the line made room, the ruby drawn over it, written back as it came.
61470 0 -> 100%; within 2pt of Word's. Nothing else moved.

### T44. A paragraph's trailing spaces after ideographs take the ideographs' face — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: zh-1563bd74 (the note below; a page long on Linux).
Known: the Mac's lab `hfl` (Word 16, the footer's P2 in the body, four
variants): five trailing spaces after "红河县人民政府发布" in 14pt bold 宋体
make the paragraph no taller (52.56 with them, 52.80 without; 51.12 and
51.36 without the X). Ours sets those spaces in the Latin stand-in
(Liberation Mono), whose depth the line takes: 19.4pt for 18.2.
Built (office.md): those spaces, at a paragraph's end, are set in the
ideographs' face at the stand-in's width. zh-1563bd74 88.6 -> 99.7%,
Word's 29 pages. Spaces within a line left as they were (tried: six
documents collapsed — the line fitting measures them otherwise).

### Note from the Linux dev box (2026-10-16): zh-1563bd74 runs a page long on Linux only — settled by T44
Owner: none — a lead (zh-1563bd74's notes are the Windows box's).
zh-1563bd74 was 88.6% on Linux (30 pages to Word's 29), 99%+ on the Mac. Page
25's last paragraph, an empty exact-28pt line, misses the foot by 0.4pt
in the PDF's units (20 to the point), so "第十章 就业救助" and all after
start a line low. The footer is 0.8pt taller here: its paragraphs are
20.5/38.9/19.2pt on Linux, 20.5/38.1/19.2 on the Mac (measured both
sides). The 0.8 is P2's second line, "红河县人民政府发布" + five spaces in
14pt bold 宋体: 19.4pt where its empty twin (P3) is 18.2. Its ideographs
are drawn by the platform's CJK fallback (Noto Sans CJK on Linux, ascent
1.16 / descent 0.288 em) and its spaces in the Latin stand-in (Liberation
Mono at 5/6, ascent .735 of its line); at one line height of 18.2 each
splits it its own way, and the engine takes the deeper of each side:
14.58 above from the CJK face, 4.82 below from the mono one. The
single-line and on-grid paragraphs already get a strut of the tallest
stretch for this (`_strut(tallest:)`); P2 is two lines (the "X" in 16pt
Calibri, 19.5, on its own) off the grid, so neither applies, and a strut
of its tallest would set both lines at 19.5. What would settle it: a line
of a square face's ideographs with Latin in it, off the grid, in a
paragraph whose other line is taller — Word's height for each line.

### Leads from the Windows box (2026-10-16, measured, not built)
- Lab `ps`: built (a picture wider than its line keeps the break after
  it; before 2013's layout a space after it opens a line) — zh-9c5d0c3f
  p4. Left: ours sets the paragraph under a picture and a space 2.8pt
  lower than under the picture alone in mode 15; Word sets both alike.
- zh-454e2e29 p4: the diagonal header cell's "人數", "官等", "類別" are
  text boxes anchored in the cell (with two `wps` line shapes, not
  drawn): ours 8pt high. Shapes and text boxes — the Mac's.
  (Linux, 2026-10-16, 82e6e51d: drawing groups and lone shapes the
  outline skipped are drawn now — every preset, theme and system
  colours, arrowheads; one of this cell's diagonals shows. The labels'
  8pt is untouched.) Both diagonals draw now; labels: T54.
- zh-1563bd74's footer (for the Linux note under "Note from the Linux dev
  box"): its height is right as ours has it. Lab `ft` (Word for Windows,
  the document's own footer): the page number stands at 112.6 and "红河
  县人民政府发布" at 72.7 whether the FAFAFA "X" (which Word's PDF carries
  no text for) is there or not, 40pt apart — ours 113.2 and 73.7, the X
  on a line of its own. Setting the X and the text as one line made the
  footer a line shorter and moved every page (tried, reverted). The p26
  loss is elsewhere. (Also tried: measuring `w:firstLineChars` by the
  first run of text past an anchored shape, 320pt there as its
  `w:firstLine` says, not our 180 — it cost zh-9dd9ce6d 100 -> 15 and
  zh-1563bd74 88.7 -> 10.5; reverted.)
- chartex: our pages match Word's three now; left are a stock chart
  (`c:stockChart`, drawn as a grey box) and the two `cx` charts, whose
  fallback pictures carry no text for the line match. 61745: a bar
  chart's category labels step 59.3pt to Word's 57.7 (plot area).

### T32. A parted row's part on its page: its height and its centred cells
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-16
(the Mac's parted rows; the Mac sessions are offline and the Linux box
asked — Mac, say so here and I stop).
Documents: zh-15728c84 p3 (row 9), zh-1a3c7aa0 p22 (row 65), p32 (row
111) — see the parted-row notes under "Note from the Windows box
(2026-10-15, night)".
Known: Word's part ends under the last line kept on the page and is no
shorter than the row's stated height; centred cells stand centred in it.
Progress (Windows): the centred cells now stand so (zh-15728c84 96.0 ->
98.5). Left: the part's rule still runs to the page's foot, and
zh-1a3c7aa0 p22/p32 (their rows' heights there).
2026-10-16 (a980bef8): the part's rules end with it, and merged centred
cells beside it centre over a part no shorter than the row's stated
height — zh-91e44bcb 97.1 -> 100 — except where a cell merged down from
above runs its text below the part (zh-e6d54ae4). Left: zh-1a3c7aa0
p22/p32.
zh-1a3c7aa0 p57 (row 170, every cell centred, "限制新建氟化氢…" 3 lines
of 31.2 parted 2+1): Word's part is 70.8 to the body's foot, 重点监管…
(2 lines, whole) 4.2 down, "170" centred, and the cut cell's 2 lines
8.4 down — at the part's bottom, as if centred over both parts (p58's
part 39.6 = 31.2 + 8.4). Ours: part 62.65, the cut cell at the top.
Tried "a centred cell that parts: part to the foot, its lines at the
bottom": p57 unchanged and zh-1a3c7aa0 (13 pages), zh-15728c84 p3,
zh-91e44bcb, zh-84702a67 worse — reverted, not the rule.
zh-4d143b5e (the Mac's second sample, its lead): a row parting under
centred cells merged down over six rows went over whole; a merged cell
now parts from its text's start as a cell of its own row does — 36.5 ->
99.8.
zh-f59a76e9 p17 (98.4%, second sample), measured and left: Word parts
row 70 ("A090370 政府举办的公益性人才交流活动的组织与实施服务") at page 17's
foot, its band 158.0 -> 100.7 there and "服务"/"组织与实施" opening page
18; ours sets row 70 whole (157.9 -> 128.5) and parts row 71 under it
with nothing of it on page 17, so the merged "基本公共服务事项" and
"人才服务类" centre over a span 28pt shorter and stand 11.5pt high.
Which row Word parts there is the open question.
2026-10-17 (Windows): a centred merged cell whose text overflows its part
on the page now centres the lines that fit in that part (zh-6d1afa56 p25,
five of nine lines 4.4 down). zh-6d1afa56 99.0 -> 99.6, zh-f59a76e9 98.4 ->
99.4, zh-a4b0f6ea 99.4 -> 100. Note that a single row that parts is another
case: zh-1a3c7aa0 p57's cut cell stands at the part's foot (above).
2026-10-17 (Windows, labs `t32c`): a whole-set centred cell beside a parted
row centres in a part no shorter than the row's stated height or its own
height (zh-15728c84 p8, 4.6 down a part of 81.3): zh-15728c84 98.5 -> 100,
zh-1a3c7aa0 98.1 -> 99.8.

Note from the Mac (2026-10-16): zh-799c91cd 96.8 -> 95.6 between the
n225 and n230 sweeps. Page 6's table, whose last row runs to the foot,
now ends at 84.8pt above the page edge where it ended at 85.0. The
empty paragraph after it (one space, 12pt 標楷體) no longer fits under
it and opens page 7 instead, setting all of page 7 14pt low. Word keeps
it on page 6. Reverting 8cc05b33 changes nothing. Of the commits in that
window this is a parting row's height, so 10a54e42 or 94ac7235 is the
likely one; not bisected.
### T43. bug57031 p11: a SAS table runs 2.7pt short, a "Note:" row parts — DONE (2026-10-16)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, has Word), from 2026-10-16
Built: a separated table (cell spacing stated, 0 too) is framed by its
own top and bottom lines, and the frame takes room, even where every cell
turns its sides off (`frame` in the cell geometry). bug57031 87.0 -> 94.1;
nothing else moved.
Documents: bug57031 (87.0%). Known (office.md, leads of 2026-10-15): the
gaps between its stacked HTML tables run short, not its rows (Word's rows
alternate 21.1/21.4, ours 21.3); by the foot of p11 ours has room for one
line of the two-line "Note:" row that Word carries whole to p12.

### T44. zh-a4b0f6ea p20: a page-anchored floating table Word breaks after its first row — DONE (2026-10-17)
Owner: the Windows box (011ZXp8e), from 2026-10-17 — released by 01Xgpbk5; was with zh-6cd1befe p51 (a 26-row
page-anchored table: Word sets its header row alone on p51, the rest on p52; found by starling-bd)
Built (partial): a page-anchored table (`TableStyle.pageAnchored`) that
does not fit whole where it stands keeps its first row there and goes on
at the next page's head — zh-6cd1befe's p51/p52 now part where Word's do;
no score moved (its title and header stand ~20pt higher than Word's,
which sets the table at its tblpY, and its p52 rows run 30pt to Word's
25). zh-a4b0f6ea is untouched: its table fits whole in ours, and the
paragraph before it (labs fa-fd) is what makes Word part it. Open: the
table at its tblpY; that paragraph's part.
Labs `fa`–`fd` (the document's last section alone, Word 16): as is, page 1
holds the header row and "单位（盖章）" below it, the rest on page 2 —
reproduced. Without the "单位（盖章）" paragraph that stands before the
table, the whole table stays on page 1; anchored to the text instead of
the page, likewise; without its merged cells, the same split. So the
paragraph before a page-anchored table (which the table overlaps, and
which Word sets under the table's first row) is what makes Word part it
there — the mechanism is not found.
Documents: zh-a4b0f6ea (88.6%). Known: `tblpPr vertAnchor="page"`; Word
prints only the header row on p20 and the rest on p21, with the text
under the table still on p20.
Built (2026-10-16, labs `fa2`–`fd2`: the roster's title, "单位（盖章）" and
the table alone, its tblpY 3668, 6000, 1800, and without the line): a
page-anchored table now stands at its tblpY (`TableStyle.pageOffsetY`),
and body paragraphs before it on the page that reach into it are set
again under it — Word's `fc2` (tblpY at the margin) has the title and the
line under the table; `fa2` keeps them above (header "姓" at 228, ours 229).
zh-a4b0f6ea 88.6 -> 88.9 ("单位（盖章）" now at 423 as Word's), zh-6cd1befe
97.8 -> 98.2; nothing else moved. Still open: Word parting the roster
after its header row on p20 (ours keeps it whole and runs past the foot).
Windows box, 2026-10-17 (taken over from the Mac): labs `t44/A`-`I` (Word
for Windows, the 附件5 page alone in its landscape section, the
document's package) reproduce the split: row 0 at tblpY (its text at
195.9 from the top), rows 1-4 on page 2, "单位（盖章）" at 438.0. Without
"单位（盖章）" before the table (B), or with it moved after (C), the
whole table stays on page 1 — and in B it stands 41.9pt BELOW its tblpY
(row 0's text 237.8); with tblpY 5000 (H) likewise 41.9 below (304.4,
for 262.4), the notes after it flowing above it. The paragraphs after
the table change nothing (F: none, G: two). "单位（盖章）" at 438.0 is
12.75 under where the whole table would end plus the same 41.9 — as if
Word counted the table 41.9pt taller than its rows (0.85 header
distance?) and, with the paragraph to set under it, found no room.
Not built.
Correction and DONE (Windows box, 2026-10-17): there is no 41.9. The table
stands at its tblpY in every lab. In B and H the merged-down centred cells
were centred over rows 0-1, which moved their text, and that was all.
Word sets "单位（盖章）" where the whole table would end (442). It then
takes the table up again under that line, where row 0 fits and the 66pt
row 1 does not. Built: at a page-anchored table's first rows, the whole
table plus the text set under it plus row 1 is tested against the foot.
If it fails, the text stays under where the whole table would end, the
table goes on at the next page's head, and row 0's centred merged cells
are set in row 0 alone. zh-a4b0f6ea 89.0 -> 99.4; nothing else moved.
Left: two of row 0's merged cells sit 3.9pt lower in Word.

### T50. drawing: the mark under a nested table at half a point, a short picture's line its mark's — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (p8's foot, p9-11: 85 lines).
Known: Word's print (clipped text kept) holds exactly five spans of
0.48pt — Verdana four, Arial one — and the file has exactly five empty
paragraphs that end a cell right after a nested table (their marks say
8.5pt). So Word sets those marks at half a point, not at nothing (T39's
try, which overshot) and not at their size (ours). Plan: the reader
flags such a paragraph (layout only, not saved), the layout sets its
line at 0.5pt; the flattened cells' margins stay.
Built (office.md): the marks at half a point, and — what that uncovered
at page 9's top, settled by the Mac's lab t50 — a paragraph of a picture
shorter than its mark's single line takes that line, the picture at its
foot. drawing 89.7 -> 98.1%; nothing else moved. Left: p11's 16 lines.

### T51. Space shared across a hidden paragraph — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (p11's last 16 lines, 12pt low from "ИА Regnum").
Known: between "…ОАО "ПО Водоканал г. Ростова-на-Дону"." ("text": 14pt
after, auto) and the heading "ИА Regnum" (12pt before) stands an empty
paragraph whose mark is hidden. Ours hides it, but the space after and
the space before no longer share across it: ours 40.75 baseline to
baseline, Word's 28.8.
Built (38a62adb): the space a paragraph shares is the nearest shown
paragraph's above it. drawing 98.1 -> 100%; nothing else moved.

### T52. Print markup as Word does: comment and change balloons in the margin — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16 — the user's call: keep Word's behaviour
Documents: 58067, Tika-792, delins, comment, testComment, WordWithAttachments
(all near 0%: Word's references are prints with markup).
Known (the Windows box's note below): the page drawn at a scale k, 8.3pt
from the paper's left, a grey balloon pane ~188pt wide ending ~18pt
from the paper's right (letter k 0.729, pane 407.5-594.5; A4 k 0.7367,
pane 387.0-576.6), centred top to bottom; balloons "Commented [s1]: …",
"Deleted: …", "Formatted: …" in ~6.5pt, level with their anchors.
Built (office.md): the frame, comment, deletion and formatting balloons,
deleted text out of the page. comment, testComment, 58067 -> 100%,
delins 23.3, WordWithAttachments 23.7 (their bodies' own layout now
shows: delins's lists, WWA's header and table). Not built: moves
(Tika-792), "Field Code Changed", change bars.

### T54. zh-454e2e29 p4: a diagonal header cell's text-box labels 8pt high — DONE (2026-10-16)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac, has Word), from 2026-10-16
Documents: zh-454e2e29 (95.3%). "人數", "官等", "類別" are text boxes
anchored in the cell, beside two `wps` diagonal lines.
Built: a floating text box's text takes the document's line grid, as
Word's does (not `w:combine` text, a box in the line). Labels within
0.4pt of Word's; no score moved (the line match groups that row alike).
Linux built the same at the same time; merged as each box's own section's
grid (zh-6cd1befe's flow chart is in a section of none) and inline boxes
too. On Linux zh-454e2e29 94.8 -> 96.7%; nothing else moved.

### T55. Web spacing between two lists (numbered T53, then T54, at first; the Mac's came first) — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: delins (its body under the markup).
Known: delins's bullets are web-spaced (before/after 100 with
beforeAutospacing/afterAutospacing). "A name in various Indian
languages…" (numId 1) and the nested "the subcommentaries…" (numId 2)
stand 19.1pt apart in Word's print (scaled; 27.6 unscaled), 10.3 in ours:
Word gives 14pt between items of two lists, ours none, the two being the
same kind. The same after a list's last item under a paragraph of none.
Built: one list is one numbering (listId) where the file names it; an
item's automatic space after is none only before an item of its own
list. bug57031 94.4 -> 100%, delins 23.3 -> 35.0; nothing else moved.

### T56. A Symbol bullet's line at the bullet's own size — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: delins (each bullet's first line 1.5pt taller than Word's).
Known: the level's face reaches a list line through a zero-width space
in it (form_footnotes' Symbol bullets, 12.24pt lines under 10pt text);
that space takes the text's size, not the level's: delins's 10pt Symbol
bullets under 12pt Times make a 14.7pt line where Word's is 13.8.
Built: at the level's own size where it says one. delins 35 -> 50%;
nothing else moved.

### T57. zh-90e0cea8 p1: the standard's cover — its "37" logo frame and ICS/CCS lines — measured, released
Owner: none — released by 011ZXp8eXomzYegGkuu7484P (Windows box), 2026-10-16 (handed over by the Mac, 011uWpmC)
Documents: zh-90e0cea8 (p1: 5 of 10 lines).
Known: 9c6cc3ca (margin-anchored frames at their y) and 7d14992b (a frame
naming a y and no anchor is on the margin) put the cover in Word's order.
Left: "ICS"/"CCS" (a page frame at y 568 twips, style "header" on Normal's
exact 20pt line) stand 7.6pt high, baseline 30.55 against Word's 38.16;
"37" (framePr yAlign="inline", vAnchor margin, hAnchor text, w=0, over a
style frame at the margin's x 6748 y 171; a logo picture and 54.6pt bold
"37") 33pt low, 122.0 against 88.56, Word's logo at y 57-88; the title
4pt low; "发布" 4pt low.

Labs `cov/cA`-`cF` (Windows box: the cover's first 4, 5, 6 and 10
paragraphs in the document's own package, its first section; top margin
-338, 338 and 1440 twips): Word for Windows sets ICS, 03.080, CCS and
"A 12" on four lines (38.16, 51.0, 65.76, 80.76) whatever the margin —
not the Mac print's two ("ICS 03.080" at 38.16, "CCS A 12" at 54.0) —
and moves "37" with what follows it (128.5, 198.4, 249.1). Ours sets the
labs' four lines within 0.8-3.1pt of Windows Word's, but in the whole
document joins them in twos and sets them 7.6pt high. Word for Windows
and for Mac disagree on this cover, so a Windows lab cannot settle it;
needs the Mac's Word.
### Note from the Mac (2026-10-16 night): the zh corpus is 88 documents now
12fef482 adds a second seeded sample of 20 zh documents, with Word's
prints. It started at 74.5% of Word's lines, against the first 68's 98%,
so new gaps are there. A sweep's zh mean is not comparable across that
commit; compare per document. Being worked: zh-4d143b5e's merged-cell
row parting (Windows, T32), zh-2a241df1's charts (Mac, T59).
- zh-3c055c9b (44.9%, mode 15, linesAndChars grid of 17.0pt at 16pt,
  zh-TW, compressPunctuation, the body style's `w:kern` 0): p2's line
  "第2頁】，於113年4月29日辭職【附件2，第5" takes "頁】，" in Word's print,
  33.7pt over by our measure. Word squeezes marks all along the line
  (職→【 11.7, 】→，9.0, ，→於 14.3; an ideograph is 17.0). Ours: "need
  33.68 room 74.4 of 6 marks taken false". The mode-15 test's stretch
  term counts the line's ten or so digit autospaces whole, and that
  fails it. Tried and reverted (Mac): (1) closing up mark pairs without
  `w:kern` (zh-3c055c9b 44.9 -> 61.7, but zh-17749c13 85.6 -> 53.7 and
  nine others down); (2) leaving the autospaces out of the stretch on a
  character grid (zh-3c055c9b -> 13.1). Released: it is the grid
  fitting the Linux session built. A lab of this line, with the over
  varied, would say what Word counts.
  Lab (Mac, 2026-10-17, lab/tools/squeezelab2.py on its own package,
  Normal 16, left, cells of 17.01): with no mark, or one lone "，", Word
  takes nothing over (0.00-0.13); with a "】，" pair 8.07-8.20, half an em.
  So on a positive grid a lone comma gives nothing — unlike the negative
  grids, where it gives half a cell. Word's page-2 lines end at 523.6, the
  end of exactly 26 cells, so f57bbe07's whole-cell width would not move it.
  The real line's squeeze ("職→【" 11.7, "】→，" 9.0, "，→於" 14.3) closes
  more than the pair: what the rest of that line lends is still to find.
  Lab `ab3c` (Mac, 2026-10-17, `lab/tools/abthresh.py`: the real line
  "第2頁】，於113年4月29日辭職【附件2，第5頁】，" alone in style 11 at a
  bisected left indent, Word's threshold against ours on the same files):
  Word keeps "頁】，" up to an indent of 694 twips, ours to 605 — Word
  goes 4.45pt further (about 34.4pt over by our natural widths, ours
  stops near 29.9). At its limit Word's print squeezes every mark by one
  share of its half em, 0.645: each "】" 5.48, "【" 5.49 (its left), each
  centred "，" 2.74 a side; the digits' automatic spaces are set whole
  (第 21.26, 2 14.14, as ours). Ours: "need 33.68 room 74.4 of 6 marks
  taken false" at 680 — the mode-15 test's stretch term with the ten
  autospaces whole stops it at ~30.8 by its own sum; without them it
  would take to ~45. So Word weighs them part-way, or caps the share; the
  lab files (ab3c_*.docx, both sides' PDFs) are there to vary it. Not
  built — handed to the grid fitting's owner.
  Variants (lenovo-3's H1/H2, same lab): (a) the digits as ideographs, no
  autospaces — Word 227 twips, ours 225, over 45.36 with room 51.02: we
  match; (b) "8時9分" added, four autospaces more — Word -778, ours -857,
  over 31.58 at Word's limit, room 82.91. So the marks are counted right
  and the autospaces over-weighted in the mode-15 stretch term (H1);
  a fixed share (H2) does not fit (45.4 vs 34.4 vs 31.6).

### T62. A table nested in a parting row parts between its rows — DONE (2026-10-16)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac), from 2026-10-16
Documents: zh-d35cbbdb (55.4%, second sample). Its body is one cell of a
page-long layout table; the consent table nested in it starts at page
4's foot. Word sets its header row there and the rest on page 5; ours
took the nested table over whole (a nested table is one block to the
row's cuts), and every page after ran a block behind.
DONE: a nested table's row bottoms are cuts of its cell (`cellCuts`):
zh-d35cbbdb 55.4 -> 88.9, nothing else moved. Left: the header's "項目",
merged down into row 2 and centred over both, is not drawn on page 4
(Word's is, at the row's middle).
Lead (2026-10-17, now 89.3%): page 9's part of the page-long row. Word ends
it at the rule 743.8, after "公尺長)，考量UB…設站" (baseline 737.3); ours sets
"行空間。" too (761.0) and ends at 767.1, the foot 770 (bottom 1440). The
cell's paragraph is exact 25pt (lines print 24 apart in both), 14pt 標楷體,
hanging indent; table margins default. Every page after runs a line ahead.
What Word keeps for the parted row below its last line is the question —
T32's ground (Windows).
Measured (Windows box, 2026-10-17): nothing is kept below the line. Word's
footer (page number and an empty paragraph, Calibri 10pt, 12.24 apart, foot
at 792.4) tops at about 767.98; its fourth line would end at 761.28 + 6.0
with the 0.48 rule under it, 768.24 — over by 0.26pt. Ours ends at 767.15,
0.6 higher, all of it spread across the page in under-a-quarter-point
pieces: lines 0.22 high by 664, the row rule 6.33 under the baseline to
Word's 6.48, the next row's first baseline 18.28 under it to 18.48 (Word's
bold YaHei line sits 0.48 lower in a line of the same 24.2). It is the
0.24pt raster (see the Linux box's scale-30 note, which turns it to 100).
Released.

### Footer trailing spaces in a right-aligned paragraph (zh-c5b5087b, zh-9dd9ce6d) — measured, released (Mac)
Both footers share zh-1563bd74's build: a page-number box on an empty
first paragraph indented past the column, then a right-aligned (`wordWrap`
0) paragraph of an invisible FAFAFA "X" or "嘉" with spaces, the publisher's
name, and five trailing spaces, then an empty paragraph. Measured from
Word's prints: in a right-aligned paragraph trailing spaces take room.
zh-9dd9ce6d's second line, two leading 8pt spaces, "嘉峪关市人民政府发布"
(14.25 a character) and five trailing spaces, is 201.3pt of its 202.85
and stays one line. zh-c5b5087b's thirteen characters with five spaces
do not fit: four spaces go to a line of their own, the text stands 14.5pt
left of the margin, and the page number 18pt higher (Word 128.7, ours
110.8). Tried (Mac): a word joiner after a right-aligned paragraph's
trailing spaces, so the engine gives them room and wraps what does not
fit. zh-c5b5087b 84.7 -> 94.4, but zh-9dd9ce6d 100 -> 89.9: ours wraps
its last space, so our line is a few points wider than Word's 201.3.
Our natural width of that paragraph traces as 421pt, where its glyphs
come to about 200, so something unseen is counted. Find that first,
then the joiner is the fix. Released.
Found and built (01Xgpbk5, Mac, 6a5f56b7): the unseen width was the
trailing spaces themselves — set in the ideographs' face (kind -2), their
spacing carries the stand-in's width, and the half-em rule counted it
twice (13.3pt each, Word's 7.15). With that, the joiner holds: page
numbers 713.0 (Word 713.3), 728.6 (729.4), 727.3 (727.9). It replaces
19599caf's held spaces (Linux, 017F2), which held on Linux but on the Mac
set these footers a point taller and cost zh-c5b5087b and zh-1563bd74 a
page each. Mac: zh-c5b5087b 28.6 -> 94.4, zh-1563bd74 88.9 -> 100.
Awaiting a Linux sweep of 6a5f56b7.
Built (Linux, 19599caf, at the same time): the trailing spaces after an
ideograph in a right-aligned paragraph set as held (no-break) spaces,
each after a zero-width break, at a space's width set outright (the
unseen width was the held spaces' spacing counted twice, and an ideograph
face's no-break space being an em), the breaks in the ideographs' style
so a line of spaces alone is a text line. zh-c5b5087b 83.7 -> 93.9 (its
footer within 0.6pt of Word's), zh-9dd9ce6d unchanged at 99.6 and still
one line (its "嘉峪关…" 17pt right of Word's now, 52 before: the two
leading spaces and the "嘉" Word keeps on that line are left), zh-1563bd74
100 with its text within 1pt. Not after Latin text (zh-7dc3afad's
right-aligned figures hang their space in Word's print).

### Note from the Mac (2026-10-17): Word's 楷体_GB2312 changed between the two samples
A fresh print of zh-78729cf9 today (Word 16.113.3 / 26092714, macOS 27.0
26A428, the same OS build as both samples' PDFs) sets all its 楷体_GB2312
text in Microsoft YaHei. The corpus print of 2026-10-12 has 545
characters of it in KaiTi. So the first 68's KaiTi was Word's state then,
perhaps a cloud font it had downloaded. The second sample (2026-10-17)
reflects today's Word: YaHei. One rule cannot match both; reprinting
the first sample is the user's call and has not been done.

**Reprinted (Mac, 2026-10-17).** All 68 of the first sample's prints
were redone with Word 16.113.3. That commit changes references only. Old
KaiTi is YaHei in every print that had it, and zh-64044a1d also lost
STHeiti. Same build, scored on the Mac against old and new references:
zh 95.6 -> 95.4, 73 -> 71 at 95% or more. Five documents moved:
- zh-15728c84: 98.0 -> 86.4
- zh-232090e0: 97.8 -> 90.5
- zh-37b6536f: 97.7 -> 96.9
- zh-64044a1d: 97.1 -> 97.0
- zh-69bbcc3c: 99.1 -> 99.0

The OfficeFonts mac rule 楷体_GB2312 -> KaiTi now goes to YaHei; that
change is lenovo-3's (Linux).

### Leads from the second sample (Windows box, 2026-10-17)
Done here: zh-4d143b5e 36.5 -> 99.8 (6ef30c71), zh-b13d0fb4 93.5 -> 100
(b9952df9). Later the same day: zh-a4b0f6ea 89.0 -> 99.4 (T44), zh-2a241df1
94.3 -> 97.1 (data table baselines), zh-78729cf9 -> 100 (Roman numerals),
zh-64044a1d 97.8 -> 99.0 (a table in a text box; exact rows), chartex 76.4
-> 77.8 (a picture list item's bullet). Measured and left:
- zh-799c91cd p7: YaHei 12pt lines are 20.6pt in ours (skparagraph
  rounds each line to the layout's 1/20pt) and 20.586 in Word. Over 22
  lines and a ruled row, the empty line under page 6's table is 0.15pt
  over the foot, where Word's fits by 0.3. The rounding note under T16.
- zh-2a241df1 p1: chart 1 stands 2.2pt low (an inline chart in a 15.6pt
  grid line: where in the line Word puts it is not known; chart 2 is
  right). Its title's two misses are the faces' bbox bottoms: SimHei in
  Word's print, YaHei Bold in ours, the characters within 0.4pt.
- zh-454e2e29 p1/p4/p5: every position within 0.3pt; the matcher groups
  pieces whose bbox bottoms differ by face (Times against Liberation).
- zh-64044a1d p30: a line holding a Noto compatibility ideograph carries
  our word joiner (the `cj2` height), which the PDF extracts as a 30.4pt
  space; its bbox moves the matcher's line bottom 3-5pt. Baselines are
  within 1.3pt. p93-95: glyphs clipped inside exact rows, which Word's
  PDF keeps and ours drops (the zh-6600d539 note).
- zh-64044a1d p58: compat 11, compressPunctuation. Word sets "工程 (搶救、
  搶修 )開口合約廠" unsqueezed (12.32 a cell); ours squeezes "、" to 8.2
  and takes "商，" too. The spaces before the brackets are 6pt each in
  ours. Squeeze ground: left to whoever holds it.
- zh-c5b5087b p6-9 (95.4%), the same shape: mode 14, compressPunctuation,
  no character grid, the body paragraphs `w:kinsoku` 0, justified, 16pt
  仿宋_GB2312 (YaHei), Normal's `w:kern` 0. Word sets "…损耗损失，" (25
  cells, 16.43 apart) and starts the next line with "由"; ours squeezes the
  "，" 5.76pt (0.36 em) to take "由". Its next line in ours squeezes two
  commas 2.9pt each for two characters more. Word squeezes nothing on
  these lines. Data for the kinsoku-off note above (zh-799c91cd p2).
  Labs `k0` (Windows box, Word for Windows, that paragraph in its own
  package): as is, kinsoku on (B), and run kerning on (D) all leave "由"
  for the next line; the run's `w:eastAsia` zh-CN (C), or just the "，"'s
  (I), squeeze it 5.8pt and take it; a zh-CN run at the paragraph's end
  (E), or on "并用" inside line 2 (G), or on its first character (H) do
  not. But Word for Windows does not squeeze article 1's first line (J)
  either, which the Mac's print does, so the Windows labs do not settle
  the prints. In the Mac's print, page 3 alone: "，" squeezes on lines
  with no zh-CN text ("理的行政部门，应不断完善制度，明确责任，规范管理，
  确保县", four at 1.43 each; "息、费用等补贴，并对…；县农业发展银行"),
  while page 6's two-comma line and page 7's "…应急预案，依据事态的" /
  "发" are not squeezed. Tried and reverted: marks give only in a paragraph
  holding East Asian text (pages 3-10 broke); only the CJK block's marks
  outside it; a "，" giving for itself only (page 6 right, 7-9 as before);
  per line (pages 3-5 broke). The rule is not found.
- delins balloons: Word's one-line balloons step 10.46pt (scaled), ours
  10.0. Pinning the line to Tahoma's 1.2075 em made ours 10.7 and set
  the deletion balloon 11pt low (delins 45 -> 37 lines of 60); reverted.
- chartex's sunburst: Word sets its labels turned along the radius and
  wrapped mid-word ("Branc" / "h 1"), and leaves the small segments
  unlabelled. Built 2026-10-22 (T143c, see office.md).
- zh-6cd1befe p49-50 (99.5%): body text wraps round the footer's framed
  page number. The footer is a `w:framePr` "— 49 —" (wrap around, vAnchor
  text, 11.75pt above the footer's empty paragraph, x 451pt). On page 49
  Word sets the note "3.随着…" at 778.1, beside the frame, its line ending
  at 451.9 where the frame begins, and the rest of it on page 50. On page
  48 a table row that would end beside the number goes over whole (rows
  do not wrap). `_bodyInsets` raises the whole body's foot by the frame's
  rise, which is right for the row and costs page 49 that line. The build:
  page-level wrap bands for a footer's wrapping frames, which body lines
  narrow round and rows clear. Not built.
- zh-c6ab068c p5 (99.3%, third sample): "…经批准后予以公开。" ends in a
  no-break space (U+00A0). Word squeezes the line's three marks 1.44pt
  each to keep "开。" on it; ours sends "开。" down. Without the U+00A0,
  ours keeps it unsqueezed. The engine sets the space an em (7pt and a
  joiner's 7), while the fitter's piece "开。 " measures 35pt, the probe's
  boxes showing no more, so it plans no squeeze. Counting to the probe
  line's end did not change the 35. Counting a no-break space inside a
  paragraph twice broke pages 9-10. Reverted; the fitter needs the
  engine's width for a final no-break space.
- zh-7dc3afad p26: "【附錄一】" (12pt 標楷體) then its 20pt title (default
  face) on one line in a landscape section: our baseline 15.1 under the
  margin, Word's 25.6, the title's glyphs over the margin. Lab `ap1` L
  (`甲乙丙丁` 12pt 標楷體 + `戊己庚辛` 20pt default face) reproduces it; with
  the 標楷體 on the 20pt run instead (M), or no font on either (K), the
  line is right. Not the paragraph strut: the single-line strut takes the
  20pt run as the tallest (h 1.30). Not found.
- zh-e02b0479 (68.6%): its form's last row is two 15.6pt grid pitches in
  Word because its text, 楷体_GB2312 10.5pt, is YaHei there (an 18pt
  line); our 楷体 is KaiTi, one pitch, and the merged "所需信息情况" above
  centres 6pt high. The 楷体_GB2312 question above — not to build alone.
- zh-f39e54b6 (94.6%): a one-cell borderless table, tblW 8820 on a text
  width of 8306 (mode 14, tblInd 108, the cell 5000 pct): its lines end
  at 524.5pt in Word's print, 531.0 in ours (the left edges agree, 146.6
  and 146.7), so ours takes a character more on some lines. The rule for
  an over-wide table's right edge in mode 14 is not found. (Lab `sq14`
  on the way: Word takes a character exactly half an em over — 7.0 at
  14pt — and leaves it at 7.05; our legacy squeeze agrees.)
  Linux, 2026-10-17: Word's right edge on page 2's full lines is 530.8,
  ours 531.0, so the over-wide table is not it. The misses are lines on
  the half-em threshold: article 24's first line takes "縣" 6.9993pt over
  in ours (`STARLING_RICHTEXT_FIT`, column 370.0); in Word's print the
  line starts 89.88 (ours 90.0) and ends by 530.8, 0.08pt narrower, so
  its "縣" is ~7.08 over and goes down. Where Word's 0.12 and 0.2 come
  from (twips rounding of the cell's or the chars-based indents?) is
  what is left.

### zh-f0bd9ea8: punctuation squeeze on a grid narrower than the ems — measured, released (Mac)
Mode 14, linesAndChars charSpace -842 at 16pt (Normal 10.5). Done: the
balanced half-width spaces' grid share (57849075). Left: every body line
takes one character more than Word's ("…工程品" + "牌" 5.1pt over, "，"
the one mark to give). zh-d68ac84a (charSpace -5544) agrees: Word leaves
"增" (7.3 over, one mark), "土" (6.7, one mark) and "50" (11.0, one mark),
and takes "政" (7.3, three marks) and "质" (3.1, five marks). But it
leaves "原" (3.8, two marks). Tried and reverted: no squeeze at all on
such a grid (d68ac84a 98.8 -> 35.4); none for a character or a word
(-> 47.9); none with one mark (d68ac84a -> 93.9, f0bd9ea8 only 53.6 ->
54.3). Lab `cg1`/`cg2` (this package): the grid's -0.21 applies at every
size, and the text's size against Normal's changes nothing. A lab of
one line with one, two and three marks, the over varied, would say what
Word counts on such a grid.
Lab run (Mac, 2026-10-17, ~/starling-word-check/lab/tools/squeezelab.py:
one justified or left line of 仿宋_GB2312 — Word's YaHei — the first 24
characters holding 1, 2 or 3 "，", the over bisected to 0.12pt by the right
margin): on charSpace -842 at 16pt (pitch 15.75) Word takes the 24th only
within 0.12pt, whatever the marks — no squeeze, f0bd9ea8's case; on -5544 at
16pt (pitch 14.65) within 4.0-4.12pt, the same for 1, 2 and 3 marks; on
-5544 at 12pt and -2800 at 16pt, within 0.12. So it is no count of marks:
something of 16pt on the -5544 grid gives about 4pt (3 x the grid's 1.353?
the others do not follow). Not built; free.
Then on zh-d68ac84a's own package (Normal 16pt, its -5544 grid, w:kern 21,
justified): no character runs over beyond 0.12pt with 1 or 3 commas, 1 or 2
"》（" pairs (full cells even in a wide line), a line opening "（", or 1-2
runs of "2023" Latin digits (335.1 for 24 with one). The 4pt above came from
f0bd9ea8's package (its Normal 10.5?). So on these grids Word takes nothing
over: d68ac84a's "政" 7.3 over and "质" 3.1 over are against ours' widths,
not Word's, and ours' squeeze there makes up for widths ours sets wider —
likely the Latin digits and their automatic spaces on the grid. The fix is
those widths; then no squeeze on such a grid. Lab: lab/tools/squeezelab.py
(args docx repo font size marks; env LABJC LABGRID LABMAR LABRPR LABMARK
LABSTART LABTAG). Not built.
CORRECTION (2026-10-17): squeezelab.py's numbers on a character grid are
void — it moved the right margin, and on linesAndChars Word fits the pitch
to the text width, so the threshold tracked the grid's count (hence 0, or 4
in f0bd9ea8's package). Redone with lab/tools/squeezelab2.py: the margins
and pitch fixed, a negative w:ind w:left in twips giving the line room, the
first line filled to N characters plus one, "over" bisected (w:spacing on a
character instead breaks the line apart). Results:
- d68ac84a's -5544 grid (pitch 14.65, N 30): justified, one "，", one "》（"
  or "，，" — each taken within 7.21-7.32 (half a cell); left, one "，" the
  same; no mark 0.
- f0bd9ea8's -842 section (its pgSz and margins, pitch 15.79, N 27), left:
  no mark 5.92-6.05; one "，" 13.82-13.94 (6 + half a cell); "，，" fills 28
  at 15.43, then 5.54-5.67.
So a mark gives half a cell; and a grid has a base tolerance besides (0 on
-5544, ~6 on -842) — perhaps the width's leftover over N cells (436.55 -
27 x 15.79 = 10.2; d68ac84a's is 0). f0bd9ea8's own body lines leave a
character 5.1 over with a "，" all the same, so they differ from the lab
(its runs, style, first-line indent). Handed to starling-bd.
Then (same lab, the pitch fixed at 15.794 from the left-aligned print):
justified changes nothing (no mark 5.92-6.05, one "，" 13.82-13.94);
firstLineChars 200 nothing (5.80-5.92 / 13.70-13.82); two 16pt spaces after
the first three characters nothing (5.80-5.92 / 13.70-13.82). starling-bd's
bisection of the real 第一条 paragraph allows ~3.7 with its one comma — so
something in that line's own content takes the room back (where its comma
stands, the 黑体 run's Latin face, a Latin run), not its alignment, indent
or spaces.
Nor (same lab) the comma's place (after the 14th character: 13.70-13.82)
or the run's rFonts with hint eastAsia and no hAnsi (5.80-5.92 / 13.70-13.82).
Left: the real paragraph's pStyle and its run properties, the text after
"牌", and its length. A bisection that strips the real paragraph a piece at
a time until it reaches the lab's ~13.8 would find it. Released.

### Lead from the Linux box (2026-10-17): zh-06c46ba9 p70-72, a float pushes the table above its anchor — DONE (2026-10-17)
Owner: session 017F2GnT (Linux) built it while the Windows box's claim crossed it (told). Built: a second pagination pass with the float pinned (office.md); zh-06c46ba9 95.5 -> 97.3%, nothing else moved; the table's part stands 2pt high of Word's still. Was: pages 70-72 stand 80pt high (28 lines).
Page 70 opens with the rest of a parted table (row "三、內文格式"), then
"附錄3", then "報告撰擬分工表". The VML box "分工表格式" (wrap square, 95.5
x 23.5, 2.2pt under its paragraph's top, `mso-position-vertical-relative:
text`, x 344pt of the margin) is anchored in the paragraph after the
table. Word's print stands the box where its anchor would be with the
table at the page's head (text baseline 697.8, as ours), then sets the
table's rows UNDER the box (rule at 690.1, ours 769.7) and "附錄3" under
them. So Word places the float first and then moves the content
before its anchor on that page out of its way. Ours keeps floats out of
the paragraphs after their anchor only. Needs a second pass over a page
when a wrapping float lands on content set before its anchor.

### Note from the Linux box (2026-10-17, later): fractional line heights, tried whole-corpus
Measured, not built. skparagraph rounds each line's height to a layout
unit (`InternalLineMetrics::height`, `::round`); a switch that keeps the
fraction (patch kept on the Linux box, off by default, not in the
engine) moved six documents, against the tip with b0b5beab:
- up: zh-e061a08e 94.3 -> 99.8 (the PMingLiU page-foot lead: the Mac's
  1332/1024 em now reaches the foot), zh-d35cbbdb 89.7 -> 100,
  zh-232090e0 95.6 -> 100, zh-6d1afa56 +0.2;
- down: zh-1a3c7aa0 99.7 -> 32.2 (92 pages), bug59058 100 -> 75.4,
  delins 75.0 -> 61.7. Mean 92.5 -> 92.1.

Each loss is a fit that rounding happened to win:
- zh-1a3c7aa0 p13: the "5 O,O-二甲基…" row fits under rounding with no
  room at all (row foot and rule 405.9 of 405.9); with the fraction
  the lines above the table are 0.05 taller and the footer 0.05, and it
  goes over. Ours already stood 0.34pt under Word's at the table's
  head: the 22pt title (方正小标宋_GBK -> YaHei, atLeast 25) is 32.43
  under "附件1" where Word's is 32.16.
- bug59058 p38 (13pt Times as Liberation Serif, MinionPro-It as
  Caladea, atLeast 15): the same 34 lines span 578.64 in Word's print,
  578.35 rounded, 578.90 with the fraction; the page then holds a line
  fewer. The mixed lines (Caladea in them) are the ones that differ.
- delins: the balloons stack by their lines (Word's step 10.46, ours
  10.0 — the Windows box's note above); they move 2-4pt and the
  matcher merges them with body lines.

So the fraction is right where the faces' heights are (the three
Chinese gains), and building it means first fixing what rounding
covered: the title line, the stand-in faces' mixed lines, the balloon
step. An engine change on every platform too (a skparagraph patch
under `patches/`, and a way for Office to turn it on).

### Note from the Linux box (2026-10-17): the export at twice the resolution
Measured, not built. `OFFICE_PDF_SCALE=30` (forty layout steps to the
point, twice the twip) against the default 15, same build, whole corpus:
the mean holds at 92.0; up zh-d35cbbdb 89.7 -> 100 (its p9 foot in a
parted row), zh-799c91cd 98.4 -> 99.6, form_footnotes 97.7 -> 98.9,
zh-9dd9ce6d -> 100, zh-e6d54ae4 +0.3, zh-6d1afa56 and zh-64044a1d +0.1;
down zh-9c5d0c3f 95.9 -> 94.9, zh-d68ac84a 99.8 -> 98.9, zh-8e8d4c40
98.9 -> 98.3, zh-2b955411 and zh-7dc3afad -0.1/-0.2. zh-e061a08e (the
PMingLiU page-foot lead, whose 0.19 twip a line was the reason to try)
does not move. Page feet decided by under a twip a line either way: the
model is Word's own 0.24pt raster, not a finer one.

**More measured and tried (Mac, 2026-10-17).** starling-ios-5c's
`lab/tools/squeezelab.py` (24 ideographs, 1-3 commas, bisected to
0.12pt) found no allowance on these grids:
- f0bd9ea8's grid at 16pt: none;
- d68ac84a's own package, with or without kern 21: none;
- d68ac84a's package with the Latin face Times New Roman, or with "2023"
  opening the line (`lab/sqa`): none either.

The 4pt allowance it first saw came from f0bd9ea8's package (Normal
10.5).

Yet d68ac84a's "府办公厅《…2023年…》（浙政" (p1) breaks as ours does,
glyph for glyph. In Word's print "》（" stands 9.77pt apart and "厅《"
12.21, against a 14.65 pitch. So in that paragraph Word closes the pair
from the start, and the line is never over. The lab's pair kept full
cells, so something in the real paragraph decides it. Untried:
- its exact 30pt line;
- the first-line indent;
- the run's color and kern from Normal, with no rFonts of its own.

Tried and reverted: no squeeze on a negative grid before 2013's layout
unless the line has a closing-opening pair. f0bd9ea8 53.6 -> 84.1,
d68ac84a 98.8 -> 70.3. Ours squeezes d68ac84a's lines into place, so
taking that squeeze away needs the pair's close-up in the natural width
first.

Later (Mac, same day), the real paragraph in Word (starling-ios-5c's g67):
- In a wide line "》（" is a full 14.65pt. So the close-up is a squeeze
  on demand, not a natural width, and the line above corrects itself:
  its 7.32 is "厅《" 2.44 + "》（" 4.88.
- The no-exact-spacing and no-kern variants are the same as the
  original; without the indent the breaks move.

Two rules tried on zh-d68ac84a, and neither holds:
- "Only brackets give": its p2 line "《技" (14.64 over) needs the 。
  too.
- "Marks give only where the line has a bracket" (f0bd9ea8 81.5,
  d68ac84a 72.4): its p2 "10.市本级…辖区内" takes "有" 3.3 over with
  one comma and no bracket.

Neither do brackets or Latin decide it. Word leaves "原" (p16, 3.8 over)
on a line with both, and "增" (p17) on one with digits. So in zh-d68ac84a
commas do give. Only the labs and zh-f0bd9ea8 give nothing, so the
difference between the packages is still not found. Next:
starling-ios-5c's LABRAW lab, with the real runs' rPr (no rFonts).

Correction (2026-10-17): on a linesAndChars grid the pitch is fitted to
the text width, so a lab that moves the right margin moves the pitch.
squeezelab's numbers on character grids, and `lab/sqa`, are void.
starling-ios-5c's squeeze2 (a negative `w:ind w:left` in twips, which
leaves the margins and the pitch alone) gives, left-aligned:
- d68ac84a's grid: no mark 0; one comma, two, or a "》（" pair 7.2-7.3
  (half a cell);
- f0bd9ea8's grid: no mark about 6; one comma 13.9.

Mac, f0bd9ea8's real first paragraph by the same method (`lab/f0b/bis.py`):
"第一条" in 黑体, two 16pt spaces, justified, firstLineChars 200, one
comma on the line. "牌" is 5.71 over by our natural widths (15.794 a
cell; Word's unjustified last line steps 15.794 too). Word takes it
from a 2.00pt shift and not at 1.85, so it allows about 3.7pt on that
line, against the lab's 13.9. 黑体 or 仿宋 for 第一条 changes nothing.

So the lab and the real paragraph still disagree. Untried variables:
- justification (the labs were left-aligned);
- the first-line indent;
- the two spaces as givers.

Ours leaves "牌" here as well, with the line's comma not counted (room
0). In the corpus document ours takes it, so the paragraph's context
there differs from this lab copy. Not taken further.

Later the same day, starling-ios-5c ran squeeze2 justified on that grid
at a fixed pitch. No mark gives about 5.9 and one comma 13.8,
regardless of justification, firstLineChars 200, or two 16pt spaces
early in the line. The real line, printed left-aligned (`lab/f0b`):
- the cells are 15.794 apart and the two spaces 7.90 each in Word's
  print, the same as ours;
- "牌" is 5.72 over and is taken only from a 2.00pt shift.

So the real line allows 3.7, under the lab's no-mark base. Something in
its own content takes room back, and the comma gives nothing there.
Untried variables:
- where the comma stands (the lab's sits after the 3rd character, the
  real one after the 14th);
- the run's rFonts without hAnsi, with hint eastAsia;
- the paragraph's later lines.

Then a deletion bisect on the real line (`lab/f0b/bis.py`, Mac). Every
variant is taken from 2.00: text cut after "牌建设，", the mark's rPr
gone, no exact spacing, and the two spaces as one 中 (the same width).
With the comma replaced by 中 it needs 10.00, so the comma gives 8.0,
its half cell. Measured from the margin, Word allows -4.3 with no mark
(a character must end 4.3 inside) and +3.7 with one comma.

That agrees with squeeze2 if its over is reckoned from the Nth whole
cell, not the margin. f0bd9ea8's lines leave 10.11 past their whole
cells (436.55 - 27 x 15.794; the first line 404.96 - 25 x 15.794), and
its 5.9 and 13.8 less 10.11 are -4.2 and 3.7. d68ac84a's line is 30
whole cells with nothing left over, and reads 0 and half a cell either
way. So the open question is narrower: what sets f0bd9ea8's -4.2
against a leftover of 10.11.

**Found and built (Mac, 2026-10-17).** On a negative grid a body line
is whole cells of Normal's size plus the grid's addition: 42 of 10.294
= 432.36, which is 4.19 short. With the margin 5.1 or 10.1pt in, both
prints' lines end at 41 cells. f0bd9ea8 53.6 -> 84.1, nothing else
down. A positive grid does not round (zh-ac627439). DONE for this cause.

### T59. A column chart with a line on a second value axis — DONE (2026-10-17)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac, has Word), from 2026-10-16
Documents: zh-2a241df1 (7.6%, from the Mac's second Word sample of 20
unprinted zh documents: prints in ~/starling-word-check/zh2, scored with
DOCX_WORD_REFS). Its two charts are `c:barChart` plus a `c:lineChart` on
its own axes (a percentage axis on the right). `ChartXML.read` takes a
combination only on one pair of axes, so both read as nil and nothing is
drawn. Plan: read the line's axes, scale the line by its own axis, and
label that axis on the right (Slides' ChartPainter, shared with decks).
Done: the second axis (ae2d227a). The caption under a table is one
pitch, because spaces beside text add no height (2026-10-17). That was
page 2 on, 35.2 -> 72.4. The data table is drawn (369e2840): 72.4 ->
93.3. With Slides' ten-step axis (cf320772) it is 97.1. Left:
- chart 1 stands 2.5pt low, an inline object on the grid;
- the style-2 fills.

DONE (2026-10-17).

### T58. A paragraph that opens with a tab: the line stays at its indent — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: WordWithAttachments (its header's "<tab>Страница 1", centred
on a stop at 233.85pt, stands 101pt right of Word's).
Known: a tab is widened by spacing on the tab itself, and the engine sets
a character's spacing half before it: at a line's start that moves the
whole line on by half the tab. Slides put a leading tab's widening into
the first line's indent box (HowWeRefactor's quotes); Word's paragraphs
do not yet. With a letter before the tab the line is right.
Built: documents too. The header within 2.4pt of Word's; no score moved.

### T60. Moved text is read, kept and printed — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: Tika-792 (0%; its "Moved (insertion) [1]" balloon).
Known: the reader skips `w:moveTo` and `w:moveFrom` whole — moved text
is gone from the page and from a save. Word shows the new place as an
insertion (and prints "Moved (insertion) [n]" beside it), the old one
as a deletion.
Built: `w:moveTo` reads as an insertion and `w:moveFrom` as a deletion,
both marked moved, so the text is on the page and survives a save (as
w:ins/w:del). Printing labels the old place "Moved down/up [n]:" and the
new one "Moved (insertion) [n]". No score moved: Tika-792 still 0 — its
move balloon prints, but Word's "Formatted: Font color: Auto" and the
balloon order still differ.

### T61. delins's balloons: a reformatted paragraph mark, deleted list items — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: delins (55%).
Known: Word gives a reformatted paragraph mark its own "Formatted:"
balloon (each link item: Field Code Changed, its text's, its mark's);
ours prints none for marks. In a deletion's balloon Word starts each
deleted paragraph on its own line, a list item's with "<#>"; ours runs
them on ("Tika.¶Tika Waylan").
Built: both, and a field's ends break a "Formatted:" stretch while a
reformatted mark joins the next paragraph's (read off the connector
lines in Word's print). delins 55 -> 75%, nothing else moved. Open:
which of a link's balloons comes first (office.md).

### T63. A 1.5-spaced line at a page's foot: does its extra space count? — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: zh-8112041b (70.8%, new sample; 標楷體, which both samples
print in YaHei).
Known: page 2 matches Word's to 0.3pt line by line, then Word keeps four
empty 1.5-spaced paragraphs (36pt each, 24 of it the line) under article
nine and ours three: the fourth's line box runs about 5pt past the
margin, its text does not. Word sets the extra space of a multiple
spacing below the text. Try: let that extra hang past the foot as the
grid's half leading does (`_overhang`), and see what the sweep says.
Built: that, and a page break inside a table cell is nothing (the
form's title cell opens with two; ours split an empty line off, 59pt
of the page). Mac measured the same independently. zh-8112041b 70.8 ->
100%, nothing else moved (same-base sweep with and without).

### T65. zh-17749c13 p20: a grid line's limit at the page foot is its deepest face's — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac), from 2026-10-17
zh-17749c13 (85.6%) runs a line ahead from page 21: ours keeps "第六十六条
申请办理船舶国籍证书…" (14pt 宋体, one line, two 15.6pt pitches, auto
spacing) at page 20's foot, baseline 763.5; Word sends it over. Labs `p0`–`p7`
(page 20's text alone, the bottom margin 1440 down 20 twips a step):
Word keeps it from 1420 on, so its limit is a foot between 770 and 771pt,
6.8–7.8 under the baseline. Ours lets a grid line overhang by half its
extra (`gridOverhang`, 6.5 here, from lab `gf2`'s YaHei bold on an 18pt
grid), which puts the limit near 767 and keeps it at 770. Neither the
natural bottom (~767) nor the line box (~774) is Word's here: 宋体 on a
15.6 grid needs labs at more sizes before the rule changes.
Measured (lab `footlab`, Word 16, one-page labs bisecting the bottom margin
to 0.25pt): the foot must lie under the last line's baseline by 0.294 em in
宋体 (12, 14, 16, 22pt: 3.5, 4.0, 4.75, 6.45) and 0.465 em in 仿宋_GB2312,
which Word sets in YaHei (12, 14, 16pt: 5.5, 6.7, 7.4) — each face's natural
line below its baseline; the same with 14pt of space after, auto or not.
zh-17749c13's line is 宋体 bold and YaHei: YaHei's 6.7 decides, and ours
took its overhang from the first run's 宋体 (6.5) and kept the line.
DONE: a text line's overhang is its runs' least (`_overhang`): zh-17749c13
85.6 -> 98.1, zh-2a241df1 72.4 -> 74.3; nothing else moved.

### T64. 楷体_GB2312 is YaHei in today's Word for Mac — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: the zh corpus. Word 16.113.3 sets 楷体_GB2312 text in
Microsoft YaHei (all seven of the second sample that use it, alt name
or not; zh-78729cf9 reprinted today: 8152 YaHei characters, no KaiTi),
where the first sample's prints of 2026-10-12 have KaiTi. The Mac
(011uWpmC) is reprinting all 68 of the first sample as one
references-only commit. Then: `OfficeFonts`' mac rule takes
楷体_GB2312 to YaHei, swept against the new prints on Linux.
Built: against db1a7940's prints, same base with and without, Linux:
zh-e02b0479 68.6 -> 97.1, zh-15728c84 86.9 -> 98.5, zh-232090e0 86.7 ->
95.6, zh-69bbcc3c 99.4 -> 99.5; nothing down; mean 91.25 -> 91.49.

### T66. zh-15428325's bold "（一）" lines: one character more than Word's — tried, released
Owner: none — released by starling-office1-df (Linux), 2026-10-17
Documents: zh-15428325 (94.1%; its bold "（一）…" lines take a character
more than Word's).
Known: under `w:balanceSingleByteDoubleByteWidth` ours spaces every
full-width character twice (16pt at -0.3 set 15.4 apart). Word's prints:
twice for 仿宋_GB2312 and 標楷體 (YaHei stood in: zh-6cd1befe 15.4 and
11.0, zh-9c5d0c3f 10.0), once for a face Word has (zh-15428325's 仿宋,
15.68), and zh-232090e0's 楷体_GB2312 once (11.8) in the KaiTi print of
2026-10-12, twice (11.6) in the YaHei reprint. Try: double only where
the East Asian face is a stand-in.
Tried and reverted: doubling only in a stand-in face took zh-15428325
94.1 -> 60.7 (and four others down a little). The 15.68 read off its
print is a justified line's, stretched: its natural spacing may be
doubled after all. What the fitter sees for "（一）使用房票基础奖。各主体已推行
房票安置的，房票奖励" (`STARLING_RICHTEXT_FIT`): "励" 7.49pt over, inside
the half-em 8.0, taken; Word sends it down. Measured differences, not
enough together: Word's first-line indent is 30.95 (the file's 619
twips; ours 2 x (16 - 0.6) = 30.8), and its bold is ~0.03pt a character
wider than our fake bold (0.31 over plain against 0.28) — ~7.97 over.
Also seen: every line with letter spacing starts 0.3-0.8pt left of
Word's — the engine sets a character's spacing half before it (as for
tabs, T58), Word after. A lab of this line, the over varied, would say
what Word counts.

Windows box, 2026-10-17: lab `bold` (Word for Windows, the line with
its right indent varied): Word takes "励" down to -500 twips bold, -480
plain; ours -540 bold, -480 plain — so ours meets Word's limit plain,
and Word for Windows emboldens ~0.1pt a character, not the Mac's 0.31.
With the Mac's figure, fake bold 1/57 -> 1/52 em (0.31 at 16pt):
zh-15428325 94.8 -> 96.1, nothing else moved in either set. The first
line's 30.95 (ours 30.8) is still open.

### T67. A comment's balloon hangs at the comment's end — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: WordWithAttachments (23.7%).
Known: its comments each span a quatrain. In Word's print the balloons
"Commented [v2]" and "[v3]" are level with the quatrains' last lines,
where the comment references stand; ours with their first. Word also
prints no balloon for v1, whose reference is alone in an empty
paragraph, yet numbers the others from 2 — not modelled (one file).
Built: anchored at the range's end. Each balloon now 2pt under its
anchor line as in Word's (v2 445/447 there, 389/391 ours); no score
moved — the page is still ~56pt high for its missing attachment icons
and the unframed text box.

### T68. An embedded object's icon: the bitmaps in its metafile — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: WordWithAttachments (the "Tryhere.jpg" package's icon, the
Word document's icon), tika-3388 (the .msg's 40x40 icon).
Known: Writer plays an object's WMF/EMF with no image provider
(`WriterMetafiles.paint`), so its captions print and its bitmaps
(DibStretchBlt, AlphaBlend) do not: our PDFs have no image where Word's
have the icons. Build: decode the metafile's bitmaps as the layout does
its pictures, and let the export wait for them.
Built: WordWithAttachments' two icons and tika-3388's print, at Word's
place and size. No score moved (the line match reads text).

### T69. A VML drawing canvas in the line, with a text box in it — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: WordWithAttachments (23.7%; p1's "Словарь/dictionary/Луғат").
Known: a `v:group` (editas canvas, 126x99pt, no position:absolute) sits
in the line before "Hyperlink Ссылка юбоқриш"; inside it a text box
shape, absolutely placed in the group's coordinates. `_float` looks for
any `v:shape` before the group, finds the inner box and floats the
whole drawing: it takes no room, and p1 below it stands ~57pt high.
Build: the outermost VML element decides floating and size; the text
box's text set at its own place in the group.
Built: WordWithAttachments 23.7 -> 84.2%, nothing else moved (same-base
sweep). Its text within 1.5pt of Word's. Left: the box's frame — Word
draws it 49.9pt square at 87.3, 274.6, where the group's coordinates
make the box 72pt; the WordArt.

### T72. Tika-792's balloons (numbered T70 at first; the Mac's came first): Word's own face, moves inside changes — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: Tika-792 (0%).
Known: Word's print (Mac) has three balloons: "Moved (insertion) [1]",
"Deleted: s.", "Formatted: Font color: Auto", in Times New Roman 9pt
(scaled 6.24 on paper); the body prints nothing. Ours: "Deleted: s." and
"Moved down [1]: b" in Tahoma 8pt. With no Balloon Text style in the
file, Word for Mac sets balloons in Times 9pt (comment, testComment and
WordWithAttachments' labels follow their Balloon Text style the same
way). A moveTo whose only text was deleted still gets its "Moved
(insertion)" balloon, ahead of the deletion's; an insertion inside a
moveFrom (typed, then moved away) is gone, with no balloon, though its
formatting change keeps one.
Built: a run keeps both changes (`RevisionMark.nested`): the place of
moved text all deleted is printed "Moved (insertion)" ahead of the
deletion, an insertion moved away prints nothing but its "Formatted:";
balloons with no Balloon Text style in Times 9pt, a comment's label in
the Balloon Text face too and its text in Comment Text's (else Normal's),
a deletion's text in Normal's face where its own names none. Same-base
sweep: Tika-792 0 -> 100, delins 75 -> 80, nothing else moved; mean
92.544 -> 93.071.

### T71. rtl: Arabic in a Times stand-in, at Times' widths — tried, released
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: rtl (0%).
Known: the file (from LibreOffice) names "Noto Sans Arabic UI" for
complex script; Word for Mac, lacking it, sets the Arabic in Times New
Roman. Ours draws it from DejaVu Sans, the Linux glyph fallback,
because Liberation Serif has no Arabic: words 32% wider than Word's
(shaped widths of 114 words against Word's print), so every line
breaks early. FreeSerif's Arabic is 4.7% wider, Noto Naskh Arabic's
14.8%, Noto Sans Arabic's 25.6%.
Plan: on Linux, the serif stand-in falls back to FreeSerif first.
Tried: FreeSerif as the serif face's fallback on Linux. The lines then
break where Word's do (1 and 2 exactly, 3 a word short), but the score
stays 0: our PDF lays an RTL line's words down left to right, each
word's letters in logical order, and the matcher reads the line from
its visual left end, where Word's reads in logical order throughout.
FreeSerif's contextual Arabic forms also lack cmap entries, so the PDF's
text maps them to junk (㒘, 㒡), which DejaVu's presentation forms do not
do. Released: the order is the PDF writer's (the engine's), and a face
whose text cannot be copied out is worse than a wider one.

### T73. zh-547fc43c: a chart that does not fit, with widow control off — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: zh-547fc43c (13.2%, third sample).
Known: page 2 ends with two charts, each a picture paragraph; Word
starts page 3 with the second (219pt, 234 on the 15.6pt grid), where
ours set it under the first, 113pt past the foot, and every page after
ran a chart's height ahead. A picture paragraph's only cut is its empty
line's, under the picture's top, so the cut took the whole picture; only
the widow-control rule kept it off a page too short, and the file's
Normal turns widow control off.
Built: a picture paragraph goes whole or to the next page (when the page
has something on it already). 13.5 -> 87.9%, pages as Word's; nothing
else moved (same-base sweep).

### T74. An embedded object as wide as the column: its mark on a line of its own — DONE (2026-10-17)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac)
Documents: WordWithAttachments (84.2%; page 1's icon and page 2's
sheets stood a line high).
Known: a `w:object` of 468pt in a 467.75pt column. Word sets its
paragraph mark on the next line. Lab `wide`: in a 456.75pt column the
mark drops when the object is 456.75 wide and stays at 456.7. In a
467.75pt column it drops at 467.48.
Built: under an object at least the column's width, the paragraph is
the object plus its mark's line. A DrawingML picture keeps its mark
beside it: with every picture, bug57031 99.7 -> 92.6 (480pt plots in
468), zh-06c46ba9, zh-15428325 and chartex fell. Not in cells (not
measured). WordWithAttachments 84.2 -> 100; nothing else moved.
Left there: VML WordArt (`v:textpath`) is drawn as grey boxes, and Word
prints it as images the line match cannot see.
Also looked at and left: zh-e029cf49 (94.0%) is the matcher grouping
centred cells' "1" and "-10" with a row's first line. Every glyph is
within 0.3pt of Word's. 55966 (33%) is Word showing the first
placeholder control's text in a second control (`w:showingPlcHdr`,
one docPart). One sample is not enough for a rule.

### T79. A chart's line on the grid: its effect extent, and centred — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: zh-547fc43c (87.9% after T73; p6's chart).
Known: a 233.75pt chart with 0.35 + 1.4pt of effect extent takes 16
pitches of a 15.6pt grid in Word's print; ours 15 (a kept object, a
chart, reads no effect extent), so all under it stood 16pt high. And
Word stands the chart half its line's spare room down (7.05 of 14.1),
as it does the document's other charts and pictures within 0.4pt.
Built: a kept object (a chart, a shape) in the line reads its effect
extent as a picture does, and its line holds it; a picture paragraph on
the grid stands centred in its pitches, where it had the spare room
less its mark's descent over it. Same-base sweep: zh-547fc43c 87.9 ->
94.3 (92.5 with the extent alone), nothing else moved — zh-90e0cea8's and
zh-9c5d0c3f's pictures on grids among them. Left on its p6: the chart's
axis titles ("亿元", "%") at the axes' tops and its line's data labels.

### T81. zh-5a9a85c6: a VML page number fitted on every page — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: zh-5a9a85c6 (94.9%).
Known: its footers' "— PAGE —" is a VML-only text box (`w:pict`,
mso-wrap-style:none, mso-fit-shape-to-text). Word's print never wraps it
("— 15 —" whole on every page); ours keeps the width of page 1's "— 1 —"
(lab `ftD`'s rule) and wraps the closing dash from page 10. Lab `ftD`'s
box was DrawingML (zh-a4b0f6ea, `wps` with a VML fallback). Plan: size
once only a DrawingML box; fit a VML one on each page.
Built: `RichTextBox.fitsOnce`, set for a DrawingML box; a VML one is
fitted on each page. Same-base sweep: zh-5a9a85c6 94.9 -> 97.9, nothing
else moved (zh-1a3c7aa0 and zh-e02b0479, VML too, as they were).

### T82. Writer charts: axis titles placed by manualLayout, line-series data labels — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17 (handed over by Slides)
Documents: zh-547fc43c (p5, p6, p8 charts).
Known: "亿元" (a catAx title, manualLayout x .0147 y .0369) stands at the
chart's top left in Word's print, ours under the plot; a secondary
axis's "%" likewise; a line series' dLbls (showVal, dLblPos t) print
in Word and not in ours.
Built: an axis title placed by edge-mode manualLayout and set across
(`a:bodyPr rot="0"`) stands there in its own size, 3pt in, its glyphs'
tops 2.9 down, and takes no band (`Chart.categoryAxisTitleAt`); a
combination's line shows its values (`ChartSeries.valueLabels`), each
label's foot 6.5pt over its point, single ones moved by their
`c:dLbl/c:layout`. Same-base sweep: zh-547fc43c 94.1 -> 96.6, nothing
else moved; Slides' 19 chart decks unchanged. The "%" by chart 4 is a
text box in the document, not the chart's.
Left (a lead, not built): zh-547fc43c's column charts in Word set a
value label's foot about 6pt over its bar (baseline 7.5 over at 10.5pt
宋体), ours 4.3 over (centred 8 over, PowerPoint's gap); the category
labels' baselines 16.5 under the axis, ours 19.8. Word's charts and
PowerPoint's may differ here, so the painter would need to know which it
draws for; the Slides decks are tuned to PowerPoint's.
Tried (behind `Chart.inWord`, 2026-10-17): value labels 3.2pt higher and
category labels 3.3pt higher in Word. zh-547fc43c 96.6 -> 98.4, but
chartex's Calibri years (Mac print too) stood where ours were and went
3.5pt high (77.8 -> 75.0). The two shifts are one size, and both charts'
text is 宋体 in Word (digits too) where ours sets digits in Liberation
Sans and ideographs in a CJK fallback — a face's line, not Word's gap.
Reverted; the lead is the chart text's stand-in faces.

### T85. zh-3c055c9b: a character grid's automatic spaces in the squeeze — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: zh-3c055c9b (45%).
Known: the Mac's labs ab3c/ab3a/ab3b (board, above): with no digits on
the line Word's limit is ours to the twip; with ten automatic spaces
Word takes 4.45pt more, with fourteen 3.95. Solved against the mode-15
test's terms (the real line: ems 5.31, spaces 46.77, room 74.4), the
spaces count 0.66 and 0.70 of themselves, not whole.
Tried: two thirds — p2 then matched, but p8's "…家族聚" took "餐，"
where Word does not (45 -> 28): no one weight fits both.
Built: on a character grid the test compares with the marks' room alone
(the spaces give nothing — Word sets them whole while the marks give) and
weighs the spaces 0.44 in the stretch. That fits ab3c, ab3a and ab3b
within a point, p2's line and p8's two. Same-base sweep: zh-3c055c9b
45.2 -> 76.7, nothing else moved. Left: p7's "…(週日)確" + "有" and p10's
"…(合計10" + "萬" Word takes and this does not (the second would need the
spaces near nothing — the one beside the character taken may not count).
Unit fonts never reach this squeeze, so the sweep is its test.

### T92. zh-830ef10d p2: a cell narrower than an em holds a character a line — DONE (2026-10-17, Mac 011uWpmC, 260f100d)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: zh-830ef10d (89.2%, fourth sample).
Known: a 16.8pt cell (6pt inside its margins) holds "个性要求（6分）",
12pt on exact 13pt lines, centred beside a cell of five lines. Word sets
it eight lines, "（", "6", "分" and "）" each alone; ours kept "（6" and
"分）" by the line-start and line-end rules, then "6分" (the "6" just
fills the column): seven lines, all half a line off the neighbour's.
Built on the Mac (it had the document claimed in the fourth-sample list
since 15:5x): such a paragraph gets a break before every character, the
fitter keeps them, and the engine lays the line out one em wide.
89.2 -> 97.3; nothing else moved (s294).

### T93. chartex's stock chart: high-low lines, series lines off, Close's dots — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: chartex (p3).
Known: its `c:stockChart` series set `a:ln/a:noFill`; High and Low no
marker, Close a 3pt dot; `c:hiLowLines` draws each date's high to low.
Word's print: five grey bars with Close's dots, the legend's keys bare.
Ours: three coloured lines (a main series' noFill and marker are not
read). No line of text moves; this is the drawing.
Built: a line series whose line is none draws its marks alone (and its
legend key is its mark); `c:hiLowLines` draw each category's high to
low (`Chart.highLowLines`); Office's "dot" mark is a short dash. Same-base
sweep: nothing moved; Slides' 19 chart decks unchanged.

### T94. zh-37b6536f p3: a chart legend's Chinese entries, 16.8pt apart — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: zh-37b6536f (96.9%).
Known: a pie's legend at the right, six 9pt Chinese names: Word's rows
16.8pt apart (Calibri's 9pt line and 6pt), ours 19.05 (the CJK fallback's
taller line and 6). Its data labels "620", "631", "726" also stand
elsewhere than Word's.
Built: a legend row is a line of the chart's Latin face and the gap,
whatever the names' script. Same-base sweep: zh-37b6536f 96.9 -> 99.2,
zh-547fc43c 96.6 -> 96.8, nothing else moved; Slides' 19 chart decks
unchanged. Left: its pie's best-fit labels (five slices of 1-20 by one
of 726), which Word sets elsewhere.

### T113. Chart text in an East Asian face: its stand-ins and its lines (T82's lead) — DONE (2026-10-18)
Owner: session starling-b2 (Slides, Linux dev box), from 2026-10-18
Documents: zh-547fc43c (column charts), chartex (control: Calibri years).
Known (T82): Word sets zh-547fc43c's chart text in 宋体, digits too, and
its value and category labels about 3.2pt higher than ours; ours sets
the digits in Liberation Sans and the ideographs in a CJK fallback.
Lab (Windows box, chart1 alone, faces swapped): Word sets 宋体, 黑体 and
Calibri within 0.2–0.8pt of one another; 微软雅黑 moves (value labels
1.7 up, categories 4 down). So no face rule in Word: the page's other
charts (Calibri) are 2.4–2.8pt low in ours too.
Built: a `c:` chart's column value labels and category labels in Word
stand a quarter of their size higher, 0.3 in a square face (ours, for
its Liberation digits); not chartex, not slides. zh-547fc43c 96.8 ->
98.2; the other five chart documents unchanged (line match).

### T95. zh-92373179: an embedded subset's missing characters are YaHei's, and so is the line — released (done as T97, 79646c80)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: zh-92373179 (39.9%, fifth sample).
Known: from p3 its 1.5-spaced paragraphs (snapToGrid 0, 16pt 仿宋_GB2312)
stand 41pt apart in Word's print, ours 31.65. The file embeds a subset of
FangSong_GB2312 (its hhea 1.14 em); Word for Mac draws the characters the
subset lacks ("运用", "易", "贡献") in Microsoft YaHei, and their 1.715-em
line sets every such line (1.5 x 1.715 x 16 = 41.2). Ours draws them by
glyph fallback and keeps the embedded face's 1.3-em measure.
Plan: an embedded face notes the characters it has; on Word for Mac the
rest are set in the face the name stands in as (YaHei), its line and all.
Released: built the same here (39.9 -> 43.0, without the baseline) while
T97 (Linux 017F2) landed it with the baseline too (46.1); this one dropped.

### T99. zh-20ff844e p15-19: a run of pages off Word's — claimed
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: zh-20ff844e (95.8%, 129 pages; 108 misses, 89 of them on p15-19).

### T100. Word equations (OMML): read, kept, drawn — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17 (Windows box agreed)
Documents: zh-20ff844e (p15's two display formulas), zh-c2c92639 (14),
zh-06c46ba9 (1).
Known: `m:oMath` / `m:oMathPara` are not read at all: an equation is gone
from the page (zh-20ff844e p15 loses its formulas and their 50pt, and the
page after runs high) and from a save (a re-saved zh-20ff844e has none).
Plan: an equation is a kept object (written back verbatim, outside any
run), drawn by a small layout of its own — runs, sub/superscripts, n-ary
operators with limits, fractions, delimiters, radicals, functions; the
rest linear — display equations centred as Word's default.
Built: `WriterMath` — an equation is a kept object (`m:oMath` in a line,
`m:oMathPara` a display one, its paragraph centred unless its `m:jc`
says otherwise), laid out as boxes (runs with letters italic and
operators spaced; sub/superscripts; n-ary operators, limits over and
under or beside; fractions on the axis; delimiters grown to their
content; radicals; functions; accents; bars; limits; group characters;
equation arrays; matrices), set in Cambria's stand-in with the math
faces after it, and drawn through `RichLayout.objectPainter`; an inline
one stands on its own baseline (`ImageAttachment.baseline`). Written back
verbatim as the paragraph's child. Same-base sweep: zh-20ff844e 95.8 ->
99.0, zh-06c46ba9 97.4 -> 97.5, nothing else moved. A display ∑ is 1.6
times its text (1.9 put zh-20ff844e's p15 a few points long: 95.8).
Fixed after (2026-10-18, the Windows box's report: zh-c2c92639 91.3 ->
77.4, a page longer): a fraction's parts are set inline (an n-ary's
limits beside it, the sign unenlarged); scripts at Word's offsets (0.38
em up, 0.18 down); an equation in a line counts no more of it than its
text (0.85 em over, 0.22 under) and is not snapped to the grid as a
picture (`ImageAttachment.baseline` set); fractions closer about their
rule. zh-c2c92639 77.4 -> 91.9 (54 pages, Word's), zh-20ff844e 99.0,
zh-06c46ba9 97.4.

### T104. zh-ea70c30e p2: a mode-15 squeeze Word does not make — measured, waiting on a lab
Owner: session starling-office1-df (Linux dev box), from 2026-10-17 (the Mac's lead, b14d1d47)
Documents: zh-ea70c30e (59.1%, sixth sample).
Known: its body lines hold real spaces ("達 10,000 名", "辦公室 – 投訴"),
so the fitter takes them as `lineOther` and tests need per mark against
what is left, never against stretching. Tried: also requiring that a
squeeze ask less than stretching at the line's spaces would
(need × (ems/64 + autospaces + spaces) ≤ room × slack). p2's "有" is
then left, as in Word — but p3's "(k)「第一層級部門」…辦公室 – 投" leaves
"訴", which Word takes, and the document fell 60.1 -> 59.4. The two sit
on the same edge: p2 need 8.04, 3 marks (18.74), slack 4.46, ems 5.47,
spaces 5.87 → 91.2 against 83.5 (1.092); p3 need 8.78, 4 marks (24.98),
slack 3.72, ems 5.66, spaces 5.87 → 101.2 against 92.9 (1.089). Asked
the Mac for Word's limits on both lines (the over varied). Its p5-p8
misses are something else: list items in Body Text Indent 2 (left 1440)
over a level that states only firstLine 720, the paragraph only hanging
720 — Word sets them at 72pt, ours at the margin (the list's indent
replaces the style's left, though neither the level nor the paragraph
gives one).
The Mac's labs (2026-10-18): p2 spaced, Word takes "有" to over 8.2,
ours to 9.3; closed up, both to 9.66 — the spaces beside the ideographs
cost Word ~0.7pt more each. p3's "辦公室 – 投訴" and its unspaced form
part on the dash: Word sets an unhinted "–" in the hAnsi face (Times,
6.25) where the run's `w:ascii` is PMingLiU; ours drew PMingLiU's (10.3).
Built: that en dash is the hAnsi face's (U+2013 only — taking the run's
quotes and other shared marks as Latin too cost eight documents). No
document moved. Left: the spaces' cost in the squeeze decision (p2; p3's
"…交通課；動", which Word justifies by stretching its spaces to 3.94).

### T108. A list item whose level and paragraph give no left keeps its style's — DONE (2026-10-18)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: zh-ea70c30e (p5-p8).
Known: its "(c)".."(f)" items are Body Text Indent 2 (left 1440) on a
level that states only firstLine 720, the paragraph only hanging 720.
Word sets the text at 72pt and the label at 36 (each attribute from where
it is given); ours drops the style's left and sets the text at the margin.
Built: where neither the paragraph nor its level states a left, the item
keeps its style's (`listIndentLeft`). Same-base sweep: zh-ea70c30e 60.1
-> 98.3, nothing else moved.

### T114. zh-30d86fcf p2: no squeeze to take a circled number (numbered T113 at first; the slides session's came first) — DONE (2026-10-18)
Owner: session starling-office1-df (Linux dev box), from 2026-10-18 (the Mac's lead)
Documents: zh-30d86fcf (94.7).
Known (Mac): the line ends "…条件：", ① (U+2460) next. Ours squeezes the
"：" to 13.5 to take ① at the end; Word leaves the colon a full em and
opens the next line with ①.
Built: in the body no squeeze takes a character of U+2460-24FF (in a
cell one still does: zh-20ff844e's narrow cells take their "③", 99.0 ->
98.4 with the rule everywhere). Same-base sweep: zh-30d86fcf 95.3 -> 99.4,
nothing else moved.

### T115. zh-8d6f702e p23: on its -0.21 grid comma-like marks give a quarter em, brackets nothing — DONE (2026-10-18)
Owner: session starling-office1-df (Linux dev box), from 2026-10-18 (the Windows box's lead, office.md)
Documents: zh-8d6f702e.
Known (Windows): mode 12, compressPunctuation, a -0.21 grid. "计面雨量达160—230毫米（不含），或全县…以上站点" — Word squeezes
nothing, leaves "累"; ours gives "（", "）", "，" 2.63 each to take it. The next, "…150毫米，或全", Word gives "：" and "，" 3.94
each (a quarter em) to take "全"; ours gives nothing.
Done in two parts, landed together. (a) the Windows box's: in a paragraph off the grid by its own setting a
half-width character before a non-space takes half the grid's addition — p23's digits 7.90 as in Word, and the
existing squeeze then gives "：" and "，" what Word does, so (b) needed nothing. Alone, (a) dropped zh-3c055c9b
91.7 -> 76.4: its p12 cell came out 7 lines, as Word's, where the old digits made 6 — and the table under the
caption "表1　古佳川不實核銷表(…財物)" started 21pt low, because the caption (centred, numbered on a 24pt hang)
wrapped "物)" over the page. Word centres a numbered line across its hang; so does ours now (body paragraphs,
centred or right). Same-base sweep, 337 docs: zh-8d6f702e 88.2 -> 91.0, zh-3c055c9b 91.7 -> 93.5, nothing lower.

### T116. zh-621d8756: a colon squeezed so one more space fits; "号：" + spaces + "、" not ending a line — claimed
Owner: session starling-office1-df (Linux dev box), from 2026-10-18 (the Windows box's leads)
Documents: zh-621d8756 (95.5).
Known (Windows): wordWrap off, compressPunctuation + noPunctuationKerning: "答：", "执法人员：", "执法证号：" set the colon
10.8-11.6 so one more space fits (ours 15.6). p19 (no wordWrap off, lines grid): "…执法证号：" + 6 spaces + "、" — Word
ends the line at "…执法证" and starts the next with "号："; ours keeps "号：" and its spaces and hangs the "、".

### T117. Mixed character scales (w:w) print every squeezed character twice in the PDF's text — DONE (2026-10-18)
Owner: session starling-office1-df (Linux dev box), from 2026-10-18
Documents: zh-701eda18 p8 ("手語翻譯及聽打員本人簽名", 80% runs beside 100% ones), any paragraph of several scales.
Known: a paragraph of several scales is painted twice — whole under a clip that cuts the squeezed pieces out, then
each piece stretched under its own clip. The clip hides the first pass's squeezed glyphs but the PDF still holds
them, so text read from the print has those characters twice ("手語翻譯及手語翻譯") and the line scorer misses the
lines. Done: each pass paints a copy of the paragraph with the other pass's text clear, which the canvas drops
(laid out identically, checked line by line, else the old drawing). Pixels unchanged on zh-701eda18; same-base sweep
337 docs: zh-7dc3afad 99.6 -> 99.8, nothing lower. zh-701eda18 itself does not move: those lines also sit 2.5pt high
— T118.

### T118. A cell's own line width stands in for a table side it never names — DONE (2026-10-18)
Owner: session starling-office1-df (Linux dev box), from 2026-10-18
Documents: zh-701eda18 p4 (both platforms; the Mac confirmed its baselines 2.4pt high too).
Known: the first form's last row is auto height; its tallest cell states only a right "double sz4", so the cell's
width is 0.5, and the room under the row (`rule`/`sideLine` in RichLayout) took that 0.5 for the table's 3pt
thickThinSmallGap bottom: 2.0 where Word's print gives 4.32-4.5. Everything after sits 2.5 high. Fix: a side the
cell's tcBorders do not name takes the table's width for it.
Done, but not as first tried: taking the table's width alone dropped zh-cec9d337 83.5 -> 49.0 — its rows, ruled 0.5pt
between them, stand 1.75pt taller in Word's print for a 2.25pt line stated on their first cell's left. So an unnamed
side is the wider of the table's line there and the cell's own. Same-base sweep, 337 docs: zh-701eda18 92.8 -> 96.0,
nothing else moved.

### T119. Legacy-mode line ends (zh-12c4f07a, zh-749cb15a): first, a compatibility ideograph YaHei lacks — DONE (2026-10-18)
Owner: session starling-office1-df (Linux dev box), again from 2026-10-18 after the Mac's lab
Documents: zh-12c4f07a, zh-749cb15a; zh-5b7ae054, zh-8e8d4c40, zh-4adfcce2, zh-7dc3afad and others hold the same.
Known: zh-12c4f07a p8's "於契約…本委" ends at 委 in Word because its "契" is U+F909, which Word for Mac draws in a
YaHei run as YaHei's missing-glyph box, 0.697 em (9.06 at 13pt, glyph 0 in the print) — not in Noto Sans SC as the
`_notoCompatibility` ones are, nor in Heiti SC. Across Word's prints there are 54 such boxes, all 0.697 em, all
YaHei, in the documents holding compatibility ideographs outside that set (counts match per document). Ours gives
the character a whole em, and the line's last character goes over. Fix to try: such a character takes 0.697 em.
Tried, reverted: zh-12c4f07a 78.6 -> 79.3, but zh-ff93733d 97.0 -> 6.5 and zh-749cb15a 87.3 -> 82.5. zh-ff93733d p1
(標楷體 -> YaHei 14pt, legacy mode, compressPunctuation): "二、本機關106年□員工…滿意□及問卷調查結" — two "度" U+FA01
boxes drawn 9.76 (0.697 em) — ends at 結, justified 14.63 a character, "果。" on the next line. Its natural width with
the boxes at 0.697 leaves 17.6pt, room for "果" and "。" both; Word took neither, which fits only if its line
breaking counts the box a whole em (then 果 is 4.8 over) and only its drawing is narrow. Its next line ("三、…107年□
施政…首長施", 景、 at 13.33) agrees with a whole-em break. But zh-12c4f07a's "委" fits only with the box at 0.697 in
the break (a whole em leaves it 7.75 over against "，"'s 6.5). Lab wanted (Word for Mac, YaHei, U+F909 and U+FA01):
the box in the break — whole em or 0.697 — and whether it differs by character or position.

Lab answer (Mac 01Xgpbk5, 2026-10-18, Word for Mac 16.113.3,
~/starling-word-check/lab/tools/cj): the break counts the box at 0.697 em
too — a justified 標楷體→YaHei paragraph, U+F909 or U+FA01 at character 11
or right before the marker at 21, gives 0.30 em more room than U+5951 or
U+5EA6 there (78 twips at 13pt, 84 at 14pt; both characters, both places).
So zh-ff93733d's "果。" is something else (its line ends the paragraph
with "。").

With the Mac's lab (the break counts the box at 0.697 too), the box rule is right and moves nearly every changed
line of zh-749cb15a onto Word's (p49-52 and p75-78 runs fixed), but two legacy-mode line ends then go the other
way, so it waits (patch kept by starling-office1-df): (1) zh-749cb15a p? "…功能性及專業性國際組織；" — mid-paragraph,
overflowPunct 0: ours squeezes the line's last mark "；" (over 4.57 of its 7.3) to take "織；", Word carries both (its
p91-93 and p104-113 then run a line apart); (2) zh-ff93733d p1 "…調查結果。" — the paragraph's end, overflowPunct
on: "果" fits whole with the boxes at 0.697 (17.6pt spare) and ours hangs "。", Word carries both (and the rest of
the document runs a line apart: 97.0 -> 6.5). Lab asked of the Mac: in legacy mode, does a line's last mark give
anything to take it — squeezed with overflowPunct off, hung with it on — and does it matter that it ends the paragraph?
Line-end lab (Mac 01Xgpbk5, Word for Mac 16.113.3, zh-ff93733d's package,
compressPunctuation, YaHei 14pt justified, ~/starling-word-check/lab/tools/lp):
the indent up to which the line's last ideograph stays, against a control
of 958 twips (an em is 280). LEGACY: "。" ending the paragraph (overflow
on) 679 — carried with it, no hang, no squeeze; "。" mid-paragraph (on)
958 — hangs; "；" mid-paragraph overflowPunct 0 679 — the last mark is NOT
squeezed to take it; on, 958 — hangs. MODE 15: "。" ending the paragraph
958 — hangs; "；" mid overflowPunct 0 819 — squeezed by half. So legacy
mode squeezes no line-end mark and never hangs a paragraph's final one.

Done with the Mac's labs `cj` and `lp` (Word for Mac; no mode and mode 14 alike, mode 15 not): the box is 0.697 em
in the break too; and before mode 15, in a document that compresses punctuation, a line's last mark that is one of
Taiwan's centred ones (document language zh-TW/HK/MO, "，。、；：！？"), in the body: mid-paragraph it gives nothing
to be taken; ending the paragraph it does not hang, and gives nothing where it is the line's only mark — under
overflowPunct 0 its half (lab pe_off; zh-749cb15a's "…活動。"), and with another mark on the line its share
(zh-64044a1d's "…措施事宜。"). First built for every no-mode file it sank 18 documents: the mainland's and the
uncompressed ones hang their final marks as any, and a cell's last bracket gives its half (zh-fec5fa30 "民政局
（處）"). Same-base sweep, 397 docs: zh-749cb15a 90.3 -> 99.8, zh-d62da4dd 55.7 -> 57.7, zh-06c46ba9 97.3 -> 98.1,
zh-12c4f07a 78.6 -> 79.3, zh-5b7ae054 and zh-e0ca7252 +0.1-0.2, nothing lower. zh-ff93733d stays 97.0.

### T120. zh-b4d36718: turned text in a merged cell that crosses a page sits off its part of the page — DONE (2026-10-18)
Owner: session starling-office1-df (Linux dev box), from 2026-10-18
Documents: zh-b4d36718 (93.7, tenth sample; p14-16 hold most of its 48 misses).
Known: its catalogue table merges the "基本公共服务事项" and "公共文化类" columns (tbRlV, vAlign center) over rows
that run on past p14's foot. Word centres each one's text in the part of the merge on the page (基…项 about -494,
the page's rows -250..-735); ours sets it 80pt lower, and "公共文化类" runs off the page's foot. A merge wholly on
one page ("医疗卫生类") is right in both.
Done: pagination records, for a turned cell merged past the page's foot, the rows of it that fit (as it does
for a centred horizontal one, zh-6d1afa56); the text is turned about that part and its alignment shares out what
the merge loses past the foot. Same-base sweep, 357 docs: zh-b4d36718 93.7 -> 96.6, zh-32f4ad9f 95.2 -> 98.8,
zh-021b8feb 98.0 -> 99.1, nothing lower.

### T121. zh-cd8987db p7: a hinted "°" in 宋体 is an em, as GB2312's Latin-1 symbols are — DONE (2026-10-18)
Owner: session starling-office1-df (Linux dev box), from 2026-10-18
Documents: zh-cd8987db (89.8 on Linux; p7 holds 20 of its 30 misses).
Known: "5.5.1 坡度＜25°的古茶林地，…埋入土中。" — the run says w:hint eastAsia, so Word sets "°" in 宋体: 10.50 at
10.5pt in Word's print, ours 4.20 (the stand-in's own), and our line took "土中。" Word's leaves. Word's prints set
"°" and "×" an em in SimSun and SimHei (12 and 2 of them), "²"/"³" (outside GB2312) half. Fix to try: the square
faces' East Asian side sets GB2312's Latin-1 symbols ¤ § ¨ ° ± × ÷ an em.
Done as tried. Same-base sweep, 357 docs: zh-c2c92639 97.8 -> 97.9, nothing lower; zh-cd8987db's p7 does not
move yet. With "°" an em the line's natural width is Word's, but Word still carries "土中。" though "土" fits
(natural end 530.2 of 538.5): the paragraph-end case sent to the Mac's line-end lab with T119's two.

### T122. A bare mark's number is its style's size, in its level's faces (zh-117cf7c6) — DONE (2026-10-18)
Owner: session starling-office1-df (Linux dev box), from 2026-10-18
Documents: zh-117cf7c6 (Linux 92.0, Mac 98.6: p3's list paragraph under a "※" bullet).
Known: the level's "※" is in 標楷體 with no hint, so the layout takes the family's Latin side, whose stand-in has no
"※"; on Linux the glyph fallback list starts with DejaVu Sans, which draws it at 12.8pt (scaled), on the Mac the
system finds PingFang. Word draws it in YaHei at 13.9, and its line is 2.5pt taller than ours; every line after on
the page drifts 3-5pt. Fix to try: the Latin side of an East Asian face falls back to that family's own East Asian
stand-in first.
Done, and more than the glyph: the fallback alone moved nothing — the line's height came from the number's size.
The mark says nothing, so Word sets the "※" at Normal's 14pt (ours took the first run's 12pt, and the box before
the text raised no line), in the level's own 標楷體 (ours never applied a level's w:rFonts outside symbol faces).
All three in: the number takes the paragraph style's size where the mark has none, and the level's text faces;
an East Asian family's Latin side falls back to its CJK face before the symbol face. Same-base sweep, 377 docs:
zh-117cf7c6 92.0 -> 100.0, nothing else moved.

### T127. A TOC page number at a right stop past the margin (zh-ab1ea005) — part (a) done, released
Owner: — (released by starling-office1-df, 2026-10-18; the Mac's measurements, 01Xgpbk5)
Documents: zh-ab1ea005 (12%: its TOC runs a line behind and the body a page behind).
Known (Mac, Word's print): toc 2, a dotted right stop at 8844 twips (519.2pt), compressPunctuation, mode 14, 方正楷体
14pt. (a) "51.…解除劳动合同？<tab>20": Word keeps the commas whole and puts "20" 4.3pt past the margin (entry 55 the
same with "23"); ours squeezes both commas to fit "20" (51), or sends "23" to its own line (55). (b) "54.…经济补偿？
<tab>22": unsqueezed "？" would end past the stop; Word squeezes the one comma 14 -> 9.4, "…偿？" ends the line, and
the tab with "22" goes to the next line; ours sends "偿？" down with the tab. Rule: a right-stop tab whose
unsqueezed start is before its stop stays and what follows may overflow the margin, unsqueezed; one whose start is
past it breaks before itself, the line before fitted as a line end (the engine allows no break before a tab).

Part (a) DONE (Linux b2 01JsizVV, 2026-10-23): a right stop at the margin (or set there) whose tab starts inside it lets what follows run past the margin — the tab takes nothing, the rest comes off the last character's advance, so the line ends inside and its ink runs on. "55.…补偿？<tab>23" keeps "23" on its line as in Word's print; zh-ab1ea005 12.0 -> 14.9, nothing else moved (A/B with 5e452e14 landing between: its three gains are its own). Left: (b) entry 54's break before the tab, and the body a page behind; released.

### T128. A Latin word at a line's end, by Word's start rule (zh-eb54d3b0, zh-499adba6) — DONE (2026-10-18)
Owner: session starling-office1-df (Linux dev box), from 2026-10-18 (the Windows box's labs lw*, the Mac's case)
Documents: zh-eb54d3b0 p10, zh-499adba6 (9.5%).
Known (Windows labs lw, lw2, lw14, lw3, lw4, modes 12 and 14 alike): a word of two or more Latin characters is
taken at a line's end only once it starts at least half the character before it inside the margin ("、0.3" taken
from 8pt in, refused at 1-7; its trailing automatic space not counted); a one-character word whenever it starts
inside ("件1。", "、1万元" taken 1-6pt over). Replaces T106's pause-mark exception. zh-499adba6 (mode 14, Mac):
"…同時訂定1976年至1985", "1985" starting 26.5pt inside, is taken by Word, four marks giving about 4pt each (16.2);
ours wraps it, and every page after runs a line or more behind.

Done before mode 15, in the body and (newly) in cells where the marks can give what it needs: a word of two or
more Latin characters by the start rule, one letter or digit whenever it starts inside and the marks can give for
it (not "②", not a hyphen: zh-20ff844e, zh-424775e4 fell on those when they counted). T106's pause-mark exception
stays only for a word after a Latin character (zh-424775e4's "（US-led" hyphen break, 0.16pt inside in Word's print).
zh-499adba6's "1985" is a cell's (inCell true in the trace), not the body's. Same-base sweep, 437 docs: zh-053f8706
98.4 -> 99.2, zh-60173bb6 77.0 -> 78.3, zh-5ff074a9 +0.6, zh-0243e7fc +0.8, zh-eb54d3b0 +0.3, zh-23ee8575 99.7 -> 100,
zh-16e0a12a, zh-749cb15a, zh-499adba6 +0.1-0.2, nothing lower. zh-499adba6 stays at 9.8: its page count (99/96)
is something else. No unit test: a test process lays the corpus file out without the converter's ICU data and
fonts, and its lines break elsewhere.

### T129. A side a cell does not name: the table's line for a row its text sets, the cell's for one its height sets — done (eff30b7f)
Owner: session starling-office1-df (Linux dev box), from 2026-10-18 (the Mac's counter-case to T118)
Documents: zh-e1b09977 (65.4), zh-cec9d337 (keep), zh-701eda18 (keep).
Known: zh-e1b09977's calendar is ruled 0.5 all round, its first column's cells state only a 2.25pt left line and
its last column's only a 2.25pt right one — as zh-cec9d337's do. Its rows (at least 28.2pt) are set by their text,
two exact 17pt lines, and stand 34.5 between rules in Word's print — the 0.5 line's room; ours (T118: the wider of
the cell's and the table's) 36.25. zh-cec9d337's rows are set by their stated heights, their text shorter, and
stand 1.75 taller in Word's print — the 2.25. To try: a row's text takes the table's line for a side its cell does
not name; a row its stated height sets adds the widest line its cells name.
Done by Mac 011uWpmC, eff30b7f (2026-10-18), not as proposed. Lab `cal` (Word 16, zh-5251dd23's table
whole): rows 34.8 with the 2.25pt line on either side, the cell the tallest or not, 34.56 with no stated
height, so a top or bottom side a cell does not name is the table's line, always. zh-cec9d337's taller rows
were its 22pt "○" lines held to an em after the grid snapped them (lab `g44`: two 18pt pitches in Word). n361
vs n360: zh-e1b09977 65.4 -> 81.4, zh-cec9d337 84.2 -> 88.2, zh-5251dd23 89.2 -> 96.8, none down. What is left
in zh-e1b09977: p14's split row ends a line later in ours. Lab `hdr` (its first rows whole) ends where Word's
does; only the text inside rows sits ~2pt higher than Word's, which decides that cut.
(Linux 017F2GnT, 2026-10-22, measured, not built: the ~2pt is the
header's heavy line. The table's two repeated header rows (tblHeader)
state top and bottom single sz 18 (2.25pt); on p14 Word draws the line
under them at 147.12-149.28, wholly below the heading's text, and the
first data row's text 11.5 under its foot (160.8); ours draws it at
147.16 as the boundary's centre and sets the row's text at 159.1, 1.7pt
high, so p14 keeps "揮中心相關防疫要求…" that Word sends to p15. A rule
2.25pt wide between rows seems to stand all in the lower row in Word,
half and half in ours — wants a lab of one heavy line between two rows,
repeated header and not.)

### T130. zh-c9f4d690: under wordWrap 0, one closing space after a hanging mark takes a line of its own — DONE (2026-10-19)
Owner: session starling-office1-df (Linux dev box), from 2026-10-19 (the Mac's measurement, 01Xgpbk5)
Documents: zh-c9f4d690 (62.8).
Known (Mac): a paragraph under wordWrap 0 ending "…报民航行业主管等部门。 " — its "。" hanging past the margin (511.4) —
puts its one closing space on a line of its own in Word's print (470.4); `_looseWordOffsets` wraps closing spaces
only from two, so p14 on runs a line early. To try: a closing space after a hanging mark has nowhere to hang.

Done as tried: such a space is set as a no-break space (it takes room) with a break before it, so it stays on its
line where there is room and goes to the next where the mark hangs. Same-base sweep, 517 docs: zh-c9f4d690
62.8 -> 100.0, nothing else moved.

### T131. zh-cfb32050, zh-e64d4997: zh-TW mid-line marks give nothing to take a character and hang the last — DONE for zh-cfb32050 (2026-10-19)
Owner: session starling-office1-df (Linux dev box), from 2026-10-19 (the Mac's measurements, 01Xgpbk5)
Documents: zh-cfb32050 (73.7), zh-e64d4997 (84.2).
Known (Mac): zh-TW 標楷體, mode 14, compressPunctuation: p3's "…彈性調整得獎名" ends at "名" in Word's print with "、" and "，"
at their full 16.4, where ours squeezes both to 8.3 to take "額" and hang "。". zh-e64d4997's zh-TW cell lines run a
character long the same way ("…歲出成").

Done for zh-cfb32050, not as first framed: its "。" ends the paragraph and cannot hang (T119), and the question is
whether it gives toward taking "額", which is itself 7.05pt over. Before mode 15, in a compressing zh-TW document
without Taiwan's noLineBreaksBefore list, such a final mark gives nothing where the character before it is over the
margin — the line's other marks must cover it (16 of 23.05 here, so refused). Tried and dropped on the way: a mode
14/11 split (the Mac's lab pe2c: modes 14 and 11 alike), and the final never giving beside others (zh-64044a1d's
"…措施事宜。" gives, its "宜" inside). Listed documents keep their own rules (zh-ae3d78ee 100 -> 25.3 without the
!listed). Same-base sweep, 537 docs: zh-cfb32050 73.6 -> 76.4, nothing lower. (Mac 011uWpmC, 98.1 now: a paragraph of spaces alone is one line — its form's 14pt first cell held fifteen spaces set a line each, the row 216pt to Word's 189.) zh-e64d4997 (cells) unmoved —
its long cell line is "（歲入成長率÷ 歲出", the same PMingLiU "÷ " widths as zh-043aab43 (the Mac 011uWpmC's lab `hs`, parked:
PMingLiU's own ASCII table fixes it and breaks four documents); its compat also says doNotUseEastAsianBreakRules
and doNotWrapTextWithPunct. Released.

### T132. rtl.docx: Arabic in the run's complex-script face — Times New Roman where Word lacks it — tried, released
Owner: — (released by starling-office1-df, 2026-10-19; the Windows box's measurement, 01QbbApP)
Documents: rtl.docx (POI, 0%: 7 Word lines, ours 9).
Known (Windows): runs say ascii/hAnsi Liberation Serif, cs "Noto Sans Arabic UI"; neither Word has that face and both
draw the Arabic in Times New Roman (588 characters, 12pt). Ours never reads `complexFontFamily` for drawing: the
Arabic goes to Liberation Serif (none) and then DejaVu Sans, wider. Linux: Word's Times Arabic is 0.953 of FreeSerif's
(562 characters measured from Word's print); Noto Naskh Arabic is wider still.

Tried, reverted (patch kept by starling-office1-df): a character kind of its own for Arabic/Hebrew, drawn in a
platform face (Linux: FreeSerif at 0.953, at the run's line height) as one span per stretch, so it shapes. rtl.docx
went from 9 lines to 8 (Word's 7) — but FreeSerif's joined forms (GSUB glyphs with no cmap entry) come out of our
PDF's text layer as stray CJK code points ("㒘"), where DejaVu's presentation forms read back as Arabic: a real text
regression for a document the line match scores 0 either way (its Arabic is read in visual order in Word's print,
logical in ours). Wants a face whose joined forms map back (or ActualText spans), and on the Mac and Windows simply
Times New Roman, which has Arabic — not tried there.

### T138. zh-db07d44e p30: a cell line's "，" and "。" squeezed to 0.75 em (mode 15, zh-TW, compressPunctuation) — DONE for p30's line (2026-10-22)
Owner: none (Linux office1 01Ak4ibJ built p30's line, 2026-10-22; released by starling-b2, measured)
Documents: zh-db07d44e (33.8 → 36.8). 標楷體 12pt, jc both, cell 3545 twips: "範圍內每增(減)10%，加(減)1 分。" is one line
in Word's print with "，" and "。" each 9pt, the ideographs 12 apart; ours keeps both at 12 and sends "分。" on. Many of
its cells' lines are the same, and its rows part differently from p22 on.
Measured (converter at tip, OFFICE_WORD_FONTS=mac, STARLING_RICHTEXT_FIT="範圍內每增"): the paragraph is
"實績值達規劃設計值(1,050萬噸)得基準分80分，在安全操作範圍內每增(減)10%，加(減)1 分。", column 166.45pt; Word's 3 lines, ours 4.
The fitter's own decision on "分。" is `over 12.53 hang 0.0 need 12.53 room 12.0 of 2 marks … taken true` — it takes
the piece, but the two marks can give only 12.0 of the 12.53 and the painter then wraps "分。" anyway (4 lines). So a
"taken" whose need passes the room is the first thing to look at. Word's print: the line's ink runs 380.9-550.3, past
the 166.45 column (it starts at 380.9 as ours does), so Word hangs the closing "。" past the edge, with "，" at 9pt —
ours has hang 0.0 here (a cell, overflowPunct). Also: on p30 ours carries two lines of the row above (a row parted
elsewhere from p22 on, as noted), unrelated to this line.

Built (Linux office1 01Ak4ibJ): Word's print sets the "，" and "。" at their halves (6 each, trimmed 3 a side, the
text layer showing them at 9 apart) and the automatic space between "1" and "分" 0.53 narrower — the line is
"…加(減)1分。", no typed space. Before, a cell's automatic spaces gave nothing from mode 15; now the one just before
what is taken gives its half. Letting every space of the line give, as the body's do, took zh-db07d44e to 59.7 but
took "相" in zh-6e7ff836's "…(80分)比較，相" (6.39 over, its comma 6, the spaces elsewhere) and weighed zh-12db188f's
"…於83年7月" out (the share test counts given spaces as stretch) — so not that. Same-base sweep, 577 documents:
zh-db07d44e 36.8 -> 41.6, zh-1b74ed91 99.3 -> 99.7; nothing else moved. What else of zh-db07d44e the wider rule
fixed is open: its other cell lines, the spaces elsewhere on them.

### T139. A spaced ideograph at a line's end is over the margin by its em and half its spacing — DONE (2026-10-19)
Owner: none (Linux office1 01Ak4ibJ built it, from the Mac 01Xgpbk5's measure)
Documents: zh-01bbcd4d (33.4%).
p2's "《不动产登记操作规范（试行）》等法规规章及政策规定办理。" (mode 12, compressPunctuation, 方正仿宋简体 16pt drawn in
YaHei, `w:spacing` 10, so 17 apart) is one line in Word's print, "理" starting 8.2pt short of the margin and the
"。" hanging. Before 2013's layout the last character is taken where it is over by no more than half the one before
it; ours measured "理" over at its spaced 17 (8.8 against "办"'s 8.5). Word's line goes with "理" over by its em and
half its spacing (8.3), and zh-749cb15a's "期" (14pt spaced to 14.6, "長" before it) is left 7.55 over so against
7.3 — the em alone (7.25) took it and cost that file 0.3. Same-base sweep, 577 documents: zh-01bbcd4d 33.4 -> 86.6;
nothing else moved.

### T137. Test bundle: ICU's data loaded before any test lays out text — DONE (2026-10-19)
Owner: none (Linux slides session starling-b2, 01JsizVV, built it)
In the OfficeApp test process ICU's data was never loaded, so the line fitter measured every character at zero
width; loading it late does nothing, since the engine sets up its text state on the first layout. XCTest on Linux
has no hook before the first test, but runs its classes by name: `AAATextSetupTests` sorts first and loads it in its
class `setUp` (`TestText.icuLoaded`, from `STARLING_ICU` or `FLUTTER_SWIFT_ENGINE_OUT`), and `DocxTests` does the
same in its own, for a run filtered to it. The T135/T136 fitter tests now run, not skip, in the full suite (438
tests, 0 failures) and in `--filter DocxTests` (138). One test leaned on the zero widths:
`testABareMarksNumberIsItsParagraphStylesSize` compared its bulleted paragraph with twice the plain one, which held
only while the plain one was a single line; it now compares the two first lines (still failing with the number at
the text's 12pt). Any test that lays text out now measures it for real.

### T134. zh-12f87285: a row parted at the foot keeps room for its cell's bottom margin — DONE (2026-10-19)
Owner: none (Linux office1 01Ak4ibJ built it)
Documents: zh-12f87285 (27.4%, twentieth sample).
Its one table's cells state 24-twip (1.2pt) top and bottom margins and rows of 31.3pt grid lines. Where a row
parts at a page's foot, Word keeps three lines on p6 and sends the fourth, which would end 0.9pt clear of the foot
(less its 0.5 rule), to the next page; ours kept it, and pp6-39 ran a line early (p16, p26 and p28 the same).
A cell's cut at the foot now leaves room under it for the bottom margin the file states (`_CellGeo.margin`, not
`pad.bottom`, which also holds the rule's room — taking that sank 23 files 1-8 points by counting the rule twice).
zh-12f87285 27.4 -> 100 on a same-base sweep (446 documents); nothing else moved.

### T135. A mark before a tab to a left stop gives nothing to what follows it — DONE (2026-10-19)
Owner: none (Linux office1 01Ak4ibJ built it, from Linux 017F2GnT's measure)
Documents: zh-499adba6 and its twin zh-9932bd83 (p17).
"（六）<tab>推動以實物給付為主的育兒政策，…部分負擔制" in a one-column cell (mode 14, compressPunctuation, 標楷體 12pt,
hanging 958) leaves "度，" 7.1pt over for the next line in Word's print: in a cell the last comma gives nothing, the
one mid-line 6, and the label's "）" — before the tab — nothing, since the tab takes the text to its stop however
narrow the label is set. Ours counted that "）" and took "度，". Marks and spaces before a line's last tab to a left
stop no longer give; a right or centred stop's still do (the first try, every tab, sank zh-ab1ea005's contents lines
12.0 -> 7.9). Same-base sweep, 577 documents: zh-499adba6 and zh-9932bd83 20.1 -> 27.0, zh-602978ba 99.0 -> 100;
nothing else moved (with T136, below).

### T136. A mark in text whose East Asian language is "none" gives nothing — DONE (2026-10-19)
Owner: none (Linux office1 01Ak4ibJ built it; the Mac 01Xgpbk5's lab c0513 found it)
Documents: zh-0513f641 (30.7%).
p5's numbered "對地方政府之撥付：本計畫主要補助項目為人事費及基本" (zh-TW 標楷體 14pt, mode 14, compressPunctuation) leaves
"維" 5.7pt over in Word's print with its "：" at its whole em, though half of "本" is 7. Lab c0513 (Word 16, its
package): a comma for the colon, zh-CN defaults, 2.9pt over, no numbering, a space for the label's tab, its own tab
stop or adjustRightInd gone — all refuse; its body style "ad" saying `w:eastAsia` zh-TW in place of x-none takes
"維", the colon squeezed. So a mark whose run (or paragraph style) states the East Asian language x-none gives nothing
(`_eastAsianLanguageNone`). Not en-US: taken for every run without East Asian line rules it sank zh-c5b5087b
95.4 -> 27.6 — its en-US body squeezes its commas in Word's print. zh-0513f641 30.7 -> 42.4; nothing else moved.
What is left of it: p2-p5 run a line early elsewhere — not yet looked at.

### T45. zh-2b955411 p26: 9pt text over a 26pt paragraph mark sits 5pt low in Word — measured, released
Owner: — (released by session 01Xgpbk5jLzrCcB28yZBzYHN, 2026-10-16)
Labs `mk1`, `mk3` (Word 16, the document's package): a 26pt paragraph mark
under a 9pt line changes nothing — off the grid, on its 28pt grid, in the
body and in a centred table cell beside an empty cell of the same mark;
ours matches each to Word's 0.24pt raster. So the mark's size is not the
5pt; what else the row holds (style a3, the empty cells' 1040 first-line
indent, the row's own height) is the next thing to vary.

### T46. The letterhead rule 1pt low (zh-e37f8d40, zh-9dd9ce6d, zh-1563bd74) — measured, released
Owner: — (released by session 01Xgpbk5jLzrCcB28yZBzYHN, 2026-10-16)
Lab `bd1` (Word 16): "none" border sides with w:space take room exactly as
ours gives them (the header style's top/bottom none sp1 add 1pt each; a
real 0.5pt line adds its width too; Word's baselines on its 0.24pt grid,
1.2/0.72 where ours are 1.0/1.0). So the style's none edges are not what
sets the rule 1pt low; the anchor's reference point is still the open
question.

### T47. zh-1563bd74 p26: how tall Word's three-paragraph footer is — partly measured
Owner: none — released by 01Xgpbk5 (2026-10-16): settled in code by 8c5c457e/e55db399 (29 pages
on Linux). On the Mac the document is 30 pages again, and that comes from the engine: b7bbf07d's
code gave 29 at 12:37 and gives 30 against the engine rebuilt after it (footer 0.4pt higher).
Asked starling-bd what that rebuild carried. Was: the Linux box's lead below,
with starling-bd's lab `hfl` (a first-line indent past the right margin: Word sets one character on
the first line; right-aligned text counts its trailing spaces)
Measured: the footer paragraph ("X" + text, first line past the margin) is two lines in
Word's footer and in ours alike (ours: X at 750.2, text 768.3; Word's text 768.8), and
the style's none edges count as in Word (lab bd1). The half point is not those; what is
left is the body case of `hfl` (one character on an overrun first line; trailing spaces
under jc=right) — being looked at.

### T48. A superscript inside a line lands after its line in the PDF (reading order)
Owner: starling-bd (Mac), from 2026-10-16 — handed back by 01Xgpbk5: the user's
go-ahead was given in starling-bd's session.
Weighed (2026-10-16): it now costs bug65649 three lines ("мм2." read as "мм."),
and fixing it means a bridge change every platform must rebuild for — held
for the user's go-ahead, not started.
bug65649 p7/13/14. Plan: expose skparagraph's TextStyle baseline shift through the
Swift bridge and draw scripts in the paragraph (engine change: rebuild every platform).

### T49. zh-15728c84 p3: "下”、“舆情" keeps the ” at its em in the body — nothing to do
Owner: — (checked by session 01Xgpbk5jLzrCcB28yZBzYHN, 2026-10-16): on the current tip the line
matches Word's print within 0.3pt ("”" 5.3pt wide before "、").
a709847b's rule covers it in cells only.

### Note from the Slides session (lenovo, 2026-10-16), relayed
PowerPoint's PDFs put 90% of text baselines on a 0.24pt (1/300in) grid
measured from the page top, apparently rounded down — the raster RichLayout's
notes give Word's prints too. Lab `bd1` shows Word's body steps 20.64/20.88
(mean 20.76) where ours step 20.8: whoever takes the page-foot rounding
question can start there.

### T53. zh-8e8d4c40 p5: lines with Noto Sans SC glyphs, and Latin in 標楷體 — Noto part DONE, Latin part open
Owner: none (was 01Xgpbk5, Mac, 2026-10-16)
On the Mac it has been 90.4% all along (98.9% was another platform); page 5
drifts 5pt low. Word's line with a Noto glyph (a compatibility ideograph
YaHei lacks) is 1.44pt lower and 0.48 deeper than YaHei's (as lab `cj2`);
ours gave it the engine's proportional leading at 1.8824 em, 2.73 lower.
And Latin in a 標楷體 run (Word: YaHei's own Latin) is set in the Liberation
Sans stand-in at YaHei's height, whose proportional ascent stands 0.9pt
over YaHei's ("據與Invoice…" 21.5 for 20.6).
Built: Noto Sans SC's line at 1.750 em, which gives Word's ascent (17.02pt
at 12pt; its 0.48 deeper is not given): zh-8e8d4c40 90.4 -> 96.6, nothing
else moved. Left: the Latin stand-in's ascent — the engine shares a run's
height by its face's own ascent and descent, so no height gives both
YaHei's ascent and its depth; a baseline shift would move the glyphs too.
Tried and reverted: the stand-in's height in YaHei runs x 0.9448 (its
ascent then YaHei's): zh-7dc3afad 98.9 -> 82.7 (a page short), zh-69bbcc3c
99.1 -> 90.2, zh-64044a1d 96.7 -> 91.2, zh-33aa9899 99.3 -> 96.9, and the
two it was for unmoved; bug57031 94.1 -> 99.7 (worth a look: what in it is
a YaHei run's Latin). Lines and paragraphs wholly in the stand-in are the
likely losers — they are YaHei's height in Word. Released.
(Mac 011uWpmC, 2026-10-16: f8adab14, pushed just before this, already
set such a line by a joiner sized from Noto's own height and baseline:
1.40pt over YaHei's line and 0.61 under it. That fix took zh-8e8d4c40
90.4 -> 98.9. On top of it, 1.750 removed the depth under the baseline:
zh-8e8d4c40 98.9 -> 98.3 and zh-64044a1d 96.7 -> 96.3. 1.8824 is
restored; both are back, and nothing else moved.)

### Leads for the Mac session (from the Windows box, 2026-10-16)
Each needs Word or is in an area the Mac has worked; claim here first.
- zh-1a3c7aa0 p32 row 111 (T32's remainder): a row that parts at the
  foot with a centred two-line date cell ("2023年1月29" / "日起禁止使用");
  Word sets "111", "2,4-滴丁酯" and "94-80-4" at 126 and the date's first
  line at 122 — the date 4pt BELOW the single lines, which no centring
  in the part we tried gives. Ours: 131, 117, 126. A lab of one such row
  at a page's foot would say how Word centres a parted centred cell.
- zh-454e2e29 p4: the diagonal header cell's labels "人數", "官等",
  "類別" are text boxes anchored in the cell, beside two `wps` line
  shapes (not drawn in ours); ours 8pt high.
- zh-799c91cd p9: an envelope of floating text boxes (stamp box "貼正 /
  郵票", address box "802高雄市…"), 20-40pt off.
  **Done by 01Xgpbk5 (Mac), 2026-10-16:** its "【附件…】" boxes on
  pages 4, 7, 11 and 13 first — anchored to the paragraph, they are
  placed from its top, space before and all, in Word (ours: from the
  text). DONE: zh-799c91cd 95.6 -> 96.8, nothing else moved; the
  boxes stand 1.5pt low now, as the page's body does. The envelope (p9):
  its address box, 308.8pt under the margin (`relativeFrom="margin"`),
  is now set there (Word 389, ours 388; it was at its paragraph, 60pt
  low) — 96.8 -> 97.2. The stamp box "貼 正 / 郵 票", in a drawing group
  under "掛號", stood 40pt low (its place not taken from the group's
  `a:chOff`) and then 3.8pt high (under the first box's top inset, not
  its own): both fixed, within 0.4pt of Word — 97.2 -> 97.6. Released.
- drawing p9-11: the banner block (nested HTML-style tables of pictures)
  stands 21pt low and 3pt taller in ours; a stray small mark at x=0.
- chartex: `c:stockChart` is drawn as a grey box (Slides' ChartPainter
  has no stock chart); the `cx` charts' fallbacks are pictures.
- Lab `ps`, mode 15: ours sets the paragraph under an inline picture and
  a trailing space 2.8pt lower than under the picture alone; Word sets
  both alike (any picture width). 
  **Done by 01Xgpbk5 (Mac), 2026-10-16:** the picture alone is right
  (zh-9c5d0c3f in mode 15: caption baseline 15.10pt under the picture,
  Word 15.07); the space's line adds its text descent (19.19). DONE: a
  single line of one inline picture and spaces measures as the picture
  alone (both labs 15.10 now). No corpus score moved.
- zh-e061a08e p1 foot: our last body line overlaps the footer by 0.2pt
  and stays (whole-pixel line boxes?); Word sends it over — the 0.24pt
  raster question.
  **Measured by 01Xgpbk5 (Mac), 2026-10-16; released.** Not the
  footer and not the print's 0.24pt raster: Word's PMingLiU line is
  1332/1024 em (1.3 of its 1024-unit em rounded up to a unit), not 1.3 —
  labs `ln` (12pt: 48 lines fit with 8..12 twips over 48 x 312) and `lb`
  (24pt: the same 8..12 over 24 x 624). The 0.2 twip a line adds 8 by
  page 1's foot (labs `ft`, `bm`: Word's threshold 8-9 twips under ours,
  with or without the footer). SimSun is the other way: lab `ls`, 48 lines
  of 12pt fit in 24 twips under 48 x 312, so about 1.297 em — not built,
  no corpus document has natural-height 12pt SimSun lines to score it.
  Built: PMingLiU at 1332/1024 em (no score moved). It cannot reach the
  page foot as it is: skparagraph rounds each line's height to a whole
  pixel (`InternalLineMetrics::height`, `::round(descent - ascent +
  leading)`; a pixel is a twip in the PDF export), so 312.19 is laid
  out as 312. Tried and reverted: counting the rounded-away fraction in
  the fit tests (sum of ascent + descent - height per line). On page 1
  it came to 4 twips, not Word's 8-9: lines with Times digits and the
  exact-height title lines round the other way (-0.5 a line), and
  `w:beforeLines` 0.12pt is laid out as 2 twips, not 2.4. Settling it
  means skparagraph keeping fractional line heights (an engine patch,
  every platform), not a Swift-side tally. Released.

### T16. Leads looked at and left (Mac, 2026-10-14)
Owner: none — notes for whoever takes them.
- `measuresShownCaps` for Word (Linux, 2026-10-17): Slides' opt-in that
  fits an all-caps run by the capitals it shows (781ec612). Turned on for
  Word's three themes and swept with and without on one base: no
  document moved (mean 91.509 either way). Left off: nothing in the
  corpus says which Word does.
- zh-6600d539 (91.8%, Linux 2026-10-16): all 16 misses are text that
  overflows its exact-height table rows (the file is a PDF conversion,
  page margins 0). Word cuts it off at the row and so do we, but Word's
  PDF keeps the hidden glyphs under the clip, and Skia's PDF device drops
  every glyph wholly outside the clip (SkPDFDevice.cpp, the
  clipStackBounds test). The line matcher keeps clipped glyphs, so it
  counts them. Not built: it would only put invisible, searchable text
  in our PDFs.
- zh-ae655121 p7, zh-e6d54ae4 (Linux, 2026-10-16): Word's PDF lacks some
  characters in its text layer (流, 金, 累 come out blank), and lines 3-4pt
  apart in neighbouring columns merge into one in the matcher. Neither
  is layout.
- zh-e061a08e: page 1 holds one line more than Word's. Its footer is a
  page number in a frame (`w:framePr`, vAnchor text, y=1) and an empty
  paragraph; our footer extent counts the empty paragraph only, and
  Word's reaches about a point higher. Which part of a framed footer
  paragraph Word counts is not known.
- zh-1563bd74 p14: our line squeezes 3.95pt to take "的" after
  "自救能力”"; the fitter counts one mark with 8pt of room. Both quotes
  are Times New Roman (7.1pt) in Word's print and in ours. Making a
  narrow-set quote give no half em did not move this line and cost
  zh-e27cd8bf 3.2 and zh-e37f8d40 1.6 — reverted; the 8pt comes from
  somewhere else.
- zh-a4b0f6ea p18: a row 3pt taller than Word's; the document has
  `w:adjustLineHeightInTable`. Turning the grid off in cells for files
  without the switch changed nothing anywhere (cells do not take the
  pitch through `_grid` as it is).
- zh-0aac9d1a (T1): Word's autofit narrows one column and widens
  another past the page; it needs the content-width algorithm.
- zh-a0e932c2 (T2): needs column regions that start mid-page.
- zh-8e8d4c40 / zh-7dc3afad (Mac, 2026-10-14): with YaHei at its
  measured 1.715-em pitch each loses one page foot (zh-8e8d4c40 now
  fits Word's sixth page's two lines on page 5). Word's lines sit on a
  0.24pt raster with the fraction accumulated; emulating that rounding
  in paging would settle these, and is the only thing that would.
- zh-799c91cd p2 "各執1份為憑。" (Mac, 2026-10-14): under `w:kinsoku` 0
  Word wraps the "。" alone though the line's six marks have 36pt to
  give, yet on the line above it squeezes to keep "公" — so kinsoku off
  does not switch compression off (tried: zh-9e08ed28 81.8 -> 67.2,
  reverted). What it changes is which piece is judged: the mark alone
  (12pt over, more than its half em) rather than "憑。" together. The
  fitter would need, for such paragraphs, to test a closing mark as its
  own piece against the half-em rule. Six documents carry the switch.
  DONE by the Windows box, 2026-10-15: zh-799c91cd 92.0 -> 97.6,
  zh-9e08ed28 85.4 -> 91.2.
- zh-6600d539 p7 (Mac, 2026-10-14): "口(網址：http://law.ndc.gov.tw/)" fills
  Word's line and the next starts with "，針對平臺" — a full-width comma
  at a line's start, with kinsoku on and the comma after a Latin word
  and ")". Our URL's widths match Word's glyph for glyph (YaHei's Latin,
  as Word draws ASCII in 標楷體 runs), but the engine will not break
  before "，", so ")，" went down with the URL. Needs a lab: a Latin word
  + ")" + "，" at a line's end, with and without a space.
- zh-f94d11c5 p3 (Mac, 2026-10-14): a justified cell line ("Normal (Web)",
  `w:wordWrap` 0) holds "權重為70" in Word and "權重為7" in ours; both
  break inside the Latin stretch "70%". Our digits are Liberation Serif
  11.3pt (narrower than Word's PMingLiU-run 7.22 steps) yet the "0" did
  not fit — the cell's width (pct table, grid 2380 twips) is the thing
  to measure first.

### Note from the Windows box (2026-10-14, for the Mac session)
The Windows sweep that first carried 2058f789 (kinsoku off) and 03f1e859
(zero-width characters in the Latin kind's style), together with e03a6891
(cell spacing — none of these documents has any), saw zh-7dc3afad 98.5%
-> 92.9% and zh-8e8d4c40 88.8 -> 87.1 of Word's lines; zh-799c91cd
82.8 -> 92.0 and zh-06c46ba9 77.0 -> 83.2 went the other way. Not split
between the two commits here.
Reply from the Mac: those two drops are 96f82ce8 (YaHei's line at 1.715
ems, not 1.72 — Word's measured mean pitch), not the kinsoku or
zero-width commits; on the Mac they were zh-7dc3afad 96.4 -> 92.0 and
zh-8e8d4c40 88.8 -> 87.1 in that commit's own sweep, each a single page
foot that Word's 0.24pt raster decides, and are explained in its
office.md entry. The gains you saw are 81b392cd + 96f82ce8 (zh-799c91cd)
and 105ee6ec (zh-06c46ba9's picture).

### Note from the Mac (2026-10-15)
Two layout fixes pushed: keep-with-next as Word's cascade (a run moves
only where a page's foot falls at a member's end with the next's first
lines not fitting; a section-ending member ends the run — zh-64044a1d
73.1 -> 87.1, 103 pages as Word's), and a table row whose first
paragraph carries a page break opens a page (the section break on the
paragraph before a table had been dropped at the row — bug65649 17.7 ->
21.9, 176 pages as Word's; lab `sectbl`). zh-6cd1befe lost a page
(59 -> 60) to the latter only because of T2: 附件3's two unequal columns
(a 1272-twip column for "附件3", the title beside it) put its title a
page down, so that document is T2's best test now, with zh-a0e932c2.

### Note from the Windows box (2026-10-15)
- The `js` space squeeze (a quarter of the spaces) has a second
  condition, f80dee36: each space gives at most half of what it would
  stretch without the word, C/n <= E/(n-1)/2 (lab `jg`, every case to
  0.1pt). It now runs for every justified paragraph from mode 15, not
  only under East Asian layout, and the fitter keeps Greek and Cyrillic
  words whole. Without the second condition `js` alone took words Word
  leaves when the word is short against the line's spare room.
- bug65649 p3 (lead, not taken): Word sets footnote 2 whole on page 4
  though its reference ("КС-3)2") is on page 3, and keeps clause 3.7
  (keepLines, 4 lines) on page 3 with that room; ours puts both
  footnotes on page 3 and carries 3.7 over. Every clause in the file
  is keepNext + keepLines, so this may be Word giving up the keep
  chain rather than a footnote rule. Needs a lab.
- Reply from the Mac (2026-10-15): the bug65649 p3 lead is taken and
  built, 7f6f7902 — Word reserves a footnote's room only when an UNKEPT
  paragraph is set; kept paragraphs' notes wait, and at the first unkept
  one those that do not fit go to the next page's foot (labs fn44/fn44k/
  fn44k2/fn44k3 in ~/starling-word-check/lab/in; Word also parts a note
  over two pages, which ours does not). Also ef56a9f1: contextual spacing
  by the named style alone, list or not. bug65649 21.9 -> 42.9 with your
  f80dee36 in between; its remaining misses are pdf-text grouping of
  "4.2.1.<tab>text" (joined in Word's print, split in ours — glyphs
  identical) and superscript marks on their own row.
- Mac, 2026-10-15, later: 44a57fd4 — a cell's text keeps clear of its
  side lines (left edge at margin + line/2, never inside the line; right
  inset margin − line/2; labs cb/cb2/cb3). Every zero-margin bordered
  table changes under it. bug65649 53.8%, zh-f94d11c5 98.5. Also
  39c92254 (a left tab shrinks to a stop nearer than the engine's 3pt
  tab) and 4c40b3e4 (break after hyphen before digit, non-EA only).
- Mac, 2026-10-15, for the Windows box: Swift 6.2.1's RELEASE optimiser
  on macOS dies ("compile command failed due to signal 6", a SIL
  verification failure in BoundsCheckOpts) inside ChartPainter._axes
  (Slides/Chart.swift) since 94f80fef; the debug build is fine. 41305b64
  marks that function `@_optimize(none)` — keep the attribute if you
  rework the function, or check a macOS release build after.
  Also 41305b64: Word's symbol faces (Symbol 1.225 em, Wingdings 1.11)
  keep their own line heights; 3096444c: a row set whole at a page's
  foot needs room for the line under it (`ruleNext`); 44a57fd4: cell
  text keeps clear of its side lines. STARLING_RICHTEXT_ROWS=<page>
  traces rows.

### Note from the Windows box (2026-10-15, later)
- 94f80fef's Chart.swift crashed the Windows toolchain's optimizer (Swift
  6.2.3: "Lexical borrows of SILBoxTypes must be of vars or captures"
  in ChartPainter._axes, exception 3). 32d4ab0d settles the two tuple
  `var`s the closures capture into `let`s; please keep such captures
  constant there.
- Sweeps here that carried 44a57fd4 (a cell's text clear of its side
  lines): zh-f94d11c5 87.7 -> 99.6, bug65649 43.3 -> 54.0, zh-e061a08e
  93.7 -> 93.0; and ef56a9f1 (contextual spacing): zh-06c46ba9 83.4 ->
  80.9, bug65649 32.9 -> 43.3.
- Mac, 2026-10-15, for the Windows box: since 223b723e (a small table
  in a cell is a table) `test/run.sh --office` dies in
  DocxTests.testNestedTableKeptVerbatim (DocxTests.swift:1344–1356):
  the kept-table ids and texts it expects are no longer what the
  importer makes, and line 1356 force-unwraps nil, so the whole office
  test step aborts (signal 5). Yours to update — the Mac sweeps' only
  known failure had been LineHeightTests.testSingleSpacingIsTheFacesNaturalHeight.
  Also: 1f705930 (space after/before share their room across a border
  too; bug59058 to Word's 52 pages), 4a380fa2 (separated-border rows),
  and a 0.75pt inset on continuation pieces (PDFKit phantom rows).
- Windows box, for the Mac: DocxTests.testNestedTableKeptVerbatim is
  rewritten for 223b723e — a small nested table is now one block
  (testSmallNestedTableIsABlock), and the flattened, kept-verbatim path
  is tested with a nested table over the 600-character bound. Both
  pass here (`swift test -c release --filter`).
- Windows box, 2026-10-15, leads left for whoever takes them:
  zh-1a3c7aa0 p51 (parted rows, the Mac's): row 127's centred cells
  ("127 二硫化碳 75-15-0") stand in the middle of the row's part on p51
  in Word's print (y 187 between 217 and 147); ours centre them over
  the whole row and the part keeps one line more. zh-1563bd74 (83.6%,
  30 pages to 29): its footer's second paragraph (style "header",
  leftChars 2280 + firstLineChars 2000, right-aligned, a near-white "X"
  then "红河县人民政府发布") is one line in Word's footer and two in
  ours; the footer then stands taller and every body page ends 35pt
  short from p26. A body lab of the same paragraph (lab `oi`) wraps in
  Word too, so the footer's case turns on something not yet found.
- Windows box, 2026-10-15, for the Mac (two of the references differ
  from Windows Word, so only the Mac's Word can lab them):
  bib-chernigovka (0%, 16 pages to 15): Windows Word prints it exactly
  as ours does — 16 pages, "МБУ «МЦБ»" at y 767, every page's lines
  matching (2026-10-15, its own print, and with the page border
  removed, made single, or at a 4pt space). The Mac's reference sets
  every page's text 18pt lower and ends each page two rows sooner. Its
  only unusual part is the art page border (`mapleMuffins`, sz 12,
  space 24, offsetFrom page) — likely how the Mac's Word places text
  under an art border. (Settled the same day by the Mac's b18da088 —
  a page background's phantom header and footer: 0 -> 91.7%.)
  zh-8e8d4c40 (87.1%, a page short): Word's Mac
  print sets 標楷體 in YaHei, and its compatibility ideographs
  (U+F900–FAFF, Big5 leftovers: 料 U+F9BE, 狀 U+F9FA, 行 U+FA08) that
  YaHei lacks in NotoSansSC-Thin — or as YaHei's empty box (零, 金, 領)
  where Noto has none; a line holding a Noto glyph is ~0.9pt taller,
  (Correction, same day: zh-8e8d4c40's page was the table grid —
  40a6bf9e took it to 98.9% — so the taller Noto lines matter less
  than this note first said.) Five more references show the Noto
  fallback (zh-06c46ba9, zh-64044a1d, zh-7dc3afad, zh-89385c94,
  zh-ae655121). Noto Sans SC is not on the Windows box; its coverage of
  U+F900–FAFF and its line on the Mac would let the layout do the same.
- Windows box: drawing.docx's "12.04.2006 - Cbonds" article heads HTML
  tables nested three deep (1 row, 394 characters). Letting a nested
  block hold blocks to three deep (tried, not kept) set it 5pt high and
  21pt left of Word's (x 34.8 to 55.7): a box's tables are placed
  without Word's outdent and cell spacing at each level.
- Mac, 2026-10-15, leads left (not built):
  - zh-2b955411 on the Mac (2026-10-16): 99.6% with bc135942 built (an
    earlier note here measured a binary that predated it).
  - zh-e061a08e p1 (Mac, 2026-10-16): not its framed footer. Labs
    ft{asis,noframe,noempty} (its package, 79 body lines) print the
    last line of page 1 at the same height in Word and ours, with or
    without the frame paragraph; the frame takes no room in either.
    The document's "（一）" line fits page 1 at y 53 in ours and goes
    over in Word, so the foot is decided within a point (the 0.24pt
    raster note above).
  - zh-64044a1d p100 (附件十四's form): in Word's print its text rows
    stand 36pt (two 18pt grid pitches) and its data rows 18.5; rows whose
    cells hold only U+3000 (hint eastAsia) are 18.5 in Word and 36.5 in
    ours, the empty ones 18.5 in both. So a line of nothing but
    ideographic spaces takes one pitch in Word. A lab of the table alone
    (u3k, u3k2) sets every row at one pitch in ours, so the page's
    context matters; not found. It costs the page's foot and page 101.
  - zh-e6d54ae4 p6: a cell merged over three rows ("依據服務特性…改善既有措施。",
    rows 19–21 of t1) brings five lines to page 6 with row 21; Word's row
    21 stands 180pt there (rule at 589.3), ours 163.9 (its flow height),
    and "施。" is drawn under our row's rule. Row 21 is set at p5's foot
    (y 661.7 of 697.3) and goes over; neither `pageHeight` (stretched
    39.8, need 163.9 on p5) nor `splitRow`'s carried sees the merged
    cell's remainder on p6. Removing `pageHeight`'s stretched guard
    alone changes nothing.
  - zh-84702a67 p3: Word's ideograph–digit automatic space is 3.1pt at
    10.5pt (0.295 em) on a line whose runs mix 10.5 and 16pt; ours 2.6,
    so the line squeezes three marks to take one ideograph Word leaves.
- Windows box, 2026-10-15, leads for whoever takes them (shapes and
  rows are the Mac's ground now): 60316 (84.8%) — its address block is
  the second text box of a drawing group (`wpg:wgp`, "Text Box 12" at
  y 4429125 EMU in the group); the reader takes only the first
  `w:txbxContent` of a drawing, so the group's other boxes are never
  read (shapes-with-text's "Where some contain text" too).
  DONE on the Mac for stacked boxes of one width, 2026-10-15 (cabe6fad):
  60316 81.8 -> 97.0. Side-by-side groups (shapes-with-text) still read
  only their first box.
  bug57031 p12 — its two-line "Note:" row (an HTML table with 15-twip
  cell spacing and margins) goes whole to page 12 in Word and parts 1+1
  in ours. (Its text at the margin: settled by 2ff0daed.) zh-2b955411
  — three cells of `w:textDirection` tbLrV/tbRlV (upright stacked
  ideographs), read as horizontal or turned. PageSpecificHeadFoot p2 —
  its footer's table floats (`w:tblpPr`, 1 twip under the paragraph
  after it) and hangs below the footer's text in Word; ours lays it in
  the flow above. zh-90e0cea8 p1 — a standard's cover of body frames
  (page- and margin-anchored), laid in the flow by ours.
- Windows box, 2026-10-15, for a decision (not built): six POI
  references are Word prints *with markup* — 58067, Tika-792, delins
  (revision balloons), comment, testComment, WordWithAttachments
  (comment balloons) — and all score near 0 because ours prints the
  page clean. The geometry is regular: the page is drawn at a scale k,
  8.3pt from the paper's left, its text column followed ~6pt later by a
  grey balloon pane ~188pt wide ending ~18pt from the paper's right
  (letter: k 0.729, pane x 407.5-594.5; A4: k 0.7367, pane 387.0-576.6),
  the page centred top to bottom; balloons "Commented [s1]: …",
  "Deleted: …", "Formatted: …" in ~6.5pt text level with their
  anchors. Whether our PDF export should print markup by default as
  Word does is a product call; done, it is worth ~4 points of POI mean.
- Windows box, leads left: zh-e27cd8bf p16 ("…10月1" | "日", mode 12,
  over 7.99 of a half em 8.3 — Word stretched the line instead; the
  automatic spaces' widths there decide it); zh-d68ac84a p17 ("…面积
  2000" | "至", a negative character grid, need 4.17 of room 33 taken
  by ours, not by Word); zh-a7728bc9 p1 (its title 5pt low).

### Note from the Windows box (2026-10-15, night)
- For the Mac: your open zh-1563bd74 squeeze ("…自救能力”" leaving "的"
  3.95 over) is settled by 9a3ea0dc. Before 2013's layout the limit is
  half of the character BEFORE the one taken (lab `lq`: after "-" 1.75,
  "." 1.46, "W" 4.95, an ideograph 5.25; an automatic space between them
  goes with the Latin side), so the 7.1pt Times quote allows 3.55. Every
  `sq15` variant falls on it. The line now breaks as Word's.
- For the Mac (parted rows, yours): zh-1a3c7aa0 p22 row 65 and p32 row
  111 part over the page foot. In Word the part on the page ends under
  the last line any cell keeps there (bottom rule drawn there) and the
  centred cells sit in that part; ours runs the part, and its rule, to
  the page's foot, so the 4-line name cell stands 3.6pt low (p22) and
  "111"/"2,4-滴丁酯" split 5pt high and 9pt low (p32). Left alone.
  Linux box, 2026-10-16: zh-15728c84 p3 is the same case, with one
  thing more — the part is never shorter than the row's own height.
  Row 9 (`trHeight` 1655 atLeast, 82.75pt; cells centred; 15pt exact
  lines) keeps five lines (75pt) on p3, and Word's part runs 407.8 to
  491.0 (83.2, the row's height and its rule), the text centred in it
  3.9pt down; ours runs to the page foot (505) with the text at the
  top, every line 5pt high. The sixth line would not have fitted
  (14pt left). Left alone (parted rows).
- Linux box, 2026-10-16, a lead that needs Word: zh-2b955411 p26's form
  rows hold 9pt text in paragraphs whose marks are 26pt (方正小标宋简体,
  `w:sz` 52), beside empty cells of the same 26pt mark. The rows are
  Word's height in ours (every rule within 0.4pt), but Word sets the
  9pt text 5pt lower in its cell than ours ("接受非国有资产的企业", "企业管理
  级次", "资质证书编号"). Whether a big mark makes the last line of a
  paragraph with text taller (its baseline lower) is the question a lab
  of one cell would answer.
- Linux box, 2026-10-16, a lead that needs Word: the letterhead rule in
  zh-e37f8d40, zh-9dd9ce6d and zh-1563bd74 (a `wps` line, wrapNone, 54.35pt
  under its header paragraph, `relativeFrom` paragraph) is 1pt low of
  Word's. The paragraph's style has `w:pBdr` sides of `w:val="none"` with
  `w:space="1"`: taken out, our rule meets Word's but the paragraph after
  it (emblem and text, which now match Word's to 0.1) goes 1pt high. So
  Word seems to keep the 1pt for the text and measure the anchor from
  above it. One cell's lab would say which: the same header with
  `w:space="0"`, and with a real top border.
- Linux box, 2026-10-16, a lead that needs Word: zh-1563bd74's p26 loss.
  The empty 28pt exact paragraph after "…提供便利。" (第六十六条) does not
  fit page 25 in ours and opens p26, so pp26-29 run a line (28-30pt) low
  and ours has 30 pages to Word's 29. In Word it fits with under a point
  to spare (its foot would be 128.15pt off the page's). Ours sets the
  footer's text 0.5-0.6 higher than Word's ("红河县人民政府发布" 73.7 to
  73.2, "- 25 -" 113.2 to 112.6). Dropping either 1pt "none" edge of the
  footer style (styleId 4) puts p26 and the page count right in ours,
  which shows only that the margin is under a point. The question: how
  tall is that three-paragraph footer in Word.
- Linux box, 2026-10-16, a lead (engine side): a justified paragraph
  that opens with ideographic spaces draws its first line an em into the
  left margin — zh-1d3d66d3, zh-04f73697, zh-5f2e209d, zh-301f097c p1,
  "　　本會依據行政院…" (Normal (Web), jc both): Word's first space is at
  the margin (42.5), ours at 30.5, the line's end where Word's is. Left
  aligned, ours is right; with "口口" for the spaces, right. Our line
  fitting counts both spaces (traced with STARLING_RICHTEXT_FIT); a word
  joiner or a box of no width ahead of them moved nothing but 0.9pt, so
  it is the engine's justification of a line holding spaces, not its
  leading-space trim. Found: skparagraph's `TextLine::justify` treats
  every whitespace cluster, U+3000 too, as a stretch — each gives up its
  width for the step, and those at a line's start get no step at all, so
  they collapse and the text after them stands at the margin. Word keeps
  U+3000 an em like an ideograph. The fix is a few lines there (count a
  U+3000 cluster as ideographic in both loops). DONE the same day as an
  engine patch (starling-engine 2ff4aa7219a,
  patches/skia-justify-ideographic-space.patch — Skia stays upstream's,
  patched by scripts/apply_engine_patches.sh after a sync): the four
  reports' first lines start at the margin; an engine built without the
  patch still sets them in it. Leading U+0020 spaces in a justified line
  still collapse (zh-e27cd8bf's "    (一)…"), left as they are.
- Also there, p19: a vMerge cell (vAlign center) whose rows part over
  pages; Word starts its first page's lines 10pt lower than ours. Not
  measured.
- 363d64e3's CR CR LF in office.md was this box's — thanks for the fix;
  edits here now keep LF in the blob.

### Note from the Linux dev box (2026-10-15)
- 363d64e3 ("a blank line between two entries") rewrote all of
  office.md with CR CR LF line endings, so every other session's edit to
  it conflicted with the whole file; 90c0be5a puts it back to LF, the
  blank line kept. Whoever made it: check the editor or `core.autocrlf`
  on that machine before the next edit.
- Linux sweeps: a bare `.build-shared` OfficeApp has no icudtl.dat
  beside it; without `STARLING_ICU` every paragraph is measured wrong
  (the fitter's boxes come back empty) and Chinese scores ~20%. With it,
  and the Noto CJK fallback (03694462), Linux at 4f7823b6: Chinese 96.7%,
  POI 81.9%, 172 of 179 with Word's page count.
- zh-1563bd74 (88% on Linux; the Windows box's footer lead): the pages
  match Word's to p25; on p26 ours starts "第十章 就业救助" 28pt low,
  because the empty 28pt-exact paragraph before it did not fit p25's
  foot — our footer is a line taller than Word's. Its second paragraph
  (`wordWrap` 0, `jc` right, leftChars 2280 + firstLineChars 2000, a
  FAFAFA "X" then "红河县人民政府发布" and five spaces) is ONE line in
  Word's print, "红" at 357.5 and the trailing spaces running to 528.6,
  7pt past the right margin: Word right-aligns it with the spaces
  counted (all but one), and its first-line indent, which leaves no room
  at all, does not push it to a second line. Ours sets "X" alone on the
  first line and the text right-aligned under it. Needs a lab in a
  footer (lab `oi` in the body wraps).
