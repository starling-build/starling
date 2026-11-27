import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// U-A11Y-1: state changes that have no focus move are said to a screen reader through ScreenReader.announce
/// ("Bold on", "Selected B3", "Slide 2 of 2", "Font dialog"). The platform bridges (AT-SPI, VoiceOver on
/// macOS and iOS) only install a sink; what is said is decided here, so it is tested here.
final class ScreenReaderTests: XCTestCase {
    override func setUp() { KeyboardTraversal.shared.reset(); ScreenReader.resetForTesting(); ScreenReader.recorded = [] }
    override func tearDown() { KeyboardTraversal.shared.reset(); ScreenReader.resetForTesting() }

    private func app(_ home: Widget) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Size(1280, 800))
    }

    func testAnnounceReachesTheSinkWithItsPriorityAndRepeatsAreDropped() {
        var got: [(String, ScreenReader.Priority)] = []
        ScreenReader.sink = { got.append(($0, $1)) }
        ScreenReader.announce("Bold on")
        ScreenReader.announce("Bold on")                      // a held key: said once
        ScreenReader.announce("Font dialog", priority: .assertive)
        ScreenReader.announce("   ")                          // nothing to say
        XCTAssertEqual(got.map { $0.0 }, ["Bold on", "Font dialog"])
        XCTAssertEqual(got.map { $0.1 }, [.polite, .assertive])
        XCTAssertEqual(ScreenReader.recorded ?? [], ["Bold on", "Font dialog"])
    }

    func testPressingBoldInWriterSaysOnThenOff() {
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        func press() {
            guard let s = KeyboardTraversal.shared.reachable().first(where: { ($0.label() ?? "").hasPrefix("Bold") }) else { return XCTFail("no Bold stop") }
            s.activate(); ui.pump()
        }
        press()
        XCTAssertEqual(ScreenReader.recorded?.last, "Bold on")
        Thread.sleep(forTimeInterval: 0.3)
        press()
        XCTAssertEqual(ScreenReader.recorded?.last, "Bold off")
    }

    func testMovingTheSelectionInSheetsSaysTheCell() {
        let c = WorkbookController()
        c.select(CellAddress(row: 2, col: 1))
        XCTAssertEqual(ScreenReader.recorded?.last, "B3, blank")
        c.select(range: CellRange(CellAddress(row: 2, col: 1), CellAddress(row: 4, col: 2)))
        XCTAssertEqual(ScreenReader.recorded?.last, "Selected B3 to C5")
    }

    func testASheetsCellIsSpokenWithItsHeadersValueAndFormula() {
        let c = WorkbookController()
        c.setInputs([(CellAddress(row: 0, col: 0), "Item"), (CellAddress(row: 0, col: 1), "Price"),
                     (CellAddress(row: 1, col: 0), "Tea"), (CellAddress(row: 1, col: 1), "4"),
                     (CellAddress(row: 2, col: 0), "Cake"), (CellAddress(row: 2, col: 1), "=B2*2")])
        c.select(CellAddress(row: 1, col: 1))
        let plain = ScreenReader.recorded?.last ?? ""
        XCTAssertTrue(plain.contains("B2") && plain.contains("Price") && plain.contains("4"), plain)
        XCTAssertFalse(plain.contains("formula"), plain)
        c.select(CellAddress(row: 2, col: 1))
        let f = ScreenReader.recorded?.last ?? ""
        XCTAssertTrue(f.contains("Price") && f.contains("8") && f.contains("formula =B2*2"), f)
    }

    func testMovingBetweenWriterTableCellsSaysRowColumnAndHeader() {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 2, columns: 2)
        let cells = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        func caret(_ i: Int) { c.selection = RichSelection(anchor: RichPosition(paragraph: i, offset: 0), focus: RichPosition(paragraph: i, offset: 0)) }
        caret(cells[1]); c.insertText("Price")
        ScreenReader.recorded = []
        caret(cells[3])
        XCTAssertEqual(ScreenReader.recorded?.last, "Row 2, column 2, Price")
        caret(cells[2])
        XCTAssertEqual(ScreenReader.recorded?.last, "Row 2, column 1")
        let n = ScreenReader.recorded?.count
        caret(cells[2])
        XCTAssertEqual(ScreenReader.recorded?.count, n)
    }

    func testChangingSlideSaysItsPlaceInTheDeck() {
        let c = DeckController()
        _ = c.addSlide()
        XCTAssertEqual(ScreenReader.recorded?.last, "Slide 2 of 2")
        c.selectSlide(0)
        XCTAssertEqual(ScreenReader.recorded?.last, "Slide 1 of 2")
    }

    func testSelectingAShapeSaysNameKindTextAndPlace() {
        let c = DeckController()
        let box = c.addTextBox(at: Rect.fromLTWH(20, 20, 200, 60))
        box.text?.insertText("Quarterly review of the numbers for the whole team now")
        c.selectShapes([])
        ScreenReader.recorded = []
        c.selectShapes([box])
        let said = ScreenReader.recorded?.last ?? ""
        XCTAssertTrue(said.contains("text box") && said.contains("Quarterly review") && said.contains("top left") && said.contains(" of "), said)
        box.altText = "Chart of sales"
        c.selectShapes([])
        c.selectShapes([box])
        XCTAssertTrue((ScreenReader.recorded?.last ?? "").contains("Chart of sales"))
    }

    func testAltTextAndTitleOnAnyShapeSurviveSaveAndOpen() throws {
        let c = DeckController()
        let box = c.addTextBox(at: Rect.fromLTWH(20, 20, 200, 60))
        let shape = c.addShape(.rect)
        let chart = c.addChart(.column)
        for (s, d, t) in [(box, "Heading \"one\" & more", "Top"), (shape, "A red box", "Box"), (chart, "Sales by quarter", "Sales")] {
            c.selectShapes([s]); c.setAltText(d, title: t)
        }
        // Saved and opened again (twice: the second save patches the kept elements).
        func reopen(_ d: DeckController) throws -> DeckController {
            let (st, th, pk) = try Pptx.read(try Pptx.write(d))
            let n = DeckController(); n.load(st, theme: th, package: pk); return n
        }
        let once = try reopen(c)
        let twice = try reopen(once)
        for d in [once, twice] {
            let alts = d.slides[0].shapes.map { [$0.altText ?? "", $0.altTitle ?? ""] }
            XCTAssertTrue(alts.contains(["Heading \"one\" & more", "Top"]), "\(alts)")
            XCTAssertTrue(alts.contains(["A red box", "Box"]), "\(alts)")
            XCTAssertTrue(alts.contains(["Sales by quarter", "Sales"]), "\(alts)")
        }
        // Editing it on a kept shape changes the saved file.
        let kept = twice.slides[0].shapes.first { $0.altText == "A red box" }!
        twice.selectShapes([kept]); twice.setAltText("A blue box", title: "")
        let third = try reopen(twice)
        XCTAssertTrue(third.slides[0].shapes.contains { $0.altText == "A blue box" && $0.altTitle == nil })
    }

    func testSlideThumbnailsAreKeyboardStopsWithNames() {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        ui.pump()
        XCTAssertTrue(KeyboardTraversal.shared.reachable().contains { $0.label() == "Slide 1" })
    }

    func testOpeningADialogSaysItsTitle() {
        let ui = app(DialogShell(title: "Subtotal", page: Text("x"), onOK: {}, onCancel: {}))
        ui.pump()
        XCTAssertEqual(ScreenReader.recorded?.last, "Subtotal dialog")
    }

    func testUndoAndRedoSayWhatTheyDidInWriter() {
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        ui.pump()
        let c = OfficeSession().controller
        c.insertText("hello")
        c.undo()
        XCTAssertEqual(ScreenReader.recorded?.last, "Undo Typing")
        Thread.sleep(forTimeInterval: 0.3)
        c.redo()
        XCTAssertEqual(ScreenReader.recorded?.last, "Redo Typing")
        Thread.sleep(forTimeInterval: 0.3)
        c.redo()
        XCTAssertEqual(ScreenReader.recorded?.last, "Nothing to redo")
    }

    func testFindSaysWhichMatchOfHowManyInSheets() {
        let c = WorkbookController()
        c.setInput("a", at: CellAddress(row: 0, col: 0)); c.setInput("a", at: CellAddress(row: 1, col: 0))
        c.setInput("a", at: CellAddress(row: 2, col: 0))
        let p = try! TextPattern("a", FindOptions())
        c.select(CellAddress(row: 0, col: 0))
        XCTAssertTrue(c.findNext(p, scope: 0))
        let at = c.findPosition(p, scope: 0)
        XCTAssertEqual(at?.index, 2); XCTAssertEqual(at?.total, 3)
    }

    func testSheetsAltPatchSetsAndClearsDescrAndTitle() {
        let raw = "<xdr:graphicFrame><xdr:nvGraphicFramePr><xdr:cNvPr id=\"2\" name=\"Chart 1\" descr=\"old\"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr></xdr:graphicFrame>"
        let a = SheetDrawingsXML._patchAlt(raw, "Sales by year", "Sales")
        XCTAssertTrue(a.contains("descr=\"Sales by year\""))
        XCTAssertTrue(a.contains("title=\"Sales\""))
        XCTAssertFalse(a.contains("old"))
        let b = SheetDrawingsXML._patchAlt(a, nil, nil)
        XCTAssertFalse(b.contains("descr")); XCTAssertFalse(b.contains("title"))
        XCTAssertTrue(b.contains("name=\"Chart 1\"/>"))
    }

    /// Sheets: a picture and a chart keep their alt text and title through save and open.
    /// With ALT_LAB_DIR set, the saved .xlsx and a .pptx are left there for Office to open.
    func testSheetsAltTextAndTitleOnPictureAndChartSurviveSaveAndOpen() throws {
        let c = WorkbookController()
        let rows = [["Month", "Sales"], ["Jan", "10"], ["Feb", "20"]]
        var items: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (col, v) in row.enumerated() { items.append((CellAddress(row: r, col: col), v)) } }
        c.setInputs(items)
        c.select(CellAddress("B2")!)
        XCTAssertTrue(c.insertChart(.column))
        c.setDrawingAlt(0, "Sales by month & year", title: "Sales")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        XCTAssertTrue(c.insertPicture(name: "dot.png", data: png, width: 40, height: 40))
        c.setDrawingAlt(1, "A red \"dot\"", title: "Dot")
        func reopen(_ w: WorkbookController) throws -> (WorkbookController, Data) {
            let data = try Xlsx.write(w.book)
            let n = WorkbookController(); n.load(try Workbook.open(data, name: "t.xlsx")); return (n, data)
        }
        let (once, saved) = try reopen(c)
        let alts = { (w: WorkbookController) in w.sheet.drawings.map { [$0.descr ?? "", $0.title ?? ""] } }
        XCTAssertEqual(alts(once), [["Sales by month & year", "Sales"], ["A red \"dot\"", "Dot"]])
        // Kept drawings: changing the alt text again patches the read element.
        once.setDrawingAlt(0, "Monthly sales", title: "")
        let (twice, _) = try reopen(once)
        XCTAssertEqual(alts(twice), [["Monthly sales", ""], ["A red \"dot\"", "Dot"]])
        if let dir = ProcessInfo.processInfo.environment["ALT_LAB_DIR"] {
            try saved.write(to: URL(fileURLWithPath: dir + "/sheets-alt.xlsx"))
            let d = DeckController()
            let box = d.addTextBox(at: Rect.fromLTWH(20, 20, 200, 60))
            let shape = d.addShape(.rect)
            let chart = d.addChart(.column)
            for (s, a, t) in [(box, "Heading text box", "Top"), (shape, "A red box", "Box"), (chart, "Sales by quarter", "Sales")] {
                d.selectShapes([s]); d.setAltText(a, title: t)
            }
            try Pptx.write(d).write(to: URL(fileURLWithPath: dir + "/slides-alt.pptx"))
        }
    }

    func testASlideSorterTileIsReadAsSlideOneNotABareNumber() {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        ui.pump()
        guard let sorter = ui.semantics().first(where: { $0.label == "Slide Sorter" })?.tap else { return XCTFail("no Slide Sorter button") }
        sorter()
        ui.pump()
        let nodes = ui.semantics()
        XCTAssertTrue(nodes.contains { $0.label == "Slide 1" && $0.isSelected == true && $0.tap != nil }, "\(nodes.map { $0.label })")
        XCTAssertFalse(nodes.contains { $0.label == "1" })
        ui.dispose()
    }
}
