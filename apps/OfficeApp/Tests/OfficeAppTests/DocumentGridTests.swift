import XCTest
@testable import OfficeApp
@testable import OfficeText

/// W-PG-3: Page Setup's Document Grid tab (no grid, lines, lines and characters, snap to characters, and the text
/// direction): one undo step, written as Word writes it, and laid out as the file read back would be.
final class DocumentGridTests: XCTestCase {
    private let sz = "<w:pgSz w:w=\"11906\" w:h=\"16838\"/>"
    private let mar = "<w:pgMar w:top=\"1440\" w:right=\"1800\" w:bottom=\"1440\" w:left=\"1800\" w:header=\"851\" w:footer=\"992\" w:gutter=\"0\"/>"

    /// A two-section file, both sections on Word's default grid of no type.
    private func read() throws -> (RichDocument, PageSetup) {
        let mid = "<w:p><w:pPr><w:sectPr>\(sz)\(mar)<w:cols w:space=\"425\"/><w:docGrid w:linePitch=\"312\"/></w:sectPr></w:pPr><w:r><w:t>one</w:t></w:r></w:p>"
        let body = "<w:body>\(mid)<w:p><w:r><w:t>two</w:t></w:r></w:p><w:sectPr>\(sz)\(mar)<w:cols w:space=\"425\"/><w:docGrid w:linePitch=\"312\"/></w:sectPr></w:body>"
        var entries = try Zip.read(try DocxFormat.write(RichDocument(plainText: "a"), pageSetup: .letter))
        let i = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var s = String(decoding: entries[i].data, as: UTF8.self)
        let a = try XCTUnwrap(s.rangeOfSubstring("<w:body>")), b = try XCTUnwrap(s.rangeOfSubstring("</w:body>"))
        s.replaceSubrange(a.lowerBound ..< b.upperBound, with: body)
        entries[i] = ZipEntry(name: entries[i].name, data: Data(s.utf8))
        let read = try DocxFormat.read(try Zip.write(entries))
        return (read.document, try XCTUnwrap(read.pageSetup))
    }

