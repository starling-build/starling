# Word fidelity: status and next steps (2026-10-27)

A snapshot written when the team stopped for the day (out of tokens). The working
board is still `docs/plans/word-gaps-tasks.md`; this file is the summary of where
everything stands and what to pick up first.

## Where the scores stand

Line-match scores (`test/docx-line-match.py`, PyMuPDF reader) on office around
6ceb5145–518df17c, engine c34c8aa8eba, against the final references:

| Corpus | Mean | At 95%+ | Notes |
|---|---|---|---|
| Windows mode, zh (645 docs, `test/corpus/docx/word-win`) | 99.3% | 628 | w26 |
| Windows mode, POI (111 docs) | 90.5% | 99 | ten POI docs print 0/0 in Word |
| Mac mode, zh (645 docs, `test/corpus/docx/word`) | 97.5% | 597 | n21; ~97.7 with today's later Mac font rules |
| Mac mode, POI (111 docs) | 91.6% | 101 | |

Linux sessions (engine c34c8aa8eba, lenovo-2's build) reported Windows 97.7 / Mac 95.4
before today's Mac font rules; that box's scores are only comparable as same-base pairs.

## What landed today (2026-10-26/27)

The landing rule: a same-base pair in BOTH modes, no document lower. The user's
standing exception (2026-10-27): a fix verified against Word lands even if a document
drops only because the fix undoes two errors that used to cancel. Log the uncovered
error on the board as a follow-up.

### Engine (starling-engine, `starling`)
- c34c8aa8eba: removed skparagraph's per-line half-letter-spacing shift
  (`patches/skia-no-line-spacing-shift.patch`), user-approved. sdk follow-ups:
  d4de9ca0, 92cfd0ac, f3f1fd7e, 4cd7cc03, 8b8ddef0. zh-6a4fc013 76.5 → 83.4 (Windows) / 68.1 → 84.9 (Mac).
- ce449fad36d: the font collection manager is never destroyed. Fixes the Windows
  crash at exit (T200; pushed with --no-verify once, the user's call).
- 5357bf0b374 / 88bc84f8bc3: horizontal scale (scaleX) applied once in the HarfBuzz shaper.

### Mac references (the user's call)
The Mac Word that printed `test/corpus/docx/word` had run as one process since
2026-10-18 13:17, and its font state drifted. 468 references were reprinted, each
alone in a fresh Word:
- a3304812: 151 that embedded Arial Unicode MS;
- a1188040: 243 more from the drifted session;
- 7581f9d0: 74 pre-drift documents naming 仿宋/楷体/_GB2312.
Mac-mode bases scored before these don't compare.

### Mac-mode font rules (fresh Mac Word)
- a69b98a8: a _GB2312 name is set in its font table's w:altName (仿宋 → FangSong,
  宋体 → SimSun, Arial Unicode MS, 微软雅黑 → YaHei); no alternate → YaHei;
  "FangSong_GB2312" with no alternate → SimSun. Mac mean 94.7 → 97.4.
- f5600ce9: the same for 方正 names (zh-2f9463d6 56.6 → 99.9, zh-419ea527 72.5 → 100).
- 0710ae9e: a name Word lacks, with no alternate: the font table's LAST entry for it
  decides. Family roman → SimSun, anything else → YaHei (lab tsim2, 7/7). zh-4c5da793 26 → 85.
- ee76953c: Mac fake bold widens each advance by 1.95%.
- ee320d14: firstLineChars counts the first character as drawn, bold widening included.
- a87891a5: a Liberation face takes the font table's alternate (T209).
- 28faf6d5 / 8b8ddef0: Mac Word hangs a line-final Latin , ? . ) on justified lines.

### Layout (both modes unless noted)
- 37509fb6: Windows character-grid squeeze, round one.
- 904c1826: a half-width character at a paragraph's end takes half the grid's
  addition (Windows). zh-72da925e 60.5 → 95.8.
- a7e4342c / 1164bd7a: grid cells are Normal's size + charSpace + Normal's spacing;
  a condensed mark beside another keeps half its condensed width. zh-5be7e156 75.8 → 97.8.
- b2e08147 (T191): a parted row's cut on Word for Windows' 1/600in raster. zh-4c5da793 85.6 → 100.
- cf2997f8, c9d223ad, 05eae24f, b206d70d: indent past a cell, a page-placed table
  after rows, a parting paragraph's floats, the legacy quote hang (windows).
- ef49ef5c / a1c6089f / b025902a (T205, T223): lines stepped under their own floats.
- c48cb6e0, 1d98d3ed, e70bd5d3, d3add605: kept rows and runs, page-placed tables at
  the footer, autofit tables in the margin.
- ce134f2c: a run of tabs alone takes no line. 9caa0c29: full-width PAGE results.
- cbb1dab5: two T181 squeeze witnesses. 7b6538e4: no contextual alternates (T208).
- 67b573fe: Wingdings 2 and other symbol faces draw their glyphs (☐, not "£").
- Charts: 5ad064a7 (3-D pie labels), b92c8187, cc5af51a, d059f64b, 6384a10a.
- Sheets (print): a2a29a6c, ee751d93, c7d07eeb, 5bd0ff87, c91da075.

