// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import OfficeText

/// Group and Ungroup for shapes the user drew: the markup side. Shapes stand on the page (`relativeFrom="page"`), so a group is
/// the box that holds them, each child keeping its own place in page units (`chOff` is the group's corner). Anything else
/// (a text box held by its paragraph, a shape inside a group already) is left alone: these return nil. A floating picture
/// (`pic:pic`) groups like a shape: its picture file goes with it as a kept relationship, the part itself staying the
/// document's (`parts`, the document's `keptParts`, gives its bytes to draw).
enum ShapeGroups {
    private static let wpsNS = "http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
    private static let wpgNS = "http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
    private static let picNS = "http://schemas.openxmlformats.org/drawingml/2006/picture"

    /// One member: a shape (`wps:wsp`) or a picture (`pic:pic`), `wsp` its whole element, `rels` the files it names.
    private struct Piece {
        var x: Int; var y: Int; var cx: Int; var cy: Int; var wsp: String; var name: String? = nil; var rels: [KeptRel] = []
        var isPicture: Bool { wsp.hasPrefix("<pic:pic") }
    }

    /// The integer `name="…"` attribute of the first tag `tag` in `xml`.
    private static func intAttr(_ xml: String, _ tag: String, _ name: String) -> Int? {
        guard let t = xml.rangeOfSubstring("<\(tag)"), let e = xml.rangeOfSubstring(">", in: t.upperBound ..< xml.endIndex),
              let a = xml.rangeOfSubstring(" \(name)=\"", in: t.upperBound ..< e.lowerBound),
              let q = xml.rangeOfSubstring("\"", in: a.upperBound ..< e.lowerBound) else { return nil }
        return Int(xml[a.upperBound ..< q.lowerBound])
    }

    /// The text between `<tag…>` and `</tag>` for the first such element.
    private static func inner(_ xml: String, _ tag: String) -> String? {
        guard let t = xml.rangeOfSubstring("<\(tag)"), let e = xml.rangeOfSubstring(">", in: t.upperBound ..< xml.endIndex),
              let c = xml.rangeOfSubstring("</\(tag)>", in: e.upperBound ..< xml.endIndex) else { return nil }
        return String(xml[e.upperBound ..< c.lowerBound])
    }

    private static func pageOffset(_ xml: String, _ element: String) -> Int? {
        guard let body = inner(xml, "wp:\(element)"), let open = xml.rangeOfSubstring("<wp:\(element) "),
              let e = xml.rangeOfSubstring(">", in: open.upperBound ..< xml.endIndex),
              xml[open.upperBound ..< e.lowerBound].containsSubstring("relativeFrom=\"page\"") else { return nil }
        return inner(body, "wp:posOffset").flatMap { Int($0) }
    }

    /// The whole `<wps:wsp …>…</wps:wsp>` of a drawing, when it holds exactly one and nothing a group could not carry.
    private static func wspElement(_ xml: String) -> String? {
        guard let s = xml.rangeOfSubstring("<wps:wsp"), let e = xml.rangeOfSubstring("</wps:wsp>", in: s.upperBound ..< xml.endIndex) else { return nil }
        let wsp = String(xml[s.lowerBound ..< e.upperBound])
        for bad in ["r:embed", "r:id=", "r:link", "<wpg:", "<pic:", "<mc:", "<wps:wsp"] where wsp.dropFirst(8).containsSubstring(bad) { return nil }
        return wsp
    }

    /// The whole `<pic:pic …>…</pic:pic>` of a drawing, when it holds exactly one picture whose file is in the package
    /// (`r:embed`; a linked picture or anything a group could not carry gives nil).
    private static func picElement(_ xml: String) -> String? {
        guard !xml.containsSubstring("<wps:wsp"), let s = xml.rangeOfSubstring("<pic:pic"),
              let e = xml.rangeOfSubstring("</pic:pic>", in: s.upperBound ..< xml.endIndex) else { return nil }
        let pic = String(xml[s.lowerBound ..< e.upperBound])
        for bad in ["r:id=", "r:link", "<wpg:", "<mc:", "<pic:pic", "<wps:"] where pic.dropFirst(8).containsSubstring(bad) { return nil }
        guard pic.containsSubstring("r:embed=\""), !xml[e.upperBound...].containsSubstring("<pic:pic") else { return nil }
        return pic.hasPrefix("<pic:pic xmlns:pic") || pic.containsSubstring("xmlns:pic=") ? pic : pic.replacingFirst("<pic:pic", "<pic:pic xmlns:pic=\"\(picNS)\"")
    }

