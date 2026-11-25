import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-HF-1 PR 2: bold, italic and alignment on the header/footer strip, and the page field in a formatted footer.
final class HeaderFooterStripLookTests: XCTestCase {
    func testStripFormatsHeaderAndFooterAndUndoes() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1600, 800))
        let s = ui.state(OfficeShellState.self)!.session
        s.controller.load(RichDocument(paragraphs: [RichParagraph()]))
        s.controller.setHeaderFooter(header: "Acme", footer: "Page {PAGE}")
        s.onHeaderFooter?()
        ui.pump()
        XCTAssertTrue(ui.tap(id: "header-bold"))
        XCTAssertTrue(ui.tap(id: "header-center"))
        XCTAssertTrue(ui.tap(id: "footer-italic"))
        XCTAssertTrue(ui.tap(id: "footer-right"))
        XCTAssertTrue(ui.tap(id: "header-footer-done"))
        let h = try XCTUnwrap(s.controller.document.headerFooters.first { $0.kind == .header })
        XCTAssertEqual(h.paragraphs[0].style.alignment, .center)
        XCTAssertTrue(h.paragraphs[0].runs[0].style.bold)
        let f = try XCTUnwrap(s.controller.document.headerFooters.first { $0.kind == .footer })
        XCTAssertEqual(f.paragraphs[0].style.alignment, .right)
        XCTAssertTrue(f.paragraphs[0].runs.contains { $0.style.field == "PAGE" && $0.style.italic })
        // The saved file writes the formatting and keeps the field.
        let parts = try Zip.read(DocxFormat.write(s.controller.document, pageSetup: .letter))
        let xml = parts.compactMap { $0.name.hasPrefix("word/footer") ? String(decoding: $0.data, as: UTF8.self) : nil }.joined()
        XCTAssertTrue(xml.contains("PAGE"))
        XCTAssertTrue(xml.contains("w:jc w:val=\"right\""))
        // Reopening the strip shows the look again.
        XCTAssertEqual(s.controller.headerFooterLook(.header), .init(bold: true, italic: false, alignment: .center))
        s.controller.undo()
        XCTAssertNil(s.controller.document.headerFooters.first { $0.kind == .footer && $0.edited == true })
    }
}
