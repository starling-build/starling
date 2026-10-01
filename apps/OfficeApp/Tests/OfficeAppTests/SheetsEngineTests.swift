// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The spreadsheet engine against values Excel computes: addresses, input
// parsing, the parser's round trip, operators and precedence, the v1
// functions, recalculation, cycles, number formats and dates.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SheetsEngineTests: XCTestCase {
    private func book(_ cells: [String: String], sheets extra: [String: [String: String]] = [:]) -> WorkbookController {
        let c = WorkbookController()
        let b = Workbook()
        for (name, _) in extra.sorted(by: { $0.key < $1.key }) { b.sheets.append(Worksheet(name: name)) }
        c.load(b)
        c.setInputs(cells.map { (CellAddress($0.key)!, $0.value) })
        for (name, cs) in extra {
            c.setInputs(cs.map { (CellAddress($0.key)!, $0.value) }, sheet: b.sheet(named: name)!)
        }
        return c
    }

    private func v(_ c: WorkbookController, _ a: String, sheet: Int = 0) -> CellValue {
        c.book.sheets[sheet].value(CellAddress(a)!)
    }

    private func eval(_ c: WorkbookController, _ f: String) -> CellValue {
        c.engine.evaluate(f, sheet: 0, at: CellAddress(row: 99, col: 25))
    }

    private func num(_ c: WorkbookController, _ f: String, file: StaticString = #filePath, line: UInt = #line) -> Double {
        guard case .number(let n) = eval(c, f) else {
            XCTFail("\(f) = \(eval(c, f)), not a number", file: file, line: line); return .nan
        }
        return n
    }

    // MARK: Addresses

    func testAddresses() {
        XCTAssertEqual(CellAddress.columnName(0), "A")
        XCTAssertEqual(CellAddress.columnName(25), "Z")
        XCTAssertEqual(CellAddress.columnName(26), "AA")
        XCTAssertEqual(CellAddress.columnName(701), "ZZ")
        XCTAssertEqual(CellAddress.columnName(16383), "XFD")
        XCTAssertEqual(CellAddress("XFD1048576"), CellAddress(row: 1_048_575, col: 16383))
        XCTAssertNil(CellAddress("XFE1"))
        XCTAssertNil(CellAddress("A0"))
        XCTAssertEqual(CellAddress("$b$3"), CellAddress(row: 2, col: 1))
        XCTAssertEqual(CellRange("A1:C3")?.a1, "A1:C3")
        XCTAssertEqual(CellRange("C3:A1")?.a1, "A1:C3")
        XCTAssertEqual(CellRange("B:D")?.a1, "B:D")
        XCTAssertEqual(CellRange("2:4")?.a1, "2:4")
    }

    // MARK: Input

    func testInputParsing() {
        func p(_ s: String) -> CellValue? { InputParser.parse(s)?.value }
        XCTAssertEqual(p("12"), .number(12))
        XCTAssertEqual(p("-3.5"), .number(-3.5))
        XCTAssertEqual(p("1,234"), .number(1234))
        XCTAssertEqual(p("1,23"), .text("1,23"))
        XCTAssertEqual(p("$1,200.50"), .number(1200.5))
        XCTAssertEqual(p("(5)"), .number(-5))
        XCTAssertEqual(p("15%"), .number(0.15))
        XCTAssertEqual(p("1e3"), .number(1000))
        XCTAssertEqual(p("'12"), .text("12"))
        XCTAssertEqual(p("true"), .bool(true))
        XCTAssertEqual(p("#n/a"), .error(.na))
        XCTAssertEqual(p("Total"), .text("Total"))
        XCTAssertEqual(p("1/2/2026"), .number(46024))       // Excel: 1/2/2026 = 46024
        XCTAssertEqual(p("2026-01-02"), .number(46024))
        XCTAssertEqual(p("12:30"), .number(0.5208333333333334))
        XCTAssertEqual(InputParser.parse("15%")?.format, "0%")
        XCTAssertEqual(InputParser.parse("$1,200.50")?.format, "$#,##0.00")
        XCTAssertNil(InputParser.parse("=A1"))
    }

    // MARK: Parser

    func testParserRoundTrips() throws {
        for f in ["=SUM(A1:B2)", "=A1+B1*2", "=(A1+B1)*2", "=-A1^2", "=A1&\" items\"",
                  "=IF(A1>0,\"yes\",\"no\")", "=Sheet2!A1", "='My Sheet'!$B$2:C3", "=SUM(A:A)",
                  "=SUM(3:3)", "=10%", "=IF(A1,,2)", "=TaxRate*A1", "=1.5E+3", "=A1<>B1", "=#N/A"] {
            XCTAssertEqual(Formula.text(try Formula.parse(f)), f, f)
        }
        XCTAssertThrowsError(try Formula.parse("=SUM(A1"))
        XCTAssertThrowsError(try Formula.parse("=1+"))
        XCTAssertThrowsError(try Formula.parse("=\"open"))
    }

    // MARK: Operators

    func testOperatorsAndPrecedence() {
        let c = book([:])
        XCTAssertEqual(num(c, "=1+2*3"), 7)
        XCTAssertEqual(num(c, "=-2^2"), 4)            // unary minus binds tighter in Excel
        XCTAssertEqual(num(c, "=2^3^2"), 64)          // left-associative
        XCTAssertEqual(num(c, "=50%*4"), 2)
        XCTAssertEqual(eval(c, "=1/0"), .error(.div0))
        XCTAssertEqual(eval(c, "=\"a\"&1&TRUE"), .text("a1TRUE"))
        XCTAssertEqual(eval(c, "=\"10\"+1"), .number(11))
        XCTAssertEqual(eval(c, "=\"x\"+1"), .error(.value))
        XCTAssertEqual(eval(c, "=\"abc\"=\"ABC\""), .bool(true))
        XCTAssertEqual(eval(c, "=1<\"a\""), .bool(true))       // numbers sort before text
        XCTAssertEqual(eval(c, "=TRUE>\"z\""), .bool(true))    // booleans after text
        XCTAssertEqual(eval(c, "=(-8)^(1/3)"), .error(.num))
        XCTAssertEqual(eval(c, "=0.1+0.2=0.3"), .bool(true))   // Excel compares to 15 significant digits
    }

    // MARK: Recalculation

    func testRecalcAndChains() {
        let c = book(["A1": "2", "A2": "=A1*10", "A3": "=A2+A1", "B1": "=SUM(A1:A3)"])
        XCTAssertEqual(v(c, "A2"), .number(20))
        XCTAssertEqual(v(c, "A3"), .number(22))
        XCTAssertEqual(v(c, "B1"), .number(44))
        c.setInput("5", at: CellAddress("A1")!)
        XCTAssertEqual(v(c, "B1"), .number(110))
        c.undo()
        XCTAssertEqual(v(c, "B1"), .number(44))
        c.redo()
        XCTAssertEqual(v(c, "B1"), .number(110))
        // An empty reference is 0; a formula referring to nothing shows 0.
        c.setInput("=Z99", at: CellAddress("C1")!)
        XCTAssertEqual(v(c, "C1"), .number(0))
    }

    func testCircularReference() {
        let c = book(["A1": "=B1+1", "B1": "=A1+1", "C1": "=A1"])
        XCTAssertEqual(v(c, "A1"), .number(0))
        XCTAssertEqual(v(c, "B1"), .number(0))
        XCTAssertFalse(c.engine.circular.isEmpty)
    }

    func testOtherSheetsAndNames() {
        let c = book(["A1": "=Data!B2*2", "A2": "='Data'!B2+Rate"], sheets: ["Data": ["B2": "21"]])
        c.book.names["RATE"] = "Data!$B$2"
        c.engine.recalculate()
        XCTAssertEqual(v(c, "A1"), .number(42))
        XCTAssertEqual(v(c, "A2"), .number(42))
        XCTAssertEqual(eval(c, "=Nope!A1"), .error(.ref))
        XCTAssertEqual(eval(c, "=Undefined+1"), .error(.name))
        // Renaming the sheet rewrites the formulas that name it.
        XCTAssertTrue(c.renameSheet(1, "Inputs"))
        XCTAssertEqual(c.input(CellAddress("A1")!), "=Inputs!B2*2")
        XCTAssertEqual(v(c, "A1"), .number(42))
    }

    // MARK: Functions

    func testAggregates() {
        let c = book(["A1": "1", "A2": "2", "A3": "abc", "A4": "TRUE", "A5": "", "A6": "4",
                      "B1": "10", "B2": "#DIV/0!"])
        XCTAssertEqual(num(c, "=SUM(A1:A6)"), 7)                 // text and TRUE in a range are skipped
        XCTAssertEqual(num(c, "=SUM(A1:A6,TRUE,\"3\")"), 11)     // but direct arguments count
        XCTAssertEqual(num(c, "=AVERAGE(A1:A6)"), 7.0 / 3)
        XCTAssertEqual(num(c, "=COUNT(A1:A6)"), 3)
        XCTAssertEqual(num(c, "=COUNTA(A1:A6)"), 5)
        XCTAssertEqual(num(c, "=COUNTBLANK(A1:A6)"), 1)
        XCTAssertEqual(num(c, "=MIN(A1:A6)"), 1)
        XCTAssertEqual(num(c, "=MAX(A1:A6)"), 4)
        XCTAssertEqual(num(c, "=PRODUCT(A1:A6)"), 8)
        XCTAssertEqual(num(c, "=MEDIAN(1,2,3,4)"), 2.5)
        XCTAssertEqual(num(c, "=STDEV(2,4,4,4,5,5,7,9)"), 2.138089935299395, accuracy: 1e-12)
        XCTAssertEqual(eval(c, "=SUM(B1:B2)"), .error(.div0))
        XCTAssertEqual(eval(c, "=AVERAGE(A5)"), .error(.div0))
        XCTAssertEqual(num(c, "=SUMPRODUCT(A1:A2,A1:A2)"), 5)
    }

    func testRounding() {
        let c = book([:])
        XCTAssertEqual(num(c, "=ROUND(2.675,2)"), 2.68)          // Excel rounds what it shows
        XCTAssertEqual(num(c, "=ROUND(-2.5,0)"), -3)
        XCTAssertEqual(num(c, "=ROUND(1234.5,-2)"), 1200)
        XCTAssertEqual(num(c, "=ROUNDUP(3.141,2)"), 3.15)
        XCTAssertEqual(num(c, "=ROUNDDOWN(-3.149,2)"), -3.14)
        XCTAssertEqual(num(c, "=INT(-3.5)"), -4)
        XCTAssertEqual(num(c, "=TRUNC(-3.5)"), -3)
        XCTAssertEqual(num(c, "=MOD(-3,2)"), 1)                  // sign of the divisor
        XCTAssertEqual(eval(c, "=MOD(1,0)"), .error(.div0))
        XCTAssertEqual(num(c, "=CEILING(4.2,0.5)"), 4.5)
        XCTAssertEqual(eval(c, "=SQRT(-1)"), .error(.num))
    }

    func testLogic() {
        let c = book(["A1": "5"])
        XCTAssertEqual(eval(c, "=IF(A1>3,\"big\",\"small\")"), .text("big"))
        XCTAssertEqual(eval(c, "=IF(A1>9,\"big\")"), .bool(false))
        XCTAssertEqual(eval(c, "=IF(A1>3,1/0,2)"), .error(.div0))
        XCTAssertEqual(eval(c, "=IF(A1<3,1/0,2)"), .number(2))   // the untaken branch is not evaluated
        XCTAssertEqual(eval(c, "=IFS(A1<3,\"a\",A1<6,\"b\")"), .text("b"))
        XCTAssertEqual(eval(c, "=IFERROR(1/0,\"none\")"), .text("none"))
        XCTAssertEqual(eval(c, "=IFNA(NA(),0)"), .number(0))
        XCTAssertEqual(eval(c, "=AND(A1>1,A1<9)"), .bool(true))
        XCTAssertEqual(eval(c, "=OR(A1>9,FALSE)"), .bool(false))
        XCTAssertEqual(eval(c, "=NOT(A1)"), .bool(false))
        XCTAssertEqual(eval(c, "=ISBLANK(B9)"), .bool(true))
        XCTAssertEqual(eval(c, "=ISNUMBER(A1)"), .bool(true))
        XCTAssertEqual(eval(c, "=ISERROR(1/0)"), .bool(true))
        XCTAssertEqual(eval(c, "=CHOOSE(2,\"a\",\"b\",\"c\")"), .text("b"))
    }

    func testConditionals() {
        let c = book(["A1": "apple", "A2": "banana", "A3": "apricot", "A4": "cherry",
                      "B1": "10", "B2": "20", "B3": "30", "B4": "40",
                      "C1": "x", "C2": "y", "C3": "x", "C4": "x"])
        XCTAssertEqual(num(c, "=SUMIF(B1:B4,\">15\")"), 90)
        XCTAssertEqual(num(c, "=SUMIF(A1:A4,\"ap*\",B1:B4)"), 40)
        XCTAssertEqual(num(c, "=SUMIF(A:A,\"<>banana\",B:B)"), 80)
        XCTAssertEqual(num(c, "=COUNTIF(B1:B4,\">=20\")"), 3)
        XCTAssertEqual(num(c, "=COUNTIF(A1:A4,\"?????\")"), 1)
        XCTAssertEqual(num(c, "=COUNTIF(C1:C4,\"x\")"), 3)
        XCTAssertEqual(num(c, "=SUMIFS(B1:B4,C1:C4,\"x\",B1:B4,\">10\")"), 70)
        XCTAssertEqual(num(c, "=COUNTIFS(C1:C4,\"x\",A1:A4,\"a*\")"), 2)
        XCTAssertEqual(num(c, "=AVERAGEIF(C1:C4,\"x\",B1:B4)"), 80.0 / 3)
        XCTAssertEqual(num(c, "=COUNTIF(D1:D4,\"\")"), 4)
    }

    func testLookups() {
        let c = book(["A1": "1", "A2": "3", "A3": "5", "A4": "7",
                      "B1": "one", "B2": "three", "B3": "five", "B4": "seven",
                      "D1": "red", "D2": "Green", "D3": "blue"])
        XCTAssertEqual(eval(c, "=VLOOKUP(5,A1:B4,2,FALSE)"), .text("five"))
        XCTAssertEqual(eval(c, "=VLOOKUP(6,A1:B4,2)"), .text("five"))          // approximate: largest ≤ 6
        XCTAssertEqual(eval(c, "=VLOOKUP(6,A1:B4,2,FALSE)"), .error(.na))
        XCTAssertEqual(eval(c, "=VLOOKUP(5,A1:B4,3,FALSE)"), .error(.ref))
        XCTAssertEqual(eval(c, "=HLOOKUP(\"three\",B2:B2,1,FALSE)"), .text("three"))
        XCTAssertEqual(num(c, "=MATCH(\"green\",D1:D3,0)"), 2)                // case-insensitive
        XCTAssertEqual(num(c, "=MATCH(4,A1:A4)"), 2)
        XCTAssertEqual(num(c, "=MATCH(\"b*\",D1:D3,0)"), 3)
        XCTAssertEqual(eval(c, "=INDEX(B1:B4,3)"), .text("five"))
        XCTAssertEqual(eval(c, "=INDEX(A1:B4,2,2)"), .text("three"))
        XCTAssertEqual(eval(c, "=INDEX(B1:B4,MATCH(7,A1:A4,0))"), .text("seven"))
        XCTAssertEqual(num(c, "=SUM(INDEX(A1:B4,0,1))"), 16)                  // a whole column of the range
        XCTAssertEqual(eval(c, "=XLOOKUP(3,A1:A4,B1:B4)"), .text("three"))
        XCTAssertEqual(eval(c, "=XLOOKUP(4,A1:A4,B1:B4,\"none\")"), .text("none"))
        XCTAssertEqual(eval(c, "=XLOOKUP(4,A1:A4,B1:B4,,-1)"), .text("three"))
        XCTAssertEqual(num(c, "=ROW(A5)"), 5)
        XCTAssertEqual(num(c, "=COLUMNS(A1:D1)"), 4)
    }

    func testText() {
        let c = book(["A1": "Hello", "A2": "World"])
        XCTAssertEqual(eval(c, "=CONCATENATE(A1,\" \",A2)"), .text("Hello World"))
        XCTAssertEqual(eval(c, "=TEXTJOIN(\", \",TRUE,A1:A3)"), .text("Hello, World"))
        XCTAssertEqual(eval(c, "=LEFT(A1,2)&RIGHT(A2,3)&MID(A1,2,3)"), .text("Herldell"))
        XCTAssertEqual(num(c, "=LEN(A1)"), 5)
        XCTAssertEqual(eval(c, "=UPPER(A1)&LOWER(A2)"), .text("HELLOworld"))
        XCTAssertEqual(eval(c, "=PROPER(\"the QUICK fox\")"), .text("The Quick Fox"))
        XCTAssertEqual(eval(c, "=TRIM(\"  a   b  \")"), .text("a b"))
        XCTAssertEqual(num(c, "=FIND(\"l\",A1)"), 3)
        XCTAssertEqual(eval(c, "=FIND(\"L\",A1)"), .error(.value))           // FIND is case-sensitive
        XCTAssertEqual(num(c, "=SEARCH(\"L\",A1)"), 3)
        XCTAssertEqual(num(c, "=SEARCH(\"w?r\",A2)"), 1)
        XCTAssertEqual(eval(c, "=SUBSTITUTE(\"a-b-c\",\"-\",\"+\")"), .text("a+b+c"))
        XCTAssertEqual(eval(c, "=SUBSTITUTE(\"a-b-c\",\"-\",\"+\",2)"), .text("a-b+c"))
        XCTAssertEqual(eval(c, "=REPT(\"ab\",3)"), .text("ababab"))
        XCTAssertEqual(num(c, "=VALUE(\"$1,000\")"), 1000)
        XCTAssertEqual(eval(c, "=EXACT(\"a\",\"A\")"), .bool(false))
        XCTAssertEqual(eval(c, "=1&\"\""), .text("1"))
        XCTAssertEqual(eval(c, "=0.1+0.2&\"\""), .text("0.3"))                // 15 significant digits
    }

    func testTextFormats() {
        let c = book([:])
        XCTAssertEqual(eval(c, "=TEXT(1234.567,\"#,##0.00\")"), .text("1,234.57"))
        XCTAssertEqual(eval(c, "=TEXT(0.256,\"0.0%\")"), .text("25.6%"))
        XCTAssertEqual(eval(c, "=TEXT(-5,\"$#,##0;($#,##0)\")"), .text("($5)"))
        XCTAssertEqual(eval(c, "=TEXT(46024,\"yyyy-mm-dd\")"), .text("2026-01-02"))
        XCTAssertEqual(eval(c, "=TEXT(46024,\"dddd, mmmm d\")"), .text("Friday, January 2"))
        XCTAssertEqual(eval(c, "=TEXT(0.75,\"h:mm AM/PM\")"), .text("6:00 PM"))
        XCTAssertEqual(eval(c, "=TEXT(7,\"000\")"), .text("007"))
        XCTAssertEqual(eval(c, "=TEXT(1234567,\"0.00E+00\")"), .text("1.23E+06"))
    }

    func testDates() {
        let c = book([:])
        XCTAssertEqual(num(c, "=DATE(2026,1,2)"), 46024)
        XCTAssertEqual(num(c, "=DATE(1900,1,1)"), 1)
        XCTAssertEqual(num(c, "=DATE(1900,3,1)"), 61)                        // after the phantom 29 Feb 1900
        XCTAssertEqual(num(c, "=DATE(2026,14,1)"), num(c, "=DATE(2027,2,1)"))
        XCTAssertEqual(num(c, "=YEAR(46024)*10000+MONTH(46024)*100+DAY(46024)"), 20260102)
        XCTAssertEqual(num(c, "=WEEKDAY(46024)"), 6)                         // Friday
        XCTAssertEqual(num(c, "=WEEKDAY(46024,2)"), 5)
        XCTAssertEqual(num(c, "=EDATE(DATE(2026,1,31),1)"), num(c, "=DATE(2026,2,28)"))
        XCTAssertEqual(num(c, "=EOMONTH(DATE(2024,1,15),1)"), num(c, "=DATE(2024,2,29)"))
        XCTAssertEqual(num(c, "=DATEDIF(DATE(2020,5,10),DATE(2026,1,2),\"Y\")"), 5)
        XCTAssertEqual(num(c, "=NETWORKDAYS(DATE(2026,1,1),DATE(2026,1,31))"), 22)
        XCTAssertEqual(num(c, "=HOUR(0.75)*100+MINUTE(0.7604166666666666)"), 1815)
    }

    func testFinance() {
        let c = book([:])
        XCTAssertEqual(num(c, "=PMT(0.05/12,360,200000)"), -1073.6432460242797, accuracy: 1e-9)
        XCTAssertEqual(num(c, "=FV(0.06/12,10,-200,-500,1)"), 2581.4033740601184, accuracy: 1e-9)
        XCTAssertEqual(num(c, "=PV(0.08/12,240,500)"), -59777.14585118777, accuracy: 1e-7)
        XCTAssertEqual(num(c, "=NPV(0.1,-10000,3000,4200,6800)"), 1188.4434123352207, accuracy: 1e-9)
    }

    // MARK: Formats

    func testNumberFormats() {
        func f(_ n: Double, _ code: String) -> String { NumberFormat.format(n, code).text }
        XCTAssertEqual(NumberFormat.general(1.0 / 3), "0.333333333")
        XCTAssertEqual(NumberFormat.general(1234567), "1234567")
        XCTAssertEqual(NumberFormat.general(123456789012), "1.23457E+11")
        XCTAssertEqual(NumberFormat.general(-0.5), "-0.5")
        XCTAssertEqual(NumberFormat.full(1.0 / 3), "0.333333333333333")
        XCTAssertEqual(NumberFormat.full(0.1 + 0.2), "0.3")
        XCTAssertEqual(f(1234.5, "#,##0.00"), "1,234.50")
        XCTAssertEqual(f(-1234.5, "#,##0"), "-1,235")
        XCTAssertEqual(f(0.5, "0%"), "50%")
        XCTAssertEqual(f(1234.5, "$#,##0.00"), "$1,234.50")
        XCTAssertEqual(f(-3, "0.00;[Red]-0.00"), "-3.00")
        XCTAssertEqual(NumberFormat.format(-3, "0.00;[Red]-0.00").color, 0xFF0000)
        XCTAssertEqual(f(0, "0.00;-0.00;\"zero\""), "zero")
        XCTAssertEqual(f(12.3, "0.###"), "12.3")
        XCTAssertEqual(f(1500000, "#,##0,,\"M\""), "2M")
        XCTAssertEqual(NumberFormat.display(.text("abc"), "\"<\"@\">\"").text, "<abc>")
    }

    func testTypedFormatSticks() {
        let c = book(["A1": "25%", "A2": "$3.50", "A3": "1/2/2026"])
        XCTAssertEqual(c.style(at: CellAddress("A1")!).numberFormat, "0%")
        XCTAssertEqual(c.style(at: CellAddress("A2")!).numberFormat, "$#,##0.00")
        XCTAssertEqual(c.input(CellAddress("A1")!), "25%")
        XCTAssertEqual(c.input(CellAddress("A3")!), "1/2/2026")
        XCTAssertEqual(NumberFormat.display(v(c, "A2"), "$#,##0.00").text, "$3.50")
    }

    func testCtrlArrowEdges() {
        let c = book(["A1": "1", "A2": "2", "A3": "3", "A6": "6"])
        XCTAssertEqual(c.edge(from: CellAddress("A1")!, rows: 1, cols: 0), CellAddress("A3"))
        XCTAssertEqual(c.edge(from: CellAddress("A3")!, rows: 1, cols: 0), CellAddress("A6"))
        XCTAssertEqual(c.edge(from: CellAddress("A6")!, rows: 1, cols: 0), CellAddress(row: CellAddress.maxRows - 1, col: 0))
        XCTAssertEqual(c.edge(from: CellAddress("A6")!, rows: -1, cols: 0), CellAddress("A3"))
    }

    func testStatusBarStats() {
        let c = book(["A1": "1", "A2": "2", "A3": "x"])
        c.select(range: CellRange("A1:A4")!)
        let s = c.selectionStats
        XCTAssertEqual(s.sum, 3)
        XCTAssertEqual(s.average, 1.5)
        XCTAssertEqual(s.count, 3)
    }
}

