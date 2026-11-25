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
    static func drawingXML(text: String?, width: Double, height: Double, id: Int = 100, preset: String = "rect", fill: String = "FFFFFF", name: String = "Text Box") -> String {
        let cx = Int(width * 12700), cy = Int(height * 12700)
        let esc = DocxFormat._esc(text ?? "")
        return "<w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"114300\" distR=\"114300\" simplePos=\"0\" relativeHeight=\"251659264\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">"
            + "<wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"column\"><wp:posOffset>228600</wp:posOffset></wp:positionH>"
            + "<wp:positionV relativeFrom=\"paragraph\"><wp:posOffset>228600</wp:posOffset></wp:positionV>"
            + "<wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/><wp:wrapSquare wrapText=\"bothSides\"/>"
            + "<wp:docPr id=\"\(id)\" name=\"\(name) \(id)\"/><wp:cNvGraphicFramePr/>"
            + "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\">"
            + "<wps:wsp xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:cNvSpPr\(text == nil ? "" : " txBox=\"1\"")/>"
            + "<wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"\(preset)\"><a:avLst/></a:prstGeom>"
            + "<a:solidFill><a:srgbClr val=\"\(fill)\"/></a:solidFill><a:ln w=\"9525\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill></a:ln></wps:spPr>"
            + (text == nil ? "" : "<wps:txbx><w:txbxContent><w:p><w:r><w:t xml:space=\"preserve\">\(esc)</w:t></w:r></w:p></w:txbxContent></wps:txbx>")
            + "<wps:bodyPr rot=\"0\" vert=\"horz\" wrap=\"square\" lIns=\"91440\" tIns=\"45720\" rIns=\"91440\" bIns=\"45720\" anchor=\"t\" anchorCtr=\"0\">" + (text != nil ? "<a:spAutoFit/>" : "<a:noAutofit/>") + "</wps:bodyPr>"
            + "</wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing>"
    }

    /// A new text box as the picture-like object the document holds, or nil if the reader does not take it as one.
    static func make(text: String = "Text box", width: Double = 144, height: Double = 54) -> ImageAttachment? {
        read(drawingXML(text: text, width: width, height: height)) { $0.textBox != nil }
    }

    /// A new filled shape (`rect`, `roundRect`, `ellipse`, `triangle`, `rightArrow`…), without text.
    static func makeShape(preset: String, width: Double = 96, height: Double = 72) -> ImageAttachment? {
        read(drawingXML(text: nil, width: width, height: height, preset: preset, fill: "4472C4", name: "Shape")) { _ in true }
    }

    private static func read(_ drawing: String, _ wanted: (ImageAttachment) -> Bool) -> ImageAttachment? {
        guard let base = try? DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter),
              var entries = try? Zip.read(base), let di = entries.firstIndex(where: { $0.name == "word/document.xml" }) else { return nil }
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        guard let r = xml.rangeOfSubstring("<w:r>"), let end = xml.rangeOfSubstring("</w:r>") else { return nil }
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
        guard let data = try? DocxFormat.write(RichDocument(paragraphs: paragraphs.isEmpty ? [RichParagraph(text: "")] : paragraphs), pageSetup: .letter),
              let entries = try? Zip.read(data), let e = entries.first(where: { $0.name == "word/document.xml" }) else { return nil }
        let xml = String(decoding: e.data, as: UTF8.self)
        guard let body = xml.rangeOfSubstring("<w:body>"),
              let end = xml.rangeOfSubstring("<w:sectPr", in: body.upperBound ..< xml.endIndex) ?? xml.rangeOfSubstring("</w:body>") else { return nil }
        return String(xml[body.upperBound ..< end.lowerBound])
    }
}