    /// The relationships `element` names (by any attribute), nil when one it names is not among `rels`.
    private static func named(_ element: String, _ rels: [KeptRel]) -> [KeptRel]? {
        var out: [KeptRel] = []
        var rest = Substring(element)
        while let a = rest.rangeOfSubstring("r:embed=\""), let q = rest.rangeOfSubstring("\"", in: a.upperBound ..< rest.endIndex) {
            let id = String(rest[a.upperBound ..< q.lowerBound])
            rest = rest[q.upperBound...]
            guard let rel = rels.first(where: { $0.id == id }), !rel.external else { return nil }
            if !out.contains(rel) { out.append(rel) }
        }
        return out
    }

    /// The name a member goes by: a picture's own `pic:cNvPr`, a shape's `wps:cNvPr` (inside a group).
    private static func ownName(_ element: String) -> String? {
        guard let c = element.rangeOfSubstring(element.hasPrefix("<pic:pic") ? "<pic:cNvPr " : "<wps:cNvPr "),
              let e = element.rangeOfSubstring(">", in: c.upperBound ..< element.endIndex),
              let a = element.rangeOfSubstring(" name=\"", in: c.upperBound ..< e.lowerBound),
              let q = element.rangeOfSubstring("\"", in: a.upperBound ..< e.lowerBound) else { return nil }
        return String(element[a.upperBound ..< q.lowerBound])
    }

    /// `pic` with its own id and name (`pic:cNvPr`) set, as Word numbers the members of a group.
    private static func renamedPicture(_ pic: String, id: Int, _ name: String?) -> String {
        guard let c = pic.rangeOfSubstring("<pic:cNvPr "), let e = pic.rangeOfSubstring(">", in: c.upperBound ..< pic.endIndex) else { return pic }
        var attrs = String(pic[c.upperBound ..< e.lowerBound])
        let selfClosing = attrs.hasSuffix("/")
        if selfClosing { attrs.removeLast() }
        func value(_ k: String) -> String? {
            guard let a = attrs.rangeOfSubstring("\(k)=\""), let q = attrs.rangeOfSubstring("\"", in: a.upperBound ..< attrs.endIndex) else { return nil }
            return String(attrs[a.upperBound ..< q.lowerBound])
        }
        var rest = attrs
        for k in ["id", "name"] {
            if let v = value(k) { rest = rest.replacingAll("\(k)=\"\(v)\"", with: "") }
        }
        let keptName = name ?? value("name") ?? "Picture \(id)"
        let others = rest.split(separator: " ").joined(separator: " ")
        return String(pic[pic.startIndex ..< c.upperBound]) + "id=\"\(id)\" name=\"\(keptName)\"" + (others.isEmpty ? "" : " " + others)
            + (selfClosing ? "/" : "") + String(pic[e.lowerBound...])
    }

    /// The bytes behind `rels`, from the document's parts (`keptParts`, keyed by package path).
    private static func files(_ rels: [KeptRel], _ parts: [String: Data]) -> [String: Data] {
        var out: [String: Data] = [:]
        for r in rels {
            let path = r.target.hasPrefix("/") ? String(r.target.dropFirst()) : "word/" + r.target
            if let d = parts[path] { out[path] = d }
        }
        return out
    }

