// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// U-shared screen-reader pass, the part AccessibleNameSweepTests does not reach: right-click menus (with their mini
/// toolbar) and the File tab's pages. Every control a screen reader can press must say what it is.
final class MenuNameSweepTests: XCTestCase {
    private func app(_ home: Widget) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Size(1440, 932))
    }
    private var shells: [(String, () -> WidgetTester)] {
        [("Writer", { self.app(OfficeShell(initialPath: nil, startBlank: true)) }),
         ("Slides", { self.app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in })) }),
         ("Sheets", { self.app(SheetsShell(initialPath: nil, onSwitch: { _, _ in })) })]
    }

    /// Pressable nodes with no name, as "where: role at x,y".
    private func unnamed(_ ui: WidgetTester, _ where_: String) -> [String] {
        var bad: [String] = []
        for n in ui.semantics() where (n.canTap || n.isButton) && n.label.trimmingWhitespace().isEmpty && n.value.isEmpty && !n.isTextField {
            bad.append("\(where_): \(n.isButton ? "button" : "tappable") at \(Int(n.frame?.x ?? -1)),\(Int(n.frame?.y ?? -1))")
        }
        return bad
    }

    func testRightClickMenusNameEveryControl() {
        var bad: [String] = [], opened = 0
        for (name, make) in shells {
            let ui = make()
            let before = Set(unnamed(ui, name))
            ui.tap(at: Offset(720, 500), buttons: kSecondaryMouseButton); ui.pump()
            if ui.has(text: "Paste") || ui.has(text: "Cut") || ui.has(text: "Copy") { opened += 1 }
            bad += unnamed(ui, "\(name) right-click").filter { !before.contains($0.replacingAll(" right-click", with: "")) }
        }
        XCTAssertGreaterThanOrEqual(opened, 2, "the right-click menus opened")
        XCTAssertEqual(bad, [])
    }

    func testFileTabPagesNameEveryControl() {
        var bad: [String] = [], pages = 0
        for (name, make) in shells {
            let ui = make()
            ui.tap(text: "File"); ui.pump()
            for page in ["Info", "New", "Open", "Save As", "Print", "Export", "Options"] where ui.has(text: page) {
                ui.tap(text: page); ui.pump(); pages += 1
                bad += unnamed(ui, "\(name)/File/\(page)")
            }
        }
        XCTAssertGreaterThan(pages, 6)
        XCTAssertEqual(Array(Set(bad)).sorted(), [])
    }
}
