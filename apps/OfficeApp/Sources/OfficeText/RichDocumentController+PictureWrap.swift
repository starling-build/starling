// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Flutter
import FlutterSwiftBridge

/// Layout Options for a floating picture: how the text wraps round it, and where it stands. Both patch the picture's
/// kept `wp:anchor` markup (the one source the layout and the writer read) and the matching `ImageFloat` flags, as one undo step.

/// Word's wrapping choices for a picture that floats (In Line with Text is a different kind of object, not a wrap).
public enum PictureWrap: String, CaseIterable, Sendable {
    case square, tight, through, topAndBottom, behindText, inFrontOfText

    public var title: String {
        switch self {
        case .square: return "Square"
        case .tight: return "Tight"
        case .through: return "Through"
        case .topAndBottom: return "Top and Bottom"
        case .behindText: return "Behind Text"
        case .inFrontOfText: return "In Front of Text"
        }
    }

    /// The `wp:wrap…` element Word writes for this choice, with a tight or through polygon that follows `points` (a closed
    /// outline in Word's 21600 space; the full rectangle by default).
    func element(points: [(Int, Int)] = PictureWrap.rectangle) -> String {
        var polygon = "<wp:wrapPolygon edited=\"0\"><wp:start x=\"\(points[0].0)\" y=\"\(points[0].1)\"/>"
        for p in points.dropFirst() { polygon += "<wp:lineTo x=\"\(p.0)\" y=\"\(p.1)\"/>" }
        polygon += "</wp:wrapPolygon>"
        switch self {
        case .square: return "<wp:wrapSquare wrapText=\"bothSides\"/>"
        case .tight: return "<wp:wrapTight wrapText=\"bothSides\">" + polygon + "</wp:wrapTight>"
        case .through: return "<wp:wrapThrough wrapText=\"bothSides\">" + polygon + "</wp:wrapThrough>"
        case .topAndBottom: return "<wp:wrapTopAndBottom/>"
        case .behindText, .inFrontOfText: return "<wp:wrapNone/>"
        }
    }

    static let rectangle: [(Int, Int)] = [(0, 0), (0, 21600), (21600, 21600), (21600, 0), (0, 0)]

    /// The outline of a preset shape of `width` x `height` (any unit) in Word's 21600 space, closed, for a tight wrap:
    /// an ellipse as 36 points, a diamond and a triangle by their corners, a rounded rectangle with its quarter arcs.
    /// Anything else is its box.
    static func outline(preset: String?, width: Double, height: Double) -> [(Int, Int)] {
        func pt(_ x: Double, _ y: Double) -> (Int, Int) { (Int((x * 21600).rounded()), Int((y * 21600).rounded())) }
        switch preset {
        case "ellipse":
            let n = 36
            var out = (0 ..< n).map { k -> (Int, Int) in
                let a = Double.pi * 2 * Double(k) / Double(n)
                return pt(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a))
            }
            out.append(out[0])
            return out
        case "diamond":
            return [pt(0.5, 0), pt(0, 0.5), pt(0.5, 1), pt(1, 0.5), pt(0.5, 0)]
        case "triangle":
            return [pt(0.5, 0), pt(0, 1), pt(1, 1), pt(0.5, 0)]
        case "roundRect" where width > 0 && height > 0:
            let r = 0.16667 * min(width, height), rx = r / width, ry = r / height
            var out: [(Int, Int)] = []
            // Corners clockwise from the top-left, each as a quarter arc in 6 steps.
            let corners: [(Double, Double, Double)] = [(rx, ry, 180), (1 - rx, ry, 270), (1 - rx, 1 - ry, 0), (rx, 1 - ry, 90)]
            for (cx, cy, from) in corners {
                for k in 0 ... 6 {
                    let a = (from + 90 * Double(k) / 6) * Double.pi / 180
                    out.append(pt(cx + rx * cos(a), cy + ry * sin(a)))
                }
            }
            out.append(out[0])
            return out
        default:
            return rectangle
        }
    }

    var behind: Bool { self == .behindText }
}

