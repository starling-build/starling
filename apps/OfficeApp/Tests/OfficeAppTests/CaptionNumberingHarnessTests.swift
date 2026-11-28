// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-FD-3: Insert Caption's "Include chapter number", and References > Insert Table of Figures, through the dialogs.
final class CaptionNumberingHarnessTests: XCTestCase {
    private func shell(numbered: Bool) -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"),
                              size: Size(1440, 932))
        let session = ui.state(OfficeShellState.self)!.session
        var h = RichParagraph(text: "Start")
        h.style.heading = 1
        if numbered { h.style.list = .numbered; h.style.listId = "7" }
        session.controller.load(RichDocument(paragraphs: [h, RichParagraph(text: "A picture")]))
        session.controller.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        ui.pump()
        return (ui, session)
    }

    func testIncludeChapterNumberPutsTheHeadingNumberFirst() {
        let (ui, session) = shell(numbered: true)
        session.onCaptionDialog?(); ui.pump()
        XCTAssertTrue(ui.tap(id: "cap-chapter")); ui.pump()
        XCTAssertTrue(ui.texts().contains("Figure 1-1"), "the preview shows the chapter")
        XCTAssertEqual(ui.overflowingFlexes(), 0, "the chapter options fit")
        XCTAssertTrue(ui.tap(id: "cap-sep-period")); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertEqual(session.controller.document.paragraphs[2].text, "Figure 1.1")
    }

    func testAnUnnumberedHeadingIsRefused() {
        let (ui, session) = shell(numbered: false)
        session.onCaptionDialog?(); ui.pump()
        XCTAssertTrue(ui.tap(id: "cap-chapter")); ui.pump()
        XCTAssertNotNil(ui.centre(id: "cap-chapter-refusal"))
        ui.press(.enter); ui.pump()
        XCTAssertEqual(session.controller.document.paragraphs.count, 2, "nothing inserted")
    }

    func testInsertTableOfFiguresListsTheCaptions() {
        let (ui, session) = shell(numbered: false)
        let c = session.controller
        c.insertCaption(label: "Figure", title: ": A cat", place: .below, excludeLabel: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        session.onFiguresDialog?(); ui.pump()
        XCTAssertTrue(ui.texts().contains("Table of Figures"))
        ui.press(.enter); ui.pump()
        let start = c.document.paragraphs.firstIndex { $0.style.contentsStart != nil }
        XCTAssertNotNil(start)
        XCTAssertEqual(c.document.paragraphs[start!].style.contentsStart, "TOC \\h \\z \\c \"Figure\"")
        XCTAssertTrue(c.document.paragraphs[start!].text.hasPrefix("Figure 1: A cat\t"))
    }
}
