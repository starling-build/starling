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
draws.

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
  not found (see accent-process above).

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
