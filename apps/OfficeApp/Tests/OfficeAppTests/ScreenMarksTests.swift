// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// The harness side of the driver's `marks` command: the same list, for the same window size, so a Mac run's
/// marks file and this one can be compared line by line. SCREEN_MARKS_DIR=dir writes each app's list there.
final class ScreenMarksTests: XCTestCase {
    private static let size = Size(1440, 932)

    private func marks(_ name: String, _ home: Widget) -> [String] {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Self.size)
        ui.pump()
        let lines = ScreenMarks.lines(root: ui.elements().first, view: Self.size)
        if let dir = ProcessInfo.processInfo.environment["SCREEN_MARKS_DIR"], !dir.isEmpty {
            FileManager.default.createFile(atPath: dir + "/\(name)-1440x932.txt", contents: Data((lines.joined(separator: "\n") + "\n").utf8))
        }
        return lines
    }

    private func centre(_ lines: [String], _ kind: String, _ label: String) -> (Double, Double)? {
        for l in lines {
            let f = l.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, f[0] == kind, f[1] == label else { continue }
            let p = f[2].split(separator: " ").compactMap { Double($0) }
            return (p[0], p[1])
        }
        return nil
    }

    func testWriterMarksMatchTheTesterAndTheView() throws {
        let lines = marks("writer", OfficeShell(initialPath: nil, startBlank: true))
        XCTAssertEqual(lines.first, "view\t1440 932")
        let home = try XCTUnwrap(centre(lines, "text", "Home"))
        XCTAssertEqual(home.1, 81, accuracy: 1, "the tab row, where mac-ipad measures it on the Mac")
        XCTAssertNotNil(centre(lines, "tip", "Zoom In"), "the status bar is listed")
        XCTAssertGreaterThan(try XCTUnwrap(centre(lines, "tip", "Zoom In")).1, 900, "the status bar sits at the bottom")
    }

    /// The Review tab's controls, where the Mac review script clicks them.
    func testWriterReviewTabMarks() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true),
                                        title: "Test"), size: Self.size)
        ui.pump()
        let tab = try XCTUnwrap(centre(ScreenMarks.lines(root: ui.elements().first, view: Self.size), "text", "Review"))
        ui.tap(at: Offset(tab.0, tab.1))
        ui.pump()
        let lines = ScreenMarks.lines(root: ui.elements().first, view: Self.size)
        if let dir = ProcessInfo.processInfo.environment["SCREEN_MARKS_DIR"], !dir.isEmpty {
            FileManager.default.createFile(atPath: dir + "/writer-review-1440x932.txt", contents: Data((lines.joined(separator: "\n") + "\n").utf8))
        }
        XCTAssertNotNil(centre(lines, "tip", "Show Comments") ?? centre(lines, "text", "Show Comments"), "the Comments group's toggle is listed")
    }

    func testSlidesAndSheetsMarks() {
        XCTAssertNotNil(centre(marks("slides", SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in })), "text", "Home"))
        XCTAssertNotNil(centre(marks("sheets", SheetsShell(initialPath: nil, onSwitch: { _, _ in })), "text", "Home"))
    }

    /// A lab's marks with a file open: SCREEN_MARKS_FILE=doc writes "file-1440x932.txt" into SCREEN_MARKS_DIR.
    func testFileMarks() throws {
        guard let path = ProcessInfo.processInfo.environment["SCREEN_MARKS_FILE"] else { throw XCTSkip("no SCREEN_MARKS_FILE") }
        _ = marks("file", OfficeShell(initialPath: path, startBlank: false))
    }

    /// SCREEN_MARKS_CHART=doc (a file that opens with its chart selected): the marks on Chart Design, then with the
    /// chart's data open, for a Mac script.
    func testChartMarks() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SCREEN_MARKS_CHART"], let dir = env["SCREEN_MARKS_DIR"] else { throw XCTSkip("no SCREEN_MARKS_CHART") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: path), title: "Test"),
                              size: Self.size)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Chart Design")); ui.pump()
        func marks(_ head: String) -> String {
            "--- " + head + "\n" + ScreenMarks.lines(root: ui.elements().first, view: Self.size).joined(separator: "\n") + "\n"
        }
        var out = marks("chart design")
        XCTAssertTrue(ui.tap(text: "Axis Titles")); ui.pump()
        // Each menu: its marks open, then the entry the Mac script applies.
        for (menu, entry) in [("Legend Position", "Top"), ("Grouping", "Stacked"), ("Quick Layout", "Layout 4"),
                              ("Change Chart Type", "Bar")] {
            XCTAssertTrue(ui.tap(text: menu), menu); ui.pump()
            out += marks(menu)
            // The menu is the last layer, so its entry is the last text that names it.
            let box = ui.elements().last { ($0.widget as? Text)?.data?.hasPrefix(entry) == true }?.findRenderObject() as? RenderBox
            XCTAssertNotNil(box, entry)
            if let box { ui.tap(at: box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2))); ui.pump() }
            out += marks("after " + entry)
        }
        XCTAssertTrue(ui.tap(text: "Edit Data")); ui.pump()
        out += marks("edit data")
        FileManager.default.createFile(atPath: dir + "/chart-1440x932.txt", contents: Data(out.utf8))
    }

    /// Insert > Chart in Word (the Mac script test/lab/wobins-mac): the Insert tab, the Chart menu, and the new chart with
    /// its data pane open. SCREEN_MARKS_INSERT_CHART is a document to insert into (lab/wobins/i0-text.docx).
    func testInsertChartMarks() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SCREEN_MARKS_INSERT_CHART"], let dir = env["SCREEN_MARKS_DIR"] else { throw XCTSkip("no SCREEN_MARKS_INSERT_CHART") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: path), title: "Test"),
                              size: Self.size)
        ui.pump()
        func marks(_ head: String) -> String {
            "--- " + head + "\n" + ScreenMarks.lines(root: ui.elements().first, view: Self.size).joined(separator: "\n") + "\n"
        }
        XCTAssertTrue(ui.tap(text: "Insert")); ui.pump()
        var out = marks("insert")
        XCTAssertTrue(ui.tap(text: "Chart")); ui.pump()
        out += marks("chart menu")
        let box = ui.elements().last { ($0.widget as? Text)?.data == "Column" }?.findRenderObject() as? RenderBox
        XCTAssertNotNil(box, "Column")
        if let box { ui.tap(at: box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2))); ui.pump() }
        out += marks("after Column")
        FileManager.default.createFile(atPath: dir + "/insert-chart-1440x932.txt", contents: Data(out.utf8))
    }
}
