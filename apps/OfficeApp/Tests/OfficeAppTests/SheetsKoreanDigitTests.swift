// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// Excel's own widest-digit width for the Korean faces: from the Windows
/// print of lab/dotumcols (colwidths.tsv, sheet "widths", column G = a width
/// of 20 characters, Range.Width in points). A digit is Range.Width / 20 / 0.75 px.
final class SheetsKoreanDigitTests: XCTestCase {
    func testDigitWidthsMatchExcelColumnWidths() {
        let rows: [(String, Double, Double)] = [   // face, size, Range.Width of a 20-character column
            ("Dotum", 9, 97.5), ("Dotum", 10, 120), ("Dotum", 11, 127.5), ("Dotum", 12, 142.5),
            ("Gulim", 9, 97.5), ("Gulim", 12, 135),
            ("Batang", 9, 90), ("Batang", 12, 142.5),
            ("DotumChe", 10, 105), ("DotumChe", 11, 112.5), ("DotumChe", 12, 120),
            ("돋움", 10, 120),
        ]
        for (face, size, pt) in rows {
            XCTAssertEqual(Workbook.digitWidth(family: face, size: size), pt / 20 / 0.75, "\(face) \(size)")
        }
    }
}
