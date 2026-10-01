// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// Against the values Excel's own documentation gives for each function.
final class SheetsMoreFunctionTests: XCTestCase {
    private let c = WorkbookController()
    private func e(_ f: String) -> CellValue { c.engine.evaluate(f, sheet: 0, at: CellAddress("Z1")!) }
    private func n(_ f: String, _ x: Double, accuracy: Double = 1e-6, line: UInt = #line) {
        guard case .number(let v) = e(f) else { return XCTFail("\(f) = \(e(f))", line: line) }
        XCTAssertEqual(v, x, accuracy: accuracy, f, line: line)
    }

    func testStatistics() {
        n("=LARGE({3,5,1,9},2)", 5); n("=SMALL({3,5,1,9},2)", 3)
        n("=RANK(5,{3,5,1,9})", 2); n("=RANK(5,{3,5,1,9},1)", 3)
        n("=RANK.AVG(2,{1,2,2,3})", 2.5, line: #line)
        n("=PERCENTILE({1,2,3,4},0.3)", 1.9); n("=QUARTILE({1,2,4,7,8,9,10,12},1)", 3.5)
        n("=PERCENTILE.EXC({1,2,3,4},0.3)", 1.5)
        n("=MODE({1,2,2,3})", 2); n("=GEOMEAN({4,5,8,7,11,4,3})", 5.476986969)
        n("=HARMEAN({4,5,8,7,11,4,3})", 5.028375962); n("=AVEDEV({4,5,6,7,5,4,3})", 1.020408163)
        n("=DEVSQ({4,5,8,7,11,4,3})", 48)
        n("=SLOPE({2,3,9,1,8,7,5},{6,5,11,7,5,4,4})", 0.305555556)
        n("=INTERCEPT({2,3,9,1,8},{6,5,11,7,5})", 0.048387097)
        n("=CORREL({3,2,4,5,6},{9,7,12,15,17})", 0.997054486)
        n("=RSQ({2,3,9,1,8,7,5},{6,5,11,7,5,4,4})", 0.057950192)
        n("=FORECAST(30,{6,7,9,15,21},{20,28,31,38,40})", 10.60725308)
        n("=NORM.S.DIST(1.333333,TRUE)", 0.908788726); n("=NORM.DIST(42,40,1.5,TRUE)", 0.908788780)
        n("=NORM.S.INV(0.908789)", 1.333334673, accuracy: 1e-5); n("=NORM.INV(0.908789,40,1.5)", 42.000002, accuracy: 1e-4)
    }

    func testMaths() {
        n("=GCD(5,2)", 1); n("=GCD(24,36)", 12); n("=LCM(24,36)", 72); n("=COMBIN(8,2)", 28); n("=PERMUT(100,3)", 970200)
        n("=FACT(5)", 120); n("=QUOTIENT(-10,3)", -3); n("=MROUND(10,3)", 9); n("=MROUND(-10,-3)", -9)
        n("=EVEN(1.5)", 2); n("=EVEN(-1)", -2); n("=ODD(1.5)", 3); n("=ODD(2)", 3)
        n("=CEILING.MATH(-8.1,2)", -8); n("=CEILING.MATH(-5.5,2,-1)", -6); n("=FLOOR.MATH(-8.1,2)", -10)
        n("=SUMSQ(3,4)", 25); n("=DEGREES(PI())", 180); n("=ATAN2(1,1)", 0.785398163); n("=SIN(PI()/2)", 1)
    }

    func testLookupAndInfo() {
        c.setInputs([(CellAddress("A1")!, "10"), (CellAddress("A2")!, "20"), (CellAddress("A3")!, "30"),
                      (CellAddress("B1")!, "x"), (CellAddress("B2")!, "y"), (CellAddress("B3")!, "x"),
                      (CellAddress("A4")!, "=SUBTOTAL(9,A1:A3)")])
        n("=MAXIFS(A1:A3,B1:B3,\"x\")", 30); n("=MINIFS(A1:A3,B1:B3,\"x\")", 10)
        XCTAssertEqual(e("=SWITCH(2,1,\"a\",2,\"b\",\"c\")"), .text("b"))
        XCTAssertEqual(e("=SWITCH(9,1,\"a\",\"none\")"), .text("none"))
        n("=XMATCH(25,A1:A3,-1)", 2); n("=XMATCH(25,A1:A3,1)", 3); n("=XMATCH(\"y\",B1:B3)", 2)
        XCTAssertEqual(e("=LOOKUP(25,A1:A3,B1:B3)"), .text("y"))
        XCTAssertEqual(e("=ADDRESS(2,3)"), .text("$C$2")); XCTAssertEqual(e("=ADDRESS(2,3,4)"), .text("C2"))
        n("=SUM(OFFSET(A1,1,0,2,1))", 50); n("=INDIRECT(\"A3\")", 30); n("=SUM(INDIRECT(\"A1:A2\"))", 30)
        XCTAssertEqual(e("=ISFORMULA(A4)"), .bool(true))
        n("=N(TRUE)", 1); XCTAssertEqual(e("=T(5)"), .text("")); n("=TYPE(\"a\")", 2); n("=ERROR.TYPE(1/0)", 2)
        // SUBTOTAL skips other SUBTOTALs and rows a filter hid.
        n("=SUBTOTAL(9,A1:A4)", 60); n("=SUBTOTAL(1,A1:A3)", 20)
        c.sheet.filteredRows = [1]
        c.engine.recalculate()
        n("=SUBTOTAL(9,A1:A3)", 40); n("=SUBTOTAL(109,A1:A3)", 40); n("=AGGREGATE(9,5,A1:A3)", 40)
        n("=AGGREGATE(14,6,A1:A3,1)", 30)
    }

    func testTextAndDates() {
        XCTAssertEqual(e("=REPLACE(\"abcdefghijk\",6,5,\"*\")"), .text("abcde*k"))
        XCTAssertEqual(e("=TEXTBEFORE(\"Red riding hood's, red hood\",\"hood\")"), .text("Red riding "))
        XCTAssertEqual(e("=TEXTAFTER(\"Red riding hood's, red hood\",\"hood\",2)"), .text(""))
        XCTAssertEqual(e("=TEXTAFTER(\"a-b-c\",\"-\")"), .text("b-c")); XCTAssertEqual(e("=TEXTBEFORE(\"a-b-c\",\"-\",-1)"), .text("a-b"))
        XCTAssertEqual(e("=FIXED(1234.567,1)"), .text("1,234.6")); XCTAssertEqual(e("=FIXED(1234.567,-1)"), .text("1,230"))
        XCTAssertEqual(e("=FIXED(-1234.567,-1,TRUE)"), .text("-1230")); XCTAssertEqual(e("=DOLLAR(-1234.567,2)"), .text("($1,234.57)"))
        n("=NUMBERVALUE(\"2.500,27\",\",\",\".\")", 2500.27); n("=NUMBERVALUE(\"3.5%\")", 0.035)
        n("=UNICODE(\"B\")", 66); XCTAssertEqual(e("=UNICHAR(66)"), .text("B"))
        n("=WEEKNUM(DATE(2012,3,9))", 10); n("=WEEKNUM(DATE(2012,3,9),2)", 11)
        n("=ISOWEEKNUM(DATE(2012,3,9))", 10); n("=ISOWEEKNUM(DATE(2027,1,1))", 53); n("=ISOWEEKNUM(DATE(2026,1,1))", 1)
        n("=WORKDAY(DATE(2008,10,1),151)", ExcelDate.serial(2009, 4, 30)); n("=DAYS(DATE(2021,3,15),DATE(2021,2,1))", 42)
        n("=DAYS360(DATE(2011,1,30),DATE(2011,12,31))", 330); n("=YEARFRAC(DATE(2012,1,1),DATE(2012,7,30))", 0.580555556)
        n("=YEARFRAC(DATE(2012,1,1),DATE(2012,7,30),3)", 0.57808219)
        n("=DATEVALUE(\"2008-08-22\")", ExcelDate.serial(2008, 8, 22))
    }

    func testFinance() {
        n("=NPER(0.12/12,-100,-1000,10000,1)", 59.6738657)
        n("=IPMT(0.1/12,1,36,8000)", -66.66666667); n("=IPMT(0.1,3,3,8000)", -292.4471299)
        n("=PPMT(0.1/12,1,24,2000)", -75.62318601); n("=PPMT(0.08,10,10,200000)", -27598.05346, accuracy: 1e-4)
        n("=CUMIPMT(0.09/12,30*12,125000,13,24,0)", -11135.23213, accuracy: 1e-4)
        n("=CUMIPMT(0.09/12,30*12,125000,1,1,0)", -937.5); n("=CUMPRINC(0.09/12,30*12,125000,13,24,0)", -934.1071234, accuracy: 1e-4)
        n("=SLN(30000,7500,10)", 2250); n("=SYD(30000,7500,10,1)", 4090.909091)
        n("=DDB(2400,300,10*365,1)", 1.315068493); n("=DDB(2400,300,10,1,2)", 480); n("=DDB(2400,300,10,10)", 22.1225472)
        n("=DB(1000000,100000,6,1,7)", 186083.3333, accuracy: 1e-3); n("=DB(1000000,100000,6,7,7)", 15845.09842, accuracy: 1e-3)
        n("=IRR({-70000,12000,15000,18000,21000,26000})", 0.086630948)
        n("=IRR({-70000,12000,15000,18000,21000})", -0.021244848)
        n("=XNPV(0.09,{-10000,2750,4250,3250,2750},{39448,39508,39751,39859,39904})", 2086.647602, accuracy: 1e-3)
        n("=XIRR({-10000,2750,4250,3250,2750},{39448,39508,39751,39859,39904})", 0.373362535, accuracy: 1e-6)
    }
}
