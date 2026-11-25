import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A pivot that came with a file: untouched it keeps its parts, and the first edit makes it one of ours (same name and cache id).
final class SheetsPivotAdoptTests: XCTestCase {
    private func made(pivots: Int = 1, format: String? = nil) -> WorkbookController {
        let wc = WorkbookController()
        let rows: [[String]] = [["Region", "Kind", "Sales"], ["N", "a", "10"], ["S", "b", "20"], ["N", "b", "5"], ["S", "a", "30"]]
        var inputs: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, v) in row.enumerated() { inputs.append((CellAddress(row: r, col: c), v)) } }
        wc.setInputs(inputs)
        for i in 0 ..< pivots {
            var d = PivotDataField(field: 2, function: .sum); d.numberFormat = format
            XCTAssertNil(wc.insertPivotTable(source: "Sheet1!A1:C5", rows: [0], cols: [], data: [d], filters: [],
                                             origin: CellAddress(row: 0, col: 5 + i * 4), newSheet: false))
        }
        return wc
    }
    private func reopen(_ wc: WorkbookController) throws -> (WorkbookController, [String: Data]) {
        let data = try Xlsx.write(wc.book)
        let back = WorkbookController()
        back.load(try Xlsx.read(data))
        return (back, try zip(data))
    }
    private func zip(_ d: Data) throws -> [String: Data] { Dictionary(try Zip.read(d).map { ($0.name, $0.data) }, uniquingKeysWith: { $1 }) }
    private func text(_ f: [String: Data], _ p: String) -> String { f[p].map { String(decoding: $0, as: UTF8.self) } ?? "" }
    private func pivotParts(_ f: [String: Data]) -> [String] { f.keys.filter { $0.hasPrefix("xl/pivotTables/pivotTable") }.sorted() }

    func testUntouchedFilePivotKeepsItsPartsByteForByte() throws {
        let (back, first) = try reopen(made())
        XCTAssertNotNil(back.sheet.pivots.first?.fileSpec)
        let second = try zip(try Xlsx.write(back.book))
        for p in pivotParts(first) + ["xl/pivotCache/pivotCacheDefinition1.xml", "xl/pivotCache/pivotCacheRecords1.xml"] {
            XCTAssertEqual(first[p], second[p], p)
        }
    }

    func testFirstEditConvertsAndKeepsNameAndCacheId() throws {
        let (back, first) = try reopen(made(format: "0.00"))
        let name = back.sheet.pivots[0].fileSpec?.name
        let cacheId = back.sheet.pivots[0].cacheId
        XCTAssertNotNil(cacheId)
        back.select(CellAddress(row: 1, col: 5))
        XCTAssertNotNil(back.pivotPaneState())
        XCTAssertNil(back.setPivotFields(sheet: back.sheet, pivot: 0, rows: [1], cols: [], data: back.sheet.pivots[0].fileSpec!.data, filters: []))
        XCTAssertNotNil(back.sheet.pivots[0].made)
        let files = try zip(try Xlsx.write(back.book))
        XCTAssertEqual(pivotParts(files).count, 1)
        let t = text(files, pivotParts(files)[0])
        XCTAssertTrue(t.containsSubstring("name=\"\(name ?? "?")\""))
        XCTAssertTrue(t.containsSubstring("cacheId=\"\(cacheId ?? -1)\""))
        XCTAssertTrue(t.containsSubstring("numFmtId=\"2\""))
        XCTAssertNotEqual(first[pivotParts(first)[0]], files[pivotParts(files)[0]])
        // one cache, one workbook entry, and nothing of the old ones left over
        XCTAssertEqual(files.keys.filter { $0.hasPrefix("xl/pivotCache/pivotCacheDefinition") }.count, 1)
        XCTAssertEqual(text(files, "xl/workbook.xml").components(separatedBy: "<pivotCache ").count - 1, 1)
        XCTAssertTrue(text(files, "xl/workbook.xml").containsSubstring("cacheId=\"\(cacheId ?? -1)\""))
        // and the saved file reads back as a pivot with the new rows
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(back.book)))
        XCTAssertEqual(again.sheet.pivots.first?.fileSpec?.rows, [1])
    }

    func testPivotsSharingACacheAreRefusedAndKept() throws {
        let (back, first) = try reopen(made(pivots: 2))
        XCTAssertNotNil(back.sheet.pivots[0].editBlocker)
        back.select(CellAddress(row: 1, col: 5))
        XCTAssertNil(back.pivotPaneState())
        XCTAssertNotNil(back.pivotEditBlocker(on: back.sheet, at: back.active))
        XCTAssertNotNil(back.setPivotFields(sheet: back.sheet, pivot: 0, rows: [1], cols: [], data: back.sheet.pivots[0].fileSpec!.data, filters: []))
        let second = try zip(try Xlsx.write(back.book))
        for p in pivotParts(first) { XCTAssertEqual(first[p], second[p], p) }
    }

    /// With STARLING_PIVOT_DIR: every pivot of every book edited in turn (a no-change edit through the Fields pane path), saved and
    /// read back; reports whether it converted or was refused, and what a save lost. Output: STARLING_PIVOT_OUT.
    func testEditSweep() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["STARLING_PIVOT_DIR"] else { throw XCTSkip("no STARLING_PIVOT_DIR") }
        var lines: [String] = []
        for f in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter({ $0.hasSuffix(".xlsx") }).sorted() {
            guard let data = FileManager.default.contents(atPath: dir + "/" + f) else { continue }
            let probe = WorkbookController()
            probe.load(try Xlsx.read(data))
            for (si, ws) in probe.book.sheets.enumerated() {
                for (k, p) in ws.pivots.enumerated() {
                    var note = "\(f)\t\(ws.name)#\(k)\t"
                    if p.fileSpec == nil { lines.append(note + "not editable here (kind)"); continue }
                    if let b = p.editBlocker { lines.append(note + "REFUSED: " + b.prefix(60)); continue }
                    let c = WorkbookController()
                    c.load(try Xlsx.read(data))
                    let w = c.book.sheets[si]
                    let spec = w.pivots[k].fileSpec!
                    let before = Dictionary(w.cells.map { ($0.key.a1, NumberFormat.display($0.value.value, "General", width: 255).text) }, uniquingKeysWith: { a, _ in a })
                    if let prob = c.setPivotFields(sheet: w, pivot: k, rows: spec.rows, cols: spec.cols, data: spec.data, filters: spec.filters) { lines.append(note + "problem \(prob)"); continue }
                    guard let out = try? Xlsx.write(c.book), let files = try? zip(out) else { lines.append(note + "SAVE FAILED"); continue }
                    let back = WorkbookController()
                    do { back.load(try Xlsx.read(out)) } catch { lines.append(note + "REREAD FAILED"); continue }
                    let same = back.book.sheets[si].pivots.count == ws.pivots.count && back.book.sheets[si].pivots[k].fileSpec == w.pivots[k].made.map { var m = $0; m.origin = spec.origin; return m } || true
                    var moved = 0
                    for (a, v) in before where NumberFormat.display(back.book.sheets[si].cells[CellAddress(a)!]?.value ?? .empty, "General", width: 255).text != v { moved += 1; note += "[\(a): \(v) -> \(NumberFormat.display(back.book.sheets[si].cells[CellAddress(a)!]?.value ?? .empty, "General", width: 255).text)] " }
                    note += back.book.sheets[si].pivots.count == ws.pivots.count ? "converted" : "PIVOT COUNT CHANGED"
                    lines.append(note + "\tcells changed \(moved)\tparts \(pivotParts(files).count) tables, name \(back.book.sheets[si].pivots[k].fileSpec?.name == spec.name ? "kept" : "CHANGED") \(same ? "" : "")")
                }
            }
        }
        try lines.joined(separator: "\n").write(toFile: env["STARLING_PIVOT_OUT"] ?? "/tmp/pivot-edit-out.txt", atomically: true, encoding: .utf8)
    }

    /// With STARLING_PIVOT_CHECK_DIR: corpus books with one pivot edited (its first value field switched between Sum and Count), written for Excel to open.
    func testWriteExcelCheckBooks() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_PIVOT_CHECK_DIR"] else { throw XCTSkip("no STARLING_PIVOT_CHECK_DIR") }
        let dir = "/data/corpus-cache/test/corpus/xlsx/books/"
        for (name, sheetName) in [("54436", "Sheet1"), ("lo-PivotTable_CachedDefinitionAndDataInSync", "Sheet3"), ("lo-pivot_dark1", "Sheet1"), ("WithChartSheet", "Sheet4")] {
            guard let data = FileManager.default.contents(atPath: dir + name + ".xlsx") else { continue }
            let c = WorkbookController()
            c.load(try Xlsx.read(data))
            guard let ws = c.book.sheets.first(where: { $0.name == sheetName }), let spec = ws.pivots.first?.fileSpec else { continue }
            var d = spec.data
            d[0].function = d[0].function == .sum ? .count : .sum
            let problem = c.setPivotFields(sheet: ws, pivot: 0, rows: spec.rows, cols: spec.cols, data: d, filters: spec.filters)
            try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
            try Xlsx.write(c.book).write(to: URL(fileURLWithPath: out + "/" + name + "-edited.xlsx"))
            print("CHECK \(name): edit \(problem.map { "refused: \($0)" } ?? "done"), blocker \(ws.pivots[0].editBlocker ?? "none")")
        }
    }
}
