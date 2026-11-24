# Legacy PowerPoint (.ppt) reader for Slides: design spec

Author: amd-opus, 2026-11-24. For: amd-9. No lab needed.

## Goal

Slides opens a binary PowerPoint 97-2003 file (.ppt, .pps, .pot) and draws it. Today these do
not open at all: 113 of the 481 new decks, and every .ppt a user picks.

## The one design decision: translate, do not build a second reader

Do what the .doc reader does (`DocRead.docx`, DocRead.swift:554) and the .xls reader does
(`XlsBuild.parts`): turn the binary records into **PresentationML parts in memory** and hand
them to the existing reader.

    .ppt bytes -> CompoundFile -> PptRecords -> PptBuild.parts -> [ZipEntry]
               -> PptxPackage(entries) -> PptxReader(package).read() -> (DeckState, DeckTheme, PptxPackage)

Why:
- `PptxReader` (2,400 lines plus the three `PptxSlideContext` files) already holds every rule we
  learned about master/layout inheritance, text levels, bullets, autofit, fills and pictures. A
  direct .ppt to `DeckState` reader would copy those rules and drift.
- `PptxPackage.init(_ entries: [ZipEntry])` (PptxReader.swift:42) takes parts directly, so no
  zip round trip is needed. Do not call `Zip.write` then `Pptx.read`.
- Save, export and the round-trip gate keep working, because the app holds a real package.
- The oracle is free: PowerPoint's own .pptx conversion of the same deck (see "Oracle" below).

Cost: you write XML strings. `DocArt.swift` already does this for shapes; reuse it.

## What is already in the tree

| Piece | File | Use for .ppt |
|---|---|---|
| Compound file reader (streams by path, bounds checked) | `CompoundFile.swift` | as is: `cf.stream("PowerPoint Document")`, `"Current User"`, `"Pictures"` |
| Drawing record walker, properties, pictures | `OfficeArt.swift` (`records`, `shapes`, `blipRecord`) | extend (step 5), do not fork |
| Shape to DrawingML: fill, line, preset name, freeform path, crop, WordArt | `DocArt.swift` (`fillLine`, `geometry`, `freeform`, `crop`, `rgb`) | move the format-neutral ones to `OfficeArt` or a new `ArtXML` enum and call them from both |
| .doc pipeline to copy the shape of | `DocRead.swift` (`parts`, `docx`) | model for `PptRead.parts` |
| CLI probes to copy | main.swift `--doc-info`, `--doc-parts`, `--xls-dump`, `--xls-parts` | add `--ppt-dump`, `--ppt-parts` |
| Test with a compound file built in the test | `XlsContainerTests.swift` (`compound(stream:)`) | lift that helper into a shared test file; extend it to several streams |
| Metafile pictures (WMF/EMF) | `Metafile.swift` | already used by Slides pictures; old decks are full of WMF clip art |

New files, all in `Slides/`, all shared code (see "Rules" at the end):
`PptRecords.swift` (container, persist directory, record tree), `PptText.swift` (text atoms and
style runs), `PptBuild.swift` (parts: presentation, masters, layouts, slides, theme, rels,
content types), `PptShapes.swift` (shape to `p:sp` / `p:pic` / `p:grpSp`).

## File structure in brief (MS-PPT)

Numbers below are from memory of [MS-PPT] and [MS-ODRAW]. The record type numbers I am sure of;
**check every bit mask in the two text tables against the spec (MS-PPT 2.9.13 TextCFException,
2.9.20 TextPFException) before coding them.** Apache POI's HSLF package is a readable second
source for understanding (do not copy code).

Streams: `Current User`, `PowerPoint Document`, `Pictures` (optional).

Every record: 8-byte header, the same shape as a drawing record (`OfficeArt.records` reads it):
version (4 bits) + instance (12 bits), type (u16), length (u32). Version 0xF means container.

Finding the live document (a file saved several times keeps old versions; latest wins):
1. `Current User` holds CurrentUserAtom (0x0FF6): after the header, size u32, **headerToken u32**
   (0xE391C05F plain, 0xF3D1C4DF encrypted), **offsetToCurrentEdit u32**.
2. At that offset in `PowerPoint Document`: UserEditAtom (0x0FF5): lastSlideIdRef u32, version
   u16, minor u8, major u8, **offsetLastEdit u32**, **offsetPersistDirectory u32**,
   **docPersistIdRef u32**, persistIdSeed u32, ...
