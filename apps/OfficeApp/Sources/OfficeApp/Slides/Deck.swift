// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The presentation model (docs/plans/slides.md). Points are the unit
// everywhere; the file format's EMU (12700 per point) are converted at the
// edges. Shapes are classes, not values: a text shape owns the
// RichDocumentController its on-canvas editor binds to, and that identity
// has to survive every edit to the deck around it.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// What a placeholder is for. The names are PresentationML's `type`
/// values, so the reader and writer need no table.
enum PlaceholderRole: String {
    case ctrTitle, subTitle, title, body
}

enum ShapeKind: Equatable {
    case placeholder(PlaceholderRole)
    case textBox
    /// A preset drawing (`prstGeom`): its DrawingML name.
    case geometry(ShapePreset)
    /// A picture (`p:pic`).
    case picture(ImageAttachment)
    /// A table: its text is a document holding one table (Writer's cell
    /// model), edited in place like any text body.
    case table
    /// A chart, drawn from its own data (Chart.swift).
    case chart(Chart)
    /// Something read from a file that the deck does not model — SmartArt,
    /// a video, a chart of a kind this app cannot draw — kept as its XML so
    /// a save writes it back untouched, and drawn as a labelled box.
    case opaque(OpaqueObject)
}

extension ShapeKind {
    /// Whether an undo can restore `other` into a shape of this kind in
    /// place: the same kind, or a chart either way (its data is a value,
    /// the shape — selected, its data grid open — stays the same object).
    func sameObject(_ other: ShapeKind) -> Bool {
        if case .chart = self, case .chart = other { return true }
        return self == other
    }
}

/// A text field (`a:fld`) that is a shape's whole text: the slide number
/// or the date, recomputed as the deck changes and written back as a
/// field, not as the text it happened to show.
struct SlideField: Equatable {
    /// PresentationML's field type: "slidenum", "datetime", "datetime1"…
    var type: String
    /// The field's GUID (`id`), kept so a save names the same field.
    var id: String

    var isSlideNumber: Bool { type == "slidenum" }

    /// The text the field shows on slide `number` (1-based) today.
    func value(slide number: Int, date: Date = Date()) -> String {
        if isSlideNumber { return "\(number)" }
        let pattern: String
        switch type {
        case "datetime2": pattern = "EEEE, MMMM d, yyyy"
        case "datetime3": pattern = "d MMMM yyyy"
        case "datetime4": pattern = "MMMM d, yyyy"
        case "datetime5": pattern = "d-MMM-yy"
        case "datetime6": pattern = "MMMM yy"
        case "datetime7": pattern = "MMM-yy"
        case "datetime10": pattern = "H:mm"
        case "datetime11": pattern = "H:mm:ss"
        case "datetime12": pattern = "h:mm a"
        case "datetime13": pattern = "h:mm:ss a"
        default: pattern = "M/d/yyyy"
        }
        return OfficeDates.format(date, pattern)
    }

    static func newId() -> String { "{" + UUID().uuidString + "}" }
}

/// The group (`p:grpSp`) a shape was read from. The deck edits group
/// members as shapes of their own; a save puts the ones still side by side
/// back in a group with this id, which the slide's animations may name.
struct ShapeGroup: Equatable {
    var fileId: Int?
    var name: String
    /// Tells this group from another of the same slide.
    var key: Int
    /// `cNvPr hidden="1"`: not shown, written back as such.
    var hidden = false
    /// The group's own fill (`p:grpSpPr`'s solid, gradient, picture or
    /// pattern fill) as read: members saying `a:grpFill` take it, so a
    /// save writes it back on the group it rebuilds.
    var fillXML: String? = nil
    /// That fill, resolved, for the members this app draws.
    var fillColor: Color? = nil
}

/// A connector as read (`p:cxnSp`): the deck draws it as a straight line
/// between its ends, and while that line and its outline are unchanged a
/// save writes the original back — curves, arrowheads, connections and
/// all — at `box`, its unrotated frame on the slide.
struct KeptLine: Equatable {
    var line: Rect
    var box: Rect
    var outline: Color?
    var width: Double
}

/// A picture as read (with `sourceXML`): written back verbatim while its
/// image, crop and turn are unchanged, so what this app does not model —
/// the blip's recolouring and transparency, a crop to a shape, a flip, a
/// fill or outline behind the picture — survives a save.
struct KeptPicture: Equatable {
    var imageId: String
    var crop: EdgeInsets?
    var rotation: Double
}

/// A shape's look as its file spelled it: the fill, line and effects in its
/// `spPr`, and its `p:style`. The deck draws what it models (a colour, an
/// outline); a save writes these back while the shape's fill and outline
/// are still what was read from them.
struct KeptLook: Equatable {
    var fill: String?
    var line: String?
    var effects: String
    var style: String?
    var readFill: Color?
    var readFillScheme: String?
    var readOutline: Color?
    var readWidth: Double

    func fillKept(_ s: ShapeState) -> Bool { s.fill == readFill && s.fillScheme == readFillScheme }
    func lineKept(_ s: ShapeState) -> Bool { s.outline == readOutline && s.outlineWidth == readWidth }
}

