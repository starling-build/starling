import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-PG-1: the Page Setup dialog and the model step behind it.
final class PageSetupDialogTests: XCTestCase {
    private func twoSections() -> RichDocumentController {
        var a = RichParagraph(); a.insert("first", at: 0, runs: [])
        var first = PageSetup.letter; first.columns = 2
        a.style.sectionPage = first
        var b = RichParagraph(); b.insert("second", at: 0, runs: [])
        var d = RichDocument(paragraphs: [a, b])
        d.lastSectionPage = .a4
        return RichDocumentController(document: d)
    }

    func testValuesApplyKeepingTheSectionsOtherSettings() {
        var v = PageSetupValues(.letter)
        v.setPaper(.a4); v.setLandscape(true); v.left = 100
        XCTAssertEqual(v.paper, .a4)
        XCTAssertTrue(v.landscape)
        var p = PageSetup.letter; p.columns = 2
        v.apply(to: &p)
        XCTAssertEqual(p.width, 841.9, accuracy: 0.01)
        XCTAssertEqual(p.height, 595.3, accuracy: 0.01)
        XCTAssertEqual(p.marginLeft, 100)
        XCTAssertEqual(p.columns, 2, "columns are not the dialog's to change")
        v.top = 400; v.bottom = 400
        XCTAssertFalse(v.valid, "margins that leave no room are refused")
    }

    func testChangeAllSectionsIsOneUndoStepAndKeepsEachColumns() {
        let c = twoSections()
        var v = PageSetupValues(.letter); v.setPaper(.legal); v.left = 50
        c.changePageSetup(allSections: true, lastSetup: .a4) { v.apply(to: &$0) }
        XCTAssertEqual(c.document.paragraphs[0].style.sectionPage?.height, 1008)
        XCTAssertEqual(c.document.paragraphs[0].style.sectionPage?.columns, 2)
        XCTAssertEqual(c.document.lastSectionPage?.height, 1008)
        XCTAssertEqual(c.document.lastSectionPage?.marginLeft, 50)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].style.sectionPage?.height, 792)
        XCTAssertEqual(c.document.lastSectionPage, .a4, "one undo restores both")
    }

    func testDialogAppliesToTheCaretSectionAndSurvivesSave() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let s = ui.state(OfficeShellState.self)!.session
        s.onPageSetupDialog?(); ui.pump()
        XCTAssertTrue(ui.has(text: "Page Setup"))
        XCTAssertTrue(ui.tap(text: "Paper"))
        XCTAssertTrue(ui.tap(id: "ps-paper-a4"))
        XCTAssertTrue(ui.tap(id: "ps-landscape"))
        XCTAssertEqual(s.pageSetup.width, PageSetup.letter.width, "nothing applies before OK")
        ui.press(.enter); ui.pump()
        XCTAssertFalse(ui.has(id: "ps-landscape"), "the dialog closed")
        XCTAssertEqual(s.pageSetup.width, 841.9, accuracy: 0.01)
        XCTAssertEqual(s.pageSetup.height, 595.3, accuracy: 0.01)
        let back = try DocxFormat.read(DocxFormat.write(s.controller.document, pageSetup: s.pageSetup))
        XCTAssertEqual(back.pageSetup?.width ?? 0, 841.9, accuracy: 0.1)
        s.controller.undo(); s.syncPageSetup()
        XCTAssertEqual(s.pageSetup.width, PageSetup.letter.width)
    }

    func testEscapeCancels() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let s = ui.state(OfficeShellState.self)!.session
        let before = s.pageSetup
        s.onPageSetupDialog?(); ui.pump()
        XCTAssertTrue(ui.tap(id: "ps-landscape"))
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "ps-landscape"))
        XCTAssertEqual(s.pageSetup, before)
    }

    /// W-HF-2: the Layout tab's page number format.
    func testTheLayoutTabSetsThePageNumberFormat() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let s = ui.state(OfficeShellState.self)!.session
        s.onPageSetupDialog?(); ui.pump()
        // The dialog's Layout tab, not the ribbon's: the last "Layout" in the tree.
        let tab = ui.elements().last { ($0.widget as? Text)?.data == "Layout" }?.findRenderObject() as? RenderBox
        let box = try XCTUnwrap(tab)
        ui.tap(at: box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2))); ui.pump()
        XCTAssertTrue(ui.has(id: "ps-fmt-decimal"))
        XCTAssertTrue(ui.tap(id: "ps-fmt-upperRoman"))
        XCTAssertFalse(ui.has(id: "ps-chapstyle"), "no chapter boxes until the chapter number is on")
        XCTAssertTrue(ui.tap(id: "ps-chapter"))
        XCTAssertTrue(ui.has(id: "ps-chapstyle") && ui.has(id: "ps-chapsep"))
        ui.press(.enter); ui.pump()
        XCTAssertFalse(ui.has(id: "ps-fmt-upperRoman"), "the dialog closed")
        XCTAssertEqual(s.controller.document.pageNumberFormat, "upperRoman")
        XCTAssertEqual(s.controller.document.chapterStyle, 1, "Heading 1 by default")
        XCTAssertNil(s.controller.document.chapterSeparator, "a hyphen, unnamed")
        let back = try DocxFormat.read(DocxFormat.write(s.controller.document, pageSetup: s.pageSetup))
        XCTAssertEqual(back.document.pageNumberFormat, "upperRoman")
        s.controller.undo()
        XCTAssertNil(s.controller.document.pageNumberFormat)
    }

    func testTheHeaderAndFooterTabShowsWhileTheStripIsOpen() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let s = ui.state(OfficeShellState.self)!.session
        XCTAssertFalse(ui.has(text: "Header & Footer"))
        s.onHeaderFooter?(); ui.pump()
        XCTAssertTrue(ui.has(text: "Header & Footer") && ui.has(text: "Different First Page"), "the tab opens with the strip, selected")
        XCTAssertTrue(ui.has(text: "Link Header to Previous"), "shown, though the one section has nothing to link to")
        XCTAssertTrue(ui.tap(text: "Different First Page")); ui.pump()
        XCTAssertTrue(s.controller.document.titlePage)
        XCTAssertTrue(ui.tap(text: "Different Odd & Even Pages")); ui.pump()
        XCTAssertTrue(s.controller.document.evenAndOddHeaders)
        XCTAssertTrue(ui.tap(text: "Close Header and Footer")); ui.pump()
        XCTAssertFalse(s.headerFooterOpen)
        XCTAssertFalse(ui.has(text: "Different First Page"), "the tab goes with the strip")
        XCTAssertTrue(s.controller.document.titlePage, "closing keeps what was set")
    }
}
