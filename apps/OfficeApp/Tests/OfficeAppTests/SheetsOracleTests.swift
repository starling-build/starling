// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Values Excel cached in Apache POI's test workbooks (test-data/spreadsheet),
// found by `OfficeApp --xlsx-check` on 2026-10-07: each case here was a
// difference between our engine and Excel's own result in a real file.

import XCTest
@testable import OfficeApp

final class SheetsOracleTests: XCTestCase {
    private func f(_ n: Double, _ code: String) -> String { NumberFormat.format(n, code).text }

    func testFormatConditions() {
        // FormatChoiceTests.xlsx, FormatConditionTests.xlsx
        XCTAssertEqual(f(10, "[<10]#\" Wow\""), "10")
        XCTAssertEqual(f(9, "[<10]#\" Wow\""), "9 Wow")
        XCTAssertEqual(f(-11, "[=-10]#\" Wow\""), "-11")
        XCTAssertEqual(f(-10, "[=-10]#\" Wow\""), "-10 Wow")
        XCTAssertEqual(f(150, "[>=100]0\" big\";[>=10]0\" mid\";0\" small\""), "150 big")
        XCTAssertEqual(f(15, "[>=100]0\" big\";[>=10]0\" mid\";0\" small\""), "15 mid")
        XCTAssertEqual(f(1, "[>=100]0\" big\";[>=10]0\" mid\";0\" small\""), "1 small")
    }

    func testFormatPlaceholders() {
        // NumberFormatTests.xlsx: ? pads with spaces, the point stays.
        XCTAssertEqual(f(1234567, "#,##.#"), "1,234,567.")
        XCTAssertEqual(f(1234567, "?,???????"), " 1,234,567")
        XCTAssertEqual(f(1234567, "?,?????????"), "    1,234,567")
        XCTAssertEqual(f(-1234567, "?,???????"), "- 1,234,567")
        XCTAssertEqual(f(1.1, "|??.?|"), "| 1.1|")
        XCTAssertEqual(f(1.1, "|?.??|"), "|1.1 |")
        XCTAssertEqual(f(5, "0.#"), "5.")
        XCTAssertEqual(f(1234.5, "#,##0.00"), "1,234.50")
        XCTAssertEqual(f(0.5, "#.00"), ".50")
    }

    func testFormatScientific() {
        // NumberFormatApproxTests.xlsx: the exponent is a multiple of the
        // integer placeholders, the E keeps its case, literals sit anywhere.
        XCTAssertEqual(f(123456.789, "|#,e-#|"), "|1e5|")
        XCTAssertEqual(f(123456.789, "|#%e-#|"), "|1%e5|")
        XCTAssertEqual(f(123456.789, "|#|e-|#|"), "|1|e|5|")
        XCTAssertEqual(f(123456.789, "|####.####|e-|#|"), "|12.3457|e|4|")
        XCTAssertEqual(f(123456.789, "|#,######.####|e-|#|"), "|123,456.789|e|0|")
        XCTAssertEqual(f(123456.789, "|0000.0000|e-|0|"), "|0012.3457|e|4|")
        XCTAssertEqual(f(1234, "##0.0E+0"), "1.2E+3")
        XCTAssertEqual(f(0.000123, "0.00E+00"), "1.23E-04")
        XCTAssertEqual(f(12345, "0.00E+00"), "1.23E+04")
    }

    func testFormatText() {
        // TextFormatTests.xlsx
        XCTAssertEqual(NumberFormat.display(.text("jello"), ";;;\\h\\i").text, "hi")
        XCTAssertEqual(NumberFormat.display(.text("jello"), "\\@@\\@").text, "@jello@")
        XCTAssertEqual(NumberFormat.display(.text("jello"), "0.00").text, "jello")
        XCTAssertEqual(NumberFormat.display(.bool(true), ";;;\"hi\"").text, "hi")
        XCTAssertEqual(NumberFormat.display(.bool(true), ";;;-@-@-").text, "-TRUE-TRUE-")
        XCTAssertEqual(NumberFormat.display(.bool(false), ";;;\\@@\\@").text, "@FALSE@")
        XCTAssertEqual(NumberFormat.display(.bool(true), "0.00").text, "TRUE")
    }