/// A text shape as it was read, besides its text: while all of this and
/// the text are unchanged, a save writes the shape's own XML back, so
/// what this app models loosely — the master's bullet glyph, colour and
/// size, shadows on runs, tab stops, the style a plain text box inherits
/// from the presentation — survives a round trip untouched.
struct ReadShape: Equatable {
    var name: String
    var kind: ShapeKind
    var frame: Rect
    var rotation: Double
    var fill: Color?
    var fillScheme: String?
    var outline: Color?
    var outlineWidth: Double
    var anchor: TextAnchor
    var insets: EdgeInsets
    var autofit: Bool
    var fontScale: Double
    var field: SlideField?

    init(_ s: ShapeState) {
        name = s.name; kind = s.kind; frame = s.frame; rotation = s.rotation
        fill = s.fill; fillScheme = s.fillScheme; outline = s.outline; outlineWidth = s.outlineWidth
        anchor = s.anchor; insets = s.insets; autofit = s.autofit; fontScale = s.fontScale; field = s.field
    }

    /// Still the shape that was read, text included.
    func unchanged(_ s: ShapeState) -> Bool { self == ReadShape(s) && s.text == s.sourceText }
}

/// An element carried through a round trip verbatim.
struct OpaqueObject: Equatable {
    /// The element as read (`p:graphicFrame`, `p:grpSp`, …).
    var xml: String
    /// What the box says ("Chart", "SmartArt", "Video").
    var label: String
    /// The slide part it came from: where its `r:id`s resolve.
    var sourcePart: String
    /// A freeform's outline, when its geometry could be read: drawn with
    /// the shape's fill and line instead of a labelled box.
    var freeform: FreeformGeometry? = nil
    /// What the object looks like, as shapes (a SmartArt's drawing part):
    /// drawn in its place, never written — the element above is the file's.
    var rendering: [ShapeState] = []
    /// The drawing is cut to the object's frame (a broken picture's box).
    var clipsRendering = false
}

/// An arrowhead (`a:headEnd`/`a:tailEnd`): its kind ("triangle",
/// "arrow", "stealth", "diamond", "oval") and its width and length as
/// multiples of the line's width — 2, 3 or 5 for sm, med, lg.
struct LineEnd: Equatable {
    var kind: String
    var width: Double
    var length: Double
}

/// A DrawingML preset shape, by its `prst` name. Open-ended: a file can
/// name any of PowerPoint's ~180 presets, and a shape keeps its name through
/// a save whether or not this app draws it exactly (unknown ones draw as
/// their bounding rectangle, PowerPoint redraws them properly).
struct ShapePreset: RawRepresentable, Hashable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    static let rect = ShapePreset(rawValue: "rect")
    static let roundRect = ShapePreset(rawValue: "roundRect")
    static let ellipse = ShapePreset(rawValue: "ellipse")
    static let triangle = ShapePreset(rawValue: "triangle")
    static let rightArrow = ShapePreset(rawValue: "rightArrow")
    static let line = ShapePreset(rawValue: "line")
    static let star5 = ShapePreset(rawValue: "star5")
    static let wedgeRectCallout = ShapePreset(rawValue: "wedgeRectCallout")

    /// What the gallery offers, in order.
    static let allCases: [ShapePreset] = [.rect, .roundRect, .ellipse, .triangle, .rightArrow, .line, .star5,
                                          .wedgeRectCallout]

    var name: String {
        switch rawValue {
        case "rect": return "Rectangle"
        case "roundRect": return "Rounded Rectangle"
        case "ellipse": return "Oval"
        case "triangle": return "Triangle"
        case "rightArrow": return "Right Arrow"
        case "line": return "Line"
        case "star5": return "Star"
        case "wedgeRectCallout": return "Callout"
        default: return rawValue
        }
    }

    var isLine: Bool { rawValue == "line" || rawValue.hasPrefix("straightConnector") }

    /// Open paths — braces, brackets, arcs, bent and curved connectors:
    /// stroked, never filled, whatever their style says.
    var isOpenPath: Bool {
        isLine || ["leftBrace", "rightBrace", "leftBracket", "rightBracket", "bracePair", "bracketPair", "arc"]
            .contains(rawValue) || rawValue.hasPrefix("bentConnector") || rawValue.hasPrefix("curvedConnector")
    }
}

/// How a slide comes on in the show.
struct SlideTransition: Equatable {
    enum Kind: String, CaseIterable { case none, fade, push, wipe, cover }
    enum Direction: String { case left = "l", right = "r", up = "u", down = "d" }

    var kind: Kind = .none
    /// Where the new slide comes from (push, wipe, cover): PresentationML's
    /// `dir`, which names the side the motion heads to.
    var direction: Direction = .left
    var duration = 0.5
    /// A transition this app does not draw (morph, vortex…), as read:
    /// shown as a fade, written back as it was until the slide's
    /// transition is changed here.
    var raw: String? = nil

    var name: String {
        switch kind {
        case .none: return "None"
        case .fade: return "Fade"
        case .push: return "Push"
        case .wipe: return "Wipe"
        case .cover: return "Cover"
        }
    }
}

