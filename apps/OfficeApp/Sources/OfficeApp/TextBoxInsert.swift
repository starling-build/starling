// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import OfficeText

/// Insert → Text Box: a new floating text box (a DrawingML `wps:wsp` in a `wp:anchor`, square wrap, thin black outline, white
/// fill). It is made as file markup and read back by the same reader that opens a Word file, so the layout and the writer see
/// it as they see one Word made.
enum TextBoxInsert {
    /// The `w:drawing` of a text box `width` × `height` points, holding `text` as one paragraph, 18 pt in and 18 pt below its
    /// paragraph; `id` numbers its `wp:docPr`.
    static func drawingXML(text: String?, width: Double, height: Double, id: Int = 100, preset: String = "rect", fill: String = "FFFFFF", name: String = "Text Box", number: Int? = nil, page: (x: Double, y: Double)? = nil, wordArt: String? = nil) -> String {
        let cx = Int(width * 12700), cy = Int(height * 12700)
        let esc = DocxFormat._esc(text ?? "")
        return "<w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"114300\" distR=\"114300\" simplePos=\"0\" relativeHeight=\"251659264\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">"
            + "<wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"\(page == nil ? "column" : "page")\"><wp:posOffset>\(page.map { Int($0.x * 12700) } ?? 228600)</wp:posOffset></wp:positionH>"
            + "<wp:positionV relativeFrom=\"\(page == nil ? "paragraph" : "page")\"><wp:posOffset>\(page.map { Int($0.y * 12700) } ?? 228600)</wp:posOffset></wp:positionV>"
            + "<wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/><wp:wrapSquare wrapText=\"bothSides\"/>"
            + "<wp:docPr id=\"\(id)\" name=\"\(name) \(number ?? id)\"/><wp:cNvGraphicFramePr/>"
            + "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\">"
            + "<wps:wsp xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:cNvSpPr\(text == nil ? "" : " txBox=\"1\"")/>"
            + "<wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"\(preset)\"><a:avLst/></a:prstGeom>"
            + (wordArt != nil ? "<a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr>"
               : "<a:solidFill><a:srgbClr val=\"\(fill)\"/></a:solidFill><a:ln w=\"9525\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill></a:ln></wps:spPr>")
            + (text == nil ? "" : "<wps:txbx><w:txbxContent><w:p>" + (wordArt != nil ? "<w:pPr><w:jc w:val=\"center\"/></w:pPr>" : "")
               + "<w:r>" + (wordArt.map { "<w:rPr>\($0)</w:rPr>" } ?? "") + "<w:t xml:space=\"preserve\">\(esc)</w:t></w:r></w:p></w:txbxContent></wps:txbx>")
            + "<wps:bodyPr rot=\"0\" vert=\"horz\" wrap=\"\(wordArt != nil ? "none" : "square")\" lIns=\"91440\" tIns=\"45720\" rIns=\"91440\" bIns=\"45720\" anchor=\"\(text == nil ? "ctr" : "t")\" anchorCtr=\"0\">"
            + (wordArt != nil ? "<a:prstTxWarp prst=\"textNoShape\"><a:avLst/></a:prstTxWarp>" : "") + (text != nil ? "<a:spAutoFit/>" : "<a:noAutofit/>") + "</wps:bodyPr>"
            + "</wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing>"
    }

    /// A new text box as the picture-like object the document holds, or nil if the reader does not take it as one.
    static func make(text: String = "Text box", width: Double = 144, height: Double = 30.4) -> ImageAttachment? {
        read(drawingXML(text: text, width: width, height: height)) { $0.textBox != nil }
    }

    /// Insert → WordArt: Word's first styles, as the run properties of the box's text (36 pt, with the letters' own fill,
    /// outline and shadow, which the reader takes from `w14:` run properties and the writer keeps as written).
    static let wordArtStyles: [(name: String, runProperties: String)] = {
        let shadow = "<w14:shadow w14:blurRad=\"38100\" w14:dist=\"19050\" w14:dir=\"2700000\" w14:sx=\"100000\" w14:sy=\"100000\" w14:kx=\"0\" w14:ky=\"0\" w14:algn=\"tl\">"
            + "<w14:srgbClr w14:val=\"000000\"><w14:alpha w14:val=\"60000\"/></w14:srgbClr></w14:shadow>"
        func line(_ rgb: String, _ emu: Int) -> String {
            "<w14:textOutline w14:w=\"\(emu)\" w14:cap=\"flat\" w14:cmpd=\"sng\" w14:algn=\"ctr\"><w14:solidFill><w14:srgbClr w14:val=\"\(rgb)\"/></w14:solidFill><w14:prstDash w14:val=\"solid\"/><w14:round/></w14:textOutline>"
        }
        func fill(_ rgb: String) -> String { "<w14:textFill><w14:solidFill><w14:srgbClr w14:val=\"\(rgb)\"/></w14:solidFill></w14:textFill>" }
        let size = "<w:sz w:val=\"72\"/><w:szCs w:val=\"72\"/>"
        return [
            ("Fill: Black; Shadow", "<w:color w:val=\"000000\"/>" + size + shadow),
            ("Fill: Blue; Shadow", "<w:color w:val=\"4472C4\"/>" + size + shadow),
            ("Fill: Orange; Shadow", "<w:color w:val=\"ED7D31\"/>" + size + shadow),
            ("Fill: White; Outline: Blue", "<w:color w:val=\"FFFFFF\"/>" + size + line("4472C4", 9525) + fill("FFFFFF")),
            ("Outline: Black; No fill", "<w:color w:val=\"000000\"/>" + size + line("000000", 9525) + "<w14:textFill><w14:noFill/></w14:textFill>"),
        ]
    }()

    /// A new WordArt box in style `style` of `wordArtStyles`: a text box with no line or fill that takes its text's size.
    static func makeWordArt(style: Int, text: String = "Your text here", number: Int = 1) -> ImageAttachment? {
        guard wordArtStyles.indices.contains(style) else { return nil }
        // (The box is fitted to its text when laid out; the extent is only a starting size.)
        let width = Double(text.count) * 20 + 14.4, height = 36 * 1.22 + 7.2
        return read(drawingXML(text: text, width: width, height: height, name: "Text Box", number: number, wordArt: wordArtStyles[style].runProperties)) { $0.textBox != nil }
    }

    /// The words Word names a shape of this preset by ("Rectangle 1", "Oval 2"…).
    static func shapeLabel(_ preset: String) -> String {
        switch preset {
        case "rect": return "Rectangle"
        case "roundRect": return "Rectangle: Rounded Corners"
        case "ellipse": return "Oval"
        case "triangle": return "Isosceles Triangle"
        case "rightArrow": return "Arrow: Right"
        default: return "Shape"
        }
    }

    /// One more than the highest number any drawing in `document` already carries in its name ("Oval 7" → 8), as Word counts.
    static func nextShapeNumber(in document: RichDocument) -> Int {
        var highest = 0
        func scan(_ xml: String?) {
            guard let xml else { return }
            var rest = Substring(xml)
            while let r = rest.rangeOfSubstring("<wp:docPr ") {
                rest = rest[r.upperBound...]
                guard let n = rest.rangeOfSubstring("name=\""), let e = rest[n.upperBound...].firstIndex(of: "\"") else { continue }
                if let v = Int(rest[n.upperBound ..< e].split(separator: " ").last ?? "") { highest = max(highest, v) }
            }
        }
        for p in document.paragraphs {
            scan(p.image?.sourceXML)
            for image in p.inlineImages.values { scan(image.sourceXML) }
        }
        return highest + 1
    }

    /// A new filled shape (`rect`, `roundRect`, `ellipse`, `triangle`, `rightArrow`…), without text (typing in it adds the text part, see `giveShapeText`). `page` puts its corner that
    /// many points from the page's top left corner (where the user clicked); `number` is the one in its name.
    static func makeShape(preset: String, width: Double = 96, height: Double = 72, number: Int? = nil, page: (x: Double, y: Double)? = nil) -> ImageAttachment? {
        read(drawingXML(text: nil, width: width, height: height, preset: preset, fill: "4472C4", name: shapeLabel(preset), number: number, page: page)) { _ in true }
    }

    /// `drawing` read as a file would read it. `rels` are the relationships it names (a picture's file), with the bytes of
    /// their parts in `parts` (package path): the drawing is read with them, so a picture in it draws, and the attachment
    /// carries them as its own (`sourceRels`, renamed; the parts stay the document's).
    static func read(_ drawing: String, rels: [KeptRel] = [], parts: [String: Data] = [:], _ wanted: (ImageAttachment) -> Bool) -> ImageAttachment? {
        guard let base = try? DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter),
              var entries = try? Zip.read(base), let di = entries.firstIndex(where: { $0.name == "word/document.xml" }) else { return nil }
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        guard let r = xml.rangeOfSubstring("<w:r>"), let end = xml.rangeOfSubstring("</w:r>") else { return nil }
        var drawing = drawing
        if !rels.isEmpty {
            // Each named relationship under an id the throwaway file cannot already use.
            guard let ri = entries.firstIndex(where: { $0.name == "word/_rels/document.xml.rels" }) else { return nil }
            var relsXML = String(decoding: entries[ri].data, as: UTF8.self)
            guard let close = relsXML.rangeOfSubstring("</Relationships>") else { return nil }
            var added = ""
            var seen = Set<String>()
            for rel in rels where seen.insert(rel.id).inserted {
                let nid = "rIdGroupPart\(seen.count)"
                for attr in DocxFormat._relationshipAttributes { drawing = drawing.replacingAll("\(attr)=\"\(rel.id)\"", with: "\(attr)=\"\(nid)\"") }
                added += "<Relationship Id=\"\(nid)\" Type=\"\(DocxFormat._esc(rel.type))\" Target=\"\(DocxFormat._esc(rel.target))\"\(rel.external ? " TargetMode=\"External\"" : "")/>"
            }
            relsXML.insert(contentsOf: added, at: close.lowerBound)
            entries[ri] = ZipEntry(name: entries[ri].name, data: Data(relsXML.utf8))
            for (path, data) in parts.sorted(by: { $0.key < $1.key }) where !entries.contains(where: { $0.name == path }) {
                entries.append(ZipEntry(name: path, data: data))
            }
        }
        xml.replaceSubrange(r.lowerBound ..< end.upperBound, with: "<w:r>" + drawing + "</w:r>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        guard let data = try? Zip.write(entries), let doc = try? DocxFormat.read(data).document else { return nil }
        for p in doc.paragraphs {
            if let image = p.image, wanted(image), image.float != nil { return image }
            if let image = p.inlineImages.values.first(where: { wanted($0) && $0.float != nil }) { return image }
        }
        return nil
    }

    /// The `w:txbxContent` body for `paragraphs`: what the document writer makes of them, lifted out of a throwaway file.
    static func contentXML(_ paragraphs: [RichParagraph]) -> String? {
        contentXML(RichDocument(paragraphs: paragraphs))
    }

    /// The same for a small document: its tables are written with their looks and grids.
    static func contentXML(_ document: RichDocument) -> String? { content(document)?.xml }

    /// The same, with the relationships the body names (the writer's `rIdLink<n>` hyperlinks): the throwaway file's ids mean
    /// nothing in the real one, so the caller keeps them as the box's own relationships, which a save renumbers.
    static func content(_ paragraphs: [RichParagraph]) -> (xml: String, rels: [KeptRel])? { content(RichDocument(paragraphs: paragraphs)) }

    static func content(_ document: RichDocument) -> (xml: String, rels: [KeptRel])? {
        guard let c = contentAndMedia(document) else { return nil }
        // (Without the picture files beside them, a new picture's relationships would name parts the real file lacks.)
        return (c.xml, c.rels.filter { !$0.id.hasPrefix("rIdBoxImage") })
    }

    /// The same, with the files of the pictures put into the box here (relationship target, bytes): the throwaway file holds
    /// them, so the caller must carry them into the real one (`RichDocumentController.keepBoxMedia`).
    static func contentAndMedia(_ document: RichDocument) -> (xml: String, rels: [KeptRel], media: [(target: String, data: Data)])? {
        var document = document
        if document.paragraphs.isEmpty { document.paragraphs = [RichParagraph(text: "")] }
        guard let data = try? DocxFormat.write(document, pageSetup: .letter),
              let entries = try? Zip.read(data), let e = entries.first(where: { $0.name == "word/document.xml" }) else { return nil }
        let xml = String(decoding: e.data, as: UTF8.self)
        guard let body = xml.rangeOfSubstring("<w:body>"),
              let end = xml.rangeOfSubstring("<w:sectPr", in: body.upperBound ..< xml.endIndex) ?? xml.rangeOfSubstring("</w:body>") else { return nil }
        var inner = String(xml[body.upperBound ..< end.lowerBound])
        var rels: [KeptRel] = []
        var media: [(target: String, data: Data)] = []
        if let r = entries.first(where: { $0.name == "word/_rels/document.xml.rels" }) {
            let text = String(decoding: r.data, as: UTF8.self)
            var from = text.startIndex
            while let a = text.rangeOfSubstring("<Relationship ", in: from ..< text.endIndex) {
                let close = text.rangeOfSubstring(">", in: a.upperBound ..< text.endIndex)?.upperBound ?? text.endIndex
                let tag = String(text[a.lowerBound ..< close])
                from = close
                func attr(_ n: String) -> String? {
                    guard let s = tag.rangeOfSubstring(" \(n)=\""), let q = tag.rangeOfSubstring("\"", in: s.upperBound ..< tag.endIndex) else { return nil }
                    return String(tag[s.upperBound ..< q.lowerBound])
                }
                if let id = attr("Id"), id.hasPrefix("rIdImage"), inner.containsSubstring("\"\(id)\""), let target = attr("Target"),
                   let file = entries.first(where: { $0.name == "word/" + target }) {
                    // A picture put in here: its file rides along under a box-own id.
                    let own = "rIdBox" + id.dropFirst(3)
                    inner = inner.replacingAll("\"\(id)\"", with: "\"\(own)\"")
                    rels.append(KeptRel(id: own, type: attr("Type") ?? "", target: target, external: false))
                    media.append((target, file.data))
                } else if let id = attr("Id"), (id.hasPrefix("rIdLink") || id.hasPrefix("rIdKept")), inner.containsSubstring("\"\(id)\""), let target = attr("Target") {
                    // (The file's text is escaped; the writer escapes it again when it keeps the relationship.)
                    let plain = target.replacingAll("&quot;", with: "\"").replacingAll("&lt;", with: "<").replacingAll("&gt;", with: ">").replacingAll("&amp;", with: "&")
                    var id = id
                    if id.hasPrefix("rIdKept") {
                        // (A save renumbers kept ids one after another, so a name that is itself a later id would be renamed twice.)
                        let own = "rIdBox" + id.dropFirst(4)
                        inner = inner.replacingAll("\"\(id)\"", with: "\"\(own)\""); id = own
                    }
                    rels.append(KeptRel(id: id, type: attr("Type") ?? "", target: plain, external: tag.containsSubstring("TargetMode=\"External\"")))
                }
            }
        }
        return (inner, rels, media)
    }
}