    func testFormatTimes() {
        // DateFormatTests.xlsx, DateFormatNumberTests.xlsx, ElapsedFormatTests.xlsx
        XCTAssertEqual(f(17816.607951388887, "hh:mm:ss a/p"), "02:35:27 p")
        XCTAssertEqual(f(36191.170208437499, "h:m:s.00 A/P"), "4:5:6.01 A")
        XCTAssertEqual(f(36191.170208437499, "hh:mm:ss.000 am/pm"), "04:05:06.009 AM")
        XCTAssertEqual(f(36191.170208437499, "hh:mm:ss"), "04:05:06")
        // (The file is a 1904-system workbook; in the 1900 system serial 1 is 1 January 1900.)
        XCTAssertEqual(f(1.0032134017094001, "yyyy-mm-dd hh:mm:ss.000"), "1900-01-01 00:04:37.638")
        XCTAssertEqual(f(1.0032134017094001, "yyyy-mm-dd hh:mm:ss"), "1900-01-01 00:04:38")
        XCTAssertEqual(f(3.14159, "[h]:m:s.000"), "75:23:53.376")
        XCTAssertEqual(f(3.14159, "[h]:mm:ss"), "75:23:53")
        XCTAssertEqual(f(3.14159, "s:m\" @ hour \"[hh]"), "53:23 @ hour 75")
        XCTAssertEqual(f(3.14159, "\"It was \"[h]\" [yes, \"h\"] hours and \"mm:ss"), "It was 75 [yes, 75] hours and 23:53")
        XCTAssertEqual(f(3.14159, "[s]\" [yes, \"ss\"] seconds\""), "271433 [yes, 271433] seconds")
        XCTAssertEqual(f(0.0854629629, "[hh]:mm:ss.0"), "02:03:04.0")
        XCTAssertEqual(f(17816.607951388887, "d \\d\\a\\y\\s h a/p"), "10 days 2 p")
        XCTAssertEqual(f(45000.5, "m/d/yyyy h:mm"), "3/15/2023 12:00")
        XCTAssertEqual(f(45000.5, "mmm d"), "Mar 15")
    }

    func testFormatGeneralInText() {
        let c = WorkbookController()
        func e(_ s: String) -> CellValue { c.engine.evaluate(s, sheet: 0, at: CellAddress("Z1")!) }
        // GeneralFormatTests.xlsx: ten significant digits.
        XCTAssertEqual(e("=TEXT(1.2345678912,\"General\")"), .text("1.234567891"))
        XCTAssertEqual(e("=TEXT(-1.2345678919,\"General\")"), .text("-1.234567892"))
        XCTAssertEqual(e("=TEXT(1234567.891234,\"General\")"), .text("1234567.891"))
        XCTAssertEqual(e("=TEXT(TRUE,\";;;\"\"hi\"\"\")"), .text("hi"))
        XCTAssertEqual(e("=TEXT(TRUE,\"-@\")"), .text("-TRUE"))
    }

    func testDates() {
        let c = WorkbookController()
        func e(_ s: String) -> CellValue { c.engine.evaluate(s, sheet: 0, at: CellAddress("Z1")!) }
        // FormulaEvalTestData_Copy.xlsx: the phantom 29 February 1900, and a
        // day overflow counted in serial days.
        XCTAssertEqual(e("=DATE(1900,2,29)"), .number(60))
        XCTAssertEqual(e("=DATE(1900,3,1)"), .number(61))
        XCTAssertEqual(e("=DATE(1900,1,22222)"), .number(22222))
        XCTAssertEqual(e("=DATE(2024,3,0)"), .number(45351))
        XCTAssertEqual(e("=DATE(2024,5,31)"), .number(45443))
        XCTAssertEqual(e("=DAY(#DIV/0!)"), .error(.div0))
        XCTAssertEqual(e("=MONTH(#N/A)"), .error(.na))
        XCTAssertEqual(e("=YEAR(#REF!)"), .error(.ref))
    }