    /// `wsp` with its shape transform's offset and extent set (EMU).
    private static func placed(_ wsp: String, x: Int, y: Int, cx: Int, cy: Int) -> String? {
        guard let o = wsp.rangeOfSubstring("<a:off "), let oe = wsp.rangeOfSubstring("/>", in: o.upperBound ..< wsp.endIndex),
              let x0 = wsp.rangeOfSubstring("<a:ext ", in: oe.upperBound ..< wsp.endIndex),
              let xe = wsp.rangeOfSubstring("/>", in: x0.upperBound ..< wsp.endIndex) else { return nil }
        return String(wsp[wsp.startIndex ..< o.lowerBound]) + "<a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/>" + String(wsp[xe.upperBound...])
    }

    /// A page-anchored drawing holding `graphic` (the `a:graphicData` body), square wrap.
    private static func anchor(x: Int, y: Int, cx: Int, cy: Int, name: String, uri: String, graphic: String) -> String {
        "<w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"114300\" distR=\"114300\" simplePos=\"0\" relativeHeight=\"251659264\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">"
            + "<wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"page\"><wp:posOffset>\(x)</wp:posOffset></wp:positionH>"
            + "<wp:positionV relativeFrom=\"page\"><wp:posOffset>\(y)</wp:posOffset></wp:positionV>"
            + "<wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/><wp:wrapSquare wrapText=\"bothSides\"/>"
            + "<wp:docPr id=\"100\" name=\"\(name)\"/><wp:cNvGraphicFramePr/>"
            + "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"\(uri)\">\(graphic)</a:graphicData></a:graphic></wp:anchor></w:drawing>"
    }

    /// Whether `image` is a shape or picture this can group: a floating `wps:wsp` or `pic:pic` standing on the page.
    static func isGroupable(_ image: ImageAttachment) -> Bool { piece(image) != nil }

    private static func piece(_ image: ImageAttachment) -> Piece? {
        guard image.float != nil, let xml = image.sourceXML, xml.containsSubstring("<wp:anchor"), !xml.containsSubstring("<wpg:wgp"),
              let wsp = wspElement(xml) ?? picElement(xml), let rels = named(wsp, image.sourceRels),
              let x = pageOffset(xml, "positionH"), let y = pageOffset(xml, "positionV"),
              let cx = intAttr(xml, "wp:extent", "cx"), let cy = intAttr(xml, "wp:extent", "cy"), cx > 0, cy > 0 else { return nil }
        var name: String?
        if let d = xml.rangeOfSubstring("<wp:docPr "), let e = xml.rangeOfSubstring(">", in: d.upperBound ..< xml.endIndex),
           let a = xml.rangeOfSubstring(" name=\"", in: d.upperBound ..< e.lowerBound),
           let q = xml.rangeOfSubstring("\"", in: a.upperBound ..< e.lowerBound) { name = String(xml[a.upperBound ..< q.lowerBound]) }
        return Piece(x: x, y: y, cx: cx, cy: cy, wsp: wsp, name: name, rels: rels)
    }

    /// The box a piece fills on the page once its turn (`rot` on its transform, 60000ths of a degree) is applied.
    private static func visibleBox(_ p: Piece) -> Piece {
        guard let r = intAttr(p.wsp, "a:xfrm", "rot"), r % 21_600_000 != 0 else { return p }
        let t = Double(r) / 60000 * Double.pi / 180
        let w = abs(Double(p.cx) * cos(t)) + abs(Double(p.cy) * sin(t)), h = abs(Double(p.cx) * sin(t)) + abs(Double(p.cy) * cos(t))
        var q = p
        let rw = Int(w.rounded()), rh = Int(h.rounded())
        q.x = p.x + (p.cx - rw) / 2; q.y = p.y + (p.cy - rh) / 2; q.cx = rw; q.cy = rh
        return q
    }

