import XCTest
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Not a pass/fail test (amd-8, 2026-11-25): with STARLING_SWEEP_DIR set, opens each document of that folder, makes one kind of
/// edit, saves, and counts by NAME (element, element@attribute, per part kind) what the original package had more of than the
/// saved one. Variants: base (no edit), then Word body / cell / header edits, or Sheets value / fill edits. Output: STARLING_SWEEP_OUT.
/// Slides (2026-11-26): base, a bold word in up to 5 text shapes, a shape moved 1 pt.
/// STARLING_SWEEP_KIND = docx | xlsx | pptx; STARLING_SWEEP_MAX caps the number of files.
final class EditLossSweepTests: XCTestCase {
    private func kind(_ part: String) -> String {
        let n = part.split(separator: "/").last.map(String.init) ?? part
        for k in ["document", "header", "footer", "styles", "numbering", "settings", "theme", "footnotes", "endnotes", "comments",
                  "workbook", "sharedStrings", "slideMaster", "slideLayout", "notesSlide", "notesMaster", "slide", "presentation", "presProps", "viewProps", "tableStyles", "drawing", "chart", "table", "pivot", "calcChain", "vmlDrawing"] where n.hasPrefix(k) { return k }
        if part.contains("worksheets/") { return "sheet" }
        return n.hasSuffix(".rels") ? "rels" : n
    }
    /// Attributes that change nothing a reader sees (amd-8, 2026-11-25; lenovo-3 found these counted as losses): a false flag equals the
    /// attribute being absent, row heights are only effective with customHeight, a height or width equal to the sheet default is the
    /// default, row spans are an optimisation hint, rsid* attributes are revision ids.
    private static let flagNames: Set<String> = ["hidden", "customHeight", "customWidth", "bestFit", "collapsed", "thickBot", "thickTop",
        "phonetic", "ph", "quotePrefix", "pivotButton"]
    private func effective(_ n: XNode, _ a: String, _ v: String, _ ctx: [String: String]) -> Bool {
        let local = a.split(separator: ":").last.map(String.init) ?? a
        if local.hasPrefix("rsid") { return false }
        let off = (v == "0" || v == "false" || v == "off")
        if Self.flagNames.contains(local) && off { return false }
        if local == "outlineLevel" && v == "0" { return false }
        if n.name == "row" {
            if local == "spans" { return false }
            if local == "ht" {
                let custom = n.attrs["customHeight"]
                if custom == nil || custom == "0" || custom == "false" { return false }
                if let d = ctx["rowH"], Double(d) == Double(v) { return false }
            }
        }
        if n.name == "col" && local == "width", let d = ctx["colW"], Double(d) == Double(v) { return false }
        return true
    }
    private func walk(_ n: XNode, _ k: String, _ out: inout [String: Int], _ ctx: inout [String: String]) {
        out[k + ":" + n.name, default: 0] += 1
        if n.name == "sheetFormatPr" {
            if let v = n.attrs["defaultRowHeight"] { ctx["rowH"] = v }
            if let v = n.attrs["defaultColWidth"] ?? n.attrs["baseColWidth"] { ctx["colW"] = v }
        }
        for (a, v) in n.attrs where !a.hasPrefix("xmlns") && a != "mc:Ignorable" && effective(n, a, v, ctx) {
            out[k + ":" + n.name + "@" + a, default: 0] += 1
        }
        for c in n.children { walk(c, k, &out, &ctx) }
    }
    private func counts(_ entries: [ZipEntry]) -> [String: Int] {
        var out: [String: Int] = [:]
        for e in entries where e.name.hasSuffix(".xml") || e.name.hasSuffix(".rels") {
            if let x = XNode.parse(e.data) { var ctx: [String: String] = [:]; walk(x, kind(e.name), &out, &ctx) } else { out["UNPARSED:" + kind(e.name), default: 0] += 1 }
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
        let isWord = kindName == "docx", isSlides = kindName == "pptx"
        var files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix("." + kindName) }.sorted()
        if let m = env["STARLING_SWEEP_MAX"].flatMap({ Int($0) }) { files = Array(files.prefix(m)) }
        let variants = isWord ? ["base", "body", "cell", "header"] : isSlides ? ["base", "text", "move"] : ["base", "value", "fill"]
        // per variant: name -> (docs, instances); delta = loss beyond the base loss of the same doc
        var docsLost: [String: [String: Int]] = [:], inst: [String: [String: Int]] = [:]
        var docsDelta: [String: [String: Int]] = [:], instDelta: [String: [String: Int]] = [:]
        var deltaDocs: [String: [String: [String]]] = [:]  // the first few docs behind each edit loss, to find them
        var applied: [String: Int] = [:], failed = 0, edited = 0
        let prog = FileHandle(forWritingAtPath: (env["STARLING_SWEEP_OUT"] ?? "/tmp/x") + ".progress") ?? { FileManager.default.createFile(atPath: (env["STARLING_SWEEP_OUT"] ?? "/tmp/x") + ".progress", contents: nil); return FileHandle(forWritingAtPath: (env["STARLING_SWEEP_OUT"] ?? "/tmp/x") + ".progress")! }()
        var docsGain: [String: Int] = [:], instGain: [String: Int] = [:]
        for f in files {
            let t0 = Date(); defer { prog.write(Data("\(f)\t\(Int(Date().timeIntervalSince(t0) * 1000)) ms\n".utf8)) }
            guard let data = FileManager.default.contents(atPath: dir + "/" + f), let entries = try? Zip.read(data) else { failed += 1; continue }
            let orig = counts(entries)
            var baseLoss: [String: Int] = [:]
            for v in variants {
                var out: Data?
                var did = v == "base"
                if isSlides {
                    guard let r = try? Pptx.read(data) else { failed += 1; break }
                    var state = r.0
                    let theme = r.1, pkg = r.2
                    func firstWord(_ t: String) -> Range<Int>? {
                        guard let w = t.range(of: #"\p{L}+"#, options: String.CompareOptions.regularExpression) else { return nil }
                        return t.utf16.distance(from: t.startIndex, to: w.lowerBound) ..< t.utf16.distance(from: t.startIndex, to: w.upperBound)
                    }
                    switch v {
                    case "text":
                        var n = 0
                        for si in state.slides.indices where n < 5 {
                            for hi in state.slides[si].shapes.indices {
                                guard var doc = state.slides[si].shapes[hi].text else { continue }
                                guard let pi = doc.paragraphs.indices.first(where: { firstWord(doc.paragraphs[$0].text) != nil }),
                                      let w = firstWord(doc.paragraphs[pi].text) else { continue }
                                doc.paragraphs[pi].applyStyle(w) { $0.bold = true }
                                state.slides[si].shapes[hi].text = doc; n += 1; did = true
                                break
                            }
                        }
                    case "move":
                        if let si = state.slides.indices.first(where: { !state.slides[$0].shapes.isEmpty }) {
                            let f = state.slides[si].shapes[0].frame
                            state.slides[si].shapes[0].frame = Rect.fromLTWH(f.left + 1, f.top, f.width, f.height); did = true
                        }
                    default: break
                    }
                    out = did ? try? PptxWriter.write(state, theme: theme, package: pkg, ownTemplates: state.ownTemplates ?? false,
                                                      recolourTheme: state.recolourTheme ?? false) : nil
                } else if isWord {
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
                let sc = counts(saved)
                let l = lost(orig, sc)
                if v == "base" {
                    baseLoss = l
                    // Gains: effective attributes/elements present after the save but not before (a save that ADDS customHeight to every
                    // row freezes heights Excel would refit). Only the no-edit save is checked: an edit adds its own marks on purpose.
                    for (k, n) in lost(sc, orig) { docsGain[k, default: 0] += 1; instGain[k, default: 0] += n }
                }
                for (k, n) in l {
                    docsLost[v, default: [:]][k, default: 0] += 1; inst[v, default: [:]][k, default: 0] += n
                    if v != "base", n > (baseLoss[k] ?? 0) { docsDelta[v, default: [:]][k, default: 0] += 1
                        if deltaDocs[v, default: [:]][k, default: []].count < 3 { deltaDocs[v, default: [:]][k, default: []].append(f) }
                        instDelta[v, default: [:]][k, default: 0] += n - (baseLoss[k] ?? 0) }
                }
            }
        }
        var lines = ["files \(files.count) failed \(failed) applied \(applied.sorted { $0.key < $1.key })"]
        for v in variants {
            lines.append("== \(v) \(v == "base" ? "(save with no edit)" : "(loss beyond the no-edit save)"): docs\tinstances\tname")
            let d = v == "base" ? docsLost[v] ?? [:] : docsDelta[v] ?? [:], n = v == "base" ? inst[v] ?? [:] : instDelta[v] ?? [:]
            for (k, c) in d.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(400) {
                let who = v == "base" ? "" : "\t" + (deltaDocs[v]?[k] ?? []).joined(separator: " ")
                lines.append("\(c)\t\(n[k] ?? 0)\t\(k)\(who)")
            }
        }
        lines.append("== gain-base (added by the save with no edit): docs\tinstances\tname")
        for (k, c) in docsGain.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(400) { lines.append("\(c)\t\(instGain[k] ?? 0)\t\(k)") }
        try lines.joined(separator: "\n").write(toFile: env["STARLING_SWEEP_OUT"] ?? "/data/s/amd-8/sweep/result.txt", atomically: true, encoding: .utf8)
    }
}