3. At offsetPersistDirectory: PersistDirectoryAtom (0x1772): repeated { u32 = persistId (low 20
   bits) + count (high 12 bits); then `count` u32 stream offsets for persistId, persistId+1, ... }.
4. Follow offsetLastEdit back until 0. For each persistId keep the offset from the **newest**
   edit that names it. Result: `[persistId: offset]`.
5. `docPersistIdRef` gives the DocumentContainer (0x03E8).

DocumentContainer children that matter:
- DocumentAtom (0x03E9): slide size x, y (i32 each, **master units: 576 per inch**, so
  1 unit = 1587.5 EMU = 1/8 pt), notes size, zoom, notesMaster ref, handoutMaster ref,
  firstSlideNumber u16, slideSizeType u16, flags.
- Environment (0x03F2): FontCollection (0x07D5) of FontEntityAtom (0x0FB7: 32 UTF-16 units of
  face name, then charset, flags, pitch/family; the index in the collection is the "font ref"),
  default TextCFException (0x0FA4) and TextPFException (0x0FA5), TextMasterStyleAtom (0x0FA3)
  for text type "other", TextSIException (0x0FA9: default language).
- DrawingGroup (0x040B): holds the OfficeArt group container (0xF000) with the picture store
  (0xF001) of FBSE entries (0xF007). In a .ppt the FBSE holds **no picture**: its `foDelay`
  field (u32 at body offset 28) is the offset of the picture record in the `Pictures` stream.
- SlideListWithText (0x0FF0): **instance 1 = masters, instance 0 = slides, instance 2 = notes.**
  Each is a run of SlidePersistAtom (0x03F3: persistIdRef u32, flags u32, cTexts u32, slideId
  u32, reserved u32), and in the slides list each atom is followed by the text of that slide's
  placeholders (TextHeaderAtom + text + style atoms, in order). The order of SlidePersistAtoms
  in instance 0 is the slide order.
- HeadersFooters (0x0FD9), ExObjList (0x0409), List (0x07D0), EndDocument (0x03EA).

A slide (SlideContainer 0x03EE) or main master (MainMasterContainer 0x03F8), found through the
persist directory:
- SlideAtom (0x03EF), 24 bytes: layout geometry i32, 8 placeholder type bytes, **masterIdRef
  u32** (a slideId from the masters list; 0 on a main master), notesIdRef u32, **flags u16**
  (bit 0 follow master objects, bit 1 follow master scheme, bit 2 follow master background).
- ColorSchemeAtom (0x07F0): 8 colours of 4 bytes (r, g, b, unused) in the order background,
  text and lines, shadows, title text, fills, accent, accent and hyperlink, accent and followed
  hyperlink. A master holds several; the one with instance 1 is its own scheme.
- TextMasterStyleAtom (0x0FA3), masters only: one per text type, the type is the record
  **instance**: 0 title, 1 body, 2 notes, 4 other, 5 centre body, 6 centre title, 7 half body,
  8 quarter body. Body: cLevels u16, then per level [a level u16, only when instance >= 5]
  TextPFException, TextCFException.
- PPDrawing (0x040C): holds the OfficeArt drawing container (0xF002): a top group (0xF003)
  whose first shape is the group itself, then the slide's shapes; plus one more shape container
  (0xF004) directly in 0xF002 that is the **background shape** (its fill is the slide background).
- SlideShowSlideInfoAtom (0x03F9, transition), ProgTags (0x1388), RoundTrip atoms (0x040E theme,
  0x040F colour mapping, and others; see step 9).

A "title master" is a SlideContainer listed in the masters list whose SlideAtom.masterIdRef
names a main master.

