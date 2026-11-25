import XCTest
@testable import OfficeApp

/// With STARLING_PIVOT_DIR set: opens each book of that folder, edits one cell, saves, and reports every pivot / slicer / timeline
/// part (and the workbook's pivotCaches list) that is gone or differs. Output: STARLING_PIVOT_OUT. Skipped otherwise.
final class SheetsPivotKeepTests: XCTestCase {
    private static func canon(_ d: Data) -> String {
        // Whitespace between tags does not matter; attribute order does not either.
        guard let n = XNode.parse(d) else { return String(decoding: d, as: UTF8.self) }
        func s(_ n: XNode) -> String {
            n.name + n.attrs.sorted { $0.key < $1.key }.map { "[\($0.key)=\($0.value)]" }.joined() + "{" + n.text.trimmingWhitespace() + n.children.map(s).joined(separator: ",") + "}"
        }
        return s(n)
    }
    func testPivotPartsSurviveAnEdit() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["STARLING_PIVOT_DIR"] else { throw XCTSkip("no STARLING_PIVOT_DIR") }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".xlsx") }.sorted()
        var lines: [String] = []
        func pv(_ n: String) -> Bool { let l = n.lowercased(); return l.contains("pivot") || l.contains("slicer") || l.contains("timeline") }
        for f in files {
            guard let data = FileManager.default.contents(atPath: dir + "/" + f), let orig = try? Zip.read(data) else { lines.append("\(f)\tUNREADABLE"); continue }
            let c = WorkbookController()
            c.load(try Xlsx.read(data))
            let a = CellAddress(row: 0, col: 0)
            c.select(a)
            c.setInputs([(a, "12345")], sheet: 0)
            guard let out = try? Xlsx.write(c.book), let saved = try? Zip.read(out) else { lines.append("\(f)\tSAVE FAILED"); continue }
            let so = Dictionary(saved.map { ($0.name, $0.data) }, uniquingKeysWith: { a, _ in a })
            var gone: [String] = [], diff: [String] = [], same = 0, effective = 0
            for e in orig where pv(e.name) {
                guard let s = so[e.name] else { gone.append(e.name); continue }
                if s == e.data { same += 1 }
                else if e.name.hasSuffix(".xml") || e.name.hasSuffix(".rels"), Self.canon(s) == Self.canon(e.data) { effective += 1 }
                else { diff.append(e.name) }
            }
            // the workbook's own list, and the content types
            func wb(_ es: [ZipEntry]) -> String {
                guard let w = es.first(where: { $0.name == "xl/workbook.xml" }), let r = XNode.parse(w.data), let p = r.first("pivotCaches") else { return "-" }
                return Self.canon(Data(String(describing: p.children.count).utf8)) + "/" + p.children.map { $0.attrs["cacheId"] ?? "?" }.joined(separator: ",")
            }
            // what the sheets and their rels say about pivots and slicers
            func refs(_ es: [ZipEntry]) -> [String] {
                var r: [String] = []
                for e in es where e.name.hasPrefix("xl/") && (e.name.hasSuffix(".rels") || e.name.hasPrefix("xl/worksheets/sheet")) {
                    let t = String(decoding: e.data, as: UTF8.self)
                    if e.name.hasSuffix(".rels") {
                        for x in XNode.parse(e.data)?.relationships() ?? [] where pv((x.attrs["Target"] ?? "") + (x.attrs["Type"] ?? "")) { r.append(e.name + ">" + (x.attrs["Target"] ?? "")) }
                    } else {
                        for k in ["slicerList", "pivotSelection", "x14:slicer", "timeslicer"] where t.containsSubstring(k) { r.append(e.name + ":" + k) }
                    }
                }
                return r.sorted()
            }
            let refGone = Set(refs(orig)).subtracting(refs(saved)).sorted()
            let wo = wb(orig), ws = wb(saved)
            let ct: (([ZipEntry]) -> Set<String>) = { es in
                guard let w = es.first(where: { $0.name == "[Content_Types].xml" }), let r = XNode.parse(w.data) else { return [] }
                return Set(r.children.compactMap { $0.attrs["PartName"] }.filter { pv($0) })
            }
            let ctGone = ct(orig).subtracting(ct(saved)).sorted()
            // the workbook's own relationships, Type and Target together (a chart sheet once came
            // back as a worksheet link)
            let wrels: (([ZipEntry]) -> Set<String>) = { es in
                guard let w = es.first(where: { $0.name == "xl/_rels/workbook.xml.rels" }) else { return [] }
                return Set((XNode.parse(w.data)?.relationships() ?? []).map { ($0.attrs["Type"] ?? "").split(separator: "/").last.map(String.init)! + " " + ($0.attrs["Target"] ?? "") }
                    .filter { !$0.hasPrefix("calcChain") })
            }
            let relGone = wrels(orig).subtracting(wrels(saved)).sorted()
            let bad = !gone.isEmpty || !diff.isEmpty || wo != ws || !refGone.isEmpty || !ctGone.isEmpty || !relGone.isEmpty
            lines.append("\(f)\t\(bad ? "LOSS" : "ok")\tbyte-same \(same), equal \(effective)" + (gone.isEmpty ? "" : "\tGONE \(gone)") + (diff.isEmpty ? "" : "\tDIFF \(diff)") + (relGone.isEmpty ? "" : "\tWORKBOOK RELS \(relGone)") + (wo != ws ? "\tWORKBOOK pivotCaches \(wo) -> \(ws)" : "") + (refGone.isEmpty ? "" : "\tREF-GONE \(refGone)") + (ctGone.isEmpty ? "" : "\tCT-GONE \(ctGone)"))
        }
        try lines.joined(separator: "\n").write(toFile: env["STARLING_PIVOT_OUT"] ?? "/tmp/pivot-out.txt", atomically: true, encoding: .utf8)
    }

    /// A pivot table's cache is built from cells and its table sits on cells: renaming the source sheet or moving the rows
    /// changes what its parts must say, as Excel's does.
    func testPivotPartsFollowARenameAndInsertedRows() throws {
        let path = "/data/corpus-cache/test/corpus/xlsx/books/54436.xlsx"
        guard let data = FileManager.default.contents(atPath: path) else { throw XCTSkip("corpus book not in the cache") }
        func parts(_ c: WorkbookController) throws -> [String: String] {
            Dictionary(try Zip.read(try Xlsx.write(c.book)).map { ($0.name, String(decoding: $0.data, as: UTF8.self)) }, uniquingKeysWith: { a, _ in a })
        }
        let c = WorkbookController()
        c.load(try Xlsx.read(data))
        let before = try parts(c)
        XCTAssertTrue(before["xl/pivotCache/pivotCacheDefinition1.xml"]!.containsSubstring("<worksheetSource ref=\"A1:C6\" sheet=\"Sheet1\"/>"))
        c.activeSheet = 0
        c.insert(.rows, at: 0)
        XCTAssertTrue(c.renameSheet(0, "Data x"))
        var p = try parts(c)
        XCTAssertTrue(p["xl/pivotCache/pivotCacheDefinition1.xml"]!.containsSubstring("<worksheetSource ref=\"A2:C7\" sheet=\"Data x\"/>"), p["xl/pivotCache/pivotCacheDefinition1.xml"]!)
        XCTAssertTrue(p["xl/pivotTables/pivotTable1.xml"]!.containsSubstring("<location ref=\"A9:B12\""))
        c.undo(); c.undo()
        p = try parts(c)
        XCTAssertEqual(p["xl/pivotCache/pivotCacheDefinition1.xml"], before["xl/pivotCache/pivotCacheDefinition1.xml"], "undone: the part is as it was")
        XCTAssertEqual(p["xl/pivotTables/pivotTable1.xml"], before["xl/pivotTables/pivotTable1.xml"])
    }

    /// Writes the Excel check book when STARLING_PIVOT_FOLLOW names a file; skipped otherwise.
    func testWriteFollowBook() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_PIVOT_FOLLOW"] else { throw XCTSkip("no STARLING_PIVOT_FOLLOW") }
        let data = try XCTUnwrap(FileManager.default.contents(atPath: "/data/corpus-cache/test/corpus/xlsx/books/54436.xlsx"))
        let c = WorkbookController()
        c.load(try Xlsx.read(data))
        c.activeSheet = 0
        c.insert(.rows, at: 2, count: 2)
        XCTAssertTrue(c.renameSheet(0, "Sales Data"))
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: out))
    }
}
