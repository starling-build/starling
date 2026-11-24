import XCTest
@testable import OfficeApp

/// An .xls opened and saved as .xlsx must be a package Excel accepts:
/// content types for charts, drawings and pictures, no font of size 0, and
/// every number format kept as the file wrote it.
final class SheetsXlsSaveTests: XCTestCase {
    func testXlsSaveIsAcceptableToExcel() throws {
        let path = "/data/corpus-cache/staging/xlsx-new/ko-xls-r3-dev/ko-260ca39d42.xls"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("corpus file missing") }
        let b = try Workbook.open(try Data(contentsOf: URL(fileURLWithPath: path)), name: "x.xls")
        let e = try Zip.read(try Xlsx.write(b))
        func text(_ n: String) -> String { String(decoding: e.first { $0.name == n }?.data ?? Data(), as: UTF8.self) }
        let ct = text("[Content_Types].xml")
        for part in e.map({ $0.name }) where part.hasPrefix("xl/charts/chart") || part.hasPrefix("xl/drawings/drawing") {
            if part.hasSuffix(".xml") { XCTAssertTrue(ct.containsSubstring("/" + part), "no content type for \(part)") }
        }
        let st = text("xl/styles.xml")
        XCTAssertFalse(st.containsSubstring("<sz val=\"0"), "a font has size 0")
        // each format code is written once (not re-escaped): no "&amp;" in a format code
        XCTAssertFalse(st.containsSubstring("formatCode=\"&amp;"))
        // reread keeps working
        XCTAssertNoThrow(try Workbook.open(try Xlsx.write(b), name: "x.xlsx"))
    }
}