/// A slide's (or a shape's) fill: a colour, a gradient, or a picture.
/// `a:effectLst/a:fillOverlay`: a second fill laid over a shape's own,
/// blended into it (`mult`, `screen`, `darken`, `lighten`, `over`).
final class FillOverlay: Equatable {
    let fill: SlideFill
    let blend: String
    init(fill: SlideFill, blend: String) { self.fill = fill; self.blend = blend }
    static func == (a: FillOverlay, b: FillOverlay) -> Bool { a.fill == b.fill && a.blend == b.blend }
}

struct SlideFill: Equatable {
    var color: Color? = nil
    /// Laid over the fill and blended into it (the Concourse theme's
    /// corner: a pale texture multiplied by a blue gradient).
    var overlay: FillOverlay? = nil
    var image: ImageAttachment? = nil
    /// The picture's transparency (`a:alphaModFix`) and duotone recolouring
    /// (`a:duotone`: the two colours luminance maps between).
    var imageAlpha = 1.0
    var duotone: [Color]? = nil
    /// Brightness and contrast (`a:lum`) or black and white (`a:biLevel`),
    /// as a colour matrix (`PptxReader.blipLevels`).
    var imageLevels: [Double]? = nil
    /// `a:tile`: the picture repeats at its own size (times `tileScale`
    /// across and `tileScaleY` down) instead of stretching. One tile is
    /// put at `tileAlign` within the area — fractions of the room left
    /// over, so (0.5, 0) is `algn="t"`, the top middle — then moved by
    /// `tileOffset` (points), and the rest are laid edge to edge from it.
    var tiled = false
    var tileScale = 1.0
    var tileScaleY = 1.0
    var tileAlign = Offset(0, 0)
    var tileOffset = Offset(0, 0)
    /// The tiles are laid from the slide's corner, not the area's: a
    /// pattern fill (`a:pattFill`), whose pixels line up across shapes.
    var tileAnchored = false
    /// Gradient stops (position 0...1, colour) and the direction, degrees
    /// clockwise from left-to-right.
    var stops: [GradientStop] = []
    var angle = 0.0
    /// The blend between two stops eases in and out (a half cosine, in
    /// linear light) instead of running evenly. PowerPoint's own export
    /// has it for a gradient whose stops are plain colours — red to green
    /// keeps to red, then to green, a tenth of the way longer at each end
    /// — and an even blend for one built of theme colours with
    /// modifiers. Why it tells them apart is not known; that it does is
    /// read off the ramps it stores (tdf105739, tdf109067).
    var eased = false
    /// A stop is a theme colour under a modifier (`tint`, `shade`,
    /// `satMod`…). A gradient of such stops blends evenly in sRGB, not in
    /// linear light, as PowerPoint's export blends it — GeomLec1's dark
    /// background runs evenly from black to grey, and blended in linear
    /// light it was pale for half its width; every one of the 350 sRGB
    /// ramps its prints store is straight in sRGB (backgrounds' text box,
    /// navy to pale blue, is 113,141,181 a quarter of the way, where
    /// linear light made it 144…). Any other is blended in linear light
    /// and shifted as PowerPoint's print shows it (`SlidePainter
    /// .linearLight`). (A plain colour under a modifier is not one:
    /// ImportWordArtGradient's alpha'd `srgbClr` stops are in linear
    /// light. Nor is a `gamma` stop's, `squared`.)
    var even = false
    /// The gradient is printed as part of a picture — a shape with depth
    /// or a camera, which PowerPoint renders and places as an image — so
    /// in sRGB, without the shift its own gradients print with
    /// (`SlidePainter.linearLight`): Scene3d_orthographicFront's yellow to
    /// cyan band starts 21,193,254 in its print, as lit, not shifted.
    var unshifted = false
    /// A stop is under `gamma` (an Office 2003 template's shaded bands,
    /// `gamma`/`shade`/`invGamma`): PowerPoint's ramp then holds to the
    /// lighter stop and leaves it as the square of the way along, in
    /// sRGB — the 45541 decks' three gradients, read off its export, to a
    /// level or two (205 → 94 is 193, 159, 102 at a quarter, half, three
    /// quarters; ours ran 177, 150, 122 in linear light).
    var squared = false
    /// The gradient names no direction (no `a:lin`, no `a:path`): its
    /// blend runs evenly in sRGB, whatever its stops — tdf104788's orange
    /// to cream bars, whose blue channel climbs 16, 33, 51… in
    /// PowerPoint's print, a straight line, where the eased linear-light
    /// blend of plain stops gave 24, 55, 84.
    var undirected = false
    /// `a:lin scaled="1"`: the angle is of the fill's unit square, so it
    /// stretches with the area — 45° runs corner to corner of a wide
    /// slide, its bands of colour lying along the other diagonal.
    var scaled = false
    /// `a:path`: the gradient radiates from `fillTo` (a rectangle in
    /// fractions of the area, usually a point) out to the edges — circles
    /// for `circle`, the area's own proportions for `rect` and `shape` —
    /// instead of running along `angle`.
    var path: GradientPath? = nil
    var fillTo = Rect.fromLTRB(0.5, 0.5, 0.5, 0.5)
    /// `a:stretch/a:fillRect`: where a stretched picture sits within the
    /// area, as fractions inset from each edge (negative: beyond it, and
    /// clipped).
    var imageInset = EdgeInsets.zero

    enum GradientPath: String { case circle, rect, shape }

    struct GradientStop: Equatable {
        var position: Double
        var color: Color
    }

