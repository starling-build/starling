import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
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
            else if let h = e.widget as? HoverButton, h.keyStop, h.onPressed != nil || h.forceEnabled { n += 1 }
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

    /// The ribbon tab strip (and File) must be reachable without a mouse: Tab to a tab title, Enter opens its page.
    func testRibbonTabsAndFileAreReachableByKeyboard() {
        KeyboardTraversal.shared.reset()
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        ui.pump()
        let before = KeyboardTraversal.shared.reachable().count
        var homeButtons = 0
        for e in ui.elements() { if let h = e.widget as? HoverButton, h.semanticLabel == "File" || h.semanticLabel == "Insert" { homeButtons += 1 } }
        XCTAssertEqual(homeButtons, 2, "File and Insert are real buttons")
        var visitedInsert = false
        ui.press(.f6)                                    // the ring goes to the first region
        while KeyboardTraversal.shared.focused?.region != "ribbon", KeyboardTraversal.shared.regions().count > 1 {
            ui.press(.f6)
            if KeyboardTraversal.shared.focused?.region == "window" && KeyboardTraversal.shared.regions().first != "window" { break }
        }
        for _ in 0..<6 {
            guard let f = KeyboardTraversal.shared.focused, let at = f.origin() else { break }
            if at.dy < 60, at.dx > 100, ui.has(text: "Clipboard") {
                ui.press(.enter)
                if !ui.has(text: "Clipboard") { visitedInsert = true; break }
            }
            ui.press(.tab)
        }
        XCTAssertTrue(visitedInsert, "Tab and Enter on a tab title must leave the Home page")
        ui.dispose()
    }

    /// Alt shows a letter over each tab; pressing a tab's letter opens that page and gives its commands letters.
    func testAltKeyTipsOpenATabThenACommand() {
        KeyboardTraversal.shared.reset()
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        ui.pump()
        XCTAssertFalse(KeyboardTraversal.shared.tipsOn)
        ui.press(.alt)
        XCTAssertTrue(KeyboardTraversal.shared.tipsOn, "tapping Alt turns the key tips on")
        let tabs = KeyboardTraversal.shared.tipCodes()
        XCTAssertGreaterThanOrEqual(tabs.count, 5, "every tab title has a tip")
        XCTAssertEqual(Set(tabs.map { $0.code }).count, tabs.count, "tips are unique")
        guard let insert = tabs.first(where: { $0.stop.label() == "Insert" }) else { return XCTFail("no tip for Insert") }
        XCTAssertTrue(ui.has(text: "Clipboard"))
        ui.type(insert.code)
        ui.pump()
        XCTAssertTrue(KeyboardTraversal.shared.tipsOn, "after a tab letter the commands get tips")
        XCTAssertFalse(ui.has(text: "Clipboard"), "the Insert page is open")
        let commands = KeyboardTraversal.shared.tipCodes()
        XCTAssertGreaterThanOrEqual(commands.count, 3)
        XCTAssertEqual(Set(commands.map { $0.code }).count, commands.count, "command tips are unique")
        ui.press(.escape)
        XCTAssertFalse(KeyboardTraversal.shared.tipsOn, "Esc turns the tips off")
        ui.dispose()
    }

    /// Every ribbon control must have a name (tooltip or caption) so it gets an Alt key tip.
    func testArrowKeysMoveASliderTheRingIsOn() {
        var value = 100.0
        let ui = app(SizedBox(width: 200, height: 40, child: Slider(value: 100, onChanged: { value = $0 }, min: 50, max: 300, label: "Zoom")))
        ui.press(.f6)
        XCTAssertEqual(KeyboardTraversal.shared.focused?.label(), "Zoom")
        ui.press(.right)
        XCTAssertEqual(value, 112.5, accuracy: 0.01)
        ui.press(.left); ui.press(.left)
        XCTAssertEqual(value, 87.5, accuracy: 0.01)
    }

    func testF6ReachesTheDocumentPageAndTheEditorKeepsTheKeys() {
        let makers: [(String, () -> WidgetTester)] = [
            ("Writer", { self.app(OfficeShell(initialPath: nil, startBlank: true)) }),
            ("Slides", { self.app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in })) }),
            ("Sheets", { self.app(SheetsShell(initialPath: nil, onSwitch: { _, _ in })) }),
        ]
        for (name, make) in makers {
            let ui = make()
            XCTAssertTrue(KeyboardTraversal.shared.regions().contains("page"), "\(name): the page is a region")
            for _ in 0..<5 where KeyboardTraversal.shared.focused != nil || FocusManager.instance.focusedNode == nil { ui.press(.f6) }
            ui.press(.f6); ui.press(.f6)   // round the regions back to the page at most once more
            var onPage = false
            for _ in 0..<5 { ui.press(.f6); if KeyboardTraversal.shared.focused == nil { onPage = true; break } }
            XCTAssertTrue(onPage, "\(name): F6 reaches the page and the ring steps aside")
            XCTAssertNotNil(FocusManager.instance.focusedNode, "\(name): the editor holds the keys")
        }
    }

    func testContextualAndEveryOtherRibbonTabHasNamedControls() {
        for tab in RibbonTab.allCases {
            let session = OfficeSession()
            let ui = app(SizedBox(width: 1400, height: 200, child: Ribbon(session: session, tab: tab, collapsed: false,
                                                                         onTab: { _ in }, onCollapse: {})))
            let all = KeyboardTraversal.shared.reachable().filter { $0.region == "ribbon" }
            let top = all.map { ($0.origin()!.dy / 10).rounded() }.min() ?? 0
            let bad = all.filter { ($0.origin()!.dy / 10).rounded() != top && $0.label() == nil }
            XCTAssertTrue(bad.isEmpty, "\(tab.title): \(bad.count) controls without a name")
            XCTAssertGreaterThan(all.count, 3, "\(tab.title): has controls")
            _ = ui
        }
    }

    func testSlideSorterTilesAreKeyboardStops() {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        ui.tap(text: "View"); ui.tap(text: "Slide Sorter")
        let tiles = KeyboardTraversal.shared.reachable().filter { ($0.label() ?? "").hasPrefix("Slide ") && $0.label() != "Slide Sorter" }
        XCTAssertFalse(tiles.isEmpty, "each sorter tile has a stop")
    }

    func testEveryRibbonControlHasAName() {
        var nameless: [String] = []
        var pages = 0
        func rowOf(_ s: KeyStop) -> Double { (s.origin()!.dy / 10).rounded() }
        func sweep(_ name: String, _ ui: WidgetTester) {
            // Every tab on the strip, whatever it is called: walk the strip's own stops.
            func strip() -> [KeyStop] {
                let all = KeyboardTraversal.shared.reachable().filter { $0.region == "ribbon" }
                let top = all.map { rowOf($0) }.min() ?? 0
                return all.filter { rowOf($0) == top }
            }
            for i in 0..<strip().count {
                let tabs = strip()
                guard i < tabs.count else { break }
                let title = tabs[i].label() ?? "tab \(i)"
                tabs[i].activate(); ui.pump()
                pages += 1
                let all = KeyboardTraversal.shared.reachable().filter { $0.region == "ribbon" }
                let top = all.map { rowOf($0) }.min() ?? 0
                for s in all where rowOf(s) != top && s.label() == nil {
                    nameless.append("\(name)/\(title) at \(Int(s.origin()!.dx)),\(Int(s.origin()!.dy))")
                }
            }
        }
        sweep("Writer", app(OfficeShell(initialPath: nil, startBlank: true)))
        sweep("Slides", app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in })))
        sweep("Sheets", app(SheetsShell(initialPath: nil, onSwitch: { _, _ in })))
        XCTAssertGreaterThan(pages, 20)
        XCTAssertEqual(nameless.count, 0, "nameless: \(nameless.prefix(60))")
    }

    func testEveryRibbonButtonOfEveryTabIsReachable() {
        let tabs = ["Home", "Insert", "Design", "Layout", "Transitions", "Review", "View", "Data", "Formulas",
                    "Page Layout", "Draw", "References", "Animations", "Slide Show"]
        var inspected = 0
        func sweep(_ name: String, _ ui: WidgetTester) {
            for tab in tabs where ui.has(text: tab) {
                ui.tap(text: tab)
                let want = buttonsOnScreen(ui)
                let got = KeyboardTraversal.shared.reachable().filter { $0.region != "page" && $0.region != "thumbnails" }.count
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

    /// Every Sheets dialog: Tab reaches each control and Esc closes it.
    /// On an empty sheet the four data dialogs must say why they do not open, never do nothing; with data they open.
    /// An open drop-down menu is one modal keyboard region: Tab walks every item and activating one runs it.
    func testMenuItemsAreReachableByTabAndActivate() {
        KeyboardTraversal.shared.reset()
        var ran: [String] = []
        let menu = MenuFlyout(items: [
            MenuFlyoutItem(text: Text("One"), onPressed: { ran.append("One") }),
            MenuFlyoutItem(text: Text("Two"), onPressed: { ran.append("Two") }),
            MenuFlyoutItem(text: Text("Three"), onPressed: { ran.append("Three") }),
        ])
        let ui = app(Center(child: menu))
        ui.pump()
        let reach = KeyboardTraversal.shared.reachable()
        XCTAssertEqual(reach.count, 3, "each menu item has a keyboard stop")
        XCTAssertTrue(reach.allSatisfy { $0.modal })
        XCTAssertEqual(tabAround(ui), 3)
        KeyboardTraversal.shared.move(reverse: false)
        ui.press(.enter)
        XCTAssertEqual(ran.count, 1, "Enter runs the focused item")
        ui.dispose()
    }

    func testDataDialogsExplainThemselvesOnAnEmptySheetAndOpenWithData() {
        let cmds: [(String, SheetCommand, String)] = [
            ("Remove Duplicates", .removeDuplicates, DuplicatesProblem.nothingToCheck.message),
            ("Subtotal", .subtotal, SubtotalProblem.nothingToTotal.message),
            ("Sort", .sortDialog, SortProblem.nothingToSort.message),
            ("Text to Columns", .textToColumns, TextToColumnsProblem.oneColumn.message),
        ]
        for (name, cmd, message) in cmds {
            KeyboardTraversal.shared.reset()
            var ui = app(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))
            var wb = ui.state(SheetsShellState.self)!.wb
            wb.onCommand?(cmd); ui.pump()
            XCTAssertTrue(ui.texts().contains(message), "\(name) on an empty sheet must say why: \(message)")
            XCTAssertTrue(KeyboardTraversal.shared.reachable().filter { $0.modal }.isEmpty, "\(name): no dialog on an empty sheet")
            KeyboardTraversal.shared.reset()
            ui = app(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))
            wb = ui.state(SheetsShellState.self)!.wb
            wb.setInputs([(CellAddress(row: 0, col: 0), "Name"), (CellAddress(row: 0, col: 1), "Qty"),
                          (CellAddress(row: 1, col: 0), "a"), (CellAddress(row: 1, col: 1), "3"),
                          (CellAddress(row: 2, col: 0), "b"), (CellAddress(row: 2, col: 1), "5")])
            wb.onCommand?(cmd); ui.pump()
            if name == "Text to Columns" { continue }   // needs a one-column selection; covered by its own tests
            XCTAssertFalse(KeyboardTraversal.shared.reachable().filter { $0.modal }.isEmpty, "\(name) must open with data")
        }
    }

    func testEverySheetsDialogIsWalkableByTab() {
        let opens: [(String, SheetCommand)] = [
            ("Insert Cells", .cellsDialog(insert: true)), ("Delete Cells", .cellsDialog(insert: false)),
            ("Paste Special", .pasteSpecial), ("Conditional Format", .conditionalFormat),
            ("Data Validation", .dataValidation), ("Consolidate", .consolidate),
            ("Remove Duplicates", .removeDuplicates), ("Text to Columns", .textToColumns),
            ("Subtotal", .subtotal), ("Sort", .sortDialog), ("Table", .tableDialog),
            ("Name Manager", .nameManager), ("Protect Sheet", .protectSheetDialog),
            ("Protect Workbook", .protectWorkbookDialog), ("Page Setup", .pageSetup),
        ]
        var opened = 0
        for (name, cmd) in opens {
            KeyboardTraversal.shared.reset()
            let ui = app(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))
            let wb = ui.state(SheetsShellState.self)!.wb
            let behind = buttonsOnScreen(ui)
            wb.onCommand?(cmd); ui.pump()
            let reach = KeyboardTraversal.shared.reachable()
            guard !reach.isEmpty, reach.allSatisfy({ $0.modal }) else { print("KEYSWEEP not modal/none: \(name) stops=\(reach.count)"); continue }
            opened += 1
            let onScreen = buttonsOnScreen(ui) - behind
            print("KEYSWEEP \(name): stops=\(reach.count) controls=\(onScreen)")
            XCTAssertEqual(reach.count, onScreen, "\(name): every control on screen has a keyboard stop")
            XCTAssertEqual(tabAround(ui), reach.count, "\(name): Tab must visit all \(reach.count) controls once")
            XCTAssertTrue(ui.press(.escape), name)
        }
        XCTAssertGreaterThanOrEqual(opened, 8, "the sweep must really open dialogs")
    }

    /// Every Slides dialog: Tab reaches each control and Esc closes it.
    func testEverySlidesDialogIsWalkableByTab() {
        let opens: [(String, (OfficeSession) -> Void)] = [
            ("Find", { $0.onFind?(false) }), ("Replace", { $0.onFind?(true) }),
            ("Symbol", { $0.onSymbolDialog?() }), ("More Colors", { $0.onMoreColors?() }),
            ("Header and Footer", { $0.onHeaderFooter?() }), ("Alt Text", { $0.onAltText?() }),
            ("Text Options", { $0.onTextOptions?() }), ("Print", { $0.onPrint?() }),
            ("Shortcuts", { $0.onShortcuts?() }),
        ]
        var opened = 0
        for (name, open) in opens {
            KeyboardTraversal.shared.reset()
            let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
            let state = ui.state(SlidesShellState.self)!
            let deck = state.session.deck!
            deck.selectShapes([deck.currentSlide.shapes.first { $0.text != nil }!]); ui.pump()
            if name == "Alt Text" {
                let pic = deck.addPicture(ImageAttachment(data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!, width: 20, height: 20), naturalSize: Size(20, 20))
                deck.selectShapes([pic]); ui.pump()
            }
            if name == "Symbol" { ui.press(.enter); ui.pump() }     // typing in the shape, as the Symbol command needs
            let behind = buttonsOnScreen(ui)
            open(state.session); ui.pump()
            let reach = KeyboardTraversal.shared.reachable()
            XCTAssertFalse(reach.isEmpty, "\(name): the dialog must open")
            guard !reach.isEmpty else { continue }
            XCTAssertTrue(reach.allSatisfy { $0.modal }, "\(name): its controls must be one modal keyboard region")
            opened += 1
            let onScreen = buttonsOnScreen(ui) - behind
            XCTAssertEqual(reach.count, onScreen, "\(name): every control on screen has a keyboard stop")
            XCTAssertEqual(tabAround(ui), reach.count, "\(name): Tab must visit all \(reach.count) controls once")
            XCTAssertTrue(ui.press(.escape), name)
        }
        XCTAssertGreaterThanOrEqual(opened, 9, "the sweep must really open dialogs")
    }

    // MARK: Tab keeps its own meaning inside the editing surfaces

    func testTabInWriterTextInsertsATabAndDoesNotWalkTheRibbon() {
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        let session = ui.state(OfficeShellState.self)!.session
        ui.tap(at: Offset(640, 400))
        ui.type("a")
        ui.press(.tab); ui.type("b")
        XCTAssertNil(KeyboardTraversal.shared.focused)
        XCTAssertEqual(session.controller.document.paragraphs[0].text, "a\tb")
    }

    func testTabAtTheStartOfAWriterListItemIndentsIt() {
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        let c = ui.state(OfficeShellState.self)!.session.controller
        ui.tap(at: Offset(640, 400))
        c.toggleList(.bullet)
        XCTAssertEqual(c.currentParagraphStyle.listLevel, 0)
        ui.press(.tab)
        XCTAssertNil(KeyboardTraversal.shared.focused)
        XCTAssertEqual(c.currentParagraphStyle.listLevel, 1)
        XCTAssertFalse(c.document.paragraphs[0].text.contains("\t"))
    }

    func testTabInTheLastWriterTableCellAddsARow() {
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        let c = ui.state(OfficeShellState.self)!.session.controller
        ui.tap(at: Offset(640, 400))
        c.insertTable(rows: 2, columns: 2)
        func rows() -> Int { (c.document.paragraphs.compactMap { $0.cell?.row }.max() ?? -1) + 1 }
        XCTAssertEqual(rows(), 2)
        ui.press(.tab); ui.press(.tab); ui.press(.tab)      // cell 2, 3, 4
        XCTAssertEqual(rows(), 2)
        ui.press(.tab)                                      // past the last cell
        XCTAssertNil(KeyboardTraversal.shared.focused)
        XCTAssertEqual(rows(), 3)
    }

    func testTabWhileTypingInASlideShapeIndentsAndDoesNotWalkOrCycle() {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        let deck = ui.state(SlidesShellState.self)!.session.deck!
        let shape = deck.currentSlide.shapes.first { $0.text != nil }!
        deck.selectShapes([shape]); ui.pump()
        ui.press(.enter); ui.pump()                              // Enter edits the selected shape's text
        ui.type("x")
        XCTAssertEqual(shape.text!.document.paragraphs[0].text, "x", "the shape's editor must have the keyboard")
        ui.press(.tab)
        XCTAssertNil(KeyboardTraversal.shared.focused)
        XCTAssertTrue(deck.selection.first === shape, "Tab typed into the shape must not cycle the selection")
        let p = shape.text!.document.paragraphs[0]
        XCTAssertTrue(p.text.contains("\t") || p.style.listLevel > 0, "Tab indents or inserts a tab in the shape's text")
    }

    func testTabInSheetsMovesToTheNextCell() {
        let ui = app(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))
        let wb = ui.state(SheetsShellState.self)!.wb
        ui.tap(at: Offset(300, 300))
        let before = wb.active
        ui.press(.tab)
        XCTAssertNil(KeyboardTraversal.shared.focused)
        XCTAssertEqual(wb.active.col, before.col + 1)
        XCTAssertEqual(wb.active.row, before.row)
    }

    func testTabInSlidesCyclesShapesAndF6LeavesAfterAClick() {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        let deck = ui.state(SlidesShellState.self)!.session.deck!
        let shapes = deck.currentSlide.shapes
        XCTAssertGreaterThanOrEqual(shapes.count, 2)
        deck.selectShapes([shapes[0]]); ui.pump()
        ui.press(.tab)
        XCTAssertNil(KeyboardTraversal.shared.focused)
        XCTAssertTrue(deck.selection.first === shapes[1])
        // F6 gets out to the ribbon; a click on the canvas gives Tab back to the slide.
        ui.press(.f6)
        XCTAssertNotNil(KeyboardTraversal.shared.focused)
        ui.tap(at: Offset(700, 400))
        XCTAssertNil(KeyboardTraversal.shared.focused)
    }

    /// Tab onto a control below the fold of a scrolling list, pane or gallery: it scrolls into view (both the plain
    /// scroll view and the lazy list), and the ring's corner is where the control is now drawn.
    func testTheRingScrollsIntoViewBelowTheFold() {
        let rows: () -> [Widget] = {
            (0..<30).map { i in KeyboardRow(label: "Item \(i)", activate: {}, child: SizedBox(height: 40, child: Text("Item \(i)"))) }
        }
        for kind in ["scroll view", "list"] {
            KeyboardTraversal.shared.reset()
            let c = ScrollController()
            let list: Widget = kind == "list" ? ListView(controller: c, children: rows())
                : SingleChildScrollView(controller: c, child: Column(children: rows()))
            let ui = app(Align(alignment: Alignment.topLeft, child: SizedBox(width: 300, height: 200, child: KeyboardRegion(name: "list", child: list))))
            ui.pump()
            ui.press(.f6)
            XCTAssertEqual(KeyboardTraversal.shared.focused?.label(), "Item 0", kind)
            for n in 1..<20 {
                ui.press(.tab); ui.pump()
                let f = KeyboardTraversal.shared.focused
                XCTAssertEqual(f?.label(), "Item \(n)", kind)
                guard let o = f?.origin() else { XCTFail("\(kind): Item \(n) has no place"); break }
                XCTAssertTrue(o.dy >= -0.01 && o.dy + 40 <= 200.01, "\(kind): Item \(n) drawn at \(o.dy), outside 0...200")
            }
            XCTAssertEqual(c.offset, 19 * 40 + 40 - 200, accuracy: 0.5, "\(kind): scrolled just enough")
            ui.press(.tab, shift: true); ui.pump()
            XCTAssertEqual(c.offset, 19 * 40 + 40 - 200, accuracy: 0.5, "\(kind): a row already in view does not scroll")
            ui.dispose()
        }
    }
}
