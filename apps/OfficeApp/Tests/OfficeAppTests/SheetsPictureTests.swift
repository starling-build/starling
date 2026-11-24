// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsPictureTests: XCTestCase {
    /// A 1 × 1 PNG.
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private func pictures(_ ws: Worksheet) -> [SheetDrawing] {
        ws.drawings.filter { if case .picture = $0.kind { return true } else { return false } }
    }

    func testInsertPictureAtTheActiveCellIsOneUndoStep() throws {
        let c = WorkbookController()
        c.select(CellAddress("C3")!)
        XCTAssertTrue(c.insertPicture(png, name: "dot.png", width: 96, height: 48))
        let d = try XCTUnwrap(pictures(c.sheet).first)
        XCTAssertEqual(d.name, "Picture 1")
        XCTAssertEqual(c.selectedDrawing, 0)
        let f = c.sheet.frame(d.anchor)
        XCTAssertEqual(f.x, 2 * Worksheet.defaultColWidth, accuracy: 0.01)
        XCTAssertEqual(f.width, 96, accuracy: 0.01)
        XCTAssertEqual(f.height, 48, accuracy: 0.01)
        c.undo()
        XCTAssertTrue(c.sheet.drawings.isEmpty)
        c.redo()
        XCTAssertEqual(pictures(c.sheet).count, 1)
    }

    func testNotAPictureIsRefused() {
        let c = WorkbookController()
        XCTAssertFalse(c.insertPicture(Data("hello".utf8), name: "x.txt", width: 10, height: 10))
        XCTAssertTrue(c.sheet.drawings.isEmpty)
    }

    func testPictureAndItsAnchorSurviveSaveAndReopen() throws {
        let c = WorkbookController()
        c.select(CellAddress("B2")!)
        XCTAssertTrue(c.insertPicture(png, name: "dot.png", width: 120, height: 60))
        let before = c.sheet.frame(c.sheet.drawings[0].anchor)
        let data = try Xlsx.write(c.book)

        let back = try Xlsx.read(data)
        let again = WorkbookController()
        again.load(back)
        let d = try XCTUnwrap(pictures(again.sheet).first)
        guard case .picture(_, let bytes) = d.kind else { return XCTFail("not a picture") }
        XCTAssertEqual(bytes, png)
        let after = again.sheet.frame(d.anchor)
        XCTAssertEqual(after.x, before.x, accuracy: 0.5)
        XCTAssertEqual(after.y, before.y, accuracy: 0.5)
        XCTAssertEqual(after.width, before.width, accuracy: 0.5)
        XCTAssertEqual(after.height, before.height, accuracy: 0.5)

        // And once more through the writer: the part is the file's own now.
        let third = WorkbookController()
        third.load(try Xlsx.read(try Xlsx.write(again.book)))
        XCTAssertEqual(pictures(third.sheet).count, 1)
    }
}
