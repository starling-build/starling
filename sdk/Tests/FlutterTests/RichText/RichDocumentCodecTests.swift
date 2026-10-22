// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import Flutter
import FlutterSwiftBridge

final class RichDocumentCodecTests: XCTestCase {
    private func sample() -> RichDocument {
        var a = RichParagraph(text: "Heading one", style: RichParagraphStyle(alignment: .center))
        a.applyStyle(0 ..< 7) { $0.bold = true; $0.color = Color(0xFF336699) }
        a.bookmarks = ["_Toc1"]
        var b = RichParagraph(text: "Body with a link and 中文。")
        b.applyStyle(5 ..< 9) { $0.italic = true; $0.link = "https://example.com/x?y=1" }
        var c = RichParagraph(text: "cell", style: .cell)
        c.cell = CellRef(table: "t1", row: 0, column: 0, fill: Color(0xFFEEEEEE))
        var doc = RichDocument(paragraphs: [a, b, c, RichParagraph()])
        doc.header = "H {PAGE}"
        doc.tableColumns["t1"] = [120, 240.5]
        doc.tableStyles["t1"] = TableStyle(borders: true, headerRow: true)
        doc.listFormats["L1"] = [0: ListLevelFormat(text: "%1)", format: .lowerRoman)]
        doc.keptParts["word/footnotes.xml"] = Data([1, 2, 3, 0, 255])
        doc.defaultTabStop = 42
        doc.keptSettings["w:autoHyphenation"] = "<w:autoHyphenation/>"
        return doc
    }

    func testRoundTripIsExact() throws {
        var doc = sample()
        doc.assignParagraphIDs()
        let data = try RichDocumentEnvelope.encode(doc)
        let back = try RichDocumentEnvelope.decode(data)
        XCTAssertEqual(back, doc)
        // And stable: the same document encodes to the same bytes.
        XCTAssertEqual(try RichDocumentEnvelope.encode(back), data)
    }

    func testIDsAssignedOnceAndUnique() {
        var doc = sample()
        XCTAssertFalse(doc.paragraphIDsAreUnique)
        doc.assignParagraphIDs()
        XCTAssertTrue(doc.paragraphIDsAreUnique)
        let ids = doc.paragraphs.map(\.id)
        doc.assignParagraphIDs()
        XCTAssertEqual(doc.paragraphs.map(\.id), ids, "a second pass changes nothing")
        XCTAssertTrue(ids.allSatisfy { $0 != 0 && $0 < 0x8000_0000 })
    }

    func testSplitKeepsHeadIDAndJoinKeepsHead() {
        var p = RichParagraph(text: "abcdef")
        p.id = 0x1234_5678
        let tail = p.split(at: 3)
        XCTAssertEqual(p.id, 0x1234_5678)
        XCTAssertNotEqual(tail.id, 0)
        XCTAssertNotEqual(tail.id, p.id)
        var head = p
        head.append(tail)
        XCTAssertEqual(head.id, 0x1234_5678)
        // A paragraph that never had an id does not invent one on split.
        var q = RichParagraph(text: "xy")
        XCTAssertEqual(q.split(at: 1).id, 0)
    }

    func testOpaqueColourSurvives() throws {
        // Above Int32.max: the decoder must not go through Int (32 bits on wasm).
        var p = RichParagraph(text: "x")
        p.applyStyle(0 ..< 1) { $0.color = Color(0xFFFFFFFF) }
        let doc = RichDocument(paragraphs: [p])
        let back = try RichDocumentEnvelope.decode(try RichDocumentEnvelope.encode(doc))
        XCTAssertEqual(back.paragraphs[0].runs[0].style.color?.toARGB32(), 0xFFFFFFFF)
    }

    func testUnknownSchemaIsRefused() throws {
        let data = Data(#"{"schema":99,"document":{"paragraphs":[]}}"#.utf8)
        XCTAssertThrowsError(try RichDocumentEnvelope.decode(data))
    }
}
