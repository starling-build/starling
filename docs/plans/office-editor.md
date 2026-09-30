# Office Writer: making the editor itself good

Status: **in progress**, 2026-09-29, branch `office`. Done headless (the
screen was locked all evening, so nothing below is seen on screen yet):
M1's keyboard half (checklist in `test/office-checklist.md`), M2 cursors,
M3 picture handles, M4 rich clipboard, M6 columns and merged cells both
ways (gridSpan and vMerge in .docx) and rectangular cell selection
(dragging or ⇧-extending from one cell into another selects whole cells;
formatting, Delete (clears, keeps the cells), copy and Merge Cells work
on the block), M7 links, M8 ribbon truth, Modify Style and section Columns
(Layout → Columns: one, two, three; `w:cols` in .docx; the flow fills a
page's columns left to right), M9 print and AutoSave, M10's welcome
document, the headless perf gate, and a three-reviewer pass over all of
it with its ~30 findings fixed (commit 4ac18e6). Open: M1's on-screen half (`test/office-drive.py`
runs the checklist and screenshots every step for review), M5 IME on
by default, the 14pt menu bug. Everyday editing added 2026-09-30, all
headless: right-click menu, Paste as plain text (⌘⇧V), AutoCorrect
(smart quotes, dashes, (c)/(r)/(tm), first-letter capitals), cell blocks,
drag-and-drop of selected text (⌥ copies; a drop caret follows the
pointer; a press that does not move collapses the selection, as Word),
the Bullets and Numbering libraries (split chevrons; .docx round-trips
the glyphs), and spelling: `RichSpellChecker` in the SDK, NSSpellChecker
behind it in the app, red underlines painted from a per-text cache that
fills 350 ms after a paragraph is first shown (a bad paragraph costs
NSSpellChecker ~5 ms, a good one ~0.3 ms, so never in the paint), the
caret's word left alone, corrections / Ignore All / Add to Dictionary
at the top of the right-click menu, and a Spelling toggle on Review.
Smart cut and paste too (`smartSpacing`, on by default): a pasted or
dropped word gets the space it needs, a cut leaves no double space and
none before a full stop. First thing
once the screen is unlocked: run the driver and look at every picture.

