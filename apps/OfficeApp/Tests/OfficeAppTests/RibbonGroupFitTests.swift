import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A ribbon group's commands and caption fit the ribbon's height: no column in the band is taller than the room it has.
final class RibbonGroupFitTests: XCTestCase {
    private func overflows(_ home: Widget) -> [String] {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Size(1440, 900))
        defer { ui.dispose() }
        var out: [String] = []
        for e in ui.elements() {
            guard let group = e.widget as? RibbonGroup else { continue }
            func walk(_ r: RenderObject) {
                if let f = r as? RenderFlex, f.direction == .vertical {
                    var used = 0.0
                    f.visitChildren { c in used += (c as? RenderBox)?.size.height ?? 0 }
                    if used > f.size.height + 0.01 { out.append("\(group.label): \(used) in \(f.size.height)") }
                }
                r.visitChildren(walk)
            }
            if let r = e.findRenderObject() { walk(r) }
        }
        return out
    }

    func testWriterHomeGroupsFitTheRibbon() {
        XCTAssertEqual(overflows(OfficeShell(initialPath: nil, startBlank: true)), [])
    }

    func testSlidesHomeGroupsFitTheRibbon() { XCTAssertEqual(overflows(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in })), []) }
    func testSheetsHomeGroupsFitTheRibbon() {
        XCTAssertEqual(overflows(SheetsShell(initialPath: nil, onSwitch: { _, _ in })), [])
    }
}
