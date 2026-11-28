import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-TB-5: a table inserted in a cell stays in the cell, its cells take typing, and a save keeps it nested as Word does.
final class NestedTableTests: XCTestCase {
    /// A 2x2 table with the caret in its first cell, then a 2x3 table inserted there.
    private func nested() -> (RichDocumentController, Int) {
        TableStyleGallery.install()
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 2, columns: 2)
        let first = c.document.paragraphs.firstIndex { $0.cell != nil }!
        c.moveTo(RichPosition(paragraph: first, offset: 0), extend: false)
        c.insertTable(rows: 2, columns: 3, textWidth: 468)
        return (c, c.document.paragraphs.firstIndex { $0.keptTable != nil }!)
    }
    private func body(_ data: Data) throws -> String {
        try XCTUnwrap(try Zip.read(data).first { $0.name == "word/document.xml" }.map { String(decoding: $0.data, as: UTF8.self) })
    }
    /// The count of `w:tbl` opened inside a `w:tc` of another.
    private func nestedCount(_ xml: String) -> Int {
        var depth = 0, n = 0, i = xml.startIndex
        while let r = xml.rangeOfSubstring("<w:tbl", in: i ..< xml.endIndex) ?? nil {
            let next = xml[r.upperBound]
            let close = xml.rangeOfSubstring("</w:tbl>", in: i ..< xml.endIndex)
            if let close, close.lowerBound < r.lowerBound { depth -= 1; i = close.upperBound; continue }
            if next == ">" || next == " " { if depth > 0 { n += 1 }; depth += 1 }
            i = r.upperBound
        }
        return n
    }

    func testATableInACellStaysInTheCellAsOneUndoStep() throws {
        let (c, i) = nested()
        let p = c.document.paragraphs[i]
        let outer = try XCTUnwrap(p.cell)
        XCTAssertEqual(outer.row, 0); XCTAssertEqual(outer.column, 0)
        let box = try XCTUnwrap(p.image?.textBox)
        XCTAssertEqual(box.paragraphs.count, 6, "a 2x3 table")
        XCTAssertEqual(Set(box.paragraphs.compactMap { $0.cell?.table }).count, 1)
        // Half the 468pt text width, less the cell's 5.4pt margins either side.
        XCTAssertEqual(p.image?.width ?? 0, 234 - 10.8, accuracy: 0.01)
        XCTAssertEqual(c.document.paragraphs[i + 1].cell, outer, "the cell still ends in a paragraph")
        XCTAssertEqual(c.document.paragraphs.filter { $0.cell?.table == outer.table }.count, 5, "four cells and the block")
        XCTAssertNotNil(c.textBoxDocument(at: i), "its cells can be edited")
        c.undo()
        XCTAssertTrue(c.document.paragraphs.allSatisfy { $0.keptTable == nil && $0.image == nil }, "one undo step")
        XCTAssertTrue(c.document.keptTables.isEmpty)
        XCTAssertEqual(c.document.paragraphs.filter { $0.cell != nil }.count, 4)
    }

    func testASaveNestsItAsWordDoes() throws {
        let (c, _) = nested()
        let xml = try body(try DocxFormat.write(c.document, pageSetup: .letter))
        XCTAssertEqual(nestedCount(xml), 1, xml)
        XCTAssertTrue(xml.containsSubstring("<w:gridCol w:w=\"1488\"/>"), "the inner grid: 223.2pt in three, \(xml)")
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let j = try XCTUnwrap(back.paragraphs.firstIndex { $0.image?.textBox != nil })
        XCTAssertNotNil(back.paragraphs[j].cell, "read back as a table in a cell")
        XCTAssertEqual(back.paragraphs[j].image?.textBox?.paragraphs.count, 6)
    }

    func testTypingInTheInnerCellsIsKeptNested() throws {
        let (c, i) = nested()
        let inside = try XCTUnwrap(c.textBoxDocument(at: i))
        let box = RichDocumentController(document: inside)
        let k = try XCTUnwrap(box.document.paragraphs.firstIndex { $0.cell?.row == 1 && $0.cell?.column == 2 })
        box.moveTo(RichPosition(paragraph: k, offset: 0), extend: false)
        box.insertText("inner words")
        let (xml, rels, _) = try XCTUnwrap(TextBoxInsert.contentAndMedia(box.document))
        XCTAssertTrue(c.setTextBoxContent(at: i, document: box.document, contentXML: xml, rels: rels))
        let saved = try body(try DocxFormat.write(c.document, pageSetup: .letter))
        XCTAssertEqual(nestedCount(saved), 1, saved)
        XCTAssertTrue(saved.containsSubstring("inner words"))
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let inner = try XCTUnwrap(back.paragraphs.first { $0.image?.textBox != nil }?.image?.textBox)
        XCTAssertEqual(inner.paragraphs.first { $0.cell?.row == 1 && $0.cell?.column == 2 }?.text, "inner words")
        c.undo()
        XCTAssertFalse(try body(try DocxFormat.write(c.document, pageSetup: .letter)).containsSubstring("inner words"), "one undo step")
        XCTAssertEqual(c.document.paragraphs[i].image?.textBox?.paragraphs.contains { $0.text == "inner words" }, false)
    }

    func testAFileNestedTableIsEditableToo() throws {
        let (c, _) = nested()
        let back = RichDocumentController(document: try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document)
        let j = try XCTUnwrap(back.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        XCTAssertNotNil(back.textBoxDocument(at: j), "a nested table read from a file opens for editing")
    }

    /// A file whose outer 1x2 table's first cell holds a 1x2 table, `a` and `b` its cells' paragraphs. (Not one cell alone:
    /// a borderless table of one cell is read as a wrapper, not a table.)
    /// (`b` nil: the paragraph of an inline picture, its file and relationship in the package.)
    private func fileNested(_ a: String, _ b: String?, beside: String = "<w:p><w:r><w:t>x</w:t></w:r></w:p>") throws -> RichDocumentController {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        let base = RichDocument(paragraphs: [RichParagraph(text: "a"), RichParagraph(image: ImageAttachment(data: png, width: 40, height: 20))])
        var entries = try Zip.read(try DocxFormat.write(base, pageSetup: .letter))
        let k = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[k].data, as: UTF8.self)
        var b = b ?? ""
        if b.isEmpty {
            let d = try XCTUnwrap(xml.rangeOfSubstring("<w:drawing>"))
            let open = try XCTUnwrap([xml.range(of: "<w:p>", options: .backwards, range: xml.startIndex ..< d.lowerBound), xml.range(of: "<w:p ", options: .backwards, range: xml.startIndex ..< d.lowerBound)].compactMap { $0 }.max { $0.lowerBound < $1.lowerBound })
            let close = try XCTUnwrap(xml.rangeOfSubstring("</w:p>", in: d.upperBound ..< xml.endIndex))
            b = String(xml[open.lowerBound ..< close.upperBound])
        }
        let from = try XCTUnwrap(xml.rangeOfSubstring("<w:body>")), to = try XCTUnwrap(xml.rangeOfSubstring("<w:sectPr"))
        let grid = "<w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/></w:tblPr>"
        let inner = "<w:tbl>\(grid)<w:tblGrid><w:gridCol w:w=\"2000\"/><w:gridCol w:w=\"2000\"/></w:tblGrid><w:tr>"
            + "<w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr>\(a)</w:tc><w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr>\(b)</w:tc></w:tr></w:tbl>"
        let outer = "<w:tbl>\(grid)<w:tblGrid><w:gridCol w:w=\"6000\"/><w:gridCol w:w=\"3000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"6000\" w:type=\"dxa\"/></w:tcPr>"
            + inner + "<w:p/></w:tc><w:tc><w:tcPr><w:tcW w:w=\"3000\" w:type=\"dxa\"/></w:tcPr>\(beside)</w:tc></w:tr></w:tbl><w:p/>"
        xml.replaceSubrange(from.upperBound ..< to.lowerBound, with: outer)
        entries[k] = ZipEntry(name: entries[k].name, data: Data(xml.utf8))
        return RichDocumentController(document: try DocxFormat.read(try Zip.write(entries)).document)
    }

    /// Fields and tracked changes in the inner cells no longer make the table read-only: an edit in the other cell keeps them.
    func testANestedTableWithAFieldAndRevisionsIsEditable() throws {
        let field = "<w:p><w:r><w:t xml:space=\"preserve\">Page </w:t></w:r><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>"
            + "<w:r><w:instrText xml:space=\"preserve\"> PAGE </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
            + "<w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r></w:p>"
        let revs = "<w:p><w:ins w:id=\"7\" w:author=\"Ann\" w:date=\"2026-01-01T00:00:00Z\"><w:r><w:t>added</w:t></w:r></w:ins>"
            + "<w:del w:id=\"8\" w:author=\"Ann\" w:date=\"2026-01-01T00:00:00Z\"><w:r><w:delText>gone</w:delText></w:r></w:del></w:p>"
        let body1 = "<w:p><w:ins w:id=\"1\" w:author=\"Bo\" w:date=\"2026-01-01T00:00:00Z\"><w:r><w:t>outer</w:t></w:r></w:ins></w:p>"
        let c = try fileNested(field, revs, beside: body1)
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.keptTable != nil })
        XCTAssertTrue(c.isNestedTable(at: i))
        let box = RichDocumentController(document: try XCTUnwrap(c.textBoxDocument(at: i)))
        let k = try XCTUnwrap(box.document.paragraphs.firstIndex { $0.cell?.column == 0 })
        box.moveTo(RichPosition(paragraph: k, offset: 0), extend: false)
        box.insertText("Top ")
        let (xml, rels, _) = try XCTUnwrap(TextBoxInsert.contentAndMedia(box.document))
        XCTAssertTrue(c.setTextBoxContent(at: i, document: box.document, contentXML: xml, rels: rels))
        let saved = try body(try DocxFormat.write(c.document, pageSetup: .letter))
        XCTAssertEqual(nestedCount(saved), 1, saved)
        for kept in ["Top Page", "fldCharType=\"begin\"", "PAGE", "<w:ins ", "added", "<w:del ", "gone"] {
            XCTAssertTrue(saved.containsSubstring(kept), "\(kept) in \(saved)")
        }
        // (One id names one change: the inner table's are moved clear of the body's.)
        let ids = RichDocumentController._annotationIds(in: saved)
        XCTAssertEqual(ids.count, 3, saved)
        XCTAssertEqual(Set(ids).count, ids.count, "ids \(ids)")
        let back = RichDocumentController(document: try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document)
        let j = try XCTUnwrap(back.document.paragraphs.firstIndex { $0.keptTable != nil })
        XCTAssertTrue(back.isNestedTable(at: j), "still editable after the save")
    }

    /// A picture in an inner cell (one the file carried, inline) no longer makes it read-only: an edit beside it keeps it.
    func testANestedTableWithAPictureIsEditable() throws {
        let c = try fileNested("<w:p><w:r><w:t>left</w:t></w:r></w:p>", nil)
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.keptTable != nil })
        XCTAssertTrue(c.isNestedTable(at: i))
        let box = RichDocumentController(document: try XCTUnwrap(c.textBoxDocument(at: i)))
        let k = try XCTUnwrap(box.document.paragraphs.firstIndex { $0.cell?.column == 0 })
        box.moveTo(RichPosition(paragraph: k, offset: 4), extend: false)
        box.insertText(" side")
        let (xml, rels, media) = try XCTUnwrap(TextBoxInsert.contentAndMedia(box.document))
        XCTAssertTrue(c.setTextBoxContent(at: i, document: box.document, contentXML: xml, rels: c.keepBoxMedia(media, rels: rels)))
        let data = try DocxFormat.write(c.document, pageSetup: .letter)
        let saved = try body(data)
        XCTAssertEqual(nestedCount(saved), 1, saved)
        XCTAssertTrue(saved.containsSubstring("left side"))
        let back = try DocxFormat.read(data).document
        let inner = try XCTUnwrap(back.paragraphs.first { $0.keptTable != nil }?.image?.textBox)
        let pic = try XCTUnwrap(inner.paragraphs.lazy.compactMap { $0.image ?? $0.inlineImages.values.first }.first, "the picture is still in its cell")
        XCTAssertFalse(pic.data.isEmpty, "and its file is in the package")
    }
}