    private func roundTrip(_ c: RichDocumentController, _ p: PageSetup) throws -> (RichDocument, PageSetup, String) {
        let data = try DocxFormat.write(c.document, pageSetup: c.document.lastSectionPage ?? p)
        let xml = String(decoding: try XCTUnwrap(try Zip.read(data).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        let back = try DocxFormat.read(data)
        return (back.document, try XCTUnwrap(back.pageSetup), xml)
    }

    func testLinesAndCharactersOnEverySectionIsOneStepAndLaysOutAsReadBack() throws {
        let (d, p) = try read()
        let c = RichDocumentController(document: d)
        XCTAssertEqual(c.documentGrid(sectionMark: 0), DocumentGrid(kind: .none, linePitch: 312))
        XCTAssertEqual(c.documentGrid(sectionMark: -1), DocumentGrid(kind: .none, linePitch: 312))
        let grid = DocumentGrid(kind: .linesAndChars, linePitch: 400, charSpace: 2048)
        c.setDocumentGrid(grid, allSections: true, lastSetup: p)
        XCTAssertEqual(c.documentGrid(sectionMark: 0), grid)
        XCTAssertEqual(c.documentGrid(sectionMark: -1), grid)
        XCTAssertEqual(c.document.lineGridPitch, 20); XCTAssertEqual(c.document.characterGridSpace, 0.5)
        XCTAssertEqual(c.document.paragraphs[0].style.sectionPage?.lineGridPitch, 20)
        XCTAssertEqual(c.document.paragraphs[0].style.sectionPage?.characterGridSpace, 0.5)

        let (back, _, xml) = try roundTrip(c, p)
        XCTAssertEqual(xml.components(separatedBy: "<w:docGrid w:type=\"linesAndChars\" w:linePitch=\"400\" w:charSpace=\"2048\"/>").count, 3, xml)
        XCTAssertEqual(back.lineGridPitch, c.document.lineGridPitch)
        XCTAssertEqual(back.characterGridSpace, c.document.characterGridSpace)
        XCTAssertEqual(back.paragraphs[0].style.sectionPage?.lineGridPitch, 20)
        XCTAssertEqual(back.paragraphs[0].style.sectionPage?.characterGridSpace, 0.5)

        c.undo()
        XCTAssertEqual(c.documentGrid(sectionMark: 0), DocumentGrid(kind: .none, linePitch: 312))
        XCTAssertEqual(c.documentGrid(sectionMark: -1), DocumentGrid(kind: .none, linePitch: 312))
        XCTAssertNil(c.document.lineGridPitch)
        XCTAssertNil(c.document.paragraphs[0].style.sectionPage?.lineGridPitch)
        XCTAssertFalse(c.canUndo, "the grid is one step")
    }

    func testSnapToCharactersCountsTheCellAsTheReaderDoes() throws {
        let (d, p) = try read()
        let c = RichDocumentController(document: d)
        c.selection = RichSelection(caret: RichPosition(paragraph: 1, offset: 0))
        c.setDocumentGrid(DocumentGrid(kind: .snapToChars, linePitch: 312, charSpace: -1000), allSections: false, lastSetup: p)
        XCTAssertEqual(c.documentGrid(sectionMark: 0).kind, .none, "only the caret's section")
        let space = try XCTUnwrap(c.document.characterGridSpace)
        let (back, _, _) = try roundTrip(c, p)
        XCTAssertEqual(try XCTUnwrap(back.characterGridSpace), space, accuracy: 1e-9)
        XCTAssertEqual(back.characterGridCellBase, c.document.characterGridCellBase)
        XCTAssertEqual(back.lineGridPitch, 15.6)
    }

    func testVerticalTextTurnsTheSectionAndWritesItsDirection() throws {
        let (d, p) = try read()
        let c = RichDocumentController(document: d)
        c.setDocumentGrid(DocumentGrid(kind: .lines, linePitch: 312, vertical: true), allSections: true, lastSetup: p)
        XCTAssertEqual(c.document.lastSectionPage?.vertical, true)
        XCTAssertEqual(c.document.paragraphs[0].style.sectionPage?.vertical, true)
        let (back, page, xml) = try roundTrip(c, p)
        XCTAssertEqual(xml.components(separatedBy: "<w:textDirection w:val=\"tbRl\"/>").count, 3, xml)
        XCTAssertTrue(page.vertical)
        XCTAssertEqual(back.paragraphs[0].style.sectionPage?.vertical, true)
        XCTAssertEqual(page.physical.width, 595.3, accuracy: 0.1, "the paper stays upright")
        // (The direction stands before the grid, as the schema orders a sectPr.)
        let dir = try XCTUnwrap(xml.rangeOfSubstring("<w:textDirection")), grid = try XCTUnwrap(xml.rangeOfSubstring("<w:docGrid"))
        XCTAssertLessThan(dir.lowerBound, grid.lowerBound)

        let c2 = RichDocumentController(document: back)
        c2.setDocumentGrid(DocumentGrid(kind: .lines, linePitch: 312, vertical: false), allSections: true, lastSetup: page)
        let (_, flat, xml2) = try roundTrip(c2, page)
        XCTAssertFalse(xml2.containsSubstring("textDirection"), xml2)
        XCTAssertFalse(flat.vertical)
        XCTAssertEqual(flat.width, 595.3, accuracy: 0.1)
    }

    func testTheTabCountsCharactersAndLines() {
        var p = PageSetup.a4; p.marginLeft = 90; p.marginRight = 90; p.marginTop = 72; p.marginBottom = 72
        var v = PageSetupValues(p)
        v.grid = DocumentGrid(kind: .linesAndChars, linePitch: 312, charSpace: 0); v.normalSize = 10.5
        XCTAssertEqual(v.charactersPerLine, 39)  // 415.3 pt / 10.5
        XCTAssertEqual(v.linesPerPage, 44)       // 697.9 pt / 15.6
        v.characterPitch = 11
        XCTAssertEqual(v.grid?.charSpace, 2048)
        v.linePitch = 18
        XCTAssertEqual(v.grid?.linePitch, 360)
        XCTAssertEqual(DocumentGrid(kind: .none, linePitch: 360, charSpace: 99).xml, "<w:docGrid w:linePitch=\"360\"/>")
    }

    /// The Word lab (PGGRID_OUT=<folder>): each grid the tab sets, saved by us, for Word to print.
    func testWriteLabFiles() throws {
        guard let out = ProcessInfo.processInfo.environment["PGGRID_OUT"] else { return }
        let ja = "吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。"
        let mixed = "Grid test 123: 日本語とEnglishが混ざる行。" + ja
        func doc(_ grid: (RichDocumentController, PageSetup) -> Void, _ name: String) throws {
            let (d, p) = try read()
            var d2 = d
            for i in d2.paragraphs.indices { d2.paragraphs[i] = RichParagraph(text: String(repeating: i == 0 ? ja : mixed, count: 4), style: d2.paragraphs[i].style) }
            let c = RichDocumentController(document: d2)
            grid(c, p)
            try DocxFormat.write(c.document, pageSetup: c.document.lastSectionPage ?? p).write(to: URL(fileURLWithPath: out + "/" + name + ".docx"))
        }
        try doc({ c, p in
            c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 0))
            c.setDocumentGrid(DocumentGrid(kind: .linesAndChars, linePitch: 400, charSpace: 2048), allSections: false, lastSetup: p)
            c.selection = RichSelection(caret: RichPosition(paragraph: 1, offset: 0))
            c.setDocumentGrid(DocumentGrid(kind: .snapToChars, linePitch: 312, charSpace: -1000), allSections: false, lastSetup: p)
        }, "pggrid-chars")
        try doc({ c, p in c.setDocumentGrid(DocumentGrid(kind: .lines, linePitch: 480), allSections: true, lastSetup: p) }, "pggrid-lines")
        try doc({ c, p in c.setDocumentGrid(DocumentGrid(kind: .lines, linePitch: 360, vertical: true), allSections: true, lastSetup: p) }, "pggrid-vert")
    }
}
