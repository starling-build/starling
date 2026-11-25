import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-P0-2: the header/footer strip must not flatten a header or footer that holds more than plain text.
final class RichHeaderFooterKeptTests: XCTestCase {
    private let richHeader = "<w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>Acme Ltd</w:t></w:r></w:p></w:hdr>"
    private let plainFooter = "<w:ftr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p><w:r><w:t>plain</w:t></w:r></w:p></w:ftr>"

    private func doc() -> RichDocument {
        var d = RichDocument(paragraphs: [RichParagraph()])
        d.header = "Acme Ltd"; d.footer = "plain"
        d.keptHeaderFooters = [KeptHeaderFooter(kind: .header, type: "default", part: "word/header1.xml", text: "Acme Ltd"),
                               KeptHeaderFooter(kind: .footer, type: "default", part: "word/footer1.xml", text: "plain")]
        d.keptParts = ["word/header1.xml": Data(richHeader.utf8), "word/footer1.xml": Data(plainFooter.utf8)]
        return d
    }

    func testRichSideIsKeptAndPlainSideEdits() {
        let c = RichDocumentController(document: doc())
        XCTAssertTrue(c.document.hasRichHeaderFooter(.header))
        XCTAssertFalse(c.document.hasRichHeaderFooter(.footer))
        let kept = c.setHeaderFooter(header: "Other", footer: "new footer")
        XCTAssertEqual(kept, [.header], "the caller is told the header was left alone")
        XCTAssertEqual(c.document.header, "Acme Ltd")
        XCTAssertEqual(c.document.footer, "new footer")
        c.undo()
        XCTAssertEqual(c.document.footer, "plain")
    }

    func testSavedFileKeepsTheRichHeaderPartAfterAnEditAttempt() throws {
        let c = RichDocumentController(document: doc())
        c.setHeaderFooter(header: "Other")
        let parts = try Zip.read(DocxFormat.write(c.document, pageSetup: .letter))
        let h = try XCTUnwrap(parts.first { $0.name == "word/header1.xml" })
        XCTAssertEqual(String(decoding: h.data, as: UTF8.self), richHeader)
    }

    func testPageNumberOnARichFooterOpensTheStripInsteadOfDoingNothing() {
        var d = doc(); d.keptParts["word/footer1.xml"] = Data(richHeader.utf8)
        let c = RichDocumentController(document: d)
        XCTAssertFalse(c.togglePageNumbers())
        XCTAssertEqual(c.document.footer, "plain")
    }

    func testStripDoneLeavesTheRichHeaderAlone() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let s = ui.state(OfficeShellState.self)!.session
        s.controller.load(doc())
        s.onHeaderFooter?()
        ui.pump()
        XCTAssertTrue(ui.has(text: "Header"), "the strip is open")
        XCTAssertTrue(ui.tap(id: "header-footer-done"))
        XCTAssertEqual(s.controller.document.header, "Acme Ltd")
        XCTAssertTrue(s.controller.document.hasRichHeaderFooter(.header))
    }
}