extension SheetsEngineTests {
    func testArrayConstants() throws {
        let c = WorkbookController()
        c.setInputs([(CellAddress("A1")!, "x"), (CellAddress("A2")!, "y"), (CellAddress("A3")!, "x"), (CellAddress("A4")!, "z")])
        func v(_ f: String) -> CellValue { c.engine.evaluate(f, sheet: 0, at: CellAddress("H1")!) }
        XCTAssertEqual(v("=SUM({1,2;3,4})"), .number(10))
        XCTAssertEqual(v("=INDEX({10,20,30},2)"), .number(20))
        XCTAssertEqual(v("=VLOOKUP(2,{1,\"a\";2,\"b\"},2,FALSE)"), .text("b"))
        XCTAssertEqual(v("=MATCH(\"b\",{\"a\",\"b\"},0)"), .number(2))
        XCTAssertEqual(v("=SUM({-1,2.5})"), .number(1.5))
        for f in ["SUM({1,2;3,4})", "VLOOKUP(2,{1,\"a\";2,\"b\"},2,FALSE)", "SUM({-1,2.5})"] {
            XCTAssertEqual(Formula.print(try Formula.parse("=" + f)), f)
        }
        XCTAssertThrowsError(try Formula.parse("={1,2;3}"))
        // Still unreadable here, and so kept as written: the intersection operator.
        XCTAssertThrowsError(try Formula.parse("=SUM(A1:C3 B2:D4)"))
        // @ is Excel's implicit intersection: SINGLE in files, @ on screen.
        XCTAssertEqual(Formula.print(try Formula.parse("=@A1:A3*2")), "@A1:A3*2")
    }
}

