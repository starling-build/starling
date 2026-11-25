import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// AutoFit and Distribute Rows.
final class AutoFitTests: XCTestCase {
    private func table() -> RichDocumentController {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 3, columns: 2)
        let i = c.document.paragraphs.firstIndex { $0.cell != nil }!
        c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
        return c
    }

    func testAutoFitVariants() {
        let c = table()
        c.autoFitTable(.fixed)
        XCTAssertTrue(c.currentTableStyle!.fixedLayout)
        c.autoFitTable(.window)
        XCTAssertFalse(c.currentTableStyle!.fixedLayout)
        XCTAssertEqual(c.currentTableStyle!.widthPercent, 100)
        c.autoFitTable(.contents)
        XCTAssertNil(c.currentTableStyle!.widthPercent)
        XCTAssertNil(c.currentTableStyle!.width)
    }

    func testAutoFitToContentsWritesAutoCellWidthsAndWindowKeepsThem() throws {
        func cellWidths(_ c: RichDocumentController) throws -> String {
            let data = try DocxFormat.write(c.document, pageSetup: .letter)
            let doc = try XCTUnwrap(try Zip.read(data).first { $0.name == "word/document.xml" })
            return String(decoding: doc.data, as: UTF8.self)
        }
        let c = table()
        c.autoFitTable(.contents)
        var xml = try cellWidths(c)
        XCTAssertTrue(xml.contains("<w:tcW w:w=\"0\" w:type=\"auto\"/>"))
        XCTAssertFalse(xml.contains("w:type=\"dxa\"/></w:tcPr>"))
        c.autoFitTable(.window)
        xml = try cellWidths(c)
        XCTAssertFalse(xml.contains("<w:tcW w:w=\"0\" w:type=\"auto\"/>"))
    }

    func testDistributeRowsGivesEveryRowTheTallest() {
        let c = table()
        let cells = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        let heights = [20.0, 50.0, 30.0]
        c.rowHeightProbe = { i in c.document.paragraphs[i].cell.map { heights[$0.row] } }
        c.distributeRows()
        let s = c.currentTableStyle!
        XCTAssertEqual([0, 1, 2].map { s.rowHeights[$0] }, [50, 50, 50])
        c.undo()
        XCTAssertNil(c.currentTableStyle?.rowHeights[0])
        _ = cells
    }
}

/// Writes the Word lab for AutoFit / Distribute Rows when AUTOFIT_LAB_OUT names a file (skipped otherwise).
final class AutoFitLabWriter: XCTestCase {
    func testWriteLab() throws {
        guard let out = ProcessInfo.processInfo.environment["AUTOFIT_LAB_OUT"] else { throw XCTSkip("no AUTOFIT_LAB_OUT") }
        let c = RichDocumentController(plainText: "")
        func addTable(_ title: String, _ fit: RichDocumentController.TableFit?, distribute: Bool = false) {
            c.moveTo(RichPosition(paragraph: c.document.paragraphs.count - 1, offset: 0), extend: false)
            c.insertText(title)
            c.insertParagraphBreak()
            c.insertTable(rows: 3, columns: 3)
            let idx = Array(c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }.suffix(9))
            let texts = ["a", "A longer cell of text", "mid", "b", "c", "d d d d d d d d d d", "e", "f", "g"]
            for (k, i) in idx.enumerated() {
                c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
                c.insertText(texts[k])
            }
            c.moveTo(RichPosition(paragraph: idx.first!, offset: 0), extend: false)
            if let fit { c.autoFitTable(fit) }
            if distribute {
                c.setRowHeight(20); c.moveTo(RichPosition(paragraph: idx[3], offset: 0), extend: false); c.setRowHeight(40)
                c.moveTo(RichPosition(paragraph: idx[6], offset: 0), extend: false); c.setRowHeight(30)
                c.rowHeightProbe = { i in c.document.paragraphs[i].cell.map { [20.0, 40.0, 30.0][$0.row] } }
                c.moveTo(RichPosition(paragraph: idx[0], offset: 0), extend: false)
                c.distributeRows()
            }
            c.moveTo(RichPosition(paragraph: c.document.paragraphs.count - 1, offset: 0), extend: false)
        }
        addTable("AutoFit to contents", .contents)
        addTable("AutoFit to window", .window)
        addTable("Fixed column width", .fixed)
        addTable("Distribute rows", nil, distribute: true)
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }
}
