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

    // MARK: Touch

    func testAFingerTakesTheNearestMarkerWithin44Points() {
        var s = RichParagraphStyle()
        s.indentLeft = 36; s.firstLineIndent = -18
        s.tabStops = [TabStop(position: 144, alignment: .right)]
        let upper = RulerGeometry.top + 3, lower = RulerGeometry.top + RulerGeometry.band - 3
        // 20 px off the first-line marker (18 pt), upper half: a finger gets it, a mouse does not.
        XCTAssertEqual(g.target(at: Offset(g.x(18) + 20, upper), style: s, touch: true), .firstLine)
        XCTAssertNotEqual(g.target(at: Offset(g.x(18) + 20, upper), style: s), .firstLine)
        // The lower half is the indents.
        XCTAssertEqual(g.target(at: Offset(g.x(36) + 18, lower), style: s, touch: true), .leftIndent)
        XCTAssertEqual(g.target(at: Offset(g.x(g.setup.contentWidth) - 15, lower), style: s, touch: true), .rightIndent)
        // A tab stop 18 px away from either half; beyond 22 px it is a new stop.
        XCTAssertEqual(g.target(at: Offset(g.x(144) - 18, upper), style: s, touch: true), .tab(0))
        XCTAssertEqual(g.target(at: Offset(g.x(144) + 30, lower), style: s, touch: true), .newTab)
        // A finger above or below the painted rows (the touch ruler is taller than they are) still counts; a mouse does not.
        XCTAssertEqual(g.target(at: Offset(g.x(18), RulerGeometry.top - 9), style: s, touch: true), .firstLine)
        XCTAssertNil(g.target(at: Offset(g.x(18), RulerGeometry.top - 9), style: s))
        XCTAssertEqual(g.target(at: Offset(g.x(36), RulerGeometry.top + RulerGeometry.band + 10), style: s, touch: true), .leftIndent)
        XCTAssertNil(g.target(at: Offset(g.x(36), RulerGeometry.top + RulerGeometry.band + 15), style: s, touch: true), "off the ruler")
        // Between an indent and a tab, the nearer wins.
        s.tabStops = [TabStop(position: 50, alignment: .left)]
        XCTAssertEqual(g.target(at: Offset(g.x(48), lower), style: s, touch: true), .tab(0))
        XCTAssertEqual(g.target(at: Offset(g.x(40), lower), style: s, touch: true), .leftIndent)
    }

    func testTheReadoutSaysWhatTheDropWouldSet() {
        var s = RichParagraphStyle()
        s.indentLeft = 36
        s.tabStops = [TabStop(position: 144, alignment: .left)]
        let mid = g.mid
        XCTAssertEqual(g.readout(.firstLine, to: Offset(g.x(54), 6), style: s), "First line 0.75 in")
        XCTAssertEqual(g.readout(.leftIndent, to: Offset(g.x(72), 30), style: s), "Left 1 in")
        XCTAssertEqual(g.readout(.rightIndent, to: Offset(g.x(g.setup.contentWidth - 18), 30), style: s), "Right 0.25 in")
        XCTAssertEqual(g.readout(.tab(0), to: Offset(g.x(180), mid), style: s), "Tab 2.5 in")
        XCTAssertEqual(g.readout(.tab(0), to: Offset(g.x(144), 80), style: s), "Remove tab", "dragged off the ruler")
        XCTAssertEqual(g.readout(.newTab, to: Offset(g.x(100), mid), style: s), "Tab 1.38 in")
        XCTAssertNil(g.readout(.kindBox, to: Offset(10, mid), style: s))
    }

    func testAFingerDragsAMarkerItDidNotQuiteHit() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let session = ui.state(OfficeShellState.self)!.session
        session.showRuler = true
        session.controller.setParagraphFormat(.init(indentLeft: 36))
        ui.pump()
        XCTAssertEqual(session.controller.currentParagraphStyle.indentLeft, 36)
        let state = try XCTUnwrap(ui.state(RulerState.self))
        let box = try XCTUnwrap(state.context?.findRenderObject() as? RenderBox)
        XCTAssertEqual(box.size.height, Ruler.height)
        let lift = ((box.size.height - 22) / 2).rounded()
        let g = RulerGeometry(setup: session.pageSetup, px: session.theme.pixelsPerPoint * session.zoom, pad: 24, width: box.size.width)
        let y = lift + RulerGeometry.top + RulerGeometry.band - 3
        // A finger 16 px right of the left-indent marker takes it, and drags it by the offset it took it at (no jump).
        let start = box.localToGlobal(Offset(g.x(36) + 16, y))
        ui.drag(from: start, to: Offset(start.dx + 36 * g.px, start.dy), kind: .touch)
        XCTAssertEqual(session.controller.currentParagraphStyle.indentLeft, 72, accuracy: 4.6, "36 pt, moved 36 pt (snapped to the grid)")
        // A mouse 16 px off the marker is not on it: it adds a tab stop.
        session.controller.setParagraphFormat(.init(indentLeft: 36))
        ui.pump()
        ui.drag(from: start, to: Offset(start.dx + 36, start.dy), kind: .mouse)
        XCTAssertEqual(session.controller.currentParagraphStyle.tabStops.count, 1)
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