/// The same through the app: one click in an inner cell puts the caret there (as Word), typing fills that cell,
/// Escape puts it back as one undo step.
final class NestedTableShellTests: XCTestCase {
    func testClickIntoTheNestedTableAndType() throws {
        setvbuf(stdout, nil, _IONBF, 0)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1440, 932))
        func settle(_ n: Int = 8) { for _ in 0 ..< n { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.03)) } }
        settle(20)
        let shell = try XCTUnwrap(ui.state(OfficeShellState.self))
        let c = shell.session.controller
        c.insertTable(rows: 2, columns: 2)
        let first = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.cell != nil })
        c.moveTo(RichPosition(paragraph: first, offset: 0), extend: false)
        c.insertTable(rows: 2, columns: 2, textWidth: shell.session.pageSetup.contentWidth)
        settle()
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.keptTable != nil })
        let editor = try XCTUnwrap(ui.elements().first { ($0.widget as? RichEditable)?.controller === c })
        let box = try XCTUnwrap(editor.findRenderObject() as? RenderBox)
        let state = try XCTUnwrap((editor as? StatefulElement)?.state as? RichEditableState)
        let r = try XCTUnwrap(state.imageRectOnScreen(i))
        // Picked as an object (keys, a drag across it), it is a table: no Shape Format tab with a size of its own.
        c.selectImage(at: i); settle()
        XCTAssertEqual(shell.session.imageTab, .tableLayout)
        c.moveTo(RichPosition(paragraph: i + 1, offset: 0), extend: false); settle()
        // The inner table's second column, first row, a little in from the cell's corner.
        let at = box.localToGlobal(Offset(r.left + r.width * 0.75, r.top + r.height / 4))
        ui.click(at: at, kind: .mouse); settle()
        XCTAssertNotNil(shell._boxEdit, "one click goes into the nested table")
        let inside = shell.session.controller
        XCTAssertFalse(inside === c)
        let cell = inside.document.paragraphs[inside.selection.focus.paragraph].cell
        XCTAssertEqual(cell?.row, 0, "the caret is in the cell clicked")
        XCTAssertEqual(cell?.column, 1, "the caret is in the cell clicked")
        // Editing keeps the page's layout: the editor lays the table out as wide as the page did.
        let pageFrame = try XCTUnwrap(state._layoutForTests.boxFrame(of: c.document.paragraphs[i].image!, c.document))
        let boxEditor = try XCTUnwrap(ui.elements().first { ($0.widget as? RichEditable)?.controller === inside })
        let boxState = try XCTUnwrap((boxEditor as? StatefulElement)?.state as? RichEditableState)
        XCTAssertEqual(boxState._layoutForTests.width, pageFrame.layout.width, accuracy: 0.01, "editing must not change the layout")
        // Not filled: a white editor hid the outer table's border just past the inner table's corner.
        XCTAssertNil((boxEditor.widget as? RichEditable)?.backgroundColor, "the page shows through the nested table's editor")
        let wordsBefore = shell.session.summary.words
        shell.session.controller.insertText("typed inside")
        settle()
        XCTAssertEqual(shell.session.summary.words, wordsBefore + 2, "the status bar counts the whole document")
        XCTAssertEqual(shell.session.summary.words, c.document.wordCount + 2 - 0 * wordsBefore, "the document total, not the cell")
        XCTAssertTrue(ui.has(text: "Table Design"))
        ui.press(.escape); settle(2)
        XCTAssertNil(shell._boxEdit, "Escape leaves the nested table")
        XCTAssertTrue(shell.session.summary.inCell, "the caret is in the outer cell")
        XCTAssertTrue(ui.has(text: "Table Design"), "the Table tabs stay after Escape")
        XCTAssertTrue(shell.session.controller === c)
        XCTAssertEqual(c.selection.focus.paragraph, i + 1, "leaving it puts the caret in the outer cell under it")
        XCTAssertNil(c.selectedImageIndex)
        // Arrows step into and out of it, as in Word: Left from the line under it goes to the end of its last cell,
        // Right from there back out; Up from under it goes into its last row, Down out again.
        ui.press(.left); settle(2)
        XCTAssertNotNil(shell._boxEdit, "Left from the line under it goes into the nested table")
        var inBox = shell.session.controller
        XCTAssertEqual(inBox.selection.focus, inBox.document.endPosition, "at the end of its last cell")
        XCTAssertTrue(ui.has(text: "Table Design"))
        ui.press(.right); settle(2)
        XCTAssertNil(shell._boxEdit, "Right past its last cell leaves it")
        XCTAssertEqual(c.selection.focus, RichPosition(paragraph: i + 1, offset: 0))
        ui.press(.up); settle(2)
        XCTAssertNotNil(shell._boxEdit, "Up from the line under it goes into the nested table")
        inBox = shell.session.controller
        XCTAssertEqual(inBox.document.paragraphs[inBox.selection.focus.paragraph].cell?.row, 1, "into its last row")
        ui.press(.down); settle(2)
        XCTAssertNil(shell._boxEdit, "Down past its last row leaves it")
        XCTAssertEqual(c.selection.focus.paragraph, i + 1)
        XCTAssertNil(c.selectedImageIndex)
        c.moveTo(RichPosition(paragraph: i + 1, offset: 0), extend: false); settle()
        let inner = try XCTUnwrap(c.document.paragraphs[i].image?.textBox)
        XCTAssertEqual(inner.paragraphs.first { $0.text == "typed inside" }?.cell?.column, 1, "\(inner.paragraphs.map(\.text))")
        let xml = String(decoding: try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.containsSubstring("typed inside"))
        c.undo()
        XCTAssertFalse(c.document.paragraphs[i].image?.textBox?.paragraphs.contains { $0.text == "typed inside" } ?? true, "one undo step")
    }
}
