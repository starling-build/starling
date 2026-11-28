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

    /// The tester's view outlives one tester: a later one that asks for another size gets it (it used to keep the first one's,
    /// so a test that needed a wide window ran at whatever width the first test of the process had).
    func testATesterTakesTheSizeItAsksForWhateverAnEarlierOneAsked() {
        let narrow = WidgetTester(SizedBox(width: 10, height: 10, child: nil), size: Size(640, 480))
        XCTAssertEqual(narrow.renderView.configuration.logicalConstraints.maxWidth, 640)
        narrow.dispose()
        let wide = WidgetTester(SizedBox(width: 10, height: 10, child: nil), size: Size(1500, 800))
        XCTAssertEqual(wide.renderView.configuration.logicalConstraints.maxWidth, 1500)
        XCTAssertEqual(wide.renderView.configuration.logicalConstraints.maxHeight, 800)
        wide.dispose()
    }

    /// W-RV-3: a click on a check box control flips it; a click beside it does not.
    func testClickingACheckBoxControlFlipsIt() {
        var p = RichParagraph(text: "Agree \u{2610} yes")
        p.controlMarkers = [
            RichControlMarker(id: 1, properties: "<w:sdtPr><w14:checkbox><w14:checked w14:val=\"0\"/><w14:checkedState w14:val=\"2612\"/><w14:uncheckedState w14:val=\"2610\"/></w14:checkbox></w:sdtPr>", offset: 6),
            RichControlMarker(id: 1, offset: 7),
        ]
        let controller = RichDocumentController(document: RichDocument(paragraphs: [p]))
        let ui = app(SizedBox(width: 600, height: 300, child: RichEditable(controller: controller)))
        let box = ui.elements().first { $0.widget is RichEditable }!
        let r = box.findRenderObject() as! RenderBox
        func state() -> Bool? { controller.document.paragraphs[0].checkBoxes.first?.checked }
        XCTAssertEqual(state(), false)
        // Far right of the line: nothing there.
        // (A mouse: a touch tap on the line raises the caret's knob, and where the text ends depends on the platform's font, so on
        // macOS the knob sat over the glyph and took the next taps.)
        ui.click(at: r.localToGlobal(Offset(500, 34)), kind: .mouse)
        XCTAssertEqual(state(), false)
        // Walk along the line until the glyph is hit.
        var x = 24.0
        while x < 200, state() == false {
            // (and down the line's height, which is the platform font's: 34 was the middle of it on Linux)
            for y in stride(from: 16.0, through: 40, by: 6) where state() == false { ui.click(at: r.localToGlobal(Offset(x, y)), kind: .mouse) }
            x += 2
        }
        XCTAssertEqual(state(), true, "a click on the glyph flips the box")
        XCTAssertEqual(controller.document.paragraphs[0].text, "Agree \u{2612} yes")
        controller.undo()
        XCTAssertEqual(state(), false)
    }

    /// W-OB-3/4: a real pointer press on a text box selects it, a drag moves it, a click on the selected box enters its text.
    func testPointerSelectsDragsAndEntersATextBox() throws {
        let controller = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "Some body text before the box.")]))
        controller.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "Boxed")))
        let at = try XCTUnwrap(controller.document.paragraphs.firstIndex { $0.image?.textBox != nil }, "the box is a paragraph of its own")
        controller.selectImage(at: at)
        var rect: Rect?
        var entered = 0
        let ui = app(SizedBox(width: 800, height: 600, child: RichEditable(
            controller: controller, onTextBoxEnter: { _, _, _ in entered += 1 }, onBoxRect: { rect = $0 })))
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let editor = try XCTUnwrap(ui.elements().first { $0.widget is RichEditable })
        let box = try XCTUnwrap(editor.findRenderObject() as? RenderBox)
        let r = try XCTUnwrap(rect, "the inserted box is selected and drawn")
        let centre = box.localToGlobal(r.center)
        func floatX() -> Double? {
            controller.document.paragraphs.compactMap { $0.image?.float?.x }.first
                ?? controller.document.paragraphs.compactMap { $0.inlineImages.inOrder.first?.float?.x }.first
        }
        let x0 = floatX()
        ui.drag(from: centre, to: Offset(centre.dx + 40, centre.dy + 20), kind: .mouse)
        ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        if let a = x0, let b = floatX() { XCTAssertGreaterThan(b, a, "dragging the selected box moves it right") }
        XCTAssertEqual(entered, 0, "a drag does not enter the text")
        let r2 = try XCTUnwrap(rect)
        ui.click(at: box.localToGlobal(r2.center), kind: .mouse)
        XCTAssertEqual(entered, 1, "a click on the selected box enters its text")
    }

    /// A finger has no Shift: with Select Multiple on, a touch tap on another floating shape picks it along with the selected one (a
    /// second tap drops it); with it off, the same tap just selects that shape.
    func testSelectMultipleLetsAFingerPickShapesToGroup() throws {
        let controller = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "Some body text before the shapes.")]))
        for (n, preset) in ["rect", "ellipse"].enumerated() {
            controller.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: preset, width: w, height: h, number: n + 1, page: (x, y)) }
            XCTAssertTrue(controller.placePendingShape(x: 60 + Double(n) * 220, y: 140, width: 120, height: 80, at: RichPosition(paragraph: 0, offset: 0)))
        }
        let shapes = controller.document.paragraphs.indices.filter { controller.document.paragraphs[$0].image?.float != nil }
        XCTAssertEqual(shapes.count, 2)
        var rect: Rect?
        let ui = app(SizedBox(width: 800, height: 600, child: RichEditable(controller: controller, onBoxRect: { rect = $0 })))
        func settle() { for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) } }
        settle()
        let editor = try XCTUnwrap(ui.elements().first { $0.widget is RichEditable })
        let box = try XCTUnwrap(editor.findRenderObject() as? RenderBox)
        func centre(of index: Int) throws -> Offset {
            controller.selectImage(at: index); settle()
            return box.localToGlobal(try XCTUnwrap(rect, "shape \(index) is selected and drawn").center)
        }
        let second = try centre(of: shapes[1])
        let first = try centre(of: shapes[0])
        XCTAssertEqual(controller.selectedImageIndex, shapes[0])
        // Off: a tap on the other shape selects it, nothing is picked.
        ui.tap(at: second, kind: .touch); settle()
        XCTAssertEqual(controller.selectedImageIndex, shapes[1])
        XCTAssertEqual(controller.pickedShapeIndexes, [shapes[1]])
        controller.selectImage(at: shapes[0]); settle()
        // On: the same tap picks it along with the selected one; another tap drops it again.
        controller.setSelectMultiple(true)
        ui.tap(at: second, kind: .touch); settle()
        XCTAssertEqual(controller.selectedImageIndex, shapes[0], "the first stays the selected one")
        XCTAssertEqual(controller.pickedShapeIndexes, shapes)
        ui.tap(at: second, kind: .touch); settle()
        XCTAssertEqual(controller.pickedShapeIndexes, [shapes[0]])
        _ = first
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

    /// W-TB-7: the Table Design tab's Table Style Options reach the controller.
    func testTableDesignOptionsReachTheController() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertTable(rows: 2, columns: 2)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Design"))
        XCTAssertTrue(ui.has(text: "Table Style Options"))
        let t = c.currentCell!.table
        XCTAssertTrue(ui.tap(text: "Total Row"))
        XCTAssertNotEqual(c.tableLook(of: t) & TableLook.lastRow, 0)
        XCTAssertTrue(ui.tap(text: "Banded Rows"))
        XCTAssertNotEqual(c.tableLook(of: t) & TableLook.noRowBands, 0)
    }

    /// W-PA-4: Home's Borders menu and Shading colour reach the controller, for a paragraph outside any table.
    func testHomeParagraphBordersAndShadingReachTheController() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Borders"))
        XCTAssertTrue(ui.tap(text: "Bottom Border"))
        XCTAssertNotNil(c.document.paragraphs[0].style.borders?.bottom)
        XCTAssertNil(c.document.paragraphs[0].style.borders?.top)
        XCTAssertTrue(ui.tap(text: "Borders"))
        XCTAssertTrue(ui.tap(text: "No Border"))
        XCTAssertNil(c.document.paragraphs[0].style.borders)
    }

    /// W-TB-8: Select > Table Properties opens the dialog; Row tab, "Allow row to break" off, OK reaches the controller.
    func testTablePropertiesDialogReachesTheController() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertTable(rows: 2, columns: 2)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        XCTAssertTrue(ui.tap(text: "Select"))
        XCTAssertTrue(ui.tap(text: "Table Properties…"))
        XCTAssertTrue(ui.tap(text: "Row"))
        XCTAssertTrue(ui.tap(text: "Allow row to break across pages"))
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertTrue(c.currentTableStyle?.rowsCantSplit.contains(c.currentCell?.row ?? 0) == true)
    }

    /// Every control of the Table Layout tab is within reach in a 1280 window: on the tab, or in the popup of a group that
    /// gave way (the tab is wider than the 1240 pt the ribbon has there, so RibbonFit folds its right-hand groups).
    func testTableLayoutTabFitsAt1280WithDrawAndEraser() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertTable(rows: 2, columns: 2)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        for label in ["Select", "Merge", "Cell Alignment", "Table Alignment", "Table Width", "Cell Margins", "AutoFit", "Row May Break",
                      "Repeat Header: Off", "Delete Table", "Row Height", "Indent", "Distribute Columns", "Borders", "Line Style", "Line Width",
                      "Header Row", "Insert Above", "Delete Column"] {
            XCTAssertTrue(ui.ribbonReaches(label, width: 1280), "\(label) is out of reach on the Table Layout tab")
        }
    }

    /// Draw Table, Eraser and Split Table: the Eraser sets the table tool (2000 wide, so the Draw group is on screen).
    func testTableLayoutEraserSetsTheTableTool() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(2000, 800))
        ui.state(OfficeShellState.self)!.session.controller.insertTable(rows: 2, columns: 2)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        XCTAssertTrue(ui.tap(text: "Select"))
        XCTAssertTrue(ui.tap(text: "Eraser"))
        XCTAssertEqual(ui.state(OfficeShellState.self)!.session.tableTool, "erase")
    }

    /// W-TB-2: the Table Layout tab's Borders and Shading menus reach the controller.
    func testTableLayoutBordersAndShadingReachTheController() {
        // (2000 wide: the Table Layout ribbon is wider than the 1240 a 1280 window gives it on macOS, where the UI font is wider than
        // on Linux, so the Borders & Shading group sat past the viewport's edge and a tap on it hit the page.)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(2000, 800))
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
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(2000, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertTable(rows: 2, columns: 2)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        XCTAssertTrue(ui.tap(text: "Cell Alignment"))
        XCTAssertTrue(ui.tap(text: "Align Center Left"))
        XCTAssertEqual(c.currentCell?.verticalAlign, "center")
        XCTAssertTrue(ui.tap(text: "Table Alignment"))
        XCTAssertTrue(ui.tap(text: "Table Center"))
        XCTAssertEqual(c.currentTableStyle?.alignment, .center)
        XCTAssertTrue(ui.tap(text: "Row May Break"))
        XCTAssertEqual(c.currentTableStyle?.rowsCantSplit, [0])
        XCTAssertTrue(ui.tap(text: "AutoFit"))
        XCTAssertTrue(ui.tap(text: "Fixed Column Width"))
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

    /// S-PI-1b: Slides' Picture Format > Change Picture asks the host for a file (the swap is DeckController.changePictures,
    /// tested in SlideIdentityTests; decoding the chosen file needs the engine, which a harness test lacks).
    func testSlidesChangePictureAsksForAFile() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let pic = deck.addPicture(ImageAttachment(data: png, width: 1, height: 1), naturalSize: Size(100, 100))
        deck.selectShapes([pic])
        ui.pump()
        var asked = false
        defer { OfficeScene.main.pictureRequested = nil }
        OfficeScene.main.pictureRequested = { _ in asked = true }
        XCTAssertTrue(ui.tap(text: "Picture Format"))
        XCTAssertTrue(ui.tap(text: "Change Picture"))
        XCTAssertTrue(asked)
    }

    func testSlidesPictureTransparencyMenuSetsTheAmount() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let pic = deck.addPicture(ImageAttachment(data: png, width: 1, height: 1), naturalSize: Size(100, 100))
        deck.selectShapes([pic])
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Picture Format"))
        XCTAssertTrue(ui.tap(text: "Transparency"))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Transparency: 50%"))
        ui.pump()
        XCTAssertEqual(pic.pictureAlpha, 0.5, accuracy: 1e-9)
        deck.undo()
        XCTAssertEqual(deck.currentSlide.shapes.first { $0.picture != nil }?.pictureAlpha ?? 0, 1, accuracy: 1e-9)
    }

    func testSlidesChangePictureTakesTheScriptStandInPicker() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let pic = deck.addPicture(ImageAttachment(data: png, width: 1, height: 1), naturalSize: Size(100, 100))
        let before = try XCTUnwrap(pic.picture?.id)
        deck.selectShapes([pic])
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("office-pick-\(getpid()).png").path
        XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: png))
        setenv("OFFICE_PICK_PICTURE", path, 1)
        defer { unsetenv("OFFICE_PICK_PICTURE"); try? FileManager.default.removeItem(atPath: path) }
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Picture Format"))
        XCTAssertTrue(ui.tap(text: "Change Picture"))
        // The picture decodes on a task: run the main loop until it lands.
        let end = Date().addingTimeInterval(5)
        while deck.currentSlide.shapes.first(where: { $0.picture != nil })?.picture?.id == before, Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05)); ui.pump()
        }
        let now = try XCTUnwrap(deck.currentSlide.shapes.first { $0.picture != nil })
        XCTAssertNotEqual(now.picture?.id, before, "the stand-in picture replaced the old one")
        XCTAssertEqual(deck.currentSlide.shapes.filter { $0.picture != nil }.count, 1, "replaced, not inserted")
    }

    func testSlidesCropHandleOverAnotherShapeCropsOnlyThePicture() throws {
        // A text box lying across the picture's top edge, once below the picture and once above it: the top crop
        // handle drawn over it takes the press, so only the crop changes and crop mode stays on.
        for boxOnTop in [false, true] {
            let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1440, 932))
            let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
            let deck = try XCTUnwrap(shell.session.deck)
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
            var box: SlideShape? = nil
            if !boxOnTop { box = deck.addTextBox(at: Rect.fromLTWH(0, 0, 10, 10)) }
            let pic = deck.addPicture(ImageAttachment(data: png, width: 1, height: 1), naturalSize: Size(100, 100))
            if boxOnTop { box = deck.addTextBox(at: Rect.fromLTWH(0, 0, 10, 10)) }
            let tb = try XCTUnwrap(box)
            let f0 = pic.frame
            tb.frame = Rect.fromLTWH(f0.left - 20, f0.top - 15, f0.width + 40, 30)
            let tb0 = tb.frame
            deck.selectShapes([pic])
            ui.pump()
            XCTAssertTrue(ui.tap(text: "Picture Format"))
            XCTAssertTrue(ui.tap(text: "Crop"))
            ui.pump()
            XCTAssertTrue(deck.cropping === pic)
            let canvas = try XCTUnwrap(ui.state(SlideCanvasState.self))
            let from = try XCTUnwrap(canvas.globalPoint(ofSlide: Offset(f0.center.dx, f0.top)))
            let to = try XCTUnwrap(canvas.globalPoint(ofSlide: Offset(f0.center.dx, f0.top + f0.height / 4)))
            ui.drag(from: from, to: to)
            ui.pump()
            XCTAssertEqual(tb.frame, tb0, "the text box under the handle stays put (box on top: \(boxOnTop))")
            XCTAssertEqual(pic.crop?.top ?? 0, 0.25, accuracy: 0.02, "box on top: \(boxOnTop)")
            XCTAssertTrue(deck.cropping === pic, "crop mode stays on (box on top: \(boxOnTop))")
            XCTAssertEqual(deck.selection.count, 1)
            XCTAssertTrue(deck.selection.first === pic)
        }
    }

    func testSlidesCropButtonTurnsCropModeOnAndEnterEndsIt() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let pic = deck.addPicture(ImageAttachment(data: png, width: 1, height: 1), naturalSize: Size(100, 100))
        deck.selectShapes([pic])
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Picture Format"))
        XCTAssertTrue(ui.tap(text: "Crop"))
        ui.pump()
        XCTAssertTrue(deck.cropping === pic)
        XCTAssertTrue(ui.tap(text: "Crop"), "pressed again, Crop applies and ends")
        ui.pump()
        XCTAssertNil(deck.cropping)
        XCTAssertTrue(deck.selection.first === pic, "the picture stays selected")
        XCTAssertTrue(ui.tap(text: "Crop"))
        ui.pump()
        XCTAssertNotNil(deck.cropping)
        ui.press(.enter)
        ui.pump()
        XCTAssertNil(deck.cropping, "Enter applies the crop")
        // In crop mode the left handle crops: dragged a quarter of the way in, a quarter of the picture is cut and the
        // picture stays where it was. One undo step takes it back.
        XCTAssertTrue(ui.tap(text: "Crop"))
        ui.pump()
        let canvas = try XCTUnwrap(ui.state(SlideCanvasState.self))
        let f0 = pic.frame
        let from = try XCTUnwrap(canvas.globalPoint(ofSlide: Offset(f0.left, f0.center.dy)))
        let to = try XCTUnwrap(canvas.globalPoint(ofSlide: Offset(f0.left + f0.width / 4, f0.center.dy)))
        ui.drag(from: from, to: to)
        ui.pump()
        XCTAssertEqual(pic.crop?.left ?? 0, 0.25, accuracy: 0.02)
        XCTAssertEqual(pic.frame.right, f0.right, accuracy: 0.01)
        XCTAssertEqual(pic.frame.width, f0.width * 0.75, accuracy: f0.width * 0.02)
        // The cut-away quarter shows as the picture itself, faded, in one band left of the frame.
        let ghost = try XCTUnwrap(ui.elements().compactMap { ($0.widget as? CustomPaint)?.painter as? CropGhostPainter }.first)
        XCTAssertEqual(ghost.bands.count, 1)
        XCTAssertEqual(ghost.full.width, ghost.bands[0].width * 4, accuracy: 1)
        // A drag inside the frame slides the picture under it: dragged right by an eighth of the picture, the left cut
        // shrinks by as much, the right one grows, and the frame stays put. One undo step.
        let f1 = pic.frame, full = f0.width
        let a = try XCTUnwrap(canvas.globalPoint(ofSlide: f1.center))
        let b = try XCTUnwrap(canvas.globalPoint(ofSlide: Offset(f1.center.dx + full / 8, f1.center.dy)))
        ui.drag(from: a, to: b)
        ui.pump()
        XCTAssertEqual(pic.frame, f1)
        XCTAssertEqual(pic.crop?.left ?? 0, 0.125, accuracy: 0.02)
        XCTAssertEqual(pic.crop?.right ?? 0, 0.125, accuracy: 0.02)
        XCTAssertTrue(deck.cropping === pic, "still cropping")
        deck.undo()
        XCTAssertEqual(try XCTUnwrap(deck.currentSlide.shapes.first { $0.picture != nil }).crop?.left ?? 0, 0.25, accuracy: 0.02)
        deck.undo()
        let back = try XCTUnwrap(deck.currentSlide.shapes.first { $0.picture != nil })
        XCTAssertEqual(back.frame, f0)
        XCTAssertNil(back.crop)
    }

    func testTextOptionsButtonOpensTheDialogAndAppliesOrCancels() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(2000, 800))
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

    /// S-TB-1g: in a Slides table cell, Table Layout is PowerPoint's: Cell Alignment and Cell Margins act on the
    /// cell, and Word's table-only buttons (Table Width, AutoFit, Indent) are not there.
    func testSlidesTableLayoutAlignsAndInsetsTheCell() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1440, 932))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        shell.session.onInsertTable?(2, 2)
        ui.pump(); ui.pump()
        let t = try XCTUnwrap(deck.currentSlide.shapes.first { $0.kind == .table })
        XCTAssertTrue(shell.session.summary.inCell)
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        ui.pump()
        for word in ["Table Width", "AutoFit", "Indent", "Table Alignment"] { XCTAssertFalse(ui.has(text: word), word) }
        func first() -> CellRef? { t.text?.document.paragraphs.first?.cell }
        XCTAssertTrue(ui.tap(text: "Cell Alignment"))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Align Bottom Center"))
        ui.pump()
        XCTAssertEqual(first()?.verticalAlign, "bottom")
        XCTAssertEqual(t.text?.document.paragraphs.first?.style.alignment, .center)
        XCTAssertTrue(ui.tap(text: "Cell Margins"))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Cell Margins: Wide"))
        ui.pump()
        XCTAssertEqual(first()?.padding, EdgeInsets(left: 10.8, top: 10.8, right: 10.8, bottom: 10.8))
        // Only the caret's cell moves.
        XCTAssertNil(t.text?.document.paragraphs.first { $0.cell?.column == 1 }?.cell?.verticalAlign)
    }

    /// S-TB-1g: the tab strip holds one Table Design tab and one Table Layout tab, and a click into a cell then typing
    /// puts the text in that cell (the cell is at 756,483 in the 1440x932 window: the new 2x2 table, 288x60 pt at 336,240).
    func testSlidesTableCellTakesTypingAndTheStripHasOneTableDesign() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1440, 932))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        shell.session.onInsertTable?(2, 2)
        ui.pump(); ui.pump()
        let t = try XCTUnwrap(deck.currentSlide.shapes.first { $0.kind == .table })
        XCTAssertEqual(ui.texts().filter { $0 == "Table Design" }.count, 1)
        XCTAssertEqual(ui.texts().filter { $0 == "Table Layout" }.count, 1)
        // Leave the table, then come back to its first cell by the mouse.
        deck.selectShapes([])
        ui.pump()
        let cell = Offset(756, 483)
        ui.click(at: cell, kind: .mouse); ui.pump()
        ui.click(at: cell, kind: .mouse); ui.pump()
        XCTAssertEqual(ui.texts().filter { $0 == "Table Design" }.count, 1)
        ui.type("Hi there")
        let first = t.text?.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 0 }
        XCTAssertEqual(first?.text, "Hi there")
    }

    /// S-TB-1h: Table Layout's Column Width sets the caret's column and the table's frame follows its grid; Table Size
    /// scales the columns and rows, the other side following with Lock Aspect Ratio on; the lock is saved.
    func testSlidesColumnWidthAndTableSize() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1440, 932))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        shell.session.onInsertTable?(2, 2)
        ui.pump(); ui.pump()
        let t = try XCTUnwrap(deck.currentSlide.shapes.first { $0.kind == .table })
        let c = shell.session.controller
        XCTAssertTrue(t.text === c)
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        ui.pump()
        for word in ["Column Width", "Table Size", "Lock Aspect Ratio", "288 pt"] { XCTAssertTrue(ui.has(text: word), word) }
        let w0 = t.frame.width, h0 = t.frame.height
        c.setColumnWidth(200, drawn: DeckController.drawnGrid(t))
        ui.pump(); ui.pump()
        XCTAssertEqual(t.text?.document.tableColumns[t.tableId ?? ""], [200, w0 / 2])
        XCTAssertEqual(t.frame.width, 200 + w0 / 2, accuracy: 0.01)
        XCTAssertTrue(ui.has(text: "200 pt"))
        // Undo takes the column and the frame back.
        c.undo(); ui.pump(); ui.pump()
        XCTAssertEqual(t.frame.width, w0, accuracy: 0.01)
        // Width with the lock off leaves the rows; with it on the rows scale too.
        c.scaleTable(kx: 1.5, rowsHeight: nil, drawn: DeckController.drawnGrid(t))
        ui.pump(); ui.pump()
        XCTAssertEqual(t.frame.width, w0 * 1.5, accuracy: 0.01)
        XCTAssertEqual(t.frame.height, h0, accuracy: 0.5)
        XCTAssertTrue(ui.tap(text: "Lock Aspect Ratio")); ui.pump()
        XCTAssertTrue(t.aspectLocked)
        c.scaleTable(kx: 2, rowsHeight: h0 * 2, drawn: DeckController.drawnGrid(t))
        ui.pump(); ui.pump()
        XCTAssertEqual(t.frame.width, w0 * 3, accuracy: 0.01)
        XCTAssertEqual(t.frame.height, h0 * 2, accuracy: 0.01)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let back = try XCTUnwrap(state.slides[0].shapes.first { $0.name == t.name })
        XCTAssertTrue(back.aspectLocked)
        XCTAssertEqual(back.frame.width, w0 * 3, accuracy: 0.5)
    }

    /// S-TB-1h: Cell Margins > Custom Margins opens Cell Text Layout; its four boxes (inches) set the caret cell's margins.
    func testSlidesCustomCellMargins() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1440, 932))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        shell.session.onInsertTable?(2, 2)
        ui.pump(); ui.pump()
        let t = try XCTUnwrap(deck.currentSlide.shapes.first { $0.kind == .table })
        XCTAssertTrue(ui.tap(text: "Table Layout")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Cell Margins")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Custom Margins…")); ui.pump()
        XCTAssertTrue(ui.has(text: "Internal margin"))
        XCTAssertTrue(ui.has(text: "0.1\""))
        XCTAssertTrue(ui.tap(id: "cellmargins.left"))
        for _ in 0..<6 { ui.press(.backspace) }
        ui.type("0.25"); ui.pump()
        XCTAssertTrue(ui.tap(id: "cellmargins.bottom"))
        for _ in 0..<6 { ui.press(.backspace) }
        ui.type("0"); ui.pump()
        XCTAssertTrue(ui.tap(text: "OK")); ui.pump()
        XCTAssertFalse(ui.has(text: "Internal margin"))
        XCTAssertEqual(t.text?.document.paragraphs.first?.cell?.padding, EdgeInsets(left: 18, top: 3.6, right: 7.2, bottom: 0))
        XCTAssertNil(t.text?.document.paragraphs.first { $0.cell?.column == 1 }?.cell?.padding)
    }

    /// S-TB-1i (the Mac's three #3349 bugs): Width with the lock on scales the height by the same ratio; Custom Margins
    /// leaves the frame as tall as its rows (it had grown 30 pt, a stray empty paragraph under the table); each edit is
    /// one undo that puts the frame and the rows back together.
    func testSlidesTableSizeMarginsAndUndo() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(1440, 932))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        shell.session.onInsertTable?(2, 2)
        ui.pump(); ui.pump()
        let t = try XCTUnwrap(deck.currentSlide.shapes.first { $0.kind == .table })
        let c = shell.session.controller
        ui.type("Hi"); ui.pump()
        let f0 = t.frame, n0 = c.document.paragraphs.count
        XCTAssertTrue(ui.tap(text: "Table Layout")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Lock Aspect Ratio")); ui.pump()
        let k = (f0.width + 14.4) / f0.width
        c.scaleTable(kx: k, rowsHeight: f0.height * k, drawn: DeckController.drawnGrid(t)); ui.pump(); ui.pump()
        XCTAssertEqual(t.frame.width, f0.width * k, accuracy: 0.01)
        XCTAssertEqual(t.frame.height, f0.height * k, accuracy: 0.01)
        let f1 = t.frame
        XCTAssertTrue(ui.tap(text: "Cell Margins")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Custom Margins…")); ui.pump()
        XCTAssertTrue(ui.tap(id: "cellmargins.left"))
        for _ in 0..<6 { ui.press(.backspace) }
        ui.type("0.4"); ui.pump()
        XCTAssertTrue(ui.tap(text: "OK")); ui.pump(); ui.pump()
        XCTAssertEqual(c.document.paragraphs.first?.cell?.padding?.left, 28.8)
        XCTAssertEqual(c.document.paragraphs.count, n0)
        XCTAssertEqual(t.frame, f1)
        // One Cmd+Z each: the margin, then the resize (frame and rows), then the typing.
        shell.session.onUndo?(); ui.pump(); ui.pump()
        XCTAssertNil(c.document.paragraphs.first?.cell?.padding)
        XCTAssertEqual(t.frame, f1)
        shell.session.onUndo?(); ui.pump(); ui.pump()
        XCTAssertEqual(t.frame, f0)
        XCTAssertNil(c.document.tableStyles[t.tableId ?? ""]?.rowHeights[0])
    }

    func testCellMarginsDialogParsesInches() {
        XCTAssertEqual(CellMarginsDialogState.parse("0.1\""), 7.2)
        XCTAssertEqual(CellMarginsDialogState.parse(" 0.5 in"), 36)
        XCTAssertEqual(CellMarginsDialogState.parse("1"), 72)
        XCTAssertNil(CellMarginsDialogState.parse("-1"))
        XCTAssertNil(CellMarginsDialogState.parse("abc"))
        XCTAssertEqual(CellMarginsDialogState.inches(7.2), "0.1\"")
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
        for (label, get) in [("Total Row", { (o: DeckController.TableOptions) in o.totalRow }), ("First Column", { $0.firstColumn }),
                             ("Last Column", { $0.lastColumn }), ("Banded Columns", { $0.bandedColumns })] {
            XCTAssertTrue(ui.tap(text: label))
            XCTAssertTrue(get(deck.selectedTableOptions!), label)
        }
        // Shading menu: "No Shading" clears every cell's own colour.
        deck.setTableShading(Color(0xFFFFFF00))
        func fills() -> Set<Color?> { Set(t.text!.document.paragraphs.compactMap { $0.cell }.map { $0.fill }) }
        XCTAssertEqual(fills(), [Color(0xFFFFFF00)])
        XCTAssertTrue(ui.tap(text: "Shading"))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "No Shading"))
        XCTAssertEqual(fills(), [nil])
        // Table Styles gallery: Accent 3 paints the header with the theme's third accent.
        XCTAssertTrue(ui.tap(text: "Table Styles"))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Medium Style 2 - Accent 3"))
        XCTAssertEqual(t.text!.document.tableStyles[t.tableId!]?.headerFill, deck.tableLookColor(.accent(2)))
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

    func testSplitCellDialogReachesTheController() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertTable(rows: 2, columns: 2)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        XCTAssertTrue(ui.tap(text: "Merge"))
        XCTAssertTrue(ui.tap(text: "Split Cell…"))
        XCTAssertTrue(ui.has(text: "Number of columns"))
        XCTAssertTrue(ui.tap(text: "OK"))                  // defaults: 2 columns, 1 row
        XCTAssertEqual(c.document.columnCount(of: c.currentCell!.table), 3)
        XCTAssertEqual(c.document.paragraphs.compactMap(\.cell).count, 5)
        c.undo()
        XCTAssertEqual(c.document.paragraphs.compactMap(\.cell).count, 4)
    }

    /// W-TB-9: Convert Text to Table and Convert Table to Text reach the controller.
    func testConvertTextAndTableDialogsReachTheController() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertText("a\tb")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 3), extend: true)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Insert"))
        XCTAssertTrue(ui.tap(text: "Table"))
        XCTAssertTrue(ui.tap(text: "Convert Text to Table…"))
        XCTAssertTrue(ui.has(text: "Separate text at"))
        XCTAssertTrue(ui.tap(text: "OK"))                   // tabs by default
        XCTAssertEqual(c.document.paragraphs.filter { $0.cell != nil }.map(\.text), ["a", "b"])
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        XCTAssertTrue(ui.tap(text: "Select"))
        XCTAssertTrue(ui.tap(text: "Convert Table to Text…"))
        XCTAssertTrue(ui.has(text: "Separate text with"))
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertNil(c.document.paragraphs.first { $0.cell != nil })
        XCTAssertEqual(c.document.paragraphs.first?.text, "a\tb")
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

    /// W-TB-1: the Insert Table grid: a click on a square inserts that many columns and rows; the caption names the size.
    func testInsertTableGridInsertsTheClickedSize() {
        XCTAssertEqual(TableGridMenuItem.caption(rows: 0, columns: 0), "Insert Table")
        XCTAssertEqual(TableGridMenuItem.caption(rows: 4, columns: 3), "3 × 4 Table")
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        XCTAssertTrue(ui.tap(text: "Insert"))
        XCTAssertTrue(ui.tap(text: "Table"))
        XCTAssertTrue(ui.has(id: "table-grid-8-10"), "ten columns by eight rows")
        XCTAssertFalse(ui.has(id: "table-grid-9-1"))
        XCTAssertTrue(ui.tap(id: "table-grid-4-3"))
        let cells = c.document.paragraphs.compactMap { $0.cell }
        XCTAssertEqual(cells.count, 12, "3 columns x 4 rows")
        XCTAssertEqual(c.document.columnCount(of: cells[0].table), 3)
    }

    /// W-TB-2: the Borders and Shading dialog applies sides, line and shading as one undo.
    func testBordersAndShadingDialogReachesTheController() {
        // (2000 wide: see testTableLayoutBordersAndShadingReachTheController.)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(2000, 800))
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

    private func pictureShell() throws -> (WidgetTester, RichDocumentController) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = try XCTUnwrap(ui.state(OfficeShellState.self)).session.controller
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        c.load(RichDocument(paragraphs: [RichParagraph(image: ImageAttachment(data: png, width: 200, height: 100))]))
        c.selectImage(at: 0)
        ui.pump()
        return (ui, c)
    }

    /// W-OB-1: the Alt Text dialog sets the picture's alternative text in one undo step; Cancel changes nothing.
    func testAltTextDialogSetsTheTextAndCancelDoesNot() throws {
        let (ui, c) = try pictureShell()
        XCTAssertTrue(ui.tap(text: "Alt Text"))
        XCTAssertTrue(ui.tap(id: "alt-text"))
        ui.type("A red box")
        XCTAssertTrue(ui.tap(text: "Cancel"))
        XCTAssertEqual(c.document.paragraphs[0].image?.altText, "")
        XCTAssertTrue(ui.tap(text: "Alt Text"))
        XCTAssertTrue(ui.tap(id: "alt-text"))
        ui.type("A red box")
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertEqual(c.document.paragraphs[0].image?.altText, "A red box")
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].image?.altText, "")
    }

    /// W-OB-1: the Crop dialog cuts the typed percents off each side, keeps the scale, and refuses a crop that leaves nothing.
    func testCropDialogCutsTheTypedPercents() throws {
        let (ui, c) = try pictureShell()
        XCTAssertTrue(ui.tap(text: "Crop"))
        XCTAssertTrue(ui.tap(id: "crop-left"))
        ui.type("25")
        XCTAssertTrue(ui.tap(text: "OK"))
        let img = try XCTUnwrap(c.document.paragraphs[0].image)
        XCTAssertEqual(img.crop?.left ?? 0, 0.25, accuracy: 0.001)
        XCTAssertEqual(img.width, 150, accuracy: 0.1)
        c.undo()
        XCTAssertNil(c.document.paragraphs[0].image?.crop)
    }

    /// W-OB-1: Reset Picture takes the crop and the turn off and shows the picture at its own size, in one undo step.
    func testResetPictureTakesCropAndTurnOff() throws {
        let (ui, c) = try pictureShell()
        _ = c.setImageCrop(at: 0, PictureCrop(left: 0.25, top: 0, right: 0, bottom: 0))
        _ = c.rotatePicture(at: 0, quarters: 1)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Reset Picture"))
        let img = try XCTUnwrap(c.document.paragraphs[0].image)
        XCTAssertNil(img.crop)
        XCTAssertEqual(img.rotation, 0)
        XCTAssertEqual(img.width / img.height, 2, accuracy: 0.01)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].image?.rotation, 90)
        XCTAssertNotNil(c.document.paragraphs[0].image?.crop)
    }

    /// W-OB-1: Change Picture on the Picture Format tab asks the host for a file (the swap itself is the controller's
    /// replacePicture, tested in DocxTests; image decoding needs the engine, which a harness test lacks).
    func testChangePictureAsksForAFile() throws {
        let (ui, _) = try pictureShell()
        var asked = false
        defer { OfficeScene.main.pictureRequested = nil }
        OfficeScene.main.pictureRequested = { _ in asked = true }
        XCTAssertTrue(ui.tap(text: "Change Picture"))
        XCTAssertTrue(asked)
    }
}
