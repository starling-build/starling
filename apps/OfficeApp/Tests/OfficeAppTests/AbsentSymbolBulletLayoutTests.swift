// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class AbsentSymbolBulletLayoutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    /// es-3b20b19c25: a ● bullet whose face is Noto Sans Symbols (absent on Windows) is drawn in the text's own face
    /// in Word's print; the absent face's taller ascent must not lift the item's first line (Word's bullets over
    /// Times 12 at 1.15 stood 12.03 apart; ours 21).
    func testAnAbsentSymbolFaceBulletDoesNotLiftItsLine() throws {
        _ = OfficeFonts.register()
        func firstBaseline(face: String?) throws -> Double {
            var p = RichParagraph(text: "item one of the list")
            p.style.list = .bullet; p.style.listId = "7"; p.style.listLevel = 0
            var doc = RichDocument(paragraphs: [p])
            var level = ListLevelFormat(text: "\u{25CF}", format: .bullet)
            if let face { level.numberRPrXML = "<w:rPr><w:rFonts w:ascii=\"\(face)\" w:hAnsi=\"\(face)\"/></w:rPr>" }
            doc.listFormats["7"] = [0: level]
            let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
            theme.wordRules = true
            // (The face is absent from the test fonts: stand it in with a taller one, as it stands taller than Times in Word's engine.)
            theme.faceResolver = { OfficeFonts.face(($0 ?? "").lowercased().hasPrefix("noto sans symbols") ? "Arial Black" : $0, eastAsian: $1) }
            let layout = RichLayout(theme: theme, paragraphCount: back.paragraphs.count)
            layout.width = 300
            layout.ensureLaidOut(back)
            let g = layout.geometry(0)
            return (g.painter.computeLineMetrics()[0].baseline + g.inkShift) / theme.pixelsPerPoint
        }
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        let plain = try firstBaseline(face: nil)
        let noto = try firstBaseline(face: "Noto Sans Symbols")
        XCTAssertEqual(noto, plain, accuracy: 0.3, "noto \(noto) plain \(plain)")
    }

    /// A multiple's extra under the text hangs over a page's footnotes: with
    /// 1.5 lines Word's print keeps a last line whose text ends above the
    /// separator though its extra reaches into it (es-28716e1db6 page 3, lab
    /// afn1: both lines stay with 0 to 12 pt after).
    func testAMultipleSpacedLastLineHangsItsExtraOverFootnotes() throws {
        func pages(size: Int, count: Int) throws -> Int {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
            let notes = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:id="1"><w:p><w:r><w:t>Note</w:t></w:r></w:p></w:footnote></w:footnotes>
            """
            entries.append(ZipEntry(name: "word/footnotes.xml", data: Data(notes.utf8)))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
            let rows = (0 ..< count).map { "<w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"360\" w:lineRule=\"auto\"/></w:pPr><w:r><w:rPr><w:sz w:val=\"\(size)\"/></w:rPr><w:t>line \($0)</w:t></w:r></w:p>" }.joined()
            xml.replaceSubrange(body.upperBound ..< sect.lowerBound,
                with: "<w:p><w:r><w:t>note</w:t></w:r><w:r><w:footnoteReference w:id=\"1\"/></w:r></w:p>" + rows)
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let doc = try DocxFormat.read(try Zip.write(entries)).document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = .letter
            layout.width = 612 * 96.0 / 72.0
            layout.ensureLaidOut(doc)
            return layout.pageCount
        }
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        // (The number of 1.5-spaced one-line paragraphs after which a second page opens; the extra of the page's last line hangs over the note.)
        for (size, opens) in [(20, 36), (24, 30)] {
            var n = 1
            while try pages(size: size, count: n) < 2 { n += 1 }
            XCTAssertEqual(n, opens, "size \(size)")
        }
    }
}