    /// The colour a gradient's stops give at `t` (0 to 1), blended evenly
    /// between the two either side; the end stops' beyond them.
    static func colorAt(_ stops: [GradientStop], _ t: Double) -> Color {
        guard let first = stops.first, let last = stops.last else { return Color(0xFF000000) }
        if t <= first.position { return first.color }
        if t >= last.position { return last.color }
        for (a, b) in zip(stops, stops.dropFirst()) where t >= a.position && t <= b.position {
            let k = b.position > a.position ? (t - a.position) / (b.position - a.position) : 0
            func ch(_ x: Int, _ y: Int) -> Int { Int((Double(x) + (Double(y) - Double(x)) * k).rounded()) }
            return Color(argb: ch(a.color.alpha, b.color.alpha), ch(a.color.red, b.color.red),
                         ch(a.color.green, b.color.green), ch(a.color.blue, b.color.blue))
        }
        return last.color
    }
}

/// `bodyPr/a:prstTxWarp`: WordArt's bend. The preset's name, its adjust
/// values in the file's order (thousandths of a percent, or 60000ths of
/// a degree), and the element as read, which is what is written back.
struct TextWarp: Equatable {
    var preset: String
    var adjust: [Double] = []
    var xml: String
}

/// `a:scene3d` and `a:sp3d`: a shape pushed back into a solid and looked
/// at from an angle. The depth in points; the camera's rotation in
/// degrees (latitude, longitude, revolution); an oblique camera's slide
/// per unit of depth instead of a rotation; the sides' colour when the
/// file names one.
struct Scene3D: Equatable {
    var depth: Double
    var lat = 0.0, lon = 0.0, rev = 0.0
    var oblique: Offset? = nil
    /// A legacy perspective camera: what lies behind also shrinks toward
    /// a point as it slides.
    var perspective = false
    var extrusionColor: Color? = nil
    /// `prstMaterial="legacyWireframe"`: edges only.
    var wireframe = false
    /// `a:lightRig`: the rig's name, and how far `dir` turns it about the
    /// line of sight, in degrees clockwise ("t" 0, "r" 90).
    var rig = "threePt"
    var rigTurn = 0.0
    /// A `legacy…` camera, which PowerPoint lights its old way.
    var legacy = false

    /// A camera that only revolves a shape with no depth: the shape
    /// turned in its own plane, and nothing of a solid to draw.
    var isFlatTurn: Bool { depth == 0 && lat == 0 && lon == 0 && oblique == nil }
}

/// What a run of WordArt is drawn with beyond its colour: a gradient or
/// picture fill, no fill at all, and an outline (`a:rPr/a:ln`), in points.
struct RunLook: Equatable {
    /// How much of its paragraph the run is, in UTF-16 units: looks are
    /// found by where a character falls, since the document merges runs
    /// that are alike in everything it knows of.
    var length = 0
    var fill: SlideFill? = nil
    var noFill = false
    var outline: Color? = nil
    var outlineWidth = 0.75

    var isPlain: Bool { fill == nil && !noFill && outline == nil }
}

enum TextAnchor: String {
    case top = "t", middle = "ctr", bottom = "b"
}

