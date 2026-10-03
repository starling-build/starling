// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsConditionalTests: XCTestCase {
    /// A1:A6 = 10, 20, 30, 40, 50, "x"; B1:B6 the same numbers.
    private func sheet(_ rules: [String]) -> WorkbookController {
        let c = WorkbookController()
        var items: [(CellAddress, String)] = []
        for (i, v) in ["10", "20", "30", "40", "50", "x"].enumerated() {
            items.append((CellAddress(row: i, col: 0), v))
            if i < 5 { items.append((CellAddress(row: i, col: 1), v)) }
        }
        c.setInputs(items)
        c.book.dxfs = [DxfStyle(bold: true, color: 0x9C0006, fill: 0xFFC7CE), DxfStyle(italic: true, fill: 0xC6EFCE)]
        c.sheet.keptElements = rules.map { ("conditionalFormatting", $0) }
        return c
    }

    private func look(_ c: WorkbookController, _ a: String) -> CFLook? { c.conditionalFormats()?.look(CellAddress(a)!) }

    func testCellIsAndPriority() {
        let c = sheet([
            "<conditionalFormatting sqref=\"A1:A6\"><cfRule type=\"cellIs\" dxfId=\"0\" priority=\"2\" operator=\"greaterThan\"><formula>25</formula></cfRule>"
            + "<cfRule type=\"cellIs\" dxfId=\"1\" priority=\"1\" operator=\"between\"><formula>40</formula><formula>60</formula></cfRule></conditionalFormatting>",
        ])
        XCTAssertNil(look(c, "A2"))
        XCTAssertEqual(look(c, "A3")?.dxf.fill, 0xFFC7CE)
        // A4 matches both: the higher priority (1) fills, the other still adds bold.
        XCTAssertEqual(look(c, "A4")?.dxf.fill, 0xC6EFCE)
        XCTAssertEqual(look(c, "A4")?.dxf.bold, true)
        XCTAssertEqual(look(c, "A4")?.dxf.italic, true)
        XCTAssertNil(look(c, "B4"))                 // outside the range
    }

    func testExpressionIsRelativeToTheRange() {
        // =$B1>=30 down A1:A5: each row looks at its own B.
        let c = sheet(["<conditionalFormatting sqref=\"A1:A5\"><cfRule type=\"expression\" dxfId=\"0\" priority=\"1\"><formula>$B1&gt;=30</formula></cfRule></conditionalFormatting>"])
        XCTAssertNil(look(c, "A2"))
        XCTAssertNotNil(look(c, "A3"))
        XCTAssertNotNil(look(c, "A5"))
        // The figures follow the data: an edit re-evaluates.
        c.setInputs([(CellAddress("B2")!, "99")])
        XCTAssertNotNil(look(c, "A2"))
    }

    func testScalesBarsAndRanks() {
        let c = sheet([
            "<conditionalFormatting sqref=\"A1:A5\"><cfRule type=\"colorScale\" priority=\"1\"><colorScale><cfvo type=\"min\"/><cfvo type=\"max\"/><color rgb=\"FFFFFFFF\"/><color rgb=\"FF000000\"/></colorScale></cfRule></conditionalFormatting>",
            "<conditionalFormatting sqref=\"B1:B5\"><cfRule type=\"dataBar\" priority=\"2\"><dataBar><cfvo type=\"min\"/><cfvo type=\"max\"/><color rgb=\"FF638EC6\"/></dataBar></cfRule>"
            + "<cfRule type=\"top10\" dxfId=\"0\" priority=\"3\" rank=\"2\"/><cfRule type=\"aboveAverage\" dxfId=\"1\" priority=\"4\" aboveAverage=\"0\"/></conditionalFormatting>",
        ])
        XCTAssertEqual(look(c, "A1")?.fill, 0xFFFFFF)
        XCTAssertEqual(look(c, "A3")?.fill, 0x808080)      // the middle of white..black
        XCTAssertEqual(look(c, "A5")?.fill, 0x000000)
        XCTAssertEqual(look(c, "B1")?.bar?.fraction ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(look(c, "B5")?.bar?.fraction ?? 0, 0.9, accuracy: 1e-9)
        XCTAssertEqual(look(c, "B5")?.dxf.bold, true)      // top 2: 40 and 50
        XCTAssertEqual(look(c, "B4")?.dxf.bold, true)
        XCTAssertNil(look(c, "B3")?.dxf.bold)
        XCTAssertEqual(look(c, "B1")?.dxf.italic, true)    // below the average of 30
        XCTAssertNil(look(c, "B3")?.dxf.italic)
    }

    func testTimePeriods() {
        // A Wednesday: 2026-10-07.
        let today = ExcelDate.serial(2026, 10, 7)
        func hit(_ p: String, _ y: Int, _ m: Int, _ d: Int) -> Bool { CFEvaluator.inPeriod(ExcelDate.serial(y, m, d), p, today: today) }
        XCTAssertTrue(hit("today", 2026, 10, 7)); XCTAssertFalse(hit("today", 2026, 10, 6))
        XCTAssertTrue(hit("yesterday", 2026, 10, 6)); XCTAssertTrue(hit("tomorrow", 2026, 10, 8))
        XCTAssertTrue(hit("last7Days", 2026, 10, 1)); XCTAssertFalse(hit("last7Days", 2026, 9, 30))
        XCTAssertTrue(hit("thisWeek", 2026, 10, 4)); XCTAssertTrue(hit("thisWeek", 2026, 10, 10))   // Sunday to Saturday
        XCTAssertFalse(hit("thisWeek", 2026, 10, 11))
        XCTAssertTrue(hit("lastWeek", 2026, 10, 3)); XCTAssertTrue(hit("nextWeek", 2026, 10, 11))
        XCTAssertTrue(hit("thisMonth", 2026, 10, 31)); XCTAssertTrue(hit("lastMonth", 2026, 9, 1))
        XCTAssertTrue(hit("nextMonth", 2026, 11, 30)); XCTAssertFalse(hit("nextMonth", 2026, 12, 1))
        // Through a rule: A1 holds today's serial, A2 yesterday's.
        let c = sheet(["<conditionalFormatting sqref=\"A1:A2\"><cfRule type=\"timePeriod\" dxfId=\"0\" priority=\"1\" timePeriod=\"today\"><formula>FLOOR(A1,1)=TODAY()</formula></cfRule></conditionalFormatting>"])
        let now = floor(ExcelDate.now())
        c.setInputs([(CellAddress("A1")!, String(Int(now))), (CellAddress("A2")!, String(Int(now) - 1))])
        XCTAssertEqual(look(c, "A1")?.dxf.fill, 0xFFC7CE)
        XCTAssertNil(look(c, "A2"))
    }

    func testTextBlanksAndDuplicates() {
        let c = sheet([
            "<conditionalFormatting sqref=\"A1:A8\"><cfRule type=\"containsText\" dxfId=\"0\" priority=\"1\" operator=\"containsText\" text=\"X\"/>"
            + "<cfRule type=\"containsBlanks\" dxfId=\"1\" priority=\"2\"/></conditionalFormatting>",
            "<conditionalFormatting sqref=\"A1:B5\"><cfRule type=\"duplicateValues\" dxfId=\"1\" priority=\"3\"/></conditionalFormatting>",
        ])
        XCTAssertEqual(look(c, "A6")?.dxf.fill, 0xFFC7CE)
        XCTAssertEqual(look(c, "A7")?.dxf.fill, 0xC6EFCE)  // blank
        XCTAssertEqual(look(c, "B2")?.dxf.fill, 0xC6EFCE)  // 20 is in A and B
    }
}