extension String {
    /// This `wp:anchor` markup with its wrapping element replaced by `wrap`'s and `behindDoc` set to match; nil when it holds no
    /// anchor or no wrapping element.
    static func _anchorWrapped(_ xml: String, _ wrap: PictureWrap, points: [(Int, Int)] = PictureWrap.rectangle) -> String? {
        guard let anchor = xml.rangeOfSubstring("<wp:anchor"),
              let tagEnd = xml.rangeOfSubstring(">", in: anchor.upperBound ..< xml.endIndex),
              let open = xml.rangeOfSubstring("<wp:wrap", in: tagEnd.upperBound ..< xml.endIndex),
              !xml[open.lowerBound...].hasPrefix("<wp:wrapPolygon") else { return nil }
        // The element's name, then its end: self-closing, or up to its closing tag.
        var nameEnd = open.upperBound
        while nameEnd < xml.endIndex, !" />".contains(xml[nameEnd]) { nameEnd = xml.index(after: nameEnd) }
        let name = "<wp:wrap" + String(xml[open.upperBound ..< nameEnd])
        guard let gt = xml.rangeOfSubstring(">", in: nameEnd ..< xml.endIndex) else { return nil }
        var end = gt.upperBound
        if xml[xml.index(before: gt.lowerBound)] != "/" {
            let close = "</" + name.dropFirst()
            guard let c = xml.rangeOfSubstring(close + ">", in: gt.upperBound ..< xml.endIndex) else { return nil }
            end = c.upperBound
        }
        var out = String(xml[xml.startIndex ..< open.lowerBound]) + wrap.element(points: points) + String(xml[end...])
        // behindDoc on the anchor's own tag.
        guard let a = out.rangeOfSubstring("<wp:anchor"), let e = out.rangeOfSubstring(">", in: a.upperBound ..< out.endIndex) else { return nil }
        var tag = String(out[a.lowerBound ..< e.lowerBound])
        if let b = tag.rangeOfSubstring(" behindDoc=\""), let q = tag.rangeOfSubstring("\"", in: b.upperBound ..< tag.endIndex) {
            tag.removeSubrange(b.lowerBound ..< q.upperBound)
        }
        tag += " behindDoc=\"\(wrap.behind ? 1 : 0)\""
        out = String(out[out.startIndex ..< a.lowerBound]) + tag + String(out[e.lowerBound...])
        return out
    }

    /// This `wp:anchor` markup with its horizontal and vertical offsets (`wp:posOffset`, EMU) set; nil when a position is held in
    /// a way this does not rewrite (a share of the page, `wp14:pctPos…`) or the markup holds no anchor.
    static func _anchorMoved(_ xml: String, x: Int, y: Int) -> String? {
        guard !xml.containsSubstring("pctPos") else { return nil }
        func set(_ xml: String, _ element: String, _ value: Int) -> String? {
            guard let open = xml.rangeOfSubstring("<wp:\(element)"),
                  let tagEnd = xml.rangeOfSubstring(">", in: open.upperBound ..< xml.endIndex),
                  let close = xml.rangeOfSubstring("</wp:\(element)>", in: tagEnd.upperBound ..< xml.endIndex),
                  xml[xml.index(before: tagEnd.lowerBound)] != "/" else { return nil }
            return String(xml[xml.startIndex ..< tagEnd.upperBound]) + "<wp:posOffset>\(value)</wp:posOffset>" + String(xml[close.lowerBound...])
        }
        guard xml.containsSubstring("<wp:anchor"), let h = set(xml, "positionH", x) else { return nil }
        return set(h, "positionV", y)
    }
}

extension RichDocumentController {
    /// The picture paragraphs picked for grouping: the selected one and every Shift-clicked one, in document order.
    public var pickedShapeIndexes: [Int] {
        guard let main = selectedImageIndex else { return [] }
        let picked = document.paragraphs.indices.filter { i in
            i == main || document.paragraphs[i].image.map { image in shapePicks.contains(image.id) } == true
        }
        return picked
    }

    /// Shift-click on the floating shape at paragraph `index`: picks it along with the selected one, or drops it again.
    public func toggleShapePick(at index: Int) {
        guard let main = selectedImageIndex, index != main, let image = _floating(index, nil) else { return }
        if let at = shapePicks.firstIndex(of: image.id) { shapePicks.remove(at: at) } else { shapePicks.append(image.id) }
        notifyListeners()
    }

    /// One undo step: the picture paragraphs `indices` give way to paragraphs holding `images` (at the first one's place), and
    /// the first of them is selected.
    @discardableResult
    public func replaceImageParagraphs(_ indices: [Int], with images: [ImageAttachment]) -> Bool {
        let sorted = Set(indices).sorted()
        guard let first = sorted.first, !images.isEmpty, sorted.allSatisfy({ $0 < document.paragraphs.count && document.paragraphs[$0].isImage }) else { return false }
        edit {
            for i in sorted.reversed() { perform(.removeParagraphs(at: i, [document.paragraphs[i]])) }
            perform(.insertParagraphs(at: first, images.map { RichParagraph(image: $0) }))
            shapePicks = []
        }
        selectImage(at: first)
        return true
    }

    /// The floating picture at paragraph `index` (its own, or inline picture `id`) with its kept anchor markup, or nil.
    private func _floating(_ index: Int, _ id: String?) -> ImageAttachment? {
        guard index < document.paragraphs.count else { return nil }
        let image = id.map { document.paragraphs[index].inlineImages[$0] } ?? document.paragraphs[index].image
        guard let image, image.float != nil, image.sourceXML?.containsSubstring("<wp:anchor") == true else { return nil }
        return image
    }

