import XCTest
import Foundation
@testable import OfficeApp

/// A whole-sheet selection is 1,048,576 × 16,384 = 2^34 cells, past a 32-bit
/// Int: in the browser (wasm32) `rows * cols` trapped, so Ctrl+A in Sheets
/// killed the app. `area` saturates instead, and no Sheets code multiplies a
/// range's rows by its cols directly.
final class SheetsRangeAreaTests: XCTestCase {
    func testWholeSheetArea() {
        let all = CellRange(top: 0, left: 0, bottom: 1_048_575, right: 16_383)
        XCTAssertEqual(all.area, 1_048_576 * 16_384)
        XCTAssertEqual(CellRange(top: 0, left: 0, bottom: 2, right: 3).area, 12)
    }

    func testAreaSaturates() {
        let huge = CellRange(top: 0, left: 0, bottom: Int.max / 2, right: 3)
        XCTAssertEqual(huge.area, Int.max)
    }

    func testNoPlainRowsTimesCols() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/OfficeApp/Sheets").standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty)
        let pattern = try NSRegularExpression(pattern: #"\.rows \* [\w.$]*\.cols\b"#)
        var hits: [String] = []
        for f in files.sorted() {
            let text = try String(contentsOfFile: dir.appendingPathComponent(f).path, encoding: .utf8)
            for (i, line) in text.components(separatedBy: "\n").enumerated()
            where pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                hits.append("\(f):\(i + 1)")
            }
        }
        XCTAssertEqual(hits, [], "use CellRange.area (32-bit safe) instead of rows * cols")
    }
}
