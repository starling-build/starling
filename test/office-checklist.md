# Office Writer — interaction checklist (plan `office-editor.md`, M1)

Run against the live app on macOS (`apps/OfficeApp/.build/debug/OfficeApp`,
drive with the recipes in `docs/plans/office.md`). Status values:
**pass** (seen on screen), **code** (behaviour pinned by a unit test but
not yet seen on screen), **pending** (not checked), **fail → fix**.

Last run: 2026-09-29, screen locked for the on-screen half.

## Pointer

| Item | Status |
| --- | --- |
| Click places the caret; click in the margin lands on the nearest line | pass |
| Shift-click extends the selection | pending |
| Drag selects; dragging past the top/bottom edge autoscrolls | pass |
| Drag across a page boundary keeps selecting | pending |
| Double-click selects a word, triple-click the paragraph | pass |
| Drag after a double-click grows by words; after a triple-click by paragraphs (both directions) | unverified (headless, 2026-09-30) |
| Drag from one table cell into another selects whole cells; Delete clears them; Merge Cells folds them | pass (seen 2026-09-30) |
| Press on selected text and drag: a drop caret follows, release moves it (⌥ copies); a still press collapses | pass (move seen 2026-09-30; ⌥ copy unverified) |
| ⌘-click selects the sentence | needs a hand: the driver cannot hold ⌘ across a click |
| Table Layout → Borders off hides the grid; Header Row shades row 0 and repeats it atop the next page | pass (both seen on screen 2026-09-30; repeat seen in PDF) |
| Misspelled word gets a red underline ~0.4s after it is shown; not the word being typed; right-click offers corrections | pass (seen 2026-09-30) |
| STARLING_IME=1: letters, Backspace, Enter arrive through the text-input plugin | pass (seen 2026-09-30) |
| STARLING_IME=1 with Pinyin/Japanese: composing underline, candidates, commit; dead keys; press-and-hold | needs a hand (driver keys arrive uncomposed) |
| Click inside a table cell puts the caret in that cell | pass |
| Click on a picture selects it | pending |
| Wheel / trackpad scrolling, incl. momentum | pass |
| Scrollbar drag | pending |
| Pointer is an I-beam over text, an arrow elsewhere | fail → M2 |

## Keyboard — motion

| Item | Status |
| --- | --- |
| ← → ↑ ↓, with ⇧ to extend | pass |
| ↑ ↓ keep the sticky x across short lines | pending |
| ⌥← ⌥→ by word | code |
| ⌥↑ ⌥↓ paragraph start/end | code (new) |
| ⌘← ⌘→ line start/end | pending |
| ⌘↑ ⌘↓ document start/end | pending |
| Home / End line edges; ⌃Home / ⌃End document | pending |
| PageUp / PageDown move a screenful and scroll | pending |
| Tab in a table moves to the next cell; ⇧Tab back; in the last cell it adds a row (changed 2026-09-30) | unverified (headless) |
| Typing while scrolled away brings the caret back into view | pending |

## Keyboard — editing

| Item | Status |
| --- | --- |
| ⏎ splits; at the end of a heading/title the new paragraph is Normal | code |
| ⏎ on an empty list item ends the list | code (new) |
| ⇧⏎ inserts a line break inside the paragraph | pending (new) |
| ⌫ at the start of a list item removes the bullet, then joins | code (new) |
| ⌫ / ⌦ at a cell wall do not join across it | code |
| ⌫ after a picture selects it, then removes it | code |
| ⌥⌫ / ⌥⌦ delete a word | code |
| ⌘⌫ deletes to the line start | code (new) |
| Tab / ⇧Tab outside a table: indent/outdent when selected, else a tab | pending |
| ⌘Z / ⇧⌘Z undo and redo, typing coalesces per word | code |
| ⌘A ⌘C ⌘X ⌘V | pass |
| ⌘B ⌘I ⌘U | pass |
| ⌘E ⌘L ⌘R ⌘J alignment | code (new) |
| ⌘] ⌘[ grow / shrink font | pending (new) |
| ⌥⌘1 2 3 headings, ⌥⌘0 Normal | pending (new) |
| ⌘F find, ⌘H replace, ⌘G next, ⌘S save, ⌘O open, ⌘N new, ⌘P print | pass (F/H), pending (rest) |
| ⌘= ⌘- ⌘0 zoom | pending |
| Esc collapses a selection; closes find, header bar, Backstage | pending |

## Window and chrome

| Item | Status |
| --- | --- |
| Focus returns to the document after every ribbon button | pending |
| Ribbon drop-downs open under their button and close on a pick | pass |
| Window resize relays out; ribbon never overflows at 1440 wide | pass (1440) / pending (narrower) |
| Dark mode via the shell theme | pending |
| Read Mode collapses the ribbon; Print Layout restores it | pending |
