// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation
import OfficeText

/// S-SH-4: Shape Format > Shape Styles, PowerPoint's Theme Styles gallery. Seven colour columns (Dark 1, Accent 1-6)
/// by six rows, each a shape style: which of the theme's fill, line and effect styles the shape takes, in which colour,
/// and the colour of its text. Applied, the shape draws the look and saves the refs (`p:style`); its own fill and line
/// are written too, because our saved theme's format scheme is plain where Office's has gradients and a shadow.
/// The look is worked out from Office's own format scheme (2013 and later), through the reader's colour maths.
struct ShapeQuickStyle: Equatable {
    /// The theme colour of each column.
    static let columns = ["dk1", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6"]
    static let rows = ["Colored Outline", "Colored Fill", "Light 1 Outline, Colored Fill",
                       "Subtle Effect", "Moderate Effect", "Intense Effect"]

    let row: Int
    let column: Int

    static let all: [ShapeQuickStyle] = rows.indices.flatMap { r in columns.indices.map { ShapeQuickStyle(row: r, column: $0) } }

    var name: String { "\(Self.rows[row]) - \(column == 0 ? "Black, Dark 1" : "Accent \(column)")" }
    var colorName: String { Self.columns[column] }

    /// The style's refs: (index into the theme's list, colour, its modifiers as XML). Index 0 is none.
    var lineRef: (idx: Int, color: String, mods: String) {
        switch row {
        case 0: return (2, colorName, "")
        case 1: return (2, colorName, "<a:shade val=\"50000\"/>")
        case 2: return (3, "lt1", "")
        case 3: return (1, colorName, "")
        default: return (0, colorName, "")
        }
    }
    var fillRef: (idx: Int, color: String) {
        switch row {
        case 0: return (1, "lt1")
        case 1, 2: return (1, colorName)
        case 3: return (2, colorName)
        default: return (3, colorName)
        }
    }
    var effectIdx: Int { [0, 0, 1, 1, 2, 3][row] }
    var fontColor: String { row == 0 || row == 3 ? "dk1" : "lt1" }

    /// `p:style` as PowerPoint writes it for this gallery entry.
    var xml: String {
        func clr(_ name: String, _ mods: String = "") -> String {
            mods.isEmpty ? "<a:schemeClr val=\"\(name)\"/>" : "<a:schemeClr val=\"\(name)\">\(mods)</a:schemeClr>"
        }
        let ln = lineRef, fl = fillRef
        return "<p:style><a:lnRef idx=\"\(ln.idx)\">\(clr(ln.color, ln.mods))</a:lnRef><a:fillRef idx=\"\(fl.idx)\">\(clr(fl.color))</a:fillRef>"
            + "<a:effectRef idx=\"\(effectIdx)\">\(clr(colorName))</a:effectRef><a:fontRef idx=\"minor\">\(clr(fontColor))</a:fontRef></p:style>"
    }

    /// What a shape in this style draws.
    struct Look: Equatable {
        var fill: Color
        /// The fill's theme slot when it is one plain theme colour ("accent1", "bg1").
        var fillScheme: String?
        /// A gradient fill (rows 4-6), nil for a solid one.
        var gradient: SlideFill?
        var outline: Color?
        var outlineScheme: String?
        var outlineWidth: Double
        var shadow: CharShadow?
        var text: Color
    }

    /// The scheme spec ("tx1", "accent2") the colour pickers use for a theme colour.
    private static func spec(_ name: String) -> String { ["dk1": "tx1", "lt1": "bg1"][name] ?? name }

    func look(_ colors: ColorContext) -> Look {
        let base = colors.scheme(colorName) ?? Color(0xFF808080)
        let lt1 = colors.scheme("lt1") ?? Color(0xFFFFFFFF), dk1 = colors.scheme("dk1") ?? Color(0xFF000000)
        // Fill.
        var fill = base, fillScheme: String? = Self.spec(colorName), gradient: SlideFill? = nil
        let fl = fillRef
        if fl.color == "lt1" { fill = lt1; fillScheme = "bg1" }
        if fl.idx >= 2, let node = Self.office.fills[fl.idx - 1] {
            var c = colors
            c.placeholder = base
            if let g = PptxReader.gradient(node, colors: c), g.stops.count >= 2 {
                gradient = g
                fill = g.stops[0].color
                fillScheme = nil
            }
        }
        // Line.
        let ln = lineRef
        var outline: Color? = nil, outlineScheme: String? = nil
        if ln.idx > 0 {
            if ln.color == "lt1" { outline = lt1; outlineScheme = "bg1" }
            else if ln.mods.isEmpty { outline = base; outlineScheme = Self.spec(colorName) }
            else { outline = DeckController.shadeLinear(base, 0.5) }
        }
        let width = ln.idx > 0 ? Self.office.lineWidths[ln.idx - 1] : 0.75
        // Effect.
        var shadow: CharShadow? = nil
        if effectIdx > 0, let node = Self.office.effects[effectIdx - 1] {
            shadow = LevelStyle.outerShadow(node, colors)
        }
        return Look(fill: fill, fillScheme: fillScheme, gradient: gradient, outline: outline, outlineScheme: outlineScheme,
                    outlineWidth: width, shadow: shadow, text: fontColor == "dk1" ? dk1 : lt1)
    }

    /// Office's format scheme (theme1.xml of PowerPoint 2013 and later): its three fill styles (solid; a light
    /// gradient; a deeper one), line widths ½, 1 and 1½ pt, and effects (none, none, a soft shadow below).
    static let office: (fills: [XNode?], lineWidths: [Double], effects: [XNode?]) = {
        let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        func node(_ xml: String) -> XNode? { XNode.parse(Data(xml.utf8)) }
        func gs(_ pos: Int, _ mods: String) -> String { "<a:gs pos=\"\(pos)\"><a:schemeClr val=\"phClr\">\(mods)</a:schemeClr></a:gs>" }
        let subtle = "<a:gradFill \(ns) rotWithShape=\"1\"><a:gsLst>"
            + gs(0, "<a:lumMod val=\"110000\"/><a:satMod val=\"105000\"/><a:tint val=\"67000\"/>")
            + gs(50000, "<a:lumMod val=\"105000\"/><a:satMod val=\"103000\"/><a:tint val=\"73000\"/>")
            + gs(100000, "<a:lumMod val=\"105000\"/><a:satMod val=\"109000\"/><a:tint val=\"81000\"/>")
            + "</a:gsLst><a:lin ang=\"5400000\" scaled=\"0\"/></a:gradFill>"
        let intense = "<a:gradFill \(ns) rotWithShape=\"1\"><a:gsLst>"
            + gs(0, "<a:satMod val=\"103000\"/><a:lumMod val=\"102000\"/><a:tint val=\"94000\"/>")
            + gs(50000, "<a:satMod val=\"110000\"/><a:lumMod val=\"100000\"/><a:shade val=\"100000\"/>")
            + gs(100000, "<a:lumMod val=\"99000\"/><a:satMod val=\"120000\"/><a:shade val=\"78000\"/>")
            + "</a:gsLst><a:lin ang=\"5400000\" scaled=\"0\"/></a:gradFill>"
        let shadow = "<a:effectLst \(ns)><a:outerShdw blurRad=\"57150\" dist=\"19050\" dir=\"5400000\" algn=\"ctr\" rotWithShape=\"0\">"
            + "<a:srgbClr val=\"000000\"><a:alpha val=\"63000\"/></a:srgbClr></a:outerShdw></a:effectLst>"
        return ([nil, node(subtle), node(intense)], [0.5, 1, 1.5], [nil, nil, node(shadow)])
    }()
}

extension DeckController {
    /// The selected shapes a shape style applies to: drawn shapes, text boxes and placeholders, not lines.
    var quickStyleTargets: [SlideShape] {
        selection.filter { s in
            switch s.kind {
            case .geometry(let p): return !p.isLine && !p.isOpenPath
            case .textBox, .placeholder: return true
            default: return false
            }
        }
    }