/// One object on a slide.
final class SlideShape {
    let id: Int
    var name: String
    var kind: ShapeKind
    /// Position and size on the slide, in points.
    var frame: Rect
    /// Clockwise, in degrees, about the frame's centre.
    var rotation = 0.0
    var fill: Color? = nil
    var outline: Color? = nil
    /// The theme slot the fill came from ("accent1"), so a new theme
    /// recolours it; nil for a colour picked as itself.
    var fillScheme: String? = nil
    var outlineWidth = 0.75
    /// The text body, if the shape has one.
    let text: RichDocumentController?
    /// The look an empty body types with: the shape's own text theme.
    /// Replaced, never edited in place: editors and cached layouts notice a
    /// new theme object, and miss a changed one.
    var textTheme: RichTextTheme?
    var anchor: TextAnchor = .top
    /// PowerPoint's default body insets: 0.1 in left and right, 0.05 in top
    /// and bottom.
    var insets = EdgeInsets(left: 7.2, top: 3.6, right: 7.2, bottom: 3.6)
    /// A diagram's margins are fractions of its font size: they shrink
    /// with the text when it is fitted.
    var insetsFollowFont = false
    /// A diagram laid out here: the shapes that end at one size
    /// (`starling:sizeGroup`, from the layout's `op="equ"` constraints).
    var sizeGroup: String? = nil
    /// `a:ln/a:prstDash`: the outline's dash pattern ("dash", "sysDot"…);
    /// nil for a solid line.
    var outlineDash: String? = nil
    /// `a:ln`'s join (`a:round`, `a:bevel`, `a:miter`): "round", "bevel",
    /// or nil for a mitred one.
    var outlineJoin: String? = nil
    /// `a:ln cap`: "rnd" or "sq", or nil for flat ends.
    var outlineCap: String? = nil
    /// A gradient line (`a:ln/a:gradFill`), drawn along the outline over
    /// the shape's box; nil for a line of one colour (`outline`).
    var outlineFill: SlideFill? = nil
    /// `a:ln/a:headEnd` and `a:tailEnd`: an arrowhead at the line's start
    /// and end.
    var headEnd: LineEnd? = nil
    var tailEnd: LineEnd? = nil
    /// `a:ln cmpd`: "dbl", "thickThin", "thinThick" or "tri"; nil for one
    /// line.
    var outlineCompound: String? = nil
    /// `bodyPr vert`: the text set a quarter turn clockwise (1: `vert`,
    /// `eaVert`) or anticlockwise (-1: `vert270`); 0 across.
    var textTurn = 0
    /// The text turned about its own middle, degrees clockwise (a
    /// camera's `rev`, the other way).
    var textSpin = 0.0
    /// A diagram's text: its lines step at its face's own height, not
    /// PowerPoint's 1.2 (`ShapeState.naturalLines`).
    var naturalLines = false
    /// `a:effectLst/a:outerShdw` (or the theme's, through `effectRef`):
    /// a blurred copy of the outline cast under the shape.
    var shadow: CharShadow? = nil
    /// `a:effectLst/a:innerShdw`: a shadow cast inward, round the inside
    /// of the outline.
    var innerShadow: CharShadow? = nil
    /// `a:glow`: a blurred halo of `glowColor` this many points out round
    /// the outline; nil for none.
    var glowRadius: Double? = nil
    var glowColor: Color? = nil
    /// `a:softEdge`: the shape fades out over this many points inside its
    /// outline; nil for a hard edge.
    var softEdge: Double? = nil
    /// `a:sp3d/a:bevelT` on a shape seen square on: its face lit as a
    /// raised edge (`SlidePainter.paintBevel`); nil for none.
    var bevel: ShapeBevel? = nil
    /// The part of `insets` that is the geometry's text rectangle (an
    /// oval's inscribed box, a chevron's notch): it stays when margins that
    /// follow the font shrink with it.
    var shapeInsets = EdgeInsets.zero
    /// `bodyPr wrap="none"`: lines break only where the text says, however
    /// narrow the box — the text runs past its edges, from the side its
    /// first paragraph is aligned to. (Drawn so; the editor still wraps.)
    var noWrap = false
    /// `bodyPr anchorCtr`: the text, as a block as wide as its widest
    /// line, centred across the box, its lines aligned within the block
    /// (vertical text: centred down it — eaVertAnchor's lower row).
    var anchorCentred = false
    /// `bodyPr numCol`: the text runs down this many columns of the box,
    /// filling each to the box's height before the next, `columnGap`
    /// points (`spcCol`) apart. (Drawn so; the editor edits one column.)
    var columns = 1
    var columnGap = 0.0
    /// WordArt: the bend the text is drawn in (`WordArt.paint`), and each
    /// paragraph's runs' looks as the file has them — by position, so
    /// they hold only while the text has the runs it was read with.
    var warp: TextWarp? = nil
    var runLooks: [[RunLook]] = []
    /// The shape as a solid seen from an angle (`Extrusion.paint`).
    var scene3d: Scene3D? = nil
    /// `normAutofit lnSpcReduction`: the share PowerPoint took off the
    /// line spacing to fit (0.2 = lines at 80%); the theme carries it.
    var lineReduction = 0.0
    /// The insets as drawn: scaled with the text when they follow it.
    var drawInsets: EdgeInsets { insets(atFontScale: fontScale) }
    /// The insets with the text at `k` of its size: the margins that follow
    /// the font scaled by it, the geometry's share kept.
    func insets(atFontScale k: Double) -> EdgeInsets {
        guard insetsFollowFont, k != 1 else { return insets }
        let g = shapeInsets
        return EdgeInsets(left: g.left + (insets.left - g.left) * k, top: g.top + (insets.top - g.top) * k,
                          right: g.right + (insets.right - g.right) * k, bottom: g.bottom + (insets.bottom - g.bottom) * k)
    }
    /// Shown greyed in an empty placeholder until it is typed into.
    var prompt: String?
    /// The placeholder's `type` and `idx` in the file, which bind it to its
    /// layout's placeholder; kept so a save binds it to the same one.
    var phType: String? = nil
    var phIdx: String? = nil
    /// A picture's crop: the fraction of the image cut from each edge.
    var crop: EdgeInsets? = nil
    /// A picture's mirroring and its crop to a shape (`prstGeom` other than
    /// rect), as read: drawn, and written back through the kept element.
    var flipH = false
    var flipV = false
    var pictureGeometry: ShapePreset? = nil
    /// A picture's transparency and duotone recolouring, as read.
    var pictureAlpha = 1.0
    var pictureDuotone: [Color]? = nil
    /// Brightness and contrast, or black and white, as a colour matrix.
    var pictureLevels: [Double]? = nil
    /// PowerPoint's Set Transparent Color (`a:clrChange`): the colour of
    /// the picture that is drawn as another — in every file seen, as
    /// nothing at all — as [from, to]. Drawn for a metafile's fills,
    /// lines and text; a bitmap's pixels are not looked through yet.
    var pictureColorChange: [Color]? = nil
    /// A picture's place within its frame (`a:fillRect`), as fractions
    /// inset from each edge.
    var pictureInset = EdgeInsets.zero
    /// `useBgFill="1"`: the shape is filled with the slide's background
    /// (a window onto it, over whatever lies between).
    var fillsWithBackground = false
    /// A kept object's look as shapes (`OpaqueObject.rendering`), built
    /// with this shape; drawn where the object sits.
    var rendered: [SlideShape] = []
    /// Not drawn: a date, footer or slide-number placeholder whose layout
    /// has no such placeholder, which PowerPoint leaves off the slide (the
    /// file still has it, and a save keeps it).
    var invisible = false
    /// A placeholder's geometry inherited from its layout or master: a
    /// preset, or a custom path evaluated for this shape's size.
    var inheritedPreset: ShapePreset? = nil
    var customPath: FreeformGeometry? = nil
    /// A gradient or picture fill as read: drawn within the outline where
    /// `fill` (a flat colour) would be. Written back through the kept look.
    var fillStyle: SlideFill? = nil
    /// The shape's id in the file it came from (`cNvPr id`): kept, because
    /// the slide's animations name shapes by it.
    var fileId: Int? = nil
    /// A table as read, with the text it had then: written back verbatim
    /// while the text is unchanged (cell fills, borders and styles this app
    /// only approximates survive), regenerated once it is edited.
    var sourceXML: String? = nil
    var sourceText: RichDocument? = nil
    var sourcePart: String? = nil
    /// A chart as read: written back through its own part while unchanged.
    var sourceChart: Chart? = nil
    /// The field this shape's text is, if it is one (slide number, date).
    var field: SlideField? = nil
    /// The group the shape was read from, if any.
    var group: ShapeGroup? = nil
    /// A connector's geometry as read (with `sourceXML`).
    var keptLine: KeptLine? = nil
    /// A picture as read (with `sourceXML`).
    var keptPicture: KeptPicture? = nil
    /// Shrink the text to fit the shape (PowerPoint's `normAutofit`), and
    /// the scale it is drawn at now (its sizes stay as typed).
    var autofit = false
    var fontScale = 1.0
    /// The look as read (fill, line, effects, style), with `sourcePart`.
    var keptLook: KeptLook? = nil
    /// What the field last showed, to tell its own updates from typing.
    var fieldShown: String? = nil

