import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// The Writer shell built headless: its ribbon is on screen and a tab can be tapped by its label.
final class UIShellHarnessTests: XCTestCase {
    func testTheWriterShellBuildsAndShowsItsRibbonTabs() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        XCTAssertTrue(ui.has(text: "Insert"))
        XCTAssertFalse(ui.texts().contains("Table"), "Table is on the Insert tab, not Home")
        XCTAssertTrue(ui.tap(text: "Insert"))
        XCTAssertTrue(ui.texts().contains("Table"))
        XCTAssertFalse(ui.texts().contains("Format Painter"))
        XCTAssertNotNil(ui.state(OfficeShellState.self))
    }

    private func app(_ home: Widget) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Size(1280, 800))
    }

    func testTheSlidesShellBuildsAndItsTabsTap() {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        XCTAssertNotNil(ui.state(SlidesShellState.self))
        XCTAssertTrue(ui.has(text: "Insert"))
        XCTAssertTrue(ui.tap(text: "Insert"))
    }

    /// S-P0-4: a deck has no painter or paragraph marks. (Fit now works: S-VW-1.)
    func testSlidesShowsNoControlThatCannotWork() {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        let tips = ui.tips().joined(separator: "|")
        XCTAssertFalse(tips.contains("Format Painter"))
        XCTAssertFalse(tips.contains("Show/Hide"))
        XCTAssertTrue(tips.contains("Fit slide"), "S-VW-1: Fit slide to window does something now")
        XCTAssertTrue(tips.contains("Font Color"), "the colour menu stays")
    }

    func testTheSheetsShellBuildsAndItsTabsTap() {
        let ui = app(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))
        XCTAssertNotNil(ui.state(SheetsShellState.self))
        XCTAssertTrue(ui.has(text: "Insert"))
        XCTAssertTrue(ui.tap(text: "Insert"))
    }

    func testAnIconOnlyButtonIsFoundByItsTooltip() {
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        XCTAssertFalse(ui.tips().isEmpty, "the ribbon has icon buttons with tooltips")
        let tip = ui.tips()[0]
        XCTAssertTrue(ui.has(tip: tip))
        XCTAssertTrue(ui.tap(tip: tip))
        XCTAssertFalse(ui.tap(tip: "no such button"))
    }

    func testKeysAndTextReachTheFocusedField() {
        let controller = TextEditingController()
        var enters = 0
        let ui = app(Column(children: [
            SizedBox(width: 200, height: 30, child: FluentTextBox(controller: controller, onSubmitted: { _ in enters += 1 })),
        ]))
        let box = ui.elements().first { $0.widget is FluentTextBox }!
        let r = box.findRenderObject() as! RenderBox
        ui.tap(at: r.localToGlobal(Offset(r.size.width / 2, r.size.height / 2)))
        ui.type("ab")
        XCTAssertEqual(controller.text, "ab")
        ui.press(.backspace)
        XCTAssertEqual(controller.text, "a")
        ui.press(.enter)
        XCTAssertEqual(enters, 1)
    }

    /// W-OB-2: selecting a picture that sits in a line of text opens the Picture Format tab, and its Half Size button reaches the model.
    func testSelectingAnInlinePictureOpensPictureFormatAndHalfSizeResizesIt() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let state = try XCTUnwrap(ui.state(OfficeShellState.self))
        let c = state.session.controller
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        var p = RichParagraph(text: "a" + RichParagraph.inlineImageCharacter + "b")
        let image = ImageAttachment(data: png, width: 120, height: 90)
        p.inlineImages[image.id] = image
        p.applyStyle(1 ..< 2) { $0.inlineImage = image.id }
        c.load(RichDocument(paragraphs: [p]))
        XCTAssertFalse(ui.has(text: "Picture Format"))
        c.selectInlineImage(in: 0, id: image.id)
        ui.pump()
        XCTAssertTrue(ui.has(text: "Picture Format"))
        XCTAssertTrue(ui.tap(text: "Half Size"))
        XCTAssertEqual(c.document.paragraphs[0].inlineImages[image.id]?.width, 60)
        XCTAssertEqual(c.document.paragraphs[0].inlineImages[image.id]?.height, 45)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].inlineImages[image.id]?.width, 120)
    }

    /// W-ED-1: the Paste button is on the Home ribbon and the shell has wired every way of pasting
    /// (plain click, plain-text key, the four Paste Options) to the controller.
    func testPasteAndPasteOptionsAreWiredToTheShell() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        XCTAssertTrue(ui.has(text: "Paste"))
        let state = try XCTUnwrap(ui.state(OfficeShellState.self))
        XCTAssertNotNil(state.session.onPaste)
        XCTAssertNotNil(state.session.onPasteMode)
    }

    /// W-TB-2: the Table Layout tab's Borders and Shading menus reach the controller.
    func testTableLayoutBordersAndShadingReachTheController() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertTable(rows: 2, columns: 2)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        XCTAssertTrue(ui.has(text: "Borders & Shading"))
        XCTAssertTrue(ui.tap(text: "Borders"))
        XCTAssertTrue(ui.tap(text: "Bottom Border"))
        XCTAssertTrue(c.document.paragraphs.compactMap { $0.cell }.contains { ($0.bordersXML ?? "").contains("w:bottom") })
    }

    /// W-TB-3: the Table Layout tab's property controls reach the controller.
    func testTableLayoutPropertyControlsReachTheController() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertTable(rows: 2, columns: 2)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        XCTAssertTrue(ui.tap(text: "Cell Alignment"))
        XCTAssertTrue(ui.tap(text: "Align Middle"))
        XCTAssertEqual(c.currentCell?.verticalAlign, "center")
        XCTAssertTrue(ui.tap(text: "Table Alignment"))
        XCTAssertTrue(ui.tap(text: "Table Center"))
        XCTAssertEqual(c.currentTableStyle?.alignment, .center)
        XCTAssertTrue(ui.tap(text: "Row May Break"))
        XCTAssertEqual(c.currentTableStyle?.rowsCantSplit, [0])
        XCTAssertTrue(ui.tap(text: "AutoFit"))
        XCTAssertEqual(c.currentTableStyle?.fixedLayout, true)
    }

    /// S-PI-1a: Picture Format > Alt Text reaches the dialog, typing and OK set the text, Esc cancels.
    func testAltTextButtonOpensTheDialogAndAppliesOrCancels() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let pic = deck.addPicture(ImageAttachment(data: png, width: 1, height: 1), naturalSize: Size(100, 100))
        deck.selectShapes([pic])
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Picture Format"))
        XCTAssertTrue(ui.tap(text: "Alt Text"))
        XCTAssertTrue(ui.has(text: "How would you describe this object and its context to someone who is blind?"))
        XCTAssertTrue(ui.press(.escape))
        XCTAssertFalse(ui.has(text: "Cancel"))
        XCTAssertNil(pic.altText)
        XCTAssertTrue(ui.tap(text: "Alt Text"))
        let box = try XCTUnwrap(ui.elements().last { $0.widget is FluentTextBox })
        let r = try XCTUnwrap(box.findRenderObject() as? RenderBox)
        ui.tap(at: r.localToGlobal(Offset(r.size.width / 2, r.size.height / 2)))
        ui.type("A red square")
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertEqual(pic.altText, "A red square")
    }

    func testTextOptionsButtonOpensTheDialogAndAppliesOrCancels() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        let box = deck.addTextBox(at: Rect.fromLTWH(100, 100, 300, 120))
        deck.selectShapes([box])
        ui.pump()
        let before = try XCTUnwrap(deck.selectedTextOptions)
        XCTAssertTrue(ui.tap(text: "Text Options"))
        XCTAssertTrue(ui.has(text: "Vertical position"))
        XCTAssertTrue(ui.tap(id: "text-anchor-middle"))
        XCTAssertTrue(ui.press(.escape))
        XCTAssertEqual(deck.selectedTextOptions, before)
        XCTAssertTrue(ui.tap(text: "Text Options"))
        XCTAssertTrue(ui.tap(id: "text-anchor-middle"))
        XCTAssertTrue(ui.tap(id: "text-dir-rotate270"))
        XCTAssertTrue(ui.tap(id: "text-fit-shrink"))
        XCTAssertTrue(ui.tap(id: "text-wrap"))
        XCTAssertTrue(ui.tap(text: "OK"))
        let o = try XCTUnwrap(deck.selectedTextOptions)
        XCTAssertEqual(o.anchor, .middle)
        XCTAssertEqual(o.direction, .rotate270)
        XCTAssertEqual(o.fit, .shrink)
        XCTAssertEqual(o.wrap, !before.wrap)
    }

    /// S-TB-1a: selecting a table opens Table Design; its two switches reach the deck.
    func testSelectedTableOpensTableDesignAndTheSwitchesApply() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        let t = deck.addTable(rows: 2, columns: 2)
        deck.selectShapes([t])
        ui.pump()
        XCTAssertTrue(ui.has(text: "Table Design"))
        XCTAssertTrue(ui.tap(text: "Header Row"))
        XCTAssertEqual(deck.selectedTableOptions?.headerRow, false)
        XCTAssertTrue(ui.tap(text: "Banded Rows"))
        XCTAssertEqual(deck.selectedTableOptions?.bandedRows, false)
        XCTAssertTrue(ui.tap(text: "Header Row"))
        XCTAssertEqual(deck.selectedTableOptions?.headerRow, true)
    }
}

