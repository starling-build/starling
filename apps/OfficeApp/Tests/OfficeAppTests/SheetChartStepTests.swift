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

    /// A title beside the plot: lab xl-step3, Excel's steps for 150 charts 60 to 200 pt tall (one letter a chart, 10 pt
    /// apart: 5, 2, 1 million or h a half), labels at 10 pt, titles one line of 7 to 18 pt. A title placed by hand, or a plot
    /// placed by hand under it, keeps the same steps (the other 60 charts).
    func testATitleTakesItsBoxAndSixMore() {
        let cases: [(String, Double, String)] = [
            ("Calibri", 7, "555222111hhhhhh"),
            ("Calibri", 10, "5555221111hhhhh"),
            ("Calibri", 12.5, "5555221111hhhhh"),
            ("Calibri", 14, "5555222111hhhhh"),
            ("Calibri", 18, "55555221111hhhh"),
            ("新細明體", 7, "555222111hhhhhh"),
            ("新細明體", 10, "5555221111hhhhh"),
            ("新細明體", 12.5, "5555221111hhhhh"),
            ("新細明體", 14, "5555222111hhhhh"),
            ("新細明體", 18, "55555221111hhhh"),
        ]
        let value: [Character: Double] = ["5": 5e6, "2": 2e6, "1": 1e6, "h": 5e5]
        for (face, t, steps) in cases {
            for (i, ch) in steps.enumerated() {
                let h = 60 + 10 * Double(i)
                let n = ChartPainter.sheetValueSteps(frameHeight: h, face: face, labelSize: 10, categorySize: nil, categoryTitleSize: nil, titleSize: t, titleFace: face)
                XCTAssertEqual(ChartPainter.scale(0, 2_917_735, intervals: n).step, value[ch], "\(face) title \(t) at \(h) pt")
            }
        }
    }

    /// A bare category title (no text properties) prints in Arial, and takes Arial's line: Excel's print of
    /// chart-tdf119138-missing-autotitledeleted (212.6 pt frame, Arial 18 pt title and category title, Calibri 10 pt labels)
    /// steps its 10-70 data by 10, not 20.
    func testABareCategoryTitleTakesArialsLine() {
        let n = ChartPainter.sheetValueSteps(frameHeight: 212.6, face: "Calibri", labelSize: 10, categorySize: 10, categoryTitleSize: 18,
                                             titleSize: 18, titleFace: "Arial", categoryTitleFace: "Arial")
        XCTAssertEqual(ChartPainter.scale(10, 70, intervals: n).step, 10, "\(n) steps")
    }
}
