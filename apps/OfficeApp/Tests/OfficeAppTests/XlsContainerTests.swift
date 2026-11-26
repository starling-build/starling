import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class XlsContainerTests: XCTestCase {
    private func rec(_ type: UInt16, _ body: [UInt8]) -> [UInt8] {
        [UInt8(type & 255), UInt8(type >> 8), UInt8(body.count & 255), UInt8(body.count >> 8)] + body
    }
    private func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24 & 255)] }

    private func boundsheet(_ name: String, kind: UInt8 = 0, hidden: UInt8 = 0) -> [UInt8] {
        rec(0x85, le32(0) + [hidden, kind, UInt8(name.utf8.count), 0] + Array(name.utf8))
    }

    /// A one-stream compound file (512-byte sectors, every stream in regular sectors).
    private func compound(stream name: String, _ content: [UInt8]) -> [UInt8] {
        precondition(content.count <= 512)
        var h = [UInt8](repeating: 0, count: 512)
        h.replaceSubrange(0 ..< 8, with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        h[0x1E] = 9; h[0x20] = 6
        h.replaceSubrange(0x2C ..< 0x30, with: le32(1))
        h.replaceSubrange(0x30 ..< 0x34, with: le32(1))
        h.replaceSubrange(0x38 ..< 0x3C, with: le32(0))
        h.replaceSubrange(0x3C ..< 0x40, with: le32(0xFFFF_FFFE))
        h.replaceSubrange(0x44 ..< 0x48, with: le32(0xFFFF_FFFE))
        for k in 0 ..< 109 { h.replaceSubrange(0x4C + k * 4 ..< 0x50 + k * 4, with: le32(k == 0 ? 0 : 0xFFFF_FFFF)) }
        var fat = [UInt8](repeating: 0xFF, count: 512)
        fat.replaceSubrange(0 ..< 4, with: le32(0xFFFF_FFFD))
        fat.replaceSubrange(4 ..< 8, with: le32(0xFFFF_FFFE))
        fat.replaceSubrange(8 ..< 12, with: le32(0xFFFF_FFFE))
        func entry(_ n: String, type: UInt8, child: UInt32, start: UInt32, size: UInt32) -> [UInt8] {
            var e = [UInt8](repeating: 0, count: 128)
            let u = Array(n.utf16)
            for (i, c) in u.enumerated() { e[i * 2] = UInt8(c & 255); e[i * 2 + 1] = UInt8(c >> 8) }
            e[64] = UInt8((u.count + 1) * 2); e[66] = type
            e.replaceSubrange(68 ..< 72, with: le32(0xFFFF_FFFF))
            e.replaceSubrange(72 ..< 76, with: le32(0xFFFF_FFFF))
            e.replaceSubrange(76 ..< 80, with: le32(child))
            e.replaceSubrange(116 ..< 120, with: le32(start))
            e.replaceSubrange(120 ..< 124, with: le32(size))
            return e
        }
        var dir = entry("Root Entry", type: 5, child: 1, start: 0xFFFF_FFFE, size: 0)
        dir += entry(name, type: 2, child: 0xFFFF_FFFF, start: 2, size: UInt32(content.count))
        dir += [UInt8](repeating: 0, count: 256)
        return h + fat + dir + content + [UInt8](repeating: 0, count: 512 - content.count)
    }

    private var book: [UInt8] {
        rec(0x809, [UInt8](repeating: 0, count: 16)) + boundsheet("Alpha") + boundsheet("Beta", hidden: 1) + rec(0x0A, [])
    }

    func testAStreamIsFoundWhateverTheCaseOfItsName() throws {
        for name in ["Workbook", "WORKBOOK", "workbook"] {
            let f = try CompoundFile(compound(stream: name, book))
            XCTAssertEqual(f.stream("Workbook")?.count, book.count, name)
            XCTAssertNil(f.stream("Other"))
        }
    }

    func testTheSheetsComeBackInWorkbookOrderWithTheirHiddenState() throws {
        let f = try CompoundFile(compound(stream: "Workbook", book))
        let sh = Xls.sheets(BiffReader.records(try XCTUnwrap(Xls.workbookStream(f))))
        XCTAssertEqual(sh.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(sh.map(\.hidden), [0, 1])
    }

    func testAContinueRecordExtendsTheRecordBeforeItAndMarksWhereItBegins() {
        let s = rec(0xFC, [1, 2, 3]) + rec(0x3C, [4, 5]) + rec(0x3C, [6]) + rec(0x0A, [])
        let r = BiffReader.records(s)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].body, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(r[0].segments, [0, 3, 5])
    }

    func testTheOpenerReadsWhatAFileHoldsNotWhatItIsCalled() throws {
        let xls = Data(compound(stream: "Book", book))
        XCTAssertEqual(try Workbook.open(xls, name: "data.xlsx").sheets.map(\.name), ["Alpha", "Beta"])
        let csv = Data("a,b\n1,2\n".utf8)
        XCTAssertEqual(try Workbook.open(csv, name: "x.xls").sheets.count, 1)
    }

    func testATruncatedOrDamagedFileThrowsOrReadsLessButNeverTraps() {
        let good = compound(stream: "Workbook", book)
        for n in stride(from: 0, to: good.count, by: 7) {
            if let f = try? CompoundFile(Array(good[0 ..< n])) { _ = f.streamPaths; _ = f.stream("Workbook").map(BiffReader.records) }
        }
        var seed: UInt64 = 12345
        for _ in 0 ..< 400 {
            var bad = good
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            bad[Int(seed >> 33) % bad.count] ^= UInt8(truncatingIfNeeded: seed >> 20) | 1
            if let f = try? CompoundFile(bad) { _ = f.streamPaths; _ = f.stream("Workbook").map(BiffReader.records) }
        }
    }

    private func u16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255)] }

    /// A book with a string split across CONTINUE (1 byte per character, then 2), numbers in RK, MULRK and plain form, a boolean, an error and a merge.
    private func cat(_ parts: [UInt8]...) -> [UInt8] { parts.flatMap { $0 } }

    private func valuesBook() -> [UInt8] {
        func globals(_ sheetAt: Int) -> [UInt8] {
            let bof = rec(0x809, cat(u16(0x600), [UInt8](repeating: 0, count: 14)))
            let sstBody = cat(le32(2), le32(2), u16(2), [0, 0x61, 0x62], u16(4), [0, 0x63, 0x64])
            let sst = cat(rec(0xFC, sstBody), rec(0x3C, [1, 0x65, 0, 0x66, 0]))
            let sheet = rec(0x85, cat(le32(UInt32(sheetAt)), [0, 0, 1, 0, 0x53]))
            return cat(bof, sst, sheet, rec(0x0A, []))
        }
        let at = globals(0).count
        let bof = rec(0x809, cat(u16(0x600), [UInt8](repeating: 0, count: 14)))
        let bits = (2.5).bitPattern
        let lo = UInt32(bits & 0xFFFF_FFFF), hi = UInt32(bits >> 32)
        let a1 = rec(0xFD, cat(u16(0), u16(0), u16(0), le32(1)))
        let b1 = rec(0x27E, cat(u16(0), u16(1), u16(0), le32(314 << 2 | 3)))
        let row2 = rec(0xBD, cat(u16(1), u16(0), u16(0), le32(7 << 2 | 2), u16(0), le32(25 << 2 | 2), u16(1)))
        let a3 = rec(0x203, cat(u16(2), u16(0), u16(0), le32(lo), le32(hi)))
        let b3 = rec(0x205, cat(u16(2), u16(1), u16(0), [1, 0]))
        let c3 = rec(0x205, cat(u16(2), u16(2), u16(0), [0x07, 1]))
        let merge = rec(0xE5, cat(u16(1), u16(3), u16(4), u16(0), u16(1)))
        return cat(globals(at), bof, a1, b1, row2, a3, b3, c3, merge, rec(0x0A, []))
    }

    func testValuesComeThroughWhateverTheirRecordKind() throws {
        let wb = try Xls.read(Data(compound(stream: "Workbook", valuesBook())))
        let s = try XCTUnwrap(wb.sheets.first)
        XCTAssertEqual(s.name, "S")
        func v(_ r: Int, _ c: Int) -> CellValue? { s.cells[CellAddress(row: r, col: c)]?.value }
        XCTAssertEqual(v(0, 0), .text("cdef"))
        XCTAssertEqual(v(0, 1), .number(3.14))
        XCTAssertEqual(v(1, 0), .number(7))
        XCTAssertEqual(v(1, 1), .number(25))
        XCTAssertEqual(v(2, 0), .number(2.5))
        XCTAssertEqual(v(2, 1), .bool(true))
        XCTAssertEqual(s.merges, [CellRange(top: 3, left: 0, bottom: 4, right: 1)])
    }

    func testADamagedBookStillReadsOrThrowsNeverTraps() {
        let good = compound(stream: "Workbook", valuesBook())
        var seed: UInt64 = 99
        for _ in 0 ..< 600 {
            var bad = good
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            bad[512 + Int(seed >> 33) % 1024] ^= UInt8(truncatingIfNeeded: seed >> 20) | 1
            _ = try? Xls.read(Data(bad))
        }
    }

    func testPageSetupFollowsTheSetupRecord() {
        func page(_ grbit: Int, scale: Int = 100, paper: Int = 9) -> String {
            XlsBuild.pageXML(setup: [0: paper, 1: scale, 2: 1, 3: 1, 4: 1, 5: grbit], margins: [nil, nil, nil, nil],
                             hdrFtr: [nil, nil], margin2: nil, grid: false, heads: false, hc: false, vc: false,
                             hBreaks: [], vBreaks: [])
        }
        let landscape = page(0, scale: 80)
        XCTAssertTrue(landscape.containsSubstring("orientation=\"landscape\""))
        XCTAssertTrue(landscape.containsSubstring("scale=\"80\""))
        XCTAssertTrue(landscape.containsSubstring("paperSize=\"9\""))
        // fNoPls: the printer settings are invalid, so paper and scale mean nothing.
        let noPls = page(4, scale: 330)
        XCTAssertFalse(noPls.containsSubstring("scale="))
        XCTAssertFalse(noPls.containsSubstring("paperSize"))
        XCTAssertTrue(noPls.containsSubstring("orientation=\"portrait\""))
        // fNoOrient: the orientation bit is ignored, the page is portrait.
        XCTAssertTrue(page(0x40).containsSubstring("orientation=\"portrait\""))
    }

    func testConditionalFormatsBecomeRulesWithDifferentialFormats() throws {
        let bof = rec(0x809, cat(u16(0x600), [UInt8](repeating: 0, count: 14)))
        let globals = cat(bof, rec(0x85, cat(le32(0), [0, 0, 1, 0, 0x53])), rec(0x0A, []))
        let at = globals.count
        let g = cat(bof, rec(0x85, cat(le32(UInt32(at)), [0, 0, 1, 0, 0x53])), rec(0x0A, []))
        // CONDFMT: one rule, bounding range A1:A3, one range A1:A3.
        let cf = rec(0x1B0, cat(u16(1), u16(0), u16(0), u16(2), u16(0), u16(0), u16(1), u16(0), u16(2), u16(0), u16(0)))
        // CF: cell value, greater than, a formula of one integer (30), a pattern block with a red background.
        let rule = rec(0x1B1, cat([1, 5], u16(3), u16(0), le32(0xA03B_FFFF), u16(0x0280), u16(0), u16(0x0540), [0x1E, 30, 0]))
        let sheet = cat(bof, cf, rule, rec(0x0A, []))
        let parts = try XCTUnwrap(XlsBuild.parts(BiffReader.records(g + sheet)))
        func text(_ n: String) -> String { String(decoding: parts.first { $0.name == n }!.data, as: UTF8.self) }
        let ws = text("xl/worksheets/sheet1.xml")
        XCTAssertTrue(ws.containsSubstring("<conditionalFormatting sqref=\"A1:A3\">"))
        XCTAssertTrue(ws.containsSubstring("operator=\"greaterThan\""))
        XCTAssertTrue(ws.containsSubstring("<formula>30</formula>"))
        XCTAssertTrue(text("xl/styles.xml").containsSubstring("<dxfs count=\"1\"><dxf><fill><patternFill><bgColor rgb=\"FFFF0000\"/>"))
    }

    func testDataValidationBecomesValidationRule() throws {
        let bof = rec(0x809, cat(u16(0x600), [UInt8](repeating: 0, count: 14)))
        let g0 = cat(bof, rec(0x85, cat(le32(0), [0, 0, 1, 0, 0x53])), rec(0x0A, []))
        let g = cat(bof, rec(0x85, cat(le32(UInt32(g0.count)), [0, 0, 1, 0, 0x53])), rec(0x0A, []))
        func empty() -> [UInt8] { u16(0) + [0] }
        // whole number between 1 and 9, blank allowed, error alert shown, cells B2:B4.
        let flags: UInt32 = 1 | 0x100 | 0x80000
        let dv = rec(0x1BE, cat(le32(flags), empty(), empty(), empty(), empty(),
                                u16(3), u16(0), [0x1E, 1, 0], u16(3), u16(0), [0x1E, 9, 0],
                                u16(1), u16(1), u16(3), u16(1), u16(1)))
        let sheet = cat(bof, dv, rec(0x0A, []))
        let parts = try XCTUnwrap(XlsBuild.parts(BiffReader.records(g + sheet)))
        let ws = String(decoding: parts.first { $0.name == "xl/worksheets/sheet1.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(ws.containsSubstring("type=\"whole\""))
        XCTAssertTrue(ws.containsSubstring("sqref=\"B2:B4\""))
        XCTAssertTrue(ws.containsSubstring("<formula2>9</formula2>"))
    }

    func testHyperlinkBecomesLinkWithAddress() throws {
        let bof = rec(0x809, cat(u16(0x600), [UInt8](repeating: 0, count: 14)))
        let g0 = cat(bof, rec(0x85, cat(le32(0), [0, 0, 1, 0, 0x53])), rec(0x0A, []))
        let g = cat(bof, rec(0x85, cat(le32(UInt32(g0.count)), [0, 0, 1, 0, 0x53])), rec(0x0A, []))
        let url = Array("http://a.b/".utf16 + [0]).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        let guid: [UInt8] = [0xD0, 0xC9, 0xEA, 0x79, 0xF9, 0xBA, 0xCE, 0x11, 0x8C, 0x82, 0, 0xAA, 0, 0x4B, 0xA9, 0x0B]
        let moniker: [UInt8] = [0xE0] + [UInt8](repeating: 0, count: 15)
        _ = guid
        let h = rec(0x1B8, cat(u16(0), u16(0), u16(0), u16(0), moniker, le32(2), le32(3), moniker, le32(UInt32(url.count)), url))
        let parts = try XCTUnwrap(XlsBuild.parts(BiffReader.records(g + cat(bof, h, rec(0x0A, [])))))
        func text(_ n: String) -> String { String(decoding: parts.first { $0.name == n }!.data, as: UTF8.self) }
        XCTAssertTrue(text("xl/worksheets/sheet1.xml").containsSubstring("<hyperlink ref=\"A1\" r:id=\"rIdL1\"/>"))
        XCTAssertTrue(text("xl/worksheets/_rels/sheet1.xml.rels").containsSubstring("Target=\"http://a.b/\""))
    }

    func testSheetExtGivesTheTabColour() throws {
        let bof = rec(0x809, cat(u16(0x600), [UInt8](repeating: 0, count: 14)))
        let g0 = cat(bof, rec(0x85, cat(le32(0), [0, 0, 1, 0, 0x53])), rec(0x0A, []))
        let g = cat(bof, rec(0x85, cat(le32(UInt32(g0.count)), [0, 0, 1, 0, 0x53])), rec(0x0A, []))
        let ext = rec(0x862, cat(u16(0x862), [UInt8](repeating: 0, count: 10), le32(0x28), le32(0), le32(0), le32(2), [0x00, 0xB0, 0xF0, 0xFF], [UInt8](repeating: 0, count: 16)))
        let parts = try XCTUnwrap(XlsBuild.parts(BiffReader.records(g + cat(bof, ext, rec(0x0A, [])))))
        let ws = String(decoding: parts.first { $0.name == "xl/worksheets/sheet1.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(ws.containsSubstring("<tabColor rgb=\"FF00B0F0\"/>"))
    }

    func testPictureBecomesDrawingWithMedia() throws {
        func art(_ ver: Int, _ inst: Int, _ type: Int, _ body: [UInt8]) -> [UInt8] {
            cat(u16(ver | inst << 4), u16(type), le32(UInt32(body.count)), body)
        }
        let bof = rec(0x809, cat(u16(0x600), [UInt8](repeating: 0, count: 14)))
        let g0 = cat(bof, rec(0x85, cat(le32(0), [0, 0, 1, 0, 0x53])), rec(0x0A, []))
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]
        let blip = art(0, 0x6E0, 0xF01E, cat([UInt8](repeating: 0, count: 17), png))
        let fbse = art(2, 6, 0xF007, cat([UInt8](repeating: 0, count: 36), blip))
        let group = art(0xF, 0, 0xF000, art(0xF, 1, 0xF001, fbse))
        let sp = art(2, 75, 0xF00A, cat(le32(1025), le32(0xA00)))
        let opt = art(3, 1, 0xF00B, cat(u16(0x4104), le32(1)))
        let anchor = art(0, 0, 0xF010, cat(u16(0), u16(1), u16(0), u16(2), u16(0), u16(3), u16(0), u16(4), u16(0)))
        let drawing = art(0xF, 0, 0xF002, art(0xF, 0, 0xF004, cat(sp, opt, anchor)))
        let wb = cat(bof, rec(0x85, cat(le32(UInt32(g0.count) + UInt32(4 + group.count)), [0, 0, 1, 0, 0x53])), rec(0xEB, group), rec(0x0A, []))
        let parts = try XCTUnwrap(XlsBuild.parts(BiffReader.records(wb + cat(bof, rec(0xEC, drawing), rec(0x0A, [])))))
        XCTAssertEqual(parts.first { $0.name.hasPrefix("xl/media/") }.map { [UInt8]($0.data) }, png)
        let dp = parts.first { $0.name.hasPrefix("xl/drawings/drawing") && !$0.name.containsSubstring("_rels") }
        let d = String(decoding: dp?.data ?? Data(), as: UTF8.self)
        XCTAssertTrue(d.containsSubstring("<xdr:col>1</xdr:col>") && d.containsSubstring("<xdr:row>2</xdr:row>"))
    }

    func testChartBecomesChartPart() throws {
        func art(_ ver: Int, _ inst: Int, _ type: Int, _ body: [UInt8]) -> [UInt8] {
            cat(u16(ver | inst << 4), u16(type), le32(UInt32(body.count)), body)
        }
        let bof = rec(0x809, cat(u16(0x600), [UInt8](repeating: 0, count: 14)))
        let cbof = rec(0x809, cat(u16(0x600), u16(0x20), [UInt8](repeating: 0, count: 12)))
        let g0 = cat(bof, rec(0x85, cat(le32(0), [0, 0, 1, 0, 0x53])), rec(0x0A, []))
        let g = cat(bof, rec(0x85, cat(le32(UInt32(g0.count)), [0, 0, 1, 0, 0x53])), rec(0x0A, []))
        let sp = art(2, 201, 0xF00A, cat(le32(1025), le32(0xA00)))
        let anchor = art(0, 0, 0xF010, cat(u16(0), u16(1), u16(0), u16(2), u16(0), u16(6), u16(0), u16(12), u16(0)))
        let drawing = art(0xF, 0, 0xF002, art(0xF, 0, 0xF004, cat(sp, anchor)))
        let cmo = cat(u16(0x15), u16(18), u16(5), u16(1), u16(0x2011), [UInt8](repeating: 0, count: 12))
        let ser = rec(0x1003, cat(u16(3), u16(1), u16(1), u16(1)))
        let chart = cat(cbof, rec(0x1002, [UInt8](repeating: 0, count: 16)), ser,
                        rec(0x1014, [UInt8](repeating: 0, count: 20)), rec(0x1017, cat(u16(0), u16(150), u16(0))), rec(0x0A, []))
        let sheet = cat(bof, rec(0xEC, drawing), rec(0x5D, cmo), chart, rec(0x0A, []))
        let parts = try XCTUnwrap(XlsBuild.parts(BiffReader.records(g + sheet)))
        let cp = parts.first { $0.name.hasPrefix("xl/charts/chart") }
        let c = String(decoding: cp?.data ?? Data(), as: UTF8.self)
        XCTAssertTrue(c.containsSubstring("barChart"))
    }

    func testFormulaTokensBecomeFormulaText() {
        let ctx = XlsFormulaContext(xtis: [], internalBooks: [], sheetNames: [], names: [])
        // A1+B2*3 : ref A1, ref B2, int 3, mul, add
        let t: [UInt8] = [0x24, 0, 0, 0, 0xC0, 0x24, 1, 0, 1, 0xC0, 0x1E, 3, 0, 0x05, 0x03]
        XCTAssertEqual(XlsFormula.decompile(t, row: 5, col: 5, relative: false, ctx: ctx), "A1+B2*3")
        // SUM(A1:B2): area, SUM with one argument
        let s: [UInt8] = [0x25, 0, 0, 1, 0, 0, 0xC0, 1, 0xC0, 0x22, 1, 4, 0]
        XCTAssertEqual(XlsFormula.decompile(s, row: 0, col: 3, relative: false, ctx: ctx), "SUM(A1:B2)")
        // A shared formula's relative reference is an offset from the cell.
        let r: [UInt8] = [0x2C, 0xFF, 0xFF, 0xFF, 0xC0]
        XCTAssertEqual(XlsFormula.decompile(r, row: 4, col: 2, relative: true, ctx: ctx), "B4")
        // A function this reader does not know leaves the cell on its cached value.
        let u: [UInt8] = [0x21, 0xFF, 0x7F]
        XCTAssertNil(XlsFormula.decompile(u, row: 0, col: 0, relative: false, ctx: ctx))
    }
}

extension XlsContainerTests {
    func testAWideBuiltInNameKeepsItsArea() {
        // ko-e0c4deb6ff's Print_Area NAME record: the option byte says wide, so the built-in's one character is 16 bits.
        let hex = "200000010b0000000100000000000106003b00000000540001000e00"
        var body: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex { let j = hex.index(i, offsetBy: 2); body.append(UInt8(hex[i ..< j], radix: 16)!); i = j }
        let r = BiffRecord(type: 0x18, body: body, segments: [0], offset: 0)
        XCTAssertEqual(XlsBuild.definedNamesXML([r], xtis: [(0, 0)], sheetNames: ["S"], kept: [0]),
                       "<definedNames><definedName name=\"_xlnm.Print_Area\" localSheetId=\"0\">S!$B$1:$O$85</definedName></definedNames>")
        XCTAssertTrue(XlsBuild.nameText(r).contains("Print_Area"), XlsBuild.nameText(r))
    }
}