    /// The gallery entry the first target was given here, for the gallery's highlight.
    var currentQuickStyle: ShapeQuickStyle? { quickStyleTargets.first?.quickStyle }

    /// Gives the selected shapes `style`: one undo step.
    func applyQuickStyle(_ style: ShapeQuickStyle) {
        endQuickStylePreview()
        let targets = quickStyleTargets
        guard !targets.isEmpty else { return }
        _checkpoint()
        for s in targets { _giveQuickStyle(style, to: s) }
        _changed()
    }

    /// Shows `style` on the selected shapes while the pointer rests on its gallery entry; nothing is recorded.
    /// `endQuickStylePreview` puts them back.
    func previewQuickStyle(_ style: ShapeQuickStyle) {
        let targets = quickStyleTargets
        guard !targets.isEmpty else { return }
        if _quickStylePreview == nil { _quickStylePreview = targets.map { ($0, _state($0)) } }
        for s in targets { _giveQuickStyle(style, to: s) }
        _redrawOnly()
    }

    func endQuickStylePreview() {
        guard let saved = _quickStylePreview else { return }
        _quickStylePreview = nil
        for (shape, st) in saved { _restoreLook(st, to: shape) }
        _redrawOnly()
    }

    /// Whether `s` still draws `look`: its fill, gradient and line as the style gave them.
    static func _showsLook(_ s: SlideShape, _ look: ShapeQuickStyle.Look) -> Bool {
        s.fill == look.fill && s.fillStyle == look.gradient && s.outline == look.outline && s.outlineWidth == look.outlineWidth
    }

    /// Draws `style` on `s` in the deck's colours (`theme` may just have changed).
    func _giveQuickStyle(_ style: ShapeQuickStyle, to s: SlideShape) {
        let look = style.look(tableStyleColors())
        s.fill = look.fill
        s.fillScheme = look.fillScheme
        s.fillStyle = look.gradient
        s.outline = look.outline
        s.outlineScheme = look.outlineScheme
        s.outlineFill = nil
        s.outlineWidth = look.outlineWidth
        s.shadow = look.shadow
        s.quickStyle = style
        s.themeStyle = false
        if var k = s.keptLook {
            k.fillReplaced = true
            k.lineReplaced = true
            k.effectsEdited = true
            s.keptLook = k
        }
        if let tt = s.textTheme, tt.textColor != look.text {
            let fresh = _textTheme(font: tt.fontFamily ?? theme.bodyFont, size: tt.fontSize, color: look.text)
            fresh.listIndent = tt.listIndent
            fresh.faceResolver = tt.faceResolver
            fresh.omitsLeadingSpace = tt.omitsLeadingSpace
            fresh.singleLineHeight = tt.singleLineHeight
            fresh.headingColor = tt.headingColor
            s.textTheme = fresh
        }
    }
}
