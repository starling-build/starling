// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// U-SH-5: the File page covers the ribbon, the document and the status bar, so a screen reader reads only the
/// page: nothing it covers (Paste, Bold, the tabs, the zoom) stays in the tree to be read or focused.
final class FileTabSemanticsTests: XCTestCase {
    private func app(_ home: Widget) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Size(1440, 932))
        ui.pump()
        return ui
    }

    private func check(_ name: String, _ ui: WidgetTester, file: StaticString = #filePath, line: UInt = #line) {
        func reads(_ word: String) -> Bool { ui.semantics().contains { $0.label.containsSubstring(word) } }
        XCTAssertTrue(reads("Paste"), "\(name): the ribbon is read before the File tab opens", file: file, line: line)
        ui.tap(text: "File"); ui.pump()
        var page: Element?
        for e in ui.elements() where e.widget is Backstage { page = e; break }
        guard let page else { return XCTFail("\(name): no File page", file: file, line: line) }
        let onPage = SemanticsSnapshot.build(from: page).map(\.label)
        let read = ui.semantics().map(\.label)
        XCTAssertGreaterThan(onPage.count, 5, file: file, line: line)
        XCTAssertEqual(read, onPage, "\(name): the tree under the File page holds only File-page nodes", file: file, line: line)
        for covered in ["Paste", "Bold", "Insert"] {
            XCTAssertFalse(reads(covered), "\(name): \(covered) is read through the File page", file: file, line: line)
        }
        // Closing the page gives the ribbon back.
        ui.press(.escape)
        XCTAssertTrue(reads("Paste"), "\(name): the ribbon is back after Escape", file: file, line: line)
    }

    /// The framework rule the page relies on: BlockSemantics drops what was painted before it under the same
    /// parent, keeps its own subtree, and does nothing when not blocking.
    func testBlockSemanticsDropsWhatItCovers() {
        func read(blocking: Bool) -> [String] {
            let ui = WidgetTester(Directionality(textDirection: .ltr, child: Stack(children: [
                Semantics(label: "under", child: SizedBox(width: 10, height: 10)),
                Positioned(left: 0, top: 0, child: BlockSemantics(blocking: blocking, child:
                    Semantics(label: "over", child: SizedBox(width: 10, height: 10)))),
                Semantics(label: "after", child: SizedBox(width: 10, height: 10)),
            ])), size: Size(100, 100))
            ui.pump()
            return ui.semantics().map(\.label)
        }
        XCTAssertEqual(read(blocking: true), ["over", "after"])
        XCTAssertEqual(read(blocking: false), ["under", "over", "after"])
    }

    func testWriter() { check("Writer", app(OfficeShell(initialPath: nil, startBlank: true))) }
    func testSlides() { check("Slides", app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))) }
    func testSheets() { check("Sheets", app(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))) }
}
