import XCTest
@testable import OfficeApp

/// Excel's automatic value-axis step on a sheet chart follows the label face's line: lab xl-step2, Excel's prints of a
/// line chart (data 2,917,735 and 1,500,000, category axis deleted) 145 pt wide and 60 to 200 pt tall in eight faces.
final class SheetChartStepTests: XCTestCase {
    private func step(_ face: String, _ size: Double, height: Double) -> Double {
        let n = ChartPainter.sheetValueSteps(frameHeight: height, face: face, labelSize: size, categorySize: nil, categoryTitleSize: nil)
        return ChartPainter.scale(0, 2_917_735, intervals: n).step
    }

    /// One 100 pt chart: Calibri 10 goes by millions, the taller Yu Gothic and Malgun Gothic lines by two millions,
    /// Calibri 7 by halves (the old rule, blind to the face, gave every one of them millions).
    func testTheStepFollowsTheLabelFaceAtOneHeight() {
        XCTAssertEqual(step("Calibri", 10, height: 100), 1_000_000)
        XCTAssertEqual(step("Yu Gothic", 10, height: 100), 2_000_000)
        XCTAssertEqual(step("游ゴシック", 10, height: 100), 2_000_000)
        XCTAssertEqual(step("Malgun Gothic", 10, height: 100), 2_000_000)
        XCTAssertEqual(step("Calibri", 7, height: 100), 500_000)
    }

    /// Where each face's step changes as the chart grows (Excel COM and print agree on all 120).
    func testTheStepShrinksAsThePlotGrows() {
        let cases: [(String, Double, [(Double, Double)])] = [
            ("Calibri", 10, [(70, 5e6), (80, 2e6), (90, 2e6), (100, 1e6), (130, 1e6), (140, 5e5)]),
            ("Calibri", 14, [(90, 5e6), (100, 2e6), (120, 2e6), (130, 1e6), (170, 1e6), (180, 5e5)]),
            ("MS PGothic", 10, [(60, 5e6), (70, 2e6), (80, 2e6), (90, 1e6), (110, 1e6), (120, 5e5)]),
            ("Arial", 10, [(60, 5e6), (70, 2e6), (90, 2e6), (100, 1e6), (120, 1e6), (130, 5e5)]),
            ("Malgun Gothic", 10, [(70, 5e6), (80, 2e6), (100, 2e6), (110, 1e6), (140, 1e6), (150, 5e5)]),
            ("Yu Gothic", 10, [(80, 5e6), (90, 2e6), (110, 2e6), (120, 1e6), (160, 1e6), (170, 5e5)]),
        ]
        for (face, size, steps) in cases {
            for (h, want) in steps { XCTAssertEqual(step(face, size, height: h), want, "\(face) \(size) at \(h) pt") }
        }
    }
}
