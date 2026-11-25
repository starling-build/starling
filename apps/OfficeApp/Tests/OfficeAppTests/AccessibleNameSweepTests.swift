import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// U-A11Y-1: every ribbon control has a name a screen reader can read: a tooltip, or text inside it.
/// An icon-only button with neither is announced as just "button".
final class AccessibleNameSweepTests: XCTestCase {
    private func app(_ home: Widget) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Size(1280, 800))
    }

    private static let tabs = ["Home", "Insert", "Design", "Layout", "Transitions", "Review", "View", "Data", "Formulas",
                               "Page Layout", "Draw", "References", "Animations", "Slide Show"]

    private func hasText(_ e: Element) -> Bool {
        var found = false
        func walk(_ x: Element) {
            if found { return }
            if let t = x.widget as? Text, !(t.data ?? "").trimmingWhitespace().isEmpty { found = true; return }
            x.visitChildElements(walk)
        }
        walk(e)
        return found
    }

    /// Unnamed FlatButtons on every tab of one shell, as "tab: icon-only button at x,y".
    private var inspected = 0
    private func unnamed(_ name: String, _ ui: WidgetTester) -> [String] {
        var bad: [String] = []
        for tab in Self.tabs where ui.has(text: tab) {
            ui.tap(text: tab)
            for e in ui.elements() {
                guard let b = e.widget as? FlatButton else { continue }
                inspected += 1
                if !(b.tip ?? "").trimmingWhitespace().isEmpty || hasText(e) { continue }
                let at = (e.findRenderObject() as? RenderBox).map { $0.localToGlobal(Offset(0, 0)) }
                bad.append("\(name)/\(tab) at \(Int(at?.dx ?? -1)),\(Int(at?.dy ?? -1))")
            }
        }
        return Array(Set(bad)).sorted()
    }

    func testEveryRibbonButtonHasAName() {
        defer { XCTAssertGreaterThan(inspected, 150, "the sweep must really look at the ribbons") }
        XCTAssertEqual(unnamed("Writer", app(OfficeShell(initialPath: nil, startBlank: true))), [])
        XCTAssertEqual(unnamed("Slides", app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))), [])
        XCTAssertEqual(unnamed("Sheets", app(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))), [])
    }

    /// A text box is named by its placeholder, or by a label (text) in the row or column that holds it.
    private var fields = 0
    private func unlabelledFields(_ ui: WidgetTester) -> Int {
        var bad = 0
        for e in ui.elements() {
            guard let box = e.widget as? FluentTextBox else { continue }
            fields += 1
            if !(box.placeholderText ?? "").trimmingWhitespace().isEmpty { continue }
            var named = false, depth = 0
            e.visitAncestorElements { a in
                depth += 1
                if a.widget is Row || a.widget is Column || a.widget is Wrap, self.hasText(a) { named = true; return false }
                return depth < 6
            }
            if !named { bad += 1 }
        }
        return bad
    }

    func testEveryDialogFieldHasAName() {
        var hooks = HyperlinkHooks(apply: { _, _, _, _ in "" })
        hooks.places = [HyperlinkPlace(id: "h", title: "Intro", kind: "Heading")]
        let find = FindHooks(findNext: { _, _, _ in "" }, replace: { _, _, _ in "" }, replaceAll: { _, _, _ in "" })
        let dialogs: [(String, Widget)] = [
            ("Hyperlink", HyperlinkDialog(hooks: hooks, onClose: {})),
            ("Find", FindReplaceDialog(initialQuery: "", hooks: find, onClose: {})),
            ("Paragraph", ParagraphDialog(initial: RichParagraphStyle(), onOK: { _ in }, onCancel: {})),
            ("Font", FontDialog(initial: RichDocumentController.CharFormat(CharStyle()), onOK: { _ in }, onCancel: {})),
            ("PageSetup", PageSetupDialog(initial: .letter, onOK: { _ in }, onCancel: {})),
        ]
        defer { XCTAssertGreaterThan(fields, 8, "the sweep must really see the fields") }
        for (name, d) in dialogs {
            let ui = app(d)
            XCTAssertEqual(unlabelledFields(ui), 0, "\(name): a field with no placeholder and no label beside it")
        }
    }
}
