// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-OB-4: a floating picture groups with a shape as Word groups them (`pic:pic` inside the `wpg:wgp`), and its picture file
/// goes along through the group, a save, a child's move and the ungroup.
final class GroupPictureTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    /// A document whose second paragraph holds a picture floating square on the page, 100pt in and 120pt down, 100 x 50.
    private func pictureOnThePage() throws -> RichDocument {
        let base = try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "text"), RichParagraph(image: ImageAttachment(data: png, width: 100, height: 50))]), pageSetup: .letter)
        var entries = try Zip.read(base)
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let start = try XCTUnwrap(xml.rangeOfSubstring("<w:drawing>")), end = try XCTUnwrap(xml.rangeOfSubstring("</w:drawing>"))
        let embed = try XCTUnwrap(xml.rangeOfSubstring("r:embed=\""))
        let id = String(xml[embed.upperBound...].prefix { $0 != "\"" })
        let drawing = "<w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"114300\" distR=\"114300\" simplePos=\"0\" relativeHeight=\"1\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">"
            + "<wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"page\"><wp:posOffset>1270000</wp:posOffset></wp:positionH>"
            + "<wp:positionV relativeFrom=\"page\"><wp:posOffset>1524000</wp:posOffset></wp:positionV><wp:extent cx=\"1270000\" cy=\"635000\"/>"
            + "<wp:wrapSquare wrapText=\"bothSides\"/><wp:docPr id=\"5\" name=\"Picture 5\"/>"
            + "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
            + "<pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:nvPicPr><pic:cNvPr id=\"0\" name=\"p\"/><pic:cNvPicPr/></pic:nvPicPr>"
            + "<pic:blipFill><a:blip r:embed=\"\(id)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
            + "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"1270000\" cy=\"635000\"/></a:xfrm><a:prstGeom prst=\"rect\"/></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:anchor>"
        xml.replaceSubrange(start.lowerBound ..< end.lowerBound, with: drawing)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        return try DocxFormat.read(try Zip.write(entries)).document
    }

    /// The picture file every picture in `doc`'s saved copy names, by relationship, as the package holds it.
    private func savedPictureFiles(_ doc: RichDocument) throws -> [Data] {
        let entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let xml = String(decoding: try XCTUnwrap(entries.first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        let rels = String(decoding: try XCTUnwrap(entries.first { $0.name == "word/_rels/document.xml.rels" }).data, as: UTF8.self)
        var out: [Data] = []
        var rest = Substring(xml)
        while let a = rest.rangeOfSubstring("r:embed=\""), let q = rest.rangeOfSubstring("\"", in: a.upperBound ..< rest.endIndex) {
            let id = String(rest[a.upperBound ..< q.lowerBound])
            rest = rest[q.upperBound...]
            let r = try XCTUnwrap(rels.rangeOfSubstring("Id=\"\(id)\""), "relationship \(id) is written")
            let t = try XCTUnwrap(rels.rangeOfSubstring("Target=\"", in: r.upperBound ..< rels.endIndex))
            let target = String(rels[t.upperBound...].prefix { $0 != "\"" })
            out.append(try XCTUnwrap(entries.first { $0.name == "word/" + target }, "part \(target) is written").data)
        }
        return out
    }

    func testAPictureGroupsWithAShapeAndKeepsItsFileThroughSaveMoveAndUngroup() throws {
        let c = RichDocumentController(document: try pictureOnThePage())
        let pi = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.float != nil })
        XCTAssertTrue(ShapeGroups.isGroupable(try XCTUnwrap(c.document.paragraphs[pi].image)), "a floating picture on the page groups")
        c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: "ellipse", width: w, height: h, number: TextBoxInsert.nextShapeNumber(in: c.document), page: (x, y)) }
        XCTAssertTrue(c.placePendingShape(x: 260, y: 140, width: 80, height: 60, at: RichPosition(paragraph: 0, offset: 0)))
        let members = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].image?.float != nil }
        XCTAssertEqual(members.count, 2)
        let images = members.compactMap { c.document.paragraphs[$0].image }
        let group = try XCTUnwrap(ShapeGroups.group(images, number: 9, parts: c.document.keptParts))
        let xml = try XCTUnwrap(group.sourceXML)
        XCTAssertTrue(xml.containsSubstring("<pic:pic") && xml.containsSubstring("<wps:wsp"), "both members are in the group")
        XCTAssertTrue(xml.containsSubstring("name=\"Picture 5\""), "the picture keeps its name inside the group")
        XCTAssertTrue(group.sourceRels.contains { $0.type.hasSuffix("/image") }, "the group names the picture's file")
        // The group stands round both: the picture's corner (100, 120) to the ellipse's far corner (340, 200).
        XCTAssertEqual(group.float?.x ?? -1, 100, accuracy: 0.01)
        XCTAssertEqual(group.float?.y ?? -1, 120, accuracy: 0.01)
        XCTAssertEqual(group.width, 240, accuracy: 0.01)
        XCTAssertEqual(group.height, 80, accuracy: 0.01)
        c.selectImage(at: members[0])
        c.toggleShapePick(at: members[1])
        XCTAssertTrue(c.replaceImageParagraphs(c.pickedShapeIndexes, with: [group]))
        XCTAssertEqual(try savedPictureFiles(c.document), [png], "the saved group's picture points at its file")
        if let path = ProcessInfo.processInfo.environment["GROUP_PICTURE_LAB"] {
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: path))
        }

        // Reopened, the picture child moves; its file stays named.
        let back = RichDocumentController(document: try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document)
        let gi = try XCTUnwrap(back.document.paragraphs.firstIndex { $0.image?.sourceXML?.containsSubstring("<wpg:wgp") == true })
        let reread = try XCTUnwrap(back.document.paragraphs[gi].image)
        XCTAssertTrue(ShapeGroups.isGroup(reread), "a group holding a picture can be taken apart")
        let gx = try XCTUnwrap(reread.sourceXML)
        let pk = try XCTUnwrap(gx.rangeOfSubstring("<pic:pic")).lowerBound < (try XCTUnwrap(gx.rangeOfSubstring("<wps:wsp")).lowerBound) ? 0 : 1
        let moved = try XCTUnwrap(ShapeGroups.editChild(reread, child: pk, .move(dx: -127000, dy: 0), parts: back.document.keptParts))
        XCTAssertEqual(moved.float?.x ?? -1, 90, accuracy: 0.01, "the group grows to hold the moved picture")
        XCTAssertTrue(back.replaceImageParagraphs([gi], with: [moved]))
        XCTAssertEqual(try savedPictureFiles(back.document), [png])

        // Ungrouped, the picture is a floating picture again, with its name and its file.
        let parts = try XCTUnwrap(ShapeGroups.ungroup(moved, number: 20, parts: back.document.keptParts))
        XCTAssertEqual(parts.count, 2)
        let picture = try XCTUnwrap(parts.first { $0.sourceXML?.containsSubstring("<pic:pic") == true })
        XCTAssertEqual(picture.data, png, "the picture draws from its file")
        XCTAssertTrue(picture.sourceXML?.containsSubstring("name=\"Picture 5\"") == true)
        XCTAssertEqual(picture.float?.x ?? -1, 90, accuracy: 0.01)
        XCTAssertEqual(picture.float?.y ?? -1, 120, accuracy: 0.01)
        XCTAssertTrue(back.replaceImageParagraphs([gi], with: parts))
        XCTAssertEqual(try savedPictureFiles(back.document), [png])
        // A picture child has no words to type: no text proxy for it.
        XCTAssertNil(ShapeGroups.textProxy(reread, child: pk))
        XCTAssertNotNil(ShapeGroups.textProxy(reread, child: 1 - pk), "the shape beside it still takes words")
    }

    func testALinkedPictureDoesNotGroup() throws {
        var doc = try pictureOnThePage()
        let pi = try XCTUnwrap(doc.paragraphs.firstIndex { $0.image?.float != nil })
        var image = try XCTUnwrap(doc.paragraphs[pi].image)
        image.sourceXML = image.sourceXML?.replacingAll("r:embed=", with: "r:link=")
        doc.paragraphs[pi].image = image
        XCTAssertFalse(ShapeGroups.isGroupable(image), "a picture whose file is outside the package is left alone")
    }
}
