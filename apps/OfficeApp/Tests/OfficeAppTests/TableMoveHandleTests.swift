import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-TB-1: the table move handle at the table's top-left corner; a click on it selects the whole table.
final class TableMoveHandleTests: XCTestCase {
    private func document() -> RichDocumentController {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "Some text before the table.")]))
        c.moveTo(RichPosition(paragraph: 0, offset: c.document.paragraphs[0].length), extend: false)
        c.insertParagraphBreak()
        c.insertTable(rows: 2, columns: 3)
        return c
    }

    func testSelectTableByNameSelectsEveryCellWhereverTheCaretIs() throws {
        let c = document()
        c.moveTo(RichPosition(paragraph: 0, offset: 2), extend: false)
        let table = try XCTUnwrap(c.document.paragraphs.compactMap(\.cell).first?.table)
        c.selectTable(table)
        let block = try XCTUnwrap(c.selection.block)
        XCTAssertEqual(block.rows, 0 ... 1)
        XCTAssertEqual(block.columns, 0 ... 2)
    }

    func testAClickOnTheHandleSelectsTheTableAndAClickInACellDoesNot() throws {
        let c = document()
        let table = try XCTUnwrap(c.document.paragraphs.compactMap(\.cell).first?.table)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SizedBox(width: 800, height: 600, child: RichEditable(controller: c)), title: "Test"), size: Size(1280, 800))
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let editor = try XCTUnwrap(ui.elements().first { $0.widget is RichEditable })
        let box = try XCTUnwrap(editor.findRenderObject() as? RenderBox)
        let state = try XCTUnwrap(ui.state(RichEditableState.self))
        let handle = try XCTUnwrap(state.tableHandleRect(of: table), "a laid-out table has a handle")
        // Just outside the top-left corner of the first cell.
        let first = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.cell != nil })
        c.moveTo(RichPosition(paragraph: first, offset: 0), extend: false)
        ui.click(at: box.localToGlobal(Offset(handle.right + 6, handle.bottom + 6)), kind: .mouse)
        XCTAssertNil(c.selection.block, "a click in the first cell puts the caret there")
        ui.click(at: box.localToGlobal(handle.center), kind: .mouse)
        let block = try XCTUnwrap(c.selection.block, "the handle selects the table")
        XCTAssertEqual(block.rows, 0 ... 1)
        XCTAssertEqual(block.columns, 0 ... 2)
    }
}