**M5, step one done:** platform messages now travel both ways. The
engine hands the Swift runtime a sender once it owns it
(`platform_message_sender_ready`), `PlatformDispatcher.sendPlatformMessage`
is real, and replies come back through `platform_message_response`
(engine commit "swift runtime: platform messages from the framework to
the platform"). Proven headless: `OFFICE_PROBE_PLATFORM=1` asks the Mac
for the pasteboard over `flutter/platform` and gets it. **M5, step two written, behind `STARLING_IME=1`:**
`RichTextInputConnection` (sdk) becomes the platform's text-input client
on focus — `TextInput.setClient`/`setEditingState`/`show` — with the
caret paragraph as the client's text; every local change re-sends the
state, every `updateEditingState` from the plugin is diffed against the
paragraph and applied as one replacement, the composing range is kept
on the controller and underlined by the editable, and
`performAction newline` splits the paragraph. With it on, the key path
declines typed characters so the plugin delivers them (the engine now
replies whether a key was consumed, so keys the framework takes never
reach the plugin). Off by default until seen working with the Pinyin
and Japanese input sources, dead keys and press-and-hold; then it
becomes the default and the key-path typing goes. Companion to `office.md`,
which tracks the suite; this one is only about the editing experience in
Writer on macOS, which is where the user has asked for the focus. Nothing
here is Linux, Windows or iOS.

## Where the editor stands

Verified on screen this week: typing, drag/shift/double/triple-click
selection with autoscroll, wheel scrolling, undo/redo, the Home tab,
headings and named styles, lists, tables (Tab between cells, row commands),
pictures, headers/footers, find/replace, zoom and the three views, the
navigation pane, and the perf gate on 200 pages (well under a millisecond
per keystroke).

Not there, in the order a writer meets them:

- **The pointer is always an arrow.** No I-beam over text, no resize cursor
  over a picture. `MouseTracker` carries a `MouseCursor` but no host sets a
  native cursor.
- **Pictures are fixed.** Inserted at their natural size, no handles, no
  resize, no move except cut and paste.
- **The clipboard is plain text.** `CocoaClipboardProvider` reads and
  writes `NSPasteboard` strings only; a rich paste works only within one
  controller (the last copied fragment). Nothing pasted from Word, Pages
  or a browser keeps its formatting, and nothing copied out carries any.
- **No IME.** Keys arrive as `KeyData` through `onKeyData`; the Cocoa host
  is not an `NSTextInputClient`, so composed input (Chinese, Japanese,
  Korean), dead keys, and macOS press-and-hold accents cannot reach the
  document.
- **Tables stop at rows.** No column insert/delete, no merged cells, no
  column resizing, no rectangular cell selection, no table tab.
- **Links display but do nothing.** No Insert → Link, no ⌘K, no click.
- **Disabled buttons stand in for features:** Format Painter, Change Case,
  Show/Hide ¶, Shapes, Text Box, Columns; Draw, References and Review are
  placeholder tabs. AutoSave is a label. Print exports a PDF.
- **Styles cannot be edited:** no Modify Style, no Update to Match.
- **Known chrome bug:** a Fluent menu item whose text is exactly 14pt
  draws with stretched letter spacing.

Unverified: keyboard navigation through tables, drag-select across a page
boundary, dark mode, window resizing, Home/End/PageUp/PageDown and the
⌥/⌘ arrow chords, scrollbar dragging, focus after every ribbon action.

## Principles

- **Verify on screen, every milestone.** Drive the app with the osascript
  and click recipes in `office.md`; keep a screenshot of the result in the
  session. A milestone is done when it was seen working, not when it
  compiles.
- **Keep the perf gate.** `OfficeApp --bench 200` (headless, debug
  build) after any change to `RichEditable` or `RichLayout`. It types
  into the middle of the 200-page document and reports per-keystroke
  layout and paint; it also checks the incremental pagination against a
  fresh layout and fails if they differ. The gate: **layout median under
  450 µs, paint median under 200 µs** (2026-09-30: 412 / 149 µs; the
  same harness measured the pre-tables layout at 2155 µs, so the earlier
  "50–100 µs" figure in `office.md` was measuring something narrower).
  Nothing in this plan may make a keystroke slower.
- **Framework first when it is a framework gap.** Cursors, IME and rich
  clipboard flavours are host and SDK work that every future app needs;
  they go in `sdk/`, with Writer as the first consumer.
- **No placeholders that look like features.** Either a button works or it
  goes; a greyed button is acceptable only inside a group that otherwise
  works.

## Milestones

### M1 — Interaction audit and fixes

A written checklist, run against the live app, of everything a writer
does without thinking: click, shift-click, drag (incl. past the edges and
across pages), double and triple click, ⌘A; ←→↑↓ with ⌥ (word) and ⌘
(line/document) and ⇧ (extend); Home/End/PageUp/PageDown; Enter and
Backspace at every boundary (list item, heading, table cell, picture,
page break); wheel and trackpad scrolling incl. momentum; scrollbar
drag; typing while scrolled away from the caret; window resize; dark mode
via the shell; focus returning to the document after every ribbon action.
Each item either passes or becomes a fix in this milestone. Deliverable:
`test/office-checklist.md` with pass/fail per item and the fixes committed.

### M2 — Cursors

A host cursor API: `MouseTracker` resolves the `MouseCursor` under the
pointer and the host sets it (`NSCursor` on Cocoa; GTK/Win32 later).
`RichEditable` declares I-beam over text, arrow over margins and chrome,
the resize cursors over picture handles (M3). One SDK change, visible in
every app with a text field.

### M3 — Pictures

Click selects a picture and shows eight handles; dragging a corner
resizes with the aspect ratio kept, an edge free; Delete removes it;
arrow keys nudge; a Picture Format contextual tab with size fields and
Reset. Cut/paste moves it (M4 makes that work across apps). Layout stays
"picture is a paragraph"; floating and wrap-around are out of scope.

### M4 — Rich clipboard

`ClipboardData` grows RTF, HTML and image flavours; the Cocoa provider
writes all of them on copy and reads the best on paste. Writer copies a
fragment as RTF (via `RtfFormat`) plus HTML plus plain; paste prefers RTF,
then HTML (a small HTML reader: p/h1–h6/b/i/u/a/ul/ol/li/table), then
text, and an image on the pasteboard becomes a picture. In-app paste keeps
using the fragment. Verified by pasting from Pages, Safari and TextEdit
and copying into them.

### M5 — Text input and IME

The Cocoa host adopts `NSTextInputClient`: marked text with its underline
in `RichEditable` (a composing range on the controller that layout draws
and every edit replaces), `insertText`, dead keys, press-and-hold accents,
the emoji picker (⌃⌘Space), and Kotoeri/Pinyin composition. `KeyData`
keeps driving shortcuts and navigation. Verified with the Pinyin and
Japanese input sources.

### M6 — Tables

Column insert/delete; merged cells in the model (`colSpan`/`rowSpan` on
`CellRef`, read from `gridSpan`/`vMerge`, written back); column resizing
by dragging a border or the ruler's column marks; rectangular cell
selection (drag across cells, ⇧-click) with format commands applying to
it; Delete clearing cells; a Table contextual tab (rows, columns, merge,
split, borders on/off, header row). Word's table styles are out.

### M7 — Links

Insert → Link (and ⌘K) with a small dialog; ⌘-click opens the URL through
the host; hover shows the target in the status bar; Backspace at a link's
end removes the link before the text as Word does.

### M8 — Ribbon truth and styles

Make Format Painter, Change Case (five cases), Show/Hide ¶ (draw pilcrows,
tabs, spaces) and Columns (two/three-column sections in `RichLayout`)
work; move Shapes, Text Box, Draw and References into a single "Coming
later" note rather than five greyed groups; Review keeps Word Count and
gains Spelling only if the host spell checker is cheap to wire
(`NSSpellChecker` is — done, see the status above). Modify Style and Update to Match Selection in the
gallery menu; the sheet edit is one undo step and re-lays out.

### M9 — Print and save

A real print dialog on macOS (`NSPrintOperation` over the exported PDF),
Page Setup from it; AutoSave becomes local autosave with recovery on the
next launch (a sidecar `.docx~`), or the label goes.

### M10 — Polish

The 14pt menu spacing bug in the framework; keyboard shortcut coverage
(⌘⇧> < for size, ⌘E/L/R/J alignment, ⌘⌥1–3 headings); a first-run
document that shows the features instead of the perf lorem; the ribbon
disabled-state and tooltip audit.

## Order and why

M1 first because it is cheap and everything after it is measured against
a baseline that is known to work. M2–M5 next because they are what makes
the editor feel native, and three of them are framework work that other
apps will need. Tables (M6) and links (M7) are the biggest remaining
document features. M8–M10 are the finish.

## Out of scope here

Track changes, comments, footnotes, table of contents fields, floating
images and text wrap, multi-user editing, Sheets and Slides, any platform
other than macOS. Each is noted in `office.md` where it belongs.