    /// The drawing at paragraph `index` (its own, or inline picture `id`) with its kept markup, floating (`wp:anchor`) or
    /// In Line with Text (`wp:inline`): what the shape and text-box tools edit, which do not care where it stands.
    private func _drawn(_ index: Int, _ id: String?) -> ImageAttachment? {
        guard index < document.paragraphs.count else { return nil }
        let image = id.map { document.paragraphs[index].inlineImages[$0] } ?? document.paragraphs[index].image
        guard let image, let xml = image.sourceXML, xml.containsSubstring("<wp:anchor") || xml.containsSubstring("<wp:inline") else { return nil }
        return image
    }

    /// Whether the drawing at `index` (or its inline picture `id`) is a shape (`wps:wsp`) In Line with Text: a click on it,
    /// selected, types into it as into a floating one.
    public func isInLineShape(at index: Int, inline id: String? = nil) -> Bool {
        guard let xml = _drawn(index, id)?.sourceXML else { return false }
        return xml.containsSubstring("<wp:inline") && xml.containsSubstring("<wps:wsp") && !xml.containsSubstring("<wpg:")
    }

    private func _store(_ index: Int, _ id: String?, old: ImageAttachment, new: ImageAttachment) {
        if let id { edit { perform(.setInlineImage(index, id: id, old: old, new: new)) } }
        else { edit { perform(.setImage(index, old: old, new: new)) } }
    }

    /// How the text wraps round the floating picture at `index` (or its inline picture `id`), if it is one that reads that way.
    public func pictureWrap(at index: Int, inline id: String? = nil) -> PictureWrap? {
        guard let image = _floating(index, id), let xml = image.sourceXML else { return nil }
        if xml.containsSubstring("<wp:wrapTopAndBottom") { return .topAndBottom }
        if xml.containsSubstring("<wp:wrapTight") { return .tight }
        if xml.containsSubstring("<wp:wrapThrough") { return .through }
        if xml.containsSubstring("<wp:wrapSquare") { return .square }
        if xml.containsSubstring("<wp:wrapNone") { return xml.containsSubstring("behindDoc=\"1\"") ? .behindText : .inFrontOfText }
        return nil
    }

    /// Set the wrapping of the floating picture at `index` (or its inline picture `id`), one undo step. False when the picture
    /// does not float, its markup has no wrapping element, or it already wraps so.
    @discardableResult
    public func setPictureWrap(at index: Int, inline id: String? = nil, _ wrap: PictureWrap) -> Bool {
        guard let old = _floating(index, id), let xml = old.sourceXML, pictureWrap(at: index, inline: id) != wrap,
              var f = old.float else { return false }
        // A shape wraps round its own outline, not its box.
        var preset: String?
        if xml.containsSubstring("<wps:wsp"), let g = xml.rangeOfSubstring("prstGeom prst=\""),
           let q = xml.rangeOfSubstring("\"", in: g.upperBound ..< xml.endIndex) { preset = String(xml[g.upperBound ..< q.lowerBound]) }
        let points = PictureWrap.outline(preset: preset, width: old.width, height: old.height)
        guard let patched = String._anchorWrapped(xml, wrap, points: points) else { return false }
        var new = old
        new.sourceXML = patched
        f.wraps = wrap == .square || wrap == .tight || wrap == .through
        f.wrapsTight = wrap == .tight || wrap == .through
        f.wrapSide = nil
        f.wrapReach = 1
        f.wrapBottomShare = 1
        f.wrapTopSkip = 0
        f.wrapPolygon = f.wrapsTight && points.count > 5 ? points.map { WrapPoint(x: Double($0.0) / 21600, y: Double($0.1) / 21600) } : []
        // (As the reader does: a top-and-bottom picture placed against the page or its paragraph bands its page.)
        f.takesRoom = wrap == .topAndBottom
        f.bandsPage = false
        if f.takesRoom, f.verticalAlign == nil, ["page", "margin", "paragraph"].contains(f.verticalFrom) {
            f.takesRoom = false
            f.bandsPage = true
        }
        new.float = f
        _store(index, id, old: old, new: new)
        return true
    }

