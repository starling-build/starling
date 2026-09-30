# Office Writer: making the editor itself good

Status: **in progress**, 2026-09-29, branch `office`. Done headless (the
screen was locked all evening, so nothing below is seen on screen yet):
M1's keyboard half (checklist in `test/office-checklist.md`), M2 cursors,
M3 picture handles, M4 rich clipboard, M6 columns (merge and cell
selection still open), M7 links, M8 ribbon truth, M9 print and AutoSave.
Open: M1's on-screen half, M5 IME (needs the engine to deliver
text-input platform messages to Swift — `sendPlatformMessage` is a stub
both ways), M6 merged cells and cell selection, M8 Columns and Modify
Style, M10. First thing once the screen is unlocked: run the checklist
and look at every one of these. Companion to `office.md`,
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
- **Keep the perf gate.** Re-run the 200-page measurement after any
  change to `RichEditable` or `RichLayout`; nothing in this plan may make a
  keystroke slower.
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
(`NSSpellChecker` is). Modify Style and Update to Match Selection in the
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
