// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsShapeInsertTests: XCTestCase {
    func testInsertedShapesAndTextBoxAreWrittenAndReadBack() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        let c = WorkbookController()
        c.load(try Xlsx.read(try Data(contentsOf: url)))
        let before = c.sheet.drawings.count
        XCTAssertTrue(c.insertShape(ShapePreset(rawValue: "roundRect")))
        c.setShapeText(c.sheet.drawings.count - 1, "Hello\nthere")
        XCTAssertTrue(c.insertShape(.rect, textBox: true))
        c.setShapeText(c.sheet.drawings.count - 1, "A & B")
        XCTAssertTrue(c.insertShape(ShapePreset(rawValue: "straightConnector1")))
        let anchors = c.sheet.drawings.suffix(3).map { $0.anchor }
        XCTAssertEqual(Set(anchors.map { "\($0)" }).count, 3, "three shapes inserted at one cell sit apart")
        let data = try Xlsx.write(c.book)
        let drawing = try Zip.read(data).first { $0.name.hasPrefix("xl/drawings/drawing") && !$0.name.contains("_rels")
            && String(decoding: $0.data, as: UTF8.self).containsSubstring("roundRect") }
        let xml = String(decoding: try XCTUnwrap(drawing).data, as: UTF8.self)
        XCTAssertTrue(xml.contains("prst=\"roundRect\""))
        XCTAssertTrue(xml.contains("txBox=\"1\""))
        XCTAssertTrue(xml.contains("<xdr:cxnSp"))
        XCTAssertTrue(xml.contains("<a:tailEnd type=\"triangle\"/>"))
        XCTAssertTrue(xml.contains("A &amp; B"))
        let back = WorkbookController()
        back.load(try Xlsx.read(data))
        XCTAssertEqual(back.sheet.drawings.count, before + 3)
        let texts = back.sheet.drawings.compactMap { d -> String? in if case .shape(let s) = d.kind { return s.plainText }; return nil }
        XCTAssertTrue(texts.contains("Hello\nthere"))
        XCTAssertTrue(texts.contains("A & B"))
        if let dir = ProcessInfo.processInfo.environment["XCHECK_DIR"] {
            try data.write(to: URL(fileURLWithPath: "\(dir)/shapes-insert.xlsx"))
        }
    }
}