    init(id: Int, name: String, kind: ShapeKind, frame: Rect, text: RichDocumentController?,
         textTheme: RichTextTheme?, anchor: TextAnchor = .top, prompt: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.frame = frame
        self.text = text
        self.textTheme = textTheme
        self.anchor = anchor
        self.prompt = prompt
    }

    var isEmptyText: Bool {
        guard let doc = text?.document else { return true }
        return doc.paragraphs.allSatisfy { $0.text.isEmpty && $0.image == nil }
    }

    var role: PlaceholderRole? {
        if case .placeholder(let r) = kind { return r }
        return nil
    }

    var preset: ShapePreset? {
        if case .geometry(let p) = kind { return p }
        return nil
    }

    var picture: ImageAttachment? {
        if case .picture(let image) = kind { return image }
        return nil
    }

    var chart: Chart? {
        if case .chart(let c) = kind { return c }
        return nil
    }

    var opaque: OpaqueObject? {
        if case .opaque(let o) = kind { return o }
        return nil
    }

    /// Text boxes and placeholders are clicked into; drawn shapes are
    /// selected first and edited on a second click, as PowerPoint does;
    /// pictures and kept objects have no text and are grabbed whole.
    var editsOnFirstClick: Bool {
        switch kind {
        case .placeholder, .textBox, .table: return true
        default: return false
        }
    }

    /// The table's id inside its document, for a table shape.
    var tableId: String? {
        guard kind == .table else { return nil }
        return text?.document.paragraphs.first?.cell?.table
    }
}

/// The slide layouts every new deck offers — PowerPoint's familiar seven,
/// drawn to our own theme.
enum SlideLayoutKind: String, CaseIterable {
    case titleSlide, titleAndContent, sectionHeader, twoContent, comparison, titleOnly, blank

    var name: String {
        switch self {
        case .titleSlide: return "Title Slide"
        case .titleAndContent: return "Title and Content"
        case .sectionHeader: return "Section Header"
        case .twoContent: return "Two Content"
        case .comparison: return "Comparison"
        case .titleOnly: return "Title Only"
        case .blank: return "Blank"
        }
    }
}

/// Colours and fonts a deck draws with. The default is our own, not any
/// shipped Office theme.
struct DeckTheme: Equatable {
    var name = "Starling"
    var headingFont = "Calibri Light"
    var bodyFont = "Calibri"
    var background = Color(0xFFFFFFFF)
    /// A gradient behind every slide, top to bottom, when the theme has one.
    var backgroundStops: [Color] = []
    var text = Color(0xFF1B1B1B)
    var subtle = Color(0xFF595959)
    var accents: [Color] = [
        Color(0xFF2B6CB0), Color(0xFFDD6B20), Color(0xFF718096),
        Color(0xFFD69E2E), Color(0xFF319795), Color(0xFF38A169),
    ]

    /// The slide background this theme paints.
    var backgroundFill: SlideFill {
        guard backgroundStops.count >= 2 else { return SlideFill(color: background) }
        let n = Double(backgroundStops.count - 1)
        return SlideFill(color: backgroundStops[0],
                         stops: backgroundStops.enumerated().map { SlideFill.GradientStop(position: Double($0.offset) / n, color: $0.element) },
                         angle: 90)
    }

