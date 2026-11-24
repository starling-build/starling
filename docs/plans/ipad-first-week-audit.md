# iPad app: first-week audit (2026-11-24)

Method: the in-app driver (`STARLING_SPIKE_INPUT`) on an iPad Pro 13" simulator (iOS 18.4), main at 36b4e9d55, Writer
(ex.docx), Slides (sl.pptx), Sheets (sh.xlsx); outcomes read from screenshots and, where possible, from the saved
file. System UI (Files picker, share, print dialog contents), long-press, selection handles, pinch and a hardware
keyboard cannot be driven from inside the app: those are on the real-iPad list. Findings only, no fixes.

## Ranked (how often a user hits it x how much it hurts)

1. **Insert > Pictures opens an in-app file panel over the app's sandbox** (Home / Desktop / Documents / Downloads
   inside the container: Library, SystemData, tmp). No Photos, no Files, no iCloud, no camera. Writer and Slides
   (same panel; Sheets has no Pictures at all). Every user who wants a picture hits it. HIGH.
2. **Sheets shows "AutoSave on" but never autosaves.** Typed B2, waited 20 s: not in the file; only the Save button,
   backgrounding or closing the window writes (a crash or force-quit loses the edits). Writer and Slides do autosave
   (verified in the file). Everyone who edits a workbook. HIGH.
3. **No Share.** No share sheet anywhere (`UIActivityViewController` is not used). Export writes "beside the document
   or in Documents" (Files > On My iPad > Office) and the user must go find it; the print dialog's own share button is
   the only share path (PDF). Sending a document is a first-week task. MEDIUM-HIGH.
4. **File > Close goes to a blank "Document1", not back to the Files browser** ("Close the document and start a blank
   one"). The browser is only reachable via File > Open. Ends every editing session. MEDIUM.
5. **File > Home (Backstage) first screen is broken on iPad:** the Recent row wraps the file name one letter per line
   and prints the whole sandbox path; "Publish documents / New publication" (a desktop feature) is offered; Info's
   "Location" is the sandbox path. Seen by everyone who opens File. LOW severity, HIGH visibility.
6. **Writer feature gaps a first-week user asks for:** Review tab = Spelling + Word Count only ("Track changes,
   comments, footnotes, a table of contents, shapes, text boxes and drawing are not in this build"); no chart in
   Insert; Table = five fixed sizes, row ops only (no column ops, merge, borders). Sheets Insert = charts and
   functions only (no table, picture, shape, link). Not iPad-specific. MEDIUM, common.
7. **Ribbon and tile rows clip at the right edge with no hint** (Slides Home "Shapes", Sheets Home "Editing", Export
   and New tiles half-cut). The ribbon does scroll sideways by drag (verified), the tile rows were not tried. LOW-MEDIUM.
8. **Double-tap on a word did not select it** (driver double tap, 120 ms apart; a caret was placed). Confirm on a real
   iPad before treating as a bug. MEDIUM if real (every touch user selects words).
9. **Cosmetics:** buttons print "Print." / "New publication." (the ellipsis glyph is missing); "Find in document
   (Cmd-F)" hint on a device that may have no keyboard; Save As suggests the name "ex" without an extension (check on
   a device what the file is called).

## Verified working
Open from the native browser (File > Open); edit text and AutoSave to the file (Writer, Slides); formatting buttons;
undo; Find (bar, match highlight); insert table (3x3 saved as w:tbl, contextual Table Layout tab); touch scroll;
ribbon scroll; tap-to-edit a text box in Slides; slide show start, tap to advance, end; Print (system dialog with page
previews); Save As and Export through the system picker; Sheets cell edit, formula (=B2*6 -> 42) and Save.

## Real-iPad list (not drivable from the app)
Long-press menus and selection handles; pinch zoom; Magic Keyboard shortcuts; the Files picker contents and the
exported file's name; drag out of a window; a full-height and a floating soft keyboard; frames stop when backgrounded;
the 50-open/close-cycle device check; two-hand touch ids; a window on an external display (mirrored by decision).
