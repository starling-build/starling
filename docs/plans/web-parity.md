# Web parity: the browser Office app against the native one

Audit of 2026-11-25 (amd-11). Goal: Writer, Slides and Sheets in the browser
have the same features as native and draw the same.

## 1. Rendering (measured)

Sample: 30 docx, 20 pptx, 20 xlsx from test/corpus (every Nth file under 400 KB).
Each file is exported to PDF natively and by File > Export > PDF in headless
Chrome; test/pdf-diff.py scores each page (share of differing pixels). Expected 0.00.
Tools: test/docx-web-render.sh (Word), test/web-parity-sweep.sh (Slides, Sheets).
Snap Chromium can only write downloads under $HOME, so WORK must be there.

| App | Files | Identical | Differing |
|---|---|---|---|
| Word | 30 | 11 | 19: 14 zh docs 8-16% worst page; lo-c4927bf5 11%; lo-2d0cbd06 3.5%; 3 under 0.1% |
| Slides | 20 | 15 | chart-slide-bg 89.6%; 45541_Footer 2.7%; glow text 0.5%; 3 under 0.2% |
| Sheets | 20 | 18 | 123233_charts 1.9%; chart-bartest-stroke 0.08% |

Findings:
1. **zh docs (all 14): same line breaks, different glyph face.** Native draws a
   Ming/Song-style serif, the browser a sans-like face, so every page differs.
   The lazy script-font path picks another CJK face than native. Fix first.
2. FIXED 2026-11-26 (engine skwasm/pdf.cpp): **Slides picture background
   (chart-slide-bg): the browser drew black** where native draws the texture
   fill. The PDF writer copied drawn pictures out of the GPU but not one inside
   a tiled image shader. Sweep: 16 of 20 decks identical (was 15).
3. Smaller: 45541_Footer (footer text), shape-text glow, chart strokes: to be
   looked at one by one after 1 and 2.
4. Word, 2026-11-26 (amd-11): 14 of 30 identical; none of the 16 that differ
   is a web bug. On each, the web matches Word and native does not:
   - zh (14 docs): native draws "○" small, in a Latin face, where Word and web draw it
     full width. It also shares justify space differently next to 》《 and 、
     (under 1%, except zh-e49d79431 page 18 at 11%, a page full of ○).
   - lo-d1e88d777 (0.03%): native also paints the highlight of a line that moved
     to the next page. It is clipped, so only one pixel row shows.
   - zh-266603368 (0.04%): 0.08 pt of justify after 、. Word spaces the line evenly,
     as the web does.
   These are native fixes (Word lane), not web ones.

## 2. Features (from fences and the wasm.md "Not done" list)

Fenced out or reduced in the browser (grep `os(WASI)`):
- Printing: "not available in the browser yet" (OfficeShell).
- Save as / autosave / recovery copies / recent files: a tab has no files; save is a download.
- Publish documents and Site creation (Backstage, SiteShell): fenced, regex parts of SiteModel off.
- Wiki shell, update check, file panel, picked-file paths: reduced.
- Debug env dumps (Diagram) are native-only by design.
Platform gaps (wasm.md): IME and touch keyboards; fonts by request; Firefox/Safari
CJK line breaking; accessibility tree; animated images; an Image widget.
Ribbon walk (2026-11-26, amd-11): `node build/tools/web-drive.mjs walk FILE OUT`
opens FILE in the browser, selects all (Ctrl+A), and clicks every ribbon button
on every tab (listed by `starling.debug('controls')`), recording any that throws.
First run: Sheets crashed on select-all ("RuntimeError: unreachable"): a whole
sheet is 2^34 cells and `rows * cols` overflowed wasm32's 32-bit Int. FIXED:
`CellRange.area` saturates, every Sheets call site uses it (SheetsRangeAreaTests).
After: Word 92 ok, Slides 155 ok, Sheets 106 ok (7 tabs), 0 throw.
Second walk (2026-11-26, amd-11): the walk now also opens each drop-down and
dialog and clicks its rows, the File backstage, and the right-click menu
(`controls` lists the overlay too). It found two bugs, both FIXED:
- No drop-down opened after a dialog had opened under a showing tooltip (native
  too). The tooltip's removal dirtied the Overlay during the window's rebuild;
  `buildScope` re-sorted and skipped it, and it stayed dirty forever, so every
  later menu insert was ignored. `buildScope` steps back after a re-sort, as
  upstream does (TooltipDialogTests).
- Word Font Color → More Colors… trapped on web: `Color(Int(0xFF…))` does not
  fit wasm32's Int. Int64 now (MoreColorsTests covers the path natively).
After: Word 385 rows, Slides 409, Sheets 250; 0 throw. The NOT-FOUND rows are
the More Colors strip's swatches (it stays open across tabs by design) and
menu rows that only exist with a selection.

## 3. Proposal (not wired): keep the web build from breaking silently

The build broke unnoticed (Int overflows, Foundation string search, a dlsym).
- Once a day, amd-8's unit watch runs `build/web-app.sh OfficeApp --package apps/OfficeApp`
  and reports a failure like a red unit test (compile and link only, about 10 min).
- Weekly: test/office-layout.sh and the two sweeps above on this sample; alert if any
  file worsens against the baseline in this document.
- Rule for authors: in shared code never use `.contains("x")`, `.range(of:)`,
  `replacingOccurrences`, `dlsym`, or Int literals above 2^31 (use sdk helpers).
