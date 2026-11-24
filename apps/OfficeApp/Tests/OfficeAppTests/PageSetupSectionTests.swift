import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-P0-3: page setup is one undoable step on the section holding the caret.
final class PageSetupSectionTests: XCTestCase {
    private func twoSections() -> RichDocumentController {
        var a = RichParagraph(); a.insert("first", at: 0, runs: [])
        a.style.sectionPage = .letter
        var b = RichParagraph(); b.insert("second", at: 0, runs: [])
        var d = RichDocument(paragraphs: [a, b])
        d.lastSectionPage = .a4
        return RichDocumentController(document: d)
    }

    func testSetPageSetupActsOnTheCaretSectionAndUndoes() {
        let c = twoSections()
        var narrow = PageSetup.letter; narrow.marginLeft = 36; narrow.marginRight = 36
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 0), focus: RichPosition(paragraph: 0, offset: 0))
        let rev = c.revision
        c.setPageSetup(narrow, lastSetup: .a4)
        XCTAssertEqual(c.document.paragraphs[0].style.sectionPage, narrow)
        XCTAssertEqual(c.document.lastSectionPage, .a4, "the last section is untouched")
        XCTAssertNotEqual(c.revision, rev, "the document is marked changed")
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].style.sectionPage, .letter)
        c.redo()
        XCTAssertEqual(c.document.paragraphs[0].style.sectionPage, narrow)

        c.selection = RichSelection(anchor: RichPosition(paragraph: 1, offset: 0), focus: RichPosition(paragraph: 1, offset: 0))
        c.setPageSetup(.letter, lastSetup: .a4)
        XCTAssertEqual(c.document.lastSectionPage, .letter)
        XCTAssertEqual(c.document.paragraphs[0].style.sectionPage, narrow)
        c.undo()
        XCTAssertEqual(c.document.lastSectionPage, .a4)
    }

    func testPerSectionChangeSurvivesSaveAndNeighboursStay() throws {
        // A real two-section file: the first paragraph ends a letter section.
        var a = RichParagraph(); a.insert("first", at: 0, runs: [])
        let base = try DocxFormat.write(RichDocument(paragraphs: [a, RichParagraph()]), pageSetup: .a4)
        var parts = try Zip.read(base)
        let di = try XCTUnwrap(parts.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: parts[di].data, as: UTF8.self)
        let sect = "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr>"
        let r = try XCTUnwrap(xml.range(of: "<w:p>") ?? xml.range(of: "<w:p "))
        let close = try XCTUnwrap(xml[r.lowerBound...].range(of: ">"))
        xml.replaceSubrange(close.upperBound..<close.upperBound, with: "<w:pPr>" + sect + "</w:pPr>")
        parts[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let read = try DocxFormat.read(try Zip.write(parts))
        let c = RichDocumentController(document: read.document)
        let idx = try XCTUnwrap(read.document.paragraphs.firstIndex { $0.style.sectionXML != nil })
        c.selection = RichSelection(anchor: RichPosition(paragraph: idx, offset: 0), focus: RichPosition(paragraph: idx, offset: 0))
        var wide = try XCTUnwrap(c.document.paragraphs[idx].style.sectionPage)
        wide.marginLeft = 144; wide.marginRight = 144; wide.columns = 2
        c.setPageSetup(wide, lastSetup: read.pageSetup ?? .a4)
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: read.pageSetup ?? .a4))
        let first = back.document.paragraphs.first { $0.style.sectionPage != nil }
        XCTAssertEqual(first?.style.sectionPage?.marginLeft, 144)
        XCTAssertEqual(first?.style.sectionPage?.columns, 2)
        XCTAssertEqual(first?.style.sectionPage?.width, PageSetup.letter.width, "size of that section is unchanged")
        XCTAssertEqual(back.pageSetup?.width, PageSetup.a4.width, "the last section keeps A4")
        XCTAssertEqual(back.document.paragraphs.first?.text, "first")
    }

    func testRibbonMarginsReachTheModelAndUndo() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        XCTAssertTrue(ui.tap(text: "Layout"))
        XCTAssertTrue(ui.tap(text: "Margins"))
        XCTAssertTrue(ui.tap(text: "Narrow (0.5\")"))
        let s = ui.state(OfficeShellState.self)!.session
        XCTAssertEqual(s.sectionSetup().marginLeft, 36)
        s.controller.undo()
        XCTAssertEqual(s.sectionSetup().marginLeft, 72)
    }
}