### Installed fonts (T203)
5997dae3 and follow-ups (1f711355, 088e87af, dcfd36b6, 0d137869, 6013d276): a
document's installed faces are used by default; File → Options → Fonts switches to
the bundled stand-ins; `OFFICE_FONT_SOURCE=bundled` pins every harness.

## In flight when we stopped: do these first

1. **The long-word engine change (user-approved, NOT pushed).** starling-engine
   39bb8cb9328, `patches/skia-long-word-next-line.patch`: an over-long word moves to
   the next line before it is broken; a line of only whitespace, zero-width clusters
   or placeholders counts as empty.
   - **The Mac's shared `host_release_arm64` is linked from this unpushed commit now.**
     To undo: rebuild from origin/starling c34c8aa8eba.
   - Last full pair (w26 → w28 / n21 → n23, on 4f294e16899): zh-6a4fc013 +1.8/+1.9,
     zh-7773163d +0.1, zh-fec5fa30 −0.1. macos-ios has since fixed zh-fec5fa30 in
     39bb8cb9328 (verified locally). The confirming sweep was stopped.
   - Next: run w29/n24 against w26/n21 on the `longbase` checkout (office 6ceb5145),
     then push the engine if nothing drops; Linux and Windows pull and rebuild.
2. **macos-ios: zh-13552a3a** (94.8 → 100 locally). In Windows mode a parted row goes
   on at trHeight + the cell's own top rule + margins. The patch is in
   `~/starling-word-check/lab/t135-continuation.patch`; it needs its pair.
3. **lenovo-2: zh-c2229d4a** (Mac 42.6). Lab tc22: under
   balanceSingleByteDoubleByteWidth, Mac Word leaves spaces at their own width (plus
   justify slack), not half an em. Build that for Mac mode only and pair.
4. **macOS-doc: zh-72da925e Mac.** Drop 904c1826's Windows-only gate (the old Mac
   drop was against a stale reference) and pair; then its p8 line-final "「" fit.
5. **office1: zh-e0ca7252** (Mac 63.3, 613 misses). Our YaHei table lacked □ (U+25A1).
   Word's msyh.ttc advances (/2048): □ 1336, ■ 1237, ○ 1237, ● 1336, ◇ 1229, ◆ 1229,
   △ 1229, ▲ 2027, ☆ 1686, ★ 1671, ※ 1724, √ 1437, ─ 1451, →← 2048, ↑↓ 1024.
6. **lenovo-3: zh-f39e54b6** (squeeze witness), then **zh-13d11e99**'s chart axis
   labels: compare its plot against zh-b8de3ae2's titled charts.

## Open problems (on the board)

- **Browser vs native, Mac only:** office-layout fails by 26 lines on word-boringcrypto
  (four paragraphs break a word apart; ¶600 13.3 vs 13.5). It predates today's commits
  and came with the engine update; Linux is green on the same engine. **Must be fixed
  before any live-site redeploy** (a redeploy needs the user's yes anyway).
- **Squeeze edges:** zh-7b08d744 (Mac 71.6) and zh-8dc59b5b. A mode-14 cell squeeze
  limit was tried and dropped (seven documents fell); numbers on the board (a6d27ff7).
- **zh-3c055c9b p2 "費、"**: which marks may give depends on their place relative to
  the digit groups (lab tfe). Parked.
- **zh-27a874b7 / zh-d62da4dd** pie labels (rest), **zh-61aaad09** pie labels.
- **Per-line heights** (zh-0978dee9): scoped, not worth building now.
- **Sub-twip grid rounding** (zh-5be7e156 p2, zh-8d6f702e p38): no model yet.
- **termd's test** fails on Linux under load (timing), passes alone.

## Decisions waiting on the user

- **Automatic hyphenation** (w:autoHyphenation; 29 corpus documents, mostly already
  100; worth 1–3 points on zh-147bdae0 and a few others). Build it or not.
- **The long-word engine change:** keep it (one confirming sweep, then push) or roll
  the Mac engine back to c34c8aa8eba.

## How to resume

- Board: `docs/plans/word-gaps-tasks.md`. Claim before working, grep before claiming.
- Sweeps: `~/starling-word-check/lab/tools/sweep-win.sh PREV NEW` (Windows mode) and
  `sweep.sh PREV NEW` (Mac mode), both pinned to `OFFICE_FONT_SOURCE=bundled`; run from
  inside the worktree. Export both STARLING_ENGINE_OUT and FLUTTER_SWIFT_ENGINE_OUT.
- Pair in both modes; base and candidate on one checkout and one engine.
- Mac Word labs: `test/docx-word-pdf.applescript`, each file in a freshly launched
  Word (quit between prints). Packages built by a session; check that no Office app is
  being driven first.
- Engine relinks on the Mac: check no sweep or ninja is running, and tell every Mac
  session first.
