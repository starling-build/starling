# Slides corpus: real decks, the four focus languages, and a line score

Planner: amd-opus, 2026-11-21, for starling-bd. This is a spec only: nothing here has been fetched,
printed or built. It is the Slides counterpart of `word-corpus-curation.md`.
The numbers were measured on 2026-11-21 over `/data/corpus-cache/test/corpus/pptx`
with a throwaway census script (`/data/s/amd-opus/slides/census.py`; it becomes `test/tools/pptx-features.py`).

## 0. What the set is today

- 561 decks, 550 of them open as zip packages; 42 MB of decks, 56 MB of PowerPoint for Windows
  prints (`powerpoint-win/`, 2026-11-07, 559 decks). The gate is `test/pptx-app-render.sh -j` against
  `baseline-win.tsv` (mean pixel difference 0.72%), with the 98 decks in `matched-win.txt` kept exact.
- **1,145 slides: 463 decks have ONE slide; only 22 have 10 or more.** 403 are LibreOffice test files
  (`lo*`), 63 OOXML/POI files and 10 fuzzer files. Only 265 decks have any text of 3 or more characters on a slide.
- Languages (from text on a slide): Han 13 decks, Hangul 2, kana 2, Hebrew 4, Cyrillic 2, Arabic 0.
  Spanish/Portuguese diacritics appear in 42 decks, but `lang=` says es 22 and pt 3: mostly test
  strings, not real Spanish or Portuguese decks.
- Features ON A SLIDE (decks): placeholders 180 (title 140, body 79), pictures 98, spAutoFit 86, SmartArt 75,
  tables 55, normAutofit 40 (fontScale 18), groups 32, 3-D 30, custom geometry 25, gradients 22, charts 19,
  cropped pictures 18, OLE 18, tabs 16, numbered bullets 15, WordArt warps 15, vertical text 11,
  RTL 5, equations 3, text columns 2. Hidden slides 2 decks; a date/time field on a slide 4 decks.

So the pixel gate is close to its ceiling on one-slide test files, and real decks are missing:
those with masters and layouts that are actually used, autofit bodies, long bullet lists, and
Korean, Japanese, Spanish or Portuguese text.

## 1. The feature fingerprint (a token set per deck)

**A. Structure** (from the XML of slides, layouts and masters; count a token only where a SLIDE uses it):
masters>=2; layouts used (distinct `type=`); each placeholder type, and whether it inherits its position (no `xfrm`) or overrides it;
`normAutofit` (with `fontScale` and `lnSpcReduction` buckets 90/80/70/<70), `spAutoFit`, none; bullets by kind (char, autonum
scheme, picture) and level >=3; `lnSpc` pct/pts, `spcBef/Aft`; tabs; text columns; `vert`
kinds; `rtl`; `anchor` and `anchorCtr`; insets; `wrap="none"`; tables (merged cells, banding
through `tableStyleId`, cell margins); charts by type (bar, line, pie, area, scatter, combo; data labels; secondary
axis); SmartArt by layout id family (list, process, cycle, hierarchy) and whether `drawing*.xml`
(PowerPoint's cached drawing) is present; pictures with `srcRect` crop, `stretch`/`tile`, SVG
(`asvg:svgBlip`), alpha mod; WordArt `prstTxWarp` kinds; groups, connectors, `custGeom`, preset
geometry kinds; fills (solid, gradient, pattern, picture), shadow and glow, 3-D; OLE and media
(their poster frames only); equations; theme font scheme (major/minor latin, ea, cs); hidden slides.
Transitions, animations, timings and notes are not printed, so they are not tokens.

**B. Text**: scripts present; the punctuation and space code points used; each font size;
the faces used AFTER PowerPoint for Windows's substitution (theme `+mj-lt`/`+mn-ea` resolved, then the
Windows font map); `lang`/`altLang`.

**C. Rules reached**: `RuleTrace.hit` names reached from Slides code (SlidePainter, WordArt,
Extrusion and Chart already have them), from one traced sweep.

The selection, dedupe and witness-floor rules are the Word plan's (§2 there), used unchanged.

