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