    func testErrorsPassThrough() {
        let c = WorkbookController()
        func e(_ s: String) -> CellValue { c.engine.evaluate(s, sheet: 0, at: CellAddress("Z1")!) }
        XCTAssertEqual(e("=ATAN2(#N/A,#NAME?)"), .error(.na))
        XCTAssertEqual(e("=CHOOSE(#REF!,1)"), .error(.ref))
        XCTAssertEqual(e("=REPLACE(\"ABCDEF\",#NAME?,2,\"xx\")"), .error(.name))
        XCTAssertEqual(e("=NPER(0.01,#N/A,-200,300)"), .error(.na))
        XCTAssertEqual(e("=PMT(\"0.01\",\"12\",\"200\",\"-300\",\"TRUE\")"), .error(.value))
        XCTAssertEqual(e("=FACT(\"E8\")"), .error(.value))
        XCTAssertEqual(e("=FACT(-1)"), .error(.num))
        XCTAssertEqual(e("=FLOOR(0,0)"), .number(0))
        XCTAssertEqual(e("=FLOOR(1,0)"), .error(.div0))
        XCTAssertEqual(e("=AVEDEV({\"a\"})"), .error(.num))
        XCTAssertEqual(e("=MEDIAN({\"a\"})"), .error(.num))
        XCTAssertEqual(e("=DEVSQ({\"a\"})"), .error(.num))
        XCTAssertEqual(e("=MODE({1,2,3})"), .error(.na))
        XCTAssertEqual(e("=MODE(1,\"1\",2,3)"), .error(.value))
        XCTAssertEqual(e("=AVERAGEA(\"TRUE\",1)"), .error(.value))
        XCTAssertEqual(e("=AVERAGEA(\"1\",1)"), .number(1))
        XCTAssertEqual(e("=MINA(\"-23\",4)"), .number(-23))
        XCTAssertEqual(e("=LARGE(TRUE,1)"), .number(1))
        XCTAssertEqual(e("=LARGE(\"2.3\",1)"), .number(2.3))
        XCTAssertEqual(e("=ADDRESS(2,3,3,TRUE,\"[Book1]Sheet1\")"), .text("[Book1]Sheet1!$C2"))
        XCTAssertEqual(e("=ADDRESS(2,3,3,TRUE,\"My Sheet\")"), .text("'My Sheet'!$C2"))
    }

    func testRangesInScalarPlaces() {
        let c = WorkbookController()
        c.setInputs([("A1", "alpha"), ("B1", "num"), ("C1", "ric"), ("A2", "x"), ("A3", "y"), ("A4", "z"),
                     ("E1", "foo"), ("F1", "foo"), ("G1", "bar"), ("H1", "baz"), ("I1", "bar"),
                     ("K5", ""), ("K6", ""), ("K7", "")].map { (CellAddress($0.0)!, $0.1) })
        func e(_ s: String, at: String) -> CellValue { c.engine.evaluate(s, sheet: 0, at: CellAddress(at)!) }
        // CONCATENATE takes the cell in its own row or column; CONCAT takes all.
        XCTAssertEqual(e("=CONCATENATE(A1:C1,A2:A4)", at: "C3"), .text("ricy"))
        XCTAssertEqual(e("=CONCATENATE(A1:C1,A2:A4)", at: "E7"), .error(.value))
        XCTAssertEqual(e("=CONCAT(A1:C1)", at: "E7"), .text("alphanumric"))
        // COUNTIFS with an array of criteria gives an array; SUM adds it up.
        XCTAssertEqual(e("=SUM(COUNTIFS(E1:I1,{\"bar\",\"baz\"}))", at: "Z1"), .number(3))
        XCTAssertEqual(e("=SUM(COUNTIFS(E1:I1,{\"foo\",\"bar\"}))", at: "Z1"), .number(4))
        // SUMPRODUCT works on arrays, so --(range) is fine inside it.
        XCTAssertEqual(e("=SUMPRODUCT(--(K5:K7))", at: "Z1"), .number(0))
        // T of a range is its first cell.
        XCTAssertEqual(e("=T(A1:C1)", at: "Z1"), .text("alpha"))
        XCTAssertEqual(e("=T(K5:K7)", at: "Z1"), .text(""))
    }

