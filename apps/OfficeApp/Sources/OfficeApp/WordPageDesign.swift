// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-PG-3: Design > Watermark. Word keeps a watermark as a VML shape in a run of every header part: WordArt text
// ("PowerPlusWaterMarkObject") or a picture ("WordPictureWatermark"), centred on the margins behind the text. Setting
// one writes the document out, puts the shape into each header (making a default one where the last section has
// none), and reads it back, so the headers the layout draws are the parts a save writes.

import Flutter
import Foundation
import OfficeText

enum WordWatermark: Equatable {
    struct TextMark: Equatable {
        var text = "CONFIDENTIAL"
        var font = "Calibri"
        /// Points; nil is Word's "Auto" (as large as fits the margins).
        var size: Double? = nil
        /// 0xRRGGBB; Word's default is silver.
        var color: UInt32 = 0xC0C0C0
        var semitransparent = true
        var diagonal = true
    }
    struct PictureMark: Equatable {
        var data: Data
        /// "png", "jpeg", "gif"…
        var ext: String
        var name: String
        /// The picture's own size in points.
        var naturalWidth: Double
        var naturalHeight: Double
        /// 1 = 100%; nil is Word's "Auto" (as large as fits the margins).
        var scale: Double? = nil
        var washout = true
    }
    case text(TextMark)
    case picture(PictureMark)

    /// Ribbon presets, as Word's gallery has them (diagonal, silver, half transparent).
    static let presets = ["CONFIDENTIAL", "DO NOT COPY", "DRAFT", "SAMPLE", "ASAP", "URGENT"]

    static let _ids = ["PowerPlusWaterMarkObject", "WordPictureWatermark"]

    // MARK: Reading

    /// The watermark the document's first header part holding one shows (for the dialog), or nil.
    static func current(in doc: RichDocument) -> TextMark? {
        for k in doc.keptHeaderFooters where k.kind == .header {
            guard let data = doc.keptParts[k.part], let root = XNode.parse(data) else { continue }
            var found: TextMark? = nil
            func walk(_ n: XNode) {
                if found != nil { return }
                if n.name == "v:shape", (n["id"] ?? "").hasPrefix(_ids[0]), let path = n.first("v:textpath") {
                    var m = TextMark()
                    m.text = path["string"] ?? m.text
                    let style = path["style"] ?? ""
                    if let r = style.rangeOfSubstring("font-family:") {
                        let rest = style[r.upperBound...]
                        m.font = String(rest.prefix { $0 != ";" }).replacingAll("&quot;", with: "").replacingAll("\"", with: "")
                    }
                    if let r = style.rangeOfSubstring("font-size:") {
                        let v = Double(String(style[r.upperBound...].prefix { $0.isNumber || $0 == "." })) ?? 1
                        m.size = v > 1 ? v : nil
                    }
                    let fill = n["fillcolor"] ?? "silver"
                    m.color = fill.hasPrefix("#") ? UInt32(fill.dropFirst().prefix(6), radix: 16) ?? 0xC0C0C0 : 0xC0C0C0
                    m.semitransparent = n.first("v:fill")?["opacity"] != nil
                    m.diagonal = (n["style"] ?? "").containsSubstring("rotation:315")
                    found = m
                    return
                }
                n.children.forEach(walk)
            }
            walk(root)
            if let found { return found }
        }
        return nil
    }

    static func has(in doc: RichDocument) -> Bool {
        doc.keptHeaderFooters.contains { k in
            guard k.kind == .header, let data = doc.keptParts[k.part] else { return false }
            let xml = String(decoding: data, as: UTF8.self)
            return _ids.contains { xml.containsSubstring("\"\($0)") }
        }
    }

    // MARK: Setting

