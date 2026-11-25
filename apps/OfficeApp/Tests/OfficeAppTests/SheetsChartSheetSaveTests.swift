import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A plain save of a book with a chart sheet keeps the chart sheet's part and its chartsheet link.
final class SheetsChartSheetSaveTests: XCTestCase {
    private func zip(_ d: Data) throws -> [String: Data] { Dictionary(try Zip.read(d).map { ($0.name, $0.data) }, uniquingKeysWith: { $1 }) }
    private func text(_ f: [String: Data], _ p: String) -> String { f[p].map { String(decoding: $0, as: UTF8.self) } ?? "" }

    func testChartSheetSurvivesASave() throws {
        let path = "/data/corpus-cache/test/corpus/xlsx/books/WithChartSheet.xlsx"
        guard let data = FileManager.default.contents(atPath: path) else { throw XCTSkip("no WithChartSheet.xlsx") }
        let orig = try zip(data)
        let c = WorkbookController()
        c.load(try Xlsx.read(data))
        let out = try zip(try Xlsx.write(c.book))
        XCTAssertEqual(out["xl/chartsheets/sheet1.xml"], orig["xl/chartsheets/sheet1.xml"])
        let rels = text(out, "xl/_rels/workbook.xml.rels")
        XCTAssertTrue(rels.containsSubstring("relationships/chartsheet\" Target=\"chartsheets/sheet1.xml\""))
        XCTAssertFalse(rels.containsSubstring("relationships/worksheet\" Target=\"chartsheets/"))
        XCTAssertEqual(text(out, "xl/workbook.xml").components(separatedBy: "<sheet ").count, text(orig, "xl/workbook.xml").components(separatedBy: "<sheet ").count)
    }
}
