import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-ED-1: after a paste the Paste Options button offers the other ways; a pick redoes the paste that way in one
/// undo step, and the document saves and reopens as picked.
final class PasteOptionsButtonTests: XCTestCase {
    private let codec = OfficeClipboardCodec()

    /// "Copied bold" with "bold" bold and green, as another document copies it.
    private func clip() -> ClipboardData {
        var src = RichDocument(plainText: "Copied bold")
        src.paragraphs[0].applyStyle(7 ..< 11) { $0.bold = true; $0.color = Color(0xFF00AA00) }
        let data = codec.encode(src.paragraphs, styles: OfficeStyles.sheet, text: "Copied bold")
        return ClipboardData(text: "Copied bold", rtf: data.rtf, html: data.html)
    }

    private func controller(_ text: String) -> RichDocumentController {
        let c = RichDocumentController(plainText: text)
        c.clipboardCodec = codec
        c.moveTo(RichPosition(paragraph: 0, offset: text.utf16.count), extend: false)
        return c
    }

    private func reopen(_ c: RichDocumentController) throws -> RichDocument {
        try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
    }

    func testTheButtonShowsAfterAPasteAndGoesWithTheNextEdit() {
        let c = controller("Start ")
        XCTAssertNil(c.pasteOptions)
        c.paste(data: clip(), mode: .keepSource)
        let shown = c.pasteOptions
        XCTAssertEqual(shown?.mode, .keepSource)
        XCTAssertEqual(shown?.end, c.caret)
        // Moving the caret keeps it; typing takes it away, as in Word.
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        XCTAssertNotNil(c.pasteOptions)
        c.insertText("x")
        XCTAssertNil(c.pasteOptions)
    }

    func testRepasteAsTextOnlyIsOneUndoStepAndSaves() throws {
        let c = controller("Start ")
        c.paste(data: clip(), mode: .keepSource)
        XCTAssertEqual(c.document.paragraphs[0].runs(in: 13 ..< 17)[0].style.color, Color(0xFF00AA00))
        c.repaste(.textOnly)
        XCTAssertEqual(c.document.paragraphs[0].text, "Start Copied bold")
        XCTAssertEqual(c.pasteOptions?.mode, .textOnly)
        let saved = try reopen(c)
        XCTAssertEqual(saved.paragraphs[0].text, "Start Copied bold")
        let s = saved.paragraphs[0].runs(in: 13 ..< 17)[0].style
        XCTAssertFalse(s.bold)
        XCTAssertNotEqual(s.color, Color(0xFF00AA00))
        // One Undo takes the whole paste out, not back to the first way.
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["Start "])
        XCTAssertNil(c.pasteOptions)
    }

    func testRepasteAsMergeKeepsBoldDropsColourAndSaves() throws {
        let c = controller("Start ")
        c.paste(data: clip(), mode: .textOnly)
        c.repaste(.mergeFormatting)
        let saved = try reopen(c)
        let s = saved.paragraphs[0].runs(in: 13 ..< 17)[0].style
        XCTAssertTrue(s.bold)
        XCTAssertNotEqual(s.color, Color(0xFF00AA00))
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["Start "])
    }

    func testAWayTheClipboardCannotGiveIsGreyedAndDoesNothing() {
        let c = controller("Start ")
        c.paste(data: clip(), mode: .keepSource)
        XCTAssertFalse(c.canRepaste(.picture))
        XCTAssertTrue(c.canRepaste(.textOnly))
        let before = c.revision
        c.repaste(.picture)
        XCTAssertEqual(c.revision, before)
        XCTAssertEqual(c.pasteOptions?.mode, .keepSource)
    }

    func testUndoingThePasteHidesTheButton() {
        let c = controller("Start ")
        c.paste(data: clip(), mode: .keepSource)
        c.undo()
        XCTAssertNil(c.pasteOptions)
        XCTAssertFalse(c.canRepaste(.textOnly))
    }
}

/// W-ED-1: Writer's Paste Special lists the clipboard's formats and pastes the chosen one alone.
final class WriterPasteSpecialTests: XCTestCase {
    private let codec = OfficeClipboardCodec()

    private func clip(png: Data? = nil) -> ClipboardData {
        var src = RichDocument(plainText: "Copied bold")
        src.paragraphs[0].applyStyle(7 ..< 11) { $0.bold = true }
        let data = codec.encode(src.paragraphs, styles: OfficeStyles.sheet, text: "Copied bold")
        return ClipboardData(text: "Copied bold", rtf: data.rtf, html: data.html, png: png)
    }

    func testTheListFollowsTheClipboardInWordsOrder() {
        XCTAssertEqual(PasteSpecialFormat.offered(by: clip()), [.html, .rtf, .unformattedText])
        XCTAssertEqual(PasteSpecialFormat.offered(by: ClipboardData(text: "just text")), [.unformattedText])
        XCTAssertEqual(PasteSpecialFormat.offered(by: ClipboardData(text: nil)), [])
        XCTAssertEqual(PasteSpecialFormat.unformattedText.label, "Unformatted Text")
        XCTAssertEqual(PasteChord.of(shift: false, alt: true), .pasteSpecial)
    }

    func testEachFormatPastesAloneInOneUndoStepAndSaves() throws {
        for (format, bold) in [(PasteSpecialFormat.html, true), (.rtf, true), (.unformattedText, false)] {
            let c = RichDocumentController(plainText: "")
            c.clipboardCodec = codec
            c.pasteSpecial(clip(), as: format)
            let saved = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
            XCTAssertEqual(saved.paragraphs[0].text, "Copied bold", "\(format)")
            XCTAssertEqual(saved.paragraphs[0].runs(in: 7 ..< 11)[0].style.bold, bold, "\(format)")
            // The Paste Options button follows, and one Undo takes the paste out.
            XCTAssertNotNil(c.pasteOptions, "\(format)")
            c.undo()
            XCTAssertEqual(c.document.paragraphs.map(\.text), [""], "\(format)")
        }
    }

    func testTheSourceLineIsTheFirstWordsOnOneLine() {
        XCTAssertEqual(WriterPasteSpecialDialog.sourceLine("a\nb"), "a b")
        XCTAssertEqual(WriterPasteSpecialDialog.sourceLine(String(repeating: "x", count: 80)), String(repeating: "x", count: 60) + "…")
        XCTAssertEqual(WriterPasteSpecialDialog.sourceLine(nil), "")
    }
}