    /// Move the floating picture at `index` (or its inline picture `id`) by `dx`, `dy` points from where it stands, one undo
    /// step. False when it does not float, is placed by alignment (left, centre, top…) or its position
    /// is held in a form this does not rewrite.
    @discardableResult
    public func movePicture(at index: Int, inline id: String? = nil, dx: Double, dy: Double) -> Bool {
        guard let old = _floating(index, id), let xml = old.sourceXML, var f = old.float, dx != 0 || dy != 0,
              f.horizontalAlign == nil, f.verticalAlign == nil else { return false }
        let x = f.x + dx, y = f.y + dy
        guard let patched = String._anchorMoved(xml, x: Int((x * 12700).rounded()), y: Int((y * 12700).rounded())) else { return false }
        var new = old
        new.sourceXML = patched
        f.x = x
        f.y = y
        new.float = f
        _store(index, id, old: old, new: new)
        return true
    }

    /// Make the shape at `index` (a `wps:wsp` with no text part, as a new shape is) ready to type in: add an empty centred
    /// paragraph as its text part, one undo step, so it enters in place like a text box. False for anything that is not such a
    /// shape, or already has text.
    @discardableResult
    public func giveShapeText(at index: Int, inline id: String? = nil) -> Bool {
        guard let old = _drawn(index, id), old.textBox == nil, let xml = old.sourceXML,
              xml.containsSubstring("<wps:wsp"), !xml.containsSubstring("<wps:txbx"), !xml.containsSubstring("<mc:"),
              let end = xml.rangeOfSubstring("</wps:spPr>") else { return false }
        let part = "<wps:txbx><w:txbxContent><w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr></w:p></w:txbxContent></wps:txbx>"
        var patched = xml
        patched.insert(contentsOf: part, at: end.upperBound)
        // (Word centres a shape's text in it.)
        if let body = patched.rangeOfSubstring("<wps:bodyPr "), let close = patched.rangeOfSubstring(">", in: body.upperBound ..< patched.endIndex),
           let a = patched.rangeOfSubstring("anchor=\"t\"", in: body.upperBound ..< close.lowerBound) {
            patched.replaceSubrange(a, with: "anchor=\"ctr\"")
        }
        var new = old
        new.sourceXML = patched
        var para = RichParagraph(text: "")
        para.style.alignment = .center
        new.textBox = RichTextBox(paragraphs: [para])
        _store(index, id, old: old, new: new)
        return true
    }

    /// The fill of the shape at `index` (nil: none), one undo step. False when it is not a shape drawn by a `wps:wsp`
    /// whose fill is a plain colour or none (a gradient or picture fill is left as it is).
    @discardableResult
    public func setShapeFill(at index: Int, inline id: String? = nil, _ color: Color?, theme: (slot: Int, lumMod: Int, lumOff: Int)? = nil) -> Bool {
        _setShapePaint(index, id, line: false, color, theme)
    }

    /// The outline colour of the shape at `index` (nil: no line), one undo step; false as `setShapeFill`.
    @discardableResult
    public func setShapeOutline(at index: Int, inline id: String? = nil, _ color: Color?, theme: (slot: Int, lumMod: Int, lumOff: Int)? = nil) -> Bool {
        _setShapePaint(index, id, line: true, color, theme)
    }