## 2. Sources and licences

| source | licence | what to take |
|---|---|---|
| data.go.kr and ministry/agency sites (*.go.kr) | KOGL type 1 (공공누리 제1유형) ONLY; types 2-4 restrict commercial use or changes | Korean briefing decks (Korean government work is mostly HWP and PDF: .pptx is scarcer, so use Common Crawl, below) |
| e-Gov Japan and ministry sites (*.go.jp) | Government of Japan Standard Terms of Use 2.0 (CC BY 4.0 compatible); skip pages marked otherwise | 説明資料 and council decks (審議会資料), many with vertical text and dense tables |
| Spain (datos.gob.es, *.gob.es), Mexico (*.gob.mx, Libre Uso MX), Argentina (*.gob.ar, CC BY 4.0), Colombia (*.gov.co), Chile (*.gob.cl) | each portal's own open licence; take only decks whose page or portal licence is stated | es-ES, es-MX, es-AR, es-CO decks |
| Brazil (*.gov.br, dados.gov.br), Portugal (*.gov.pt, dados.gov.pt) | per dataset (CC BY or ODbL on the portals; the Brazilian access law 12.527 is NOT a licence) | pt-BR, pt-PT decks |
| gov.uk | OGL v3 | English business-style decks |
| EU institutions (Publications Office, Commission) | Commission Decision 2011/833/EU, usually CC BY 4.0 | de, fr, it, pl and other EU languages, a few decks each |
| US federal agencies | public domain (17 USC 105) | English, charts and tables |
| Test suites not yet taken: LibreOffice sd/qa, Apache POI, Open XML SDK (MIT), python-pptx (MIT), docx4j/pptx4j (Apache-2.0) | as stated | feature witnesses only (equations, columns, rare charts); ONE-slide files count as features, not as decks |

**Discovery.** The Common Crawl columnar URL index (`cc-index-table`, parquet) finds candidates by TLD and suffix:
`url_host_tld IN ('kr','jp','es','mx','ar','co','cl','br','pt') AND url_path LIKE '%.pptx'`,
or `content_mime_detected` = the presentationml type. Fetch from the ORIGIN URL, not the WARC:
Common Crawl truncates large payloads (`content_truncated`), and decks are often over the limit.
Record the licence from the page that links the deck, not from the deck itself.
docxcorp.us served the Word sets (ODC-BY). Ask whether it, or a similar API, carries `.pptx`. Until it answers, plan on Common Crawl.

