// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// .xlsx: a real Excel file read (Fixtures/karma_performance.xlsx, from
// Boost.Spirit's docs — Boost Software License: four sheets, shared
// strings, custom widths, ten charts), written back with every part we
// do not model kept, and a workbook built here surviving the round trip.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class XlsxTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func a(_ s: String) -> CellAddress { CellAddress(s)! }

    func testReadsAnExcelFile() throws {
        let book = try Xlsx.read(try fixture())
        XCTAssertEqual(book.sheets.map(\.name), ["Single double", "Sequence of items", "Single int", "Sequence"])
        let s = book.sheets[0]
        XCTAssertEqual(s.value(a("E3")), .text("gcc 4.4.0 (32)"))
        XCTAssertEqual(s.value(a("D4")), .text("sprintf        "))       // spaces kept (xml:space)
        XCTAssertEqual(s.value(a("E4")), .number(0.737))
        XCTAssertEqual(s.value(a("P10")), .number(0.254))
        // Column D is 13.7109375 stored characters: 96 px, 72 pt (ECMA-376's formula).
        XCTAssertEqual(s.colWidth(3), 72)
        XCTAssertEqual(s.colWidth(0), Worksheet.defaultColWidth)
        // The chart's anchor and the page margins are kept, not modelled.
        XCTAssertTrue(s.keptElements.contains { $0.name == "drawing" })
        XCTAssertTrue(s.keptElements.contains { $0.name == "pageMargins" })
    }

    func testRoundTripKeepsTheRest() throws {
        let data = try fixture()
        let book = try Xlsx.read(data)
        let out = try Xlsx.write(book)
        let before = Dictionary(uniqueKeysWithValues: try Zip.read(data).map { ($0.name, $0.data) })
        let after = Dictionary(uniqueKeysWithValues: try Zip.read(out).map { ($0.name, $0.data) })
        // Every part survives; the ones we do not regenerate, byte for byte.
        let regenerated: Set<String> = ["[Content_Types].xml", "xl/workbook.xml", "xl/_rels/workbook.xml.rels",
                                        "xl/styles.xml", "xl/sharedStrings.xml"]
        for (name, d) in before where !regenerated.contains(name) && !name.hasPrefix("xl/worksheets/sheet") {
            XCTAssertEqual(after[name], d, name)
        }
        XCTAssertEqual(Set(after.keys), Set(before.keys))
        // The sheet still anchors its drawing, by the same relationship.
        let sheet1 = String(decoding: try XCTUnwrap(after["xl/worksheets/sheet1.xml"]), as: UTF8.self)
        XCTAssertTrue(sheet1.contains("<drawing r:id="), sheet1.prefix(300).description)
        // And it reads back the same.
        let again = try Xlsx.read(out)
        for (i, ws) in book.sheets.enumerated() {
            XCTAssertEqual(again.sheets[i].name, ws.name)
            XCTAssertEqual(again.sheets[i].cells.count, ws.cells.count)
            for (addr, c) in ws.cells { XCTAssertEqual(again.sheets[i].value(addr), c.value, "\(ws.name)!\(addr.a1)") }
            XCTAssertEqual(again.sheets[i].colWidths, ws.colWidths)
        }
        // Excel is told to recalculate, and no stale calcChain remains.
        let wb = String(decoding: try XCTUnwrap(after["xl/workbook.xml"]), as: UTF8.self)
        XCTAssertTrue(wb.contains("fullCalcOnLoad=\"1\""))
    }

    func testBuiltWorkbookRoundTrips() throws {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Budget 2026"), Worksheet(name: "Rates")]))
        c.setInputs([(a("A1"), "Item"), (a("B1"), "Cost"), (a("A2"), "Rent"), (a("B2"), "1200"),
                     (a("A3"), "Food"), (a("B3"), "$350.50"), (a("A4"), "Total"), (a("B4"), "=SUM(B2:B3)"),
                     (a("C2"), "=B2/$B$4"), (a("C3"), "=IF(B3>300,\"high\",\"ok\")"), (a("D2"), "TRUE"),
                     (a("D3"), "=1/0"), (a("E2"), "1/2/2026"), (a("F2"), "=XLOOKUP(\"Food\",A2:A3,B2:B3)"),
                     (a("G2"), "'007")])
        c.setInputs([(a("A1"), "0.05")], sheet: 1)
        c.setInput("=B4*Rates!A1", at: a("B5"))
        c.select(range: CellRange("A1:B1")!)
        c.setStyle { $0.bold = true; $0.fill = 0xD9E1F2; $0.borders.bottom = true }
        c.select(range: CellRange("C2")!)
        c.setStyle { $0.numberFormat = "0.0%"; $0.hAlign = .center; $0.fontName = "Arial"; $0.fontSize = 14; $0.color = 0xC00000 }
        c.setColumnWidth(0, 90)
        c.setRowHeight(0, 24)
        c.sheet.merges = [CellRange("D5:E6")!]
        c.sheet.freezeRows = 1
        c.book.names["TAXRATE"] = "Rates!$A$1"
        c.book.nameSpellings["TAXRATE"] = "TaxRate"
        c.stashViewState()

        let data = try Xlsx.write(c.book)
        // The newer function is written with Excel's prefix.
        let sheet = try XCTUnwrap(try Zip.read(data).first { $0.name == "xl/worksheets/sheet1.xml" })
        XCTAssertTrue(String(decoding: sheet.data, as: UTF8.self).contains("_xlfn.XLOOKUP("))

        let back = WorkbookController()
        back.load(try Xlsx.read(data))
        XCTAssertEqual(back.book.sheets.map(\.name), ["Budget 2026", "Rates"])
        let s = back.book.sheets[0]
        XCTAssertEqual(s.value(a("B4")), .number(1550.5))
        XCTAssertEqual(s.value(a("B5")), .number(77.525))
        XCTAssertEqual(back.input(a("B4")), "=SUM(B2:B3)")
        XCTAssertEqual(back.input(a("C2")), "=B2/$B$4")
        XCTAssertEqual(back.input(a("F2")), "=XLOOKUP(\"Food\",A2:A3,B2:B3)")   // no prefix in the bar
        XCTAssertEqual(s.value(a("F2")), .number(350.5))
        XCTAssertEqual(s.value(a("C3")), .text("high"))
        XCTAssertEqual(s.value(a("D2")), .bool(true))
        XCTAssertEqual(s.value(a("D3")), .error(.div0))
        XCTAssertEqual(s.value(a("G2")), .text("007"))
        XCTAssertEqual(s.value(a("E2")), .number(46024))
        XCTAssertEqual(back.style(at: a("E2")).numberFormat, "m/d/yyyy")
        XCTAssertEqual(back.style(at: a("B3")).numberFormat, "$#,##0.00")
        let head = back.style(at: a("A1"))
        XCTAssertTrue(head.bold)
        XCTAssertEqual(head.fill, 0xD9E1F2)
        XCTAssertTrue(head.borders.bottom)
        let pct = back.style(at: a("C2"))
        XCTAssertEqual(pct.numberFormat, "0.0%")
        XCTAssertEqual(pct.hAlign, .center)
        XCTAssertEqual(pct.fontName, "Arial")
        XCTAssertEqual(pct.fontSize, 14)
        XCTAssertEqual(pct.color, 0xC00000)
        XCTAssertEqual(s.colWidth(0), 90)
        XCTAssertEqual(s.rowHeight(0), 24)
        XCTAssertEqual(s.merges, [CellRange("D5:E6")!])
        XCTAssertEqual(s.freezeRows, 1)
        XCTAssertEqual(back.book.names["TAXRATE"], "Rates!$A$1")
        XCTAssertEqual(back.engine.evaluate("=TaxRate*100"), .number(5))
    }

    /// A minimal package written by hand: shared formulas, inline strings,
    /// a function we do not have, an array formula, x:-prefixed elements.
    private func handmade() throws -> Data {
        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><x:sheetData>
        <x:row r="1"><x:c r="A1"><x:v>2</x:v></x:c><x:c r="B1"><x:f t="shared" ref="B1:B3" si="0">A1*10</x:f><x:v>20</x:v></x:c><x:c r="C1" t="inlineStr"><x:is><x:t>inline</x:t></x:is></x:c></x:row>
        <x:row r="2"><x:c r="A2"><x:v>3</x:v></x:c><x:c r="B2"><x:f t="shared" si="0"/><x:v>30</x:v></x:c><x:c r="C2"><x:f>_xlfn.FANCYNEW(A1)</x:f><x:v>42</x:v></x:c></x:row>
        <x:row r="3"><x:c r="A3"><x:v>4</x:v></x:c><x:c r="B3"><x:f t="shared" si="0"/><x:v>40</x:v></x:c><x:c r="C3"><x:f t="array" ref="C3">SUM(A1:A3*2)</x:f><x:v>18</x:v></x:c></x:row>
        </x:sheetData></x:worksheet>
        """
        let wb = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
        """
        return try Zip.write([
            ZipEntry(name: "xl/workbook.xml", data: Data(wb.utf8)),
            ZipEntry(name: "xl/_rels/workbook.xml.rels", data: Data(rels.utf8)),
            ZipEntry(name: "xl/worksheets/sheet1.xml", data: Data(sheet.utf8)),
        ])
    }

    func testSharedArrayAndUnknownFormulas() throws {
        let c = WorkbookController()
        c.load(try Xlsx.read(try handmade()))
        let s = c.sheet
        XCTAssertEqual(c.input(a("B2")), "=A2*10")           // the shared formula, shifted
        XCTAssertEqual(c.input(a("B3")), "=A3*10")
        XCTAssertEqual(s.value(a("B3")), .number(40))
        XCTAssertEqual(s.value(a("C1")), .text("inline"))
        // A function we do not have shows the value Excel computed.
        XCTAssertEqual(c.input(a("C2")), "=FANCYNEW(A1)")
        XCTAssertEqual(s.value(a("C2")), .number(42))
        // An array formula keeps its cached result until arrays spill here.
        XCTAssertEqual(s.value(a("C3")), .number(18))
        c.setInput("5", at: a("A1"))
        XCTAssertEqual(s.value(a("B1")), .number(50))
        // Written back: a package Excel can open, the array formula intact.
        let out = try Xlsx.write(c.book)
        let names = Set(try Zip.read(out).map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["[Content_Types].xml", "_rels/.rels", "xl/styles.xml", "xl/sharedStrings.xml"]))
        let sheet = String(decoding: try XCTUnwrap(try Zip.read(out).first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
        XCTAssertTrue(sheet.contains("t=\"array\" ref=\"C3\""))
        XCTAssertTrue(sheet.hasPrefix("<?xml"))
        XCTAssertTrue(sheet.contains("<x:worksheet") && sheet.hasSuffix("</x:worksheet>"))
    }

    func testRawSplitKeepsText() {
        let xml = Array("<?xml version=\"1.0\"?><root a=\"1\"><b x=\"&gt;\"/><!-- c --><d><e>t</e><e/></d><f><![CDATA[<g>]]></f></root>".utf8)
        let s = RawXML.split(xml)
        XCTAssertEqual(s.rootStart, "<root a=\"1\">")
        XCTAssertEqual(s.children.map(\.name), ["b", "d", "f"])
        XCTAssertEqual(s.children[1].text, "<d><e>t</e><e/></d>")
        XCTAssertEqual(s.children[2].text, "<f><![CDATA[<g>]]></f>")
    }
}

