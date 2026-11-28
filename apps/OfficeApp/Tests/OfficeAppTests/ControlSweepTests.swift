import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Taps every icon button of each shell's ribbon, tab by tab, each on a fresh shell (a dialog left open by one
/// tap would otherwise swallow the next), and lists the ones that change neither the model, the view state nor
/// what is on screen. Such a button is dead: wire it or hide it.
final class ControlSweepTests: XCTestCase {
    private func app(_ home: Widget) -> WidgetTester {
        // 1500 wide: the Writer Home ribbon is 1377 pt on macOS (the UI font there is wider than on Linux), over the 1240 the
        // ribbon's viewport has at 1280, so its last control ("All styles") sat outside the viewport and a tap on it hit the page.
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Size(1500, 800))
    }

    private static let tabs = ["Home", "Insert", "Design", "Layout", "Transitions", "Review", "View", "Data", "Formulas", "Page Layout", "Draw", "References", "Animations", "Slide Show", "Mailings"]

    /// `make` builds a shell and returns it with a closure reading its model and view state.
    private func sweep(_ name: String, _ make: () -> (WidgetTester, () -> String)) -> [String] {
        var dead: [String] = []
        let (probe, _) = make()
        let tabs = Self.tabs.filter { probe.has(text: $0) }
        for tab in tabs {
            probe.tap(text: tab)
            for tip in Array(Set(probe.tips())).sorted() {
                let (ui, state) = make()
                ui.tap(text: tab)
                let before = (state(), ui.texts().sorted(), ui.tips().sorted())
                guard ui.tap(tip: tip) else { continue }
                let after = (state(), ui.texts().sorted(), ui.tips().sorted())
                if before == after { dead.append("\(name)/\(tab)/\(tip)") }
            }
        }
        return dead
    }

    /// Controls that rightly do nothing on a fresh shell: they act on an edit history, an open edit, a
    /// selection or a state they are already in. Anything else dead is a bug.
    /// (Written the Mac way, run through `.keys`: a tip spells its chord for the platform, "⌘Z" here and "Ctrl+Z" on Linux.)
    private static let idle: Set<String> = Set([
        "Redo (⇧⌘Z)", "Undo (⌘Z)", "Decrease", "Cancel", "Enter", "Double-click to rename",
        "Direction and sequence", "Normal", "Print Layout",
        // Nothing to select on a fresh blank slide (an icon-only button of the Editing group once that group gives way).
        "Select All",
        // Already the paragraph's state in the fixture (left, no indent, no formatting): idempotent.
        "Align Left", "Decrease Indent", "Clear All Formatting",
    ].map(\.keys))
    /// Slides has no selection fixture here yet, so its formatting controls cannot be told from dead ones.
    private static let slidesFormatting: Set<String> = Set([
        "Align Left", "Align Right", "Center", "Justify", "Bold (⌘B)", "Italic (⌘I)", "Underline (⌘U)",
        "Strikethrough", "Subscript", "Superscript", "Bullets", "Numbering", "Increase Indent", "Decrease Indent",
        "Clear All Formatting",
    ].map(\.keys))

    private func names(_ l: [String]) -> Set<String> { Set(l.map { String($0.split(separator: "/", maxSplits: 2)[2]) }) }

    func testNoControlIsDead() {
        func writer(selected: Bool) -> () -> (WidgetTester, () -> String) {
            {
                let ui = self.app(OfficeShell(initialPath: nil, startBlank: true))
                let s = ui.state(OfficeShellState.self)!
                if selected { s.session.controller.insertText("Some text to format"); s.session.controller.selectAll() }
                return (ui, { "\(s.session.controller.revision) \(s.session.zoom) \(s.session.viewMode) \(s.session.showMarks)" })
            }
        }
        // Dead on an empty page and still dead with text selected.
        let w = names(sweep("Writer", writer(selected: false))).intersection(names(sweep("Writer", writer(selected: true))))
        let p = names(sweep("Slides") {
            let ui = self.app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
            let s = ui.state(SlidesShellState.self)!
            // Zoomed in, so "Fit slide to window" has something to change.
            s.session.deck!.setViewZoom(percent: 150)
            return (ui, { "\(s.session.deck!.revision) \(s.session.slidesSorter) \(s.session.deck!.viewPercent)" })
        })
        let x = names(sweep("Sheets") {
            let ui = self.app(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))
            let s = ui.state(SheetsShellState.self)!
            return (ui, { "\(s.session.workbook!.revision)" })
        })
        XCTAssertEqual(w.subtracting(Self.idle).sorted(), [], "Writer controls that do nothing: wire or hide them")
        XCTAssertEqual(p.subtracting(Self.idle).subtracting(Self.slidesFormatting).sorted(), [], "Slides controls that do nothing")
        XCTAssertEqual(x.subtracting(Self.idle).sorted(), [], "Sheets controls that do nothing")
    }
}