extension SheetsConditionalTests {
    func testIconSets() {
        // A1:A5 = 10…50: percent thresholds 33 and 67 of 10..50 are 23.2 and 36.8.
        let c = sheet([
            "<conditionalFormatting sqref=\"A1:A5\"><cfRule type=\"iconSet\" priority=\"1\"><iconSet iconSet=\"3Arrows\"><cfvo type=\"percent\" val=\"0\"/><cfvo type=\"percent\" val=\"33\"/><cfvo type=\"percent\" val=\"67\"/></iconSet></cfRule></conditionalFormatting>",
            "<conditionalFormatting sqref=\"B1:B5\"><cfRule type=\"iconSet\" priority=\"2\"><iconSet iconSet=\"3Flags\" reverse=\"1\" showValue=\"0\"><cfvo type=\"num\" val=\"0\"/><cfvo type=\"num\" val=\"20\"/><cfvo type=\"num\" val=\"40\" gte=\"0\"/></iconSet></cfRule></conditionalFormatting>",
        ])
        XCTAssertEqual(look(c, "A1")?.icon?.index, 0)
        XCTAssertEqual(look(c, "A3")?.icon?.index, 1)
        XCTAssertEqual(look(c, "A4")?.icon?.index, 2)
        XCTAssertEqual(look(c, "A1")?.icon?.set, "3Arrows")
        // Reversed, value hidden; 40 is not > 40.
        XCTAssertEqual(look(c, "B1")?.icon?.index, 2)
        XCTAssertEqual(look(c, "B4")?.icon?.index, 1)
        XCTAssertEqual(look(c, "B5")?.icon?.index, 0)
        XCTAssertEqual(look(c, "B5")?.icon?.showValue, false)
    }
}