    private func _setShapePaint(_ index: Int, _ id: String?, line: Bool, _ color: Color?, _ theme: (slot: Int, lumMod: Int, lumOff: Int)? = nil) -> Bool {
        guard let old = _drawn(index, id), let xml = old.sourceXML, xml.containsSubstring("<wps:wsp") else { return false }
        var hex = ""
        if let color { let v = String(color.value & 0xFFFFFF, radix: 16, uppercase: true); hex = String(repeating: "0", count: 6 - v.count) + v }
        // A theme pick stays linked to its slot (`a:schemeClr` with lumMod / lumOff), so a theme change recolours it.
        let names = ["bg1", "tx1", "bg2", "tx2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6"]
        var paint = color == nil ? "<a:noFill/>" : "<a:solidFill><a:srgbClr val=\"\(hex)\"/></a:solidFill>"
        if color != nil, let t = theme, t.slot >= 0, t.slot < names.count {
            var mods = ""
            if t.lumMod < 100 { mods += "<a:lumMod val=\"\(t.lumMod * 1000)\"/>" }
            if t.lumOff > 0 { mods += "<a:lumOff val=\"\(t.lumOff * 1000)\"/>" }
            paint = "<a:solidFill><a:schemeClr val=\"\(names[t.slot])\"" + (mods.isEmpty ? "/>" : ">\(mods)</a:schemeClr>") + "</a:solidFill>"
        }
        // The shape's `wps:spPr` blocks (a group has one per child): the picked child's, else every one (a plain shape has one).
        var spans: [Range<String.Index>] = []
        var from = xml.startIndex
        while let open = xml.rangeOfSubstring("<wps:spPr>", in: from ..< xml.endIndex),
              let close = xml.rangeOfSubstring("</wps:spPr>", in: open.upperBound ..< xml.endIndex) {
            spans.append(open.upperBound ..< close.lowerBound)
            from = close.upperBound
        }
        if let child = groupChild, xml.containsSubstring("<wpg:wgp"), selectedImageIndex == index { spans = spans.indices.contains(child) ? [spans[child]] : [] }
        guard !spans.isEmpty else { return false }
        var out = xml
        for span in spans.reversed() {
            var body = String(out[span])
            // Where the paint stands: after the geometry for the fill, inside the line's element for the outline.
            var at: String.Index
            if line {
                guard let l = body.rangeOfSubstring("<a:ln"), let gt = body.rangeOfSubstring(">", in: l.upperBound ..< body.endIndex),
                      !body[l.upperBound ..< gt.lowerBound].hasSuffix("/") else { continue }
                at = gt.upperBound
            } else {
                guard let g = body.rangeOfSubstring("</a:prstGeom>") ?? body.rangeOfSubstring("</a:custGeom>") else { continue }
                at = g.upperBound
            }
            let rest = body[at...]
            if rest.hasPrefix("<a:solidFill>"), let e = body.rangeOfSubstring("</a:solidFill>", in: at ..< body.endIndex) {
                body.replaceSubrange(at ..< e.upperBound, with: paint)
            } else if rest.hasPrefix("<a:noFill/>") {
                body.replaceSubrange(at ..< body.index(at, offsetBy: "<a:noFill/>".count), with: paint)
            } else if rest.hasPrefix("<a:gradFill") || rest.hasPrefix("<a:blipFill") || rest.hasPrefix("<a:pattFill") {
                continue
            } else {
                body.insert(contentsOf: paint, at: at)
            }
            out.replaceSubrange(span, with: body)
        }
        var new = old
        new.sourceXML = out
        if var outline = old.outline, !xml.containsSubstring("<wpg:wgp") {
            if line { outline.color = color.map { Color(0xFF00_0000 | Int64($0.value & 0xFFFFFF)) } } else { outline.fill = color.map { Color(0xFF00_0000 | Int64($0.value & 0xFFFFFF)) } }
            new.outline = outline
        }
        guard new.sourceXML != xml else { return false }
        _store(index, id, old: old, new: new)
        return true
    }

    /// The words in the text box at `index` (its paragraphs, one per line) when they are plain enough to edit as words
    /// (no character or paragraph formatting, no table); nil for anything else.
    public func textBoxText(at index: Int, inline id: String? = nil) -> String? {
        guard let image = _drawn(index, id), let box = image.textBox, let xml = image.sourceXML,
              let open = xml.rangeOfSubstring("<w:txbxContent>"),
              let close = xml.rangeOfSubstring("</w:txbxContent>", in: open.upperBound ..< xml.endIndex) else { return nil }
        let inner = xml[open.upperBound ..< close.lowerBound]
        for marker in ["<w:rPr", "<w:pPr", "<w:tbl", "<w:br", "<w:tab", "<w:fld", "<w:hyperlink", "<w:drawing", "<mc:"]
        where String(inner).containsSubstring(marker) { return nil }
        return box.paragraphs.map(\.text).joined(separator: "\n")
    }