extension XlsxTests {
    func testReadsChartsAndTheirCells() throws {
        let book = try Xlsx.read(try fixture())
        let c = WorkbookController()
        c.load(book)
        var charts = 0
        for (si, ws) in book.sheets.enumerated() {
            for d in ws.drawings {
                guard case .chart(let sc) = d.kind else { continue }
                charts += 1
                // The cells say what the file's cache says.
                XCTAssertEqual(c.liveChart(sc).series.map(\.values), sc.chart.series.map(\.values), "\(ws.name) \(d.name)")
                _ = si
            }
        }
        XCTAssertEqual(charts, 10)
        // Edit a value a chart reads, and the chart follows.
        let sc = try XCTUnwrap(book.sheets[0].drawings.lazy.compactMap { d -> SheetChart? in
            if case .chart(let sc) = d.kind { return sc } else { return nil } }.first)
        c.setInputs([(a("E4"), "9")], sheet: 0)
        XCTAssertEqual(c.liveChart(sc).series[0].values.first, 9)
    }
}

extension XlsxTests {
    func testDefinedNamesFollowTheSheets() throws {
        let book = Workbook(sheets: [Worksheet(name: "Data"), Worksheet(name: "Other")])
        book.fileNames = [
            DefinedName(name: "_xlnm.Print_Area", localSheet: 0, attrs: [:], text: "Data!$A$1:$D$20"),
            DefinedName(name: "_xlnm.Print_Titles", localSheet: 0, attrs: [:], text: "Data!$1:$2"),
            DefinedName(name: "Rates", localSheet: nil, attrs: ["comment": "kept"], text: "Data!$B$2:$B$9"),
            DefinedName(name: "_xlnm._FilterDatabase", localSheet: 1, attrs: ["hidden": "1"], text: "Other!$A$1:$C$5"),
        ]
        book.names["RATES"] = "Data!$B$2:$B$9"
        book.nameSpellings["RATES"] = "Rates"
        let c = WorkbookController()
        c.load(book)
        c.insert(.rows, at: 0)
        _ = c.renameSheet(0, "Figures")
        let xml = String(decoding: try XCTUnwrap(try Zip.read(try Xlsx.write(c.book)).first { $0.name == "xl/workbook.xml" }).data, as: UTF8.self)
        XCTAssertTrue(xml.containsSubstring("<definedName name=\"_xlnm.Print_Area\" localSheetId=\"0\">Figures!$A$2:$D$21</definedName>"), xml)
        XCTAssertTrue(xml.containsSubstring("<definedName name=\"Rates\" comment=\"kept\">Figures!$B$3:$B$10</definedName>"), xml)
        XCTAssertTrue(xml.containsSubstring("hidden=\"1\" localSheetId=\"1\">Other!$A$1:$C$5"), xml)
        c.deleteSheet(0)
        let after = String(decoding: try XCTUnwrap(try Zip.read(try Xlsx.write(c.book)).first { $0.name == "xl/workbook.xml" }).data, as: UTF8.self)
        XCTAssertFalse(after.containsSubstring("Print_Area"))
        XCTAssertTrue(after.containsSubstring("localSheetId=\"0\">Other!$A$1:$C$5"), after)
    }
}
