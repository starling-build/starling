// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// U-SH-6: a modal dialog or menu hides what is under it from screen readers, as it does from the keyboard; a pane
/// or the Find bar does not. The sweep presses every control a screen reader can press in the ribbon, the title bar
/// and the status bar of Writer, Slides and Sheets, on every tab, the way a screen reader presses it.
final class ModalSemanticsSweepTests: XCTestCase {
    private static let tabs = ["Home", "Insert", "Draw", "Design", "Layout", "References", "Review", "View",
                               "Transitions", "Animations", "Slide Show", "Page Layout", "Formulas", "Data"]

    private func app(_ make: () -> Widget) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: make(), title: "Test"), size: Size(1440, 932))
        ui.pump(); ui.pump()
        return ui
    }

    /// The topmost modal keyboard region on screen (a dialog, a menu), if one is open.
    private func modal(_ ui: WidgetTester) -> Element? {
        ui.elements().last { ($0.widget as? KeyboardRegion)?.modal == true }
    }

    private func chrome(_ ui: WidgetTester) -> [String] {
        ui.semantics().filter { n in
            guard n.canTap, n.role != .tab, let f = n.frame, !n.label.isEmpty else { return false }
            return f.y < 200 || f.y > 900
        }.map(\.label)
    }

    /// Full-window layers that take every click (a dialog's dimmed backdrop): a cover the keyboard and the screen
    /// reader must not get past either.
    private func covers(_ ui: WidgetTester) -> Int {
        ui.elements().filter { e in
            guard let l = e.widget as? Listener, l.behavior == .opaque, let box = e.findRenderObject() as? RenderBox,
                  box.hasSize else { return false }
            return box.size.width >= 1440 && box.size.height >= 900
        }.count
    }

    private var modals = 0, panes = 0
    private func sweep(_ name: String, _ make: () -> Widget) -> [String] {
        var bad: [String] = []
        var ui = app(make)
        for tab in Self.tabs where ui.has(text: tab) {
            ui.tap(text: tab); ui.pump()
            let labels = chrome(ui)
            let bare = covers(ui)
            for (i, label) in labels.enumerated() {
                // Each press starts from a fresh window on this tab, so one control's state cannot hide another's.
                if i > 0 { ui = app(make); ui.tap(text: tab); ui.pump() }
                guard let n = ui.semantics().first(where: { $0.label == label && $0.canTap }) else { continue }
                n.tap?(); ui.pump(); ui.pump()
                bad += check(name, "\(tab)/\(label)", ui, bare)
                // A menu's "…" items open dialogs: press each from a fresh menu.
                guard let menu = modal(ui) else { continue }
                let more = SemanticsSnapshot.build(from: menu).filter { $0.canTap && ($0.label.containsSubstring("…") || $0.label.containsSubstring("...")) }.map(\.label)
                for item in more {
                    ui = app(make); ui.tap(text: tab); ui.pump()
                    guard let n = ui.semantics().first(where: { $0.label == label && $0.canTap }) else { break }
                    n.tap?(); ui.pump(); ui.pump()
                    guard let m = modal(ui), let it = SemanticsSnapshot.build(from: m).first(where: { $0.label == item && $0.canTap }) else { continue }
                    it.tap?(); ui.pump(); ui.pump()
                    bad += check(name, "\(tab)/\(label)/\(item)", ui, bare)
                }
            }
        }
        return bad
    }

    private func check(_ name: String, _ path: String, _ ui: WidgetTester, _ bare: Int) -> [String] {
        if ui.elements().contains(where: { $0.widget is Backstage }) { return [] }  // FileTabSemanticsTests
        let read = ui.semantics().map(\.label)
        if let m = modal(ui) {
            modals += 1
            let own = SemanticsSnapshot.build(from: m).map(\.label)
            if read == own { return [] }
            let extra = read.filter { !own.contains($0) }.prefix(4)
            return ["\(name)/\(path): read through the modal: \(Array(extra))"]
        }
        if covers(ui) > bare { return ["\(name)/\(path): a click-blocking cover that is not a modal region"] }
        guard ui.has(text: "Home") else { return [] }   // a full-window mode (Slide Show, Read Mode)
        panes += 1
        if ui.semantics().contains(where: { $0.role == .tab && $0.label == "Home" }) { return [] }
        return ["\(name)/\(path): the ribbon is hidden with no modal open"]
    }

    func testModalsBlockAndPanesDoNot() {
        var bad: [String] = []
        bad += sweep("Writer") { OfficeShell(initialPath: nil, startBlank: true) }
        bad += sweep("Slides") { SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }) }
        bad += sweep("Sheets") { SheetsShell(initialPath: nil, onSwitch: { _, _ in }) }
        XCTAssertGreaterThan(modals, 40, "the sweep must really open dialogs and menus")
        XCTAssertGreaterThan(panes, 40, "the sweep must really press non-modal controls")
        print("SWEEP modals \(modals) others \(panes)")
        XCTAssertEqual(bad, [])
    }
}