    func testLookupsSearchAsExcelDoes() {
        let c = WorkbookController()
        c.setInputs([("B1", "0.1"), ("C1", "9700"), ("B2", "0.22"), ("C2", "xyz"), ("B3", "0.24"), ("C3", "xyz"),
                     ("B4", "0.32"), ("C4", "160726"), ("B5", "0.35"), ("C5", "204100"), ("B6", "0.37"), ("C6", "510300"),
                     ("E1", "INTEGRAL"), ("E2", "0"), ("E3", "1"), ("E4", "2"), ("E5", "534"), ("E6", "9999999999"), ("E7", "-9999999999"),
                     ("F1", "a"), ("F2", "b"), ("F3", "c"), ("F4", "d"), ("F5", "e"), ("F6", "f"), ("F7", "g"),
                     ("H1", "DOUBLE"), ("I1", "BLANK"), ("J1", "STRING"), ("K1", "REF"), ("L1", "AREA"),
                     ("H2", "1.1"), ("I2", ""), ("J2", "s"), ("K2", "r"), ("L2", "a"),
                     ("L1", "10"), ("L2", "20"), ("L3", "30"), ("M1", "ten"), ("M2", "twenty"), ("M3", "thirty")].map { (CellAddress($0.0)!, $0.1) })
        func e(_ s: String) -> CellValue { c.engine.evaluate(s, sheet: 0, at: CellAddress("Z9")!) }
        // xlookup.xlsx: binary search (search_mode 2) over a list Excel trusts sorted.
        XCTAssertEqual(e("=XLOOKUP(46523,C1:C6,B1:B6,0,1,2)"), .number(0.22))
        XCTAssertEqual(e("=XLOOKUP(46523,C1:C6,B1:B6,0,1)"), .number(0.32))
        // FormulaEvalTestData_Copy.xlsx: the first probe passes the key, so #N/A.
        XCTAssertEqual(e("=VLOOKUP(-1,E1:F7,2,TRUE)"), .error(.na))
        XCTAssertEqual(e("=VLOOKUP(25,L1:M3,2,TRUE)"), .text("twenty"))
        XCTAssertEqual(e("=VLOOKUP(5,L1:M3,2,TRUE)"), .error(.na))
        XCTAssertEqual(e("=VLOOKUP(99,L1:M3,2)"), .text("thirty"))
        XCTAssertEqual(e("=MATCH(25,L1:L3,1)"), .number(2))
        XCTAssertEqual(e("=LOOKUP(\"DOUBLE\",H1:L1,H2:L2)"), .number(1.1))
        XCTAssertEqual(e("=LOOKUP(25,L1:L3,M1:M3)"), .text("twenty"))
        XCTAssertEqual(e("=COUNTIF(E1:E7,1/0)"), .number(0))
    }

    func testCountifMatchesErrors() {
        let c = WorkbookController()
        c.setInputs([("A1", "=1/0"), ("A2", "=NA()"), ("A3", "=1/0"), ("A4", "5")].map { (CellAddress($0.0)!, $0.1) })
        func e(_ s: String) -> CellValue { c.engine.evaluate(s, sheet: 0, at: CellAddress("Z1")!) }
        XCTAssertEqual(e("=COUNTIF(A1:A4,1/0)"), .number(2))
        XCTAssertEqual(e("=COUNTIF(A1:A4,NA())"), .number(1))
    }

    func testSubtotalSkipsSubtotals() {
        let c = WorkbookController()
        c.setInputs([("A1", "1"), ("A2", "=SUBTOTAL(9,A1)"), ("A3", "=SUBTOTAL(9,A1,A2)"), ("A4", "=SUBTOTAL(9,A1:A2)")].map { (CellAddress($0.0)!, $0.1) })
        XCTAssertEqual(c.book.sheets[0].value(CellAddress("A3")!), .number(1))
        XCTAssertEqual(c.book.sheets[0].value(CellAddress("A4")!), .number(1))
    }

    func testDeletedNameIsRef() {
        let c = WorkbookController()
        c.book.names["SALE_1"] = "Sheet1!#REF!"
        c.setInputs([("A1", "=sale_1*2")].map { (CellAddress($0.0)!, $0.1) })
        XCTAssertEqual(c.book.sheets[0].value(CellAddress("A1")!), .error(.ref))
    }

    func testIterativeCalculation() {
        // 57535.xlsx: calcPr iterate="1"; E4 = 6, E5 = 0.1*(E4+E6), E6 = E4+E5
        // settle at 1.3333 and 7.3333 instead of showing 0 as a loop.
        let c = WorkbookController()
        c.book.iterate = true
        c.setInputs([("E4", "6"), ("E5", "=0.1*(E4+E6)"), ("E6", "=E4+E5")].map { (CellAddress($0.0)!, $0.1) })
        guard case .number(let e5) = c.book.sheets[0].value(CellAddress("E5")!),
              case .number(let e6) = c.book.sheets[0].value(CellAddress("E6")!) else { return XCTFail("not numbers") }
        XCTAssertEqual(e5, 1.3333333, accuracy: 0.001)
        XCTAssertEqual(e6, 7.3333333, accuracy: 0.001)
        XCTAssertTrue(c.engine.circular.isEmpty)
        // Without iteration the loop shows 0 and is flagged.
        let d = WorkbookController()
        d.setInputs([("E4", "6"), ("E5", "=0.1*(E4+E6)"), ("E6", "=E4+E5")].map { (CellAddress($0.0)!, $0.1) })
        XCTAssertEqual(d.book.sheets[0].value(CellAddress("E5")!), .number(0))
        XCTAssertFalse(d.engine.circular.isEmpty)
    }