extension SheetsEngineTests {
    /// After every edit, the incremental pass agrees with a full one.
    func testIncrementalRecalcMatchesAFullOne() {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "One"), Worksheet(name: "Two")]))
        var rng = SystemRandomNumberGenerator()
        func ref() -> String { "\(["A", "B", "C", "D"].randomElement(using: &rng)!)\(Int.random(in: 1 ... 12, using: &rng))" }
        let formulas = [
            { "=\(ref())+\(ref())" }, { "=SUM(A1:\(ref()))" }, { "=Two!\(ref())*2" }, { "=SUMIF(A1:A12,\">5\",B1:B12)" },
            { "=IF(\(ref())>3,\(ref()),0)" }, { "=COUNT(One!A:B)" }, { "=VLOOKUP(\(ref()),A1:D12,2,FALSE)" }, { "=RATE_ME+1" },
            { "=SEQUENCE(\(Int.random(in: 1 ... 3, using: &rng)))" }, { "=FILTER(A1:A12,A1:A12>4,0)" }, { "=SUM(A1#)" },
        ]
        c.book.names["RATE_ME"] = "One!$C$3"
        for round in 0 ..< 300 {
            let sheet = Int.random(in: 0 ... 1, using: &rng)
            let a = CellAddress(ref())!
            let text = Int.random(in: 0 ..< 3, using: &rng) == 0 ? formulas.randomElement(using: &rng)!() : "\(Int.random(in: 0 ... 9, using: &rng))"
            c.setInputs([(a, text)], sheet: sheet)
            // Values as the incremental pass left them, then as a full pass computes them.
            let incremental = c.book.sheets.map { ws in ws.cells.mapValues(\.value) }
            let incSpilled = c.book.sheets.map(\.spilled)
            c.engine.recalculate()
            let full = c.book.sheets.map { ws in ws.cells.mapValues(\.value) }
            if incSpilled != c.book.sheets.map(\.spilled) { XCTFail("round \(round): spills differ"); return }
            if incremental != full {
                XCTFail("round \(round): \(text) into \(sheet):\(a.a1) left values stale")
                return
            }
        }
    }
}

extension SheetsEngineTests {
    /// A running total 50,000 rows long: evaluated in dependency order, so
    /// it neither recurses 50,000 deep (a stack overflow, before) nor
    /// recomputes everything when an unrelated cell changes.
    func testLongChainsAndIncrementalEdits() {
        let c = WorkbookController()
        var items: [(CellAddress, String)] = []
        let n = 50_000
        for r in 0 ..< n {
            items.append((CellAddress(row: r, col: 0), "1"))
            items.append((CellAddress(row: r, col: 1), r == 0 ? "=A1" : "=B\(r)+A\(r + 1)"))
        }
        c.setInputs(items)
        XCTAssertEqual(c.sheet.value(CellAddress(row: n - 1, col: 1)), .number(Double(n)))
        c.setInputs([(CellAddress("A1")!, "11")])
        XCTAssertEqual(c.sheet.value(CellAddress(row: n - 1, col: 1)), .number(Double(n + 10)))
        let t = Date()
        c.setInputs([(CellAddress("D1")!, "7")])
        XCTAssertLessThan(Date().timeIntervalSince(t), 0.5)          // nothing reads D1
    }
}
