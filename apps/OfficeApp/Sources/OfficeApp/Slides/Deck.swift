// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The presentation model (docs/plans/slides.md). Points are the unit
// everywhere; the file format's EMU (12700 per point) are converted at the
// edges. Shapes are classes, not values: a text shape owns the
// RichDocumentController its on-canvas editor binds to, and that identity
// has to survive every edit to the deck around it.

import Flutter
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
    /// Something read from a file that the deck does not model — a chart,
    /// SmartArt, a video, a table — kept as its XML so a save writes it
    /// back untouched, and drawn as a labelled box.
    case opaque(OpaqueObject)
}

/// An element carried through a round trip verbatim.
struct OpaqueObject: Equatable {
    /// The element as read (`p:graphicFrame`, `p:grpSp`, …).
    var xml: String
    /// What the box says ("Chart", "SmartArt", "Video").
    var label: String
    /// The slide part it came from: where its `r:id`s resolve.
    var sourcePart: String
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

/// A slide's (or a shape's) fill: a colour, a gradient, or a picture.
struct SlideFill: Equatable {
    var color: Color? = nil
    var image: ImageAttachment? = nil
    /// Gradient stops (position 0...1, colour) and the direction, degrees
    /// clockwise from left-to-right.
    var stops: [GradientStop] = []
    var angle = 0.0

    struct GradientStop: Equatable {
        var position: Double
        var color: Color
    }
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
    var outlineWidth = 0.75
    /// The text body, if the shape has one.
    let text: RichDocumentController?
    /// The look an empty body types with: the shape's own text theme.
    let textTheme: RichTextTheme?
    var anchor: TextAnchor = .top
    /// PowerPoint's default body insets: 0.1 in left and right, 0.05 in top
    /// and bottom.
    var insets = EdgeInsets(left: 7.2, top: 3.6, right: 7.2, bottom: 3.6)
    /// Shown greyed in an empty placeholder until it is typed into.
    var prompt: String?
    /// The placeholder's `type` and `idx` in the file, which bind it to its
    /// layout's placeholder; kept so a save binds it to the same one.
    var phType: String? = nil
    var phIdx: String? = nil
    /// A picture's crop: the fraction of the image cut from each edge.
    var crop: EdgeInsets? = nil

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

    var opaque: OpaqueObject? {
        if case .opaque(let o) = kind { return o }
        return nil
    }

    /// Text boxes and placeholders are clicked into; drawn shapes are
    /// selected first and edited on a second click, as PowerPoint does.
    var editsOnFirstClick: Bool { preset == nil }
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
struct DeckTheme {
    var name = "Starling"
    var headingFont = "Calibri Light"
    var bodyFont = "Calibri"
    var background = Color(0xFFFFFFFF)
    var text = Color(0xFF1B1B1B)
    var subtle = Color(0xFF595959)
    var accents: [Color] = [
        Color(0xFF2B6CB0), Color(0xFFDD6B20), Color(0xFF718096),
        Color(0xFFD69E2E), Color(0xFF319795), Color(0xFF38A169),
    ]
}

/// One slide.
final class Slide {
    let id: Int
    var layout: SlideLayoutKind
    var shapes: [SlideShape]
    let notes: RichDocumentController
    var hidden = false
    /// The layout part this slide used in the file it came from, so a save
    /// keeps it on the same layout (nil: one of ours, by `layout`).
    var layoutPart: String? = nil
    /// The slide's own background, as read (`p:bg`), written back as is.
    var backgroundXML: String? = nil
    /// The slide's background as drawn (nil: the theme's colour).
    var background: SlideFill? = nil
    /// The part this slide was read from, where its kept background's and
    /// objects' relationship ids resolve.
    var sourcePart: String? = nil

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
