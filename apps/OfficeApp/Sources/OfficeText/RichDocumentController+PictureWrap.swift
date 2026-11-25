// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter

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

    /// The `wp:wrap…` element Word writes for this choice.
    var element: String {
        let polygon = "<wp:wrapPolygon edited=\"0\"><wp:start x=\"0\" y=\"0\"/><wp:lineTo x=\"0\" y=\"21600\"/>"
            + "<wp:lineTo x=\"21600\" y=\"21600\"/><wp:lineTo x=\"21600\" y=\"0\"/><wp:lineTo x=\"0\" y=\"0\"/></wp:wrapPolygon>"
        switch self {
        case .square: return "<wp:wrapSquare wrapText=\"bothSides\"/>"
        case .tight: return "<wp:wrapTight wrapText=\"bothSides\">" + polygon + "</wp:wrapTight>"
        case .through: return "<wp:wrapThrough wrapText=\"bothSides\">" + polygon + "</wp:wrapThrough>"
        case .topAndBottom: return "<wp:wrapTopAndBottom/>"
        case .behindText, .inFrontOfText: return "<wp:wrapNone/>"
        }
    }

    var behind: Bool { self == .behindText }
}

extension String {
    /// This `wp:anchor` markup with its wrapping element replaced by `wrap`'s and `behindDoc` set to match; nil when it holds no
    /// anchor or no wrapping element.
    static func _anchorWrapped(_ xml: String, _ wrap: PictureWrap) -> String? {
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
        var out = String(xml[xml.startIndex ..< open.lowerBound]) + wrap.element + String(xml[end...])
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
    /// The floating picture at paragraph `index` (its own, or inline picture `id`) with its kept anchor markup, or nil.
    private func _floating(_ index: Int, _ id: String?) -> ImageAttachment? {
        guard index < document.paragraphs.count else { return nil }
        let image = id.map { document.paragraphs[index].inlineImages[$0] } ?? document.paragraphs[index].image
        guard let image, image.float != nil, image.sourceXML?.containsSubstring("<wp:anchor") == true else { return nil }
        return image
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
              let patched = String._anchorWrapped(xml, wrap), var f = old.float else { return false }
        var new = old
        new.sourceXML = patched
        f.wraps = wrap == .square || wrap == .tight || wrap == .through
        f.wrapsTight = wrap == .tight || wrap == .through
        f.wrapSide = nil
        f.wrapReach = 1
        f.wrapBottomShare = 1
        f.wrapTopSkip = 0
        f.wrapPolygon = []
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

    /// The words in the text box at `index` (its paragraphs, one per line) when they are plain enough to edit as words
    /// (no character or paragraph formatting, no table); nil for anything else.
    public func textBoxText(at index: Int, inline id: String? = nil) -> String? {
        guard let image = _floating(index, id), let box = image.textBox, let xml = image.sourceXML,
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
              let old = _floating(index, id), var box = old.textBox, let xml = old.sourceXML,
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
        _floating(index, id)?.textBox?.autoHeight == true
    }

    /// The text box at `index` as paragraphs to edit in place, when it holds nothing the in-place editor would lose
    /// (no table, picture, field or markup it cannot write back); nil for anything else.
    public func textBoxParagraphs(at index: Int, inline id: String? = nil) -> [RichParagraph]? {
        guard let image = _floating(index, id), let box = image.textBox, let xml = image.sourceXML,
              let open = xml.rangeOfSubstring("<w:txbxContent>"),
              let close = xml.rangeOfSubstring("</w:txbxContent>", in: open.upperBound ..< xml.endIndex) else { return nil }
        let inner = String(xml[open.upperBound ..< close.lowerBound])
        // (Fields, tracked changes and bookmarks are written back by the document writer as they were read. A link to a
        // page outside the file needs a relationship in the file's own list, which the box's text cannot make: not editable yet.)
        for marker in ["<w:tbl", "<w:drawing", "<mc:", "<w:sdt", "<w:object", "<w:pict"]
        where inner.containsSubstring(marker) { return nil }
        if inner.containsSubstring("<w:hyperlink"), inner.containsSubstring("r:id=") { return nil }
        guard box.paragraphs.allSatisfy({ $0.image == nil && $0.inlineImages.isEmpty && $0.keptTable == nil }) else { return nil }
        return box.paragraphs
    }

    /// Replace the content of the text box at `index` with `paragraphs`, written as `contentXML` (the `w:txbxContent` body),
    /// one undo step. False when the box is not editable in place or nothing changed.
    @discardableResult
    public func setTextBoxContent(at index: Int, inline id: String? = nil, paragraphs: [RichParagraph], contentXML: String, height: Double? = nil) -> Bool {
        guard textBoxParagraphs(at: index, inline: id) != nil,
              let old = _floating(index, id), var box = old.textBox, let xml = old.sourceXML,
              let open = xml.rangeOfSubstring("<w:txbxContent>"),
              let close = xml.rangeOfSubstring("</w:txbxContent>", in: open.upperBound ..< xml.endIndex) else { return false }
        // Revision and bookmark ids are one space for the whole file. The writer numbers a box's from 1 like the body's, so move
        // them above every id the other boxes already hold (the body's revisions are renumbered from 1 on save).
        var highest = 99_999
        for (i, p) in document.paragraphs.enumerated() {
            for other in [p.image].compactMap({ $0 }) + Array(p.inlineImages.values) {
                if i == index, other.id == old.id { continue }
                if let x = other.sourceXML { highest = max(highest, Self._highestRevisionId(in: x)) }
            }
        }
        let patched = String(xml[xml.startIndex ..< open.upperBound]) + Self._shiftRevisionIds(contentXML, by: highest) + String(xml[close.lowerBound...])
        var new = old
        // (A box that resizes to fit its text keeps the height its text now needs, as Word's does.)
        if let height, box.autoHeight, abs(height - old.height) > 0.5 { new.height = height }
        guard patched != xml || new.height != old.height else { return false }
        new.sourceXML = patched
        box.paragraphs = paragraphs
        new.textBox = box
        _store(index, id, old: old, new: new)
        return true
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
