// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-PA-1c: the ruler's markers and tab stops are live.
final class RulerTests: XCTestCase {
    private let g = RulerGeometry(setup: .letter, px: 1, pad: 24, width: 800)

    func testMarkersAndStopsAreGrabbed() {
        var s = RichParagraphStyle()
        s.indentLeft = 36; s.firstLineIndent = -18
        s.tabStops = [TabStop(position: 144, alignment: .right)]
        let top = RulerGeometry.top
        XCTAssertEqual(g.target(at: Offset(g.x(18), top + 2), style: s), .firstLine)
        XCTAssertEqual(g.target(at: Offset(g.x(36), top + 12), style: s), .leftIndent)
        XCTAssertEqual(g.target(at: Offset(g.x(s.indentRight + g.setup.contentWidth), top + 12), style: s), .rightIndent)
        XCTAssertEqual(g.target(at: Offset(g.x(144), g.mid), style: s), .tab(0))
        XCTAssertEqual(g.target(at: Offset(g.x(200), g.mid), style: s), .newTab)
        XCTAssertNil(g.target(at: Offset(g.x(200), 40), style: s), "below the ruler")
        XCTAssertEqual(g.target(at: Offset(10, g.mid), style: s), .kindBox)
    }

    func testDragsMeanOneFormat() {
        var s = RichParagraphStyle()
        s.indentLeft = 36; s.firstLineIndent = -18
        s.tabStops = [TabStop(position: 144, alignment: .right), TabStop(position: 216, alignment: .left)]
        // First-line marker to 54 pt: first line sits at 54, left indent is untouched.
        XCTAssertEqual(g.format(.firstLine, to: Offset(g.x(54), 6), style: s, kind: .left)?.firstLineIndent, 18)
        // Left-indent marker to 72: the first line stays where it was (18 pt), so it hangs by 54.
        let f = g.format(.leftIndent, to: Offset(g.x(72), 16), style: s, kind: .left)
        XCTAssertEqual(f?.indentLeft, 72); XCTAssertEqual(f?.firstLineIndent, -54)
        // Never past the left margin.
        XCTAssertEqual(g.format(.leftIndent, to: Offset(g.x(-30), 16), style: s, kind: .left)?.indentLeft, 0)
        // Right indent 1 inch from the right edge.
        XCTAssertEqual(g.format(.rightIndent, to: Offset(g.x(g.setup.contentWidth - 72), 16), style: s, kind: .left)?.indentRight, 72)
        // A stop moved, one dragged off the ruler, and a new one.
        XCTAssertEqual(g.format(.tab(1), to: Offset(g.x(252), g.mid), style: s, kind: .left)?.tabStops?.map(\.position), [144, 252])
        XCTAssertEqual(g.format(.tab(0), to: Offset(g.x(144), 80), style: s, kind: .left)?.tabStops?.map(\.position), [216])
        let n = g.format(.newTab, to: Offset(g.x(100), g.mid), style: s, kind: .center)?.tabStops
        XCTAssertEqual(n?.map(\.position), [99, 144, 216]); XCTAssertEqual(n?.first?.alignment, .center)
    }

    func testClickingTheRulerAddsAStopOneUndo() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let session = ui.state(OfficeShellState.self)!.session
        session.showRuler = true; ui.pump()
        XCTAssertTrue(ui.tap(id: "ruler"))
        XCTAssertEqual(session.controller.currentParagraphStyle.tabStops.count, 1)
        session.controller.undo()
        XCTAssertTrue(session.controller.currentParagraphStyle.tabStops.isEmpty)
    }
}