    /// `doc` with `mark` (nil: none) in every header part. `page` is the last section's page.
    static func setting(_ mark: WordWatermark?, in source: RichDocument, page: PageSetup) throws -> RichDocument {
        // Written out and read back first: the editor's own header becomes a part like any other.
        var doc = try DocxFormat.read(try DocxFormat.write(source, pageSetup: page)).document
        if mark != nil {
            // The last section needs a header part of each kind it shows for the mark to be on every page.
            var types = ["default"]
            if page.titlePage || doc.titlePage { types.append("first") }
            if doc.evenAndOddHeaders { types.append("even") }
            for type in types where !doc.keptHeaderFooters.contains(where: { $0.kind == .header && $0.type == type }) {
                guard type != "default" || doc.header.isEmpty else { continue }
                var n = 1
                while doc.keptParts["word/header\(n).xml"] != nil { n += 1 }
                let part = "word/header\(n).xml"
                doc.keptParts[part] = Data(_emptyHeader.utf8)
                doc.keptPartTypes[part] = "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"
                doc.keptHeaderFooters.append(KeptHeaderFooter(kind: .header, type: type, part: part, text: ""))
            }
        }
        let parts = doc.keptParts.keys.filter { $0.hasPrefix("word/header") && $0.hasSuffix(".xml") }.sorted()
        var shape = 1
        for part in parts {
            guard let data = doc.keptParts[part] else { continue }
            var xml = _withoutWatermark(String(decoding: data, as: UTF8.self))
            let file = String(part.dropFirst(5))
            let relsPath = "word/_rels/\(file).rels"
            var rels = doc.keptParts[relsPath].map { String(decoding: $0, as: UTF8.self) }
            if let r = rels { rels = _withoutWatermarkRels(r) }
            if let mark {
                let run: String
                switch mark {
                case .text(let t):
                    run = _textRun(t, shape, page)
                case .picture(let p):
                    var k = 1
                    while doc.keptParts["word/media/watermark\(k).\(p.ext)"] != nil, doc.keptParts["word/media/watermark\(k).\(p.ext)"] != p.data { k += 1 }
                    doc.keptParts["word/media/watermark\(k).\(p.ext)"] = p.data
                    let rel = "<Relationship Id=\"rIdWatermark1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/watermark\(k).\(p.ext)\"/>"
                    if let r = rels, let close = r.rangeOfSubstring("</Relationships>") {
                        var r2 = r; r2.insert(contentsOf: rel, at: close.lowerBound); rels = r2
                    } else {
                        rels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(rel)</Relationships>"
                    }
                    run = _pictureRun(p, shape, page)
                }
                xml = _inserting(run, into: xml)
                shape += 1
            }
            doc.keptParts[part] = Data(xml.utf8)
            if let rels { doc.keptParts[relsPath] = Data(rels.utf8) }
        }
        // Back through the reader, so the headers the layout draws are these parts.
        return try DocxFormat.read(try DocxFormat.write(doc, pageSetup: page)).document
    }

    static let _ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:w10=\"urn:schemas-microsoft-com:office:word\""
    static let _emptyHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:hdr \(_ns)><w:p><w:pPr><w:pStyle w:val=\"Header\"/></w:pPr></w:p></w:hdr>"

    /// Every run holding a watermark shape taken out.
    static func _withoutWatermark(_ original: String) -> String {
        var xml = original
        for id in _ids {
            while let hit = xml.rangeOfSubstring("id=\"\(id)") {
                // The run around it: the last `<w:r>`/`<w:r ` before, the first `</w:r>` after.
                var start: String.Index? = nil
                var from = xml.startIndex
                while let r = xml[from ..< hit.lowerBound].rangeOfSubstring("<w:r") {
                    let c = xml[r.upperBound]
                    if c == ">" || c == " " { start = r.lowerBound }
                    from = r.upperBound
                }
                guard let start, let end = xml[hit.upperBound...].rangeOfSubstring("</w:r>") else { return xml }
                xml.removeSubrange(start ..< end.upperBound)
            }
        }
        return xml
    }

    static func _withoutWatermarkRels(_ original: String) -> String {
        var xml = original
        while let r = xml.rangeOfSubstring("<Relationship Id=\"rIdWatermark"), let end = xml[r.upperBound...].rangeOfSubstring("/>") {
            xml.removeSubrange(r.lowerBound ..< end.upperBound)
        }
        return xml
    }