    /// The shapes as one group (named "Group `number`"), standing where the shapes stand; nil unless there are two or more and
    /// every one is groupable.
    static func group(_ shapes: [ImageAttachment], number: Int, parts: [String: Data] = [:]) -> ImageAttachment? {
        let pieces = shapes.compactMap(piece)
        guard shapes.count >= 2, pieces.count == shapes.count else { return nil }
        // The group's box holds what the eye sees: a turned shape counts by the box its turn sweeps.
        let seen = pieces.map(visibleBox)
        let left = seen.map(\.x).min()!, top = seen.map(\.y).min()!
        let cx = seen.map { $0.x + $0.cx }.max()! - left, cy = seen.map { $0.y + $0.cy }.max()! - top
        var children = ""
        for (k, p) in pieces.enumerated() {
            guard var c = placed(p.wsp, x: p.x, y: p.y, cx: p.cx, cy: p.cy) else { return nil }
            // The shape keeps its own name inside the group (Word's `wps:cNvPr`, a picture's `pic:cNvPr`), so ungrouping gives it back.
            if p.isPicture { c = renamedPicture(c, id: k + 1, p.name) } else if let n = p.name, let open = c.rangeOfSubstring(">") {
                c = String(c[c.startIndex ..< open.upperBound]) + "<wps:cNvPr id=\"\(k + 1)\" name=\"\(n)\"/>" + String(c[open.upperBound...])
            }
            children += c
        }
        let graphic = "<wpg:wgp xmlns:wpg=\"\(wpgNS)\" xmlns:wps=\"\(wpsNS)\"><wpg:cNvGrpSpPr/><wpg:grpSpPr><a:xfrm><a:off x=\"\(left)\" y=\"\(top)\"/>"
            + "<a:ext cx=\"\(cx)\" cy=\"\(cy)\"/><a:chOff x=\"\(left)\" y=\"\(top)\"/><a:chExt cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm></wpg:grpSpPr>\(children)</wpg:wgp>"
        let drawing = anchor(x: left, y: top, cx: cx, cy: cy, name: "Group \(number)", uri: wpgNS, graphic: graphic)
        let rels = pieces.flatMap(\.rels)
        return TextBoxInsert.read(drawing, rels: rels, parts: files(rels, parts)) { $0.sourceXML?.containsSubstring("<wpg:wgp") == true }
    }

    /// Whether `image` is a group of shapes `ungroup` can take apart.
    static func isGroup(_ image: ImageAttachment) -> Bool { children(image) != nil }

