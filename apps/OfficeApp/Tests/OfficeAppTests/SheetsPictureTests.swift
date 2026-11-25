// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-IL: Insert → Picture in Sheets (place, move, resize, delete, alt text, save as a drawing with its media part).

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsPictureTests: XCTestCase {
    /// A 1×1 PNG.
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private func book() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "S")]))
        return c
    }

    private func pictures(_ c: WorkbookController) -> Int {
        c.sheet.drawings.filter { if case .picture = $0.kind { return true }; return false }.count
    }

    func testInsertSelectsAndUndoes() {
        let c = book()
        XCTAssertTrue(c.insertPicture(name: "a.png", data: png, width: 960, height: 720))
        XCTAssertEqual(pictures(c), 1)
        XCTAssertEqual(c.selectedDrawing, 0)
        let f = c.sheet.drawings[0].anchor
        XCTAssertEqual(c.sheet.frame(f).width, 480, accuracy: 1)   // fitted down, shape kept
        XCTAssertEqual(c.sheet.frame(f).height, 360, accuracy: 1)
        c.undo(); XCTAssertEqual(pictures(c), 0)
        c.redo(); XCTAssertEqual(pictures(c), 1)
    }

    func testNotAPictureIsRefused() {
        let c = book()
        XCTAssertFalse(c.insertPicture(name: "a.txt", data: Data("hello".utf8), width: 10, height: 10))
        XCTAssertEqual(pictures(c), 0)
    }

    func testAltMoveResizeDelete() {
        let c = book()
        c.insertPicture(name: "a.png", data: png, width: 100, height: 50)
        c.setDrawingAlt(0, "A dot")
        XCTAssertEqual(c.sheet.drawings[0].descr, "A dot")
        c.undo(); XCTAssertNil(c.sheet.drawings[0].descr)
        c.setDrawingFrame(0, x: 40, y: 30, width: 200, height: 100)
        let r = c.sheet.frame(c.sheet.drawings[0].anchor)
        XCTAssertEqual(r.x, 40, accuracy: 1); XCTAssertEqual(r.y, 30, accuracy: 1)
        XCTAssertEqual(r.width, 200, accuracy: 1)
        c.deleteDrawing(0)
        XCTAssertEqual(pictures(c), 0)
        c.undo(); XCTAssertEqual(pictures(c), 1)
    }

    func testSavesWithItsMediaPartAndAltText() throws {
        let c = book()
        c.setInputs([(CellAddress(row: 0, col: 0), "x")])
        c.insertPicture(name: "a.png", data: png, width: 100, height: 50)
        c.setDrawingAlt(0, "A dot & more")
        let out = try Xlsx.write(c.book)
        let parts = Dictionary(uniqueKeysWithValues: try Zip.read(out).map { ($0.name, $0.data) })
        XCTAssertEqual(parts["xl/media/starling-image1.png"], png)
        XCTAssertTrue(String(decoding: try XCTUnwrap(parts["[Content_Types].xml"]), as: UTF8.self).containsSubstring("Extension=\"png\""))
        let drawing = parts.first { $0.key.hasPrefix("xl/drawings/drawing") && $0.key.hasSuffix(".xml") }
        XCTAssertTrue(String(decoding: try XCTUnwrap(drawing).value, as: UTF8.self).containsSubstring("descr=\"A dot &amp; more\""))
        let back = WorkbookController(); back.load(try Xlsx.read(out))
        guard case .picture(_, let data) = back.sheet.drawings[0].kind else { return XCTFail("no picture") }
        XCTAssertEqual(data, png)
        XCTAssertEqual(back.sheet.drawings[0].descr, "A dot & more")
        // saved again unchanged: still one picture
        XCTAssertEqual(pictures(back), 1)
    }

    private func shell() -> (WidgetTester, SheetsShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "t"),
                              size: Size(1280, 800))
        ui.pump()
        return (ui, ui.state(SheetsShellState.self)!)
    }

    func testPicturesButtonAsksTheHostForAFile() {
        let (ui, _) = shell()
        var asked = false
        defer { OfficeScene.main.pictureRequested = nil }
        OfficeScene.main.pictureRequested = { _ in asked = true }
        XCTAssertTrue(ui.tap(text: "Insert")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Pictures"))
        XCTAssertTrue(asked)
    }

    func testAltTextButtonOnlyWithAPictureSelected() {
        let (ui, st) = shell()
        XCTAssertTrue(ui.tap(text: "Insert")); ui.pump()
        XCTAssertFalse(ui.has(text: "Alt Text"))
        st.wb.insertPicture(name: "a.png", data: png, width: 100, height: 50); ui.pump()
        XCTAssertTrue(ui.has(text: "Alt Text"))
        XCTAssertTrue(ui.tap(text: "Alt Text")); ui.pump()
        XCTAssertTrue(ui.has(text: "OK"))
    }
}
