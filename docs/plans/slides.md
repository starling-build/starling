# Slides — a presentation app beside Writer

Status: **approved 2026-09-30** with three answers: one app for both
kinds, charts in v1, 16:9 by default (PowerPoint's own default since
2013: Widescreen, 13.333 x 7.5 in). Phase 5 of
`docs/plans/office.md`, given its own revision as that plan promised.
macOS first, like Writer; nothing here may break the wasm or iOS builds
of the shared code.

## Office landing presentation (2026-10-01)

`ui/openoffice` now presents six real Slides pages: the office suite,
Writer, Slides, Sheets, planned platforms, and the open source project. The browser starts
OfficeApp at `/office-landing`, reads `slides/landing-wide.pptx` and
`slides/landing-tall.pptx`, and uses the existing `SlideShowView` and painter.
The HTML supplies links, accessible slide descriptions, and navigation; the slide content
is editable PPTX text and shapes, including document, presentation, and
workbook illustrations for the three app panels. Writer, Slides, and Sheets
link to their public web apps.

`OfficeLandingDeck.swift` generates the initial decks. Native OfficeApp's
`--landing-deck OUTPUT [--portrait]` writes them.
After building native OfficeApp and `build/web-app.sh OfficeApp --package
apps/OfficeApp`, run `build/office-landing.sh` (`OFFICE_BIN` can select the
native executable). It generates both decks and prepares a versioned web
runtime with a matching font manifest. Serve `ui/openoffice`, then run
`node build/tools/office-landing-posters.mjs http://127.0.0.1:8006/` to
capture all twelve previews from the real rendered canvas. The generated
PPTX and preview PNGs are source assets; runtime files are ignored build
outputs. Publish `runtime.json` and its referenced runtime directory with
the site when deploying.

The previews are visible immediately and remain navigable if live startup
fails. After startup, arrows, taps and swipes control the live presentation;
changing the viewport swaps decks while preserving the slide index. An
editable deck download remains available in the page.
The regular OfficeApp route still opens Writer.

The Swift 6.4 web build also needs the concurrency executor factory: legacy
global/main enqueue hooks leave image-decoding MainActor tasks queued.
`WebExecutor` now installs that factory for current compilers, retaining
the hooks for older ones. Slideshow painters track decoded-image and font
revisions so asynchronously loaded assets trigger a repaint. The factory
integration follows the current [JavaScriptKit executor integration](https://github.com/swiftwasm/JavaScriptKit/blob/main/Sources/JavaScriptEventLoop/JavaScriptEventLoop%2BExecutorFactory.swift).

Validation after rebasing onto `office` (`c7b9af81`): all 94 Office unit tests pass, the release WASM build succeeds,
and browser checks cover startup at a slide hash, buttons, keyboard, Tab
focus exit, phone swipes, viewport rotation preserving the current slide,
the text dialog, the last-slide boundary, and preview navigation when the
runtime request fails. The upstream date fields use browser timezone offsets
and an English Gregorian formatter on WASM, avoiding the native-only
Foundation date formatter; parity tests cover its formats, leap day, midnight,
and noon. The icon subset includes the 141 icons exposed by the updated SDK. Both screenshot orientations were captured from
Slides and visually checked; the default Writer route also loads.

## What "done" means for v1

Someone can open a `.pptx` a colleague sent, fix a few slides, add one,
present it full screen, and send the file back — and the colleague's
PowerPoint opens it without complaint and without layout drift on the
slides we touched. Starting a deck from scratch is the second case:
pick a theme, add slides from layouts, type, drop in pictures and
shapes, present.

Charts are v1 (the user's call): column, bar, line, pie, area and
scatter, drawn from the values the file caches, with their data edited
in a small grid. Not v1: SmartArt, video and audio, morph and motion-path
animation, comments, co-authoring, ink, 3D. A file carrying any of
these opens, shows a labelled placeholder box where the object sits,
and keeps the original XML so a save writes it back untouched.

## Shape of the code

**One app for both kinds.** `apps/OfficeApp` opens a `.docx` as a
Writer document and a `.pptx` as a deck, and Backstage's New offers
both. The session carries a document kind; the shell swaps the ribbon's
kind-specific tabs and the body (pages for Writer; thumbnails, slide
canvas and notes for Slides) while the title bar, Backstage, File tab,
status bar, colour bars, find and the recovery copy stay shared. No
package split is needed. The window title names the kind
("Deck1 — Slides"); the bundle's own name is an open question below.

**New code, by layer:**

| Layer | Where | What |
| --- | --- | --- |
| Model | `Slides/Deck.swift` | `Deck`, `Slide`, `Shape`, `Theme`, `Layout`; value types, points as the unit |
| Controller | `Slides/DeckController.swift` | every mutation, one undo stack, selection |
| Canvas | `Slides/SlideCanvas.swift` | one slide, zoomed to fit, shapes + handles + guides |
| Painter | `Slides/SlidePainter.swift` | paints a slide at any scale; canvas, thumbnails, show and PDF all use it |
| Format | `Slides/Pptx.swift` | PresentationML read/write over the existing `Zip` and `MiniXML` |
| Show | `Slides/SlideShow.swift` | full screen, transitions, keys, presenter layout |
| Charts | `Slides/Chart.swift`, `ChartPainter.swift` | chart model, DrawingML chart read/write, painter, data grid |
| Chrome | `Slides/SlidesRibbon.swift`, `ThumbnailPane.swift`, `NotesPane.swift` | |

Text in a shape is a `RichDocument` edited by the existing
`RichEditable` with `pageSetup: nil` (a continuous column the width of
the box). Writer's character and paragraph formatting, lists, spelling,
IME and clipboard come along for free, and the ribbon's Font and
Paragraph groups are the same widgets bound to whichever text box has
focus.

## The model

```
Deck
  slideSize          13.333 x 7.5 in (16:9) by default; 4:3 and custom
  theme              colours (12 slots), heading + body fonts, background
  layouts            Title, Title and Content, Section Header, Two Content,
                     Comparison, Title Only, Blank — each a list of placeholders
  slides [Slide]
    layout           which layout it follows
    shapes [Shape]   back to front
    notes            RichDocument
    background       inherits from theme unless set
    transition       none | fade | push | wipe | cover, duration
    hidden           skipped in the show

Shape
  id, name
  kind               placeholder(role) | textBox | geometry(preset) |
                     line/connector | picture | table | group | opaque(xml)
  frame              x, y, w, h in points; rotation; flipH/flipV
  fill, outline      solid colour or theme slot, width, dash, arrowheads
  text               RichDocument? + insets, vertical anchor, autofit
  animation          (M7) entrance effect, order, trigger
```

Placeholders resolve against their layout at read time, the way Writer
resolves `.docx` styles to absolute values: a title placeholder that does
not set its own position or font takes the layout's, and the model holds
the resolved result plus "inherited" flags so a save writes back only
what the user changed. `opaque(xml)` is how unsupported objects survive a
round trip.

## Where it stands

### Next (as of 2026-10-11)

The painter gate after sweep 27, 553 decks against PowerPoint's own
export of each: mean 3.01% of pixels differing. By band:

| deck's mean | decks | points of the 3.01 |
|---|---|---|
| ≤ 2% | 371 | 0.34 |
| 2–20% | 174 (90 at 2–5, 54 at 5–10, 30 at 10–20) | 1.96 |
| > 20% | 8 | 0.71 |

So the worst-ranked decks are no longer where the work is. Of the
eight over 20%, two are truncated zips from a fuzzer that PowerPoint
recovers more of, one PowerPoint exports black (tdf113163), and the
rest want whole features for one to five decks each (`a:scene3d`
materials, TIFF and JPEG-XR, WordArt fills). Two thirds of what is left
is in the middle band, where one cause tends to recur across many
decks — the line height was one such, and moved dozens at once.

In order:

1. **See today's work on screen.** Everything since the SmartArt engine
   was verified through the headless PDF export, and the editor has
   paths the export never takes. Known already: a turned table cell's
   text draws turned but its caret and selection do not, so editing one
   looks wrong; a metafile's own bitmaps decode asynchronously and rely
   on the repaint that `onImageDecoded` asks for; a metafile as a shape
   or background *fill* (not a picture) is not drawn. `test/slides-drive.py`
   is the way in.
   **Done 2026-10-31 (macos-ios, c8c4eea1b):** all three seen on screen
   and settled. A turned table cell's caret, selection and click now map
   through the cell's turn (`RichLayout._turnedFrame`; the click used to
   find the end of the text wherever it fell); a metafile as a shape's or
   background's picture fill is played over the area (`paintFill`,
   stretched or into its `a:fillRect`, not tiled — no corpus deck has
   one, a test deck is a rect/ellipse with `a:blipFill` on a WMF/EMF part);
   a metafile's own bitmaps were already fine on screen (lo-tdf149206's
   WMF and its thumbnail). Painter gate, 553 decks: no movers. To drive a
   deck by hand: `Driver.launch(args=[path])` with a COPY of the deck (the
   app writes a `~` backup and restores unsaved edits per file), and a
   debug build needs `apps/OfficeApp/.build/debug/data` (copy it from a
   checkout that has one) or the engine's ICU data check aborts at launch.
2. **Triage the 2–20% band.** Sample it (every fifth deck by rank, say),
   put a cause on each from its pair image, and fix what recurs.
   Suspects, unmeasured: wrapping that differs by a word (font
   substitution — Liberation and Carlito are metric-compatible, the
   rest are not), autofit landing a step off, bullet and paragraph
   spacing given as a percentage, and the title shadows and glows this
   app does not draw.
3. **Metafiles in Writer.** `Metafile` is app-level and only Slides
   calls it: a Word document's WMF or EMF picture is still a box.
   Mostly wiring, in `RichLayout`'s picture path and the PDF export.
4. **The mid-size features**, when a deck that matters needs one:
   multi-column bodies (`bodyPr numCol`, two corpus decks), WordArt
   text fills and warps (two or three), and the metafile leftovers —
   hatched and pattern brushes, arcs, EMF+ where there are no GDI
   records beside it.

About the oracle. PowerPoint's side of every score is a fixed set of
PDFs, exported once by `test/pptx-powerpoint-render.sh` on 2026-10-08
(PowerPoint for Mac 16.113). A sweep runs only this app and
`test/pdf-diff.swift`, which is why sweeps are comparable with each
other — and why an update to PowerPoint, or to a corpus file, means
regenerating all of them before the next number means anything. Since
2026-10-11 the decks, those PDFs and the last sweep's per-deck scores
are in the repository (`test/corpus/pptx`, with a README on provenance,
licences and how to run and regenerate): they had lived only in
`~/.cache` and `~/starling-ppt-check` on one Mac, and the PDFs cannot
be downloaded again. `test/pptx-app-render.sh` with no arguments sweeps
that copy.
Where PowerPoint for Mac and the file format part ways the format's
reading is kept and the cost written down (an `ExtTextOut` opaque box,
+3.5 on activex_textbox; the editor's placeholder box no longer shown
in an export, +6.6 on the 45541 deck until its WMF preview drew).

**On Windows, 2026-10-11.** The gate runs there too: OfficeApp builds
for Windows (zlib from the fetched sources, as the web build has it;
the engine rebuilt with Skia's PDF backend, which
`build/win/engine-args.ps1` now turns on), `test/pdf-diff.py` scores
pages with MuPDF, and `test/pptx-powerpoint-pdf.ps1` drives PowerPoint
for Windows over COM — from a shell that is not elevated, or it cannot
reach a PowerPoint the desktop user has open. Sweep 27 again, by the
Windows build against the same Mac PowerPoint PDFs: mean 2.95% (the
Mac's 3.01), bands 370 / 175 / 8, every deck the same page count, no
errors; 418 of 553 within 0.15 of the Mac's score. Nothing found that
this platform draws differently — what moved is the rasteriser
(`test/corpus/pptx/README.md`, "Sweeping off a Mac";
`baseline-mupdf.tsv`). One measure of the oracle itself: PowerPoint for
Windows against PowerPoint for Mac on 60810 is 3.8% (worst page 8.3),
so a few points of a text-heavy deck's score are the two PowerPoints.

**A drawn diagram's text, 2026-10-11** (sweep 28, Windows and MuPDF
only: 2.95 → 2.94%, ≤2% 370 → 372; 13 decks down, three up — two by
0.06 and the gear deck by 0.3, its text now visible and turned).
Found through `lo-tdf93830`, whose SmartArt text was white on white:

- **The colour scheme's text colour beats the drawing's `fontRef`.** A
  drawing part's `fontRef` is the quick style's (`lt1`), whatever the
  colour scheme says; PowerPoint lays the diagram out afresh and takes
  the node's style label's `txFillClrLst` (dk1 on an outlined scheme).
  Surveyed over every drawn diagram in the corpus: the two disagree
  only where that list names a colour (six decks), and an empty list
  leaves the fontRef to rule. The reader now puts a named one in the
  fontRef's place, by the shape's `modelId` → presentation point →
  `presStyleLbl`. Scores rose at first on those decks: text that was
  invisible had cost nothing, and now showed where it sat wrong.
- **Space after as a percentage (`spcAft spcPct`) was dropped** — only
  points were read, though space before had both. Read like it, and not
  applied under a body's last paragraph, where PowerPoint adds nothing:
  counted there, every one-line SmartArt label (35% after) measured
  taller than its box and was shrunk to fit (17 decks worse until then).
- **A percentage of spacing is of the size the runs are set in**, not
  the level's default: a SmartArt label is 31 pt by its runs under a
  level that says nothing (alterman_security 10.5 → 9.5, 60810 −0.2).
- **A bullet is one character**: `buChar char="••"` drew two.

Left on those decks: a gear's text is turned with its shape where
PowerPoint keeps it upright, and tdf141058's elbow connectors are
straight lines.

**The 2–20% band, sampled, 2026-10-11** (sweep 29, Windows and MuPDF:
2.94 → 2.90%, ≤2% 372 → 377, 2–20% 173 → 168; 15 decks down, two up by
under 0.1). Every seventh deck of the band by rank, 25 of them, a cause
put on each from its worst page:

| cause | decks |
|---|---|
| a diagram laid out here, sized or placed unlike PowerPoint's | 5 |
| `a:scene3d` (extrusion, camera) | 5 |
| a face this app does not have, so the text wraps elsewhere | 4 |
| one small thing wrong, visible in the picture | 7 |
| hairlines, anti-aliasing, a texture's resampling | 4 |

So about a fifth of the band is the diagram engine and another fifth
single causes; fonts and 3D are a third and stay. Fixed from the
"one small thing" pile:

- **Text that does not wrap** (`bodyPr wrap="none"`, 986 shapes in 62
  decks) was wrapped at its box. `SlideShape.noWrap`: the painter lays
  it out as wide as its longest line (the narrowest width with no more
  lines than at no limit) and hangs the excess off the side its first
  paragraph is not aligned to (`SlideTextCache.textLeft`). tdf104722's
  title, one letter per line in a 94 pt box, 3.1 → 1.1. The editor
  still wraps: its column is the box.
- **A table cell's `a:noFill`** left the row's band or header showing.
  It is a fully transparent `CellRef.fill` now, and the layout stops
  the row's shading at such a cell's edges (tdf164936 7.4 → 0.3,
  tdf135843_insideH 8.7 → 4.4, table-shadow 3.9 → 0.8).
- **A line at alpha 0 is no line**, on a shape or a cell's edge; a
  shape's gradient line is its first stop that shows, where it had
  fallen through to the style's colour (tdf149588 3.5 → 0.5).
- **A title or body does not take the presentation's default text
  style** — only the master's title and body styles; the default is for
  the other objects. alterman_security's says `i="1"` at every level
  and its bodies drew italic.

Seen and left: an untyped `<p:ph/>` with no `idx` on a layout whose
content placeholder is `idx="1"` reads as that body (bullet, 28 pt)
where PowerPoint gives it no master styling (formatting-bullet-indent),
and that deck's `indent="900000"` on a plain paragraph is not drawn;
text in an ellipse wraps a word early (shape-text-glow-effect, whose
glow is not drawn either); a path gradient's focus (tdf94238).

**The diagram engine against its pictures, 2026-10-11** (sweep 30,
Windows and MuPDF: 2.90 → 2.85%; 12 decks down, two up by under 0.1).
The band's largest single cause, taken deck by deck:

- **A hierarchy's labels were 2.3 pt.** An org chart is defined at ten
  times the frame (`w` = 10 × the width) and brought down by `fit`,
  which scaled `primFontSz` and the margins along with the boxes. They
  are left alone now — the 65 pt cap is for the boxes as they end up,
  and the reader fits the text from there. Every org chart had been
  boxes with a dot in them, on the Mac too (the baseline scores agree).
- **`hierBranch`**: named without a value it is "std" (it had matched
  no branch: a standard block drawn with hanging connectors, and a
  child lost), and "init" is PowerPoint's own choice, which the
  definition has no branch for — a node whose children are all leaves
  hangs them to its right, any other and the top of the chart sets
  them side by side (worked out from org-chart2 and org-chart against
  their pictures). The line to hanging children comes down clear of
  them, 0.16 of a box outside their edge; they sit 0.25 of a box left
  of the parent's middle. recursion 14.7 → 2.8.
- **Assistants** (`hierChild3`) stand between the shape and its
  children, their right edge just left of the trunk, and a
  `bendPt="end"` connector bends half a level's space above the child
  however far up the parent is. org-chart 15.5 → 13.0: what is left is
  packing — PowerPoint sets the second root beside the first, over its
  subtree's empty corner, where this sets subtree boxes side by side.
- **A cycle's ring** follows from the space between siblings when there
  is one (the chord is a node and that space), ahead of `diam`: cycle7
  gives both as proportions of a frame-wide node, and held to the
  diameter its boxes were a third of PowerPoint's. Connectors sit on
  the chord between their neighbours, not out on the ring (which also
  swelled the extent everything is scaled from), and arrowheads at both
  ends are a `leftRightArrow`. multidirectional 10.9 → 3.9.
- **A cycle node's own constraints are applied before it is sized**:
  `h` = `w` is what makes cycle2's nodes circles, and applied after, it
  could only shrink a slot already too flat. cycle 4.6 → 1.3.
- **Nodes that start at one size end at one size**, the smallest any of
  them needed (`primFontSz op="equ"`) — `DeckController`, over a
  diagram's laid-out shapes by their nominal size. Eight decks by a
  little.

Second pass, same day (sweep 31: 2.85 → 2.80%, ≤2% 378 → 381):

- **The diagram's own background and outline** (`dgm:bg`, `dgm:whole`
  in the data part) are a rectangle the size of the frame behind
  everything, for a drawn diagram and one laid out here alike.
  smartart-background 8.3 → 1.3, its drawing-part twin 7.5 → 0.6.
- **A factor of a thousand is not a proportion.** `h` = 1000 `w` is how
  a layout says "as tall as it needs"; kept in step with it, a step as
  tall as the frame was a third of a point wide, and accent-process had
  no boxes. Such a composite has no height to hand out either: its
  children keep the heights their constraints gave them, where an
  `INF` rule had stretched them to the frame's foot. A shape moved by
  `zOrderOff` onto another's place goes past it (the label was behind
  its own box). accent-process 9.8 → 6.1; its boxes are still a fifth
  larger than PowerPoint's and its child boxes shorter.
- **A snake's item is sized by its own proportions**, applied before
  the grid is chosen (`h` = 1.06 `w`), and the grid is the column count
  that comes out largest in the frame, not the one nearest the frame's
  shape. And **a size of 1 is a unit**, not a point: `w` = 1 taken as a
  width collapsed each item to a line down its middle, and its
  contents were laid out from there, half an item low.
  snake-rows 13.8 → 1.6.

Left: linear-rule (the arrow's text and proportions), missing-bullet
(a `bgShp` drawn pale, and the text sized unlike PowerPoint's),
vertical-box-list (the box taller than PowerPoint's), children (rows
share height unlike PowerPoint's 3:4), cycle-matrix, and org-chart's
packing.

**The worst single pages, 2026-10-11** (sweep 32, Windows and MuPDF:
2.80 → 2.70%, ≤2% 381 → 386; 12 decks down, two up by under 0.2; all
59 matched decks still match). From a sheet of the twelve worst
one-page decks that are not 3D or fonts:

- **A turned or mirrored group was kept and never drawn** — a show and
  an export had nothing where it stood, since the editor's box is not
  shown there. It is drawn as its members now, each placed by the
  group's child space, mirrored about the group's middle when the group
  is, then turned about it and by its angle (`OpaqueObject.rendering`,
  as a diagram's shapes are; the file's element is still what is
  written). tdf100065 12.2 → 0.04, group-rot 2.4 → 0.1,
  forum-mso-de-138303 4.7 → 0.6, 54542_cropped_bitmap 5.4 → 1.8.
- **`mc:AlternateContent` was an object box**: drawn as its fallback's
  shapes, or its choice's where the fallback holds nothing this app
  reads (a diagram in each: tdf131553, 10.7 → 0.4).
- **A chart's legend goes where `c:legendPos` puts it** — beside the
  plot (r, l, tr) as a column, or above — where it was always below;
  absent, the schema's default is the right. `Chart.legendPosition`,
  written back. pie-chart 10.6 → 4.7.
- **A built-in table style's first column, last column and last row**
  are dressed like the header when the table's flags ask (the deck does
  not define these styles; this is Medium Style 2's way). tdf149785
  9.1 → 4.7.
- **A picture fill with neither `a:stretch` nor `a:tile` is tiled**, on
  a shape as on a background, and a shape's `a:tile` is read at all (it
  was always stretched). tdf128596 9.1 → 3.0.
- **`a:lin scaled="1"`**: the angle is of the unit square and stretches
  with the area (`SlideFill.scaled`). tdf105739 moved little — the
  direction is right now, PowerPoint's ramp still holds its end colours
  longer.

Seen and left: a chart's own series colours, bold title and data labels
(tdf149985); justified text and picture bullets (pptx2svg); an empty
table row's height (tdf144092-emptyShapeTextProps); hList1's item
heights and shadows (fill-color-list).

**Where a body's lines fall, 2026-10-12** (sweep 33, Linux and MuPDF:
2.70 → 2.57%, ≤2% 387 → 396, 2–20% 158 → 149; 120 decks down, 14 up, the
most by 0.5; 60 matched — two gained, `lo-slidenum_field` lost at 0.01%).
Measured, not seen: the baseline of every line in PowerPoint's PDF
against ours (`page.get_text("dict")` in MuPDF gives both), which says
which of two lines is off by a point where a pair image shows a blur.
Four things, each of which alone made as many decks worse as better,
because they had been cancelling each other:

- **"Single" is 1.2 of the size, for every face.** PowerPoint's own pages
  have Arial, Consolas and Lucida Sans Unicode (1.15, 1.17 and 1.47 by
  their metrics) all at 1.2; Calibri's 1.22 was near enough to have
  looked like the face's own. `RichTextTheme.singleLineHeight`; Word
  keeps the face's.
- **No space before a body's first paragraph** (`omitsLeadingSpace`):
  `sample` lands on PowerPoint's baseline to the tenth of a point.
- **`lnSpcReduction` is taken off the spacing, not multiplied into it**:
  90% less 20% is 70%. `lineSpacingReduction`, in `lineSpacingScale`'s
  place.
- **The export lays out at four pixels a point.** The engine sets a line
  on whole pixels, so at one a point 12.8 was 13 and 26.5 was 27, and a
  long body ended a third of a line low.

With them: **`bodyPr numCol`** — a body in columns, each filled to the
box's height before the next, `spcCol` apart, as the layout's pages
(lo-3columns 12.4 → 7.0); and **a bullet sits on its line's baseline**,
where one at 80% of the size hung six points above the text.

Left: the editor's caret and selection in a columned body follow the
layout's page geometry and were not looked at on screen; autofit does not
know about columns; lo-tdf169524 (+0.3) spaces its lines at 1.08 of the
size by something not found.

**WordArt and shapes with depth, 2026-10-12** (sweep 34, Linux and MuPDF:
2.57 → 2.41%, ≤2% 396 → 400, over 20% 8 → 6; 20 decks down, six up by
0.1 to 2.2).

- **WordArt** (`Slides/WordArt.swift`): a body with a `prstTxWarp` is
  fitted to its box and bent, where it was laid out flat at its own
  size. The envelope bends (plain and its slant, inflate, deflate and
  their halves, the waves, can, triangle, chevron, slant,
  deflate-inflate) stretch every line across the box between two
  curves; arch, circle and button set each line along the box's ellipse
  at its own size. There are no glyph outlines to bend, so a character
  is drawn through the affine map of its own cell — exact along a path,
  and for the bends a letter leans and rides the curve without itself
  curving. (The rest came the same day: see below.)
- **A run's gradient or picture fill and its outline** (`a:rPr`'s
  `gradFill`, `blipFill`, `ln`) are read (`RunLook`, by run position)
  and drawn in WordArt, the fill as one across the whole word. This
  needed the engine: a text style's foreground crossed the bridge as a
  colour only. `ParagraphBuilderBridge::SetForegroundPaint` hands the
  next `PushStyle` a whole paint — shader, stroke — on the native
  bridge and the web one; and an `ImageShader` takes a raster image,
  which a headless export's decoded pictures are (it took only
  "UI-thread-safe" ones, so never one of those).
- **Shapes with depth** (`Slides/Extrusion.swift`): `a:sp3d
  extrusionH` under `a:scene3d`'s camera is drawn as the solid — the
  outline swept back, turned by the camera's latitude, longitude and
  revolution (the preset's, or the file's `a:rot`), its sides drawn far
  to near in the extrusion colour, else the outline's, else the
  fill's, lit by how they face. Oblique cameras slide the back aside
  instead (a fifth of the depth, measured), the legacy perspective
  ones draw it in toward a point as well, `legacyWireframe` is edges
  only, and a camera that only revolves a flat shape turns it in its
  plane. The outlines land on PowerPoint's (isometricRightUp 10.7 →
  4.1, wireframe 25.7 → 0.7, orthographicFront 12.7 → 0.7, the
  highlight rings 29.8 → 14.0). What it is not: bevels, materials,
  light rigs — one fixed light — or true perspective for the modern
  perspective cameras, which are drawn parallel.

The pixel score is a poor judge of WordArt: large letters a few pixels
from PowerPoint's cost more than small flat ones nowhere near
(WordArtDefaultColor 6.3 → 8.5 with the slant now drawn, Arial Black
standing in as Liberation Sans). Those six are up for that.

Left: the text of a 3D shape is drawn flat
over the solid; a deck's saved copy keeps the warp but not a run's
gradient or outline (they were never written); none of this was looked at in the
editor, on screen; lo-tdf146223's 2×2
JPEG backgrounds, which PowerPoint prints as one flat grey and this app
as four pixels — the file is a LibreOffice regression case, left alone.

**Every WordArt bend, 2026-10-12.** All forty presets are drawn now,
fitted against PowerPoint's own printing of each: `test/corpus/pptx-wordart`
is five decks made for it, eight bends a slide, and PowerPoint for
Windows' export of them — the corpus has a dozen of the forty, and the
first versions of the rest, written from what the names suggest, were
wrong about four families:

- **A pour** (Arch Up, Arch Down, Circle, Button Pour) is the text poured
  between two arcs of the box's ellipse — stretched from the outer curve
  in to half its radius, across the whole arc — not text along a path.
- **A ring** is the text round a ring seen from the front: its first half
  across the near side, the second coming back across the far side
  mirrored; inside the ring the near side is the upper arc.
- **Curve** tapers over a level foot; **cascade** runs from its full
  height to the adjust's share of it; **deflate-inflate** and its three-
  band sibling give one line the top band alone.
- **The text is fitted by the letters there are**: with no descender in
  it the baseline is the foot of the band ("Plain" fills its box, "Stop"
  leaves room for its p).

And: a run's look is found by where a character falls, not by the run's
position — the document merges runs alike in what it knows, so
"Double" + " Wave 1" was one run with two looks and drew black; text on a
path is filled letter by letter, each with the whole gradient, where
text fitted to the box shares one across it.

Left: a bend's adjust values other than the default are read and used
but were fitted at the default only; Button and the banded bends were
seen with one line.

**One deck at a time: lo-font-scale, 2026-10-12** (9.67 → 5.88; sweep 36,
Linux and MuPDF: 2.41 → 2.39%, 23 decks down, 14 up — the most
lo-3columns by 1.3, not looked into). The way of working from here: one
deck, one thing in it, measured against PowerPoint's page until it
matches; the whole corpus once, at the end. In this deck, three bulleted
paragraphs under `normAutofit fontScale="85000" lnSpcReduction="20000"`:

- **The fitted scale is the letters' alone.** The text began 4 pt left of
  PowerPoint's: `marL` had been shrunk with the font. `RichLayout.fontScale`
  scales the sizes; the indents, the spacing and the box stay the file's
  (81.3 where PowerPoint has 81.4).
- **A fitted size is a whole number of points**: 32 pt at 85% is set in
  27, not 27.2 — the lines were 4 pt too wide and one broke elsewhere
  (674.6 / 674.7).
- **A spacing under single comes off the space above the line**, the
  letters keeping their depth below, where the engine shares it out
  above and below: the first baseline was 1.2 pt low (87.9 / 88.1).
  `RichTextTheme.baselineShift`, for a multiple only, PowerPoint only.
- **A bullet is set in its own face** (`buFont`,
  `RichParagraphStyle.bulletFontFamily`): Arial's dot is two thirds the
  width of Calibri's. Not for a symbol face, whose codes become the
  glyphs they show.

Left in it: the gap between paragraphs is 32.5 pt where PowerPoint's is
31.9 — its space before comes out near 5.9 of the file's 6.41, by a rule
one deck does not give away (not the fitted scale: that would be 5.45).
The editor still lays fitted text out the old way (`SlideCanvas`'s zoom).

**One deck at a time: lo-3columns, 2026-10-12** (8.26 → 6.62; sweep 37:
2.39 → 2.38%, 19 decks down, ten up by at most 0.34). A body in three
columns under `fontScale="62500" lnSpcReduction="20000"`:

- **The export lays out at twenty pixels a point**, where it was four:
  the engine sets a line on whole pixels, so 12.6 pt was 12.5 and the
  sixteenth line of a column stood 1.6 pt high. 12.6 now, as PowerPoint's.
- **A column draws its own lines of a paragraph that runs on** into the
  next (`RichLayout._linesPainter`), where it showed the whole paragraph
  through a window: at a spacing under single a line's ascenders stand
  in the box of the line above, and the next column's first line showed
  as a row of specks under this one's last. Only where
  `singleLineHeight` is set; Word's pages keep the window.

Left in it: the first baseline is 0.5 pt above PowerPoint's, inside what
PowerPoint's own page rounds by in this deck (its pitches go 12.0, 12.9,
13.0).