    /// The Design tab's gallery: our own, named for what they look like.
    static let presets: [DeckTheme] = [
        DeckTheme(),
        DeckTheme(name: "Slate", headingFont: "Calibri Light", bodyFont: "Calibri",
                  background: Color(0xFF1E2430), text: Color(0xFFF2F4F8), subtle: Color(0xFFB4BCCB),
                  accents: [Color(0xFF5AA9E6), Color(0xFFF2A65A), Color(0xFF8C9AB0),
                            Color(0xFFF6D365), Color(0xFF5CC8B8), Color(0xFF7BD389)]),
        DeckTheme(name: "Paper", headingFont: "Cambria", bodyFont: "Calibri",
                  background: Color(0xFFFBF7EF), text: Color(0xFF2B2622), subtle: Color(0xFF6E655C),
                  accents: [Color(0xFF8C3B2E), Color(0xFF3E6B5A), Color(0xFFB08B4F),
                            Color(0xFF5B5F97), Color(0xFFA26769), Color(0xFF6B8F71)]),
        DeckTheme(name: "Ocean", headingFont: "Calibri Light", bodyFont: "Calibri",
                  background: Color(0xFF0B3C5D), backgroundStops: [Color(0xFF0B3C5D), Color(0xFF05213A)],
                  text: Color(0xFFFFFFFF), subtle: Color(0xFFC7DCEB),
                  accents: [Color(0xFF34C3EB), Color(0xFFFFB547), Color(0xFF7FA7C2),
                            Color(0xFFF5E663), Color(0xFF3ED6A0), Color(0xFFFF7A6B)]),
        DeckTheme(name: "Forest", headingFont: "Cambria", bodyFont: "Calibri",
                  background: Color(0xFF1F3A2E), text: Color(0xFFF4F1E8), subtle: Color(0xFFC8D5C0),
                  accents: [Color(0xFF9CCB86), Color(0xFFE9B44C), Color(0xFF7C9A88),
                            Color(0xFFD9E7A6), Color(0xFF6FB3A6), Color(0xFFE07A5F)]),
        DeckTheme(name: "Sunrise", headingFont: "Calibri Light", bodyFont: "Calibri",
                  background: Color(0xFFFFFFFF), text: Color(0xFF2D1E2F), subtle: Color(0xFF6D5A6E),
                  accents: [Color(0xFFE4572E), Color(0xFFF3A712), Color(0xFF29335C),
                            Color(0xFFA8C686), Color(0xFF669BBC), Color(0xFF8E5572)]),
    ]
}

/// One slide.
final class Slide {
    let id: Int
    var layout: SlideLayoutKind
    var shapes: [SlideShape]
    let notes: RichDocumentController
    var hidden = false
    /// `showMasterSp="0"`: the layout's and master's own shapes stay off
    /// this slide. Not drawn by this app (it draws no master shapes), but
    /// written back, or PowerPoint shows them over the slide's background.
    var hideMasterShapes = false
    /// The slide's colour-map override (`p:clrMapOvr`) as read — a slide
    /// can swap the master's light and dark roles — written back as is.
    var clrMapOvrXML: String? = nil
    /// The slide's ActiveX controls (`p:controls`) as read: not drawn here,
    /// written back with their parts and VML drawing, so PowerPoint still
    /// has them (and draws each one's fallback picture).
    var controlsXML: String? = nil
    /// The layout's and master's own shapes, drawn behind this slide's
    /// (from the file it came from); never written, never editable.
    var decorations: [SlideShape] = []
    /// The layout part this slide used in the file it came from, so a save
    /// keeps it on the same layout (nil: one of ours, by `layout`).
    var layoutPart: String? = nil
    /// The slide's own background, as read (`p:bg`), written back as is.
    var backgroundXML: String? = nil
    /// The slide's own background (nil: its layout's, master's or theme's).
    var background: SlideFill? = nil
    /// What the slide's layout or master paints behind it, from the file it
    /// came from: drawn, never written (the master already says it).
    var inheritedBackground: SlideFill? = nil
    /// The part this slide was read from, where its kept background's and
    /// objects' relationship ids resolve.
    var sourcePart: String? = nil
    var transition = SlideTransition()
    /// Where the slide's layout puts its date, footer and slide number
    /// ("dt", "ftr", "sldNum"), from the file; Header & Footer places them
    /// there (PowerPoint's defaults otherwise).
    var footerFrames: [String: Rect] = [:]
    /// The slide's animations as read (`p:timing`): written back as read
    /// while `animations` is what was read from it (or, for timing this app
    /// does not model, while every shape it names is still on the slide).
    var timingXML: String? = nil
    /// Entrance animations, in order (Animation.swift).
    var animations: [ShapeAnimation] = []
    /// `animations` as read from `timingXML`; nil when the file's timing
    /// holds what this app does not model, which is then kept, not edited.
    var sourceAnimations: [ShapeAnimation]? = nil

    /// The file's animations are kept as they are and cannot be edited here.
    var animationsKept: Bool { timingXML != nil && sourceAnimations == nil }

    init(id: Int, layout: SlideLayoutKind, shapes: [SlideShape], notes: RichDocumentController) {
        self.id = id
        self.layout = layout
        self.shapes = shapes
        self.notes = notes
    }

