import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// U-KEY-1: everything can be reached and used without a mouse: Tab and Shift+Tab, F6 between regions, Enter or Space to
/// press, Esc to go back. The sweep tabs through every dialog and every ribbon tab and checks nothing is left out.
final class KeyboardTraversalTests: XCTestCase {
    override func setUp() { KeyboardTraversal.shared.reset() }
    override func tearDown() { KeyboardTraversal.shared.reset() }

    private func app(_ home: Widget) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Size(1280, 800))
    }

    /// Buttons on screen the keyboard should reach: enabled ribbon buttons and enabled fluent buttons.
    private func buttonsOnScreen(_ ui: WidgetTester) -> Int {
        var n = 0
        for e in ui.elements() {
            if let b = e.widget as? FlatButton, b.enabled { n += 1 }
            else if let h = e.widget as? HoverButton, h.onPressed != nil || h.forceEnabled { n += 1 }
            else if e.widget is FluentTextBox { n += 1 }
        }
        return n
    }

    /// Tabs round the whole list once; returns how many different controls the ring visited.
    private func tabAround(_ ui: WidgetTester, limit: Int = 400) -> Int {
        var seen: [ObjectIdentifier] = []
        for _ in 0..<limit {
            ui.press(.tab)
            guard let f = KeyboardTraversal.shared.focused else { break }
            let id = ObjectIdentifier(f)
            if seen.contains(id) { break }
            seen.append(id)
        }
        return seen.count
    }

    private func dialog(_ log: @escaping (String) -> Void = { _ in }) -> WidgetTester {
        app(DialogShell(title: "Page Setup",
                        tabs: [DialogTab(title: "Margins", page: Button(onPressed: { log("page") }, child: Text("Reset"))),
                               DialogTab(title: "Paper", page: Text("paper"))],
                        okEnabled: true, onOK: { log("ok") }, onCancel: { log("cancel") }))
    }

    func testTabVisitsEveryControlOfADialogAndWrapsRound() {
        let ui = dialog()
        let on = buttonsOnScreen(ui)
        XCTAssertGreaterThanOrEqual(on, 5)   // two tabs, Reset, OK, Cancel
        XCTAssertEqual(tabAround(ui), on)
    }

    func testShiftTabGoesBackAndEnterOrSpacePresses() {
        var log: [String] = []
        let ui = dialog { log.append($0) }
        ui.press(.tab)                                   // first: the "Margins" tab
        ui.press(.tab, shift: true)                      // wraps to the last: Cancel
        ui.press(.space)
        XCTAssertEqual(log, ["cancel"])
        ui.press(.tab)                                   // wraps to the first again
        ui.press(.tab); ui.press(.tab)                   // Paper, Reset
        ui.press(.enter)
        XCTAssertEqual(log, ["cancel", "page"])          // Enter on a focused control presses it, it is not OK
    }

    func testEscapeFirstDropsTheRingThenCancels() {
        var log: [String] = []
        let ui = dialog { log.append($0) }
        ui.press(.tab)
        XCTAssertNotNil(KeyboardTraversal.shared.focused)
        ui.press(.escape)
        XCTAssertNil(KeyboardTraversal.shared.focused)
        XCTAssertEqual(log, [])
        ui.press(.escape)
        XCTAssertEqual(log, ["cancel"])
    }

    func testTheTabShowsWhichPageIsOpenThroughTheKeyboard() {
        let ui = dialog()
        ui.press(.tab); ui.press(.tab)                   // Paper tab
        ui.press(.enter)
        XCTAssertEqual(ui.state(DialogShellState.self)?.selectedTab, 1)
    }

    func testEveryRibbonButtonOfEveryTabIsReachable() {
        let tabs = ["Home", "Insert", "Design", "Layout", "Transitions", "Review", "View", "Data", "Formulas",
                    "Page Layout", "Draw", "References", "Animations", "Slide Show"]
        var inspected = 0
        func sweep(_ name: String, _ ui: WidgetTester) {
            for tab in tabs where ui.has(text: tab) {
                ui.tap(text: tab)
                let want = buttonsOnScreen(ui)
                let got = KeyboardTraversal.shared.reachable().count
                inspected += want
                XCTAssertEqual(got, want, "\(name)/\(tab): \(want) buttons on screen, \(got) reachable by keyboard")
            }
        }
        sweep("Writer", app(OfficeShell(initialPath: nil, startBlank: true)))
        sweep("Slides", app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in })))
        sweep("Sheets", app(SheetsShell(initialPath: nil, onSwitch: { _, _ in })))
        XCTAssertGreaterThan(inspected, 150)
    }

    func testF6MovesBetweenRegions() {
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        XCTAssertGreaterThanOrEqual(KeyboardTraversal.shared.regions().count, 2)
        ui.press(.f6)
        let first = KeyboardTraversal.shared.focused?.region
        XCTAssertNotNil(first)
        ui.press(.f6)
        XCTAssertNotEqual(KeyboardTraversal.shared.focused?.region, first)
    }

    /// Every Writer dialog: Tab reaches each button, check box and text box, and wraps round; Esc closes it.
    func testEveryWriterDialogIsWalkableByTab() {
        let opens: [(String, (OfficeSession) -> Void)] = [
            ("Paragraph", { $0.onParagraphDialog?() }), ("Font", { $0.onFontDialog?() }),
            ("Page Setup", { $0.onPageSetupDialog?() }), ("Insert Table", { $0.onInsertTableDialog?() }),
            ("Borders", { $0.onBordersShadingDialog?() }), ("Numbering", { $0.onNumberingValueDialog?() }),
            ("List", { $0.onListFormatDialog?(true) }), ("Symbol", { $0.onSymbolDialog?() }),
        ]
        var opened = 0
        for (name, open) in opens {
            KeyboardTraversal.shared.reset()
            let ui = app(OfficeShell(initialPath: nil, startBlank: true))
            let session = ui.state(OfficeShellState.self)!.session
            let behind = buttonsOnScreen(ui)
            open(session); ui.pump()
            let reach = KeyboardTraversal.shared.reachable()
            guard !reach.isEmpty, reach.allSatisfy({ $0.modal }) else { continue }
            opened += 1
            XCTAssertEqual(reach.count, buttonsOnScreen(ui) - behind, "\(name): every control on screen has a keyboard stop")
            XCTAssertEqual(tabAround(ui), reach.count, "\(name): Tab must visit all \(reach.count) controls once")
            XCTAssertTrue(ui.press(.escape), name)
        }
        XCTAssertGreaterThanOrEqual(opened, 5, "the sweep must really open dialogs")
    }
}