    /// Replace the words in the text box at `index` (one paragraph per line), one undo step. False when the box is not a
    /// plain one (`textBoxText` is nil) or the words are the same.
    @discardableResult
    public func setTextBoxText(at index: Int, inline id: String? = nil, _ text: String) -> Bool {
        guard let current = textBoxText(at: index, inline: id), current != text,
              let old = _drawn(index, id), var box = old.textBox, let xml = old.sourceXML,
              let open = xml.rangeOfSubstring("<w:txbxContent>"),
              let close = xml.rangeOfSubstring("</w:txbxContent>", in: open.upperBound ..< xml.endIndex) else { return false }
        func esc(_ line: Substring) -> String {
            var out = ""
            for ch in line { out += ch == "&" ? "&amp;" : ch == "<" ? "&lt;" : ch == ">" ? "&gt;" : String(ch) }
            return out
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let body = lines.map { "<w:p><w:r><w:t xml:space=\"preserve\">\(esc($0))</w:t></w:r></w:p>" }.joined()
        var new = old
        new.sourceXML = String(xml[xml.startIndex ..< open.upperBound]) + body + String(xml[close.lowerBound...])
        box.paragraphs = lines.map { RichParagraph(text: String($0)) }
        new.textBox = box
        _store(index, id, old: old, new: new)
        return true
    }

    /// Whether the text box at `index` resizes to fit its text (`spAutoFit`).
    public func textBoxAutoHeight(at index: Int, inline id: String? = nil) -> Bool {
        _drawn(index, id)?.textBox?.autoHeight == true
    }

    /// The text box at `index` as paragraphs to edit in place, when it holds nothing the in-place editor would lose
    /// (no table, picture, field or markup it cannot write back); nil for anything else.
    public func textBoxParagraphs(at index: Int, inline id: String? = nil) -> [RichParagraph]? {
        guard let image = _drawn(index, id), let box = image.textBox, let xml = image.sourceXML,
              let open = xml.rangeOfSubstring("<w:txbxContent>"),
              let close = xml.rangeOfSubstring("</w:txbxContent>", in: open.upperBound ..< xml.endIndex) else { return nil }
        let inner = String(xml[open.upperBound ..< close.lowerBound])
        // (Fields, tracked changes and bookmarks are written back by the document writer as they were read. A link to a
        // page outside the file needs a relationship in the file's own list, which the box's text cannot make: not editable yet.)
        for marker in ["<w:tbl", "<w:drawing", "<mc:", "<w:sdt", "<w:object", "<w:pict"]
        where inner.containsSubstring(marker) { return nil }
        guard box.paragraphs.allSatisfy({ $0.image == nil && $0.inlineImages.isEmpty && $0.keptTable == nil }) else { return nil }
        return box.paragraphs
    }

    /// The text box at `index` as a small document to edit in place, tables included: the paragraphs with the
    /// box's table looks and grids. nil when the box holds what the editor would lose (the same list as
    /// `textBoxParagraphs`) or a table inside a table's cell.
    public func textBoxDocument(at index: Int, inline id: String? = nil) -> RichDocument? {
        guard let image = _drawn(index, id) else { return nil }
        return Self._textBoxDocument(of: image)
    }

    /// `textBoxDocument` for an attachment in hand (a floating text box or a group child lifted out as one).
    static func _textBoxDocument(of image: ImageAttachment) -> RichDocument? {
        guard let box = image.textBox, let xml = image.sourceXML,
              let open = xml.rangeOfSubstring("<w:txbxContent>"),
              let close = xml.rangeOfSubstring("</w:txbxContent>", in: open.upperBound ..< xml.endIndex) else { return nil }
        let inner = String(xml[open.upperBound ..< close.lowerBound])
        for marker in ["<mc:", "<w:sdt", "<w:object", "<w:pict"]
        where inner.containsSubstring(marker) { return nil }
        guard _picturesAreKept(inner, box.paragraphs) else { return nil }
        // A table inside a cell is not rewritten.
        var from = inner.startIndex
        while let o = inner.rangeOfSubstring("<w:tc>", in: from ..< inner.endIndex) ?? inner.rangeOfSubstring("<w:tc ", in: from ..< inner.endIndex) {
            guard let c = inner.rangeOfSubstring("</w:tc>", in: o.upperBound ..< inner.endIndex) else { return nil }
            if String(inner[o.upperBound ..< c.lowerBound]).containsSubstring("<w:tbl") { return nil }
            from = c.upperBound
        }
        guard box.paragraphs.allSatisfy({ $0.keptTable == nil }) else { return nil }
        // Every table the text holds must be one the box knows the look of.
        let ids = Set(box.paragraphs.compactMap { $0.cell?.table })
        if inner.containsSubstring("<w:tbl"), ids.isEmpty { return nil }
        var doc = RichDocument(paragraphs: box.paragraphs)
        doc.tableStyles = box.tableStyles
        doc.tableColumns = box.tableColumns
        return doc
    }

    /// Put an edited box back (`textBoxDocument`'s counterpart): its paragraphs and table looks and grids, written as
    /// `contentXML`, one undo step. False when the box is not editable in place or nothing changed.
    @discardableResult
    public func setTextBoxContent(at index: Int, inline id: String? = nil, document: RichDocument, contentXML: String, rels: [KeptRel] = [], height: Double? = nil) -> Bool {
        guard textBoxDocument(at: index, inline: id) != nil,
              let old = _drawn(index, id), var box = old.textBox, let xml = old.sourceXML,
              let open = xml.rangeOfSubstring("<w:txbxContent>"),
              let close = xml.rangeOfSubstring("</w:txbxContent>", in: open.upperBound ..< xml.endIndex) else { return false }
        // Revision and bookmark ids are one space for the whole file. The writer numbers a box's from 1 like the body's, so move
        // them above every id the other boxes already hold (the body's revisions are renumbered from 1 on save).
        var highest = 99_999
        for (i, p) in self.document.paragraphs.enumerated() {
            // (The body: the ids its bookmarks keep from the file, and as many revision ids as it has revision runs.)
            highest = max(highest, p.bookmarkMarkers.compactMap { Int($0.id) }.max() ?? 0)
            highest = max(highest, p.runs.filter { $0.style.revision != nil }.count + p.bookmarks.count)
            for other in [p.image].compactMap({ $0 }) + Array(p.inlineImages.values) {
                if i == index, other.id == old.id { continue }
                if let x = other.sourceXML { highest = max(highest, Self._highestRevisionId(in: x)) }
            }
        }
        let patched = String(xml[xml.startIndex ..< open.upperBound]) + Self._shiftRevisionIds(contentXML, by: highest) + String(xml[close.lowerBound...])
        let ids = Set(document.paragraphs.compactMap { $0.cell?.table })
        var new = old
        // (A box that resizes to fit its text keeps the height its text now needs, as Word's does.)
        if let height, box.autoHeight, abs(height - old.height) > 0.5 { new.height = height }
        guard patched != xml || new.height != old.height else { return false }
        new.sourceXML = patched
        // (The links the new words name replace the ones the writer made last time; the file's own relationships stay.)
        new.sourceRels = old.sourceRels.filter { !$0.id.hasPrefix("rIdLink") && !$0.id.hasPrefix("rIdBoxKept") } + rels
        box.paragraphs = document.paragraphs
        box.tableStyles = document.tableStyles.filter { ids.contains($0.key) }
        box.tableColumns = document.tableColumns.filter { ids.contains($0.key) }
        new.textBox = box
        _store(index, id, old: old, new: new)
        return true
    }

    /// The same for a box of plain paragraphs (no table looks).
    @discardableResult
    public func setTextBoxContent(at index: Int, inline id: String? = nil, paragraphs: [RichParagraph], contentXML: String, rels: [KeptRel] = [], height: Double? = nil) -> Bool {
        setTextBoxContent(at: index, inline: id, document: RichDocument(paragraphs: paragraphs), contentXML: contentXML, rels: rels, height: height)
    }

    /// Pictures inside a box are edited in place only when each one is a plain inline picture the file carried (its own XML and
    /// relationships ride with it), and the text holds no drawing the reader did not turn into one.
    static func _picturesAreKept(_ inner: String, _ paragraphs: [RichParagraph]) -> Bool {
        var drawings = 0, from = inner.startIndex
        while let r = inner.rangeOfSubstring("<w:drawing", in: from ..< inner.endIndex) { drawings += 1; from = r.upperBound }
        var images: [ImageAttachment] = []
        for p in paragraphs { images += [p.image].compactMap { $0 } + Array(p.inlineImages.values) }
        return images.count == drawings && images.allSatisfy { $0.sourceXML != nil && $0.float == nil && $0.textBox == nil }
    }

    private static let _idTags = ["<w:ins ", "<w:del ", "<w:bookmarkStart ", "<w:bookmarkEnd ", "<w:rPrChange ", "<w:pPrChange ", "<w:moveFrom ", "<w:moveTo "]

    /// Visit each revision or bookmark `w:id="N"` of `xml`: (range of the digits, value).
    private static func _revisionIds(in xml: String) -> [(Range<String.Index>, Int)] {
        var out: [(Range<String.Index>, Int)] = []
        for tag in _idTags {
            var from = xml.startIndex
            while let t = xml.rangeOfSubstring(tag, in: from ..< xml.endIndex) {
                from = t.upperBound
                guard let end = xml.rangeOfSubstring(">", in: from ..< xml.endIndex),
                      let a = xml.rangeOfSubstring("w:id=\"", in: from ..< end.lowerBound),
                      let q = xml.rangeOfSubstring("\"", in: a.upperBound ..< end.lowerBound),
                      let n = Int(xml[a.upperBound ..< q.lowerBound]) else { continue }
                out.append((a.upperBound ..< q.lowerBound, n))
            }
        }
        return out
    }

    public static func _annotationIds(in xml: String) -> [Int] { _revisionIds(in: xml).map(\.1) }

    public static func _highestRevisionId(in xml: String) -> Int { _revisionIds(in: xml).map(\.1).max() ?? 0 }

    /// `xml` with every revision and bookmark id raised by `offset` (start and end of a bookmark move together).
    static func _shiftRevisionIds(_ xml: String, by offset: Int) -> String {
        var out = xml
        for (range, n) in _revisionIds(in: xml).sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            out.replaceSubrange(range, with: String(n + offset))
        }
        return out
    }
}

