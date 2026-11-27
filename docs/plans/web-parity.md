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

## 4. Plan: the browser's file features (2026-11-26, amd-11)

Missing in the browser today: Print, a real Save As, AutoSave and recovery copies,
recent files, and publishing. Word first, then Slides and Sheets on the same pieces.
Nothing here is deployed to the live sites without the coordinator's OK.

**One seam, testable natively.** The shell's browser paths stop being `#if os(WASI)`
dead ends and go through one object, `OfficeHost.browser` (a `BrowserFiles` value):
print a PDF, keep a recovery copy, list and reopen recent documents, save through a
file handle. The web build sets it at start-up from host calls; unit tests set an
in-memory one and drive the real OfficeShell with WidgetTester, so every feature has
a native failing-before test. A Chrome test (test/office-files-web.mjs, web-drive's
CDP) checks the page side: the print frame, IndexedDB rows, recovery after a reload.

1. **Print.** File > Print renders the same PDF as Export (PdfExport, waiting for
   pictures and fonts), but hands the bytes to a new host call `print_pdf` instead of
   a download: the page loads them into a hidden iframe and calls its `print()`, so
   the browser's own print dialog opens (printer, pages, copies). The page range
   picked in our Print pane is applied before (printPages). Fallback where an iframe
   cannot print (some mobile browsers): open the PDF in a new tab.
   DONE 2026-11-26 (Word): BrowserPrintTests (native, a stand-in host); in Chrome,
   Ctrl+P then Print gave the page a 78 KB PDF in the print frame. Slides and Sheets
   still offer Export in the browser: they print through their own paths, next.
2. **AutoSave and recovery.** Two seconds after the last edit (OfficeHost.autosaveDelay,
   as natively) the document's bytes go to IndexedDB (database `starling-office`,
   store `recovery`, one row per tab: name, kind, time, bytes). A save or download
   deletes the row. On start, a row whose tab is gone (Web Locks: each tab holds a
   lock named after its row) is offered as natively: "Recovered unsaved changes", with
   Keep / Discard. Rows are capped (the newest 10, and 200 MB in total).
   DONE 2026-11-26 (Word), as natively rather than with Keep / Discard: the restored
   document opens unsaved with "Restored an unsaved document — Save to keep it", and
   Close's Don't Save drops the row. BrowserRecoveryTests (native, a stand-in page);
   test/office-recovery-web.sh in Chromium: type, close, a new browser on the same
   profile gets the text back, Save downloads it and deletes the row. Not yet: Slides.
   DONE 2026-11-27 (amd-11): a flush on page close. The page calls `starling_page_hidden`
   on visibilitychange (hidden) and pagehide, and Word writes its copy at once instead of
   after the 2-second pause, which a closing tab never gets; a hide with no edit since the
   last copy writes nothing. BrowserRecoveryTests (fails before), office-recovery-web.sh
   step 4 (row there 300 ms after pagehide; fails on the old build).
3. **Recent files.** Each open and save puts a row in IndexedDB store `recent` (name,
   kind, time, a copy of the bytes, and the file handle where the browser has the
   File System Access API). Backstage Home and Open list them as natively; reopening
   uses the handle (asking for permission again if the browser wants) or the copy.
   20 rows, oldest dropped first, the same cap on bytes as recovery.
   DONE 2026-11-27 (Word, amd-11): `OfficeHost.browserRecent`; the page keeps rows in
   its own database `starling-office-recent` (stores `recent` = name/time/size, read
   at start, and `recentBytes` = the copy), keyed by name; 20 rows and 200 MB, the
   newest always kept. Word remembers what its picker opens (decks and workbooks too,
   which it hands on) and what Save downloads; Home lists the names, a click reads
   the copy back (a copy the browser evicted says so and leaves the list).
   BrowserRecentTests (native, a stand-in page; fail before), test/office-recent-web.sh
   (Chromium, 6/6). Not yet: file handles (they come with item 4's pickers: today's
   picker is an <input>, which gives none); Slides' and Sheets' own Open and Save;
   Open in a tab goes straight to the browser's picker, so only Home lists Recent.
4. **Save As and Save.** Where `showSaveFilePicker` exists (Chrome, Edge), Save As
   asks the browser for a place and a name (Word, OpenDocument, PDF, plain text) and
   keeps the handle; Save then writes the same file in place, as natively, and a
   file opened through `showOpenFilePicker` saves back to itself. Elsewhere (Firefox,
   Safari) Save As shows our own name-and-format dialog and downloads, and Save
   downloads.
5. **Publishing.** Natively a publication is a folder with site.json that Publish
   builds and pushes with git. A tab has neither, so in the browser it needs a server
   that takes the built pages. That is a product decision (where pages go, who may
   publish): planned last, after asking the coordinator; until then the Backstage
   entry stays hidden in the browser, as now.

Order: 1, 2, 3 (2 and 3 share the IndexedDB layer), 4, then 5. One PR each, Word
first; Slides and Sheets follow in the same PR where the shell code is shared.
