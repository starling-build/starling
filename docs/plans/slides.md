# Slides — a presentation app beside Writer

Status: **approved 2026-09-30** with three answers: one app for both
kinds, charts in v1, 16:9 by default (PowerPoint's own default since
2013: Widescreen, 13.333 x 7.5 in). Phase 5 of
`docs/plans/office.md`, given its own revision as that plan promised.
macOS first, like Writer; nothing here may break the wasm or iOS builds
of the shared code.

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