/// X-P0-3: the Sheets title bar's Undo and Redo follow the workbook, and Find names the workbook.
final class SheetsTitleBarUndoHarnessTests: XCTestCase {
    func testTitleBarUndoRedoFollowTheWorkbook() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        let shell = try XCTUnwrap(ui.state(SheetsShellState.self))
        XCTAssertFalse(shell.session.summary.canUndo)
        shell.wb.setInput("5", at: CellAddress("A1")!)
        XCTAssertTrue(shell.session.summary.canUndo)
        XCTAssertFalse(shell.session.summary.canRedo)
        shell.session.onUndo?()
        XCTAssertFalse(shell.session.summary.canUndo)
        XCTAssertTrue(shell.session.summary.canRedo)
    }

    /// W-OB-1: Rotate Right and Rotate Left on the Picture Format tab turn a picture in its own paragraph, one undo step each.
    func testRotateButtonsTurnAPictureInItsOwnParagraph() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = try XCTUnwrap(ui.state(OfficeShellState.self)).session.controller
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        c.load(RichDocument(paragraphs: [RichParagraph(image: ImageAttachment(data: png, width: 200, height: 100))]))
        c.selectImage(at: 0)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Rotate Right"))
        XCTAssertEqual(c.document.paragraphs[0].image?.rotation, 90)
        XCTAssertEqual(c.document.paragraphs[0].image?.width, 100)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Rotate Left"))
        XCTAssertEqual(c.document.paragraphs[0].image?.rotation, 0)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].image?.rotation, 90)
    }

    /// W-TB-1: the Select menu and the Insert Table dialog reach the controller.
    func testTableSelectAndInsertTableDialogReachTheController() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        XCTAssertTrue(ui.tap(text: "Insert"))
        XCTAssertTrue(ui.tap(text: "Table"))
        XCTAssertTrue(ui.tap(text: "Insert Table…"))
        XCTAssertTrue(ui.has(text: "Number of columns"))
        XCTAssertTrue(ui.tap(text: "AutoFit to window"))
        XCTAssertTrue(ui.tap(text: "OK"))
        let cells = c.document.paragraphs.compactMap { $0.cell }
        XCTAssertEqual(cells.count, 10, "the default 5 x 2 grid")
        XCTAssertEqual(c.currentTableStyle?.widthPercent, 100)
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        XCTAssertTrue(ui.tap(text: "Select"))
        XCTAssertTrue(ui.tap(text: "Select Column"))
        c.setCellShading(Color(0xFFDDEEFF))
        XCTAssertEqual(c.document.paragraphs.compactMap { $0.cell }.filter { $0.fill != nil }.count, 2)
    }

    /// W-TB-2: the Borders and Shading dialog applies sides, line and shading as one undo.
    func testBordersAndShadingDialogReachesTheController() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertTable(rows: 2, columns: 2)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        XCTAssertTrue(ui.tap(text: "Borders"))
        XCTAssertTrue(ui.tap(text: "Borders and Shading…"))
        XCTAssertTrue(ui.has(text: "Apply to"))
        XCTAssertTrue(ui.tap(text: "Bottom"))
        XCTAssertTrue(ui.tap(text: "Double"))
        XCTAssertTrue(ui.tap(text: "3"))
        XCTAssertTrue(ui.tap(text: "Automatic"))          // opens the line colour panel
        XCTAssertTrue(ui.has(text: "Theme Colors"))
        XCTAssertTrue(ui.tap(tip: "Accent 2"))
        XCTAssertTrue(ui.tap(text: "Unchanged"))          // opens the shading panel
        XCTAssertTrue(ui.tap(tip: "Accent 1"))
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertEqual(c.currentCell?.fill, Color(Int64(0xFF4472C4)))
        let xml = c.currentCell?.bordersXML ?? ""
        XCTAssertTrue(xml.contains("ED7D31"), "the picked theme colour is the line colour")
        XCTAssertTrue(xml.contains("w:bottom"))
        XCTAssertTrue(xml.contains("double"))
        XCTAssertTrue(xml.contains("w:sz=\"24\""))
        c.undo()
        XCTAssertNil(c.currentCell?.bordersXML)
    }
}