**One deck at a time: tdf144092-emptyShapeTextProps, 2026-10-12** (11.80
→ 0.39; sweep 38: 2.38 → 2.35%, six decks down — aascu's leadership
summit 11.2 → 8.4 by the same — one up by 0.19). **An empty paragraph in
a table cell is as tall as its end mark says**: the cell's `endParaRPr
sz="9600"` makes its row 122 pt of nothing, as a letter that size would;
the cell reader took the cell's own size for an empty paragraph, where
the body reader already took the end mark's.

**One deck at a time: pptx2svg, its justified paragraph, 2026-10-12**
(7.99 → 6.94; sweep 39: six decks down, none up). The paragraph was
justified already; it broke its second line a word later than
PowerPoint's. **PowerPoint sets letters one by one**: the engine joined
Calibri's "tt" and "ti" into ligatures, which made "formatting" 72.8 pt
where PowerPoint has 73.4, and a line of such words had room for one
more. `RichTextTheme.disablesLigatures` (liga and clig off), for slides.
The lines break at the same words now, the last ending at 455.1 / 454.7.

Left in the deck, each its own task: its bullets are Wingdings stars
(drawn as dots); the last line's mixed faces, raised word and spaced
letters.

**One deck at a time: pptx2svg, its bullets, 2026-10-12** (6.94 → 6.91;
the corpus unmoved). `buFont typeface="Wingdings"` with `buChar char="✭"`
— U+272D, a star in its own right, not a Wingdings code — drew the
level's dot: the symbol-face table had no entry for it. **A character
that is a symbol by itself is that symbol whatever face is named**;
only Latin-1 and the private range are a symbol face's codes. Same
place and size as PowerPoint's (its star is Segoe UI Symbol's, this one
DejaVu's).

**One deck at a time: pptx2svg, its last line, 2026-10-13** (6.91 → 6.58
over two tasks; sweep 40: three decks down — the AES conference deck, in
Verdana throughout, 10.5 → 9.5 — none up; 179 Word documents, one 0.12
up).

- **Superscript and subscript leave the line.** They were shrunk and left
  on the baseline: the engine has no baseline to shift. The run now
  holds its place unseen (`textStyle(scriptHidden:)`) and
  `RichLayout._paintScripts` draws each stretch of it again, three tenths
  of the full size up or a fifth down — 7.0 and 5.0 pt at 24, as
  PowerPoint's page has them. Layout, carets and selections are as they
  were. Shared with Writer, whose superscripts rise too.
- **Verdana is DejaVu Sans** (`OfficeFonts.verdana`; four faces added to
  Resources/fonts, 3 MB), where it was Liberation Sans and an eighth
  short. Not a metric clone — there is none — but of the same design,
  and within a hundredth of Verdana's widths word for word; LibreOffice
  makes the same replacement. The file keeps "Verdana". The line ends at
  581.9 where PowerPoint's ends at 590.3 (517.4 before): Verdana's space
  is the wider.

Left in that line: "over" is Andale Mono, drawn in Liberation Mono. Not
checked: that the browser build fetches the new faces when a document
asks for Verdana (they are staged, and listed lazy in the manifest).

**One deck at a time: tdf105739, its gradient, 2026-10-13** (12.28 →
0.42; sweep 41: 2.35 → 2.32%, three decks down — tdf109067 3.6 → 2.5 —
one up by 0.13). A background of red to green at 45°, scaled. Its
direction and middle were right already; PowerPoint's ramp kept to red,
then to green, longer at each end.

The ramp is in PowerPoint's own PDF to be read: an axial shading over a
1,365-sample function. For this deck the samples are in a linear-light
profile and follow **a half cosine** — (1 − cos πt) / 2 — to within a
hundredth; for lo-subtitle-animation-save they are in sRGB and run
evenly. Across the corpus the first kind are gradients whose stops are
plain colours (`srgbClr`, no modifiers: tdf105739, tdf109067,
ImportWordArtGradient) and the second those of theme colours under
`tint`, `satMod` and the rest. `SlideFill.eased`, set by the reader when
no stop's colour has a modifier; `linearLight(_:eased:)`. Why PowerPoint
tells them apart is not known — and the second kind's even ramp in sRGB
is not what `linearLight` gives them (it blends them evenly in linear
light, as sweep 9 found for themes.pptx): not looked at here.

With it: a CDATA section's text is kept by the system XML reader on
Linux (`foundCDATA`; FoundationXML drops it where the Mac hands it to
`foundCharacters`), which a new test of the two readers found.

**One deck at a time: tdf149985, its chart's colours, 2026-10-13** (10.44
→ 6.31; sweep 42: two decks down — oox-chart-theme-override 1.1 → 0.5 —
none up). **A chart's theme override is its theme.** A chart pasted from
another file has a `themeOverride` part beside it, whose colour scheme
stands in for the deck's wherever the chart says `schemeClr`; the bars
were Office's gold, orange, green and blue where the chart's own accents
are a navy and three greens. The reader resolves the chart's colours
against the override, and a series that names a slot or leaves its
colour to the cycle — which are drawn against the deck's theme, later —
gets the colour it has in the chart's own. (The file's XML is what is
written back while the chart is untouched.)

Left in that chart, each its own task: the title's own run properties
(bold, centred, dark blue); the value axis's major unit and number
format; data labels; the legend's order and size; the user shape drawn
over the plot (`chartUserShapes`).

**One deck at a time: tdf149985, its chart's title, 2026-10-13** (6.31 →
5.70; the corpus otherwise unmoved). **A chart's title has its own
size, weight, colour and lines.** Every title was 18.6 pt of the theme's
text colour on one line; this one is bold 14 pt in 002060 with a break
in it. `Chart.titleSize`, `titleBold`, `titleColor`: the first run's
properties, over the paragraph's `defRPr`, over the title's `txPr`; a
paragraph or an `a:br` is a new line, each centred. Written back for a
chart this app writes. And chart text is set without ligatures, as
slide text is. Lands on PowerPoint's: 212.1 across, baseline 124.2 /
124.3.

**One deck at a time: tdf149985, its chart's value axis, 2026-10-13**
(5.70 → 5.65; aascu's download deck 12.8 → 13.1, below).

- **An axis is marked in no more than eight steps**: the smallest of 1,
  2, 5 × a power of ten that needs no more. It was six, which marked
  this chart 0 to 1,500 in 500s where PowerPoint has 0 to 1,600 in 200s.
  Two rules tied to the axis's length and the labels' size came first,
  and the full sweep threw each out on another deck (halves on the
  default chart; 50s on aascu's 0 to 600). Eight fits every axis of
  PowerPoint's pages looked at: 200s to 1,600, 100s to 600, ones to 6,
  twos to 10.
- **The axis's labels in its own size** (`c:valAx/c:txPr`,
  `Chart.valueLabelSize`) — 9 pt here, 8 on aascu's, where all were 12.
  That one costs aascu's deck 0.3: its labels are PowerPoint's size now,
  the column they stand in narrower, and its bars two pixels from where
  they were.
- **And in its own number format** (`c:numFmt`, or the first series'
  when it is linked to the source; `Chart.valueFormat`), through
  Sheets' `NumberFormat`: "1,600", and an accounting format's "-" for
  nought. Right edges within half a point of PowerPoint's.

With them, for the web build, which upstream's new code had stopped
linking: `RichLayout._cellSide`'s `range(of:)` is `firstRange(of:)`, and
`OfficeFonts`' lock is nothing where there is one thread.

**One deck at a time: tdf149985, its labels from cells, 2026-10-13**
(5.65 → 5.70, for now). The percentages on the top series' bars are
"Value From Cells" labels: the series' `c:dLbls` shows a
`c15:datalabelsRange`, whose cache has each point's text as the file
last had it. `ChartSeries.cellLabels`, with the series' label size,
weight and colour (`c:dLbls/c:txPr`); drawn inside the end of each bar
(`dLblPos inEnd`) for a column or bar chart. Present now, in white bold
12 pt, at PowerPoint's height to a point — and 11 to 20 pt left of
PowerPoint's, because the bars are: the legend is drawn at 12 pt where
the file's is 9, and takes that much of the plot. The legend is next,
and the score waits on it.

**One deck at a time: tdf149985, its legend, 2026-10-13** (5.70 → 3.45;
the corpus 2.127%, two decks closer, none further). The legend has its
own size (`c:legend/c:txPr`, here 9 pt; `Chart.legendSize`), and its
keys and gaps go with it. Beside stacked columns or areas it lists the
series in stacking order, the top of the stack first. A line of a legend
at the side is its text's height and 6 pt. It is within 2 pt of
PowerPoint's place, and being the right width it leaves the plot the
right width: the bars and the labels from cells, 11 to 20 pt off before,
are within 3. Left in this chart: the oval over the last bar (the
chart's own drawing, `c:userShapes`), the bold category labels, and the
shadow under the bottom series.

**One deck at a time: tdf149985, its category labels, 2026-10-13**
(3.45 → 3.46: right, and no closer). The category axis's labels have
their own size and weight (`c:catAx/c:txPr`; `Chart.categoryLabelSize`,
`categoryLabelBold`), here 12 pt bold. They are PowerPoint's letters
now, 2 pt above its and up to 3 pt left, which is the plot's doing: its
left edge is 4 pt out and the gap under the axis 3 pt short. Left in
this chart: that, the oval over the last bar, and the shadow.

**One deck at a time: tdf152070, its tiled background, 2026-10-14**
(7.61 → 2.69; sweep 44: the only deck that moved). A picture tiled at
60% across and 70% down, the grid moved 35 pt right and 40.5 down. Read
off PowerPoint's page: every triangle 69.7 pt apart across and 48.7
down, the first at the offset. Only `sx` was read, for both directions,
and `tx`, `ty` and `algn` not at all. `SlideFill.tileScaleY`,
`tileOffset`, `tileAlign` (`PptxReader.tile`, for a background, a
shape and WordArt alike): one tile placed by the alignment within the
area, moved by the offset, the rest laid edge to edge from it both
ways. Within half a point of PowerPoint's now; what is left is how the
JPEG's thin lines are smoothed. `flip` (every corpus deck says `none`)
is not drawn.

**Diagrams laid out here: sizes from a font size, 2026-10-14** (sweep
45; of the 35 decks whose diagram this app lays out, mean 4.41 →
3.80). Found through lo-vertical-bracket-list, whose text was 16 pt in
a 36 pt box where PowerPoint's is 65 pt in a 111 pt one.

- **A length that is a multiple of a font size is in millimetres.**
  hProcess3's arrow is `2 × primFontSz` and, at PowerPoint's 50 pt,
  283.5 pt tall: 100 mm. Read as points, every such box was 2.8 times
  too small and its text was shrunk to fit it. A margin is not: desTx's
  `lMarg` of 0.3 at 65 pt sets its text 19.5 pt in.
- **A layout that lets its text shrink does so until it fits.** With a
  `primFontSz` rule, a layout that overflows its frame at its own sizes
  is laid out again at the largest whole font size that fits (down to
  the rule's value), keeping the widths its algorithms give; the tree
  was scaled down instead, narrowing every box with the text. hList1
  (lo-smartart-dir) at 31 pt and hProcess3 at 50 are PowerPoint's own.
  A layout that fits at no size — an org chart drawn at ten times its
  frame — is scaled as before.
- **A box measured from another is held to that one's proportions
  first.** hList1's body starts under its heading, capped at 0.4 of its
  width; it started under the height the font asked for, a gap between
  them. Only a cap of `w` or `h` by the node's own other side: hProcess3's
  text is capped by a user variable (`userT`) that PowerPoint lets it
  outgrow.

Bracket list 6.75 → 1.58, linear-rule 9.17 → 0.48, dir 4.30 → 1.75,
linear-rule-vert 7.60 → 4.38, vertical-box-list 8.85 → 5.88,
fill-color-list 17.03 → 15.10. One worse: accent-process (process3)
6.04 → 9.25. PowerPoint sets it at 34 pt, and its body box is 1.6 × 34
mm as the layout says; the frame alone allows 55, so something else
brings it down — a fit of the text in its heading, perhaps, but no
reading of the margins found gives 34. Its old 31 pt was the old units'
accident.

**Diagrams laid out here: their text, 2026-10-14** (sweep 46: corpus 2.03 → 2.00%, 21 decks closer, four further by 0.1 or less; the 34
decks whose diagram this app lays out, mean 4.08 → 3.60). Found through
lo-smartart-missing-bullet (14.60 → 3.74), a pList2 whose frame was
pale where PowerPoint's is navy, its items 8 pt high and its text 60 pt
where PowerPoint's is 42 and 33. Read where PowerPoint saved its own
drawing of a diagram (lo-smartart-rotation2's pList2; every drawing in
the corpus for the spacing):

- **A presentation point's own `spPr` is that shape's**, over the colour
  scheme and over the data point's: the frame is `tx2` at 90%, set on
  that one shape. `DgmModel.presSpPr`.
- **A shape drawn as nothing still takes room.** pList2's `invisiNode`
  (`hideGeom`) holds the top of each item; left out of the item's
  extent, the item was centred 8.4 pt too high.
- **Children's text under their parent's, in one shape, is 78% of it**
  when nothing names a second size: 33 under 42 here, 51 under 65 in
  lo-smartart-bullet-list. Children shown alone take the first size
  (the bracket list's 65).
- **A margin no constraint names is 0.56 of the font size** — 256032
  EMU round 36 pt text in PowerPoint's drawing; a margin a constraint
  names with no value is 0, as the schema says.
- **Lines at 90%, 35% after a first-level paragraph and 15% after a
  lower one** — 369 of the 371 paragraphs of PowerPoint's own diagram
  drawings in the corpus. Seventeen decks closer, three further by
  about 0.1.

Left on missing-bullet: our text is 46 and 35 where PowerPoint's is 42
and 33 — its fit is a step or two tighter than ours.

**A size a constraint gave does not grow to fill, 2026-10-14** (sweep
47: 2.00 → 1.97%; lo-fill-color-list 15.10 → 1.41, lo-smartart-dir
1.76 → 0.65, nothing else moved). hList1's body is `1.22 ×
primFontSz` — 224.8 pt at 65, exactly PowerPoint's — with a rule
letting its height go to INF. That rule was read as "take the rest of
the column", and an empty body ran to the bottom of the frame. It is
leave to grow for the text; a size the constraints set is kept.

**Org charts packed by their outlines, 2026-10-14** (sweep 48: 1.97 →
1.93%; lo-smartart-org-chart 12.56 → 2.11, org-chart2 7.78 → 3.02,
data-follow 6.16 → 0.67; nothing else moved). PowerPoint's boxes were
166 × 83 where ours were 140 × 70, the same chart scaled less: its
second manager, with no one under it, stands one gap beside the first
manager's box — over the first one's staff — where ours stood past the
whole of the first one's subtree, and the wider tree was scaled down
more to fit. A hierarchy's siblings now come in as far as a gap from
the shapes already placed at the heights they have shapes at
(`layoutHierChild`, `shapeRects`).

With it (sweep 49): **a box sized in font sizes and squeezed by the
room it was given also counts as not fitting**, so the text shrinks.
A box directly in a row is clipped to its slot, so the overflow never
showed in the frame test (linear-rule-vert 4.38 → 4.01). Two tests:
`testASiblingPacksAgainstTheOutlineNotTheBoundingBox`,
`testFontSizedBoxesAreMillimetresAndShrinkToFit`.

**Diagrams laid out here: cycleMatrix, and fitting as PowerPoint fits,
2026-10-14** (sweep 50: 1.93 → 1.92%; cycle-matrix 7.21 → 2.61,
table-list 2.13 → 0.67, font-size 1.91 → 1.10, maxdepth 1.05 → 0.62,
picture-strip 3.87 → 3.22, vertical-block-list 1.09 → 0.59, background
0.96 → 0.45, org-chart 2.11 → 1.81, missing-bullet 3.74 → 3.54; two
worse by 0.2, below). Found through lo-smartart-cycle-matrix, whose
quadrants were flat slabs with bulleted text in a corner:

- **A fixed aspect re-applies the constraints** inside the square it
  cut: the quadrants are 0.433 of the circle each way (138.6 pt square
  in PowerPoint's), not of the slot before it was squared.
- **An edge offset moves a box whose size is given**, rather than
  stretching it (`lOff`… with `w`/`h` set): the quadrants stand 1% off
  the middle and keep their size.
- **A half-turned shape is mirrored both ways**, not across only — one
  mirror put the third quadrant's curve and text in the wrong corner.
- **A quarter-turned shape keeps its text upright**, as a second
  shape over the box its text area turned to (`shape` returns both).
- **Levels count from the shallowest point the shape shows**: the
  quadrants show their node's children, each a first level — centred,
  unbulleted, at the first size. Bullets start at the second level
  unless `stBulletLvl` says otherwise.
- **`op="equ"` font sizes group by the constraint**, not by the size
  the text was set at (`starling:sizeGroup`): the quadrants end at 43
  together and the side boxes at 12, where one smallest size for the
  whole diagram made them all 16. A size equal to another's joins that
  one's group.
- **Text shrinks by whole points to the rule's 5**, not by the text
  box's 7.5% steps, and paragraph spacing shrinks with it.
- **A shape's geometry inset stays when the font margins shrink**: an
  oval's inscribed box, a chevron's notch (`SlideShape.shapeInsets`).
  Scaled with the margins, the text was fitted to more room than the
  shape has — 53 pt in center-cycle's circle where PowerPoint's is 49,
  52 in maxdepth's chevrons where it is 45; both now PowerPoint's.
- **The fit is measured to a twentieth of a point**: in whole points a
  64.8 pt line counted as 64.

Worse: data-follow 0.67 → 0.89 and recursion 2.23 → 2.42 — both now 59
pt where PowerPoint has 58 (they were 55 by the old steps). At 59 the
line is 63.7 pt in a room of 64.3, so PowerPoint asks for slightly more
than our measure does; neither the margins unscaled nor the face's 1.22
line explain all three decks at once. recursion's root also stands over
the wrong place (centred under 360 where PowerPoint centres it over its
two children), as it did before.

**A path gradient from its focus, 2026-10-14** (sweep 51: 1.917 →
1.903%; GeomLec1 16.27 → 12.29, tdf154858 2.19 → 0.19, tdf94238 2.27 →
0.99, tdf114848 8.46 → 8.26; minimal-gradient-fill-issue 3.14 → 3.30,
below). GeomLec1's background is the theme's `path="circle"` fill with
`fillToRect l=65% b=98%`, black at the edges, grey at the top right; ours
was grey from edge to edge. Read off PowerPoint's page, the ramp is a
**two-point gradient**: it starts at a focus and ends on the circle
through the area's four corners, a true circle in points (squeezed to
the area's proportions it was ten times further off). Over 2,005 grey
pixels the model is within 0.003 of PowerPoint's ramp at the median,
0.014 at the 90th percentile.

- **The focus is the fill-to insets in proportion**: l / (l + r)
  across, t / (t + b) down (`SlidePainter.pathFocus`). That is the
  rectangle itself when it is a point, as almost every file has it;
  GeomLec1's 65/0 and 0/98 make the top right corner, where the
  rectangle's centre (82%, 1%) was 4 to 13 points of the ramp off. A
  focus outside the area (a theme's light from above the slide,
  `t=-80% b=180%`) keeps the circle round it as before — no deck has
  shown which is right there.
- **A path gradient of theme colours under modifiers blends evenly in
  sRGB** (`SlideFill.even`): the black-to-grey ramp is a straight line
  in PowerPoint's pixels, as tdf105739's work found for
  lo-subtitle-animation-save and left. Plain colours, even under
  modifiers (ImportWordArtGradient's alpha'd `srgbClr`), stay in linear
  light, and so do linear gradients: the 45541 decks' `gamma`/`shade`/
  `invGamma` bands went 7.4 → 10.6 blended evenly.

minimal-gradient-fill-issue's corner radial has both stops at 50%, a
hard edge PowerPoint draws soft; neither the old circle nor the new one
draws it so.

**A fill overlay, and nothing under a picture fill, 2026-10-14** (sweep
52: 1.903 → 1.888%; GeomLec1 12.29 → 8.17, aascu 5864 12.98 → 11.45,
backgrounds 4.73 → 2.03; picture-strip +0.12, below). The Concourse
theme's corner is a right triangle filled with a pale texture at half
alpha and `effectLst/fillOverlay blend="mult"` over it — a blue
gradient multiplied in. We drew it white. Now:

- **`a:fillOverlay` is a second fill on `SlideFill.overlay`**, read
  from the shape's effects over its own fill (a gradient or a colour)
  and painted in a layer with the fill: the overlay blended into the
  fill alone (`mult`, `screen`, `darken`, `lighten`; otherwise over),
  then the two onto the slide. Two decks use it, both this theme.
- **A picture fill has nothing under it.** `paintFill` drew the fill's
  colour first, white when it had none, so a picture at half alpha was
  half white instead of half what lies behind; backgrounds' tiled
  textures were the same. picture-strip's empty picture frames no longer
  paint white, which costs it 0.12 against a diagram laid out wrong
  anyway.

**Charts under another master's theme; fixed axis bounds, 2026-10-14**
(sweep 53: 1.8882 → 1.8871%; aascu cooper 7.61 → 7.11, aascu 5864
11.45 → 11.29). aascu 5864's chart slides hang from a third master whose
theme is Office's (blue, red, green, purple, aqua), while the deck's
theme — the first slide's — is Concourse's; a series that follows the
theme was drawn in Concourse's teal and red.

- **A chart on a slide whose master has another theme takes that
  theme's colours as its own** (`SlideContext.foreignTheme`), through
  the path a theme override part already took: each series that names
  a slot or follows the cycle gets its colour fixed at reading.
- **`c:scaling` min and max and `c:majorUnit` are the value axis's**
  (`Chart.valueMin`/`valueMax`/`valueStep`, written back). For fixed
  bounds the step keeps to ten intervals at most — 0 to 1 by 0.1, as
  PowerPoint's, where the automatic eight made it 0.2 — and bars past a
  bound are cut at the plot's edge. Only this deck fixes them.

Left on these charts then: the plot's place, and text this old chart
leaves unsized — PowerPoint's 10 pt with a bold title, ours 12.

**A chart's own look, as the file states it, 2026-10-14** (sweep 54:
1.8871 → 1.8834%; aascu 5864 11.29 → 9.84, LIBRE_OFFICE-100610-0 5.80 →
5.25; nothing else moved). LibreOffice's export of a survey deck and
aascu's old charts say more about their look than we read:

- **The plot stands where `c:manualLayout` puts it** (edge mode): the
  plot itself for `layoutTarget inner`, else a box it shares with its
  axis labels (`Chart.plotLayout`); a pie's area likewise.
- **A pie's slices take their `c:dPt` colours** (`pointColors`, written
  back), the legend's keys with them; a `dPt` that is the theme's own
  cycle keeps following the theme. Under another master's theme the
  cycle is fixed at reading, as series' colours are.
- **The plot area's fill** (`c:plotArea/c:spPr`) under the plot — a
  pie's, the square it stands in.
- **An axis with `c:delete` has no labels and no room for them, and a
  value axis with no `c:majorGridlines` no gridlines.** Both are written
  back.
- **Data labels in their number format**: the labels' own, else the
  numbers' (`formatCode` "0": 80, where we wrote 79.63).
- **No automatic title from a series with no name**: one unnamed
  series titled the census chart "Series 1"; PowerPoint shows none.

Left: 3-D (both decks' pies and bars are `view3D`, drawn flat), text
the chart leaves unsized (10 pt in PowerPoint), and category labels
PowerPoint turns 45° where they do not fit.

**Text shadows, 2026-10-14** (sweep 55: 1.8834 → 1.8821%; the three
45541/45545 decks 7.4 → 7.2, alterman_security 7.50 → 7.25; nothing
worse). 23 decks give runs an `a:effectLst/a:outerShdw` — 45541's
master puts a black one three points down and right under every title
and bullet — and we drew none.

- **`CharStyle.shadow`** (SDK, `CharShadow`: colour, offset and blur in
  points) is read from a run's or a level's effects, inherited through
  the levels like the other run properties (an effect list with no
  shadow turns it off), passed to the engine as a text shadow, and
  written back as an `outerShdw`.
- **Drawn sharp, at 45% of its strength where it is blurred.** The
  engine's blurred text shadow reaches PDF as a soft mask that Skia
  places at the page's corner: MuPDF and Poppler both showed nothing.
  Nine faint sharp copies spread over the blur came out wider and
  darker than PowerPoint's (whose 3 pt blur of a 2 pt stroke peaks at
  58% black) and scored worse than no shadow; one copy at 45% scores
  best of what was tried. A real blur, on screen and in PDF, wants the
  soft mask fixed in the engine.
- **A shadow cast on the ground is not drawn** (`sx`/`sy`/`kx`/`ky`
  other than identity: tdf114848's perspective shadows): as a copy of
  the letters it would stand up beside them.

**Table text in the table style's face, with its own bullets,
2026-10-14** (sweep 56: 1.8821 → 1.8787%; the AES conference deck 9.49 →
8.25, bug68703 3.48 → 3.11, bug62513 −0.13, customGeo −0.14; nothing
worse among the 55 decks with tables). The AES deck's tables are Verdana
in PowerPoint, where its default text style says Arial and we set them
in Arial, a word or two wider a line.

- **A table style's `tcTxStyle` face** (`fontRef idx`, or a named
  `a:font`) is its cells' text's, over the deck's default text style;
  a built-in style the deck does not define is the theme's minor font,
  as every one PowerPoint ships says.
- **A cell paragraph's own bullet** — its character, colour and size —
  as a shape's: the AES tables' "•" at every level, where the layout's
  own drew "◦" below the first.

Also looked at, and left: Divino_Revelado (14.3%) is a truncated zip;
PowerPoint repairs it into eleven blank pages and we draw what is in
it. The tdf139618 WordArt trio's bends are PowerPoint's to a few
points; what costs is Arial Black, for which no free face of its weight
is shipped (the shared font code the Writer session is changing).

**A chart's own text size, 2026-10-14** (sweep 57: 1.8787 → 1.8724%;
bar-chart 4.72 → 2.91, pie-chart 4.67 → 3.01, line-chart and
scatter-chart within 0.03). POI's five chart decks give the chart
space a text size (`c:chartSpace/c:txPr` 18 pt) and nothing else;
PowerPoint sets every label and the legend at 18 and the title, which
says nothing, at 22 bold. We set them at 12 and the title at 18.6.

- **`Chart.textSize`** is the labels', legend's and data labels' size
  where their own is unsaid, and an unsized title is 1.2 of it,
  rounded (21.6 → 22); written back in the chart space's text.
- **A title is bold where nothing says** — its runs, its paragraph, its
  own text or the chart's. aascu 5864's titles (14 and 12 pt, no `b`)
  are bold in PowerPoint too.

Left: tdf147586 says 12 everywhere and PowerPoint shows 10.5 and 10 —
the chart is drawn smaller than its text by something not found.
Also looked at and left: lo-tdf169524's body, whose lines are 1.08 of
the size within a paragraph and 1.22 between paragraphs in
PowerPoint with no spacing in the file, and lo-tdf98603's Hebrew
(FrankRuehl, and PowerPoint reads a paragraph `rtl="0"` right to left).

**A chart area's tiled picture and outline, 2026-10-14** (sweep 58:
1.8724 → 1.8667%; chart-texture-bg 6.38 → 4.35, chart-picture-bg 5.55 →
4.40). The chart area's picture fill is tiled at its own size when it
says `a:tile`, and placed by its `fillRect`, as a shape's is — the
paper texture was one sheet stretched over the chart — and the area's
own line (`c:spPr/a:ln`, a 2.25 pt blue frame on both) is drawn.

**Bullets on the baseline, Wingdings' round one at its size,
2026-10-14** (sweep 59: 1.8667 → 1.8660%; five decks a little closer,
45541 7.23 → 7.16, tdf126234 0.74 → 0.78). Measured on 45541's ink:
PowerPoint's Wingdings "l" is 14.7 pt across at 26 pt (0.565 em), its
foot 2.4 pt above the text's baseline; ours was 10.7 across and stood
four points higher.

- **A Slides marker stands on its first line's baseline** (the
  `markersAtHang` branch of the layout hung it from the line's top):
  26 decks by about 0.01 each.
- **A stand-in bullet's own face and scale** (`bulletStandInFamily`,
  `bulletStandInScale`, SDK, drawing only — `bulletFontFamily` and
  `bulletScale` stay the file's and are what is saved). Wingdings'
  round bullet, the commonest (46 decks), is Carlito's "●" at 1.23
  times: Carlito's is 0.46 em across with its centre 0.295 above the
  baseline, which at that scale is Wingdings' to half a point. (DejaVu's
  "●" at its size sits 4 pt low: its centre is 0.265.)

Tried and dropped: Calibri lines at the face's own 1.22 rather than
1.2 — 60810's body is 17.1 pt a line at 14 pt in PowerPoint — made 39
decks worse and 21 better (1.8667 → 1.8926). Whatever spaces 60810's
lines, it is not the face.

**A picture cropped to a freeform, 2026-10-14** (sweep 60: 1.8660 →
1.8486%; tdf140714 2.03 → 0.00, tdf153008 5.89 → 0.06, tdf156649 1.98 →
0.20). A picture's `spPr` may outline it with `a:custGeom` — tdf153008's
circle in four curves — and was drawn square. It is clipped to the
outline's filled contours now (`customPath`, as a preset's
`pictureGeometry` clips it), in both the picture and metafile paths.

**Dashed lines; hidden shapes, 2026-10-14** (sweep 61: 1.8486 →
1.8298%; 66 decks now match exactly, from 62). Two things every
outline and every shape was treated alike for:

- **`a:prstDash`** (`outlineDash`, shapes and connectors): the outline
  cut into the pattern's pieces in widths of the line, as DrawingML
  gives them — dash 4·3, dot 1·3, lgDash 8·3, dashDot 4·3·1·3 and its
  long and double kinds, sysDash 3·1, sysDot 1·1, sysDashDot 3·1·1·1,
  sysDashDotDot 3·1·1·1·1·1 (`SlidePainter.dashPattern`). Twelve decks;
  presetDashDot 3.40 → 0.00, tdf134053_dashdot 2.26 → 0.74, group-rot and
  tdf126741 to 0.00. Not yet: a table cell's dashed rules
  (tableBorderLineStyle) and `a:custDash`.
- **`cNvPr hidden="1"`**, on a shape or its group, is kept and not drawn
  (`invisible`, as a footer its layout has no place for):
  hidden_group_shape 4.88 → 0.00, tdf147586 1.37 → 1.11,
  tdf169496_hidden_graphic 0.23 → 0.03.

**Shape shadows, 2026-10-14** (sweep 62: 1.8280 → 1.8123%; twenty decks
closer — effectOrder 3.66 → 1.67, tdf125551 4.07 → 2.49, shape-blur-effect
1.25 → 0.15, 54542_cropped_bitmap 1.80 → 0.89 — customGeo +0.34 and
tdf152606 +0.07). A shape's or picture's `a:outerShdw` was not drawn;
14 decks give one directly, 8 more through their theme's effect style
(`effectRef`, Office 2007's themes shadow every shape).

- **`SlideShape.shadow`** (the SDK's `CharShadow`), read from the
  shape's own effect list or, with none, its style's theme effect with
  the referred colour as `phClr` (`PptxTheme.effectStyles`); one cast
  on the ground (scaled or skewed) is left out, as for text.
- **Drawn as the outline's blurred copy** (a mask-filter blur of half
  the blur radius — which, unlike a text shadow's, reaches PDF where it
  belongs), offset on the page whatever the shape's turn, faded with a
  translucent plain fill.
- **Not under a picture fill**: its shadow is of what the picture
  paints (tdf128596's ticks on nothing went 3 → 29 with the outline's).

Left: inner shadows, and shadows of shapes with no fill (PowerPoint
shadows their text or line).

**Glow and soft edges, 2026-10-14** (sweep 63: 1.8123 → 1.7971%;
shape-soft-edges 3.71 → 0.04, shape-glow-effect 0.64 → 0.01,
shape-text-glow-effect 3.79 → 0.76, effectOrder 1.67 → 0.37;
tdf141058-1 +0.27). A shape's `a:glow` is its outline stroked at the
glow's radius and filled, blurred by a quarter of the radius, behind
it; `a:softEdge` draws the shape in a layer of its own and cuts the
band inside its outline away with a blurred stroke (`dstOut`) twice the
radius wide, blurred by 0.4 of it — measured on shape-soft-edges, whose
fade PowerPoint has half gone 0.73 of the radius in and spread over
0.9 of it; this matches it to a few levels. A run's glow is not drawn:
blurred text reaches PDF as the misplaced soft mask text shadows hit.

**A monochrome chart style, 2026-10-14** (aascu cooper 7.11 → 5.78; no
other chart deck moved). Office 2007's chart styles (`c:style` 1–48)
are eight columns of colour by six rows of effects: greys, the accents,
then accent 1 to 6 each in shades of itself. The cooper deck's stacked
columns are style 12 — accent 2's column — and were drawn in the
accent cycle (orange, maroon, white, black). Measured there: its four
series are accent 2 shaded in linear light to 0.58 and 0.85 and tinted
to 0.86 and 0.575, which is 1 − 0.56 × each series' place out from the
middle (−¾, −¼, ¼, ¾) to a level per channel (`Chart.monochrome`; a
pie's slices likewise). A monochrome style is kept and written back,
its series without a fill of their own; any other style is dropped as
before.

Tried and dropped: tints in sRGB where a `satMod` follows (customGeo's
satMod 300% gradient is sRGB's to a level, its plain table bands are
linear light's) — made 13 decks worse, themes 2.59 → 18.28. How
PowerPoint combines a tint with a saturation boost is still open.

**An unbulleted paragraph's own first-line indent, 2026-10-14** (sweep
64: 1.7942 → 1.7875%; eleven decks closer — n778859 2.16 → 0.87,
ecodesign 4.15 → 3.55, testPPT 2.36 → 1.82, the 45541 trio −0.24 — none
further). The layout's `firstLineIndent` answered only under Word's
rules, so a Slides paragraph with no bullet ignored its own indent: a
master that hangs every body level (marL 27, indent −27 pt) and a
paragraph that turns its bullet off (`buNone`) left the first line at
27 where PowerPoint starts it at 0. It is the paragraph's own now,
outside tables. A picture bullet (`a:buBlip`, seven decks) is read as a
bullet whose marker is not drawn yet, so its text stays where a list's
is (tdf90626 and tdf138148 hung out to the left without that).

**Vertical text in shapes, 2026-10-14** (tdf128684 1.95 → 0.44,
vert_and_padding 3.02 → 1.99, eaVertAnchor 4.05 → 3.28, shape-text-rotate
0.06 → 0.01, vert270AndTextRot −0.03; six decks, none further). A
body's `vert` (`vert`, `eaVert`, `mongolianVert` a quarter clockwise;
`vert270` anticlockwise) was ignored and the text laid out across. It is
laid out in the frame turned a quarter — width and height swapped, the
insets turned with it — and drawn turned back (`SlideShape.textTurn`).
Drawing only: the editor still edits it across, and East Asian
characters are turned with the Latin ones rather than stood upright as
`eaVert` stands them.

**No space after a body's last paragraph, in points too, 2026-10-14**
(sweep 65: 1.7783 → 1.7703%; bnc904423 3.59 → 1.39, ShapeLineProperties
3.45 → 1.88, tdf169825_vertical_layouts 0.99 → 0.47, customGeo −0.09;
none further). A percentage after was already left off a body's last
paragraph; one in points was not, and a master giving every body
paragraph 11.5 pt after lifted a centred box's text by half of it.

Also looked at and left: the 1.08/1.22 line pitches of lo-tdf169524
and 60810 (see above).

**A bullet with no hang, 2026-10-14** (sweep 66: 1.7530 → 1.7502%;
ececapstonespring2012 3.57 → 1.99, nothing else moved). That deck, an
export with no default text style, says no `marL` or `indent` anywhere:
PowerPoint then puts a level half an inch in and hangs nothing — the
bullet at the edge, the text straight after it ("•Down Syndrome", the
D 9.7 pt right of the bullet). The reader gives such a level those
margins, and the layout (`markersAtHang`) sets a bullet whose hang is
at or past its text at the first line's start with the first line led
by the bullet's width; both now land within 0.1 pt of PowerPoint's.

**Picture bullets, 2026-10-14** (tdf90626 0.59 → 0.54, tdf114913 0.15 →
0.12, tdf138148 0.06 → 0.04; seven decks have them, the others' slides
show none). `a:buBlip` is resolved from the part each level comes from
(slide, layout, master — `LevelStyle.bulletPicture`), carried on the
paragraph (`RichParagraphStyle.bulletPicture`, SDK) behind an empty
marker, and drawn by the slide in the marker's place, preloaded for
export like any picture. Its size, measured: 0.714 of the bullet's —
the first run's size times `buSzPct` — so 28 pt text has a 20 pt
picture, and tdf90626's 47% of 32 pt and 151% of 10 pt are both
10.7 pt; its foot on the baseline.

**A layout's turned group is drawn, 2026-10-14** (sweep 67: 1.7500 →
1.7474%; tdf149865 2.43 → 1.32, themes 2.59 → 2.33, alterman −0.06).
A master's or layout's own shapes behind a slide left out every object
kept whole — a group turned or mirrored, a diagram — as if it could not
be drawn; those drawn from their members (`rendering`) are drawn now.
tdf149865's coloured stripe across the top is a group turned a quarter.

**A bullet is never underlined, 2026-10-14** (sweep 68: Maloney 8.23 →
8.22; nothing else moves). A Slides bullet took its first run's whole
style, so the "•" before Maloney's underlined theory names was drawn
with a line under it; PowerPoint takes the run's face, size and colour
only. Its underline, strike, highlight and link are dropped now. (The
same deck's one wrap that differs, "it's more", is Verdana against
DejaVu Sans, a point short at the edge.)

**Webdings' disc and square in a metafile, 2026-10-14** (sweep 69:
1.7474 → 1.7468%; 45545_Comment 6.89 → 6.78, both 45541 decks 6.92 →
6.81). The three decks share a slide whose picture is a WMF grid of
Webdings "n" and "g". We drew them as "●" and "■" in a stand-in face,
under half an em across; Webdings' are a whole em. Measured on
PowerPoint's print: 1.0 em wide, 1.06 em apart, centred 0.29 em above
the baseline. A run of only those two, set on its baseline from the
left, is drawn as discs and squares of that size now.

**A tint before a strong saturation boost mixes in sRGB, 2026-10-14**
(sweep 70: 1.7468 → 1.7451%; customGeo 7.57 → 7.12, tdf114848 8.01 →
7.73, backgrounds 2.03 → 1.83; nothing worse). The Office 2007 themes'
gradient fills are `tint 50% satMod 300%` and the like. customGeo's
orange diagram boxes measure (255, 200, 154) at the deep end in
PowerPoint's print; the sRGB tint then the boost gives (255, 202, 159),
the linear-light tint (255, 208, 188). The rule is narrow, each part
paid for by a deck the broad one made worse:
- the boost must come **straight after** the tint (subtitle-animation's
  background, `tint hueMod satMod lumMod`, is linear light's);
- it must be **155% or more** (GeomLec1's and aascu's blue bands, tint
  86% satMod 149%, are linear light's: +0.83 and +0.31 with every
  boost);
- the colour must not be **grey** (tdf94238's black glow and GeomLec1's
  grey backgrounds; a boost leaves a grey grey);
- and not a picture's **duotone** (Treck's background in themes, tint
  95% satMod 120%).
The earlier attempt that made themes 18.28 had none of these.
What PowerPoint actually does is still unknown; this is a fit.

**A master with no text styles, 2026-10-14** (sweep 71: 1.7451 →
1.7446%; tdf148685 0.58 → 0.45, tdf169524 7.34 → 7.23,
subtitle-animation-save 0.70 → 0.67; nothing worse). Masters written by
other programs can leave out `p:txStyles`; we then set every
placeholder at 18 pt. PowerPoint keeps its own: a title at 44 pt in the
heading face, a body or subtitle at 28 pt with an Arial "•", both at 90%
line spacing and the body 10 pt before each paragraph — the PDF's lines
are those to a tenth of a point. A content placeholder (`p:ph` with no
type) takes the same but no bullet (outliner-list-style's first level
has none).

**Pattern fills, 2026-10-15** (sweep 72: 1.7446 → 1.7353%; tdf107608
5.08 → 0.07). `a:pattFill` was not read, so a shape fell through to its
style's colour. PowerPoint's export draws a pattern as a PDF tiling
pattern: one pattern pixel a point, the grid laid from the slide's
corner, not the shape's, and square to the slide even when the shape
is turned (tdf107608's rectangle is turned 270° and its stripes still
run down to the right). `Slides/PatternFill.swift` holds the 48
presets as 8×8 bitmaps (GDI+'s hatch brushes, which the presets name;
ltDnDiag checked against the print, the rest not seen in the corpus)
and draws one as a tiled BMP, eight pixels to the pattern pixel, with
`SlideFill.tileAnchored`; `paintFill` undoes the shape's turn for it.
The blend of the two colours by share stands for the fill wherever a
single colour is wanted. (The other moves in this sweep — table decks
±0.1 — come from the Writer session's shared table changes, not this.)

**Medium Style 2 in every colour, 2026-10-15** (sweep 73: 1.7353 →
1.7284%; predefined-table-style 3.83 → 0.57, tdf149785 3.04 → 2.53;
nothing worse). A table that names a built-in style its deck does not
define was drawn in a guess: Medium Style 2 in the first accent. The
style's seven colourings (dk1 and the six accents) are built in now
(`PptxTemplates.mediumStyle2`, by their ids), so predefined-table-style's
`{073A0DAA…}` comes out black and grey as PowerPoint draws it, and the
first-accent one follows the style itself (tdf149785's emphasised
edges). Other built-in families (Light, Medium 1/3/4, Dark, Themed) are
still the guess.

**Aslant category labels, 2026-10-15** (aascu 5864 9.84 → 9.80; its
census and OECD charts 16.5 → 15.5 a page). A column chart's category
labels that did not fit their slot were wrapped, and a word wider than
the slot broken inside itself ("Mexi / co"). The axis's `c:txPr/a:bodyPr
rot` is read now (`Chart.categoryLabelTurn`; -60000000 is the charts'
"automatic" and reads as none): a turn sets the labels aslant, each
ending at its tick and running down to the left, the plot raised by
their drop. With no turn given they are set at 45° when a single word
of one is wider than its slot, as PowerPoint does.

**A chart's outlines and axis colours, 2026-10-15** (aascu 5864 9.80 →
9.48; tdf149985 +0.04, its light grey outline half a pixel off). Read
and drawn now: a bar's or column's outline (`ser/spPr/a:ln`), the plot
area's border (`plotArea/spPr/a:ln`), the axes' label colours and the
value labels' weight (`c:txPr`), and gridlines in a colour of their own
(not the standard `tx1` at 15%, which is our default look and what a
save writes, so a written chart reads back as it was).

**3-D pies, 2026-10-15** (LIBRE_OFFICE-100610-0 5.20 → 3.13; its worst
page 18.7 → 11.4). A `c:pie3DChart` was drawn as a flat circle in a
grey square. It is a tilted disc now (`Chart.pieTilt`, from
`c:view3D/c:rotX`), measured from PowerPoint's print at 30°: the disc
0.473 as tall as it is wide (sin 30° × 0.946, the perspective's share),
the rim 0.228 of the radius deep, the whole filling 94% of the plot's
width or 97% of its height, the plot 7% and 8.5% inside the room left
by title and legend, and the rim the slice's colour × (0.575 + 0.3 |cos
θ|) — 0.575 at the front, 0.875 at the sides.

**3-D bars, and a bar chart's legend, 2026-10-15** (LIBRE_OFFICE-100610-0
3.13 → 2.94, aascu 5864 −0.03). A `c:bar3DChart` draws each bar as a
box (`Chart.barView`, from `c:view3D` rotX/rotY): its depth is the bar's
own thickness, shown up by sin(rotX) and right by sin(rotY) of it (15°
and 20° in PowerPoint's print: 12 and 16 pt on a 46.5 pt bar), the top
0.757 of the colour and the side 0.64, with the plot made that much
smaller so the boxes stay inside. A horizontal bar chart's legend lists
its series last first, at any side, as its bars run. Left: the walls
and floor behind 3-D bars, and the value axis's auto steps (aascu's
census chart is 0–90 by 10 in PowerPoint, ours 0–100 by 20).

**An Office 2007 embedded object's picture, 2026-10-15** (tdf169781
4.02 → 1.62). An embedded Excel chart with no `p:pic` fallback shows
the picture its legacy VML drawing names; we looked for that drawing
under the relationship `vmlDrawing` only, and Office 2007 names it
`legacyDrawing` (in its own namespace). Both are read now, and both
are carried on a save.

**A picture's brightness, contrast and black-and-white, 2026-10-15**
(tdf79007 1.43 → 0.20, tdf89928 1.74 → 0.86). `a:lum` and `a:biLevel`
on a picture or picture fill were not read. They are a colour matrix
now (`PptxReader.blipLevels`, applied with any duotone after it), fitted
to PowerPoint's print: contrast c scales about the middle by 1 + c
(1 / (1 − c) above nought), then brightness b blends toward white by b
— Washout (70%, −70%) takes black to 205 — and black-and-white turns a
pixel whose luminance is under the threshold black and the rest white
(a 74% grey under a 75% threshold black, a 76% one white).

**A broken archive's later entries, 2026-10-15** (the fuzzer's deck
4986… 95.89 → 28.97). A file with no central directory was salvaged
from its local headers front to back, stopping at the first entry that
would not read; that deck has 77 entries, some with damaged names or
streams, and stopped after one slide. The scan now skips a bad entry
and goes on at the next local header, an entry whose size only a data
descriptor gives running to the next header; an entry cut short by the
end of the file is still lost. 19 of PowerPoint's 23 slides come back
(the others' names are scrambled — `ppp/slides/slide10.xml`). Shared:
documents and workbooks salvage the same way. Left: 5611…'s diagram,
whose frame lost its `a:ext` to the fuzzer and which PowerPoint still
draws. (2026-10-18: its drawing's five shapes have all lost their
`a:xfrm` too — `a:xdrm` — and PowerPoint's 2×2 boxes match neither the
drawing nor the frame's 640 pt width, so it laid the diagram out afresh
at a size not recoverable from this file; reading a sizeless frame from
its offset alone changed nothing, and was taken back.)

**Tab stops, 2026-10-15** (sweep 75: 1.5945 → 1.5937%; eight decks
closer — tdf120028 −0.13, n778859 −0.12, HowWeRefactor −0.05 — none
further). A tab in slide text was the engine's own: no stops at all.
The reader takes `a:tabLst` (left, centre, right, decimal) and
`defTabSz` (an inch unless a level says otherwise) now, and the layout
sets tabs as it does Word's: the paragraph's own stops, the hanging
indent first, then the default stops — all measured from the text's
left edge. PowerPoint's print of HowWeRefactor's quotes, to a tenth of
a point: the first line's tab to the indent (70.1), "bursts. ⇥⇥– Martin
Fowler" at the sixth and seventh inch (475.2, 547.2). Two things
Slides-only in the layout: a tab on a line the paragraph wraps onto is
measured from that line's start, the lines found by laying the
paragraph out with the tabs so far until they stop moving (the probe is
one long line, and a third line's tab had been placed as if it ended
the first); and a paragraph that opens with a tab puts the tab's
widening into the first line's indent box, since the engine sets
added spacing half before a character and at a line's start that moved
the line (10.8 pt).

**A freeform in a turned or mirrored group, 2026-10-15** (sweep 76:
1.5937 → 1.5906%; tdf131082 1.67 → 0.15, HowWeRefactor 4.05 → 3.85).
Such a group is drawn from its members; a member kept whole hands on
what it is drawn from — right for a nested turned group, but a freeform
is kept whole and draws itself, and it handed on nothing. HowWeRefactor's
mirrored wrenches over its "R" boxes were missing. A kept member with
nothing to hand on and a freeform of its own is drawn as itself now.

**Radar charts, and a chart that colours no text, 2026-10-15** (POI's
bar, pie, line and scatter charts −0.02 to −0.06; radar-chart 1.68 →
1.99). A `c:radarChart` was kept as an undrawn object. It is a chart
type now (`ChartType.radar`, read, drawn and written): a spoke a
category from the top clockwise, a ring at each value step, the values
up the first spoke, and each series a closed line (or a filled shape,
`radarStyle filled`), its legend key a line. Its score is worse than
the empty frame's: the drawing is PowerPoint's to a few points, and a
near miss counts twice where nothing counted once. A chart whose text
has no colour at all (`Chart.plainText`, POI's 2007-style charts) is
set in the theme's text colour — black in PowerPoint's print — where
ours were all 65% grey; a chart that says the standard grey (a new
one, PowerPoint 2013's) keeps it, and the legend's own colour is read.
Tried and dropped: PowerPoint's mid grey (#868686) for gridlines that
say nothing — radar +0.77, scatter +0.95: ours are a little off its
lines, and a darker miss costs more.

Tried and dropped, 2026-10-15: vertical-box-list (list1) in PowerPoint
keeps its natural height, centred in the frame — parentText 0.82 of the
font size in mm, the child box 0.7, the overlap −0.41 — where we fill
the frame. Growing only children with an INF *rule*, not an INF
*constraint*, made it 5.88 → 11.11 and linear-rule-vert +0.43: the
negative space's `op="lte"` caps (−0.82 × the parent box) are what
PowerPoint does not follow, and they are the thing to look at.

**A custom dash, 2026-10-15** (slide-section-test 0.14 → 0.13). A
line's `a:custDash` — its stops in thousandths of a percent of the
line's width — was drawn solid; it is a dash of its own now
("cust:2.99,1.01", on and off by turns, in widths).

**Dashed table borders, 2026-10-15** (tableBorderLineStyle 2.65 →
2.39, tdt142291 0.41 → 0.27). A cell edge's `a:prstDash` (or custom
dash) was drawn solid. `CellRef.CellLine` carries a dash now (shared
SDK, additive: nil is solid, as every Word border is), and the layout
draws the edge in its pieces from its start.

Sweep 77, 2026-10-15 (1.5902 → 1.5892%): no Slides change — the
Writer session's shared commits since sweep 76 (fonts, tables) moved
seventeen decks, tdf140852 −0.25 and tdf98603 −0.22 the most, none more
than +0.09 the other way.

Tried and dropped: the themes deck's centred radial background is, in
PowerPoint's print, the stops at t² of the way out (251, 246, 234, 211,
181 at t = 0, 0.2 … 0.8 — ours an even ramp, 30 levels dark half way).
Taking t² for every path gradient of theme colours made GeomLec1 +5.07,
tdf94238 +3.69 and tdf114848 +2.34 and did not register on themes'
score. What sets the curve is not known.

**A diagram point's own effects, 2026-10-15** (fill-color-list 1.41 →
0.07). A SmartArt laid out here took a point's own fill and line from
its `dgm:spPr` but not its `a:effectLst`; fill-color-list's headings
each carry a shadow there, which PowerPoint draws. The effects go into
the shape now, and the shape's shadow is drawn as any other's.

**Columns with a line over them, 2026-10-15** (aascu 5864 9.46 → 9.20;
its OECD chart 16.7 → 7.8 a page). A plot area of a `c:barChart` and a
`c:lineChart` on the same axes was a combination this app kept undrawn.
It is one chart now: the columns as before, and the line chart's series
(`Chart.lineSeries`) drawn over them through their categories' middles
on the one value axis, each with its marks (`c:marker` symbol, size and
colours; a point whose marker says none shows none) and its line unless
that is `noFill` — aascu's 1995 rates, red dots over the 2005 columns.
They are in the legend after the columns, keyed by their mark; a chart
with them never takes a series name as its title; and a save writes
them back as a line chart on the same axes. Also read: a legend's own
place (`c:legend/c:layout/c:manualLayout`, `Chart.legendBox`), its
entries in a row there and the plot's room untouched. Other
combinations (a line on a secondary axis, areas with lines) are still
kept undrawn.

**A rectangle's path gradient, and a slide shaded to its title,
2026-10-15** (sweep 78: 1.5863 → 1.5812%; tdf114848 7.73 → 4.90, its
worst page 18.4 → 10.4). A `path="rect"` gradient (and `"shape"`,
taken as its box) was drawn as a squeezed circle. It is rectangles now,
from the fill-to rectangle out to the area's edges, each the colour
that far along (96 steps, drawn outside in). And a slide background
`shadeToTitle="1"` with a path gradient runs out from the title's box:
tdf114848's is light along the whole title and darker toward every
edge, where ours had a circle round the middle.

**A 2007 chart's 10 pt text, 2026-10-15** (LIBRE_OFFICE-100610-0 −0.08,
aascu 5864 −0.04, cooper +0.03). A chart that states no text size and
no text colour anywhere — none of PowerPoint 2013's grey (`tx1`
lumMod 65%) in any of its text — sets its labels and legend at 10 pt
in PowerPoint's print (aascu's children's-skills charts); ours were 12,
and the wider labels tipped into the aslant rule where PowerPoint's
stand level. `Chart.baseTextSize`; a 2013-style chart (and a new one)
keeps 12. The legend's bold (`c:legend/c:txPr`) is read too.

**A theme line style's width, 2026-10-15** (sweep 79: 1.5811 →
1.5549%; 61 decks closer — tdf127964 0.89 → 0.00, tdf114848 −0.88,
group −0.79, backgrounds −0.68, the connector decks −0.6, customGeo
−0.58, aascu 5864 −0.42 — five 3-D decks +0.02 to +0.11). A shape whose
style refers to a line style (`p:style/a:lnRef idx`) and whose own line
names no width was drawn ¾ pt wide whatever the theme said. It takes
that line style's width now (`PptxTheme.lineWidths`, from
`a:lnStyleLst`): ¾, 2 and 3 pt in an Office 2007 theme, ½, 1 and 1½ in
a 2013 one — aascu's ovals' 2 pt red rims, every default connector's
1 pt.

**Arial Black, 2026-10-15** (WordArtBitmapFill 20.70 → 16.83,
ThemeColorTransparency 12.50 → 8.83, placeholder-layout-color −0.37,
themes −0.26, SampleShow −0.17; Wordart3D +0.44). No face shipped here
is Arial Black, and its runs were set in the plain sans — light and
narrow, "TRADE SHOW" on one line where PowerPoint breaks it. Slides now
set it in Arial's bold, 0.07 em further apart a letter: Arial Black's
measure in PowerPoint's prints (1.10 to 1.16 of the bold's, median
1.12, on the four lines the corpus prints in it). Slides-only (the
reader's run style), the shared font table untouched.

**A table style's rules side by side, 2026-10-15** (sweep 80: 1.5406 →
1.5301%; 22 decks closer — bug68703 2.71 → 1.50, tdf149865 −0.57,
bnc480256 −0.51, bnc887225 −0.49 — bnc910045 +0.11). A deck's table
style's whole-table rules (`a:wholeTbl/a:tcStyle/a:tcBdr`) were read as
one switch and a colour: any side ruled was every side ruled, at the
default width. Each of the six sides is its own now (`TableStyle.edges`:
a side the style leaves out or sets `noFill` has no rule) and the rules
are the width the style gives (`borderWidth`). Tried with it and
dropped: `{793D81CF…}` (tdf135843_insideH's undefined style) built in as
rows ruled and columns not — +1.85 there, its rows still the wrong
height; that deck stays undrawn-ruled.

**Line spacing over single, 2026-10-15** (sweep 81: 1.5301 →
1.5267%; tdf137367 −0.80, bug68703 −0.33, tdf51340 −0.26,
TextFittingStored −0.14, 60810 −0.07, none further). The rule that
PowerPoint takes all of a spacing's change above the line held for
spacing under single (the masters' 90%) and was applied over single
too, where it does not: at 150% PowerPoint puts 0.70 of the extra above
tdf137367's first 40 pt line and 0.72 above bug68703's 11 pt cells —
the engine's own proportional share (0.75) — and ours stood 7.3 and
1.9 pt low. `baselineShift` is nought over single now (shared SDK,
Slides-only path: Word's is nought already).

**A diagram's text that must fit a capped box, 2026-10-15**
(accent-process 9.35 → 2.29; no other diagram deck moves). process3's
heading box is held to 0.4 of its width (`h` ≤ 0.4 `w`, its own), and
its text must fit in it: PowerPoint sets "a" at 33 pt there — 1.2 ×
33 for the line and 0.56 and 0.3 of it for the margins come to the
68 pt the cap leaves — and every box sized in font sizes (the shape at
1.2, the child at 1.6) follows; we kept 55 pt, the boxes a third too
tall. The layout's fit now counts such a box squeezed when its lines
and margins at the font size (or the size its text states) do not fit
— only for a height capped by the box's own width: a cap from a user
variable (linear-rule's hProcess3) PowerPoint lets the text outgrow,
and with every cap counted that deck went +2.87.

**An empty row takes no room, 2026-10-15** (smartart-children 6.92 →
3.42; no other diagram deck moves). hierarchy4 hangs a row (`lin`) of
children under every node, empty under a leaf. Measured, an empty
container counted as the whole height offered, so a node's column
asked for its box plus a frame's height of nothing, and the boxes
above came out a third of PowerPoint's. A `lin` with no children and
no shape measures nought now.
Left: its widths. PowerPoint's columns are as wide as their row of
children — boxes 110 pt, gaps 9 and 19, its heading 227 over the row,
which is the layout's widths (480 each, spaces 0.168 and half that)
with each heading at least its row (`txOne w ≥ horzOne w`, `op="gte"`)
scaled into the frame. Letting a frame-sized row measure its contents
gets 0.75 there and breaks linear-rule, continuous-block-process and
table-list (+14 to +25): the `gte` has to be met where the engine
measures, not in general.

**An empty paragraph's spacing by its end mark, 2026-10-15** (sweep 82:
1.5076 → 1.5053%; 60810 −0.60, alterman −0.49, ecodesign −0.13;
GeomLec1 +0.03). A percentage of spacing before or after is of the
paragraph's own text size, and an empty paragraph has only its end
mark (`a:endParaRPr sz`) to say it; we took the level's instead, so
alterman's 24 pt blank lines under a 28 pt level were 1.3 pt taller a
gap each, and the slide drifted down by its paragraphs.

**No space before a content placeholder's paragraphs, 2026-10-15**
(tdf169524 7.23 → 3.43). The built-in style for a master with no text
styles (above, 2026-10-14) gave a content placeholder's first level
the body's 10 pt before each paragraph. tdf169524's "line pitch
mystery" was that: every first-level paragraph 10 pt further down than
PowerPoint's print, which has none. Taken out for the content style;
the subtitle's has one paragraph and says nothing either way.

Tried and dropped, 2026-10-15: a blurred text shadow drawn as the
paragraph's text again, in the shadow's colour through a blurred layer
(the 45541 trio, every line shadowed 3 pt down-right, blur 3 pt). Skia's
PDF output rasterises each such layer — the three decks' PDFs went to
2.8 MB — and at sigma = blur / 2 the shadow came out wider and darker
than PowerPoint's tight one: 6.78 → 8.53. The sharp 45% copy stays.

Tried and dropped, 2026-10-15: names the shared font table does not
know go to Cambria's measure (Word's rule); a Slides-side resolver sent
plainly sans names (Work Sans, Poppins, Montserrat, "… Sans") to
Liberation Sans instead. Mean +0.0004: tdf148665 −0.12 but tdf140852
+0.19 and HowWeRefactor +0.10 — Work Sans Light is narrower than
Arial's measure, and the lines re-wrapped. No better stand-in without
a face of that width.

**Percent spacing under PowerPoint's own shrink, 2026-10-15** (sweep
83: 1.4984 → 1.4962%; bug62513 −0.74, testPPT −0.33, aptia −0.26;
aascu 5864 +0.11). A body that PowerPoint shrank to fit
(`normAutofit fontScale`) has its percentage spacing of the text as
drawn: bug62513's 20% before its 77.5% list items is 6.0 pt in the
print, ours 7.7 from the full size. The stored scale multiplies it now
(before and after). aascu's page 17 has its gaps exactly PowerPoint's
(36.0) and scores worse: its first line is 1.2 pt high, which the
too-wide gaps had been making up for.

**A placeholder drawn as a preset of its own, 2026-10-15** (customGeo
6.49 → 6.11, its oval page 22.3 → 3.9; tdf162283 2.21 → 0.09,
tdf157019_objPlaceholderCustomShape 0.94 → 0.53; the five decks with
one, none worse). Only a placeholder's inherited preset was read; one
the slide gives it (`prstGeom prst="ellipse"` on a content
placeholder) was drawn as a rectangle with its text across the frame.
It is drawn as the preset now, its text in the preset's text rectangle.

**A shape's style names its face, 2026-10-15** (sweep 84: 1.4909 →
1.4886%; customGeo 6.11 → 4.88, AES −0.04, linear-rule-vert −0.02;
none worse). A drawn shape's `fontRef idx="minor"` was read for its
colour only, so its text took the deck's default face — Arial in
customGeo, whose boxes PowerPoint sets in Calibri. The style's face now
ranks as its colour does: over the layout, master and deck defaults,
under the shape's own list style and paragraph.

**A shadow in the shape's own outline, 2026-10-15** (sweep 85: 1.4886
→ 1.4872%; customGeo 4.88 → 4.28, tdf125551 −0.08, four more a little;
none worse). Shadows, glows and soft edges took their outline from the
preset's name, at its default adjust values: customGeo's three pie
slices each cast a three-quarter pie, a grey slab over the chart. They
take the evaluated path now (its filled parts as one, so a can's lid
does not cut a hole in it).

**Linked text, 2026-10-15** (the 21 decks with a link: tdf148966 2.23
→ 1.83, customGeo −0.04, eight more a little; tdf137367 +0.30, its
three links now coloured and underlined as PowerPoint draws them,
the underline a pixel off). A run with `hlinkClick` was drawn as plain
text; it is underlined now, in the theme's `hlink` colour unless the
link keeps the text's own (`ahyp:hlinkClr val="tx"`).

**PowerPoint's light rigs, measured, 2026-10-15** (the extruded decks:
lightRig_default 12.31 → 1.35, dir_rotation 7.44 → 1.18,
material_highlight 13.94 → 8.58, perspectiveContrastingLeft 6.77 →
2.07, rot_rotation −2.92, shape_rotation −2.11, obliqueTopRight
−1.82, isometricRightUp −1.54, modernCamera −0.81; none worse; 36
points over nine decks). An extruded solid was shaded by one made-up
light in the viewer's frame. A probe (each face painted in an id
colour, PowerPoint's page sampled under it) showed the rigs light the
shape in its OWN frame — a face is as bright whatever the camera
(threePt's front 1.00–1.13 from four cameras) — and gave each rig's
numbers: threePt (the default) turned right 0.12 of the colour, up
and right 0.30, up 0.74, left 0.69, front 1.04; harsh left 1.51, top
0.80, front 0.83, and with `dir="r"` top 1.51 and left 0.86 — a second
light from below turned round. Those are now an ambient share plus two
lights per rig, turned by `dir`; other rigs use threePt, the legacy
cameras keep the old shading, and a solid seen from behind its old dark
back. Not modelled: `lightRig rot` (rot_rotation's front is 0.45 in
PowerPoint), materials' highlights, bevels.

Tried and dropped: **fitting `normAutofit` text with no stored scale
when the deck opens** (tdf98603's 72 pt Hebrew title, one smaller line
in PowerPoint's print, two here). Mean 1.4207 → 1.4292: tdf98603 −0.86,
but aptia +0.78, NumberedList +0.69, smartart-background +1.51 and a
dozen more — PowerPoint leaves aptia's eight-item list overflowing its
box rather than shrinking it, so it does not refit on open, and what
shrank tdf98603's title is something else (its Hebrew face's size?).
Also tried: `lightRig rot` as a turn of the rig's lights — no order or
sign of lat/lon gives rot_rotation's left 1.51, top and front 0.45
from the two lights as fitted.

**A line of no width is no line, 2026-10-15** (vert_and_padding 1.99
→ 1.39, ThemeColorTransparency 8.83 → 8.49, trailing-paragraphs 0.09
→ 0.03; the eight decks with one, none worse). `a:ln w="0"` with a
colour — LibreOffice's hairline — was drawn a pixel wide; PowerPoint
draws nothing.

**A group whose child space has no width, 2026-10-15** (tdf136830 3.22
→ 0.05; the only deck with one). `chExt cx="0"` was kept whole and
drawn as nothing. PowerPoint's print keeps the members' own widths,
placed from the group's corner, and scales only the other way (1.159,
the heights' ratio); that is the mapping now.

**A chart's own face, 2026-10-15** (LIBRE_OFFICE-100610 2.86 → 2.77;
the chart decks otherwise unchanged). Chart text was always in the
theme's body face; LIBRE_OFFICE-100610's charts name Calibri (title,
and the chart's text) in an Arial theme, and PowerPoint sets them in
Calibri. A face the chart names — `c:chartSpace/c:txPr`, the title's
runs — is used now; a theme slot (`+mn-lt`) still means the theme's.

**A table span with nothing to span, 2026-10-15** (LIBRE_OFFICE-100610
2.77 → 2.67; the only such row in the corpus, the table decks
unchanged). A cell's `gridSpan="3"` with no `hMerge` cells after it
(the row two short of the grid) took three columns here; PowerPoint
keeps it to one, and "Vermelho" wraps there. A span now reaches over
the merged cells that follow it and no further. (PowerPoint also draws
the two missing cells as white boxes with black edges; not done.)

**A gradient with no direction blends evenly, 2026-10-15** (tdf104788
0.96 → 0.08, its worst page 5.76 → 0.47; the only deck with one). Its
orange-to-cream bars name no `a:lin` and no `a:path`, and PowerPoint's
print blends them in a straight line in sRGB (blue 16, 33, 51… down
the bar); plain stops otherwise get the eased linear-light blend
(tdf109067's, whose `a:lin` has no `scaled`, still does). One deck of
evidence, but the only gradient of the kind in the corpus.

**A chart's own colour map, and a bare pie's size, 2026-10-15**
(chart_pt_color_bg1 2.98 → 0.74; the other chart decks unchanged).
The chart part's `c:clrMapOvr` was ignored, so its `bg1 lumMod 85%`
slice took the slide's swapped map (bg1 dark) and drew black; it is
read over the slide's now (light grey, as printed). And a pie with no
title and no legend stands in its whole frame: PowerPoint's ring is
0.926 of the frame's half height, ours was 0.87 inside the 9 pt margin
(the only such pie in the corpus; ones with a title or legend keep the
margin).

**A picture fill casts its picture's shadow, 2026-10-15** (tdf128596
3.00 → 0.12, tdf112209 0.56 → 0.11; the four decks with a shadowed
picture fill, none worse). A shape filled with a picture had no shadow
at all (its outline's showed grey through the gaps). PowerPoint casts
the shadow of what the picture paints — tdf128596's tiled ticks each
with a soft one, which is what makes them read bold — and so does this
now: the fill drawn again through a layer tinted to the shadow's colour
and blurred, offset under the shape.

**A chart's own drawing, 2026-10-15** (tdf149985 3.57 → 1.87; aascu
5864's two unchanged, the chart decks unchanged). Shapes a chart part
carries in its `c:userShapes` drawing — tdf149985's grey oval and
"$1.4B" over its last bar — were not read. They are now: each anchor
(`relSizeAnchor` by fractions of the chart's frame, `absSizeAnchor` by
offset and size) places its shape there, drawn over the chart and
never written (the chart part keeps them).

**Numbered lists as PowerPoint counts them, 2026-10-15** (the 18 decks
with `buAutoNum`: n90255 −0.12, NumberedList-12ab-ab-34 −0.08,
tdf173712 −0.06; n83889 +0.01). Every numbered level was "1." and an
unnumbered line restarted every level: NumberedList's sub-items read
1, 2 where PowerPoint has a, b, and its outer items after them began
again at 1. PowerPoint's runs are per level — a level numbers on past
deeper items and starts again after a line at its own level or
shallower that is unnumbered or numbered another way — and each run
now is a list of its own in the document, in its scheme's format (a. /
c) / (i) …) from `startAt`; an empty paragraph neither counts nor
breaks. A save writes the scheme back (it wrote `arabicPeriod` for
every list). The shared numbering rules (Word's) are untouched.

Sweep 86, 2026-10-15: 1.3976% over the 553 decks (from 1.4984 at sweep
83 this morning), the baseline written whole again; 84 decks exact.

**Data labels in their own look, 2026-10-15** (aascu 5864 8.84 →
8.85; the chart decks otherwise unchanged). A series' labels'
`c:txPr` was read only for labels taken from cells; aascu's census
chart says 14 pt bold for its value labels, which PowerPoint shows and
we drew at the chart's 10. Read for every series (or the chart type's
`c:dLbls`) now, and the column, bar, line and scatter labels drawn in
it. The page scores the same: its axis runs 0–90 by tens in
PowerPoint's print, 0–100 by twenties here, so the bars stand lower
and the labels with them — the size-dependent step still open below.

**A value axis with no labels takes up to ten steps, 2026-10-15**
(scores unchanged). aascu's census chart deletes its value axis and
runs 0–90 by tens in PowerPoint's print (nine steps); the eight-step
rule made it 0–100 by twenties. With no labels to space, ten are
allowed now, and its bars stand at PowerPoint's heights. The only
other deleted value axes (LIBRE_OFFICE-100610's) come out the same
either way. The page still scores alike: its 3-D wall sets the bars
off to the right in PowerPoint's print, and ours stand from the plot's
left edge.

**Right-to-left WordArt, 2026-10-15** (WordArtFontText 4.83 → 4.52,
WordArtFontTheme 3.71 → 3.38; the 23 WordArt decks otherwise
unchanged). WordArt is set a letter at a time, left to right in the
order the text is stored, so tdf125085's Hebrew read backwards. A line
whose first strong letter is Hebrew or Arabic is now put in visual
order — reversed, with any stretch of Latin letters and digits in it
reading forwards. (Mirrored brackets are not swapped.)

**TIFF pictures, 2026-10-15** (ArtisticEffectSample 25.84 → 1.63;
bug65228's small TIFF unchanged). The image codec reads no TIFF, so
ArtisticEffectSample's slide-wide photograph (an uncompressed RGBA
TIFF behind its layout) was drawn as nothing. `Tiff.swift` reads a
baseline TIFF's first image — 8-bit grey, RGB or RGBA, in strips,
uncompressed, PackBits or LZW (with the horizontal predictor) — and
hands the codec its pixels as a BMP. The part is kept as it was for a
save; only the drawing changes. (JPEG XR, `.wdp`, is still undrawn:
bug65523 and tdf112633 carry one each.)

**A layout's picture-filled shapes in an export, 2026-10-15** (sweep
87: 1.3527 → 1.3521%; alterman_security −0.19, ArtisticEffectSample
−0.17; none worse). An export waits for every picture to decode first,
and listed the layout's and master's shapes' pictures but not their
picture fills (nor the members of a group drawn from its parts), so
ArtisticEffectSample's layout logo — a box filled with a PNG — came out
as nothing. Their fills are waited for now.

**A snake's short last line, centred, 2026-10-15** (smartart1 4.33 →
0.23, smartart-rightoleftblockdiagram 4.32 → 0.23; the 73 diagram decks
otherwise unchanged but picture-strip −0.01). A grid of boxes laid out
here put a short last line at the start of the row; the snake's `off`
parameter, "ctr" by default and in both decks, centres it under the
lines above, as PowerPoint draws the fifth box alone under two.

**A diagram's quarter-turned box with upright text, 2026-10-15**
(tdf145528_SmartArt_Matrix 3.36 → 2.93, smartart-rotated-text 0.72 →
0.45, n862510_2 1.56 → 1.31; the other diagram decks unchanged). A
SmartArt drawing turns a box a quarter and its text frame back
(`dsp:txXfrm rot`), and gives that frame upright: the matrix's "Writer"
(box 270°, text 90°) and "Draw". Only the half turn was understood, so
these read sideways. Such a shape is now drawn as two: its outline
turned, and its text as an upright box of its own in the frame given —
a diagram's drawing is never written, so the split costs nothing on a
save.

Found, and left: **PowerPoint for Mac's PDFs carry gradients in
"Generic RGB Linear"** (an ICC profile with Apple's primaries, not
sRGB's). aascu 5864's page 32 (74%) is a 000076 → 0000FF → 000076
band: the shading's samples are (0,0,47) … (0,0,255), linear light as
blended here, but in that space, so pure blue prints as (9, 48, 255)
through MuPDF and every pixel of the page differs from our sRGB
(0, 0, 255). The blend is right; the reference's colour space is not
one to imitate in the app's own drawing. It costs any page with a
saturated gradient a few points; pale gradients barely move.

**A damaged deck's missing slides and theme, 2026-10-15** (sweep 88:
1.3355 → 1.2897%; clusterfuzz 4986 28.96 → 3.28; Divino_Revelado
+0.30, its PowerPoint pages blank either way). Two repairs PowerPoint
makes that we did not. A slide whose part is missing from the archive
(4986 lacks four) was dropped, so every slide after it was compared
with the page before its own; it is a blank page now, as PowerPoint
shows it. And a master whose theme part is missing read as no colours
at all — the deck's grey and orange boxes drew as nothing; it is
PowerPoint's own Office theme now (accent 3 A5A5A5, accent 2 ED7D31,
line widths ½, 1, 1½ pt).

**A shape's fills before its outlines, 2026-10-15** (sweep 88 again:
1.28966 → 1.28940%; lo-cshapes 2.52 → 2.39, numfmt −0.01; none worse).
A shape of several paths was filled and stroked path by path; lo-cshapes'
chartStar, chartPlus and chartX list their lines before the box they
lie on, and PowerPoint shows the lines over the box. Every path is
filled first now, then every outline drawn. (Its accentCallout1, which
PowerPoint leaves out altogether, is still drawn here.)

**A header cell two rows tall keeps its fill, 2026-10-15** (tdf149785
2.43 → 1.38; the other table decks unchanged). Its "Key Functions"
spans the header row and the one under it; it took no fill of its own
(the header's is the row's), and the second row's band, painted after
it across the whole row, covered it. The reader gives such a cell the
header's fill as its own, and the row shading (shared layout, so
Word's merged cells too) leaves a gap for any cell from a row above
that spans down into the row with a fill of its own.

**A hierarchy's parent over its children, 2026-10-15**
(smartart-org-chart2 3.02 → 1.28, smartart-recursion 2.42 → 0.69; the
other diagram decks unchanged). A parent was centred over the width of
everything below it; `hierRoot`'s `hierAlign` is "tCtrCh" by default —
centred over its children — and PowerPoint puts recursion's A midway
between B1 and B2, though B1 has two under it and B2 one. The shape now
stands between its first and last child's own boxes (side-by-side
children; "tCtrDes" and the stacked kinds keep the old centring).

Tried and dropped: **a cycle's connectors spanning the gap
(`connDist`)** — each arrow from one box's edge to the next's less its
10% pads, all as long as the shortest where the layout says `connDist`
op="equ", as thick as half that. multidirectional's arrows are that in
PowerPoint's print (all 78 px, the bottom gap's 0.8), but ours came out
too close to the top box (its ring sits 4 pt off PowerPoint's), +0.45;
and smartart-cycle's arrows, which PowerPoint keeps small and equal,
grew where its gaps are wide, +0.19.

**Nine steps up the page, eight across, 2026-10-15** (line-chart 3.07
→ 2.65, scatter-chart 2.32 → 2.00; the chart decks otherwise
unchanged). The same data, 8.2 at most, runs 0 to 9 by ones up
line-chart's and scatter-chart's value axes in PowerPoint's print and
0 to 10 by twos across bar-chart's. An axis up the page now takes up to
nine steps (every earlier case fits: 200s to 1,600, 100s to 600, ones
to 6, twos to 10 where ones would be ten); one across the page (a bar
chart's, a scatter's x) keeps to eight; radar's rings stay at eight.
This replaces the deleted-axis rule of ten (aascu's 0–90 by tens is
nine).

**A symbol face's private-range codes in text, 2026-10-15** (sweep 89:
1.27989 → 1.27940%; tdf106638 0.83 → 0.55, its Wingdings tick; numfmt
+0.01, noise). A run in Symbol or Wingdings (by `a:sym`, or its own
face) spells its glyphs in U+F020–F0FF, which no shipped face draws:
GeomLec1's "x=y ⇒ x+z" had a gap for its U+F0DE. Such codes now show as
the glyphs they stand for, by the table the metafile reader already
had — Symbol's now with the arrows (⇒ ⇔ ⇐ ⇑ ⇓ ↔), set and logic signs
(∈ ∉ ∩ ∪ ⊂ ⊆ ⊃ ⊇ ∀ ∃ ∇ ∂ ¬ ∧ ∨ ≡ ∝ ⊥ ∠ ∫) and the rest of the Greek.

**A pie is 0.97 of its room, 2026-10-15** (pie-chart 2.85 → 1.78;
chart_pt_color_bg1 0.74 → 0.76; the chart decks otherwise unchanged).
pie-chart's pie, under its title and beside its legend, is 131 pt in
PowerPoint's print where ours was 124 (0.92 of the room inside the
chart's 9 pt margin). 0.97 of that room fits it and the bare doughnut
both (159 pt there, which had needed a rule of its own: no margin when
there is no title and no legend); that rule is gone.

Tried again and dropped: #868686 gridlines for 2007-style charts, now
that line- and scatter-chart's steps are PowerPoint's (0–9 by ones).
Still worse — scatter +0.68, radar +0.46, line +0.21, bar +0.16: the
lines sit a pixel off PowerPoint's, and the darker the line the more
the miss costs. Their placement first.

**Outward tick marks, and a 2007 chart's margin, 2026-10-15**
(line-chart 2.65 → 2.04, bar-chart 2.75 → 2.34, pie-chart 1.78 → 1.45,
chart_pt_color_bg1 0.76 → 0.62, scatter-chart 2.00 → 1.87; aascu
cooper +0.14). Where an axis's `c:majorTickMark` is "out" (or
"cross"), PowerPoint's labels stand further off it: 5.6 pt more beside
a vertical chart's value axis, 8.8 beside a bar chart's categories,
3.7 more below — read now (`valueTicksOut`, `categoryTicksOut`). And a
2007-style chart that Office wrote (`c:style` present, text in no
colour of its own) keeps 6.5 pt to the frame at its left and bottom,
not 9: the POI decks' labels stood 2.5 pt in from PowerPoint's; a newer
chart's 9 holds (moving every chart's left in made the 2013 ones up to
+1.0 worse), and LibreOffice's charts, which name no style, keep it
too. A chart this app writes names style 2 unless it came from a file
that named none.

Sweep 90, 2026-10-15: 1.2747% (from 1.4984 at sweep 83 this morning);
the baseline written whole again, 84 decks exact.

**A WMF with its y axis up, 2026-10-15** (aascu cooper 5.79 → 5.28,
its page 11 12.4 → 4.2; the 41 decks with a metafile otherwise
unchanged). The cartoon on cooper's page 11 sets its window at origin
y 1215 with a height of −1824 — y running up — and the picture's frame
was taken with that negative height, which draws nothing. The frame is
the window's size now, its sign left to the mapping, which turns the
picture the right way up into it, as GDI does.

**Arrowheads, 2026-10-15** (the 24 decks with one: within ±0.02 each —
heads are small). `a:headEnd`/`a:tailEnd` were not read, so every
connector and line arrow ended bare. They are drawn now at PowerPoint's
sizes, measured off its PDFs: width and length the line's width times
2, 3 or 5 (sm, med, lg), the line's width taken as 2 pt at least — a
medium head on cooper's ¾ pt connectors and lo-connectors' ½ pt ones is
6 pt; "triangle" (and "stealth", "diamond", "oval") filled, the line
stopping inside it; "arrow" open, two strokes. Straight lines only;
bent and curved connectors still end bare.

**WordArt's lines keep their spacing, 2026-10-15** (ImportWordArtGradient
18.12 → 11.99, WordArtDefaultColor 8.41 → 7.07, WordArtFontText 4.52 →
3.12, WordArtFontTheme 3.38 → 2.16, three more −0.2; the 23 WordArt
decks none worse). Bent text of several lines was squeezed together —
each line's letters filling its share of the band — so ImportWordArt's
"Happy" ran into its "Birthday", where PowerPoint leaves a 27 pt gap.
The lines now stand a pitch apart and the whole, first capitals to last
foot, is fitted to the band. The pitch, 1.3 heights of a line's box,
is the corpus's best (1.0–1.6 tried); not derived.

**A damaged PNG, read as PowerPoint reads it, 2026-10-15** (crash-57308
3.81 → 2.69; the other damaged decks unchanged). Its footer, a rainbow
bar, is a PNG with one IDAT whose CRC and whose zlib Adler sum are both
wrong; PowerPoint draws it and the image codec refused it. When a PNG
does not decode, `Png.repaired` inflates its image data raw (no Adler
check), deflates it afresh and writes every chunk with a true CRC, and
the codec is tried again. (Its other picture, which decodes cleanly
here, PowerPoint shows as "The picture can't be displayed"; not
imitated.)

Looked at and left: tdf146223's 2×2 JPEGs, which PowerPoint shows as
one flat colour — (35,35,35) for pixels decoding to 0, 57, 32 and 92 —
match no decode tried (a DC-only one gives 44).

**A wave's slant, 2026-10-15** (FontWorkScaleX 3.52 → 3.29; the other
WordArt decks unchanged). A wave preset's second adjust (`adj2`, ±10%)
slides its top edge against its bottom one by twice that share of the
width (the preset's `of2`) — right when negative — as textPlain's
adjust does; it was ignored, and FontWorkScaleX's −5661 wave stood
upright where PowerPoint's leans right. It now slants the block the way
textPlain's does.

**A diagram's margins follow the author's text size, 2026-10-15**
(smartart-snake-rows 1.54 → 1.09; linear-rule-vert and
composite-infer-right −0.02; the other diagram decks unchanged). A
diagram laid out here takes its margins as fractions of the layout's
font size (65 pt, `tMarg` 0.3 of it): right for text the layout sizes,
wrong for text whose every run the author sized — snake-rows' 16 pt
children sat 22 pt down in their boxes, PowerPoint's about 5. Such a
shape's margins are now scaled by its largest run over the layout's
size.

Left: lo-tdf125573's `fromWordArt` arch (its text grown to fill the
arc in PowerPoint's print, 18 pt here) — the only such shape in the
corpus.

**Elbow and curved connectors, 2026-10-15** (sweep 91: 1.2511 →
1.2432%; lo-connectors 1.27 → 0.00, elbowConnectors, curvedConnectors,
tdf154074_freeConnector, connectorConnection, tdf164623 and tdf89449
to 0.00–0.03, tdf141058-1 −0.23; none worse). Every `p:cxnSp` was drawn
as a straight line from one corner of its box to the other, so an
elbow or a curve was a diagonal. A bentConnector or curvedConnector is
now its preset path in its box, turned and mirrored as a shape is,
stroked and never filled, with its arrowheads at the path's ends along
its first and last segments. Unedited it is written back as read; an
edited one keeps its preset.

**A placeholder with no type and no index is the title's, 2026-10-15**
(bullet-indent 1.24 → 1.07, formatting-bullet-indent 2.00 → 2.09; the
nine decks with one otherwise unchanged). `<p:ph/>` is index 0, which is
the title's, and PowerPoint sets formatting-bullet-indent's "Object
without master styling" as its title — 44 pt light, no bullet — where
we took it for a body (28 pt, bulleted). It inherits as a title now; the
file's own spelling is kept for a save. (formatting-bullet-indent scores
worse for being right: its 44 pt Calibri Light falls to Carlito's
regular weight here.)

**A plain table's grid is 1 pt, 2026-10-15** (sweep 92: 1.2430 →
1.2364%; tdf135843_export 1.76 → 0.02, table-with-no-theme 0.85 →
0.07, tdf151767 0.52 → 0.00, shapes −0.31, tdf132472 −0.26, aptia
−0.25; clusterfuzz 6254 +0.20, a table PowerPoint draws a sliver wide).
A table with no style, or "Table Grid" (`{5940675A…}`), is ruled in
black at 1 pt in PowerPoint's print; ours were the editor's ½ pt.

**Inner shadows, and a picture's outline, 2026-10-15** (sweep 93:
1.2364 → 1.2342%; tdf99030 1.70 → 0.44, graphic-stroke's frame drawn;
tdf169088 +0.03). `a:innerShdw` was not read: tdf99030's layout box,
black inside its edges in PowerPoint's print (blurRad 9 pt at 100%),
was flat and pale. A shape with a fill now draws everything outside its
outline, offset and blurred, clipped to the inside. And a picture's
own line (`a:ln`, or its style's `lnRef`) is drawn round it — but not
round one turned in 3-D, which is drawn flat here and whose frame would
stand where the picture does not (Scene3d_pureImage, +0.31 when tried).

**A diagram connector between the nodes it names, 2026-10-15**
(smartart-accent-process 2.29 → 1.74; the other diagram decks
unchanged). A connector in a row stood in the middle of its slot, level
with the middle of the columns beside it; accent-process's names the
nodes it joins (`srcNode`/`dstNode` = parTx) and PowerPoint draws it
between those headers. It now stands midway between them.

Tried and dropped: textCircle's later lines on smaller circles inside
the first (TextOnCircle +0.28) — PowerPoint's circle text is also
larger and starts further round than ours, and those come first.

**Compound outlines, 2026-10-15** (ShapeLineProperties 1.88 → 1.98;
the other four decks with one unchanged). `a:ln cmpd` was not read: a
"double line" was one thick line. A closed outline now draws as two or
three — the full stroke with its gaps rubbed out, each gap a share of
the width from the outer edge: dbl ⅓ in the middle, thickThin 0.6–0.8,
thinThick 0.2–0.4, tri 0.2–0.4 and 0.6–0.8. ShapeLineProperties' 5 pt
thinThick reads 1 pt line, 1 pt gap, 3 pt line from outside in, exactly
PowerPoint's profile; the page scores a little worse for its edges
(PowerPoint's PDF fills the bands as rectangles, snapped differently).

**A newer chart's value labels and legend, 2026-10-15** (chart-slide-bg,
-texture-bg, -picture-bg, tdf112089 −0.03 each, tdf114821 −0.05,
chart-theme-override −0.01; none worse). On a 2013-style chart
PowerPoint's value labels stand 2.5 pt further off the plot than the
room it leaves them (at 166.5 where ours were at 169, the plot and
category labels exactly where PowerPoint's are), and the legend's
entries are 2.5 pt closer together (9.5 between entries, not 12). Both
now; a 2007-style chart keeps its own measures.

Tried and dropped: a newer chart's plot ending 1.2 pt higher (its value
labels' pitch says so) — six chart decks +0.07 to +0.44.

**Aptos, tightened, 2026-10-15** (the twelve Aptos decks −1.21 in sum:
NumberedList −0.56, tdf173712 −0.26, shape-text-glow-effect −0.13, six
more a little; tdf162283 +0.03). Aptos, Office's new default, is set
in Liberation Sans here, and PowerPoint's lines in it are 3.5% shorter
than ours (5.5% in bold) over 28 lines compared. A run in Aptos is now
set 0.0185 em tighter (bold 0.031), as Arial Black's stand-in is set
looser — in the Slides reader only, the shared face untouched.

**A diagram's lines step at their face's own height, 2026-10-17** (the
74 diagram decks −1.96 in sum: tdf141058-1 1.67 → 1.13, tdf93830 1.32
→ 0.90, smartart-preserve 0.63 → 0.32, 17 more better; missing-bullet
+0.60, smartart-simple +0.23, tdf149551's Pie +0.19, ten more +0.01 to
+0.08). In a diagram's text PowerPoint does not use its 1.2 single
line: customGeo's 17 pt bullets at 90% stand 18.66 apart, 0.9 of
Calibri's own 1.22, and tdf149551's Courier ones 0.9 of Courier New's
1.13. A diagram shape's theme now takes its face's own line
(`ShapeState.naturalLines`; `SlideFonts.ownNaturalHeight` for a face
drawn by a stand-in of another height). Per text box, by its default
face at first — tdf149551's runs are Courier in boxes whose face is
Calibri — and then run by run (`RichTextTheme.naturalLinesPerFace`,
shared and off for Word, with `faceLineHeight` naming a stand-in's
original's height: `SlideFonts.drawnNaturalHeight`): Pie 0.48 → 0.17,
Venn 0.42 → 0.16, Pyramid −0.15; Gear +0.14, GeomLec1 +0.06.
missing-bullet's text is fitted, and fits at another size.

**A table cell's bullets where the file puts them, 2026-10-17** (the
AES deck 5.57 → 5.11, its slide 18 13.5 → about 6, tdf123090 0.17 →
0.15; no other table deck moved). A bulleted cell paragraph hung its
bullet in an 18 pt slot before the text at every level; PowerPoint
puts it at `marL + indent` and the text at `marL`, as in a shape: the
AES tables' "•" at marL 0, 36 and 72 with indent 0 stand at the cell's
edge, half an inch and an inch in, the text right after each. A cell
that says neither keeps the old slot. Also left: Divino_Revelado's
first eleven slides, which PowerPoint prints blank (every one names a
`tags` part and a sound its cut-short zip lost; the twelfth names
neither and prints) — copying that would hide text a reader can use.

**A run in capitals fitted by its capitals, 2026-10-17** (sweep 161:
1.0603 → 1.0598%; 60810 5.19 → 5.09, its slide 18 10.1 → about 4,
themes 1.51 → 1.38; lo-numfmt +0.01). A title in `cap="all"` was
spaced, kerned and put on the eighth-point grid by the letters it holds,
not the capitals it shows: 60810's "Connection to global talent
programmes/R200", 24 pt bold Calibri in a 547.75 pt line, is 547.4 kerned
as capitals ("TA", "LT") on the grid and fits in PowerPoint's print; as
lowercase pairs it came to 552 and wrapped. The measuring loop now
reads a capped run's letters as their capitals
(`RichTextTheme.measuresShownCaps`, shared and off for Word).

**Looked at and left, 2026-10-17:** customGeo's bevelled diagram
headers (`chilly`, `translucentPowder`, a 10 pt `softRound` bevel)
print with the face lifted about 31% toward white — 79,129,189 →
134,168,215, 0,176,80 → 78,201,136, 255,102,0 → 255,150,78 — and a
lit band along the top and right; the only deck with that rig, and
four boxes of one slide.

**Gradients as PowerPoint's print colours them, 2026-10-17** (sweep 162:
1.0598 → 1.0509%; aascu 5864 7.86 → 5.74, its slide 32 73.8 → about 2,
tdf109067 2.51 → 0, tdf105739 0.42 → 0, tdf109187 0.06 → 0, backgrounds
1.13 → 0.83; customGeo +0.08, tdf152606 +0.09, Scene3d_pureImage
+0.21, cropped_image +0.07). PowerPoint's PDFs hold two kinds of
gradient, and say which by the colour space each is tagged with:
- **sRGB** (350 in the corpus' prints): every one an even blend in sRGB.
  These are the gradients with a theme colour under a modifier (`tint`,
  `shade`, `satMod`, `lumMod`…), which we blended in linear light unless
  they were path gradients: backgrounds' text box, navy to pale blue,
  is 113,141,181 a quarter of the way in PowerPoint's print, 144,… ours.
  Now even, whatever the direction (`SlideFill.even`).
- **"Generic RGB Linear"** (206): the plain-colour ones, stored as
  linear-light values in Apple's linear profile, whose primaries are not
  sRGB's — so any viewer shows every colour of them shifted: pure blue
  as 9,48,254, red as 255,39,0, the stops too. aascu 5864's slide-sized
  blue band (000076 to 0000FF) differed on 74% of its page. The
  linear-light blend now goes through the profile's own matrix to sRGB
  (`SlidePainter.genericLinear`, from its rXYZ/gXYZ/bXYZ), which lands
  on MuPDF's rendering of it to a level.
Not for a shape with depth or a camera (`SlideFill.unshifted`):
PowerPoint prints those as pictures, in sRGB (Scene3d_orthographicFront
lost 0.28 with the shift). The losses are diagrams PowerPoint redraws
from their style — customGeo's purple statement boxes are a two-stop
ramp in its print, three stops in the file — and 3-D lighting it adds
(tdf152606's arrows, brighter than their own stops); the old linear-light
blend was brighter, and nearer them by chance. tdf93868's plain black
to grey (three stops, two the same) and KEY02's text gradient print
in sRGB, unexplained; neither moves, being grey or white.

**A chart's value axis up the page in up to ten steps, 2026-10-17** (no
deck moved). The Mac's Word session found Word's prints of zh-2a241df1's
charts (Excel's engine) need ten: 435,043 runs to 500,000 by 50,000,
where nine made the step 100,000. Nine had only ever been told from
eight here; the 19 chart decks are the same either way. Horizontal
value axes keep eight.

**Tried and dropped, 2026-10-17:** a free Trebuchet MS stand-in. Istok
Web, PT Sans and Fira Sans are nearer Trebuchet's widths than Liberation
Sans (0.027, 0.028, 0.030 em off per letter, weighted, to 0.038), but
the letters already stand at Trebuchet's own advances
(`SlideFonts.face`), and the seven Trebuchet decks moved −0.04, −0.01
and +0.05 in sum (2411 unchanged at 2.26): not worth four more font
files.

**Aptos's baseline, 2026-10-17** (the 22 Aptos decks −0.05 in sum:
tdf173712 2.00 → 1.88, tdf160490 −0.02, liststyle −0.02; text-highlight
1.36 → 1.45, table-with-different-font-colors +0.01). Aptos is drawn in
a clone whose descent is a smaller share of its height, and its lines
stood 0.013 to 0.08 em below PowerPoint's in twelve decks. The copies
PowerPoint's PDFs embed keep only `hhea` (1923 over 577, a share of
0.23), which overshot to 0.02 em high; 0.21 lands ten decks within
0.016 em (`SlideFonts.ownDescentShare`). text-highlight's baselines are
now PowerPoint's to 0.05 pt, but its highlight's foot rose half a point
with them, past PowerPoint's. tdf173712 is still 0.066 em low.

**A table cell's deeper levels at their default indents, 2026-10-17**
(the AES deck 5.11 → 4.97, its slide 18 13.5 → 9.5; no other table
deck moved). A cell paragraph with `lvl="1"` or `lvl="2"` and no
`marL` of its own takes its level's from the master's other-text style
or the presentation's default (`lvl2pPr`, `lvl3pPr`: half an inch and
an inch there), as PowerPoint does; the table's own base style is level
one's, and had put them at the cell's edge. Every bullet of that slide
now stands within 0.1 pt of PowerPoint's.

**A metafile picture recoloured, 2026-10-17** (customGeo 4.07 → 4.06;
the 35 decks with a metafile or a duotone otherwise unchanged). A WMF or
EMF picture's duotone, transparency and levels were applied to bitmaps
only; PowerPoint applies them to the played drawing too — customGeo's
signpost WMFs under an `accent1` duotone print 39,87,145 and were their
own black and yellow. The drawing is now played into a layer that takes
the same colour filter (`SlidePainter.imagePaint`).

**A bullet before a link in the text's colour, 2026-10-17** (no deck
moved at two places). A paragraph whose first run is a link drew its
bullet in the link's colour; PowerPoint draws it in the run's own (or
the level's): customGeo's resources page, black bullets before blue
links.

**A short table row filled out; a chart's deleted axis and unlined walls,
2026-10-17** (LIBRE_OFFICE-100610's survey slide 7.86 → 7.83; nothing
else moved). Its second row's last cell spans three columns with no
merged cells after it: PowerPoint wraps "Vermelho" in one column and
fills the row out with two empty cells, ruled black over the white
edge of the cell above — we left the room bare. And its 3-D bar
chart, whose axes are both deleted and whose floor and back wall say
no line, stood on an axis line and in a box's edges; it now stands in
neither (`Chart.BarView.walled`).

**A 3-D bar as deep as it is wide, 2026-10-17** (LIBRE_OFFICE-100610
2.04 → 2.00; aascu 5864 unchanged). A 3-D bar chart's box was a
category deep and each bar a 1 + gapDepth share of it. PowerPoint's
bars are as deep as they are wide, in a box `gapDepth` deeper: the
survey's four bars abreast, 46.5 pt wide with no gap, show 15.5 across
and 12 up in its print (46.5 deep), where ours took the whole
category's 186. aascu 5864's single series comes out the same either
way (11.2 wide, its box 28).

**A 3-D pie in perspective, and a hidden axis left unrounded,
2026-10-17** (LIBRE_OFFICE-100610 2.00 → 1.51, worst page 7.17 → 4.49;
workbooks: LIBRE_OFFICE-128382 12.12 → 11.14, chart-tdf114139 2.13 →
1.37, lo-orderOfCNumFmtElements 3.87 → 3.33, 45544 and both 45540s
+0.03). PowerPoint draws a 3-D pie as seen from about 4.8 radii off:
the survey's centre stands 62.5 of the top's 152.5 px down, not half
way, and the rim shows only where it faces the eye. Its rim is lit
from the left — 0.85 of the colour there, 0.54 at the front, 0.41 from
a little right of it on, where ours was darkest in the middle and
light at both ends — and the rim is 0.275 of the radius deep. A best
fit there puts each label inside its slice, 0.9 of the way out, in
the labels' own colour (unless the file moves them: 45544's moves are
from beside the pie). And a value axis the file deletes, with no
gridlines, runs to the data and a twentieth past it, unrounded: the
survey's 3-D bars reach 6 of 6.3 and 14 of 14.7, where ours stopped at
6 of 7. Left: 45544's moved pie labels land off the chart.

**A chart title where the file places it, 2026-10-17**
(LIBRE_OFFICE-100610 1.51 → 1.49, aascu 5864 5.74 → 5.73; workbooks
mixed by a few hundredths). A title's own place
(`c:title/c:layout/c:manualLayout`, edge mode) was dropped: the
survey's bar charts' titles stand a third of the way down their
charts in PowerPoint's print, across the bars, where ours sat at the
top. The text stands 4.5 pt in and 1.5 down from the box's corner,
drawn after the plot; the plot keeps its room as before.

**A table cell's bullet in its own face, 2026-10-17** (AES 2011
Maloney 4.97 → 4.69; the 54 other table decks unchanged). A cell's
`a:buFont` was dropped, so its "•" came out in the text's face: in
Maloney's Verdana tables a 6.9 pt dot where PowerPoint sets Arial's
4.9, and "Can you headings that tell" went a word early. Cells now
take the bullet's face, and Wingdings' round bullet's stand-in, as a
shape's paragraphs do.

**Looked at and left, 2026-10-17:** the Office 2007 theme's intense
effect — a 5 × 2 pt `bevelT` under `threePt` — on 60810's eight
SmartArt boxes (one page): PowerPoint lifts the face 7% and lights a
5 pt band, white-hot 1.5 pt in along the top, the sides and foot
darkened to about 0.7 at the edge. Only 60810 and customGeo use it.

**A diagram box's fit measured finely, 2026-10-17** (customGeo 4.06 →
4.02, its slide 47's fourth column back at 17 pt; the 50 other SmartArt
decks unchanged). Re-fitting a diagram drawing's text to its box laid
the text out in whole points unless the box's margins follow its font:
customGeo's fourth year column, 17 lines of 17 pt at 90%, rounded each
18.65 pt line up to 19 and took 335 pt of a 330 pt box, so it shrank
to 15.7 where PowerPoint keeps 17 (its lines within 0.6 pt of ours,
326 pt in all). The fit is now measured at a twentieth of a point
everywhere. Also seen there: `spcFirstLastPara="0"` (no space after
the last paragraph) is not read.

**A cropped picture drawn whole and clipped, 2026-10-17** (sweep 165:
1.0504 → 1.0464%; customGeo 4.02 → 3.81, Maloney 4.69 → 4.34, 54542
0.89 → 0.16, cooper 4.44 → 4.29, 60810 5.09 → 5.00; lo-croppedTo0
+0.13 and tdf153008 +0.12, edge smoothing only). PowerPoint's print
embeds a cropped picture whole and clips it; ours drew the crop's
rectangle of it, which the PDF carried as a cut copy, sampled from
another origin by any reader: customGeo's 138 dpi screenshots of
small print came out a different grey in every letter. A crop (not a
pad) is now the whole picture drawn to where it falls, clipped to the
frame.

**A bullet's offset 0 when only its edge is said, 2026-10-17** (sweep
166: 1.0464 → 1.0460%; aascu 5864 5.73 → 5.56, lo-n83889 0.48 → 0.42;
none worse). A paragraph whose margin (`marL`) is said somewhere and
whose offset (`indent`) nowhere hung its bullet our usual 18-odd pt
into the margin; the format's default offset is 0, the bullet at the
edge with the text after it, as PowerPoint prints aascu's text boxes
(`marL="0"` from the default text style, no indent).
Also seen there: a chart with no `c:style` and bare gridlines prints
them #868686, Office 2007's grey, not 15%; drawn so, the page scored
no better — our 3-D plot's gridlines stand half a point off
PowerPoint's (its back wall 5 pt shorter) — so left for now. Its
labels are Lucida Sans Unicode in PowerPoint's print, Liberation Sans
in ours.

**Hebrew paragraphs right to left, and an unknown face's Hebrew at
Calibri's widths, 2026-10-17** (sweep 167: 1.0460 → 1.0441%;
tdf98603 4.79 → 3.74; tdf134862 +0.02). A slide paragraph's direction
(`a:pPr rtl`) was not read at all. Now a paragraph that says `rtl="1"`
runs right to left, and so does one that says nothing itself and
starts (first strong letter) in Hebrew or Arabic — tdf98603's quoted
line under a master that says `rtl="0"` everywhere has its opening
quote at the right in PowerPoint's print, where ours put it at the
left. Its face, FrankRuehl, is missing on the printing machine and
set in Calibri; Calibri's Hebrew widths (narrower than Carlito's by a
fifth) now go with any face that falls back to Calibri, not only one
named so, and the line breaks after the word PowerPoint's does.

**Kerning as PowerPoint kerns, 2026-10-17** (sweep 171: 1.0441 →
1.0301%; tdf140852 3.86 → 1.85, HowWeRefactor 3.50 → 2.29, alterman
5.54 → 4.84, smartart-simple 3.90 → 3.24, tdf93868 1.72 → 1.25,
2411-Performance_Up, 45541 ×2 and 45545 −0.40, fourteen more a little;
none worse past 0.02). The engine kerned every pair of every run.
PowerPoint's prints say otherwise, three ways:
- A run's `kern` is the size it kerns from (`kern="0"`: not at all).
- Where a run's styles say no `kern` at all, it depends on the deck.
  A deck with a default text style of its own (`p:defaultTextStyle`,
  which every PowerPoint file has) leaves such a run unkerned:
  alterman's body text at 24 pt sets "You" at its plain width, its
  title and body styles saying nothing — and so do bug68703 and
  bug65228, which say `kern` nowhere. A deck with none (LibreOffice's)
  takes PowerPoint's built-in default, kerned from 12 pt up:
  lo-open-as-read-only's "read-only," is 2.7 pt short of plain.
  (Sweep 174 settled this: 1.0254 → 1.0247%, bug68703 1.15 → 0.93.)
- A face with no `kern` table is never kerned: Work Sans and Poppins
  kern only in their OpenType layout, which PowerPoint does not use
  (tdf140852's "Training" and lo-master-slides' "Avoid" at their plain
  widths), Tahoma Bold the same, and Century Gothic has no kerning at
  all where its stand-in does.
The shared layout's `RichTextTheme.kernsByRun` (on for slides, off for
Word, which keeps its own `wordRules`) turns the engine's kerning off
for a run whose `kerningFrom` is 0 or above its size.

**A newer chart's plot 1.5 pt lower on a slide, 2026-10-17** (sweep
172: 1.0301 → 1.0254%; chart-picture-bg 2.66 → 1.63, chart-slide-bg
2.32 → 1.61, chart-texture-bg 2.24 → 1.59, tdf149985, tdf112089 and
tdf114821 a little; none worse). A 2013-style column chart's top
gridline stands 1.5 pt lower in PowerPoint's print than ours (100.5
against 99 on chart-slide-bg), its foot where ours was; 1.25 and 1.75
both scored worse. Its value labels' middles stand 1.2 pt above their
lines, which made no difference to the score and is left. Slides only
(`Chart.onSlide`): the half-line top was measured on Word's prints.

**A 2007-style bar chart's value labels back at the foot, 2026-10-17**
(bar-chart 1.40 → 1.31; the other chart decks unchanged). Raising its
plot 3.8 pt (2026-10-16) took the value labels under it up too —
they are drawn from the plot's foot — where PowerPoint's stay at the
frame's: 401.4 in its print, ours 397.8. They now stand 7.8 pt under
the plot, as the plot was raised.

**A metafile's last unit on its frame's edge, 2026-10-17** (sweep 175:
1.0247 → 1.0191; lo-activex_picture 3.20 → 1.62, spinbutton 0.44 →
0.05, control_background_color 1.90 → 1.59, commandbutton 0.64 → 0.43,
tika-2605 0.14 → 0.00, eight more control decks; 45541's three +0.01).
PowerPoint stretches a WMF's window so its last unit, not the unit
after it, lands on the frame's right and bottom edges, and clips what
is drawn in that unit: a control's picture of 175 by 114 units, ruled
grey on all four sides, prints with its left and top rules only, the
fill running to the edge. Ours drew all four rules inside the frame.
A window thousands of units across moves by nothing to see.

**An EMF's frame to and including its last unit, 2026-10-17** (sweep
177: 1.0191 → 1.0145; lo-tdf143222 4.22 → 0.24, bug54570 2.62 → 2.30,
ecodesign 3.19 → 2.99 — its page 23 7.52 → 1.11 —, four more a little;
lo-tdf149206 1.41 → 3.39, tdf169694 +0.05). The other way about from a
WMF: an EMF is drawn as if its frame were a unit wider and taller than
the header says, so lo-tdf143222's pasted sheet, 1569 units across,
prints 0.064% smaller than ours, every word drifting right and down
by up to half a point. One unit narrower (as a WMF) made it 6.25.
tdf149206 fits neither: its one bitmap prints 563.5 by 451 units for
a frame of 562.95 by 450.35 (and a window mapped onto a viewport of
its own), half a unit either side; left.

**Lines on whole points, 2026-10-17** (sweep 180: 1.0145 → 1.0016;
55 decks better, 25 worse; smartart-simple 3.24 → 1.63, pptx2svg 5.00
→ 3.69, tdf93868 1.25 → 0.62, 60810 −0.44, the AES deck −0.36, cooper
−0.35, alterman −0.31; font-scale +0.58, tdf169524 +0.53, aptia +0.21).
The wobble found earlier is a rounding: PowerPoint sets every line's
baseline on a whole point from the top of its box's text, 0.1 pt
down, and its print then rounds that down to the 1/300 in raster. The
AES table's 16.8 pt lines (17, 17, 17, 16, 17 apart), alterman's,
ececapstone's and aptia's every long box fit it exactly, all 21 lines
of the AES page; the 0.1 is the same in all four, whatever the face,
size or spacing. Each line of a box is now drawn in its own band and
moved to the nearest such point (0.02 above a whole one, the
raster's rounding allowed for). A line we set nearer half a point off
goes to the wrong point, a whole point out — aptia's two, font-scale's
one; the rest land within a tenth. Not yet: tables (whose points count
from each cell's text), boxes in columns (lo-3columns went +1.72,
their lines side by side in one band), turned text.
A box of one line goes on its point too (sweep 181: 1.0016 → 0.9956,
51 better, 30 worse; smartart-simple 1.63 → 0.76, WithMaster 1.16 →
0.75; bnc862510_6 +0.22, tdf129686 +0.21): it had been left as set.
And to the whole point nearest our line rather than the nearest of
PowerPoint's (0.1 below whole ones), the line drawn 0.02 above it as
before (sweep 182: 0.9956 → 0.9874, 60 better, 9 worse; font-scale
−0.58, tdf125551 −0.42; bullet-indent +0.19). Our lines stand a little
high: of 3289 lines the snap moves, 2807 land within 0.15 pt so, 2669
the other way, a whole point out 394 times to 537. Courier New is the
face most often a point high (28% of its lines), then Lucida Sans
Unicode (19%); Calibri, Arial and Verdana 8–10%.

**Tried and dropped, 2026-10-17: a table's lines on whole points,**
each cell's counted from its own text's top, each line drawn in a band
the width of its cell's text, the rest of the table (fills, rules)
drawn once outside every band. The 55 table decks went +0.71 in sum,
20 worse and 12 better (tableBorderLineStyle −0.64, table_test2 −0.23,
the AES deck only −0.17; bug68703 +0.98, its rows' white rules lying
inside the text's line boxes and moved with them). And the pass for
the rest kept every line's text in the PDF under its clip, so the
page held each line twice (68 for 35). Wants a way to draw a cell's
lines alone, not the table under a clip. (A box's bands draw nothing
twice: a line outside the band is left out whole.)

**A table's lines on whole points after all, 2026-10-17** (sweep 183:
0.9874 → 0.9847; 18 decks better, 5 worse; tableBorderLineStyle
−0.64, bug68703 −0.27, table_test2 −0.27, the AES deck −0.17;
tdf149785 +0.16). Done inside the layout this time
(`RichTextTheme.cellLineShift`, nil for Word): where a cell's
paragraph draws its text, each line is drawn in its band, moved to its
point counted from the top of the cell's text, and the marker with the
first line. The fills and the rules are drawn once, where they were,
and the PDF holds each line once.

**Lucida Sans Unicode's own widths, 2026-10-17** (GeomLec1 5.71 →
5.35, aascu 5864 5.13 → 4.99; no other deck sets it). PowerPoint's
prints of the two embed the face's subsets, and their /Widths (codes
read through MacRoman, there being no ToUnicode) give 71 printable
characters and the dash, quotes and ellipsis: 18 of our estimates
from Arial's were out, "/" 0.32 em for 0.52, "?" 0.63 for 0.42, "J"
0.48 for 0.31, "+" and "=" 0.67 for 0.80. Word's table is the same one.

**A 2007-style chart's axes, and its plot a point lower, 2026-10-17**
(sweep 184: 0.9847 → 0.9801; line-chart 1.78 → 0.84, scatter-chart
1.79 → 1.16, bar-chart 1.31 → 0.81; cooper +0.07). Office 2007 draws
an unstyled chart's gridlines, both axes' lines and their outward
ticks (5.7 pt) all in 0.75 pt of #868686; ours had 15% grey gridlines
and no axes or ticks. The grey was tried twice before and lost, the
gridlines a point off: a titled 2007-style plot starts a point lower
on a slide (line- and scatter-chart's top gridline at 161.35 in the
print, ours 160.43, now 161.43). Cooper's untitled charts stand 3.8 pt
higher than ours, top and bottom, and their darker rules now cost a
little; one deck, not followed. Slides only (`onSlide`). A 2007-style
radar's rings and spokes are that grey too (radar-chart 1.58 → 1.24;
its rings within 0.4 pt of the print's). And a 2007-style series' line
is its colour shaded to 95% in linear light and saturated 105% (the
style's line, as Office 2007 draws a shape's outline): line-chart's
4F81BD series prints 4A7EBB, as do radar-chart's line and the rims of
scatter-chart's marks, their fills 4F81BD (radar −0.01, scatter
−0.02).

**A style's line through its theme line's colour, 2026-10-17** (sweep
186: no deck moves past 0.01). A shape whose outline comes from its
style (`a:lnRef idx`) takes the colour through the theme's line style's
modifiers on `phClr`: the Office 2007 theme's first line is shaded to
95% and saturated 105%, and shapes' connector prints 4A7EBB for
4F81BD, as ours now does. Only the width was read before.

A 2007-style pie on a slide has no white rims between its slices, as
its print shows (chart_pt_color_bg1 0.62 → 0.55, pie-chart 1.42 →
1.44: its slices a little off PowerPoint's, which the rims hid).

A newer chart's value labels on a slide stand 1.25 pt above their
gridlines' places (chart-slide-bg and its three like it −0.02 each;
tdf114821 +0.02, tdf149985 +0.01): lowering its plot 1.5 pt took them
down with it, and they print 1.1 to 1.5 above. tdf149985's and
tdf114821's category labels and plot foot stand 2.1 pt high, the rest
of the chart where PowerPoint's is. That is the foot: a newer chart on
a slide with no legend under it keeps 6.9 pt there, not 9 (tdf149985
1.79 → 1.17, tdf114821 0.91 → 0.71); one with a legend there keeps 9
(chart-slide-bg's labels already PowerPoint's). And a 2007-style
scatter's x labels stand 7.6 pt under its plot, as a line chart's do,
not 4 (scatter-chart 1.14 → 1.08; they printed 3.5 pt lower).

**A shrink-to-fit's reduction under a spacing of its own, 2026-10-18**
(lo-3columns 6.34 → 5.17, GeomLec1 −0.02; the other 16 shrink-to-fit
decks unchanged). Where the paragraph's own spacing is under single,
PowerPoint takes the autofit's `lnSpcReduction` off the whole line,
baseline and all, not off the space above: lo-3columns' 90% less 20%
at 15 pt puts the first baseline 9.5 pt down (every one of its column's
twelve lines on its whole point fits 9.4 to 9.6 only), where ours stood
at 8.7. From single, it comes off above as before: font-scale's 100%
less 20% are PowerPoint's so, and a point low scaled (+3.18 tried);
aptia and testPPT the same way.

Tried and dropped: lo-3columns' lines on whole points from each
column's top (through `cellLineShift`, with the page piece's place).
Most land within 0.1 pt, but every fifth a point low: its first
baseline here is 9.54 where PowerPoint's lies in 9.4–9.5, and rounding
to the nearest point (which suits the decks at large) takes it up
(5.17 → 5.19).

**Tried and dropped, 2026-10-18: blurred text shadows** (since done
another way — see "Blurred text shadows in the PDF"). 45541's
titles and bullets cast a black shadow 3 pt down and right, blurred
3 pt; ours is a sharp copy at 45% (the engine's own text blur goes to
PDF as a soft mask at the page's corner). Drawn instead as the text
again in a blurred layer (colour filter srcIn, blur image filter, as
picture-filled shapes cast theirs), it looks right on screen and in
a close-up, but Skia rasterises such a layer at the PDF's raster DPI,
72: one pixel a point, so the shadow came out in blocks and the three
45541 decks went 5.99 → 7.21 (7.10 at half the blur). Raising
`fRasterDPI` to 300 in the engine's PDF bridge (a controlled sweep,
the same engine with and without it) made the corpus worse: 0.966 →
1.035, 109 decks worse to 89 better, and a tiled picture fill in a
rasterised layer drawn at the wrong scale (page_transparent_bitmap
+15). Wants a blur that is not rasterised at all, or a raster DPI
for the shadow layer alone.
The sharp stand-in's strength, 0.35 of the shadow's alpha rather than
0.45 (sweep 237): 45541's three copies −0.08 each, alterman +0.07 — its
shadow the same 3 pt, blurred 3 pt, but light grey on white where
45541's is black on dark blue. A trade between two decks; left at 0.45.

**Tried and dropped, 2026-10-18: a path gradient's tile
(`a:tileRect`).** ImportWordArtGradient's third box runs its tile a
whole box above and to the right, so in PowerPoint's print the letters
are deep at the bottom left and clear toward the top right; ours, laid
over the box, are clear at its middle. Laying the gradient over the
tile (and, with it, reading a rectangle path's fill-to rectangle as
fractions of the area, as every other reader of it does, where the
rectangle painter took its right and bottom as insets — as
`shadeToTitle` writes them) went +1.54 in sum: the target deck +0.11,
minimal-gradient-fill-issue's radial box (no `a:fillToRect`) all one
colour, tdf114848 +0.74. The two conventions want reconciling first.

**A shrink-to-fit's reduction of an unstated spacing stops at three
fifths of a line, 2026-10-18** (sweep 208: corpus mean 0.9655 → 0.9641;
bug62513 −0.49, ecodesign −0.13, customGeo −0.07, aascu 5864 −0.06,
tdf149961 −0.05; testPPT +0.01). bug62513's fitted lists (slides 8, 9,
17) stood a whole point high, every line. A survey of the corpus's 36
boxes with an `lnSpcReduction` (first line, ours against PowerPoint's,
both snapped to whole points) bounds where PowerPoint's unsnapped first
baseline lies under the text's top, as a share of the size. Spacing
said nowhere, less 20%: 0.7167–0.7206 from eight Calibri boxes of 18
to 36 pt — 0.72, three fifths of a 1.2 line — where taking all of it
off above gives 0.696, a point high in five; less 10%: 0.8125–0.8167
from seven, ours 0.816, above the floor. Spacing stated as 100%, less
20% (lo-font-scale): all of it off above, as before — the floor on
those cost it +0.68. And plain spacing under single, no reduction
(tdf157740's 70%), is as before: +0.24 when the floor took it too.
So the floor is for a reduction of a spacing said nowhere, which the
reader marks (`RichParagraphStyle.lineSpacingUnstated`, false for
Word). (60810's slide 17, 19 pt less 10%, still a point off: another
face.)

**Tried and dropped, 2026-10-18: table cell lines rounded a tenth of a
point low.** Maloney's slide 8 cell has every fifth 16.8 pt line a
point high (170.56 to PowerPoint's 171.6): our unsnapped line stands a
little above PowerPoint's, and at that phase it rounds the other way.
Rounding `cellLineShift` from 0.1 pt lower moved those (Maloney −0.03,
LIBRE_OFFICE-100610 −0.13, customGeo −0.03) but bug68703 +0.46 and six
others +0.02 to +0.07: 0.47 worse in sum. The nearest point stays.

**A raised run's shadow goes with it, 2026-10-18** (sweep 205: no
page moved past rounding; aascu 5864's title "21st"). A raised or
lowered run is held unseen in its line and drawn again where it
belongs; the unseen copy kept its shadow, which stood at the baseline
under the raised "st" (black, 2 pt down), and the copy drawn raised
had none. Now the held copy casts nothing and the raised one casts
its run's shadow. (Word, which shifts such runs in the line, does not
take this path.)

Tried and dropped the same day: Lucida Sans Unicode's bold as the
regular thickened (a Liberation Sans family loaded without its bold,
so the engine emboldens). PowerPoint's bold Lucida, which has no bold
face, is only a little heavier than its regular (5864's and GeomLec1's
titles); Skia's emboldening came out nearly as heavy as Liberation
Sans Bold, and goes to PDF as Type 3 glyphs. GeomLec1 +0.36.

**A column's value label past its end, as far off as it is large; a
chart title four fifths of the chart wide, 2026-10-18** (sweeps 202–203:
aascu 5864's chart pages 8 9.23 → 8.90, 16 8.96 → 8.92, 5 21.23 →
21.17; nothing else moved, few slide charts label their columns).
PowerPoint stands a column's label 0.79 of its size over a rising
bar's top and 0.94 under a falling bar's foot (5864's 18 pt labels:
14.3 and 16.9 pt); ours stood 8 pt over every bar, right for 10 pt
labels only, so its 18 pt ones sat on their bars and its −1.4 and
−2.1 on the axis line. And a chart's title wraps at four fifths of
the chart's width: 5864's 20 pt title breaks before "at", its first
line 535 pt of a 696 pt chart and "at" taking it past 557; ours used
the whole width less the margins. Both for slides; Word's charts are
as they were.

**A line of so many points has its baseline at a fixed share,
2026-10-18** (sweep 199: corpus mean 0.9658 → 0.9655; pptx2svg 3.69 →
3.51, none other moved). PowerPoint sets pptx2svg's 30 pt Verdana
line where it sets Calibri's: the paragraph before (Calibri) and this
one stand 54 pt apart, as two Calibri ones do. The engine shares an
exact line out by the drawn face's ascent and descent, so DejaVu Sans
(drawing Verdana) stood its baseline 0.5 pt lower than Carlito, and
the whole-point snap took it a full point low. Found by editing the
deck: the line's sizes, its raised and lowered runs, the paragraph
before's level and length moved nothing; dropping its face for
Calibri put it right. Now a Slides theme's `exactLineDescentShare`
(0.22, Carlito's) moves each such paragraph to that share; Word's is
nil.

**A table cell's runs carry what a text box's do, 2026-10-18** (sweep
236: highlight-test-case −0.13, cooper −0.02; none worse). A cell's runs
were built with weight, slant, underline, face, size, colour and
spacing only: highlight-test-case's green and yellow highlights in its
table's first cell were drawn plain. They take strike-through, raised
and lowered text, highlight, shadow and capitals now, as a text box's.

**Looked at and left, 2026-10-22 (late):**
- GeomLec1's bold Lucida Sans Unicode. PowerPoint fakes it (render mode
  2, fill and stroke) for "Euclid" and the grey "common notions", but
  not for the red "postulates", also `b="1"`: no rule from one deck.
  Making the bold from the regular cost the deck 0.34, so its bold stays
  Liberation Sans Bold.
- A run's own outline (`a:rPr/a:ln`) outside WordArt is still not drawn.
  Only tdf114848's footer (a 1.45 pt white line over red 12 pt text,
  which reads white in PowerPoint's print) and HowWeRefactor's six runs
  have one among the decks with a print. `_clearedPainter`'s span copy
  would carry a stroked second pass, if it is ever worth it.
- 60810's worst pages (p22, p10, p4: 6-7%) are screenshots, the
  difference their resampling's; AES p8 (7.5%) is Verdana's stand-in's
  glyphs, the layout line for line.

**WordArt's letters fitted capital top to descender foot, 2026-10-22**
(sweep 254: corpus mean 0.9202 → 0.9101; WordArtBitmapFill −3.95,
Wordart3D −1.24, ThemeColorTransparency −1.04, WordArtDefaultColor
−0.39, FontWorkScaleX −0.12; ImportWordArtGradient +0.87, the
tdf125085 pair +0.15 and +0.17). A warped line's band was mapped to
its box less 0.13 above and 0.03 below (0.2 with no descender). The
glyphs' boxes are one em, so the capitals stand only a few hundredths
in and a descender hangs past the foot (Archivo Black's "y" by 0.017
em): WordArtBitmapFill's "Happy" stood 10 pt over its frame's top and
"Birthday"'s "y" 8 pt under its foot, where PowerPoint's print keeps
both inside, its letters about 7% shorter. Fitted over the 20 WordArt
decks (75.6 in sum at the old values; 0.04 above and −0.02 or 0.15
below, 70.1): 0.04 / −0.02 / 0.15. ImportWordArtGradient, whose two
lines' pitch was fitted at the old values, is the one that loses.

**Lucida Sans Unicode's italic slanted from its regular, 2026-10-22**
(sweep 253: corpus mean 0.9206 → 0.9202; aascu 5864 4.85 → 4.65,
GeomLec1 5.33 → 5.32; none worse). The face has no italic, and
PowerPoint's print slants its regular (aascu 5864's p34 quote, `i="1"`,
embeds only LucidaSansUnicode). Ours drew Liberation Sans Italic, whose
letters are another design (a one-storey "a", a narrower "f"). The stand-in
is now Liberation Sans's regular and bold under a family of their own
("Starling Lucida Sans", no italic), and the engine slants the regular as
PowerPoint does. Making the bold from the regular as well, as PowerPoint
also does, set GeomLec1 0.34 worse: its bold stays Liberation Sans Bold.
(A note for whoever reads these comparison images: the left panel is
PowerPoint's and the middle ours. At the size an image comes in, an
italic read as upright here and sent a first attempt the wrong way; the
fonts a page embeds settle it.)

**A top bevel lit as PowerPoint lights the 2007 intense effect,
2026-10-22** (sweep 252 against control sweep 251 at the same head:
corpus mean 0.9208 → 0.9206; 60810 −0.07, tdf155412_typeface −0.03;
none worse past lo-numfmt's rounding). Bevels (`sp3d bevelT`) were not
drawn at all. 60810's slide 13 boxes (5 × 2 pt under `threePt`,
measured at 8 px/pt in PowerPoint's print): the face lifted 7%, a band
of light peaking 1.5 pt inside the top edge that adds about 68 to every
channel (the yellow's 188 green to full, its 9 blue to 78) and is gone
by 5 pt, and the sides and foot darkened to about 0.74 at the edge,
back within two to three points. Now read (`ShapeBevel`: the shape's
own `sp3d`, else its theme effect style's through `effectRef`) and
drawn over a plain fill clipped to the outline (`paintBevel`): the
face at 1.07, a dark rim (a blurred stroke), and the outline stroked a
little down in the colour plus 68, seen only in the top band. Each
scaled by the bevel's steepness against that one's (h/w over 0.4):
tdf155412's 15 × 3 pt bar shows a pale facet in PowerPoint's print,
and drawn at full strength it went +0.73. A colour dodge for the light
whitened the teal bar (dodge overdoes bright colours where PowerPoint
adds); computed colours drawn plainly stay vector in the PDF. Not
drawn: gradient-filled shapes (bnc862510_5's green half-disc), and the
dark-edge material (`dkEdge`), which bnc862510_5's grey box and
tdf145528's matrix print flat (+0.06, +0.02 drawn; tdf148921 −0.08).

**A titled pie stands further under its title, 2026-10-19** (the 19
chart decks: pie-chart 1.34 → 1.03, no other moved; corpus mean 0.9214 →
0.9208). pie-chart's pie is 262.5 pt across in PowerPoint's print, its
top 156.25; ours was 265.75 and 153.5: the room under the title 3.35 pt
taller. A flat pie on a slide now stands 6.95 pt under its title, not
the 3.6 measured on chart-slide-bg's column chart, which keeps it.

**A legend beside the plot keys as a row does, 2026-10-19** (sweep 250:
corpus mean 0.9217 → 0.9214; pie-chart −0.10, bar-chart, tdf149985 −0.03,
aascu 5864, line-, radar-, scatter-chart −0.01; none worse). A column
of legend entries beside the plot had 7 pt keys 4 pt before their names
(at 12 pt), where a row on a slide has had PowerPoint's 6.57 and 2.92:
the column's are the same — aascu 5864's 20 pt keys 10.98 square,
tdf149985's 9 pt 4.94, pie- and bar-chart's 9.88 at 18 — and its names
end 10 pt short of the frame (9.8, 10.2), a point further in than the
plot's margin. The plot's right edge stays where the 7 pt keys put it:
its gaps to the legend (12, and 17.3 for a 2007-style chart) were
measured with them, against PowerPoint's plots; moved with the keys,
line-, radar- and bar-chart went +0.2 to +0.4. (The earlier note on
tdf149985 dropped these keys for that reason.)

**A chart title's lines in their own sizes, its box its longest line,
2026-10-19** (sweep 249: corpus mean 0.9219 → 0.9217; LIBRE_OFFICE-100610
−0.05, aascu 5864 −0.03, none other moved). aascu 5864's slide 16 has
three charts titled "Average scores around age n", 14 pt, over "(relative
to those with grad-school parents)", 12 pt: the whole title was drawn at
the first run's 14, so its second line wrapped elsewhere. A later
paragraph's own size now holds for its lines (`Chart.titleLineSizes`).
And two of those titles are placed by the file (`manualLayout`): wrapped,
the title's painter was as wide as the room it wrapped in, its lines
centred in that, so they stood 12 and 19 pt right of PowerPoint's. The
title is now as wide as its longest line, and that line stands 3 pt into
the file's box — not the 4.5 fitted to these same charts when the wrap
hid it; LIBRE_OFFICE-100610's five bar-chart titles, 1.5 pt right
before, are now where PowerPoint's are.

**Measured and left, 2026-10-19.** vertical-bracket-list's text box
is 110.84 pt tall in PowerPoint's print, its text 65 pt: the text's
own height (65 × 1.2 × 90% = 70.2) and its 20 pt margins, to half a
point — the box grows for its text, as its `rule type="h" val="INF"`
lets it. Ours stays at its constraint's 101.3 (0.55 × 65 read as
millimetres) and the reader shrinks the text to 59 pt to fit. Growing
a `tx` node for its text wants the diagram engine to measure text,
which it does not. Also: a diagram's bullet stands 22.5 pt before its
text at 34 pt in accent-process, 32.4 at 65 in the bracket list, 25.4
at 51 in bullet-list (ours, at 13.5 pt hanging, matches only the
last), 11.6 at 33 in missing-bullet; no rule found. aascu 5864's 3-D
column chart (no `c:style`) prints its gridlines #868686, ours 15%
grey; drawn so, the page went 21.17 → 21.96, its gridlines being where
ours are not. And a picture-filled WordArt (WordArtBitmapFill,
deflate-inflate) differs by its band's curve, not its tiles.

**A cycle's arrows on their chords, 2026-10-19** (sweep 248: corpus
mean 0.9250 → 0.9219; smartart-multidirectional −0.98, smartart-cycle
1.03 → 0.27, none other moved). Every arrow of smartart-cycle stood
16.3 pt above PowerPoint's, whatever its direction — half its own
height. The cycle sets each connector's slot centred on the chord
between its neighbours; the node's own caps then shrank the slot from
its top left corner, so the arrow, turned about its new middle, rose by
half what was cut. A turned node is now shrunk about its middle. (What
multidirectional's note took for the ring sitting off was this.)

**A placeholder's shadow from its master, and a shadow scaled alike
both ways, 2026-10-19** (sweep 247: corpus mean 0.9267 → 0.9250;
tdf104015 0.92 → 0.00, none other moved). tdf104015's title is red and
shadowed by its master's title (`a:effectLst` in the master's
`p:spPr`); the red was inherited and the shadow not. A placeholder with
no effects of its own (no `effectLst`, `effectDag` or `effectRef`) now
takes its layout's or master's. And that shadow is scaled 101% both
ways (`sx` = `sy`), which the reader had refused as a shadow cast on
the ground: a uniform scale is the outline larger or smaller, now drawn
so about the point its `algn` names (`CharShadow.scale`, `anchor`;
tdf130058's 1% shadow, too small to see either way, now the size it
says). Skewed or flattened shadows stay undrawn.

**A diagram row holds what its children settle, 2026-10-19** (sweep
246: corpus mean 0.9319 → 0.9267; smartart-children 3.13 → 0.23,
none other moved). hierarchy-list "children": two parents side by
side, each two children under it. Every parent and child is as wide as
the diagram by its constraint, the space between parents 0.168 of that
and between children half the parents'. PowerPoint lays the whole out
at those sizes and scales it once: its print has each child 110.6 pt,
the inner space 9.3 (0.084) and the outer 18.6 (0.168), to a tenth.
We measured a parent at its own constraint, one diagram wide, so the
top row shrank by 2.17 and the parent's own row again by 2.08 — the
outer space came out 37 pt. A row or column of no shape of its own now
measures at least what its children hold — their sum along it, the
widest across — when every child's size there is settled by a
constraint (`settledContent`). Not when any child only fills what it
is offered (continuous-block-process, table-list, autofit-sync went
+8 to +36 so), nor when one is sized below nothing: linear-rule's arrow
drawn back under its row is `w` = −1 × the row's, an overlap. Reading
a child's constraints early to settle it moved linear-rule too
(+2.9); it reads those already applied.

**A metafile's one-bit pattern brush in its own colours, 2026-10-19**
(sweep 244: corpus mean 0.9369 → 0.9319; lo-activex_scrollbar 1.84 →
0.31, lo-activex_togglebutton −1.18, tdf126324 −0.01; none worse). A
WMF `DibCreatePatternBrush` was a middle grey whatever its pattern: the
ActiveX controls' pictures fill their scrollbar troughs and pressed
buttons with an 8×8 checker of the text colour and white (light grey,
pale cyan in PowerPoint's print). A one-bit pattern (BS_PATTERN) paints
its clear bits in the text colour and its set ones in the background's,
so it is now the two mixed by their share of the pattern. (EMF's
pattern brushes, records 93 and 94, are still grey: no deck to check
them against. Shared with Word's metafiles.)

**A 2007-style chart's legend below its plot, 2026-10-19** (sweep 243:
corpus mean 0.9370 → 0.9369; cooper 3.02 → 2.91; lo-numfmt +0.01, a
deck with no chart: rounding). cooper's two census charts (style 12,
their 10 pt legends below) stood their legends 1.7 pt and their plots
2.9 pt low of PowerPoint's print, their category names 3.1. A
2007-style chart sits 6.5 pt in from its frame's foot (line-, bar- and
scatter-chart's, legends beside); with its legend below it is 8.2, and
the plot stands 9.55 above the legend's line where a newer chart's
stands 8.4. Every line of the two now within 0.3 pt. Slides only; one
deck says it.

**Blurred text shadows in the PDF, 2026-10-18** (sweep 242: corpus
mean 0.9395 → 0.9370; 45541_Header −0.45, 45541_Footer and
45545_Comment −0.44, tdf114848 −0.02, alterman −0.01; customGeo +0.01,
its slide 41's 43% shadow on a pale ellipse a soft grey where
PowerPoint's is fainter). Why the engine's text-shadow blur "went to the
page's corner": it did not — the soft mask was where the text is, but
11% at its darkest. The engine makes a text shadow's blur with
`respectCTM` false, so its sigma is in device units, and the export
draws twenty pixels a point into a PDF whose units are points: our
sigma, in pixels, was twenty times too wide. With
`RichTextTheme.shadowBlurDeviceScale` set (1/20, by the slides' PDF
export alone; nil on screen and in Word, which keep the sharp 45% copy)
a blurred run shadow is the engine's blur at 0.4 of the file's radius
and 55% strength. Not the file's own measure: the PDF's mask is
rasterised at 72 dpi and softens it again, where PowerPoint's print
holds each word's shadow as a 300 dpi picture, black at its core. At
0.5 and full strength the shadow spread wider and greyer than
PowerPoint's (45541 +0.66); the strength mattered more than the width
(45541 5.99 → 5.48 at 50%, alterman 4.34 → 4.28 at 100%); 0.4 and 55%
is better than the sharp copy in both.

**Tried and dropped, 2026-10-18: no whole points in a shrunk box.**
bug62513's slide 2 (text at 55%, its 13 pt lines 15.6 apart) stands a
point low from its "Jurisdictional Reps" on, where ours rounds a
line set at x.5 the other way; PowerPoint's 13 pt lines there wobble
15.12 to 16.08 apart, not on whole points from the text's top. Drawing
a shrunk box's lines unsnapped (sweep 240) made 0.9395 → 0.9432:
pptx2svg +1.26, bug62513 itself +0.41 — PowerPoint does snap them,
by a rule not found. Two more, not followed: PowerPoint draws a
chart's 18.62 pt title in 19 pt letters set at 18.62's advances (its
PDF's `Tm` is 79.17/300 in), and 11.97 in 12, where whole-point sizes
everywhere (advances too) made chart-slide-bg 0.23 → 0.43; and
tdf173712's 8 pt heading in Aptos stands a point high, a rounding
that its first baseline, 7.58 by the tuned 0.21 share, takes up to 8
where PowerPoint's lies under 7.5.

**An exact line keeps a quarter of its text's size under its
baseline, 2026-10-18** (sweep 239: corpus mean 0.9398 → 0.9395;
customGeo 3.48 → 3.30, none other moved). customGeo's 32 pt text in
33 pt lines and its 40 pt title in 35 stood a point and two high in
ours, where pptx2svg's 17 pt in 20 and 14 pt in 30 were exact: under
PowerPoint's baseline is 0.22 of the line or 0.25 of the text's size,
whichever is more (customGeo's 8.04 under 33 pt lines, 0.251 of 32;
9.96 under its 35, 0.249 of 40; pptx2svg's lines, taller than their
text, 0.22 of the line). The size is the first run's: pptx2svg's 28 pt
line holding a 47 pt "fox" keeps 0.22 of its 30. The earlier note
below ("Measured and left") had each rule fitting one deck; the
larger of the two fits both. `RichTextTheme.exactLineDescentOfSize`
(0.25, Slides; nil, so off, for Word).

**A chart's legend row stands right of the frame's middle,
2026-10-18** (sweep 238: corpus mean 0.9403 → 0.9398; chart-slide-bg
−0.08, chart-picture-bg, chart-texture-bg and tdf112089 −0.07,
cooper's page 6 6.13 → 6.08; LIBRE_OFFICE-100610's page 8 +0.02). A survey of the legend keys in a row, ours against
PowerPoint's, found every one in chart-slide-bg's legend 2.25 pt left
of PowerPoint's and cooper's (10 pt, a 2007-style chart) 3.3 left: we
centred the row on the plot's room, which for a 2007-style chart is
not centred in the frame, and PowerPoint's rows stand 0.19 of the
legend's size right of the frame's middle (2.37 at 12 pt, 1.76 and
1.74 for cooper's two). A row on a slide is now centred there; the keys
are within 0.03 pt of PowerPoint's in chart-slide-bg's family and 0.2
in cooper's (whose names are Verdana, drawn in DejaVu Sans, wider).
A legend beside the plot is not moved: tdf149985's column has
PowerPoint's 6.57 keys too, but its names start 1.8 pt right of
PowerPoint's for a margin, not a key, and is left.

Seen on the way, not followed: lo-tdf149865 prints every "Work Sans"
— regular, and bold "Delta" — in Work Sans Light, the one weight
PowerPoint's machine had; and with_japanese's centred box stands 1.2
pt low throughout (its line pitches match ours, so its box is 2.4 pt
taller in PowerPoint's; which line makes it, not found).

**A group's child turned on its side scales with the axes swapped,
2026-10-18** (sweep 234: corpus mean 0.9437 → 0.9406;
sample_pptx_grouping_issues −1.11, GroupTransform 0.68 → 0.18,
tdf149124 −0.09; none worse). A group scaled unevenly (GroupTransform's
child space 4320000 tall drawn 2880000) scales a member turned 45° to
135° (or 225° to 315°) with its width taking the group's vertical
factor and its height the horizontal, as such a box is stored; ours
scaled it along the group's axes, its 80° shape squeezed across where
PowerPoint's loses a third of its length. Both the flattened and the
turned-group paths now swap the factors for such members
(`swapGroupScale`), about the member's centre.

**A bulleted paragraph's first-line indent is a hang, 2026-10-18**
(sweep 233: corpus mean 0.9443 → 0.9437; bullet-indent 1.08 → 0.74;
nothing else moved). bullet-indent's first paragraph
(`indent="324000"`, a first-line indent, under a bullet) prints in
PowerPoint with the bullet at the margin and the text at the indent,
as a hanging indent of that size would; ours put the bullet at margin
+ indent and the text after it. A paragraph's own positive indent
under a bullet is now read as that hang (`hangPositiveIndent`), both
lines landing to the tenth of a point. (A first try put the call
between the `if` that sets the first-line offset and its `else if`:
the `else if` then hung on the new `if`, and every paragraph with an
indent of its own lost it — 70 decks worse, though the new code never
ran for them. Read the chain an insertion goes into.)

**A diagram's author-sized text keeps its size when laid out here,
2026-10-18** (sweep 227: autofit-sync's third column now PowerPoint's
16 and 14 pt at its place to a tenth of a point; no score moved past
rounding — white text on a dark box is few pixels). Laid out here (no
drawing), a node whose points are all `custT` and whose runs all carry
an `sz` joined its siblings' shared fit and was scaled with them: the
third column's 16 pt "C" by the others' 8/65, to 2 pt. Such text now
keeps its sizes, outside the shared fit, as the drawing path keeps it.

**A scatter chart's X gridlines only where its X axis has them,
2026-10-18** (sweep 226: scatter-chart 1.08 → 0.69; nothing else
moved). A scatter chart drew gridlines up from every X tick whatever
the file said; scatter-chart's bottom `c:valAx` has no
`c:majorGridlines`, and PowerPoint's print none. Read now
(`Chart.scatterXGrid`), and written back so.

**A diagram node's edge where its centre or far edge places it,
2026-10-18** (sweep 225: corpus mean 0.9472 → 0.9450; smartart-cnt 1.28
→ 0.08; nothing else moved). Found on a contact sheet of mid-scoring
pages: smartart-cnt's vProcess5 boxes carried no text. A node not yet
laid out read its left (top) edge as its `l` (`t`) or 0 — so vProcess5's
middle box, placed by `ctrX`, and its arrow, by `r`, stood at 0 to
everything measuring from them: the second arrow at the first box's
right edge, and the text boxes (right edge = the arrow's left, less
0.57 of its width) collapsed, their "a", "b", "c" at the 5 pt floor.
The near edge now follows from the centre or the far edge where only
those are given.

**A gradient line, 2026-10-18** (sweep 224: corpus mean 0.9479 →
0.9472; backgrounds −0.41, tdf114848 −0.02; none worse). A shape's
`a:ln/a:gradFill` was drawn in its first visible stop; the backgrounds
deck's frame runs orange to blue across its box in PowerPoint's print.
The line is now stroked with the gradient over the shape's box
(`SlideShape.outlineFill`), as a gradient fill is laid.

Also seen, not ours: tdf140852's "Work Sans Medium" title prints in
Work Sans Light in PowerPoint's PDF — that machine had no Medium — so
ours, in the Medium it names, stands heavier.

**A straight connector's width from the theme, 2026-10-18** (sweep
222: corpus mean 0.9493 → 0.9482; lineStyle −0.26, tdf114845 −0.19,
tdf149697 −0.06, tdf154363 −0.04, tdf89449 −0.03, tdf141058 −0.01; none
worse). A straight connector with no `a:ln w` of its own was 0.75 pt
whatever its style's `lnRef` named; an elbow or a curve already took
the theme's line style's width. lineStyle's `lnRef idx="2"` is 2 pt in
PowerPoint's print. And a connector's shadow is read now — its own,
or its style's `effectRef` from the theme — and an outline with no fill
casts the shadow of its stroke, blurred (sweep 223: lineStyle −0.13,
tdf114845 −0.04, none worse): the 2007 theme's soft shadow under
lineStyle's line, which PowerPoint prints as a picture.

**A picture's soft edge, 2026-10-18** (sweep 221: corpus mean 0.9519 →
0.9493; croppedTo0 2.00 → 0.62, 60810 −0.07; nothing worse). A
picture's `softEdge` was not read — only a shape's — so croppedTo0's
rounded picture, faded 10 pt in PowerPoint's print, was drawn sharp.
It is now, as a shape's edge is. Not on a picture in 3-D (`sp3d`, a
bevel on it): tdf170095's 25 pt soft edge does not show in PowerPoint's
print, the picture whole (its transparent parts black, not followed);
fading it cost +0.88.

**Tried and dropped, 2026-10-18: Calibri Light in Lato Light.** 266
decks name Calibri Light (newer themes' heading face), drawn in
Carlito's regular, visibly heavier than PowerPoint's. Lato Light (the
design Carlito was cut from) at 0.895 of the size (its capitals
Calibri's height), 0.0216 em a letter wider and at Calibri's 0.22
depth below the baseline set tdf142648's title where PowerPoint's
stands to a tenth of a point — but its lower case is smaller (0.445 of
the size to Calibri's 0.466) and its strokes lighter than Calibri
Light's, and the corpus went 0.9519 → 0.9613, 32 decks worse to 3
better. Carlito's regular, heavier but the right shapes, matches more
pixels.

**Helvetica's depth below the baseline, 2026-10-18** (sweep 218:
slide-sections 1.07 → 0.80; nothing else moved). Its six 36 pt titles
stood a point lower than PowerPoint's (whose print embeds the Mac's
Helvetica): drawn in Liberation Sans, they took Arial's 0.19 share
below the baseline. Helvetica's own is 471 of 2048 (`ownDescentShare`).
Consolas the same way (sweep 219: clusterfuzz 4986 −0.04, nothing
else): drawn in Liberation Mono (0.265 below), its 24 pt code stood 1
to 2 pt high; its own is 514 of 2398.

**A preset of no known name is a line, 2026-10-18** (sweep 217:
corpus mean 0.9536 → 0.9525; clusterfuzz 4986 2.72 → 2.12, its slide 6
16.0 → 2.2; nothing else moved). The fuzzed deck's "roCndRect" (a
corrupted "roundRect") prints in PowerPoint as a line across its frame,
top left to bottom right, in the shape's line, with no fill and no
text; ours drew a filled rectangle with its title. Every preset the
other decks name is defined, so only a name DrawingML does not know
falls back so. Also seen there and left: slide 5, whose every `cNvPr`
has lost its `id` ("nd"), is blank in PowerPoint's print — the
required id missing, the shapes dropped. One fuzzed slide, and dropping
shapes on load is not this app's to do.

**A newer chart's legend and right edge as PowerPoint prints them,
2026-10-18** (sweep 215: corpus mean 0.9636 → 0.9536; tdf112089 −1.35,
chart-slide-bg −1.28, chart-texture-bg −1.27, chart-picture-bg −1.24,
tdf114821 −0.40; none worse). A survey of matched lines across (ours
against PowerPoint's) found chart-slide-bg's category labels and
legend entries 1.2 to 1.7 pt left of PowerPoint's, more the further
right. Its plot ends 11.1 pt inside the frame in PowerPoint's print,
ours 13 (its four categories 151.3 apart to our 150.9), and its 12 pt
legend's keys are 6.57 square, 2.92 before their names, 11.2 between
entries and their feet half a point under the baseline — ours 7, 4,
9.5, centred on the line, 1.3 higher; the pitch matched, the parts did
not. Both for a 2013-style chart on a slide, its legend in rows: a
legend beside the plot (tdf149985's) keeps the old keys and margin,
+0.25 and +0.11 with the new.
A 2007-style chart's legend keys are the same (sweep 216: cooper's
pages 6 and 5864's 16 a little better, nothing worse past rounding):
cooper's 10 pt legend has keys 5.47 square, 2.4 before their names —
6.57 and 2.92 at 12 — its entries 13.9 apart at 12 pt, and its keys
where a centred one stands.

**Seven tenths of a spacing over single above the line, 2026-10-18**
(sweep 212: corpus mean 0.9641 → 0.9636; clusterfuzz 4986 −0.10,
n83889 −0.08, 60810 −0.07, outliner-list-style −0.04, tdf137367 −0.02;
tdf51340 +0.03, ArtisticEffectSample +0.04). A corpus-wide survey of
matched lines (ours against PowerPoint's, `~/tmp/linesurvey`) found
clusterfuzz 4986's 200% Calibri lines a point low and tdf137367's 150%
ones 1.9 low: PowerPoint puts 0.70 of the extra above the line (as
measured on tdf137367 before, and left), the engine 0.78 for Carlito.
A Slides theme's `extraAboveShare` (0.7; nil for Word) moves such
paragraphs so. Not a face with a depth of its own (Courier New,
Poppins): TextFittingStored's 150% Courier went +0.40 and
master-slides' 110% Poppins +0.27 with it.

**Measured and left, 2026-10-18: exact lines whose text nearly fills
them.** customGeo's 32 pt text in 33 pt lines (slide 21) and 26 pt in
27 (slide 19) stand a point low in ours, 80 lines across seven slides:
PowerPoint's first baseline lies 0.742–0.773 and 0.722–0.759 of the
line under the text's top, where the fixed 0.78 above gives 0.78. A
fixed 0.75 fits those and pptx2svg's paragraph gap, but not pptx2svg's
own 17 pt text in 20 pt lines (0.755–0.805): customGeo −0.10, pptx2svg
+2.74. A baseline at the line less a share of the size (0.26 of it,
Calibri's depth) fits customGeo's two and pptx2svg's first box, not its
Calibri-to-Verdana gap. Left at 0.78 until a third deck says which. (Settled the same day:
the larger of the two — see "An exact line keeps a quarter".)

**A space before a line break counts in a box that does not wrap,
2026-10-18** (sweep 198: corpus mean 0.9670 → 0.9658; cooper 3.67 →
3.04, none worse). In a `wrap="none"` box PowerPoint centres and
right-aligns a line ending in a space before `a:br` with the space:
cooper's eleven such titles stand half a space left of the trimmed
line, to a tenth of a point. In a wrapping box it hangs the space as
at any wrap — cooper's slide 11, the same XML in a wrapping box, and
clusterfuzz 4986's titles stand where trimmed — so only an unwrapped
box keeps it (as a no-break space). Tried for every box first: cooper
gained, those titles lost 5 pt.

**A picture placeholder's text is body text, 2026-10-18** (sweep 196:
pic-placeholder-with-text 0.61 → 0.23, slide-section-test −0.04; none
worse). Text typed into a `ph type="pic"` took the master's other-text
style (18 pt); PowerPoint sets it in the body style (28 pt). Table,
chart, clip art, diagram and media placeholders read so too.

**A table's row bands colour their text, 2026-10-18**
(table-with-different-font-colors: all sixteen cells' colours now
PowerPoint's, its worst page 1.61 → 1.59; the other table decks
unchanged). A band's `tcTxStyle` (`band1H`/`band2H`) was never read,
only its fill: the third row's cyan (band2H) printed in the whole
table's grey. Counted as the fills are, from the row after a header.

**A diagram shape turned round keeps its text area turned, 2026-10-18**
(missing-bullet 4.00 → 3.76, cycle-matrix 2.32 → 2.26, autofit-sync
−0.04; the other diagram decks unchanged). A layout shape turned 180°
is drawn mirrored both ways so its text stays upright; the text kept
the unturned shape's text area, so cycleMatrix's third quadrant set
"C1" in the wedge's outer corner (428.9, 385.1) where PowerPoint sets
it near the circle's centre (389.8, 346.1). Its text now goes in its
own box over the mirrored text area (388.3, 344.6).

**Arial Black in Archivo Black, 2026-10-18** (ThemeColorTransparency
7.73 → 7.27, placeholder-layout-color 0.69 → 0.53, themes −0.02;
WordArtBitmapFill +2.38, Wordart3D +1.11: +2.86 in sum, kept). Arial
Black was Liberation Sans Bold at Arial Black's widths, thin letters
standing apart. Archivo Black (OFL, Google Fonts) has Arial Black's
widths (H 0.833, a 0.667 em) and its weight, and is now bundled and
used for it. The two decks that go up are WordArt we draw wrong anyway
— Wordart3D without its depth and in the wrong place, BitmapFill's
picture tiles misaligned — where heavier letters only cover more of
what already disagrees.

**A table cell's own line runs past its corners, 2026-10-18**
(tableBorderLineStyle 1.77 → 1.01, tdt142291 0.27 → 0.08, three more
−0.01; the other table decks unchanged). PowerPoint draws a cell's
`lnL`…`lnB` from half its width before the edge's start to half past
its end, and counts its dashes from there: the "Dash" row's top rule
runs 203.5 to 384.5 for a cell from 204 to 384, and every dash stood
half a point late in ours. `RichTextTheme.cellLinesPastCorners`, on
for slides only.

**An outline's join, 2026-10-18** (sweeps 191–192: −0.06 in sum, 8
decks better, one 0.01 worse). Ours mitred every outline; PowerPoint's
prints join 223 thick strokes round against 301 mitred, the round ones
mostly in lines that name no join. A line's `a:round`, `a:bevel` or
`a:miter` (or its theme line style's) is now read, and one that names
none is joined round. Its ends too (`a:ln cap`, "rnd" or "sq", or its
theme line style's; sweep 194: −0.01, none worse). A connector's join
and ends are read too, and a dashed line with round or square ends
counts each cap inside its dash, the start cap reaching half a width
before the dash's place and a dot a cap's circle alone
(tdf134053_dashdot 0.74 → 0.07; the ten other decks with such lines,
all charts' gridlines or WordArt, unchanged).

Fixed, 2026-10-18: the whole-point bands wrote a box's text into the
PDF again for every line when the box is turned other than by quarters
(tdf149538_upright, 289° with its text upright: 26 letters held twelve
times over, 256 characters become 3040). Found by counting each page's
text against PowerPoint's print. Such a box is no longer snapped
(tdf100065 +0.02, the 13 other turned decks unchanged).

**A grey picture's soft mask left sharp, 2026-10-18** (sweep 190 with
the rule's first form: lo-narration-non-media-shape 1.75 → 0.00,
oox-graphic-stroke 1.69 → 0.58; nothing else moved but tdf93830, which
the final form keeps at 0.86). PowerPoint marks an enlarged picture
`/Interpolate true` but leaves its soft mask unmarked when the picture
is grey (both decks' 64-pixel grey-and-alpha logos print crisp-edged,
their shades smoothed), and marks a colour picture's mask too
(tdf93830's RGBA icons). Our export marked every image, masks
included; it now inflates each masked picture and leaves the mask of a
grey one (every pixel's three values equal) unmarked.

**Turned text on whole points too, 2026-10-18** (eaVertAnchor 1.22 →
0.46, vert_and_padding 0.38 → 0.15, customGeo −0.02; the six other
decks with turned text unchanged). Vertical text and a turned
diagram frame are laid out along their own lines and turned when
drawn; the bands snap in that layout, so the rule holds along the
turned text as it does upright.

**A diagram's quarter-turned text frame keeps its own insets,
2026-10-18** (tdf135953_SmartArt_textposition 2.65 → 1.39; the other 50
diagram decks unchanged). "left shape" is read up the box's side in a
`txXfrm` turned 270°, its `bodyPr` inset 10 pt at the frame's top. The
insets were added to the page-side offsets of the turned room and then
turned with them by the painter, so the inset landed along the line
and the text stood 10.3 pt nearer the side than PowerPoint's. Now the
frame is placed where the painter's turn about the shape's centre takes
it, the insets go inside it along the text, and the result is handed
over in the order the painter turns back (within 0.3 pt).

**Tried and dropped, 2026-10-18: a shape's shadow at full strength to
its moved outline**, fading outward over the blur's radius (the outline
grown by half the radius, blurred by a quarter), from one edge of
customGeo's page 9 where PowerPoint's shadow read twice as dark as
ours. Sweep 189: +10.5 in sum, 22 decks worse and one better —
customGeo itself +0.27, tdf125551 +2.17, 54542_cropped_bitmap +1.30.
Our blur about the outline, sigma half the radius, stays.

**Tried and dropped, 2026-10-17:** a percentage before a paragraph
taken of the line as spaced (times `lnSpc`), from alterman's 80% lines
whose gaps looked a fifth short — sweep 173: alterman 4.84 → 6.31, the
three 45541s +0.57, five more worse, none better. Its gaps are the
wobble, not the rule. Also not drawn: reflections (`a:reflection`),
whose only printed case is themes' Trek title, three pages.

**Also looked at, 2026-10-17:** PowerPoint's line positions wobble by
up to a point in a repeating pattern — the AES 2011 tables' 16.8 pt
lines step 17.04, 17.04, 17.04, 16.08, 16.80, averaging ours exactly —
and alterman's 80% lines step 23.04 with an odd 24.0 or 22.8. No rule
found from two cases.

**Tried and dropped, 2026-10-17:** WordArt lines on a circle each on
their own ring. tdf125582's two 40 pt lines stand 42.5 pt apart in
PowerPoint's print, the last where ours both stand, and stacking them so
put each in its place — but PowerPoint also sets the outer line tighter
(its 13 letters over about 95° where ours run past 100°), and the deck
went 2.38 → 2.48. Also tried: Myriad Pro taking Segoe UI's descent, and
Trebuchet's and Franklin Gothic's Windows descents left out — −0.04 in
sum, mixed, not kept.

**Poppins' and Work Sans' baselines, 2026-10-17** (lo-master-slides
1.62 → 1.04, tdf157740 0.09 → 0.00, tdf140852 −0.12, three more a
little; none worse). Bundled as themselves, they still sat off
PowerPoint's: Poppins 0.03 em high (its 0.1 em line gap, half of which
the engine puts under the baseline, PowerPoint counting none), Work
Sans 0.06 low (PowerPoint by its Windows descent, 0.237 of the line,
where its hhea gives 0.207). Both in `ownDescentShare` now.

**Myriad Pro in Selawik, 2026-10-17** (HowWeRefactor 3.63 → 3.50, the
one deck naming it). PowerPoint's Mac printed its Myriad Pro in Segoe UI
(its lines 8% wider than ours in Calibri, the rule for faces it lacks);
it now goes to Segoe UI's stand-in.

**PowerPoint's box for a picture that names none, 2026-10-17**
(tdf147586 0.95 → 0.18, missing-blip-fill 0.45 → 0.06, crash-57308
2.69 → 2.48, clusterfuzz 4986 −0.05). A `p:pic` with no `blipFill`, or
a blip with neither `r:embed` nor `r:link`, prints in PowerPoint as a
white box ruled black, a bevelled icon with a red cross 7 pt in, and
"The picture can't be displayed." in Segoe UI 10.5 pt 27 pt in, cut to
the frame. We drew nothing; now the same (`PptxReader.brokenPicture`,
`OpaqueObject.clipsRendering`). Not for a picture naming a part the
package lacks: Divino_Revelado's, its zip cut short, print as nothing,
and boxing them cost it 1.3.

**Free fonts bundled for Slides, 2026-10-17** (sweep 157: 1.088 →
1.070%, 27 decks better, two +0.01/+0.02; lo-master-slides 5.02 → 1.62,
eaVertAnchor 2.76 → 1.22, vert_and_padding 1.33 → 0.38,
TextFittingStored 1.74 → 0.97, KEY02 2.46 → 1.98). With the user's go-
ahead, families decks name are drawn in free fonts where one exists:
Poppins and Work Sans in themselves (every weight a deck names — "Poppins
Light", "Work Sans Medium" — loaded under that name), Segoe UI in
Selawik (Microsoft's own free stand-in, loaded as "Selawik Doc"),
Franklin Gothic in Libre Franklin, Courier New in TeX Gyre Cursor (a
Courier, where Liberation Mono is a sans mono), Century Gothic in TeX
Gyre Adventor, Palatino in TeX Gyre Pagella. `SlideFonts.freeFaces`;
the files, sources and licences are in Resources/fonts/README.md and
THIRD_PARTY_NOTICES.md; the web build loads them on demand. Word keeps
its stand-ins; the fonts are there for it if it wants them. The
fonts directory grew from 9.8 to 16 MB.

**Tried and dropped, 2026-10-16:** Courier New's lines at its own
height (1.133 em) rather than 1.2 — tdf149551's three diagrams step at
it at 90%, but the 13 Courier decks went +1.47 in sum (vert_and_padding
+0.68, TextFittingStored +0.45, eaVertAnchor +0.40); 2411's Courier
steps at 1.2. Also left: tdf143222's "Acࢢon" is only its PDF text layer
(the EMF's "ti" ligature by glyph index; drawn right), and
Divino_Revelado's worst pages are blank in PowerPoint's print.

**Hebrew at Times New Roman's and Calibri's own widths, 2026-10-16**
(sweep 154: 1.0996 → 1.088%; tdf98603 5.96 → 4.79, nothing else
moved). PowerPoint sets tdf98603's Hebrew title in Times New Roman and
its quote in Calibri; their Hebrew letters are a fifth narrower than
Liberation Serif's and DejaVu Sans's (alef 0.481 em to 0.600), and our
lines broke a word early. `SlideFontWidths.timesHebrew`/`calibriHebrew`
(U+05B0–U+05F4, from Windows' times.ttf and calibri.ttf) are their
`otherAdvances`; such a character is set at that width on the advance
grid, before the grid's own rounding (shared; only with a grid).

**A 2007-style bar chart's plot as PowerPoint sizes it, 2026-10-16**
(bar-chart 2.27 → 1.52; the other chart decks unchanged). Its plot
starts at 156.4 in PowerPoint's print where ours started at 151.4, ends
3.8 pt higher (390.1, not 393.9) and stands 1.9 pt further right: the
top inset is 7 pt, the bottom 7.8 over the value labels, the gap beside
the category labels 7.9 (were 2, 4 and 6), for a 2007-style chart only.
Its category labels also stand 1.45 pt above their bands' middles, as
its value labels above their lines (1.52 → 1.40).

**A metafile's empty text record fills nothing when the background is
transparent, 2026-10-16** (lo-activex_textbox 4.02 → 0.37,
lo-activex_combobox 0.92 → 0.11; the other 24 decks with WMF pictures
unchanged). An ActiveX control's picture paints its face with an
`ExtTextOut` of no characters, `ETO_OPAQUE` and a box, in the
background colour — green for one of the text boxes — after
`SetBkMode(TRANSPARENT)`. PowerPoint's print fills nothing there; we
filled the box green. Such a record now fills only in the opaque mode
(`Metafile`, shared with Word — told).

**Palatino Linotype at its own widths, 2026-10-16** (aascu 5864 7.92 →
7.89, the one deck PowerPoint printed it in). Liberation Serif, drawing
it, has Times' narrower widths; now Palatino's, and its Windows descent
(613 of 2763) for its baseline.

Tried again and dropped: Calibri Light at Windows' own widths, now
kerned and on the grid — still +2.41 over its 39 decks (bug62736 +0.47,
tdf115394-zero +0.51). PowerPoint's prints here are a Mac's, and its
Calibri Light's lines are shorter than Windows' widths make them.

**A face at its own widths is kerned and on the grid too, 2026-10-16**
(the AES deck 5.91 → 5.58, tdf129686 −0.08, ooxtheme −0.06, KEY02 −0.04,
six more −0.01 or −0.02; pptx2svg +0.02, two +0.01; 51 decks run). Where
the theme has an advance grid (slides), a character set at its face's
own width is kerned as the stand-in kerns, where the run kerns, and
put on the grid, as any other.

**Ten more faces at their own widths, 2026-10-16** (KEY02 4.10 → 2.50,
ooxtheme 1.56 → 0.63, themes 2.01 → 1.72, bnc862510_7 0.90 → 0.64, ten
more a little; n862510_4 +0.02). Segoe UI (and Light and Semilight),
Tahoma, Trebuchet MS, Franklin Gothic Book and Medium, Century Gothic,
Gill Sans MT and Candara, with their bolds where they have one: their
widths for U+0020–U+007E read from the Windows build box's own font
files (`SlideFontWidths`, generated), and the stand-in set at them by
`SlideFonts.face` — replacing the even spacings for Tahoma Bold and
Franklin Gothic. Their Windows descents join `ownDescentShare` for
Trebuchet, Franklin Gothic, Century Gothic and Gill Sans.
Calibri Light's own widths came out worse than its 0.0054 em spacing
(seven Calibri Light decks +0.1 to +0.5): a face set at its own widths
is not kerned nor put on the eighth-point grid here, and Calibri Light
titles are kerned. It keeps the spacing; kerning faces set at their
own widths is the next thing to try.

**A raised run's size is a whole point, rounded up, 2026-10-16**
(pptx2svg 5.15 → 4.98, WithMaster −0.01; the other decks with raised
or lowered runs unchanged). PowerPoint's prints set them at 65% of the
size rounded up to a whole point — 20 → 13, 24 → 16, 28 → 19, 32 → 21,
34 → 23, 11 → 8 — where we set 65% exactly (15.6 for 16).
`RichTextTheme.scriptSizeWholeUp` (shared, off for Word), and the
raise is taken from the run's own size rather than back from 65%.

**Arial Black at its own widths, 2026-10-16** (placeholder-layout-color
0.82 → 0.61, SampleShow 1.30 → 1.19, themes unchanged). It was Arial's
bold spaced 0.07 em a letter; it is now that bold at Arial Black's own
advances (`OfficeFonts.arialBlackAdvances`, Word's), by `SlideFonts.face`.

**Verdana at its own widths in slides, 2026-10-16** (the AES deck 7.53
→ 5.91, pptx2svg 5.44 → 5.15, tdf129686 0.42 → 0.17, aascu 5864 −0.02;
the other Verdana decks unchanged). DejaVu Sans, drawing it, is within
a per cent of its lines on average, but not letter by letter: its space
is 0.32 em to Verdana's 0.35, its letters a little wider. `SlideFonts.face`
now gives Verdana the advances Word already had for it
(`OfficeFonts.verdanaAdvances` and the bold), as Lucida Sans Unicode.

**Text turned by its camera's `rev`, 2026-10-16** (tdf128212,
tdf128213 and its -shaperot twin 0.57 → 0.27 each; tdf128206 0.68 →
0.70). A text body's `scene3d` camera turned about its own axis
(`camera/rot rev`, with `lat` and `lon` nought) turns the text the
other way about the middle of the text as set: rev 90° reads upward
("Vertical it should be!" out of the top of its box), 270° downward.
`SlideShape.textSpin`. tdf128206's turn is right but its middle is
54 pt off along the line: its insets are wider than its arrow's text
rectangle, and how PowerPoint measures the middle of such a box is not
known from one deck.

**Tried and dropped, 2026-10-16:** the squared ramp for every path
gradient of theme colours under modifiers (now blended evenly): themes'
radial background fits it (61 → 5 levels off over its quarters), but
GeomLec1 went 5.74 → 9.15, ImportWordArtGradient +1.31, tdf94238 +0.88
(sweep 140, +5.72 in sum). Across the corpus's 52 sampled ramps
PowerPoint exported, 31 sit nearer the squared curve and 21 nearer an
even blend, with no rule yet for which.

**A gradient of `gamma` stops ramps as PowerPoint's does, 2026-10-16**
(the 45541 trio 6.49 → 6.54 each, the score's colour tolerance hiding
the gain; nothing else has such stops). Their Office 2003 template's
background, title bar and rule are gradients whose stops carry
`gamma`/`shade`/`invGamma`. PowerPoint's export stores them as sampled
ramps, and in sRGB every one holds to its lighter stop and leaves it as
the square of the way along: 205 → 94 is 193, 159, 102 at a quarter,
half and three quarters (a 205 → 22 one 192, 159, 104; a 3-stop
119 → 255 → 119 one 219 at its quarters). Ours, in linear light, ran
177, 150, 122 — the whole background up to 14 levels dark. Now
`SlideFill.squared`, read for any gradient with a `gamma` stop: the
background matches PowerPoint's to a level or two down the page. The
score rises 0.05 because the text's anti-aliased edges now sit on the
lighter blue; the background itself was inside the diff's tolerance.

Built against a snapshot of the engine at bfbfc074 (`SetBaselineShift`,
from the Word session's T48): the shared host_debug/host_release
libraries predate it and no longer link the app.

**A freeform that draws on after closing is not drawn, 2026-10-16**
(lo-cshapes 1.92 → 0.07). LibreOffice writes its accent callouts with a
path that goes `close` then `lnTo`, no `moveTo` between; PowerPoint
draws none of such a shape — not its fill, not its other paths — and
the six were yellow squares here. `FreeformGeometry.parse` now gives
such a shape no paths. No preset and no other deck has the pattern.

**An arc's angles are the ones seen from its centre, 2026-10-16**
(sweep 134: 1.129 → 1.119%, eight decks better, none worse; tdf149918
pie 2.30 → 0.57, tdf144742_funnel 1.46 → 0.00, cshapes 2.39 → 1.92,
tdf125551 −0.26, tdf114848 −0.12). `arcTo`'s `stAng` and `swAng` were
taken as the ellipse's parameter; they are the angles of its points as
seen from the centre, and on a stretched ellipse the two differ (equal
at the quarters, so most presets never showed it). tdf149918's pie,
339° to 90° in a 340 × 227 pt frame, ended its arc 16 pt short of the
bottom, its centre off. Converted now (`FreeformGeometry`, for presets
and freeforms alike); a flat ellipse (no width or no height) keeps the
file's angles — converting them broke tdf103477's brackets.

**A diagram shape showing an author-sized point's text keeps its size,
2026-10-16** (tdf149551_SmartArt_Venn 0.69 → 0.57; tdf145528_SmartArt_Matrix
2.94 → 3.07). A drawing shape is kept from shrinking its text when its
point has `custT`, or the point it belongs to; tdf145528's centre tile
belongs to the document and shows the 72 pt "☺" through a `presOf`
connection, so it was shrunk to 29 pt. Such connections now count.
The Matrix deck scores worse for it: its smiley is the right size now,
but PowerPoint (on a Mac) drew it in Apple Color Emoji, a yellow face,
and ours is DejaVu's outline.

**A diagram node's own resizing, 2026-10-16** (composite-infer-right
3.72 → 2.24; the other 72 diagram decks unchanged). A point's
`custScaleX`/`custScaleY` (the author dragging a shape's size) was not
read: composite-infer-right's picture placeholder is 70.8% of the fifth
its constraint gives it, about its middle, in PowerPoint's print, and
the text beside it stays where the constraint put it. Read now for a
composite's children. Not for a linear layout's (linear-rule's 142%,
the one other deck with one), and `custLinFactNeighborX`/`Y` are not
followed — the box with them in this deck is where its constraints put
it.

**A diagram's text frame turned a quarter in a shape that is not,
2026-10-16** (tdf135953_SmartArt_textposition: "left shape" and "right
shape" now read upward up their boxes' sides, as in PowerPoint's print;
its score is 3.01 either way, the rest being letter edges; the other
ten decks with a turned `txXfrm` unchanged). A drawing's `txXfrm rot`
of 90° or 270° on an unturned shape was dropped, and the text set
level at the frame's unturned place, half off the slide. It is now
laid out along the frame and drawn turned (`textTurn`), in the room the
turned frame covers. (A turned shape whose frame turns back keeps the
upright handling it had.)

Also tried and dropped: a 2007-style chart's top inset 6.5 pt, as its
left and bottom (cooper's plot stands 2.2 pt high in PowerPoint's): six
chart decks worse, +1.66; only for charts with no title, nothing in sum.

**A chart's category names wrap in the plot's slots, centred; and a
chart's own theme fonts, 2026-10-16** (cooper 4.52 → 4.44, aascu 5864
8.08 → 7.99; the other chart decks unchanged). Three things:
the room a category name has is a fifth (an nth) of the plot's width,
not of the chart's — the value labels beside the plot are not the
categories' — so cooper's "African American" breaks in two as in
PowerPoint's print; a broken name centres each of its lines; and a
chart's theme override (`themeOverride`) gives its fonts as well as its
colours — aascu 5864's employment chart, under a master in Lucida Sans
Unicode, is Calibri by its own, and its names had wrapped in the wider
face. Word's charts share the painter, so its pages have the first two.

**A chart's text falls back for characters its face lacks,
2026-10-16** (found by the Word session: zh-37b6536f's pie legend,
机构信息 and the rest, printed as boxes on Linux). Chart text named only
its Latin stand-in; it now carries `RichTextTheme.glyphFallback`, as body
text and metafile text do. The eighteen chart decks are unchanged.

**Tried and dropped, 2026-10-16: baselines on PowerPoint's 0.24 pt
raster.** Each paragraph's first baseline set on the page's 1/300 in
raster (the transform read off the canvas, turned text left alone):
to the nearest step, sweep 119 −0.39 in sum, 31 decks better and 26
worse (table_test2 −0.27; smartart-simple and ArtisticEffectSample
+0.23); rounded down, as PowerPoint's PDFs look to be, +3.92 (67 worse).
Our baselines are not yet within the raster's step of PowerPoint's
often enough for the snap to pay.

**Arial's and Times New Roman's baselines without their line gap,
2026-10-16** (sweep 118: 1.133 → 1.129%, 24 decks better, 13 worse;
alterman 6.12 → 5.57, open-as-read-only 1.38 → 0.85, the 45541 trio
−0.32 each, 2411 −0.18; tdf95932, tdf79082, bnc904423 and
ShapeLineProperties about +0.2 each). Their clones keep the originals'
line gap (Arial's 67 units, Times' 87), and the engine puts a share of
it under the baseline; PowerPoint sets the baseline by ascent and
descent alone. Arial's 43 decks stood a median 0.011 em high and now
stand 0.001. Both are now in `SlideFonts.ownDescentShare`. (The sweep
itself ran Arial alone — a file edited mid-build kept the old binary —
and the table holds the subset run with both for the 118 decks that
have either.) The four decks now worse are single lines that land just
under PowerPoint's: its PDF's baselines are rounded down to a 0.24 pt
raster, and ours, at the true place, are up to 0.24 below it.

**Tried and dropped, 2026-10-16:** Aptos's and Franklin Gothic's
baselines by measured shares (`ownDescentShare` 0.2067 and 0.2264,
fitted to their lines standing 0.020 and 0.044 em low): the fifteen
decks with either went +0.14 in sum (text-highlight +0.08, tdf149785
+0.03). Their offset is not the baseline's place in the line. Also
not followed: HowWeRefactor's Courier at 60% spacing stands 0.1 em
high — PowerPoint has its first baseline at 0.50 em where our rule for
spacing under single gives 0.40; one deck, and the rule holds at 90%.
(2026-10-18: Courier set by its stand-in's own descent share instead,
which gives that 0.48, cost twelve Courier decks +3.92 in sum —
eaVertAnchor +1.92, TextFittingStored +0.79 — for HowWeRefactor's
−0.05. Courier New's own share stays.)

**A cell's runs kerned, 2026-10-16** (55 table decks: cooper 4.73 →
4.54, bnc910045 0.42 → 0.24, table_test2 −0.08, nine more −0.01 to
−0.04; aptia +0.01). A table cell's runs now read `kern` as a text
box's do (PowerPoint's masters say 12 pt), and are kerned on the
eighth-point grid from that size up.

**Tahoma Bold and Franklin Gothic spaced, and a cell's runs too,
2026-10-16** (sweep 113: 1.135 → 1.133%, six decks better, none worse;
bnc862510_7 1.34 → 0.90, table-with-different-font-colors 1.47 → 1.29,
bnc870233_1 −0.12, tdf149785 −0.10). Tahoma's bold, in Liberation Sans
Bold, is set 0.030 em a letter looser (its lines were 5% short);
Franklin Gothic Book 0.032 and Medium 0.024 tighter (6% and 4% long).
The per-face spacing (Arial Black, Aptos, Calibri Light, Consolas and
these) is now one function, `PptxReader.faceSpacing`, and a table
cell's runs take it as a text box's do — tdf149785's Franklin Gothic is
all in a table, and table-with-different-font-colors' cells are Aptos.

**Calibri Light, tightened, 2026-10-16** (sweep 112: 1.146 → 1.135%,
31 decks better and none worse; tdf142648 2.87 → 1.61,
formatting-bullet-indent 2.07 → 1.14, TextFittingStored 2.38 → 1.74,
tdf115394 0.99 → 0.49). Calibri Light, the heading face of Office's
2013–2019 themes, is drawn in Calibri's regular clone, and PowerPoint's
lines in it are 1.2 to 1.6% shorter than ours — the same in all twenty
decks that have it (69 lines; tdf104788 and tdf132282 left out, their
lines differ for other reasons). A run in it is now set 0.0054 em a
letter tighter, in the Slides reader, as Aptos is. A corpus-wide
comparison of line widths by face now leaves Tahoma Bold 5% narrow
(three decks), Franklin Gothic Book 6% wide (two) and HowWeRefactor's
Myriad Pro, which PowerPoint set in Segoe UI, 8% narrow.

**Lucida Sans Unicode at its own widths, 2026-10-16** (sweep 111:
1.152 → 1.146%; GeomLec1 7.22 → 5.74, aascu 5864 8.40 → 8.11, KEY02
4.31 → 4.10 from the baseline entry below; n862510_4 and numfmt +0.01).
Liberation Sans, drawing it, is 9% narrow, and GeomLec1's lines broke a
word late. A slide's runs in it are now set at the face's own widths,
the table Word already had (`OfficeFonts.lucidaSansUnicodeAdvances`),
its made-up bold and italic as wide as the regular: `SlideFonts.face`
is the slides' `faceResolver`, and `RichTextTheme.setsFaceAdvances`
(shared, off by default) lets those widths apply outside Word's rules.
Tried before as one extra spacing for every letter (dropped: GeomLec1
worse) — per letter, and with its baseline right, it is a point and a
half better. GeomLec1's first paragraph now breaks where PowerPoint's
does; its bold (PowerPoint's is lighter) and a line with ⇒ still differ.

**A baseline by the face the text names, 2026-10-16** (GeomLec1 8.16
→ 7.22, the AES deck 8.10 → 7.54, aascu 5864 8.56 → 8.40, two more a
hundredth; none worse). PowerPoint sets a line's baseline by the
proportions of the face it names — its Windows ascent and descent —
and we set it by the stand-in's. Where that is a metric clone (Calibri,
Arial, Times, Courier New) the two agree, and Calibri's 2,843 lines
compared stand a median 0.001 em off PowerPoint's. Where it is not,
they did not: Verdana in DejaVu Sans stood 0.039 em high, Segoe UI in
Calibri's 0.047, Tahoma in Liberation Sans 0.032, and Lucida Sans
Unicode 0.10 low. `RichTextTheme.ownDescentShare` (shared, nil and so
off for Word) now gives the named face's share below the baseline for
those four (`SlideFonts.ownDescentShare`), and the paragraph is drawn
that much lower or higher. HowWeRefactor's Segoe UI is unchanged: its
file asks for Myriad Pro, which PowerPoint's machine set in Segoe UI.

Found on the way, and not followed: 90% of the baselines in
PowerPoint's PDFs lie on a 1/300-inch grid (0.24 pt) from the page's
top, floored (chance would put 4% there); ours lie anywhere. Our lines
are mostly further off than the grid's step for other reasons, so
snapping would gain little yet, and the engine sets a paragraph's lines
together, so it would mean drawing each line on its own.

**A 2007-style chart's plot stands further from its legend,
2026-10-16** (radar-chart 2.01 → 1.74, bar-chart −0.07, scatter −0.02;
aascu 5864 +0.04). The four 2007-style charts (style 2, legend at the
right) end their plots 5.3 pt short of ours, every one, the legend where
ours is: the gap to a right-hand legend is 17.3 pt for them, not 12.
Pies and the newer charts keep 12 (pie-chart and tdf149985 were 0.26
and 0.58 worse with it). Their plots also start 2.6 pt further off the
value labels (line- and scatter-chart's at 152.3, the labels where
ours were): the room is 11.1 pt there, not 8.5, the labels kept in
place (line-chart 2.05 → 1.82, cooper −0.06). And their value labels
stand with their middles 1.45 pt above their gridlines (line- and
scatter-chart −0.04 each); the newer charts' measure the same but came
out a hundredth or two worse raised, and are left on their lines. The bar chart's plot is
also 5 pt shorter at the top and 3.8 at the bottom — not yet followed.

**A diagram shape's one adjustment, 2026-10-16** (smartart-children
3.42 → 3.15, cycle-matrix 2.61 → 2.34, accent-process −0.21,
autofit-sync −0.20, smartart-text −0.20, composite-infer-right −0.18,
missing-bullet −0.14, cnt −0.13; none worse). A layout's `dgm:adj
idx="1"` went to the shape as `adj1`, which a preset with a single
adjustment — the rounded rectangle's corner, `adj` — never reads: every
diagram rounded rectangle had the default corner, two-thirds again as
round as the 0.1 the layouts ask. The first is now given under both
names.

**Kerned where the run says so, on the grid, 2026-10-16** (sweep 108:
the decks' means 5.74 lower in sum; font-scale 5.47 → 3.39, pptx2svg
6.70 → 5.44, 3columns −0.45, 60810 −0.42, cooper −0.21, fifteen more;
tdf95932 +0.13). A run's `kern` (kerning from that size up, hundredths
of a point — PowerPoint's own masters say 1200) is read into
`CharStyle.kerningFrom`, and the advance grid then snaps each
character's advance kerned with the next one (`_pairAdvance`) where the
run kerns at its size. Without it the grid's one-span-a-character had
dropped kerning everywhere.

**Glyphs on an eighth of a point, 2026-10-16** (sweep 107: 1.17 →
1.17%, the sum of the decks' means 3.13 lower; aptia 2.99 → 2.21,
alterman 6.49 → 6.15, Performance_Up 2.89 → 2.59, bnc904423, tdf169524,
ShapeLineProperties and 60810 −0.3 each, 22 more by over 0.05;
thirteen further by 0.05 to 0.3 — 3columns, font-scale, pptx2svg the
most). PowerPoint's print sets each glyph's advance on an eighth of a
point: Arial's "d" at 32 pt, 17.797 wide, is set 17.75, its "S" 21.344
→ 21.375, its hyphen 10.656 → 10.625, every letter of Performance_Up's
"Swap is disk-based Extension of RAM" so; the line came to 540.2 pt in
a 540.6 column where ours, at the faces' own widths, was 0.4 too long
and wrapped "RAM" (60810's "PROGRAMMES/R200" title the same way). The
shared layout has a switch for it, `RichTextTheme.advanceGrid`
(points; nil, the default, leaves the faces' widths), on at 0.125 for
slides: each Latin character's width snapped by the spacing after it.
(Characters so set are spans of their own, so kerning goes — which
PowerPoint applies only where a run's `kern` says so.)

**A face PowerPoint lacks is Calibri, 2026-10-16** (sweep 106:
tdf168835 0.58 → 0.21, master-slides 5.23 → 5.01, bug65228 0.37 → 0.19,
tdf119187 0.47 → 0.29, tdf147586 1.12 → 0.95, Divino −0.07, tdf140852
−0.06, three more a little; n862510_4 0.30 → 0.42, tdf98603 +0.06). The
shared stand-ins set a name they do not know in the Cambria clone —
Word on a Mac's rule (2026-10-15). PowerPoint, printing a face its
machine lacks, uses Calibri: tdf168835's "Marianne", bug65228's
"Graphik", tdf119187's "BentonSans" are Calibri in its prints. Slides
now resolve faces through `SlideFonts.resolve`, which does that and
otherwise defers to the shared rule. Tried on the way and dropped: such
a name in Liberation Sans (the faces PowerPoint had — Work Sans,
Poppins — no nearer), and in it only when the file declares the face a
sans (`pitchFamily` 34: "Myriad Pro" and "Open Sans" are Segoe UI in
PowerPoint's prints), which left HowWeRefactor 0.10 and tdf98603 0.23
worse; and a weight of a known face ("Segoe UI Light") as that face
(n862510_4 0.46).

**Palatino Linotype is a serif, 2026-10-16** (aascu 5864 8.71 → 8.66,
its "Excellence with Equity" page 16.8 → 15.4). The shared stand-ins
listed "palatino" with the serifs but not "palatino linotype", Windows'
name for it, which fell through to the sans; it now goes with Palatino
(Liberation Serif, narrower than Palatino — P052, its metric clone, is
on this machine but not bundled). No Word document in the corpus names
it.

**Gradient-filled text outside WordArt, 2026-10-16** (tdf114848 4.00 →
3.75, n862510_4 0.35 → 0.30; the other sixteen decks with such runs
unchanged). A run's `a:gradFill` is drawn as a gradient only in WordArt
(its run looks); in any other text it fell to no colour — black — where
PowerPoint's "Word Art Perspective" is red. Such a run now takes the
gradient's middle colour (`SlideFill.colorAt`, halfway). Still not
drawn there: a run's own outline (`a:ln`), which makes tdf114848's
12 pt red footer read white in PowerPoint's print.

**Looked at and left, 2026-10-16:**
- Bevels (`sp3d bevelT`) are not drawn. Fifteen decks have one
  (60810's twenty, customGeo's, aascu 5864's, GeomLec1's, HowWeRefactor's
  among them), and PowerPoint prints each such shape as a picture: on
  customGeo's diagram headers a 10 pt band lit along the top and right,
  shaded along the bottom and left, the face itself a little brighter
  (79,129,189 → 82,132,199 under `chilly` and `translucentPowder`). The
  fifteen use eight rigs (flat, threePt, chilly, glow, soft, twoPt,
  contrasting, balanced, brightRoom) and five materials, most bevels 1
  to 2 pt: too many unknowns to model from one measured case.
- PowerPoint's own stand-ins: tdf147586's "Open Sans" (absent on the
  printing machine) is Segoe UI in its print; ours is the unknown-face
  Cambria clone. One deck; the general "unknown → sans" was tried and
  dropped above.

**Latin text parted at spaces and hyphens, 2026-10-16** (sweep 103:
tdf149551_SmartArt_Pyramid 1.33 → 1.18, _Gear 0.57 → 0.45, _Pie 0.59 →
0.51, cooper 5.16 → 5.11, customGeo 4.24 → 4.22; none worse).
PowerPoint parts Latin text where Word does — at spaces and after
hyphens — and not after a slash or a closing bracket, where the engine
may by Unicode's rules: customGeo's ".../knowledge-" breaks at the
hyphen, its "articles/#articles-by-…" stays whole. Word's rule
(`_joinsLatin`, word joiners where the engine would part) is now its
own switch in the shared layout, `RichTextTheme.officeLatinBreaks`, on
for slides; `wordRules` implies it, so Word is as it was. (60810's
"PROGRAMMES/R200" now moves down whole, but the line is still 0.4 pt
too wide to stay up.)

**A table cell's numbers, 2026-10-16** (customGeo's crosswalk slide).
A numbered paragraph in a table cell showed "1." whatever its
`startAt`: the runs of numbers (`_numberRuns`) were worked out for a
shape's text only. Each cell now numbers its own paragraphs, under list
names of its own, so customGeo's six cells count 1 to 6 as PowerPoint's
do.

**A text block centred across its box (`anchorCtr`), 2026-10-16**
(eaVertAnchor 3.28 → 2.79, tdf165261 −0.11, tdf165341 −0.09,
tdf149551_TextRot −0.05, slide-section-test −0.04, vert270AndTextRot
−0.03; fifteen decks say it, none worse). `bodyPr anchorCtr` was not
read. The text is now a block as wide as its widest line, centred
across the box, its lines aligned within the block — hanging out both
sides alike when wider; for vertical text, which is laid out in the box
turned, that centres it down the box (eaVertAnchor's lower row, whose
columns started at the box's top). Written back on save.

Also looked at and left, 2026-10-16: minimal-gradient-fill-issue's two
stops at one position — PowerPoint holds the first colour to 50% and
then blends to the second by 100%, but shows the second flat when both
are at 0, not a rule to build on from one deck; bug54570's metafile
chart, whose bars PowerPoint's PDF strokes with a 0.025 pt black line
though the file selects the null pen (an export artifact, not drawn).

**PictureStrips: the strips' shape, and their pictures, 2026-10-16**
(smartart-picture-strip 3.33 → 4.40, though now laid out as
PowerPoint's; snake-rows 1.09 → 1.03). Two faults. A snake chose its
grid by items in the frame's proportions, not their own: PictureStrips'
composite says `ar` 3 (three times as wide as tall), and sized as the
frame two fitted across with the third below, where PowerPoint stacks
the three in one column — they now are. And a diagram laid out here
from its data (no drawing part) looked its points' pictures up among
the slide's relationships, not the data part's, so the numbered tabs
(`blipFill`, its `fillRect` 25% past each side) were drawn as nothing.
The score reads worse because the wrong layout happened to cover more
of PowerPoint's ink; what is left is PowerPoint's strips a little
smaller with closer gaps (item 116 pt, gap 17.6, where the rules give
121 and 32) and its text 73 pt into the strip where `lMarg` = 0.6 w
gives 209 — not derived from this one deck.

**Banded columns, 2026-10-16** (table-with-different-font-colors 1.48
→ 1.47: its second slide's text colours and second column's fill now
PowerPoint's). `bandCol` was not read. The style's `band1V` and
`band2V` now take turns across the columns, counted from the one after
an emphasised first column; their text colour (the cyan third column),
and their fill unless the rows are banded too, whose bands PowerPoint
draws over them. The only deck that asks.

**A 3-D column chart's box, 2026-10-16** (LIBRE_OFFICE-100610-0 2.67
→ 2.04, aascu 5864 8.83 → 8.71, its census slide 25.6 → 21.6; the only
two decks with `c:bar3DChart`). A 3-D bar or column chart now stands
in a box one category deep (`depthPercent`), its floor and walls
running back up and to the right by the view's angles — aascu's 9.5 pt
across and 7.5 up, its categories 28 pt apart, in PowerPoint's print:
the floor's outline drawn, the value gridlines along the side wall and
across the back, the bars a `1 + gapDepth` share of the depth in its
middle, their labels over their fronts. The plot is the box's front,
the room behind it taken from the area. Each bar's depth had been its
own width, and the gridlines flat. (PowerPoint's gridlines there are
mid-grey; the 2-D charts' light grey is kept — darker lost before.)

**Tried and dropped, 2026-10-16:**
- The built-in body style (a master with no `p:txStyles`) hung half an
  inch less a quarter — `marL` 18 pt, `indent` −18 — as Office's own
  master does: subtitle-animation-save's text stands 18 pt in, after its
  bullet, in PowerPoint's print (0.67 → 0.52). But tdf160487's subtitle,
  `buNone` and `indent="0"` under the same built-in style, is not moved
  in by it (0.70 → 2.03): no one rule fits both.
- A radial gradient's ramp: PowerPoint's print stores a sampled colour
  function, not the two stops, and themes' 1003 background darkens with
  the square of the distance (r², to a point, along the diagonal and
  across) where ours runs evenly; but tdf114848's three-stop circle
  runs the other way (lightens early) and GeomLec1's matches ours. Five
  decks have radial shadings; left.
- 60810's "CONNECTION TO GLOBAL TALENT PROGRAMMES/R200" title wraps
  after the slash: Carlito's kerning leaves the line 0.4 pt wider than
  Calibri's (548.0 to 547.6) in a 547.7 pt box.

**A diagram's turned text, by autoTxRot, 2026-10-16**
(smartart-rotation 6.20 → 6.08, autoTxRot 2.59 → 2.61; every letter
on autoTxRot's three pages now at PowerPoint's angle). The text
algorithm's `autoTxRot`: "upr", the default, turns text whole quarters
back to within 45° of level, half-way rounding to the even quarter (135°
reads at -45°, 225° at 45°); "grav" turns only text past 90° and short
of 270° the other way up; "none" leaves it with its shape. We had
turned head-down text a half round and quarter-turned text upright,
whatever the setting — smartart-rotation's 120° and 240° arrows read at
-60° and 60° where PowerPoint's read at 30° and -30°.
What remains there is the ring: PowerPoint's three arrows stand 0.676
of their width from the centre, ours 0.375 (chord = width + sibSp,
-0.35 of it); autoTxRot's sixteen at 2.685 of theirs. Neither the
spacing taken as 0 nor the arc between centres as the diagonal fits
both, so the ring is left as it is.

**A diagram line keeps its spare room, 2026-10-16**
(smartart-vertical-box-list 5.88 → 0.19, smartart-linear-rule-vert
3.97 → 0.11; the other 71 diagram decks unchanged). A line no longer
shares the room it has to spare among the children a rule lets grow
without bound (`rule type="h" val="INF"`, `constr val="INF"`): that
rule is leave to grow for text, and PowerPoint sets list1's one short
item at its constraints — the box 0.82 × 65 mm, the body 0.7 × 65,
overlapping by half the box — centred in the frame, where we had
stretched both to fill it.

**Tried and dropped, 2026-10-16:** an unknown face (Work Sans,
Poppins) set in Liberation Sans again on slides rather than in the
Cambria clone the shared substitution now gives every name it does not
know (Word on a Mac's rule, 2026-10-15). Eight decks moved by under
0.2 either way and tdf140852 went 4.28 → 4.47: a sans of the wrong
width is no nearer than a serif, so the slides keep the shared rule.

**Medium Style 1, and a table's text size, 2026-10-16**
(tdf135843_insideH 4.36 → 0.02; the other 55 table decks unchanged).
The deck names PowerPoint's built-in Medium Style 1 without defining
it, and was drawn with no rules at all: it is now among the built-in
styles (dark rules round the table and between rows, none between
columns). Drawn, its empty rows stood taller than PowerPoint's: a
table's text takes the master's other-text style before the
presentation's default (10.13 pt here, where the default says 13.5).

**Pictures smoothed when enlarged, 2026-10-15** (tdf146223 37.40 →
31.38, tdf93830 4.39 → 1.30, tdf157793 2.51 → 0.00, tdf157635 2.26 →
0.00, tdf123684 0.69 → 0.25, croppedTo0 2.25 → 1.87, tdf153466 0.38 →
0.03; oox-graphic-stroke +0.06). PowerPoint marks a picture
`/Interpolate true` in its PDF when it is drawn larger than its pixels
(183 of the 187 such in the reference prints; 4 of 3377 drawn smaller),
so a viewer smooths it; Skia's PDF backend never does, and a 16-pixel
icon an inch across printed as blocks. The slide export now marks every
picture after writing (one classic cross-reference table, rewritten),
which changes nothing for one drawn smaller. Slides only: Word's and
Sheets' PDFs are as they were.
tdf146223's remaining gap is PowerPoint's own decoding: its 2×2 JPEGs
come out one flat colour (re-encoded flat in its PDF), where every
decoder here gives four pixels; neither their average nor the DC term
alone fits both pages (35 for a grey whose four are 0, 57, 32, 92).

**Hebrew in its own face, 2026-10-15** (tdf98603 6.14 → 5.92,
tdf125085 WordArtFontText 3.12 → 2.85; nothing else moved). Hebrew,
Arabic and Thai letters are set in the run's `a:cs` face, else the
theme's complex-script face, else the theme's face for that script
(`a:font script="Hebr"`), as PowerPoint sets them; spaces and
punctuation go with the letters before them. They were all in the
Latin face, which has no Hebrew, so they fell to DejaVu Sans. tdf98603's
title still wraps where PowerPoint's does not: Liberation Serif's Hebrew
is 12% wider than Times New Roman's (717 pt to 642 for the line), a
missing face, not tuned for.

**A chart in its own slide's theme font, 2026-10-15** (aascu cooper
5.26 → 5.16, aascu 5864 −0.02; the chart decks otherwise unchanged).
A chart that names no face was drawn in the deck's first master's body
font; on a slide whose theme is another's, PowerPoint uses that theme's
(cooper's census chart in Verdana, aascu's in Calibri, both drawn in
Liberation Sans here). Measured with a corpus-wide comparison of line
widths by face, which also showed Consolas 8.7% wide in Liberation Mono
(one fuzzed deck) and Lucida Sans Unicode 9% narrow (two decks; DejaVu
tried before and dropped).
Consolas is now set 0.05 em tighter, its own 0.55 em advance
(clusterfuzz 4986 3.27 → 3.20). The same for Lucida Sans Unicode
(+0.052 em, bold +0.022) was tried and dropped: its own deck,
GeomLec1, went 8.12 → 8.23 while aascu 5864 gained 0.07 — that
deck's gap is not line width.

**A chart's gaps, from PowerPoint's own, 2026-10-14** (chart-slide-bg
4.39 → 2.35, chart-texture-bg 4.35 → 2.27, chart-picture-bg 4.40 → 2.69,
tdf112089 3.40 → 1.81, tdf114821 1.43 → 0.97; line-chart, tdf149985 and
chart-theme-override +0.1 or less). Matching every line of text on our
pages with PowerPoint's (median offset over 89 decks: 0.25 pt) put
these four decks' chart text 2.4 pt low and 2.1 pt to the left, all of
it. The default chart's gaps are now read off chart-slide-bg's page:
title to plot 3.6 pt, plot to its category labels 7.6, labels to the
legend 8.4, the legend 1.2 above the chart's margin, value labels 8.5
left of the plot — where they were 6, 4, 6, 0 and 6.

**Tried and dropped, 2026-10-14**, so they are not tried again blind:

- **Lucida Sans Unicode as DejaVu Sans** in Slides (1.3% off its widths,
  where Liberation Sans is 11% narrow): GeomLec1's regular lines then
  break where PowerPoint's do, but its bold and italic — which Lucida
  Sans Unicode synthesizes — are far narrower than DejaVu's own, and
  those lines broke worse. 1.7561 → 1.7586%; GeomLec1 8.15 → 9.31.
- **Half a point of slack on a body's wrap width** (2411's "…Extension
  of RAM" fits PowerPoint's box with 0.4 pt to spare and wraps here):
  39 decks worse at 0.5, 77 at 1.0. Our widths are right in general.
- **lo-tdf137367's 150% lines** stand 7.3 pt higher in PowerPoint with
  the same pitch; five other decks at 150% line up to a quarter point,
  so it is that deck (a subtitle under `normAutofit`), not the rule.
- **Picture bullets** were read as markers not drawn — drawn now, below.
- **The size of smartart-rotation's arrows, accent-process' and
  vertical-box-list's boxes**: PowerPoint's are about 0.7 of ours,
  sized from a smaller font than the frame allows; the reason is still
  not found (see accent-process above). Measured exactly 2026-10-18 (the
  arrows' paths, rotated, fitted to PowerPoint's bounding boxes): in a
  480 × 320 pt frame its three arrow5 arrows are 159.8 pt — a third of
  the frame's width — their ring 106.7 in radius, two thirds of an
  arrow, centred 296.7 pt down (the top arrow's top on the frame's).
  Neighbours stand 1.155 arrow-widths apart: the layout's `sibSp` of
  −0.35 of a node (which ours follows, overlapping them, 205 pt each)
  is not what PowerPoint did here.

**The corpus in two groups, 2026-10-11.** `test/corpus/pptx/matched*.txt`
lists the decks this app draws exactly as PowerPoint does (every page
0.00%: 59 of 553 by MuPDF at sweeps 31 and 32) and `others*.txt` the rest;
`test/pptx-corpus-groups.py` writes them from the baselines, and
`CORPUS_GROUP=matched test/pptx-app-render.sh WORK` sweeps the first in
under a minute and fails if one of them no longer matches. Lists, not
folders: a deck changes group without a file moving.

The branch: this work is on `office` (fast-forwarded from `sheets`,
which is kept level with it), rebased over the Writer session's
commits. Where the two met, Writer's model won and Slides reads into
it — `TableStyle.rowHeights`, `CellRef.verticalAlign` (which the layout
now applies, for Writer too), `CharStyle.caps` — with what PowerPoint
needs beyond it added beside: a cell's own margins, text direction and
coloured edge lines.

**S1 done 2026-09-30**, seen on screen through `test/slides-drive.py`:
Backstage offers Blank document and Blank presentation and the window
switches kind; a deck opens on a 16:9 title slide with the ribbon's
Slides tabs, a live thumbnail pane, the slide canvas zoomed to fit, and a
notes pane; placeholders show their prompts and take typing at the
layout's size and anchoring (60 pt bottom-anchored title, bullets in the
body); New Slide, the layout menu (text carried by role), Duplicate,
Delete, arrow keys between slides, 4:3/16:9, and Insert → Text Box.
Writer is unchanged (its driver run and bench are as before).

**S2 done 2026-09-30**, on screen through the `shapes` step: the shapes
gallery (rectangle, rounded rectangle, oval, triangle, arrow, line, star,
callout) from Insert and Home; click to select, drag to move with smart
guides (slide edges and centre, other shapes' edges and centres), eight
handles to resize (the opposite handle pinned, rotation included), a
rotation handle that settles on right angles, marquee selection (what it
wholly contains), Arrange (front/back/forward/backward, six aligns),
Shape Fill and Outline, a second click on a selected shape types into
it, Esc leaves the text with the shape selected, arrows nudge, Delete,
⌘D, ⌘C/⌘X/⌘V of shapes, ⌘A, Tab through shapes. Undo is the deck's, by
snapshot; a text-editing session folds into one step when it ends, and
⌘Z while typing undoes the typing first.

**S6 part 1 done 2026-09-30** — themes, backgrounds, pictures. Six
themes of our own (Starling, Slate, Paper, Ocean, Forest, Sunrise) in the
Design tab; applying one restyles placeholders, theme-coloured shapes
(their accent slot travels in the file as `schemeClr`) and text that
followed the old theme, and from then on the deck is written with our
master, layouts and theme (a gradient theme's master paints it) while
kept objects still come from the file; one undo step. Format Background:
theme, colour, two gradients, a picture, Apply to All — written as solid,
`gradFill` or `blipFill`. Insert → Pictures places a picture at its
natural size within the slide; the Picture Format tab resets it or crops
it to an aspect (inside its box). Tables are part 2.

**Corpus round, 2026-10-01.** Apache POI's 95 `.pptx` test files (real
PowerPoint decks from bug reports, plus fuzzer cases), each read, saved,
re-read and checked, then slide 1 and the middle slide drawn by Quick
Look before and after. Every healthy file now round-trips; the nine
fuzzer files fail cleanly (no crash, no hang) or are salvaged; visible
render differences went from 25 of 118 to 18, the worst from 42 to 15
(of 255). Found and fixed:

- **A shape's `p:style` was dropped**, and with it every fill, line and
  text colour a shape takes from its style — boxes saved see-through,
  white titles saved black. The reader now resolves fillRef/lnRef for
  every kind of shape and fontRef over the layout's and master's colours;
  the writer keeps the style, and keeps the file's own fill, line and
  effects (gradients, patterns, picture fills, shadows) while the shape's
  fill and outline are unchanged.
- **Exact line spacing (`spcPts`) became a multiple of the paragraph's
  default size**, so lines overlapped once runs were larger. The paragraph
  model gained `lineHeightPoints` (the layout makes every line exactly
  that tall), read and written as points.
- **Bullet positions were recomputed**: a file's own marL and indent now
  come back as read (indentLeft and firstLineIndent carry them relative
  to the shape's list indent; new lists are written as before).
- **Turned or mirrored groups lost their turn** when flattened: they are
  now kept whole (drawn as a labelled box, written as read).
- **Autofit text boxes lost `normAutofit`** (S8 regression): a text box
  that shrinks its text says so again.
- **A zip with its end cut off would not open** (no central directory):
  the reader now salvages every complete entry from the local headers, as
  PowerPoint and Word repair; a package so damaged that it has no master
  with a layout is saved on our templates, and kept objects drop
  relationships to parts the file does not have.

Left: bullet colours (`buClr`) are not modelled; Quick Look shows small
wrap and bullet-gap differences on ~15 slides.

**S8 done 2026-10-01** — dark mode, resize, keyboard. On macOS the app
now follows the system appearance (it was always light) and changes with
it; `OFFICE_DARK=1`/`0` overrides it. Slides' chrome darkens and slides
stay as designed; Writer's page now stays white in dark mode, its chrome
dark — a dark page had made colour-styled text (the Title's navy) vanish.
Shrinking the window to 760×560 refits the slide and keeps the panes; the
ribbon clips its last groups there, as Writer's does. Keyboard: F6 goes
slide → notes and from the thumbnails to the slide, ⇧F6 to the thumbnails;
F5/F6 now work with a shape selected (the selected-shape keys used to
swallow them, so F5 did nothing while a shape was selected). Tab, Return,
Esc, arrows and Delete already covered shapes and slides. Spelling in
boxes and notes was already on (both editors take the checker).
Left for later: KeyTips (Alt-letters into the ribbon) — the ribbon is
mouse-only; the Heading previews in the style gallery are low-contrast
in dark mode (Writer's ribbon).

**S8, recovery copy and AutoSave, 2026-10-01.** As Writer: two seconds
after the last change a deck writes `name.pptx~` beside itself (an
untitled one under the recovery directory), or with AutoSave on the file
itself; saving removes the copy; opening a deck whose copy is newer loads
the copy, unsaved, and says so; the first launch restores an untitled
deck left unsaved. `OFFICE_RECOVERY_DIR` moves the untitled copies — the
test drivers set it, after a driven Writer opened the user's own untitled
document's copy (the "nihao shijie" screenshot of 2026-09-30 was that,
not the user's window).

**PowerPoint round, 2026-10-03.** Microsoft PowerPoint (16.113, on the
Mac) is now the oracle, driven by `test/pptx-powerpoint.sh DIR`, which
opens every deck in a folder and reports whether PowerPoint asks to
repair it. Our own decks (`--deck-sample`, `--deck-showcase`: every
layout, all six chart kinds with labels and axis titles, header and
footer fields, a hidden slide, a fade) open clean and PowerPoint's own
PDF export draws them as designed. The 92 saved corpus decks: 81 opened
clean, 11 asked for repair — 8 of them real decks, all fixed; the other 3
are fuzzer-damaged files that PowerPoint repairs *before* we touch them
(controls). Neither `pptx-check.py` nor Quick Look had caught either
bug, which is why the oracle exists:

- **A legacy OLE object lost its drawing.** `p:oleObj spid="_x0000_s…"`
  draws through a shape in the slide's VML drawing part, reached by a
  `vmlDrawing` relationship nothing in the slide XML names — so the
  r:id remap kept the embedding and dropped the drawing, and the slide
  needed repair. The writer now carries that part (and its images)
  whenever a kept object still contains an `oleObj`. Six decks.
- **Audio and video were read as pictures.** A media shape is a `p:pic`
  (the poster frame) with `a:audioFile`/`a:videoFile` and `p14:media`
  on its `p:nvPr`, played by the slide's timing tree. Modelled as a
  picture, the media relationships went while the kept `p:timing` still
  called them. The reader now keeps such a `p:pic` whole. Two decks.
  `pptx-check.py` learned that PowerPoint itself writes
  `<a:hlinkClick r:id="" action="ppaction://media"/>` there.

Also in this round (uncommitted since 2026-10-01): a master's
placeholders are always typed (title/body — PowerPoint repairs a master
with an untyped one), a usable master needs its theme part too, a macro
project and relationships to missing parts are left behind, and the
saved file is always a plain presentation content type.

Driving notes: PowerPoint's scripted PNG export returns without error
and writes nothing; `save … as save as PDF` works, rasterise with
PDFKit. The sandbox grants read access for a Launch Services open
(`open -a`) but not always for an AppleScript `open` of an untouched
file (a "Grant File Access" dialog, which also precedes any save into a
new folder — grant it once per folder, under `$HOME`). PDF export skips
hidden slides.

**Text shapes kept verbatim, 2026-10-03.** PowerPoint's own render of
`45541_Header` showed two losses a repair prompt never would: the title
slide's text boxes lost their centring, and the cyan Wingdings bullets
became plain Arial dots. Both were the rewrite path spelling out what
it had resolved — and resolving the first one wrong: a text box on a
slide takes the presentation's `defaultTextStyle` (`algn="ctr"` in that
deck) over the master's `otherStyle` (`algn="l"`), which the reader had
the other way round. Fixed in the reader, and then the house pattern
applied to text shapes as it already was to tables, charts and
connectors: every shape read from a file carries its XML plus a
`ReadShape` snapshot (kind, frame, rotation, fill, outline, anchor,
insets, autofit, field), and the writer emits the original while the
snapshot and the text are unchanged — so the master's bullet glyph,
colour and size, run shadows, tab stops and `spAutoFit` all survive
untouched. Any edit (typing, a move, a recolour) drops the shape onto
the explicit path as before. Round-trips are byte-identical per shape
up to attribute order; the corpus gate (86 ok) and the 92 package
tests are unchanged; PowerPoint draws the deck exactly as the original.
`test/pptx-corpus.py` also falls back to its cache when GitHub's
listing is unreachable (a connection reset had aborted a run).
The one deck the verbatim path regressed was `Divino_Revelado`, a
truncated file we salvage: its shapes play a click sound whose `.wav`
was cut off, and the kept-XML remap turned `<a:snd r:embed="…">` into
`<a:snd name="hammer.wav"/>` — no reference, schema error, repair
prompt. An element that is nothing but its reference (`a:snd`,
`a:audioFile`, `a:videoFile`, …) is now dropped when its part is
missing. Bisecting a repair by repacking slide hybrids with `zip -r`
does not work: the repacked *unmodified* tree repairs too, so every
hybrid reads as guilty — diff the XML instead.

**In the browser, 2026-10-03.** Slides builds and runs in the web
build of Office (`build/web-app.sh OfficeApp --package apps/OfficeApp
--serve`): new deck, open and save `.pptx` through the picker and
downloads, charts, the show. What it took is in docs/plans/wasm.md
("Slides runs in the browser too"); the one Slides-wide change is that
dates come from `SlidesDates` (no DateFormatter), natively as well.

**LibreOffice corpus, and PowerPoint as the renderer, 2026-10-08.** The
corpus grew from POI's 95 decks to **561**: LibreOffice's `sd/qa/unit/data/pptx`
(403 real regression decks, as `lo-*`) and `oox/qa/unit/data` (63, as
`oox-*`), fetched by the same `test/pptx-corpus.py`. And the pixel gate is
now PowerPoint's own drawing, as the user asked: `test/pptx-powerpoint-render.sh
IN OUT WORK` has PowerPoint export the original and our saved copy to PDF
(`test/pptx-powerpoint-pdf.applescript`, repairing when asked and saying so)
and `test/pdf-diff.swift` scores every page — a PowerPoint-vs-PowerPoint
difference is ours to explain, where Quick Look's was often Quick Look's
(and `qlmanage` hangs on some LibreOffice decks besides). WORK must be the
one folder PowerPoint's sandbox was granted (`~/starling-ppt-check`): a
subfolder made later is a new folder and blocks the export behind a "Grant
File Access" dialog that looks like a 120 s hang.

Headless, before fixes: 538 of 561 round-tripped and checked clean. In
PowerPoint, 44 of 550 rendered decks differed from their originals, 3 copies
needed repair (two fuzzer controls and a file missing its own layouts).
After: **552 clean headless** (the rest are the originals' damage — Divino
truncated, tdf169781's missing layouts, fuzzers), **545 of 550 identical in
PowerPoint**, and the 5 left are two fuzzer files, Divino, tdf169781 and one
1% group. Found and fixed, in order of pixels:

- **Pictures were regenerated from the model**, so everything the model
  does not hold vanished: a blip's recolouring (`a:clrChange` making an
  EMF's white transparent — a black page turned white, tdf113163),
  transparency, greyscale and black-and-white effects, a flip
  (mirrored-graphic), a crop to a shape (crop-to-shape, a rounded rect, a
  triangle), a fill or outline behind the picture (tdf163803), and the
  `useLocalDpi` and `bwMode` details. A picture read from a file now keeps
  its element (`KeptPicture`: image, crop, turn) and is written back
  verbatim at its frame while those are unchanged, like text shapes,
  tables and charts already were.
- **`showMasterSp="0"` was dropped**, so a slide that hid its master's
  shapes got them back over its own background (themes slide 7, aascu
  slide 7, tdf146223's pink page gone dark). Read, kept on the slide,
  written.
- **The slide's `p:clrMapOvr` was replaced** by `masterClrMapping`, so a
  slide swapping bg1 for dk1 lost its black page (chart_pt_color_bg1).
  Kept as read and written back; the reader also applies the override (and
  the layout's) to its colour map, so the app draws it right too.
- **A placeholder picture with `<p:spPr/>`** (its frame the layout's) was
  dropped on read: the inherited placeholder's frame is used now (layouts
  slide 9, customshape-bitmapfill-srcrect).
- **A group's own fill** (`p:grpSpPr` solidFill, which members say
  `a:grpFill` for) and its `hidden="1"` were lost when the group was
  rebuilt (tdf104201's green boxes with white text, tdf131082,
  hidden_group_shape). Carried on `ShapeGroup`, written back.
- **A group with a zero `chExt`** was flattened unmapped, leaving members at
  child-space coordinates (tdf136830): kept whole now, like a turned group.
- **Custom shows** listed slides by relationship ids the save renumbered
  (four tdf decks needed repair): remapped, emptied shows dropped.
- **Transition and animation sounds** (`p:snd`, `p:sndTgt`) kept their
  `r:embed` but not the relationship or the .wav: kept XML now goes through
  the same remap as shapes.
- **Carried media had no content type** when the source typed it by
  extension (video.avi, bnc591147): the Default comes along, and common
  audio/video extensions have one of our own.
- `pptx-check.py` no longer counts an id repeated only across
  `mc:AlternateContent` Choice and Fallback as a duplicate (six false
  failures).

- **ActiveX controls (`p:controls`) were dropped** — 13 decks. Kept as
  read and written back with their parts (`activeX/*.xml` + `.bin`),
  their fallback pictures and the slide's VML drawing, which places them;
  PowerPoint draws the fallback picture as before. This app draws nothing
  for them.

Left in the app itself (the file is right): `a:grpFill` members are drawn
unfilled, and controls are not drawn.

**The painter against PowerPoint, 2026-10-08.** The writer gate measures
what PowerPoint draws from our FILE; this round measured what this app
DRAWS. `OfficeApp --deck-pdf in.pptx out.pdf` is the headless File → Export
→ PDF (pictures decoded first), and `test/pptx-app-render.sh IN PPT WORK`
scores it page by page against PowerPoint's own PDF of the same original
(the `NAME-orig.pdf` the render gate already made). The scores are larger
than the writer's — fonts, wrapping and anti-aliasing differ on every
page — so the use is the ranking: the worst decks show what the app does
not draw at all. Over the 553 decks PowerPoint renders:

| | mean | median | ≤2% | >20% |
|---|---|---|---|---|
| before | 9.7% | 2.6% | 256 | 92 |
| after | 5.6% | 1.2% | 317 | 40 |

Found and fixed, by pixels (the file is never touched — every one of
these is read-side or paint-side, and the writer regression round shows
the saved copies byte-identical):

- **The layout's and master's own shapes were never drawn** — logos, bars,
  decorative pictures, a title slide's whole picture. `Slide.decorations`
  holds them (not placeholders; honouring `showMasterSp` on the slide and
  the layout), drawn beneath the slide's shapes, never written.
- **Freeforms (`a:custGeom`) were labelled boxes.** `Freeform.swift` reads
  the path list — moveTo, lnTo, quad and cubic Béziers, arcTo, close — and
  evaluates DrawingML's guide formulas (`*/`, `+-`, `?:`, `at2`, `cos`,
  `pin`… with the built-in `w`, `h`, `ss`, `cd4`… names), so the shape is
  drawn along its path in its fill and line, holes cut (even-odd). A guide
  this cannot evaluate still gives a box.
- **SmartArt was a box.** A deck saved by PowerPoint carries the diagram's
  own drawing (`diagrams/drawingN.xml`, reached from the data part's
  `dsp:dataModelExt`); its `dsp:` shapes read as `p:` ones, with their
  `txXfrm` text frames, and are drawn where the frame sits. LibreOffice
  saves no such part, so those decks stay boxes (the ~8 `lo-smartart-*`
  decks still over 20%).
- **Placeholders inherit more than text**: their fill and line from the
  layout's and master's placeholder (tdf95932's green body), and their
  geometry — a preset, or a custom path (custgeom-placeholder's notched
  ellipse).
- **Pictures lost their mirroring, their crop to a shape, their
  transparency (`alphaModFix`) and duotone recolouring** (a theme's
  background picture is usually a duotone of `bg2`; tdf123684 went from
  black-on-white to its dark teal); a negative crop now pads.
- **Backgrounds**: a theme `bgRef` picture resolves in the theme part (it
  was looked up in the master's); the headless export decodes inherited
  background pictures too (half the "white pages" were only that).
- **Gradients blend in linear light**, as PowerPoint does — red to green
  through orange, not brown; the stops are spelled out with in-betweens
  for the sRGB shader. Shapes draw their own gradient and picture fills
  (`fillStyle`) instead of a middle colour, including a gradient inherited
  from the theme's fill style through `p:style`; a first stop at alpha 0
  no longer blanks the shader (the paint's alpha scales it).
- **Groups**: members saying `a:grpFill` take the group's colour;
  `useBgFill` shapes are windows onto the slide background, clipped to
  their outline; a group with a zero child extent is kept whole.
- **Tables**: an empty table still draws its rows' fills and borders; a
  table with no style id draws as a plain grid; `mathMinus` has a path.
- **Second pass, same day**: a background picture marked `a:tile` is
  tiled at its own size (a tile larger than the slide is a photo someone
  marked "tile": fitted, as PowerPoint shows it); a chart area's own
  picture or colour fill is drawn under the plot (chart-picture-bg from
  44% to 6%); a video draws as its poster frame, or black without one
  (bnc591147 from 50% to 0); a diagram's text is fitted to its shape.
- **Third pass**: the dump (`--deck`) lists a diagram's rendered shapes
  under its frame, which showed that a save LOST them — the drawing part
  is reached only through the data part's `dsp:dataModelExt relId`, a
  slide relationship nothing in the slide XML names (the OLE `vmlDrawing`
  trap again), so the writer now carries it under that id; PowerPoint
  never needed it (it lays the diagram out afresh) and still opens every
  copy clean. The headless export had no ICU data (a bare `swift build`
  binary has no `data/`), so its paragraphs wrapped between characters —
  `initializeHeadlessText` now takes `STARLING_ICU` or the loaded
  FlutterMacOS.framework's copy; the gain was under half a point, so the
  earlier numbers stand. Bulleted text in a shape whose level 0 declares
  no text edge (a SmartArt's) had a zero-width list slot and no bullet:
  the slot is the first bulleted paragraph's hang now. A table cell's
  own fill and line colour (`a:tcPr`) are read — a table laid out by hand
  carries its look there, not in a style (an IHEP deck's red-and-pink
  table from 23% to 15%); lines all `noFill` turn the grid off. A row's
  own height (`a:tr h`) is a minimum now — `RichDocument.tableRowHeights`,
  honoured by RichLayout — which PowerPoint keeps however little is in
  the row (tcPr-vert from 39% to 2%, tdf144092-tableHeight from 30% to
  12%). A date, footer or slide-number placeholder with no frame of its
  own and none on its layout is not on the slide for PowerPoint, whatever
  the master has: read as `invisible`, kept for the file, not drawn.
  Character spacing (`spc`) reaches the layout as `CharStyle.letterSpacing`;
  the corpus uses it in fractions of a point, so no deck moved. A cell's
  `anchor` (`CellRef.anchor`, honoured by RichLayout's row placement)
  sits its content in the middle or at the bottom of a taller row.

**Fourth pass, 2026-10-09** (sweep 16 over the same 553 decks: mean
5.57% → 4.83%, ≤2% 317 → 330, >20% 40 → 29; no deck worse by more than
1.5 points), all read- or paint-side, found by reading the worst pages:

- **Path gradients** (`a:path path="circle|rect|shape"` with
  `a:fillToRect`) were drawn as linear. `SlideFill.path`/`fillTo`; the
  painter radiates from the fill-to point to the farthest corner, in a
  space squeezed to the area's aspect — PowerPoint stretches even a
  "circle" to the slide (themes.pptx's radial layout is lit to all four
  edges alike), so rings are ellipses. Every theme's `bgRef` 1003 is one of
  these: themes 18.7% → 3.1%, lo-tdf114848, GeomLec1.
- **Colour modifiers**: `satMod`/`satOff` and `hueMod`/`hueOff` were
  ignored — satMod 350% is what turns a theme's near-grey `lt2` into the
  cream of its backgrounds — and **tint and shade mix in linear light**,
  as PowerPoint does (a 55% tint of a dark grey is a light grey, not the
  sRGB midpoint's medium one; GeomLec1's backgrounds were far too dark).
  Between `a:gamma` and `a:invGamma`, how a converted .ppt spells its
  shades, they work on the sRGB values as they are (45541_Header's blue
  master went too dark without that).
- **A stretched picture's `a:fillRect`** places it within its frame
  (`SlideFill.imageInset`, `SlideShape.pictureInset`; negative is beyond,
  clipped): a background inset 55% from the left and 56% from the top
  covered the whole slide (lo-tdf153466 78% → 0.2%, lo-n821567 38% → 1.5%).
- **A mirrored shape** (`flipH`/`flipV` on a `p:sp`) was read only for
  pictures: a flipped `line` drew along the wrong diagonal (aascu's V).
  Read for every shape, drawn mirrored (its text upright), written back.
- **An empty `a:gradFill`** (no stops, 63200's oval) now falls through to
  the style's `fillRef` instead of drawing nothing; a **placeholder
  inherits its layout's gradient** too, not only a solid fill
  (tdf114848's title bar); a **freeform draws its gradient or picture
  fill** within its path (lo-tdf112209), and **`a:grayscl`** is the
  black-to-white duotone.
- **Table styles come from the deck's `tableStyles.xml`** now, by id:
  the whole table's fill and rules (`a:ln` or `a:lnRef`), `firstRow`,
  `band1H`/`band2H`, and `lastRow`/`firstCol`/`lastCol` when the table's
  flags ask, each with its text colour and weight; a translucent band is
  composited over the table background (`a:tblBg`, a themed style's
  gradient by its middle colour). The old guess — the first accent, white
  bold header text — stays for a style the deck does not define.
  Maloney's "Medium Style 2" went from olive to its navy and grey
  (25% → 14%); lo-bnc480256's themed styles 34% → 9%; Light styles no
  longer get a filled header. Cell paragraphs with `a:buChar` draw their
  bullets (the layout's cell list slot, 18 pt).
- **Doughnut charts** are read, drawn (rings; the hole shows what is
  behind) and written (`c:holeSize`), as a pie with a hole:
  lo-chart_pt_color_bg1 26% → 3%.
- **`mathEqual`, `mathNotEqual`, `mathMultiply`, `mathDivide`** have
  paths (`SlidePainter.band` winds a band the way `addRect` does, so the
  stroke through ≠ fills instead of cutting holes where it crosses).
- **"Lucida Sans Unicode" came out monospace**: the font substitute took
  any family with "code" in its name for a code font. Unicode is not code.

**SmartArt laid out here, 2026-10-11** (`Slides/Diagram.swift`). A
diagram in a .pptx is data (the text and its hierarchy), a layout
definition (an algorithm), a colour scheme and a style — and, when
PowerPoint saved it, a cached drawing of the result. A deck LibreOffice
saved has no drawing (or an empty one), and the ~25 `lo-smartart-*` decks
were labelled boxes, most of what was left over 20%. `DiagramLayout` is
an interpreter for the layout definition language (`dgm:layoutDef`),
reduced to what the built-in layouts use:

- **Building the presentation tree**: `forEach` over the data by axis
  (`ch`, `des`, `desOrSelf`, `followSib`/`precedSib` through the sibling
  sequence of transitions, `par`, `root`…), with per-step `st`/`cnt`
  (`axis="ch desOrSelf" st="1 1" cnt="1 0"`), `ptType` filters, the last
  sibling's transition hidden; `choose`/`if` on `cnt`, `pos`, `revPos`,
  `depth`, `maxDepth` and variables (`dir`, `hierBranch`, from the
  definition's `varLst` or the data's `presLayoutVars`); `ref` to a named
  forEach for recursion.
- **Constraints**: `w h l t r b ctrX ctrY sibSp sp primFontSz …` by
  `for`/`forName`/`ptType` and `refType`/`refFor`/`refForName`, with
  `fact`, `val`, `op` (`lte`/`gte` as caps and floors), `INF` as
  "unbounded — take what is left". A size tied to the node's other size
  (h = 0.6 w) is remembered and kept in step when the layout scales it;
  a cap on one takes the other with it (the circle stays round). A laid-out
  node's size is the slot it got; its own constraints can only shrink it.
- **Algorithms**: `composite` (children by their l/t/w/h/ctrX/ctrY/r/b,
  `lOff`/`rOff`, re-anchored when they come out smaller, `INF` rules
  filling what is left); `lin` (children along the direction at their
  natural size — a container's being what its children add up to —
  shrunk together to fit, or only those a `rule` names along with the
  spaces that follow them, the unbounded ones sharing any slack and
  filling across; each child aligned across the line by what it holds;
  the line as long as its run, spaces included); `snake` (the column
  count whose grid is closest to the frame's proportions, scaled to fit,
  centred); `cycle` (a ring from `stAng` by `spanAng`, radius from
  `sibSp` or `diam` — which caps the nodes to keep their spacing — the
  first node in the centre for `ctrShpMap=fNode`, nodes turned along the
  path, connectors between neighbours sized against the nodes as they
  ended up); `hierRoot`/`hierChild` (natural layout, the root centred
  over its children's block, two or more leaves hanging to the right
  of the parent's middle, the whole tree scaled into the frame at the
  end); `pyra` (bands of a triangle, the first at the top); `conn` as a
  bent line from the parent's bottom to the child's top (or across to a
  hanging child's side), or a block arrow in a line or ring.
- **Shapes**: ordinary `p:sp` elements the slide reader then reads like a
  drawing part's — preset, adjustments, rotation (180° as a mirror so the
  text stays upright, ±90° with the box turned), `hideGeom`, `zOrderOff`
  as places in the stack; fill and line from the colour scheme's style
  label (the data's presentation point names it, else the definition's,
  else `node<depth>`) by its index among that label, `repeat`/`cycle`/
  `span`, over the quick style's references; the point's own `spPr`
  first. Text from the points the node presents, the node's own first and
  its descendants as bulleted levels, at the constrained font size
  (65 pt down to 5), fitted by the reader with words kept whole, the
  margins (fractions of the font size) shrinking with it
  (`starling:insScale`, `SlideShape.insetsFollowFont`).
- `STARLING_DIAGRAM_DEBUG=1` prints the presentation tree with every
  node's rect, values and caps to stderr.

Over the 30 drawing-less decks (sweep 18): bullet-list 36% → 0.9,
font-size 46 → 2.7, table-list 38 → 2.3, autofit-sync 41 → 5, chevron
8 → 0.2, cnt (vProcess5) 30 → 1.5, pyramid 27 → 0.4, center-cycle
13 → 1.2, org-chart2 19 → 8, children 35 → 7, linear-rule 20 → 9,
linear-rule-vert 31 → 7.5. The whole corpus: mean 4.83% → 3.84%, decks over
20% from 29 to 15 (three decks whose empty drawing part used to draw
as a labelled box score a few points worse laid out — snake-rows,
picture-strip, accent-process — because the box was small). Left: missing-bullet (PowerPoint sizes its text far
smaller than the box allows, for a reason the file does not show),
fill-color-list (hList1's text boxes end short of the frame), the
`asst` and `hang` org-chart branches, `pyraAcct` text strips, and the
layouts the corpus does not exercise.

**Presets from their definitions, 2026-10-11** (`Slides/PresetGeometry.swift`,
`PresetDefinitions.swift`). The painter drew some thirty presets from
hand-written outlines at PowerPoint's default adjust values, and the
rest as their box; a pie with its own angles, a funnel, a "not equal"
with a slanted stroke all came out wrong (18–26%). Now every `prstGeom`
is evaluated like a freeform from the spec's definitions
(presetShapeDefinitions.xml — ECMA-376's, as LibreOffice carries it: 187
presets, generated into a Swift string with the `a:` prefix the freeform
reader expects, handles and connection sites stripped), with the shape's
`avLst` over the definition's defaults, at the size of the frame as
placed (a group's child scaled by the group — PowerPoint sizes an
arrow's head by the frame it ends up with, 63200). The outline goes
through `customPath`, drawn contour by contour as the definition says:
`fill="none"` contours stroked only, `stroke="false"` ones filled only,
`darken`/`lighten` ones toned (a cube's faces), a whole turn of `arcTo`
as the oval itself (Skia's arc of a full sweep is nothing — the funnel's
rim had no hole). The definition's `a:rect` is where the text goes: an
oval's text box is its inscribed rectangle, a pie's its quarter, and the
reader adds the difference to the shape's insets. A picture's own
`spPr` fill is painted behind it (a black square around a padded
image, tdf163803); an OLE object's and an ActiveX control's fallback
`p:pic` are read (the object's as its rendering, the controls' as
decorations), though both corpus cases are WMF/EMF and stay grey. A
tiled picture repeats at its declared resolution (PNG `pHYs`, JFIF
density — `PptxReader.imageDPI`) rather than a flat 96 dpi, and one
that declares none at 144: measured by cross-correlating the tile at
candidate sizes against PowerPoint's export of lo-page_transparent_bitmap
(a 94 px PNG drawn 47 pt wide — its pixels taken as a Retina screen's,
it seems; 43% → 4%). Images draw with bilinear filtering.

Sweep 19: corpus mean 3.84% → 3.42%, ≤2% 339 → 348, decks over 20% 15 →
11. mathNotEqual 26 → 0, funnel 25 → 1.5, image_with_fill 21 → 0,
pie_textarea 19 → 3.4, vert_and_padding 11 → 3.8, the Scene3d lightRig
trio 19 → 13, cycle-matrix 16 → 9.

**Table cells as the file has them, 2026-10-11** (`CellRef` in the SDK's
`RichDocument.swift`, `RichLayout.swift`). A cell's text direction
(`tcPr vert`: `vert` reads down, `vert270` up — `CellRef.textDirection`),
its own margins (`marL`…`marB`, PowerPoint's 0.1"/0.05" defaults where
the file is silent — `padding`, in points) and its own edge lines
(`lnL`…`lnB` with width and colour, or `noFill` — `borders`) are read,
laid out and written back; Word's `w:textDirection` is read and written
too. A turned cell is laid out in its own horizontal space and painted
turned a quarter about the corner it reads from (bottom-left reading
up, top-right reading down). Its lines run along the row's height,
which the row's other cells decide, so the layout places the rows
first, then wraps each turned cell at the height its rows came to — no
shorter than its longest word, since the paragraph engine would break
the word where PowerPoint grows the row (and it reports the word's
width only once it has wrapped: after an unconstrained layout
`minIntrinsicWidth` is nothing) — and stretches the last row the cell
covers if the longest line still does not fit. Lines then stack across
the column, where the anchor's free space is. Edge lines are drawn per
cell over the style's rules at their own width, a hidden edge drawn as
nothing; before, the first cell line found recoloured every rule of the
table (table_test2's whole grid was orange). Caret and selection in a
turned cell are not turned with it: editing one works, but looks wrong
until that is done. Sweep 20: table_test2 21.2 → 5.9%, the two aascu
decks −1.4, tableBorderLineStyle 4.1 → 3.5, bug68703 +0.4 (its cells
set no top and bottom margin, and the text now sits where that puts
it); corpus mean 3.42 → 3.37%, decks over 20% 11 → 10. What remains of table_test2
is the line height — Calibri's at 18 pt is 22.0 pt in PowerPoint and
20.6 here, so a five-line cell is 7 pt shorter and a turned cell next
to it wraps one line more.

**Single spacing is the face's own height, 2026-10-11** (`RichTextTheme`
in the SDK's `RichLayout.swift`). `RichParagraphStyle.lineSpacing` was
documented as a multiple of the font's natural line height and passed
to the engine as a multiple of the font size (Flutter's `height`), so
every single-spaced line was the size exactly: 18 pt of Calibri made
18 pt lines where PowerPoint makes 22 (Calibri's ascent, descent and
gap are 1.22 of its size; Arial's 1.15 — Carlito and Liberation Sans
match, which is what they are for). The theme now measures each face's
natural height once (a 100 px probe, cached per family and weight) and
scales the multiple by it, so 100% is the face's own and Word's 1.08
is 1.08 of that — Writer's lines grow the same way, which is how Word
has them (Calibri 11 single-spaced is 13.4 pt there). With that, a
body PowerPoint shrank to fit needs the share it took off the line
spacing as well as off the sizes: `normAutofit lnSpcReduction` is read
beside `fontScale` (`SlideShape.lineReduction`), carried on the shape's
theme as `lineSpacingScale`, applied by every layout of it (painter,
editor, autofit) and written back; before, the short lines happened to
stand in for it. Sweep 21: corpus mean 3.37 → 3.23%, decks ≤2% 349 →
357; the three 45541/45545 decks −2.7, lo-group −2.6, table_test2
5.9 → 3.4, tableHeight 3.2 → 1.5, twenty-odd decks −1; up: lo-tdf160487
+0.6 and lo-tdf158512 +0.7. Writer's own rendering changed with it and
has no pixel oracle (the Word gate scores Word against Word); the
native-versus-browser layout gate still passes.

**A drawn diagram's callouts, 2026-10-11.** A SmartArt drawing part's
shape carries its own text frame (`dsp:txXfrm`), and the reader took
that branch instead of evaluating the shape's preset, so a header
drawn as an `upArrowCallout` had no outline and the filter that drops
arrows the painter cannot draw dropped it (tdf150789 lost two headers
and their arrows). The preset is evaluated whatever the text frame,
which now only decides where the text goes. Of the 36 corpus decks
whose diagrams are drawn with text frames, none moved up: SmartArt_Pie
17 → 0.7, tdf150789 15 → 1.5, SmartArt_Pyramid 8.8 → 1.6,
SmartArt_rightArrow 5.8 → 2.3.

**Capitals, the file's bullets, empty items, 2026-10-11** (60810,
alterman_security). Three things every bulleted deck showed: a run's
`cap="all"` was ignored (60810's titles are all capitals by its
master), a bullet was always the level's default glyph (• ◦) where the
master names one (`buChar` — "–" for the second level in both decks),
and an empty paragraph in a list drew its bullet, which PowerPoint
never does. The reader sets Writer's `CharStyle.caps` (and
`smallCaps` for `cap="small"`), which the layout already shows in
capitals for Word's All caps — the text keeps its case and is written
back with the attribute; `RichParagraphStyle.bulletText` is
the file's glyph, with a Wingdings or Symbol code mapped to the Unicode
glyph it shows (§ → ▪, Symbol's · → •; a code this app does not know
draws the level's own); and a Slides theme sets
`marksEmptyListItems` off, which Writer leaves on as Word does.
Sweep 23: 60810 12.9 → 12.4, a handful of decks by a tenth; the
corpus mean stays 3.15% — the glyphs and the empty items are a few
pixels each, and most decks' bullets were the default already.

**No placeholder boxes in a show or an export, 2026-10-11.** An
object the deck cannot draw (a picture whose part the file lacks,
Divino_Revelado; an unknown object) got a labelled grey box
everywhere. PowerPoint shows nothing in its place, so the box is now
the editor's only (`SlidePainter(placeholders:)`): the show and the
PDF export draw nothing there. Divino_Revelado 16.2 → 15.2,
lo-tdf131553 11.3 → 10.6, lo-tdf169781 −1.7, lo-group-rot −1.0,
radar-chart −0.8; the EMF/WMF decks are unmoved (their pictures go
through the picture path, not this one). The one loss: 45541_Footer,
45541_Header and 45545_Comment (one deck three times) go 11 → 17.7,
because slide 8 is an embedded PowerPoint slide whose only preview
is a WMF in a VML drawing — PowerPoint draws that, this app cannot,
and the full-slide grey box happened to be nearer to it than the
master's blue gradient now showing through. Taken: a show should not
display an editor's box. Sweep 25: corpus mean 3.15 → 3.18%, decks
≤2% 362 → 363.

**Bullets where and how the file has them, 2026-10-11.** The marker
sat right before its text, right-aligned in the list indent; PowerPoint
puts a bullet's left edge at `marL + indent`, the hanging position, and
so does Word. A Slides theme now asks for that (`markersAtHang`: the
list indent before the text plus the paragraph's first-line indent,
never over the text), and the marker takes the level's own colour and
size (`buClr`, `buSzPct` — `bulletColor`, `bulletScale` on the
paragraph style, written back; the `…Tx` forms follow the text). 60810
and alterman_security now show their bullets as PowerPoint does; the
scores barely move (a bullet is a few pixels), autofitIndentation −0.15.
Writer keeps its own marker placement — Word's hang is the numbering
definition's, which the Writer model carries differently.

**WMF and EMF pictures, 2026-10-11** (`Metafile.swift`, app-level so
Writer can use it too). 47 corpus decks carry a metafile — clip art, an
embedded sheet's or slide's preview, every ActiveX control's picture —
and no image codec reads one: it is GDI calls, not pixels. `Metafile`
plays the records once into steps (fill, stroke, text, bitmap, clip)
and paints them as vectors, stretched into the picture's frame with the
crop applied; `SlideTextCache.metafile(_:)` parses by magic bytes and
`image(_:)` stays out of the way. The subset is what the corpus uses,
found by histogramming all 101 WMFs and 18 EMFs: pens, brushes and
fonts with the object table (WMF's lowest free slot, EMF's own indices
and stock objects), polygons and polylines, EMF path brackets with
béziers, rectangles and ellipses, `ExtTextOut` with its alignment,
escapement and opaque box, `PatBlt` and the DIB blits (the bitmap
rewrapped as a BMP file for the codec; AND, OR and XOR masks as
multiply, screen and difference), rectangular and region clips, and the
mapping — WMF's window, EMF's window, viewport and world transform,
applied to every point as it is read, so a turned or skewed ellipse is
four mapped cubics. The picture is WMF's first window, and EMF's frame
taken to device units. Text in Wingdings, Webdings or Symbol is mapped
to the Unicode glyphs it shows. Not done: hatches and pattern brushes
(a grey), arcs, EMF+ records (the GDI ones beside them are drawn),
raster operations beyond copy and the mask idioms, `clrChange` on a
metafile. An embedded object from before `p:pic` fallbacks keeps its
preview in the slide's VML drawing (`<v:shape id=spid><v:imagedata>`),
read as text since VML is not always XML — 45541's embedded slide, a
whole page that was blank, is its WMF now.

Two places where the oracle and GDI part: `ExtTextOut` with ETO_OPAQUE
and no text fills its box with the background colour in GDI, and
PowerPoint for Mac leaves it white (lo-activex_textbox's green field,
+3.5 here); and lo-tdf113163 exports black from PowerPoint where the
EMF's visible part is white (the pie chart it holds draws correctly
when the whole picture is on the slide). GDI's reading is kept.

Left on the painter side, from the same ranking: 3D (`a:scene3d`
materials and lighting), TIFF and JPEG-XR pictures (no decoder —
ArtisticEffectSample), WordArt text fills and warps (tdf139618), a 2×2
JPEG stretched over a slide that PowerPoint shows flat (tdf146223),
and the 1–3% that is text wrapping and font metrics everywhere.

**S8, find and replace, 2026-09-30.** ⌘F, ⌘H and the title bar's
search field open Writer's find bar over the deck: every text body in
reading order — each slide's shapes as they stack, table cells included,
then its notes — case-insensitively, with "n of N"; Return in the field
goes on (the keyboard stays there: an earlier cut moved focus into the
match, and the next Return replaced it with a paragraph break), the match
selected on its slide. Replace replaces the selected match and goes on;
Replace All is one undo step across the deck. Also fixed: a table row's
shading was painted over the selection (Writer's tables too) — shading
now has a layer of its own under it.

**S8, autofit, 2026-09-30.** Placeholders shrink their text to fit as
PowerPoint's do (`normAutofit`): as their text or box changes, the shell
picks the largest of PowerPoint's steps (100% down to 25%) at which it
fits, and the shape draws at that scale — editor, thumbnails, show and
PDF alike — while the text keeps the sizes it was typed in. A file's own
`fontScale` is read as such rather than baked into the sizes (which then
went back out frozen, under `noAutofit`), written back as
`normAutofit fontScale`, and not re-measured until the text changes, so a
deck opens at PowerPoint's scales. Our master and layouts say
`normAutofit` too.

**S7 done 2026-09-30** — part 3, presenter view: Slide Show →
Presenter View or ⌥F5 runs the show as PowerPoint's presenter layout in
the one window — the current slide (as far as its animations have got;
a click on it goes on), the next slide (with how many animations remain
here), the notes in large type, a timer with pause and reset, the slide
counter, the clock, Back / Next and End Show. One window, not a second
display: putting the audience view on another screen wants a host hook
for a second window, which macOS has and the framework does not yet.

**S7 part 2 done 2026-09-30** — entrance animations. An Animations tab
(Preview; None, Appear, Fade, Fly In, Wipe, Zoom; Effect Options with
direction and As One Object / By Paragraph; Start, Duration, Delay; the
Animation Pane; Move Earlier/Later), click numbers beside animated shapes
(by paragraph: beside each paragraph) while the tab or pane is open, and
a pane listing the slide's entrances in play order. The show plays them a
click at a time — a click finishes a group still running, Back takes the
last one away, a first group that starts by itself plays on arrival, and
a slide reached by stepping back arrives fully built. A slide's
`p:timing` is read when it holds only these entrances (whole shapes or
single paragraphs, including PowerPoint's empty root on slides without
animations): written back byte for byte while unchanged, as PowerPoint's
own tree once edited. Timing with anything else — exits, emphasis,
motion paths, other entrances — is kept as read and the tab says so
rather than editing it. Of the real decks, X3 models 110 of 117 slides
(the rest use Blinds, Dissolve and an exit) and the lecture 28 of 33.

Two S4 losses found and fixed on the way:

- **Groups lost their own id**, so a group's animation went on save (the
  lecture's three). Members still edit as shapes, but remember their
  outermost group; a save groups the ones still side by side again under
  its id, and the lecture keeps all 23 groups and all its animations.
- **Every connector became a straight line** — no curve, no arrowhead,
  and pointing the wrong way when rotated and flipped. Connectors now draw
  between their real ends (flips, then rotation about the box) and, while
  the line and outline are as read, are written back as the original
  element; Quick Look draws the lecture's curved arrow again.

**S7 part 1 done 2026-09-30** — header and footer, and fields. Insert →
Header & Footer is PowerPoint's Slide tab: date and time (updating, or
fixed text), slide number, footer text, "Don't show on title slide",
Apply or Apply to All, one undo step. The three sit where the slide's
layout keeps them (read from the file's layout or master), PowerPoint's
positions otherwise, and our master and layouts now carry them as
PowerPoint's do (`dt`/`ftr`/`sldNum`, idx 10–12). A shape whose text is
one field (`a:fld`) keeps it: slide numbers follow the slide's place, dates
are today's, both are written back as fields, and typing over one makes
it text. Updating a field is not an edit: a file with stale cached
numbers opens clean.

Trap paid for: **every slide number was frozen on save.** The reader
took a field's cached text as plain text, so the lecture deck's numbers
became literal "3"s — wrong after any reorder, and wrong in PowerPoint
for good. Nothing failed: the round trip compares text, and the text
matched.

**S6b done 2026-09-30** — charts. Insert → Chart offers column, bar,
line, pie, area and scatter on PowerPoint's own sample data; the Chart
Design tab changes the kind (the data kept), opens the data grid, and
turns the title, legend, data labels and axis titles on and off, with
clustered / stacked / 100% stacked for the kinds that stack. The data
grid sits beside the slide — series across, categories (a scatter's x
values) down, Add/Remove Row and Series — and redraws the chart as it is
typed; typing in one cell is one undo step. Charts draw in PowerPoint's
default look (gridlines, 65% text, legend below, the theme's accents in
its colour cycle), follow a new theme, and print, show and export like
any shape. A `.pptx` chart is read from its part's cached values
(category and scatter kinds, stacking, gap and overlap, titles, labels,
explicit and theme colours); an unchanged one is written back through its
own part, an edited or new one as our `c:chartSpace` with its cache and
an embedded one-sheet workbook so PowerPoint's Edit Data opens on it.
Doughnut, radar, 3-D, stock and combination charts stay kept objects.
Checked against python-pptx's PowerPoint-style charts (all six read,
doughnut and radar kept, an identical round trip) and Quick Look, which
draws our written chart like PowerPoint's default.

Traps paid for in S6b:

- **A Row in a horizontal scroll view must be `mainAxisSize: .min`.**
  Unbounded, it asks for infinite width; the finite-size assert added in
  the engine-debt pass caught it as a crash on Edit Data, where it would
  once have drawn nothing. The grid now widens the pane instead of
  scrolling sideways.
- **A chart's data is a value, its shape is an object.** Undo matched
  shapes by `kind ==`, so a chart with other data came back as a new
  shape: the selection and the open data grid lost it. Charts restore in
  place (`ShapeKind.sameObject`).
- **Absent `c:gapWidth`/`c:overlap` mean 150 and 0** (the schema), not
  PowerPoint's 219 and −27 for a new chart; and a series coloured with its
  own slot of the cycle is "follows the theme", or a chart we wrote reads
  back unequal and is never kept.
- **`FluentTextBox` typed an "a" for ⌘A**: it tracked no modifiers. It
  tracks the command key now (⌘, Ctrl off Apple platforms): ⌘A selects
  all, other ⌘ chords are not text. Inline, not RichText's
  `KeyChordTracker` — the web build does not compile `RichText/`, and
  `test/run.sh`'s size gate is what said so.
- The Office driver now sends no input once its app has exited — the
  first crash here left the next clicks to whatever window was in front.

**S6 part 2 done 2026-09-30** — tables. Insert → Table offers a menu
of sizes; the table is a Writer table inside a frame (the same cells, Tab and
⇧Tab between them, the Table Layout tab for rows, columns and merges), in
PowerPoint's default look — an accent header row in white bold, banded
rows in two tints, white rules — which follows the theme. Its height
follows its rows. Read from a file: grid, column widths, merges and the
header/band flags, with the style GUID approximated by our look; an
unedited table is written back exactly as read, an edited one as our own
`a:tbl` with every fill spelled out (Quick Look draws it as PowerPoint's
Medium Style 2). The framework's `TableStyle` gained header, band and
rule colours for it.

Traps paid for in S6:

- **A text theme edited in place goes unseen**: the thumbnails' layout
  cache and the editors kept the old colours (white on cream). Text
  themes are replaced, never mutated, and the cache keys on the object.
- **An inherited background is not the slide's**: storing the master's
  picture as each slide's own wrote it 117 times (0.5 MB → 2.4 MB).
  Inherited backgrounds are drawn, not written; and one image file is
  one attachment however many slides use it.
- **Slide text must not scroll.** The table's height is fitted at 1 px
  per point, the editor lays out at its zoom where lines round
  differently, and the few pixels' difference drew the editor's scroll
  thumb down the table's edge. `RichEditable(scrolls: false)` pins the
  text and draws no thumb; shapes overflow, as in PowerPoint.
- Pictures are grabbed whole: "edits on first click" means text boxes
  and placeholders only, or a picture is a frame of edge bands.

**S5 done 2026-09-30**: the slide show. From Beginning / From Current
(Slide Show tab, F5 / ⇧F5, ⌘⇧↩ / ⌘↩) puts the window full screen through
a new framework hook, `hostSetFullscreen` (Cocoa: toggleFullScreen, made
reliable below), and plays the visible slides letterboxed on black: → ↓
Space Return PageDown N and a click go on, ← ↑ Backspace PageUp P and a
right click go back, Home/End, a number then Return jumps, B and W blank
the screen, Esc ends; the pointer hides after two seconds still; the end
screen is PowerPoint's. Transitions (None, Fade, Push, Wipe, Cover, with
direction and duration, Apply To All) live on each slide, play on the
way in, and round-trip through `p:transition` (kinds this app does not
draw are kept verbatim and shown as a fade). Animations are not modelled
until S7, but a slide's `p:timing` is kept and written back while every
shape it names is still on the slide — so shapes now keep their file
ids through a save. Both real decks keep every animation except three
of the lecture's (aimed at groups, which the reader flattens).

Traps paid for in S5:

- **AppKit drops `toggleFullScreen` sent from inside an event handler or
  to a window mid-transition** — the show stayed windowed one run in two.
  The native call now runs on the next run-loop turn, marks the window
  full-screen capable, and retries once if the state did not change.
- **Saving renumbered every shape**, which silently orphaned the deck's
  animations (they name shapes by `cNvPr id`). Ids are kept now.

**S4 done 2026-09-30**: `.pptx` both ways, plus PDF. The reader resolves
what PowerPoint resolves — placeholder geometry, body settings and text
looks through slide, layout, master, the master's text styles and the
presentation's defaults; colours through the master's map into the theme
with lumMod/lumOff/tint/shade/alpha; backgrounds (colour, gradient,
picture, `bgRef` into the theme) through slide, layout and master;
pictures with their crop; connectors with flips; groups flattened; any
preset name kept (drawn exactly for ~25, as its box otherwise). Charts,
SmartArt, tables, video and freeforms are kept as XML and drawn as a
labelled box. A deck from a file is written through its package
(masters, layouts, themes copied byte for byte; kept objects re-pointed
with the parts they reach); a new deck gets our own templates. Gates:
`OfficeApp --deck-roundtrip in out` (read, write, read: dumps equal within
0.1 pt), `test/pptx-check.py` (structure PowerPoint would refuse or
"repair"), and Quick Look (`qlmanage -t`, Apple's own Office importer)
for the first slide. Both real decks on this machine (a 117-slide
PowerPoint talk and a 33-slide lecture with SmartArt) round-trip, pass
the check, and render the same in Quick Look before and after. On
screen: open, edit, ⌘S, reopen; Export → PDF writes every visible slide.

Traps paid for in S4:

- **An absent `anchor` means top, for every shape.** Defaulting drawn
  shapes to centre wrote `anchor="ctr"` back, and Quick Look then stopped
  wrapping that box — found by bisecting the written XML one attribute at
  a time against Quick Look renders.
- **Pictures are cropped by `a:srcRect`**: one image file fed two
  pictures on the lecture's title slide, each showing a different part.
- **A run that does not say "not bold" inherits bold** from its layout:
  every run property is written explicitly, `b="0"` included.
- **No PowerPoint here, but Quick Look is Apple's Office importer**: a
  file it will not thumbnail is a file PowerPoint will at least repair.
- The lecture deck lives in ~/Downloads and is the user's: read locally
  for testing, never committed. The Boost talk is BSL-licensed.

**S3 done 2026-09-30**: drag a thumbnail to reorder (an accent line
shows where it lands), right-click a thumbnail for New/Duplicate/Delete/
Hide Slide and the layouts, ⌘↑/⌘↓ move the current slide, Enter in the
pane adds one and Delete removes one, hidden slides show dimmed, and the
Slide Sorter view (View tab or the status bar) lays every slide out as a
grid; a double click opens one in Normal view.

Traps paid for in S2:

- **Global coordinates were device pixels.** The framework's
  `getTransformTo(nil)` walked past the root and folded the device pixel
  ratio into `globalToLocal`, so a dragged shape moved half as far as the
  pointer on a 2x screen. Fixed in the framework (upstream stops below
  the root); the colour picker, selection drags and the Linux IME caret
  were wrong by the same factor.
- **Drags end at the release, not the last move.** Moves are coalesced
  while a frame is busy; the up event is applied as a final move.
- **Every per-shape subtree is keyed and the same shape each build**, and
  its Stack does not clip (a shape hanging off the slide is drawn whole).
- **Driver menus**: the Shapes menu rows are 28 px from y 195; a click a
  row off picks the neighbour silently, and a click above the menu picks
  nothing — the first "drags go to the backdrop" was an empty slide.

Traps paid for in S1:

- **A Stack whose child list changes shape remounts the editor under the
  click.** Each text shape was [outline, prompt, editor] while empty and
  [outline, editor] once editing — the editor element moved index,
  remounted mid-gesture, took the typing and never painted it. Every
  shape now builds the same three children and hides what is off.
- **FluentApp reads `home` once.** A new home under the same app is never
  shown; the kind switch keys the whole app instead.
- **No LayoutBuilder in the framework.** The canvas learns its size
  through `SizeReporter`, a proxy box that reports from `performLayout`
  through a post-frame callback (real since the engine-debt commit).
- **Shapes are classes**, not the values the model section first said:
  a text shape owns the controller its editor binds to, and that
  identity must survive every deck edit.

## Milestones

Each one ends on screen, through a driver script like
`test/office-drive.py` (`test/slides-drive.py`), with pictures read by a
person before it is called done.

**S1 — Skeleton.** The session gains a document kind; New → Blank
Presentation (and `OfficeApp --slides`) opens a blank 16:9 deck, the ribbon (Home, Insert, Design, Transitions,
Slide Show, View), a thumbnail pane, the slide canvas zoomed to fit, and
a notes pane. Title and subtitle placeholders take typing. Writer
unchanged and re-verified.

**S2 — Objects on the canvas.** Select, move, resize (8 handles, Shift
keeps aspect), rotate (handle above the box), nudge with arrows; multi-
select by marquee; Delete, Duplicate (⌘D), Cut/Copy/Paste of shapes;
smart guides snapping to slide centre and other shapes' edges and
centres; Arrange (front/back, align, distribute). Insert Text Box and
the basic shapes gallery (rectangle, rounded rectangle, ellipse,
triangle, arrow, line, star, callout). Fill and outline colour from the
existing colour bars. Double-click a shape to edit its text; Esc leaves
text editing with the shape still selected.

**S3 — Slides as a list.** New Slide with a layout menu, Duplicate,
Delete, Hide, reorder by dragging thumbnails, ⌘↑/⌘↓; Layout menu on an
existing slide re-flows its placeholders; Slide Sorter view; notes edit.
Thumbnails come from `SlidePainter` at thumbnail scale, cached per slide
revision.

**S4 — `.pptx` both ways.** Reader: presentation, slides, layouts,
masters, theme, notes, pictures, `sp`/`pic`/`cxnSp`/`graphicFrame`
tables/`grpSp`, DrawingML text (`a:p`, `a:r`, `a:rPr`, bullets, levels),
preset geometries we draw, everything else `opaque`. Writer: a valid
package with one master, our seven layouts, the theme, and the slides;
untouched imported layouts and masters are written back as read.
PDF export, one page per slide, through the existing SkPDF path.

**S5 — Present.** From Beginning (F5) and From Current Slide (⇧F5):
the window goes full screen through the host's `setFullscreen`, the
slide letterboxed on black. Next on →, ↓, Space, Return, click and
page-down; back on ←, ↑, Backspace; Esc ends; a number then Return
jumps; B and W blank the screen. Fade, push, wipe and cover transitions
run on an `AnimationController`. The pointer hides after two seconds
still.

**S6 — Design.** Five or six built-in themes of our own (no Microsoft
theme names or artwork), slide size, background colour/gradient/picture,
Format Background. Tables (insert grid, type in cells, add/remove rows
and columns, banded style) reusing Writer's table cell model where it
fits. Pictures: insert, crop, replace, reset size.

**S6b — Charts.** Insert Chart (column, bar, line, pie, area, scatter)
with sample data; edit data in a grid pane; chart title, legend, axis
titles, data labels; colours from the theme. `.pptx` charts read from
their `c:chartSpace` part and its cached values; a written chart carries
its cache plus an embedded workbook (a minimal `.xlsx` over the same Zip
layer) so PowerPoint's Edit Data opens it.

**S7 — Show extras.** Entrance animations on click (Appear, Fade, Fly
In, Wipe, Zoom) with an animation pane for order; presenter view
(current slide, next slide, notes, elapsed timer, slide counter) as a
layout of the presenting window. Header and footer: slide number, date,
footer text.

**S8 — Polish and gates.** Dark mode, window resize, keyboard-only
operation, autofit (shrink text on overflow, as PowerPoint's
`normAutofit`), spell check in boxes and notes, Find and Replace across
slides, recent files and the recovery copy (`name.pptx~`, as Writer does).

## Gates

- **Perf:** a 100-slide deck opens in under a second; thumbnail strip
  scrolls at frame rate; a keystroke in a text box lays out and paints in
  under 1 ms; dragging a shape repaints only the canvas. A `--bench`
  flag like Writer's.
- **Round trip:** a corpus of real decks (our own, and public-domain
  ones; none from customers) read → write → read compares equal by a
  `--dump` of every shape's kind, frame and text, the way
  `office-layout.sh` gates Writer. Visual check of the written files in
  Keynote and Quick Look (`qlmanage -t`), which are on every Mac.
  PowerPoint itself is not on this machine; a check there needs a
  person or a VM.
- **Tests:** model and controller unit tests (undo of every mutation,
  placeholder inheritance, z-order), Pptx unit tests per part, the
  driver script per milestone.

## Risks and traps known before starting

- **Interior repaint boundaries do not work in this framework**
  (`RenderObject.swift`, `_compositeChild`): a `RepaintBoundary` paints
  nothing. Thumbnails therefore cannot be "the slide widget in a
  RepaintBoundary, scaled"; they are `SlidePainter` drawing into a
  `CustomPaint` at thumbnail scale. Fixing interior boundaries properly
  would help both apps and is worth doing if thumbnail repaint shows up
  in the perf gate.
- **Text editing under a transform.** The canvas is scaled to fit and
  shapes rotate. `RichEditable` has only been used unscaled; its caret,
  hit-testing, selection drag and IME rectangle all need checking inside
  `Transform`. Expect framework fixes here in S1–S2.
- **Two undo stacks.** A text box's `RichDocumentController` keeps its
  own undo; the deck keeps another. Leaving text editing folds the
  text session into one deck step, and ⌘Z inside a box undoes text
  first. Get this right in S2 or every later milestone inherits it.
- **Presenter view on a second display** needs a second native window.
  The Cocoa host has one; the framework already has secondary-view
  pipelines (the Linux multi-monitor path in `Adapter.swift`). v1
  presents in one window; a true two-screen presenter view is a host
  spike after S7.
- **Driver limit:** a modifier held across a synthetic click never
  reaches the app, so Shift-click multi-select and Shift-drag
  constrained resize are checked by hand.
- **Fonts.** Decks name Calibri, Calibri Light, Aptos, Arial. Writer's
  `OfficeFonts` resolver maps the metric-compatible clones; Aptos has
  no free clone, so it falls back and widths will differ slightly. The
  round-trip dump compares text and frames, not line breaks, for that
  reason.

## Naming and legal

"Slides" as the app name, as asked. It is a generic word; Google's
product is "Google Slides", so plain "Slides" is low risk, but the
bundle identifier and About box should say "Starling Slides". Themes,
icons and template content are our own; the ribbon follows the same
reasoning as Writer's (layout conventions are not protected; the ribbon
patent family has expired). `THIRD_PARTY_NOTICES.md` grows if a font or
library is added.

## Order and estimate

S1–S5 are the useful product: open, edit, present, save. Roughly in
proportion to Writer's milestones, S1–S2 are the largest (the kind switch,
then the canvas interaction model), S4 is the riskiest (PresentationML
inheritance), and S5–S8 are each smaller. Work goes on branch `office`
with engine fixes on `starling`, as Writer's did.

## Open question

The app is one bundle for both kinds, and its name is "Writer" today.
A suite name is needed before the macOS bundle and the About box can
say anything sensible; until then the bundle stays "Writer" and each
window's title names its kind.
