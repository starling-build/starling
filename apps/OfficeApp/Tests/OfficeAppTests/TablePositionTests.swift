import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-TB-5: a table dragged by its move handle floats, as in Word; Table Properties > Around > Positioning sets where.
final class TablePositionTests: XCTestCase {
    private func document() -> RichDocumentController {
        TableStyleGallery.install()
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "Some text before the table.")]))
        c.moveTo(RichPosition(paragraph: 0, offset: c.document.paragraphs[0].length), extend: false)
        c.insertParagraphBreak()
        c.insertTable(rows: 2, columns: 3)
        return c
    }
    private func table(_ c: RichDocumentController) -> String { c.document.paragraphs.compactMap(\.cell).first!.table }

    func testThePositionReadsAndWritesAsWordDoes() throws {
        var p = TablePosition()
        p.x = 36; p.y = 18.5; p.horizontalFrom = .margin; p.verticalFrom = .page; p.top = 4; p.allowOverlap = false
        XCTAssertEqual(p.xml, #"<w:tblpPr w:leftFromText="180" w:rightFromText="180" w:topFromText="80" w:vertAnchor="page" w:horzAnchor="margin" w:tblpX="720" w:tblpY="370"/><w:tblOverlap w:val="never"/>"#)
        XCTAssertEqual(TablePosition(xml: p.xml), p)
        p.horizontalAlign = "center"; p.verticalAlign = "bottom"; p.x = 0; p.y = 0
        XCTAssertEqual(TablePosition(xml: p.xml), p)
        XCTAssertTrue(p.xml.containsSubstring(#"w:tblpXSpec="center""#))
        XCTAssertFalse(p.xml.containsSubstring("w:tblpX=\""))
        XCTAssertNil(TablePosition(xml: "<w:tblLayout/>"))
        p.movesWithText = true
        XCTAssertEqual(p.verticalFrom, .paragraph)
        p.movesWithText = false
        XCTAssertEqual(p.verticalFrom, .margin, "Move with text off measures from the margin")
    }

    func testSettingAPositionIsOneUndoStepAndSurvivesASave() throws {
        let c = document()
        let t = table(c)
        var p = TablePosition()
        p.x = 100; p.y = 24
        c.setTablePosition(of: t, p.xml)
        let s = try XCTUnwrap(c.document.tableStyles[t])
        XCTAssertEqual(s.floatX, 100, "the layout reads the place at once")
        XCTAssertEqual(s.floatOffsetY, 24)
        XCTAssertEqual(TablePosition(xml: s.keptPosition), p)

        let data = try DocxFormat.write(c.document, pageSetup: .letter)
        let doc = try XCTUnwrap(try Zip.read(data).first { $0.name == "word/document.xml" }.map { String(decoding: $0.data, as: UTF8.self) })
        XCTAssertTrue(doc.containsSubstring(#"<w:tblpPr w:leftFromText="180" w:rightFromText="180" w:tblpX="2000" w:tblpY="480" w:vertAnchor="text"/>"#), doc)
        let back = try DocxFormat.read(data).document
        let bt = try XCTUnwrap(back.paragraphs.compactMap(\.cell).first?.table)
        XCTAssertEqual(back.tableStyles[bt]?.floatX, 100)
        XCTAssertEqual(back.tableStyles[bt]?.floatOffsetY, 24)
        XCTAssertEqual(TablePosition(xml: back.tableStyles[bt]?.keptPosition), p)

        c.undo()
        XCTAssertNil(c.document.tableStyles[t]?.keptPosition, "one undo step")
        XCTAssertNil(c.document.tableStyles[t]?.floatX)
        c.setTablePosition(of: t, p.xml)
        c.setTablePosition(of: t, nil)
        XCTAssertNil(c.document.tableStyles[t]?.floatX, "None takes the place away")
        XCTAssertNil(c.document.tableStyles[t]?.floatOffsetY)
    }

    func testDraggingTheHandleFloatsTheTableAndAClickStillSelectsIt() throws {
        let c = document()
        let t = table(c)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SizedBox(width: 800, height: 600, child: RichEditable(controller: c)), title: "Test"), size: Size(1280, 800))
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let editor = try XCTUnwrap(ui.elements().first { $0.widget is RichEditable })
        let box = try XCTUnwrap(editor.findRenderObject() as? RenderBox)
        let state = try XCTUnwrap(ui.state(RichEditableState.self))
        let handle = try XCTUnwrap(state.tableHandleRect(of: t))
        ui.click(at: box.localToGlobal(handle.center), kind: .mouse)
        XCTAssertNotNil(c.selection.block, "a click without a move selects the table")
        XCTAssertNil(c.document.tableStyles[t]?.keptPosition, "and does not float it")

        let pt = handle.width / 8   // the handle is 8 points square
        ui.drag(from: box.localToGlobal(handle.center), to: box.localToGlobal(handle.center + Offset(60 * pt, 30 * pt)), kind: .mouse)
        for _ in 0 ..< 3 { ui.pump() }
        let p = try XCTUnwrap(TablePosition(xml: c.document.tableStyles[t]?.keptPosition), "a drag floats the inline table")
        XCTAssertEqual(p.horizontalFrom, .column)
        XCTAssertEqual(p.verticalFrom, .paragraph, "it moves with its paragraph, as Word sets a dragged table")
        XCTAssertEqual(p.x, 60, accuracy: 1)
        XCTAssertEqual(p.y, 30, accuracy: 1)
        XCTAssertEqual(c.document.tableStyles[t]?.floatX ?? 0, p.x, accuracy: 0.01)
        c.undo()
        XCTAssertNil(c.document.tableStyles[t]?.keptPosition, "the drag is one undo step")
    }

    func testThePositioningDialogSetsThePlace() throws {
        let c = document()
        let t = table(c)
        let first = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.cell != nil })
        c.moveTo(RichPosition(paragraph: first, offset: 0), extend: false)
        var v = TablePropertiesValues(of: c)
        v.wrap = .around
        v.position.horizontalAlign = "center"
        v.position.horizontalFrom = .margin
        v.position.y = 12
        v.apply(to: c)
        let s = try XCTUnwrap(c.document.tableStyles[t])
        XCTAssertEqual(TablePosition(xml: s.keptPosition)?.horizontalAlign, "center")
        XCTAssertEqual(s.alignment, .center, "a centred float is laid out centred")
        XCTAssertEqual(s.floatOffsetY, 12)
        var w = TablePropertiesValues(of: c)
        XCTAssertEqual(w.position.horizontalAlign, "center", "the dialog opens on the table's place")
        w.wrap = .none
        w.apply(to: c)
        XCTAssertNil(c.document.tableStyles[t]?.keptPosition)
        XCTAssertNil(c.document.tableStyles[t]?.floatOffsetY)
    }
}