**Reject:** personal data (names with phone numbers or IDs on slides, student lists); decks
PowerPoint opens only through repair (the print script reports `pdf repaired`); a date/time field
on a slide (PowerPoint prints today's date); decks over 60 slides or 30 MB; decks whose faces are
missing on the Windows box (check the faces embedded in the print against the deck's faces);
no stated licence. Every deck gets a manifest row: id (SHA-256), URL, licence, language and locale,
slides, source, and the tokens it adds. As for Word, decks and prints go to `/data/corpus-cache`, never to git; the manifest goes in `docs/plans/`.

**Held-out FINAL TEST set.** Before development starts, starling-bd takes 20% of each language's
accepted decks off the box as the Slides final test set, as was done for Word. Nobody else sees those decks or their ids.

## 3. Targets (one page)

| language (locale) | real decks today | target decks | target slides | notes |
|---|---|---|---|---|
| Korean (ko-KR) | ~2 | 80 | 1,200 | Malgun Gothic and Gulim faces, word-based wrapping, tables |
| Japanese (ja-JP) | ~2 | 80 | 1,200 | Meiryo, Yu Gothic, MS PGothic; vertical text; kinsoku |
| Spanish (es-ES 30, es-MX 20, es-AR/CO/CL 20) | few | 70 | 1,000 | long bullet lists, autofit, charts |
| Portuguese (pt-BR 45, pt-PT 15) | ~0 | 60 | 900 | as Spanish |
| English (gov.uk, US federal) | test files | 40 | 600 | masters and layouts, charts, tables |
| Chinese (zh-CN/TW), Arabic, Hebrew, EU languages | 13 / 0 / 4 / few | 10 / 10 / 10 / 20 | 600 together | spread the scripts; RTL |
| **Total** | | **~380** | **~5,500** | 5x today's slides |

| feature (decks, real decks only) | today, on a slide | target |
|---|---|---|
| body placeholder inheriting a layout's position; masters>=2 | 79 / 20 | 200 / 30 |
| normAutofit with fontScale (each bucket) | 18 | 60 (15 per bucket) |
| bullet levels >=3; numbered bullets | ? / 15 | 60 / 40 |
| tables (merged cells, styles) | 55 (mostly tests) | 80 |
| charts (each of bar, line, pie, combo) | 19 | 80 (20 each) |
| SmartArt (with and without cached drawing) | 75 (tests) | 40 real |
| cropped pictures; SVG pictures | 18 / ? | 60 / 15 |
| WordArt warps; vertical text | 15 / 11 | 15 / 30 (mostly ja) |
| text columns; equations; RTL | 2 / 3 / 5 | 10 / 10 / 15 |

Pick by "new tokens added" until each line above is met. Within a language, prefer decks of 5-40 slides.

## 4. Size budget and references

- Decks at most 30 MB and 60 slides; expect about 1 GB of decks and about 1 GB of prints in `/data/corpus-cache`. Nothing goes in git.
- **Prints: PowerPoint for Windows only**, through `test/pptx-powerpoint-pdf.ps1` (COM, read-only, alerts off), run
  under `test/pptx-powerpoint-render.sh` on the windows box as for the 2026-11-07 set. Record PowerPoint's
  build in a STAMP beside the prints. Never mix builds inside a set; a new build means reprinting the set.
- Check each print: its page count is the deck's visible slide count (hidden slides are skipped:
  confirm on the 2 decks that have them before trusting it); `pdf repaired` means the deck is rejected; the faces in the print must match the deck's faces after substitution.
- Time per deck: measure it on the first 50 decks (Word took about 9 s a document) before scheduling the rest.

## 5. The scorer and the gate

- **Line score** (new `test/pptx-line-match.py`, built from `docx-line-match.py` v2 and
  `pptx-line-survey.py`): read the glyph lines of PowerPoint's print and of ours, slide by slide. A
  PowerPoint line is matched when ours has one on the same slide within 3 pt of its height that starts or ends with the same
  four characters: the Word v2 rule, unchanged. Rotated and vertical lines are left to the visual score.
  A deck's line score is the share of PowerPoint's lines matched.
- **Visual score**: the existing pixel diff (`pdf-diff.py`, MuPDF, 96 dpi, radius 2), per slide.
- **Combined**, the Word rule (`docx-combine.py`): decks whose print has text lines take the line score; decks with
  none (picture-only, WordArt drawn as outlines) take the visual one, 100 at <=1% worst slide falling to 0 at 10%. The visual numbers are reported beside it, so nothing is hidden.
- **Sets**: `p0` is today's 561 decks (pixel gate and `matched-win.txt` unchanged); `p1` is the new decks, scored combined.
  The digit bumps on any change to a list, as for Word.
- **Gate**: `pr.sh`'s render gate runs `p0` as today, plus `p1` on a stratified subset of at most 1,500 slides (every token
  witnessed twice, every language present) so gate time stays near today's 10 minutes. amd-8's hourly round
  sweeps all of `p1` and bisects drops, as for Word. A deck drop needs starling-bd's approval by full id.

## 6. Who does what (suggested; starling-bd assigns)

1. Census tool `test/tools/pptx-features.py` (layers A and B), the line matcher and the combine step: amd-opus, about 1 day.
2. Sourcing: two sessions, one for ko and ja, one for es and pt (with en and EU on the side). Each uses Common Crawl
   discovery, then licence check, rejects and token-gain selection, and delivers a manifest. About 1-2 days.
3. Prints: `windows`, a 50-deck pilot first (time, repair rate, face misses), then the rest.
4. Faces: whoever owns the bundled fonts adds metrics-only Windows stand-ins for the new faces before the reseed.
5. Reseed and the gate subset: amd-8.