    /// `run` put into the part's first paragraph (after its properties), the VML namespaces declared on the root.
    static func _inserting(_ run: String, into original: String) -> String {
        var xml = original
        if let root = xml.rangeOfSubstring("<w:hdr"), let gt = xml[root.upperBound...].firstIndex(of: ">") {
            let tag = String(xml[root.lowerBound ..< gt])
            var add = ""
            for (p, uri) in [("r", "http://schemas.openxmlformats.org/officeDocument/2006/relationships"), ("v", "urn:schemas-microsoft-com:vml"),
                             ("o", "urn:schemas-microsoft-com:office:office"), ("w10", "urn:schemas-microsoft-com:office:word")]
            where !tag.containsSubstring("xmlns:\(p)=") { add += " xmlns:\(p)=\"\(uri)\"" }
            xml.insert(contentsOf: add, at: xml[root.lowerBound ..< gt].last == "/" ? xml.index(before: gt) : gt)
        }
        var from = xml.startIndex
        while let r = xml[from...].rangeOfSubstring("<w:p") {
            let c = xml[r.upperBound]
            guard c == ">" || c == " " || c == "/" else { from = r.upperBound; continue }
            guard let gt = xml[r.upperBound...].firstIndex(of: ">") else { break }
            if xml[xml.index(before: gt)] == "/" {
                let head = String(xml[r.lowerBound ..< xml.index(before: gt)])
                xml.replaceSubrange(r.lowerBound ... gt, with: head + ">" + run + "</w:p>")
                return xml
            }
            var at = xml.index(after: gt)
            if xml[at...].hasPrefix("<w:pPr"), let close = xml[at...].rangeOfSubstring("</w:pPr>") { at = close.upperBound }
            else if xml[at...].hasPrefix("<w:pPr/>") { at = xml.index(at, offsetBy: 8) }
            xml.insert(contentsOf: run, at: at)
            return xml
        }
        if let end = xml.rangeOfSubstring("</w:hdr>") {
            xml.insert(contentsOf: "<w:p><w:pPr><w:pStyle w:val=\"Header\"/></w:pPr>\(run)</w:p>", at: end.lowerBound)
        }
        return xml
    }