extension RichDocumentController {
    /// The boxes of a group's children, in points from the group's top left, in drawing order; nil when the picture is not a group.
    public func groupChildBoxes(at index: Int) -> [Rect]? {
        guard index < document.paragraphs.count, let xml = document.paragraphs[index].image?.sourceXML, xml.containsSubstring("<wpg:wgp"),
              let grp = xml.rangeOfSubstring("<wpg:grpSpPr>"), let grpEnd = xml.rangeOfSubstring("</wpg:grpSpPr>", in: grp.upperBound ..< xml.endIndex) else { return nil }
        func ints(_ s: String, _ tag: String, _ a: String, _ b: String) -> (Int, Int)? {
            guard let t = s.rangeOfSubstring("<\(tag) "), let e = s.rangeOfSubstring(">", in: t.upperBound ..< s.endIndex) else { return nil }
            let attrs = String(s[t.upperBound ..< e.lowerBound])
            func v(_ n: String) -> Int? {
                guard let r = attrs.rangeOfSubstring(n + "=\""), let q = attrs.rangeOfSubstring("\"", in: r.upperBound ..< attrs.endIndex) else { return nil }
                return Int(attrs[r.upperBound ..< q.lowerBound])
            }
            guard let x = v(a), let y = v(b) else { return nil }
            return (x, y)
        }
        let head = String(xml[grp.upperBound ..< grpEnd.lowerBound])
        guard let off = ints(head, "a:chOff", "x", "y") else { return nil }
        var boxes: [Rect] = []
        var from = grpEnd.upperBound
        while let open = xml.rangeOfSubstring("<wps:wsp>", in: from ..< xml.endIndex) ?? xml.rangeOfSubstring("<wps:wsp ", in: from ..< xml.endIndex),
              let close = xml.rangeOfSubstring("</wps:wsp>", in: open.upperBound ..< xml.endIndex) {
            let w = String(xml[open.upperBound ..< close.lowerBound])
            if let o = ints(w, "a:off", "x", "y"), let e = ints(w, "a:ext", "cx", "cy") {
                boxes.append(Rect.fromLTWH(Double(o.0 - off.0) / 12700, Double(o.1 - off.1) / 12700, Double(e.0) / 12700, Double(e.1) / 12700))
            }
            from = close.upperBound
        }
        return boxes.isEmpty ? nil : boxes
    }

