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
