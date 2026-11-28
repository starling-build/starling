// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-FD-1: Insert → Date & Time inserts text (or, ticked, a field); F9 brings fields up to date; Esc changes nothing.
final class DateTimeDialogHarnessTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        return (ui, ui.state(OfficeShellState.self)!.session)
    }

    func testEnterInsertsTheFormattedDateAndUndoes() {
        let (ui, session) = shell()
        session.onDateTimeDialog?(); ui.pump()
        ui.press(.enter); ui.pump()
        let text = session.controller.document.paragraphs[0].text
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains(","), "the long format: \(text)")
        XCTAssertTrue(session.controller.fieldSpans().isEmpty)
        session.controller.undo()
        XCTAssertEqual(session.controller.document.paragraphs[0].text, "")
    }

    /// The eleven formats scroll inside a fixed box (they used to run past it, over the check box, at 1440x932); the last
    /// one is reached by scrolling and picked by a click.
    private func clock0(_ ui: WidgetTester) -> FieldClock { (ui.state(DateTimeDialogState.self)!.widget as! DateTimeDialog).clock }

    func testFormatListScrollsInAFixedBoxWithNoOverflow() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1440, 932))
        let session = ui.state(OfficeShellState.self)!.session
        session.onDateTimeDialog?(); ui.pump()
        XCTAssertEqual(ui.overflowingFlexes(), 0)
        let label = try XCTUnwrap(ui.centre(ofText: "Available formats:"))
        let check = try XCTUnwrap(ui.centre(ofText: "Update automatically"))
        XCTAssertGreaterThan(check.dy - label.dy, DateTimeDialog.listHeight)
        XCTAssertLessThan(check.dy - label.dy, DateTimeDialog.listHeight + 60)
        let firstRow = clock0(ui).format(picture: "M/d/yyyy", english: true) ?? ""
        let before = try XCTUnwrap(ui.centre(ofText: firstRow))
        ui.scroll(at: Offset(before.dx, before.dy + 60), delta: Offset(0, 400)); ui.pump(); ui.pump()
        let clock = clock0(ui)
        let last = clock.format(picture: "HH:mm:ss", english: true) ?? ""
        // (The tester reports a text's unscrolled place, so take the scroll off it.)
        let moved = ui.state(DateTimeDialogState.self)!.listScroll.offset
        XCTAssertGreaterThan(moved, 0)
        let unscrolled = try XCTUnwrap(ui.centre(ofText: last))
        let at = Offset(unscrolled.dx, unscrolled.dy - moved)
        XCTAssertLessThan(at.dy, check.dy)
        XCTAssertGreaterThan(at.dy, label.dy)
        ui.tap(at: at); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertEqual(session.controller.document.paragraphs[0].text.filter { $0 == ":" }.count, 2)
    }

    func testEscapeInsertsNothing() {
        let (ui, session) = shell()
        session.onDateTimeDialog?(); ui.pump()
        ui.press(.escape); ui.pump()
        XCTAssertEqual(session.controller.document.paragraphs[0].text, "")
    }

    func testAutomaticInsertsAFieldThatF9Refreshes() {
        let (_, session) = shell()
        let c = session.controller
        let before = FieldClock(year: 2026, month: 11, day: 25, hour: 9, minute: 5, second: 0)
        c.insertDateTime(picture: "dddd, MMMM d, yyyy", automatic: true, clock: before)
        XCTAssertEqual(c.document.paragraphs[0].text, "Wednesday, November 25, 2026")
        XCTAssertEqual(c.fieldSpans().first?.instruction.trimmingCharacters(in: .whitespaces), "DATE \\@ \"dddd, MMMM d, yyyy\"")
        let later = FieldClock(year: 2026, month: 12, day: 3, hour: 9, minute: 5, second: 0)
        let n = c.updateFields { FieldEvaluator.evaluate($0, shown: $1, clock: later, properties: [:]) }
        XCTAssertEqual(n, 1)
        XCTAssertEqual(c.document.paragraphs[0].text, "Thursday, December 3, 2026")
        c.insertDateTime(picture: "HH:mm", automatic: true, clock: later)
        XCTAssertTrue(c.fieldSpans().last?.instruction.contains("TIME") ?? false)
    }

    func testPropertyFieldsShowTheDocumentProperties() {
        let core = Data("<?xml version=\"1.0\"?><cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>My Title</dc:title><dc:creator>Ann</dc:creator></cp:coreProperties>".utf8)
        let props = FieldEvaluator.properties(keptParts: ["docProps/core.xml": core])
        XCTAssertEqual(FieldEvaluator.evaluate(" AUTHOR ", shown: "", clock: nil, properties: props), "Ann")
        XCTAssertEqual(FieldEvaluator.evaluate("TITLE", shown: "x", clock: nil, properties: props), "My Title")
        XCTAssertNil(FieldEvaluator.evaluate("SUBJECT", shown: "x", clock: nil, properties: props))
    }
}
