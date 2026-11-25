import XCTest
import OfficeText
@testable import OfficeApp

/// Not a pass/fail test (amd-8, 2026-11-25): with STARLING_SWEEP_DIR set, opens each document of that folder, makes one kind of
/// edit, saves, and counts by NAME (element, element@attribute, per part kind) what the original package had more of than the
/// saved one. Variants: base (no edit), then Word body / cell / header edits, or Sheets value / fill edits. Output: STARLING_SWEEP_OUT.
/// STARLING_SWEEP_KIND = docx | xlsx; STARLING_SWEEP_MAX caps the number of files.
final class EditLossSweepTests: XCTestCase {
    private func kind(_ part: String) -> String {
        let n = part.split(separator: "/").last.map(String.init) ?? part
        for k in ["document", "header", "footer", "styles", "numbering", "settings", "theme", "footnotes", "endnotes", "comments",
                  "workbook", "sharedStrings", "drawing", "chart", "table", "pivot", "calcChain", "vmlDrawing"] where n.hasPrefix(k) { return k }
        if part.contains("worksheets/") { return "sheet" }
        return n.hasSuffix(".rels") ? "rels" : n
    }
    private func walk(_ n: XNode, _ k: String, _ out: inout [String: Int]) {
        out[k + ":" + n.name, default: 0] += 1
        for (a, _) in n.attrs where !a.hasPrefix("xmlns") && a != "mc:Ignorable" { out[k + ":" + n.name + "@" + a, default: 0] += 1 }
        for c in n.children { walk(c, k, &out) }
    }
    private func counts(_ entries: [ZipEntry]) -> [String: Int] {
        var out: [String: Int] = [:]
        for e in entries where e.name.hasSuffix(".xml") || e.name.hasSuffix(".rels") {
            if let x = XNode.parse(e.data) { walk(x, kind(e.name), &out) } else { out["UNPARSED:" + kind(e.name), default: 0] += 1 }
        }
        return out
    }
    private func lost(_ a: [String: Int], _ b: [String: Int]) -> [String: Int] {
        var r: [String: Int] = [:]
        for (k, v) in a { let d = v - (b[k] ?? 0); if d > 0 { r[k] = d } }
        return r
    }

    func testSweep() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["STARLING_SWEEP_DIR"], let kindName = env["STARLING_SWEEP_KIND"] else { throw XCTSkip("no STARLING_SWEEP_DIR") }
        let isWord = kindName == "docx"
        var files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix("." + kindName) }.sorted()
        if let m = env["STARLING_SWEEP_MAX"].flatMap({ Int($0) }) { files = Array(files.prefix(m)) }
        let variants = isWord ? ["base", "body", "cell", "header"] : ["base", "value", "fill"]
        // per variant: name -> (docs, instances); delta = loss beyond the base loss of the same doc
        var docsLost: [String: [String: Int]] = [:], inst: [String: [String: Int]] = [:]
        var docsDelta: [String: [String: Int]] = [:], instDelta: [String: [String: Int]] = [:]
        var applied: [String: Int] = [:], failed = 0, edited = 0
        let prog = FileHandle(forWritingAtPath: (env["STARLING_SWEEP_OUT"] ?? "/tmp/x") + ".progress") ?? { FileManager.default.createFile(atPath: (env["STARLING_SWEEP_OUT"] ?? "/tmp/x") + ".progress", contents: nil); return FileHandle(forWritingAtPath: (env["STARLING_SWEEP_OUT"] ?? "/tmp/x") + ".progress")! }()
        for f in files {
            let t0 = Date(); defer { prog.write(Data("\(f)\t\(Int(Date().timeIntervalSince(t0) * 1000)) ms\n".utf8)) }
            guard let data = FileManager.default.contents(atPath: dir + "/" + f), let entries = try? Zip.read(data) else { failed += 1; continue }
            let orig = counts(entries)
            var baseLoss: [String: Int] = [:]
            for v in variants {
                var out: Data?
                var did = v == "base"
                if isWord {
                    guard let d = try? DocxFormat.read(data) else { failed += 1; break }
                    var doc = d.document
                    func boldWord(_ i: Int) -> Bool {
                        let t = doc.paragraphs[i].text
                        guard let r = t.range(of: #"\p{L}+"#, options: .regularExpression) else { return false }
                        let lo = t.utf16.distance(from: t.startIndex, to: r.lowerBound), hi = t.utf16.distance(from: t.startIndex, to: r.upperBound)
                        doc.paragraphs[i].applyStyle(lo ..< hi) { $0.bold = true }
                        return true
                    }
                    switch v {
                    case "body":
                        let idx = doc.paragraphs.indices.filter { doc.paragraphs[$0].cell == nil && doc.paragraphs[$0].image == nil && !doc.paragraphs[$0].text.isEmpty }
                        let step = max(1, idx.count / 5)
                        for i in stride(from: 0, to: idx.count, by: step).prefix(5) where boldWord(idx[i]) { did = true }
                    case "cell":
                        if let i = doc.paragraphs.indices.first(where: { doc.paragraphs[$0].cell != nil && !doc.paragraphs[$0].text.isEmpty }) { did = boldWord(i) }
                    case "header":
                        if !doc.header.isEmpty { doc.header += " X"; did = true }
                    default: break
                    }
                    out = did ? try? DocxFormat.write(doc, pageSetup: d.pageSetup ?? .letter) : nil
                } else {
                    guard let book = try? Xlsx.read(data) else { failed += 1; break }
                    let c = WorkbookController(); c.load(book)
                    if v != "base" {
                        for si in c.book.sheets.indices {
                            c.activeSheet = si
                            let a = CellAddress(row: 0, col: 0)
                            c.select(a)
                            if v == "value" { c.setInputs([(a, "12345")], sheet: si); did = true }
                            else { c.setStyle({ $0.fill = 0xFFAA00 }, range: CellRange(a)); did = true }
                        }
                    }
                    out = did ? try? Xlsx.write(c.book) : nil
                }
                guard did, let o = out, let saved = try? Zip.read(o) else { if did { failed += 1 }; continue }
                applied[v, default: 0] += 1; if v != "base" { edited += 1 }
                let l = lost(orig, counts(saved))
                if v == "base" { baseLoss = l }
                for (k, n) in l {
                    docsLost[v, default: [:]][k, default: 0] += 1; inst[v, default: [:]][k, default: 0] += n
                    if v != "base", n > (baseLoss[k] ?? 0) { docsDelta[v, default: [:]][k, default: 0] += 1; instDelta[v, default: [:]][k, default: 0] += n - (baseLoss[k] ?? 0) }
                }
            }
        }
        var lines = ["files \(files.count) failed \(failed) applied \(applied.sorted { $0.key < $1.key })"]
        for v in variants {
            lines.append("== \(v) \(v == "base" ? "(save with no edit)" : "(loss beyond the no-edit save)"): docs\tinstances\tname")
            let d = v == "base" ? docsLost[v] ?? [:] : docsDelta[v] ?? [:], n = v == "base" ? inst[v] ?? [:] : instDelta[v] ?? [:]
            for (k, c) in d.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(400) { lines.append("\(c)\t\(n[k] ?? 0)\t\(k)") }
        }
        try lines.joined(separator: "\n").write(toFile: env["STARLING_SWEEP_OUT"] ?? "/data/s/amd-8/sweep/result.txt", atomically: true, encoding: .utf8)
    }
}
