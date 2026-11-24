import XCTest
import Flutter
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

    /// W-ED-1: the Paste button is on the Home ribbon and the shell has wired every way of pasting
    /// (plain click, plain-text key, the four Paste Options) to the controller.
    func testPasteAndPasteOptionsAreWiredToTheShell() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        XCTAssertTrue(ui.has(text: "Paste"))
        let state = try XCTUnwrap(ui.state(OfficeShellState.self))
        XCTAssertNotNil(state.session.onPaste)
        XCTAssertNotNil(state.session.onPasteMode)
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
}
