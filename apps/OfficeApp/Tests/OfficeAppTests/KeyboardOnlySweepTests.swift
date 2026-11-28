// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// U-KEY-2: the whole app works without a mouse. The sweep reaches every ribbon command of Writer, Slides and Sheets
/// with the keyboard alone (F6 to the ribbon, Tab to the tab title, Enter, Tab to the command, Enter), and checks what
/// opens: every control a pointer could press in a dialog, menu, gallery or pane has a keyboard stop, Tab walks them all
/// in reading order with a ring on each, and Escape closes a dialog or menu and hands the ring back to its button.
final class KeyboardOnlySweepTests: XCTestCase {
    override func setUp() { KeyboardTraversal.shared.reset() }
    override func tearDown() { KeyboardTraversal.shared.reset() }

    private static let tabs = ["Home", "Insert", "Draw", "Design", "Layout", "References", "Review", "View",
                               "Transitions", "Animations", "Slide Show", "Page Layout", "Formulas", "Data"]

    private func app(_ make: () -> Widget) -> WidgetTester {
        KeyboardTraversal.shared.reset()
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: make(), title: "Test"), size: Size(1440, 932))
        ui.pump(); ui.pump()
        return ui
    }

    private var kt: KeyboardTraversal { KeyboardTraversal.shared }
    private func modal(_ ui: WidgetTester) -> Element? { ui.elements().last { ($0.widget as? KeyboardRegion)?.modal == true } }

    /// Moves the ring by keyboard alone to the control called `label`: F6 through the regions, Tab through each.
    private func reach(_ ui: WidgetTester, _ label: String, region: String = "ribbon") -> Bool {
        if kt.focused?.label() == label { return true }
        for _ in 0..<8 {
            if kt.focused?.region == region { break }
            ui.press(.f6)
        }
        guard kt.focused?.region == region else { return false }
        for _ in 0...kt.reachable(inRegion: region).count {
            if kt.focused?.label() == label { return true }
            ui.press(.tab)
        }
        return false
    }

    /// A fresh window with `tab` opened by keyboard.
    private func onTab(_ make: () -> Widget, _ tab: String) -> WidgetTester? {
        let ui = app(make)
        if tab == "Home" { return ui }
        guard reach(ui, tab) else { return nil }
        ui.press(.enter)
        ui.press(.escape)          // the ring leaves; the new page's commands come next
        return ui
    }

    /// Tappable nodes a screen reader sees that no keyboard stop covers (the stop's corner lies inside the node).
    private func unreachable(_ ui: WidgetTester, in root: Element?) -> [String] {
        let nodes = (root.map { SemanticsSnapshot.build(from: $0) } ?? ui.semantics()).filter { $0.canTap && !$0.label.isEmpty }
        let stops = kt.reachable().compactMap { $0.origin() }
        return nodes.filter { n in
            guard let f = n.frame, f.width > 1, f.height > 1 else { return false }
            return !stops.contains { o in o.dx >= f.x - 2 && o.dx <= f.x + f.width && o.dy >= f.y - 2 && o.dy <= f.y + f.height }
        }.map(\.label)
    }

    /// Tabs round once; returns the stops visited, in order.
    private func tabAround(_ ui: WidgetTester) -> [KeyStop] {
        var seen: [KeyStop] = []
        for _ in 0..<400 {
            ui.press(.tab)
            guard let f = kt.focused, !seen.contains(where: { $0 === f }) else { break }
            seen.append(f)
        }
        return seen
    }

    private var dialogs = 0, menus = 0, panes = 0, views = 0, commands = 0

    /// The tab titles a screen reader sees.
    private func tabTitles(_ ui: WidgetTester) -> [String] { ui.semantics().filter { $0.role == .tab }.map(\.label) }

    /// Puts the ring on the `i`th ribbon control by keyboard alone: F6 to the ribbon's first control, then Tab.
    private func reach(_ ui: WidgetTester, index i: Int) -> KeyStop? {
        for _ in 0..<8 where kt.focused?.region != "ribbon" { ui.press(.f6) }
        let list = kt.reachable(inRegion: "ribbon")
        guard i < list.count, kt.focused === list.first else { return nil }
        for _ in 0..<i { ui.press(.tab) }
        return kt.focused === list[i] ? list[i] : nil
    }

    private func sweep(_ name: String, _ make: () -> Widget) -> [String] {
        var bad: [String] = []
        let probe = app(make)
        let titles = tabTitles(probe).filter { Self.tabs.contains($0) }
        probe.dispose()
        let only = ProcessInfo.processInfo.environment["KEYSWEEP_TAB"]     // a developer's shortcut: one tab
        for tab in titles where only == nil || only == "\(name)/\(tab)" {
            guard let first = onTab(make, tab) else { bad.append("\(name)/\(tab): the tab title is not reachable by keyboard"); continue }
            let count = kt.reachable(inRegion: "ribbon").count
            first.dispose()
            for i in 0..<count {
                guard let ui = onTab(make, tab) else { break }
                guard let stop = reach(ui, index: i) else { bad.append("\(name)/\(tab)#\(i): Tab never reaches it"); continue }
                // An icon's glyph is not a name: a control whose only words are a symbol font's has none.
                let label = String((stop.label() ?? "").unicodeScalars.filter { !(0xE000...0xF8FF).contains($0.value) && $0.value < 0xF0000 })
                    .trimmingCharacters(in: .whitespaces)
                if Self.tabs.contains(label) || label == "File" { ui.dispose(); continue }
                if label.isEmpty {
                    let o = stop.origin()!
                    let near = ui.semantics().first { n in n.frame.map { o.dx >= $0.x - 2 && o.dx <= $0.x + $0.width && o.dy >= $0.y - 2 && o.dy <= $0.y + $0.height } ?? false }
                    bad.append("\(name)/\(tab)#\(i): a ribbon control with no name (reader hears '\(near?.label ?? "")' at \(Int(o.dx)),\(Int(o.dy)))")
                }
                commands += 1
                let regionsBefore = Set(kt.regions())
                ui.press(.enter); ui.pump()
                bad += check(name, "\(tab)/\(label.isEmpty ? "#\(i)" : label)", ui, stop, regionsBefore)
                ui.dispose()
            }
        }
        return bad
    }

    private func check(_ name: String, _ path: String, _ ui: WidgetTester, _ opener: KeyStop, _ before: Set<String>) -> [String] {
        if ui.elements().contains(where: { $0.widget is Backstage }) { return [] }
        var bad: [String] = []
        if let m = modal(ui), kt.reachable().contains(where: { $0.modal }) {
            // A dialog gives the keyboard back to the document when it closes, as Word's do; a menu or gallery
            // gives it back to the button that opened it.
            let region = (m.widget as? KeyboardRegion)?.name ?? ""
            let isDialog = region != "menu" && region != "ribbon-group"
            if isDialog { dialogs += 1 } else { menus += 1 }
            let missed = unreachable(ui, in: m)
            if !missed.isEmpty { bad.append("\(name)/\(path): no keyboard stop for \(Array(missed.prefix(5)))") }
            let all = kt.reachable()
            let walked = tabAround(ui)
            if walked.count != all.count { bad.append("\(name)/\(path): Tab visits \(walked.count) of \(all.count) controls") }
            if let i = walked.firstIndex(where: { $0 === all.first }), walked.count == all.count {
                let rotated = Array(walked[i...] + walked[..<i])
                if !zip(rotated, all).allSatisfy({ $0 === $1 }) { bad.append("\(name)/\(path): Tab order is not reading order") }
            }
            for _ in 0..<3 where modal(ui) != nil { ui.press(.escape); ui.pump() }
            if modal(ui) != nil { bad.append("\(name)/\(path): Escape does not close it") }
            else if !isDialog, kt.focused !== opener, ui.has(text: "Home") {
                bad.append("\(name)/\(path): after Escape the ring is on \(kt.focused?.label() ?? "nothing"), not its button")
            }
            return bad
        }
        if let m = modal(ui) {
            // A view with nothing to press (a slide show) is fine, if Escape ends it; anything pressable needs a stop.
            let missed = unreachable(ui, in: m)
            if !missed.isEmpty { bad.append("\(name)/\(path): no keyboard stop for \(Array(missed.prefix(5)))") }
            for _ in 0..<3 where modal(ui) != nil { ui.press(.escape); ui.pump() }
            if modal(ui) != nil { bad.append("\(name)/\(path): Escape does not close it") } else { views += 1 }
            return bad
        }
        let added = kt.regions().filter { !before.contains($0) }
        for region in added {
            panes += 1
            ui.press(.escape)
            var hit = false
            for _ in 0..<8 { ui.press(.f6); if kt.focused?.region == region { hit = true; break } }
            if !hit { bad.append("\(name)/\(path): F6 never reaches the \(region) pane") }
        }
        return bad
    }

    func testEveryCommandIsUsableByKeyboardAlone() {
        var bad: [String] = []
        bad += sweep("Writer") { OfficeShell(initialPath: nil, startBlank: true) }
        bad += sweep("Slides") { SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }) }
        bad += sweep("Sheets") { SheetsShell(initialPath: nil, onSwitch: { _, _ in }) }
        print("KEYSWEEP commands \(commands) dialogs \(dialogs) menus \(menus) panes \(panes) views \(views) bad \(bad.count)")
        for b in bad { print("KEYSWEEP BAD \(b)") }
        if ProcessInfo.processInfo.environment["KEYSWEEP_TAB"] != nil { return }
        XCTAssertGreaterThan(commands, 200, "the sweep must really reach the ribbon's commands")
        XCTAssertGreaterThan(dialogs + menus, 80, "the sweep must really open dialogs and menus")
        XCTAssertEqual(bad, [])
    }
}
