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
        shell.session.controller.insertText("typed inside")
        settle()
        shell._leaveBox(); settle()
        XCTAssertTrue(shell.session.controller === c)
        XCTAssertEqual(c.selection.focus.paragraph, i + 1, "leaving it puts the caret in the outer cell under it")
        XCTAssertNil(c.selectedImageIndex)
        let inner = try XCTUnwrap(c.document.paragraphs[i].image?.textBox)
        XCTAssertEqual(inner.paragraphs.first { $0.text == "typed inside" }?.cell?.column, 1, "\(inner.paragraphs.map(\.text))")
        let xml = String(decoding: try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.containsSubstring("typed inside"))
        c.undo()
        XCTAssertFalse(c.document.paragraphs[i].image?.textBox?.paragraphs.contains { $0.text == "typed inside" } ?? true, "one undo step")
    }
}