    func testCalcPrRoundTrip() throws {
        let c = WorkbookController()
        c.book.iterate = true
        c.book.iterateCount = 50
        c.setInputs([("A1", "=A1+1")].map { (CellAddress($0.0)!, $0.1) })
        let data = try Xlsx.write(c.book)
        let back = try Xlsx.read(data)
        XCTAssertTrue(back.iterate)
        XCTAssertEqual(back.iterateCount, 50)
    }
}

final class XlsxPrefixedNamespaceTests: XCTestCase {
    /// A file whose SpreadsheetML carries an `x:` prefix (the Crafton Hills
    /// report in POI's corpus): read, written back, every part is in the
    /// default namespace and nothing is left half-prefixed.
    func testPrefixedMainNamespaceRoundTrips() throws {
        let main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        let rels = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let wb = """
        <?xml version="1.0" encoding="utf-8" standalone="yes"?><x:workbook xmlns:r="\(rels)" xmlns:x="\(main)"><x:workbookPr codeName="ThisWorkbook" /><x:sheets><x:sheet name="Report" sheetId="1" r:id="rId1" /></x:sheets></x:workbook>
        """
        let sheet = """
        <?xml version="1.0" encoding="utf-8" standalone="yes"?><x:worksheet xmlns:r="\(rels)" xmlns:x="\(main)"><x:sheetPr><x:outlinePr summaryBelow="1" /></x:sheetPr><x:dimension ref="A1:B2" /><x:sheetData><x:row r="1"><x:c r="A1" t="s"><x:v>0</x:v></x:c><x:c r="B1"><x:v>2</x:v></x:c></x:row><x:row r="2"><x:c r="B2"><x:f>B1*2</x:f><x:v>4</x:v></x:c></x:row></x:sheetData></x:worksheet>
        """
        let styles = """
        <?xml version="1.0" encoding="utf-8" standalone="yes"?><x:styleSheet xmlns:x="\(main)"><x:fonts count="1"><x:font><x:sz val="11" /><x:name val="Calibri" /></x:font></x:fonts><x:fills count="2"><x:fill><x:patternFill patternType="none" /></x:fill><x:fill><x:patternFill patternType="gray125" /></x:fill></x:fills><x:borders count="1"><x:border><x:left /><x:right /><x:top /><x:bottom /><x:diagonal /></x:border></x:borders><x:cellStyleXfs count="1"><x:xf numFmtId="0" fontId="0" fillId="0" borderId="0" /></x:cellStyleXfs><x:cellXfs count="1"><x:xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" /></x:cellXfs></x:styleSheet>
        """
        let sst = """
        <?xml version="1.0" encoding="utf-8"?><x:sst count="1" uniqueCount="1" xmlns:x="\(main)"><x:si><x:t>Unit</x:t></x:si></x:sst>
        """
        let types = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>
        """
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\(rels)/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """
        let wbRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\(rels)/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="\(rels)/styles" Target="styles.xml"/><Relationship Id="rId3" Type="\(rels)/sharedStrings" Target="sharedStrings.xml"/></Relationships>
        """
        let entries = [("[Content_Types].xml", types), ("_rels/.rels", rootRels), ("xl/workbook.xml", wb), ("xl/_rels/workbook.xml.rels", wbRels),
                       ("xl/worksheets/sheet1.xml", sheet), ("xl/styles.xml", styles), ("xl/sharedStrings.xml", sst)]
            .map { ZipEntry(name: $0.0, data: Data($0.1.utf8)) }
        let book = try Xlsx.read(Zip.write(entries))
        XCTAssertEqual(book.sheets[0].cells[CellAddress("A1")!]?.value, .text("Unit"))
        XCTAssertEqual(book.sheets[0].cells[CellAddress("B2")!]?.input, "=B1*2")
        let out = try Zip.read(Xlsx.write(book))
        for e in out where e.name.hasSuffix(".xml") {
            let text = String(decoding: e.data, as: UTF8.self)
            XCTAssertFalse(text.containsSubstring("<x:"), "\(e.name) still carries the x: prefix")
            XCTAssertFalse(text.containsSubstring("xmlns:x=\"\(main)\""), "\(e.name) still declares the x: prefix")
            if e.name.hasPrefix("xl/") { XCTAssertTrue(text.containsSubstring("xmlns=\"\(main)\""), "\(e.name) has no default namespace") }
        }
        let again = try Xlsx.read(Xlsx.write(book))
        XCTAssertEqual(again.sheets[0].cells[CellAddress("B1")!]?.value, .number(2))
    }
}