    /// The title text, for the thumbnail pane's tooltip and the outline.
    var titleText: String {
        let title = shapes.first { $0.role == .title || $0.role == .ctrTitle }
        return title?.text?.document.plainText() ?? ""
    }
}

/// A placeholder in a layout: where it sits and how its text looks.
struct PlaceholderSpec {
    let role: PlaceholderRole
    let name: String
    let frame: Rect
    let fontSize: Double
    let heading: Bool
    let alignment: ParagraphAlignment
    let anchor: TextAnchor
    let bullets: Bool
    let bold: Bool
    let subtle: Bool
    let prompt: String
    /// How the placeholder binds to its layout in a file — PowerPoint's own
    /// default layouts use the same type/idx pairs, so a slide added to a
    /// deck read from PowerPoint lands on the right placeholders there too.
    let phType: String?
    let phIdx: String?

    init(_ role: PlaceholderRole, _ name: String, _ frame: Rect, size: Double, heading: Bool = false,
         align: ParagraphAlignment = .left, anchor: TextAnchor = .top, bullets: Bool = false,
         bold: Bool = false, subtle: Bool = false, prompt: String, type: String? = nil, idx: String? = nil) {
        self.phType = type ?? (role == .body ? nil : role.rawValue)
        self.phIdx = idx
        self.role = role
        self.name = name
        self.frame = frame
        self.fontSize = size
        self.heading = heading
        self.alignment = align
        self.anchor = anchor
        self.bullets = bullets
        self.bold = bold
        self.subtle = subtle
        self.prompt = prompt
    }
}

extension SlideLayoutKind {
    /// Placeholder geometry for a 16:9 slide of 960 x 540 pt. The positions
    /// follow PowerPoint's default master closely enough that a deck moved
    /// between the two keeps its shape; other sizes scale these.
    var placeholders: [PlaceholderSpec] {
        let title = PlaceholderSpec(.title, "Title", Rect.fromLTWH(66, 28.75, 828, 104.4), size: 44,
                                    heading: true, anchor: .middle, prompt: "Click to add title")
        let body = "Click to add text"
        switch self {
        case .titleSlide:
            return [
                PlaceholderSpec(.ctrTitle, "Title", Rect.fromLTWH(120, 88.4, 720, 188), size: 60,
                                heading: true, align: .center, anchor: .bottom, prompt: "Click to add title"),
                PlaceholderSpec(.subTitle, "Subtitle", Rect.fromLTWH(120, 283.6, 720, 130.4), size: 24,
                                align: .center, prompt: "Click to add subtitle", idx: "1"),
            ]
        case .titleAndContent:
            return [title, PlaceholderSpec(.body, "Content", Rect.fromLTWH(66, 143.75, 828, 342.6), size: 28,
                                           bullets: true, prompt: body, idx: "1")]
        case .sectionHeader:
            return [
                PlaceholderSpec(.title, "Title", Rect.fromLTWH(65.5, 134.6, 828, 224.6), size: 60,
                                heading: true, anchor: .bottom, prompt: "Click to add title"),
                PlaceholderSpec(.body, "Text", Rect.fromLTWH(65.5, 361.4, 828, 118.1), size: 24,
                                subtle: true, prompt: body, type: "body", idx: "1"),
            ]
        case .twoContent:
            return [
                title,
                PlaceholderSpec(.body, "Content Left", Rect.fromLTWH(66, 143.75, 408, 342.6), size: 28,
                                bullets: true, prompt: body, idx: "1"),
                PlaceholderSpec(.body, "Content Right", Rect.fromLTWH(486, 143.75, 408, 342.6), size: 28,
                                bullets: true, prompt: body, idx: "2"),
            ]
        case .comparison:
            return [
                PlaceholderSpec(.title, "Title", Rect.fromLTWH(66.1, 28.75, 828, 104.4), size: 44,
                                heading: true, anchor: .middle, prompt: "Click to add title"),
                PlaceholderSpec(.body, "Heading Left", Rect.fromLTWH(66.1, 132.4, 406.1, 64.9), size: 24,
                                anchor: .bottom, bold: true, prompt: body, type: "body", idx: "1"),
                PlaceholderSpec(.body, "Content Left", Rect.fromLTWH(66.1, 197.3, 406.1, 290.3), size: 24,
                                bullets: true, prompt: body, idx: "2"),
                PlaceholderSpec(.body, "Heading Right", Rect.fromLTWH(486, 132.4, 408.1, 64.9), size: 24,
                                anchor: .bottom, bold: true, prompt: body, type: "body", idx: "3"),
                PlaceholderSpec(.body, "Content Right", Rect.fromLTWH(486, 197.3, 408.1, 290.3), size: 24,
                                bullets: true, prompt: body, idx: "4"),
            ]
        case .titleOnly:
            return [title]
        case .blank:
            return []
        }
    }
}

/// A top bevel (`a:bevelT`): its width and height in points, the light
/// rig it is lit by (`a:lightRig rig`) and the surface's material
/// (`a:sp3d prstMaterial`).
struct ShapeBevel: Hashable {
    var width: Double
    var height: Double
    var rig = "threePt"
    var material = "warmMatte"
}