    static func _pt(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    static func _esc(_ s: String) -> String {
        s.replacingAll("&", with: "&amp;").replacingAll("<", with: "&lt;").replacingAll(">", with: "&gt;").replacingAll("\"", with: "&quot;")
    }

    static let _placement = "z-index:-251657216;mso-position-horizontal:center;mso-position-horizontal-relative:margin;mso-position-vertical:center;mso-position-vertical-relative:margin"

    /// The text's box: its advance by the face's line at `size` points.
    static func _textBox(_ t: TextMark, size: Double) -> (Double, Double) {
        let tp = TextPainter(text: TextSpan(text: t.text, style: Flutter.TextStyle(fontSize: size, fontFamily: OfficeFonts.substitute(t.font))), textDirection: .ltr)
        tp.layout(minWidth: 0, maxWidth: 100000)
        let box = (tp.width, tp.height)
        tp.dispose()
        return box
    }

    /// The shape's size: at a set size, the text's box; at Auto, that box scaled to fit the margins (turned 45 degrees,
    /// its corner-to-corner span across them).
    static func _textSize(_ t: TextMark, _ page: PageSetup) -> (Double, Double) {
        let (w0, h0) = _textBox(t, size: t.size ?? 100)
        guard t.size == nil, w0 > 0, h0 > 0 else { return (w0, h0) }
        let page = page.physical
        let cw = page.width - page.marginLeft - page.marginRight, ch = page.height - page.marginTop - page.marginBottom
        let k = t.diagonal ? min(cw, ch) * 2.0.squareRoot() / (w0 + h0) : min(cw / w0, ch / h0)
        return (w0 * k, h0 * k)
    }

    static func _textRun(_ t: TextMark, _ n: Int, _ page: PageSetup) -> String {
        let (w, h) = _textSize(t, page)
        let fill = t.color == 0xC0C0C0 ? "silver" : "#" + _hex6(t.color)
        return "<w:r><w:rPr><w:noProof/></w:rPr><w:pict>"
            + "<v:shapetype id=\"_x0000_t136\" coordsize=\"21600,21600\" o:spt=\"136\" adj=\"10800\" path=\"m@7,l@8,m@5,21600l@6,21600e\"><v:formulas><v:f eqn=\"sum #0 0 10800\"/><v:f eqn=\"prod #0 2 1\"/><v:f eqn=\"sum 21600 0 @1\"/><v:f eqn=\"sum 0 0 @2\"/><v:f eqn=\"sum 21600 0 @3\"/><v:f eqn=\"if @0 @3 0\"/><v:f eqn=\"if @0 21600 @1\"/><v:f eqn=\"if @0 0 @2\"/><v:f eqn=\"if @0 @4 21600\"/><v:f eqn=\"mid @5 @6\"/><v:f eqn=\"mid @8 @5\"/><v:f eqn=\"mid @7 @8\"/><v:f eqn=\"mid @6 @7\"/><v:f eqn=\"sum @6 0 @5\"/></v:formulas><v:path textpathok=\"t\" o:connecttype=\"custom\" o:connectlocs=\"@9,0;@10,10800;@11,21600;@12,10800\" o:connectangles=\"270,180,90,0\"/><v:textpath on=\"t\" fitshape=\"t\"/><v:handles><v:h position=\"#0,bottomRight\" xrange=\"6629,14971\"/></v:handles><o:lock v:ext=\"edit\" text=\"t\" shapetype=\"t\"/></v:shapetype>"
            + "<v:shape id=\"PowerPlusWaterMarkObject\(n)\" o:spid=\"_x0000_s\(2048 + n)\" type=\"#_x0000_t136\" style=\"position:absolute;margin-left:0;margin-top:0;width:\(_pt(w))pt;height:\(_pt(h))pt;\(t.diagonal ? "rotation:315;" : "")\(_placement)\" o:allowincell=\"f\" fillcolor=\"\(fill)\" stroked=\"f\">"
            + (t.semitransparent ? "<v:fill opacity=\".5\"/>" : "")
            + "<v:textpath style=\"font-family:&quot;\(_esc(t.font))&quot;;font-size:\(t.size.map(_pt) ?? "1")pt\" string=\"\(_esc(t.text))\"/>"
            + "<w10:wrap anchorx=\"margin\" anchory=\"margin\"/></v:shape></w:pict></w:r>"
    }

    static func _pictureRun(_ p: PictureMark, _ n: Int, _ page: PageSetup) -> String {
        var w = p.naturalWidth, h = p.naturalHeight
        if let s = p.scale { w *= s; h *= s } else if w > 0, h > 0 {
            let page = page.physical
            let cw = page.width - page.marginLeft - page.marginRight, ch = page.height - page.marginTop - page.marginBottom
            let k = min(cw / w, ch / h)
            w *= k; h *= k
        }
        return "<w:r><w:rPr><w:noProof/></w:rPr><w:pict>"
            + "<v:shapetype id=\"_x0000_t75\" coordsize=\"21600,21600\" o:spt=\"75\" o:preferrelative=\"t\" path=\"m@4@5l@4@11@9@11@9@5xe\" filled=\"f\" stroked=\"f\"><v:stroke joinstyle=\"miter\"/><v:formulas><v:f eqn=\"if lineDrawn pixelLineWidth 0\"/><v:f eqn=\"sum @0 1 0\"/><v:f eqn=\"sum 0 0 @1\"/><v:f eqn=\"prod @2 1 2\"/><v:f eqn=\"prod @3 21600 pixelWidth\"/><v:f eqn=\"prod @3 21600 pixelHeight\"/><v:f eqn=\"sum @0 0 1\"/><v:f eqn=\"prod @6 1 2\"/><v:f eqn=\"prod @7 21600 pixelWidth\"/><v:f eqn=\"sum @8 21600 0\"/><v:f eqn=\"prod @7 21600 pixelHeight\"/><v:f eqn=\"sum @10 21600 0\"/></v:formulas><v:path o:extrusionok=\"f\" gradientshapeok=\"t\" o:connecttype=\"rect\"/><o:lock v:ext=\"edit\" aspectratio=\"t\"/></v:shapetype>"
            + "<v:shape id=\"WordPictureWatermark\(n)\" o:spid=\"_x0000_s\(2048 + n)\" type=\"#_x0000_t75\" style=\"position:absolute;margin-left:0;margin-top:0;width:\(_pt(w))pt;height:\(_pt(h))pt;\(_placement)\" o:allowincell=\"f\">"
            + "<v:imagedata r:id=\"rIdWatermark1\" o:title=\"\(_esc(p.name))\"\(p.washout ? " gain=\"19661f\" blacklevel=\"22938f\"" : "")/>"
            + "<w10:wrap anchorx=\"margin\" anchory=\"margin\"/></v:shape></w:pict></w:r>"
    }

    static func _hex6(_ c: UInt32) -> String {
        let digits = Array("0123456789ABCDEF")
        return String((0 ..< 6).reversed().map { digits[Int((c >> (UInt32($0) * 4)) & 0xF)] })
    }
}