Shapes on a slide are ordinary OfficeArt shapes with three PowerPoint-specific children:
- ClientAnchor (0xF010): 8 bytes, four i16 in master units **in the order top, left, right,
  bottom** (not left, top). A 16-byte form with four i32 exists too. A group member has
  ChildAnchor (0xF00F: left, top, right, bottom i32 in the group's space; already read).
- ClientData (0xF011): PowerPoint records: PlaceholderAtom (0x0BC3: position i32, **type u8**,
  size u8), ExObjRefAtom (0x0BC1), InteractiveInfo (0x0FF2), AnimationInfo (0x1014).
- ClientTextbox (0xF00D): the text records, or OutlineTextRefAtom (0x0F9E: an i32 index into
  this slide's text in SlideListWithText). **Placeholder text usually lives in the list, not
  in the shape.** Missing this gives slides with empty titles.

Placeholder types (PlaceholderAtom type): 1 master title, 2 master body, 3 master centre title,
4 master subtitle, 7 master date, 8 master slide number, 9 master footer, 10 master header,
13 title, 14 body, 15 centre title, 16 subtitle, 17 vertical title, 18 vertical body, 19 object,
20 graph, 21 table, 22 clip art, 23 org chart, 24 media, 26 picture.

Text records, in order inside a ClientTextbox or after a SlidePersistAtom:
- TextHeaderAtom (0x0F9F): text type u32 (same numbers as the master style instances).
- TextCharsAtom (0x0FA0): UTF-16LE. Or TextBytesAtom (0x0FA8): one byte per character, each
  byte is the **low byte of a UTF-16 unit** (so Latin-1), not a code page.
- StyleTextPropAtom (0x0FA1): paragraph runs then character runs. Each run: count u32
  [+ indent level u16 for paragraph runs], then a mask u32 and the fields the mask names, in a
  fixed order. Runs cover **text length + 1** (the implied final paragraph mark). If the atom
  is absent, the whole text takes the master style for its type.
- MasterTextPropAtom (0x0FA2): runs of (count u32, indent level u16), used when there is no
  StyleTextPropAtom. TextRulerAtom (0x0FA6): per-shape tab stops and per-level left margin and
  indent. TextSpecialInfoAtom (0x0FAA): language runs.
- Field marks, each with a text position: SlideNumberMCAtom 0x0FD8, DateTimeMCAtom 0x0FF7,
  GenericDateMCAtom 0x0FF8, HeaderMCAtom 0x0FF9, FooterMCAtom 0x0FFA, RTFDateTimeMCAtom 0x1015.
- In the text: 0x0D ends a paragraph, 0x0B is a line break inside a paragraph.

Units: positions and paragraph indents are master units (x 1587.5 = EMU; round once, at the
end). Font size is whole points. Line spacing: 0 or more is percent, negative is master units.
Space before/after: same sign rule. A colour is 4 bytes r, g, b, index: index 0xFE means the
RGB is literal, 0 to 7 names a colour of the scheme, 0xFF is "not set".

## Mapping to PresentationML

| .ppt | emitted part |
|---|---|
| DocumentAtom slide size, firstSlideNumber | `ppt/presentation.xml` `p:sldSz`, `firstSlideNum`; slide and master id lists |
| Main master | `ppt/slideMasters/slideMasterN.xml` + `ppt/theme/themeN.xml` |
| Master's ColorSchemeAtom | theme `a:clrScheme` + master `p:clrMap` (below) |
| TextMasterStyleAtom 0, 1, 4 | master `p:txStyles`: `p:titleStyle`, `p:bodyStyle`, `p:otherStyle`, levels as `a:lvl1pPr`... |
| TextMasterStyleAtom 5 to 8 | `a:lstStyle` on the matching placeholder of the layout (they differ from 0/1 only in a few fields) |
| Title master | a layout `type="title"` under its main master, carrying the title master's shapes |
| Other slides | one plain layout per main master (see "Layouts") |
| Slide | `ppt/slides/slideN.xml`, rel to its layout |
| Background shape fill; flag bit 2 clear | `p:bg` on the slide; otherwise omitted (inherits) |
| Flag bit 0 clear (does not follow master objects) | `showMasterSp="0"` |
| PlaceholderAtom | `p:nvPr/p:ph type=... idx=...` |
| Shape, picture, group, line, connector | `p:sp`, `p:pic`, `p:grpSp`, `p:cxnSp` with explicit `a:xfrm` always |
| Text | `p:txBody` with `a:p`, `a:r`, `a:br`, `a:fld` |
| Pictures stream record | `ppt/media/imageN.ext` + rel; dedupe by store index |

Colour scheme to theme. My expectation, to be confirmed in step 3 against five converted decks'
`theme1.xml` before coding: `lt1` = background, `dk1` = text and lines, `lt2` = shadows,
`dk2` = title text, `accent1` = fills, `accent2` = accent, `hlink` = accent and hyperlink,
`folHlink` = accent and followed hyperlink, with the plain `clrMap` (bg1=lt1, tx1=dk1, bg2=lt2,
tx2=dk2). A scheme index in a colour (0 to 7) becomes the matching `a:schemeClr`
(bg1, tx1, bg2, tx2, accent1, accent2, hlink, folHlink); a literal becomes `a:srgbClr`.

A slide that does not follow its master's scheme (flag bit 1 clear, scheme bytes differ): give
it a clone of the master with its own theme, deduplicated by the 32 scheme bytes. That keeps
inherited master text recoloured correctly with no special case in the reader. Check what
PowerPoint's conversion did on one such deck first; match it if it is simpler.

Layouts. In a .ppt every shape carries its own anchor, so position never comes from a layout.
The layout only has to pass the master through. Emit per main master: one `type="title"` layout
when a title master exists, and one pass-through layout for everything else. Do not try to
reproduce PowerPoint's eleven standard layouts. Text style inheritance then works by placeholder
type through the master's `txStyles`, which `PptxReader` already does.

Text properties (`a:pPr` / `a:rPr`). Emit **only fields whose mask bit is set**; everything
else must be left out so the master style shows through. Paragraph: level (`lvl`), alignment,
line spacing, space before/after, left margin (`marL`), first-line indent (`indent` =
indent - leftMargin), bullet on/off, bullet char, bullet font, bullet size (positive percent,
negative points), bullet colour, tab stops, default tab, font alignment, RTL. Character: bold,
italic, underline, shadow, emboss, font ref (`a:latin`), East Asian font ref (`a:ea`), symbol
font ref (`a:sym`), size, colour, baseline offset percent (`baseline`).

Shape body properties from OfficeArt properties: text insets (0x81 to 0x84, EMU), wrap (0x85),
anchor (0x87: top, middle, bottom and the centred forms), text flow / vertical (0x88),
autofit (the fit-shape-to-text bit of 0xBF), rotation (0x04, 16.16 degrees), flips (shape flags).

## Order of work: one unit test per step

Each step lands on its own (a PR through pr.sh) and adds one test file method. Build fixtures in
the test from bytes (as `XlsContainerTests` does): **no corpus file goes in git**. Put the record
builders (`rec(type, inst, body)`, `container(type, children)`, `compound(streams:)`) in one
shared test helper in step 1.

**Step 0. Census (half a day, no code landed except the probe).**
Add `--ppt-dump <file>`: streams, live persist objects, record-type counts, per slide the shape
count and text types. Run it over all 113 originals
(`/data/corpus-cache/staging/pptx-new/*-ppt-*-dev/*.ppt`, plus `zh-wide1-ppt`). Post on the
board: how many are encrypted, PowerPoint 95, have title masters, own-scheme slides, tables
(step 8), round-trip themes (step 9), OLE charts. The counts order steps 7 to 9; the order
below is my guess.
Test: none (probe only).

**Step 1. Container and live record directory** (`PptRecords.swift`).
`PptFile(cf)`: Current User, edit chain, persist directory, `record(persistId)`, document
container, slide and master lists in order. Refuse with a clear `FormatError.unsupported`:
encrypted (token 0xF3D1C4DF), no `PowerPoint Document` stream or no `Current User` (PowerPoint
95 and older). Cap the edit-chain walk (a loop must end) and bounds-check every offset.
Test `PptContainerTests`: a file with two edits where the second moves slide 1 to a new offset;
assert the newer offset wins, slide order follows the list, and the encrypted token throws.

**Step 2. Slides appear: empty slides at the right size and count** (`PptBuild.swift`).
Emit content types, root rels, `presentation.xml`, one minimal master + theme + layout, one
empty `slideN.xml` per slide. Wire up opening: `Pptx.read` sniffs the compound-file signature
(`OfficeCrypto.isCompoundFile`) and, when a `PowerPoint Document` stream exists, goes through
`PptBuild`; an encrypted .pptx (also a compound file) keeps its current path. Add "ppt", "pps",
"pot" to `DocumentKind.kind(forPath:)` and the open panel list in Backstage.swift:326. Saving
a deck opened from .ppt must go to Save As .pptx, never write PresentationML over the .ppt:
check what the `.doc` path does and do the same. Add `--ppt-parts <file> <dir>`.
Test `PptBuildTests.testSlideListAndSize`: 3 slides, 4:3 size 5760 x 4320 gives a `DeckState`
with 3 slides and a 720 x 540 pt page.

**Step 3. Masters, colour scheme, backgrounds.**
Real master per MainMaster, theme from its scheme, title master as the title layout, slide to
layout by SlideAtom.masterIdRef, background shape fill (solid first; gradient and picture in
step 6), the three follow-master flags. Confirm the scheme mapping against conversions first.
Test: two masters with different schemes, slide 2 on master 2 with its own solid background;
assert each slide's resolved background colour and its master.

**Step 4. Text** (`PptText.swift`). The biggest step; split into three PRs.
- 4a. Plain text: TextChars/TextBytes, paragraph and line breaks, OutlineTextRefAtom lookup
  into the slide list, placeholders (`p:ph`) by PlaceholderAtom, text boxes without one.
  Test: a title held in SlideListWithText and a body held in the shape; both texts read back,
  with the right placeholder roles and three paragraphs.
- 4b. Run and paragraph properties: StyleTextPropAtom parsing (a pure function: bytes + text
  length to `[PptParaRun]`, `[PptCharRun]`), run splitting where paragraph and character runs
  cross, the font collection, colours. Emit only masked fields.
  Test: one text with a bold red 24 pt run inside a centred level-1 paragraph; assert the runs,
  and assert an unmasked field is **absent** from the XML (not zero).
- 4c. Master text styles: TextMasterStyleAtom to `p:txStyles` and layout `lstStyle`,
  MasterTextPropAtom levels, TextRulerAtom overrides, document defaults from Environment.
  Test: a body with no StyleTextPropAtom at level 2 takes the master's level-2 size, bullet and
  indent.

**Step 5. Shapes** (`PptShapes.swift`, `OfficeArt.swift`).
Extend `ArtShape` rather than fork: keep the raw ranges of ClientAnchor, ClientData and
ClientTextbox (three `Range<Int>?` fields; the .xls cell anchor parse stays as it is), and pass
the background shape back separately. Then: anchor to `a:xfrm` (group members through the
group's coordinate space, as `DocArt.group` does), rotation and flips, preset geometry by shape
type (`DocArt.geometry` knows 14 of about 200: complete the table from MS-ODRAW's MSOSPT list,
which uses the same names as `PresetGeometry.swift` for almost all), adjust values (0x147 on),
freeforms (`DocArt.freeform`), solid fill, line colour/width/dash/arrowheads, shadow, groups,
lines and connectors, text body properties.
Test: a rounded rectangle with a 16-bit ClientAnchor (top, left, right, bottom order!), a
45-degree rotation and a child inside a group; assert frames in points, rotation, preset.

**Step 6. Pictures and richer fills.**
`OfficeArt.blips(group:delay:)`: for each FBSE read the record at `foDelay` in the `Pictures`
stream through the existing `blipRecord` (JPEG, PNG, DIB, WMF, EMF, PICT already handled).
Picture shapes (type 75, property 0x104 is the 1-based store index) to `p:pic` with crop
(`DocArt.crop`); picture and gradient fills for shapes and backgrounds (fill type 0x180,
colours 0x181/0x183, angle 0x18B, focus 0x18C, stops 0x197); OLE objects and MS Graph charts
draw their stored preview picture (the shape already names it), nothing more.
Test: a Pictures stream with one PNG and one deflated WMF, two FBSE entries; assert both
attach to the right shapes with the right bytes and crop.

**Step 7. Fields, header/footer, numbers.**
Slide number, date and footer fields from the MC atoms to `a:fld`; HeadersFooters container
(which of date, number, footer show, and the footer text); firstSlideNumber; hyperlinks on
text runs (InteractiveInfo + TextInteractiveInfoAtom 0x0FDF, target in ExObjList).
Test: a footer placeholder with a slide-number field on slide 2 with firstSlideNumber 5 reads "6".

**Step 8. Tables.**
A .ppt table is a **group** of cell rectangles (text boxes) and border lines, marked by group
property 0x039F with row heights in 0x03A0. Steps 5 and 4 already draw it correctly as shapes.
This step turns it into a real `a:tbl` in a `p:graphicFrame`: snap cell rectangles to a grid of
distinct x and y edges, merged cells by span, borders from the line shapes on each edge, cell
fill and insets from each rectangle. Do it only if the census shows enough tables and the
shape form scores worse than the table form; otherwise it is an editing nicety, not a render fix.
Test: a 2 x 2 table group with one merged row; assert grid columns, the span and cell texts.

**Step 9. Later, by census count.**
Notes pages (list instance 2); transitions (0x03F9) and animations; text effects (WordArt:
`DocArt.wordArtContent`); the round-trip theme atom (0x040E: a zipped theme part written by
PowerPoint 2007+, which gives real theme fonts and effects. Use it only after checking on
conversions that PowerPoint itself does; an edited-in-2003 file can hold a stale one);
per-run language; PowerPoint 95 files; encrypted files (`OfficeCrypto` has the RC4 pieces).

## Oracle and scoring

- Primary, exact: for each .ppt, PowerPoint's own conversion to .pptx. `OfficeApp --deck` on
  our translation against `--deck` on the conversion: same slide count, same shape count per
  slide, same frames, same text. Conversions exist in the cache for the r1 and r3 sets
  (`/data/corpus-cache/test/corpus/pptx-cjk-r1/decks`, `pptx-cjk-r3/*-ppt-r3-dev`); the m1
  .ppt folders in staging have prints but I found no conversions beside them: ask starling-bd
  for them (the Windows print helper can save-as).
- Secondary, the real target: the PowerPoint print of each deck (481 PDFs sit beside the
  originals) through `test/pptx-app-render.sh`, which needs teaching to take a .ppt input.
  The line-match score of our .ppt read should approach the score we already get on
  PowerPoint's conversion of the same deck: that gap is this reader's error, the rest is the
  Slides engine's and not yours.
- Step 0's probe and `--ppt-parts` are the debugging tools: dump our parts, diff against the
  unzipped conversion.

## Traps

1. Old versions stay in the stream. Never scan `PowerPoint Document` front to back for slides:
   go through the persist directory only, or deleted slides come back.
2. Placeholder text is usually in SlideListWithText, reached by OutlineTextRefAtom.
3. ClientAnchor is top, left, right, bottom, in master units, and comes in 8- and 16-byte forms.
   The existing `ArtShape.anchor` parse is the .xls cell anchor: do not reuse it.
4. Style runs count the final paragraph mark (text length + 1). Clamp, never trap, when the
   counts do not add up (they often overshoot).
5. TextBytesAtom is not code-page text.
6. An unmasked property is "inherit", not zero. Writing `b="0"` or `sz` for an unmasked field
   breaks master inheritance silently.
7. The same record type means different things by instance (SlideListWithText,
   TextMasterStyleAtom, ColorSchemeAtom). Always match on type and instance.
8. Some files hold a `PP97_DUALSTORAGE` storage (a PowerPoint 95 + 97 dual save): read the
   streams inside it when the root has no usable `Current User`.
9. The first shape in the top group is the group itself, and the background shape sits outside
   the group. Neither is a slide shape.
10. Every read is bounds-checked: a hostile file gives a throw, never a trap (the rule
    `CompoundFile.swift` states). Cap recursion depth on nested containers and groups.
11. `PptxReader` recurses through groups with large frames: read from `PptxPackage` directly as
    `Pptx.read` does, and keep the translation pass iterative or shallow.

## Rules that apply

- Shared code, also built for the web: no `.contains("literal")`, `.range(of:)`, `NSLock`,
  `String(format:)`, `trimmingCharacters`, `FileHandle.standardError` in these files. CLI probes
  stay in main.swift (native only).
- Microsoft fonts: metrics only. The font collection gives names; never read embedded font data.
- Rules by property, never by deck name. No corpus files, prints or scores in git. The held-out
  set is never used.
- Unit tests: `~/bin/unit-tests.sh --filter Ppt` before each PR. Land through `~/bin/pr.sh`.
- Slides gate: these PRs add a reader path and should not change any .pptx render; a changed
  .pptx score means the shared code (`OfficeArt`, `DocArt`) moved: check .xls and .doc tests too
  (`XlsContainerTests`, `DocHeaderPictureTests`).

## Size

Roughly 2,500 to 3,500 lines for steps 1 to 7. Steps 1 to 4a make most decks open with their
text in place; 4b to 6 make them look right. Step 4 is the long one.