    private static func children(_ image: ImageAttachment) -> [Piece]? {
        guard image.float != nil, let xml = image.sourceXML, xml.containsSubstring("<wpg:wgp"),
              let gx = pageOffset(xml, "positionH"), let gy = pageOffset(xml, "positionV"),
              let body = inner(xml, "wpg:wgp"), let gp = inner(body, "wpg:grpSpPr"),
              let ox = intAttr(gp, "a:off", "x"), let oy = intAttr(gp, "a:off", "y"),
              let ex = intAttr(gp, "a:ext", "cx"), let ey = intAttr(gp, "a:ext", "cy"),
              let px = intAttr(gp, "a:chOff", "x"), let py = intAttr(gp, "a:chOff", "y"),
              let qx = intAttr(gp, "a:chExt", "cx"), let qy = intAttr(gp, "a:chExt", "cy"), qx > 0, qy > 0, ex > 0, ey > 0,
              !body.containsSubstring("<wpg:grpSp>"), !body.containsSubstring("<wpg:wgp"),
              !gp.containsSubstring("rot=\"") else { return nil }
        _ = (ox, oy)
        let sx = Double(ex) / Double(qx), sy = Double(ey) / Double(qy)
        var out: [Piece] = []
        var rest = Substring(body)
        // The members in their order, shapes and pictures alike.
        while true {
            let shape = rest.rangeOfSubstring("<wps:wsp"), picture = rest.rangeOfSubstring("<pic:pic")
            guard let s = [shape, picture].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) else { break }
            let isPicture = s == picture
            guard let e = rest.rangeOfSubstring(isPicture ? "</pic:pic>" : "</wps:wsp>", in: s.upperBound ..< rest.endIndex) else { return nil }
            let wsp = String(rest[s.lowerBound ..< e.upperBound])
            rest = rest[e.upperBound...]
            guard let cx = intAttr(wsp, "a:ext", "cx"), let cy = intAttr(wsp, "a:ext", "cy"),
                  let cox = intAttr(wsp, "a:off", "x"), let coy = intAttr(wsp, "a:off", "y"),
                  let element = isPicture ? picElement(wsp) : wspElement(wsp), let rels = named(element, image.sourceRels) else { return nil }
            out.append(Piece(x: gx + Int(Double(cox - px) * sx), y: gy + Int(Double(coy - py) * sy),
                             cx: Int(Double(cx) * sx), cy: Int(Double(cy) * sy), wsp: element, name: ownName(element), rels: rels))
        }
        return out.isEmpty ? nil : out
    }

    /// One change to a child of a group (EMU).

    /// `wsp` with its text body set to `body` (a `w:txbxContent` inside; a plain shape gets a text part, centred as Word's).
    private static func withText(_ wsp: String, _ body: String) -> String? {
        var x = wsp
        if let o = x.rangeOfSubstring("<w:txbxContent>"), let c = x.rangeOfSubstring("</w:txbxContent>", in: o.upperBound ..< x.endIndex) {
            x.replaceSubrange(o.upperBound ..< c.lowerBound, with: body); return x
        }
        guard !x.containsSubstring("<wps:txbx"), !x.containsSubstring("<mc:"), let end = x.rangeOfSubstring("</wps:spPr>") else { return nil }
        x.insert(contentsOf: "<wps:txbx><w:txbxContent>\(body)</w:txbxContent></wps:txbx>", at: end.upperBound)
        if let b = x.rangeOfSubstring("<wps:bodyPr "), let close = x.rangeOfSubstring(">", in: b.upperBound ..< x.endIndex),
           let a = x.rangeOfSubstring("anchor=\"t\"", in: b.upperBound ..< close.lowerBound) { x.replaceSubrange(a, with: "anchor=\"ctr\"") }
        return x
    }

    /// Child `k` as a text box of its own (a shape without text gets an empty one), for the editor to read its words from.
    static func textProxy(_ image: ImageAttachment, child k: Int) -> ImageAttachment? {
        guard let pieces = children(image), pieces.indices.contains(k), !pieces[k].isPicture, let wsp = pieces[k].wsp.containsSubstring("<w:txbxContent>") ? pieces[k].wsp : withText(pieces[k].wsp, "<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr></w:p>"),
              let placedWsp = placed(wsp, x: 0, y: 0, cx: pieces[k].cx, cy: pieces[k].cy) else { return nil }
        let drawing = anchor(x: pieces[k].x, y: pieces[k].y, cx: pieces[k].cx, cy: pieces[k].cy, name: pieces[k].name ?? "Shape", uri: wpsNS,
                             graphic: placedWsp.hasPrefix("<wps:wsp xmlns:wps") ? placedWsp : placedWsp.replacingFirst("<wps:wsp", "<wps:wsp xmlns:wps=\"\(wpsNS)\""))
        guard var shape = TextBoxInsert.read(drawing, { _ in true }) else { return nil }
        if shape.textBox == nil {
            var para = RichParagraph(text: "")
            para.style.alignment = .center
            shape.textBox = RichTextBox(paragraphs: [para])
        }
        return shape
    }

    /// The group with child `k` changed: the child is moved, resized or taken out, and the group's box (its own transform, its
    /// extent and its place on the page) is made to hold the children as they stand. Everything else of the drawing (wrap,
    /// name, the children's own markup and names) is kept. Nil when the group is not one `ungroup` could take apart, `k` is
    /// not a child, or the change would empty the group.
    static func editChild(_ image: ImageAttachment, child k: Int, _ change: GroupChildChange, parts: [String: Data] = [:]) -> ImageAttachment? {
        guard var pieces = children(image), pieces.indices.contains(k), var xml = image.sourceXML else { return nil }
        switch change {
        case .move(let dx, let dy): pieces[k].x += dx; pieces[k].y += dy
        case .resize(let cx, let cy): guard cx > 0, cy > 0 else { return nil }; pieces[k].cx = cx; pieces[k].cy = cy
        case .delete: pieces.remove(at: k)
        case .text(let body): guard let w = withText(pieces[k].wsp, body) else { return nil }; pieces[k].wsp = w
        }
        guard !pieces.isEmpty else { return nil }
        let seen = pieces.map(visibleBox)
        let left = seen.map(\.x).min()!, top = seen.map(\.y).min()!
        let cx = seen.map { $0.x + $0.cx }.max()! - left, cy = seen.map { $0.y + $0.cy }.max()! - top
        var kids = ""
        for p in pieces { guard let c = placed(p.wsp, x: p.x, y: p.y, cx: p.cx, cy: p.cy) else { return nil }; kids += c }
        guard let g0 = xml.rangeOfSubstring("<wpg:grpSpPr>"), let g1 = xml.rangeOfSubstring("</wpg:grpSpPr>", in: g0.upperBound ..< xml.endIndex),
              let end = xml.rangeOfSubstring("</wpg:wgp>", in: g1.upperBound ..< xml.endIndex) else { return nil }
        xml.replaceSubrange(g1.upperBound ..< end.lowerBound, with: kids)
        xml.replaceSubrange(g0.upperBound ..< g1.lowerBound, with: "<a:xfrm><a:off x=\"\(left)\" y=\"\(top)\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/><a:chOff x=\"\(left)\" y=\"\(top)\"/><a:chExt cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm>")
        func setOffset(_ element: String, _ v: Int) -> Bool {
            guard let o = xml.rangeOfSubstring("<wp:\(element) "), let a = xml.rangeOfSubstring("<wp:posOffset>", in: o.upperBound ..< xml.endIndex),
                  let b = xml.rangeOfSubstring("</wp:posOffset>", in: a.upperBound ..< xml.endIndex) else { return false }
            xml.replaceSubrange(a.upperBound ..< b.lowerBound, with: String(v)); return true
        }
        guard setOffset("positionH", left), setOffset("positionV", top),
              let e0 = xml.rangeOfSubstring("<wp:extent "), let e1 = xml.rangeOfSubstring("/>", in: e0.upperBound ..< xml.endIndex) else { return nil }
        xml.replaceSubrange(e0.lowerBound ..< e1.upperBound, with: "<wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/>")
        // The pictures still in the group bring their files (a deleted one's is no longer named).
        let rels = pieces.flatMap(\.rels)
        return TextBoxInsert.read(xml, rels: rels, parts: files(rels, parts)) { $0.sourceXML?.containsSubstring("<wpg:wgp") == true }
    }

    /// The shapes a group is made of, each standing where it stood in the group, named from `number` on; nil when the group
    /// is more than shapes.
    static func ungroup(_ image: ImageAttachment, number: Int, parts: [String: Data] = [:]) -> [ImageAttachment]? {
        guard let pieces = children(image) else { return nil }
        var out: [ImageAttachment] = []
        for (k, p) in pieces.enumerated() {
            guard let wsp = placed(p.wsp, x: 0, y: 0, cx: p.cx, cy: p.cy) else { return nil }
            let graphic = p.isPicture ? wsp : wsp.hasPrefix("<wps:wsp xmlns:wps") ? wsp : wsp.replacingFirst("<wps:wsp", "<wps:wsp xmlns:wps=\"\(wpsNS)\"")
            let drawing = anchor(x: p.x, y: p.y, cx: p.cx, cy: p.cy, name: p.name ?? (p.isPicture ? "Picture \(number + k)" : "Shape \(number + k)"),
                                 uri: p.isPicture ? picNS : wpsNS, graphic: graphic)
            guard let shape = TextBoxInsert.read(drawing, rels: p.rels, parts: files(p.rels, parts), { _ in true }) else { return nil }
            out.append(shape)
        }
        return out
    }
}

private extension String {
    func replacingFirst(_ target: String, _ with: String) -> String {
        guard let r = rangeOfSubstring(target) else { return self }
        return String(self[startIndex ..< r.lowerBound]) + with + String(self[r.upperBound...])
    }
}