    /// A click at `point` (points from the selected group's top left): picks the topmost child there; false when none is hit.
    @discardableResult
    public func pickGroupChild(at index: Int, point: Offset) -> Bool {
        guard selectedImageIndex == index, let boxes = groupChildBoxes(at: index),
              let hit = boxes.lastIndex(where: { $0.contains(point) }) else { return false }
        groupChild = hit
        notifyListeners()
        return true
    }

    /// What the app does to one child of a group (EMU, page coordinates).
    /// Set by the app, which knows the markup: (group, child, change, the document's parts for its pictures' files) gives
    /// the changed group, or nil.
    public nonisolated(unsafe) static var groupChildEditor: ((ImageAttachment, Int, GroupChildChange, [String: Data]) -> ImageAttachment?)? = nil

    /// The picked child lifted out of its group as a text box of its own (a plain shape gets an empty text), or nil.
    public nonisolated(unsafe) static var groupChildProxy: ((ImageAttachment, Int) -> ImageAttachment?)? = nil

    /// The words of the picked child of the selected group, to edit (`nil` when it cannot be edited in place).
    public func groupChildTextDocument() -> RichDocument? {
        guard let index = selectedImageIndex, let child = groupChild, index < document.paragraphs.count,
              let image = document.paragraphs[index].image, let proxy = Self.groupChildProxy?(image, child) else { return nil }
        return Self._textBoxDocument(of: proxy)
    }

    /// The edited words go back into the picked child of the selected group (one undo step); the group stays whole.
    @discardableResult
    public func setGroupChildText(document: RichDocument, contentXML: String, rels: [KeptRel] = []) -> Bool {
        guard groupChildTextDocument().map({ $0.paragraphs.count != document.paragraphs.count || $0 != document }) ?? true else { return false }
        return editGroupChild(.text(contentXML), rels: rels)
    }

    /// One undo step: the picked child of the selected group moves, resizes (points) or goes. The pick stays after a move or
    /// a resize.
    @discardableResult
    public func editGroupChild(_ change: GroupChildChange, rels: [KeptRel] = []) -> Bool {
        guard let index = selectedImageIndex, let child = groupChild, index < document.paragraphs.count,
              let image = document.paragraphs[index].image, let edit = Self.groupChildEditor,
              let changed = edit(image, child, change, document.keptParts) else { return false }
        var next = changed
        if !rels.isEmpty { next.sourceRels = image.sourceRels.filter { !$0.id.hasPrefix("rIdLink") && !$0.id.hasPrefix("rIdBoxKept") } + rels }
        guard replaceImageParagraphs([index], with: [next]) else { return false }
        if case .delete = change {} else { groupChild = child; notifyListeners() }
        return true
    }
}

/// A change to one child of a group, in EMU.
public enum GroupChildChange {
    case move(dx: Int, dy: Int), resize(cx: Int, cy: Int), delete
    /// The child's text becomes this `w:txbxContent` body.
    case text(String)
}
