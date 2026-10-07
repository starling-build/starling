// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// `OfficeApp --xlsx-check file.xlsx…`: Excel as the formula oracle. Every
// formula cell in a file carries the value Excel last computed for it
// (`<v>`); this reads each file, recalculates every formula with our
// engine, and compares. A cell counts as
//   ok        our value matches the cached one (numbers to 1e-9 relative)
//   kept      the engine fell back to the file's value — a function it
//             lacks, a formula it could not read, a legacy array formula
//   volatile  NOW, RAND, OFFSET…: the file's value cannot be expected
//   DIFF      computed, and different
// One line per file (`ok kept volatile diff name`), then the first diffs
// of each file as `sheet!A1  =formula  ours | excel`. Exit 1 if any file
// fails to read; diffs are the report, not the verdict.

import Foundation

enum SheetsCheck {
    struct Counts { var ok = 0, kept = 0, volatile = 0, diff = 0, noCache = 0 }

    static func run(_ paths: [String], maxDiffs: Int = Int(ProcessInfo.processInfo.environment["XLSX_CHECK_MAX"] ?? "") ?? 12) -> Int32 {
        var failed: Int32 = 0
        var total = Counts()
        for path in paths {
            let name = path.lastPathComponent
            guard let data = FileManager.default.contents(atPath: path) else {
                print("READ-FAIL \(name): no such file"); failed = 1; continue
            }
            let c = WorkbookController()
            do {
                c.load(try Xlsx.read(data))
            } catch {
                print("READ-FAIL \(name): \(error)"); failed = 1; continue
            }
            var counts = Counts()
            var diffs: [String] = []
            var volatileSeen: [CalcEngine.SheetCell: Bool] = [:]
            for (si, ws) in c.book.sheets.enumerated() {
                for addr in ws.cells.keys.sorted() {
                    guard let cell = ws.cells[addr], cell.isFormula else { continue }
                    guard let cached = cell.cached else { counts.noCache += 1; continue }
                    if cell.rawFormula != nil || cell.formula == nil || (cell.arrayRef != nil && !cell.dynamic) {
                        counts.kept += 1; continue
                    }
                    let f = cell.formula!
                    if Formula.usesUnknownFunction(f) { counts.kept += 1; continue }
                    if volatile(f, c.book, sheet: si, seen: &volatileSeen) { counts.volatile += 1; continue }
                    let ours = c.engine.value(si, addr)
                    if same(ours, cached) { counts.ok += 1; continue }
                    counts.diff += 1
                    if diffs.count < maxDiffs {
                        diffs.append("  \(ws.name)!\(addr.a1)  \(cell.input)  \(show(ours)) | \(show(cached))")
                    }
                }
            }
            print(String(format: "%5d ok %4d kept %3d volatile %4d DIFF  %@", counts.ok, counts.kept, counts.volatile, counts.diff, name))
            for d in diffs { print(d) }
            total.ok += counts.ok; total.kept += counts.kept; total.volatile += counts.volatile; total.diff += counts.diff
        }
        if paths.count > 1 {
            print(String(format: "TOTAL %d ok %d kept %d volatile %d DIFF in %d files", total.ok, total.kept, total.volatile, total.diff, paths.count))
        }
        return failed
    }

    /// Volatile itself, or reading (through cells and names) a cell that is:
    /// TODAY() two cells upstream still makes the file's value a stale one.
    static func volatile(_ f: FormulaExpr, _ book: Workbook, sheet: Int, seen: inout [CalcEngine.SheetCell: Bool]) -> Bool {
        if Formula.isVolatile(f) { return true }
        var refs: [FormulaRef] = []
        Formula.references(f, into: &refs)
        var names: [String] = []
        Formula.names(f, into: &names)
        for n in names {
            if let t = book.names[n.uppercased()], let e = try? Formula.parse(t) {
                if Formula.isVolatile(e) { return true }
                Formula.references(e, into: &refs)
            }
        }
        for r in refs {
            let si = r.sheet.flatMap { book.sheet(named: $0) } ?? sheet
            guard si >= 0, si < book.sheets.count else { continue }
            let rg = r.range
            // Whole columns and big areas: look only at formula cells inside.
            for (addr, cell) in book.sheets[si].cells where rg.contains(addr) {
                guard let cf = cell.formula else { continue }
                let key = CalcEngine.SheetCell(sheet: si, cell: addr)
                if let known = seen[key] { if known { return true } else { continue } }
                seen[key] = false
                let v = volatile(cf, book, sheet: si, seen: &seen)
                seen[key] = v
                if v { return true }
            }
        }
        return false
    }

    static func same(_ a: CellValue, _ b: CellValue) -> Bool {
        switch (a, b) {
        case (.number(let x), .number(let y)):
            if x == y { return true }
            let scale = max(abs(x), abs(y))
            return abs(x - y) <= 1e-9 * max(scale, 1)
        case (.text(let x), .text(let y)): return x == y
        case (.bool(let x), .bool(let y)): return x == y
        case (.error(let x), .error(let y)): return x == y
        case (.empty, .text(let y)): return y.isEmpty
        case (.text(let x), .empty): return x.isEmpty
        case (.number(let x), .empty), (.empty, .number(let x)): return x == 0
        // Excel caches a formula's boolean as 1/0 in some writers.
        case (.bool(let x), .number(let y)), (.number(let y), .bool(let x)): return (x ? 1 : 0) == y
        default: return false
        }
    }

    static func show(_ v: CellValue) -> String {
        switch v {
        case .empty: return "(empty)"
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .text(let s): return "\"\(s)\""
        case .bool(let b): return b ? "TRUE" : "FALSE"
        case .error(let e): return e.rawValue
        }
    }
}
