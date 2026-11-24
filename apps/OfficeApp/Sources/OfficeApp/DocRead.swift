// The legacy Word binary format (.doc, Word 97-2003: MS-DOC), read into .docx
// parts the same way XlsBuild turns a .xls into .xlsx parts: the container
// (CompoundFile), the FIB (file information block), the piece table (CLX) that
// says where each run of the text lives, and then the document written as
// WordprocessingML for the docx reader to open.
//
// M0: the main story's text and its paragraphs, nothing else yet. Later
// milestones add character and paragraph properties, styles, sections, tables,
// lists, fields and pictures; the parts below grow with them.
//
// Shared code (also built for the web): bytes and our own helpers only.

import Foundation

/// What the FIB says: where the streams are and how long each story is.
struct DocFib {
    var nFib = 0
    var encrypted = false
    var tableStream = "0Table"
    var ccpText = 0
    var ccpFtn = 0
    var ccpHdd = 0
    var ccpAtn = 0
    var ccpEdn = 0
    var ccpTxbx = 0
    var ccpHdrTxbx = 0
    /// (fc, lcb) pairs of FibRgFcLcb, in the file's order.
    var fcLcb: [(fc: Int, lcb: Int)] = []

    static let fcStshf = 1, fcPlcfSed = 6, fcPlcfHdd = 11, fcPlcfBteChpx = 12, fcPlcfBtePapx = 13, fcSttbfFfn = 15, fcClx = 33

    func range(_ index: Int) -> (fc: Int, lcb: Int)? { index < fcLcb.count && fcLcb[index].lcb > 0 ? fcLcb[index] : nil }

    init?(_ w: [UInt8]) {
        guard w.count >= 154, OfficeArt.u16(w, 0) == 0xA5EC else { return nil }
        nFib = OfficeArt.u16(w, 2)
        let flags = OfficeArt.u16(w, 10)
        encrypted = flags & 0x100 != 0
        tableStream = flags & 0x200 != 0 ? "1Table" : "0Table"
        // csw, the 16-bit words (fibRgW), then cslw, the 32-bit ones (fibRgLw), then the (fc, lcb) pairs.
        let csw = OfficeArt.u16(w, 32)
        let lwAt = 34 + csw * 2
        let cslw = OfficeArt.u16(w, lwAt)
        let lw = lwAt + 2
        func ccp(_ k: Int) -> Int { k < cslw ? OfficeArt.u32(w, lw + 4 * k) : 0 }
        ccpText = ccp(3); ccpFtn = ccp(4); ccpHdd = ccp(5); ccpAtn = ccp(7); ccpEdn = ccp(8); ccpTxbx = ccp(9); ccpHdrTxbx = ccp(10)
        let pairsAt = lw + cslw * 4
        let n = OfficeArt.u16(w, pairsAt)
        var at = pairsAt + 2
        for _ in 0 ..< n {
            guard at + 8 <= w.count else { break }
            fcLcb.append((OfficeArt.u32(w, at), OfficeArt.u32(w, at + 4)))
            at += 8
        }
    }
}

/// One run of the text: characters [cp, next cp) are at `fc` in the WordDocument stream.
struct DocPiece {
    var cp: Int
    var cpEnd: Int
    var fc: Int
    var compressed: Bool
    var prm = 0            // the piece's property modifier (Prm1: an index into the CLX's grpprl list; Prm0, one sprm by index, is not read: no dev file has one)
    var grpprl: [UInt8] = []   // the sprms that modifier stands for
}

enum DocRead {
    /// Windows-1252 for the bytes of a compressed piece (0x80-0x9F differ from Latin-1).
    private static let cp1252: [UInt16] = [
        0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
        0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
    ]

    /// The piece table out of the CLX (a run of grpprl "Prc"s, then the "Pcdt" holding the PlcPcd).
    /// The end of a header or footer story's text: its last paragraph mark closes the story and takes no line of its own
    /// (pt-2b169d7457: three marks after the last text line are two paragraphs in Word, not three).
    static func storyEnd(_ a: Int, _ b: Int) -> Int { b - a > 1 ? b - 1 : b }

    /// The settings part of a binary file: it lays out as Word's earlier modes do, so the mark of a paragraph that ends
    /// in a page break stands on the page the break opens (pt-2b169d7457's cover page).
    static func settingsXML(facing: Bool, tabStop: Int? = nil) -> String {
        "<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">" + (facing ? "<w:evenAndOddHeaders/>" : "") + (tabStop.map { "<w:defaultTabStop w:val=\"\($0)\"/>" } ?? "") + "<w:compat><w:splitPgBreakAndParaMark/></w:compat></w:settings>"
    }

    static func pieces(clx: [UInt8]) -> [DocPiece] {
        var p = 0
        var prcs: [[UInt8]] = []
        while p < clx.count, clx[p] == 0x01 {
            let n = OfficeArt.u16(clx, p + 1)
            if p + 3 + n <= clx.count { prcs.append(Array(clx[p + 3 ..< p + 3 + n])) }
            p += 3 + n
        }
        guard p + 5 <= clx.count, clx[p] == 0x02 else { return [] }
        let lcb = OfficeArt.u32(clx, p + 1)
        let plc = p + 5
        guard plc + lcb <= clx.count, lcb >= 4 else { return [] }
        // n + 1 character positions, then n 8-byte piece descriptors.
        let n = (lcb - 4) / 12
        var out: [DocPiece] = []
        for k in 0 ..< n {
            let cp = OfficeArt.u32(clx, plc + 4 * k), end = OfficeArt.u32(clx, plc + 4 * (k + 1))
            let d = plc + 4 * (n + 1) + 8 * k
            let raw = OfficeArt.u32(clx, d + 2)
            let compressed = raw & 0x4000_0000 != 0
            let fc = raw & 0x3FFF_FFFF
            guard end > cp else { continue }
            let prm = OfficeArt.u16(clx, d + 6)
            var g: [UInt8] = []
            if prm & 1 != 0 { let i = prm >> 1; if i < prcs.count { g = prcs[i] } }
            out.append(DocPiece(cp: cp, cpEnd: end, fc: compressed ? fc / 2 : fc, compressed: compressed, prm: prm, grpprl: g))
        }
        return out
    }

    /// The characters [0, count) of the document, as UTF-16 code units.
    static func text(_ w: [UInt8], pieces: [DocPiece], count: Int) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(count)
        for pc in pieces where pc.cp < count {
            let n = min(pc.cpEnd, count) - pc.cp
            for i in 0 ..< n {
                if pc.compressed {
                    let at = pc.fc + i
                    guard at < w.count else { break }
                    let b = w[at]
                    out.append(b >= 0x80 && b < 0xA0 ? cp1252[Int(b) - 0x80] : UInt16(b))
                } else {
                    let at = pc.fc + 2 * i
                    guard at + 2 <= w.count else { break }
                    out.append(UInt16(w[at]) | UInt16(w[at + 1]) << 8)
                }
            }
        }
        return out
    }

    private static func esc(_ u: [UInt16]) -> String {
        var s = String.UnicodeScalarView()
        var i = 0
        while i < u.count {
            var c = UInt32(u[i])
            if c >= 0xD800, c < 0xDC00, i + 1 < u.count, u[i + 1] >= 0xDC00, u[i + 1] < 0xE000 {
                c = 0x10000 + ((c - 0xD800) << 10) + UInt32(u[i + 1]) - 0xDC00
                i += 1
            }
            i += 1
            switch c {
            case 0x26: s.append(contentsOf: "&amp;".unicodeScalars)
            case 0x3C: s.append(contentsOf: "&lt;".unicodeScalars)
            case 0x3E: s.append(contentsOf: "&gt;".unicodeScalars)
            default: if let sc = Unicode.Scalar(c) { s.append(sc) }
            }
        }
        return String(s)
    }

    /// Where a story sits and what hangs off its characters: the first character's position in the document,
    /// the section properties ending a paragraph, the notes referenced, and whether it is a note's own text.
    struct StoryContext {
        var base = 0
        var sectEnds: [Int: String] = [:]
        var footnotes: [Int: Int] = [:]
        var comments: [Int: Int] = [:]
        var endnotes: [Int: Int] = [:]
        var noteKind = ""            // "footnote" or "endnote" inside a note's own text
        var shapes: [Int: (xml: String, behind: Bool)] = [:]   // character position of a shape anchor -> its drawing run
        var styles = ""             // the style sheet's XML, to settle toggled character flags against
        var picture: ((Int) -> String?)?         // the run of the inline picture whose data sits at an offset of the Data stream
    }

    /// The paragraphs of a story as `w:p` elements: a paragraph mark (0D, or 07 for a cell or row end)
    /// ends one. A PAGE or NUMPAGES field stays a field; any other keeps its result and drops its instruction.
    static func paragraphs(_ t: [UInt16], chp: [DocPropRun] = [], pap: [DocPropRun] = [], fonts: [String] = [], ctx: StoryContext = StoryContext()) -> String {
        var xml = ""
        var runs = "", cur: [UInt16] = []
        struct Field { var instr: [UInt16] = []; var inInstr = true; var live = false }
        var fields: [Field] = []
        var rpr = ""
        var ci = 0, pi = 0
        // The property list covering `cp` (runs are sorted; the pointer only moves forward).
        func cover(_ r: [DocPropRun], _ k: inout Int, _ cp: Int) -> DocPropRun? {
            while k < r.count, r[k].cpEnd <= cp { k += 1 }
            return k < r.count && r[k].cp <= cp ? r[k] : nil
        }
        func flush() {
            if !cur.isEmpty { runs += "<w:r>" + rpr + "<w:t xml:space=\"preserve\">" + esc(cur) + "</w:t></w:r>"; cur = [] }
        }
        func fld(_ type: String) -> String { "<w:r>" + rpr + "<w:fldChar w:fldCharType=\"\(type)\"/></w:r>" }
        func instrLive(_ f: Field) -> Bool {
            let n = String(decoding: f.instr, as: UTF16.self).uppercased().split(separator: " ").first.map(String.init) ?? ""
            return n == "PAGE" || n == "NUMPAGES"
        }
        func instrRun(_ f: Field) -> String { "<w:r>" + rpr + "<w:instrText xml:space=\"preserve\">" + esc(f.instr) + "</w:instrText></w:r>" }
        var cache: [UInt8] = [], cacheValid = false
        var sym: (String, String)?
        var curG: [UInt8] = []
        var front = "", back = ""     // shapes of the paragraph: behind the text come first, in front of it last (the order they are painted in)
        var rowCells: [String] = [], cellXml = ""
        var tblRows: [(g: [UInt8], cells: [String])] = []
        func tableXML(_ tblRows: [(g: [UInt8], cells: [String])]) -> String {
            guard !tblRows.isEmpty else { return "" }
            var recs = tblRows.compactMap { t in DocProps.row(t.g).map { (t, $0) } }
            // Rows that do not share their column edges are stated against the union of them (snapped within 3 twips), when they share the left edge.
            var union: [Int]? = nil
            if let f = recs.first?.1.edges.first, recs.allSatisfy({ abs(($0.1.edges.first ?? f) - f) <= 3 }) {
                var u: [Int] = []
                for e in recs.flatMap({ $0.1.edges }).sorted() where u.isEmpty || e - u[u.count - 1] > 3 { u.append(e) }
                if recs.contains(where: { $0.1.edges.count != u.count }) { union = u }
            }
            if let u = union { recs = tblRows.compactMap { t in DocProps.row(t.g, union: u).map { (t, $0) } } }
            guard let r0 = recs.first?.1 else { return "" }
            var tbl = "<w:tbl>" + r0.tblPr + "<w:tblGrid>" + r0.grid.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined() + "</w:tblGrid>"
            for (t, r) in recs {
                let all = t.cells.count == r.cells.count
                var n = 0
                tbl += "<w:tr>" + r.trPr
                for cl in r.cells {
                    let body = n < t.cells.count ? t.cells[n] : ""
                    if !cl.merged || all { n += 1 }
                    if cl.merged { continue }
                    tbl += "<w:tc>" + cl.pr + (body.isEmpty ? "<w:p/>" : body) + "</w:tc>"
                }
                tbl += "</w:tr>"
            }
            return tbl + "</w:tbl>"
        }
        func endTable() {
            guard !tblRows.isEmpty else { return }
            xml += tableXML(tblRows)
            tblRows = []
        }
        // Tables nested in a cell (itap 2 and up): one open level each; their cell and row marks are 0x0D paragraphs
        // flagged 0x244B / 0x244C. A level closes into the cell of the level below when a paragraph of that level (or lower) arrives.
        var nest: [(cells: [String], cell: String, rows: [(g: [UInt8], cells: [String])])] = []
        func closeNest(to depth: Int) {
            while nest.count > depth {
                let lv = nest.removeLast()
                let t = tableXML(lv.rows)
                if nest.isEmpty { cellXml += t } else { nest[nest.count - 1].cell += t }
            }
        }
        for (k, c) in t.enumerated() {
            let cp = ctx.base + k
            if !chp.isEmpty {
                let g = cover(chp, &ci, cp)?.grpprl ?? []
                curG = g
                if !cacheValid || g != cache { flush(); cache = g; cacheValid = true; rpr = DocProps.rPr(g, fonts: fonts, toggles: true); sym = DocProps.symbol(g, fonts: fonts) }
            }
            if let f = fields.last, f.inInstr, c != 0x14, c != 0x15, c != 0x13 {
                if c >= 0x20 { fields[fields.count - 1].instr.append(c) }
                continue
            }
            switch c {
            case 0x0D, 0x07:
                flush()
                let pr = cover(pap, &pi, cp)
                let tf = DocProps.tableFlags(pr?.grpprl ?? [])
                let itap = tf.inTable ? max(1, DocProps.sprms(pr?.grpprl ?? []).last(where: { $0.op == 0x6649 }).map { Int($0.u8) } ?? 1) : 0
                if itap >= 2 {
                    let innerCell = DocProps.sprms(pr?.grpprl ?? []).contains { $0.op == 0x244B && $0.u8 == 1 }
                    let innerRow = DocProps.sprms(pr?.grpprl ?? []).contains { $0.op == 0x244C && $0.u8 == 1 }
                    closeNest(to: itap - 1)
                    while nest.count < itap - 1 { nest.append(([], "", [])) }
                    if innerRow, c == 0x0D {
                        runs = ""
                        if let g = pr?.grpprl, DocProps.row(g) != nil { nest[nest.count - 1].rows.append((g, nest[nest.count - 1].cells)) }
                        nest[nest.count - 1].cells = []; nest[nest.count - 1].cell = ""
                        break
                    }
                    var pp = DocProps.pPr(pr?.grpprl ?? [], istd: pr?.istd ?? 0)
                    if !rpr.isEmpty { pp = pp.isEmpty ? "<w:pPr>" + rpr + "</w:pPr>" : String(pp.dropLast(8)) + rpr + "</w:pPr>" }
                    nest[nest.count - 1].cell += DocProps.settleToggles("<w:p>" + pp + back + runs + front + "</w:p>", styles: ctx.styles, istd: pr?.istd ?? 0)
                    runs = ""; back = ""; front = ""
                    if innerCell { nest[nest.count - 1].cells.append(nest[nest.count - 1].cell); nest[nest.count - 1].cell = "" }
                    break
                }
                closeNest(to: 0)
                if tf.inTable, tf.rowEnd, c == 0x07 {
                    // the mark that ends a table row carries the row's table properties
                    runs = ""
                    if let g = pr?.grpprl, DocProps.row(g) != nil { tblRows.append((g, rowCells)) }
                    rowCells = []; cellXml = ""
                    break
                }
                var pp = DocProps.pPr(pr?.grpprl ?? [], istd: pr?.istd ?? 0)
                // the paragraph mark's own character properties (they size an empty paragraph's line)
                if !rpr.isEmpty { pp = pp.isEmpty ? "<w:pPr>" + rpr + "</w:pPr>" : String(pp.dropLast(8)) + rpr + "</w:pPr>" }
                if let sp = ctx.sectEnds[cp] { pp = pp.isEmpty ? "<w:pPr>" + sp + "</w:pPr>" : String(pp.dropLast(8)) + sp + "</w:pPr>" }
                let para = DocProps.settleToggles("<w:p>" + pp + back + runs + front + "</w:p>", styles: ctx.styles, istd: pr?.istd ?? 0); runs = ""; back = ""; front = ""
                if tf.inTable {
                    cellXml += para
                    if c == 0x07 { rowCells.append(cellXml); cellXml = "" }
                } else {
                    endTable()
                    xml += para
                }
            case 0x0B: flush(); runs += "<w:r><w:br/></w:r>"
            case 0x0C:
                flush()
                if let sp = ctx.sectEnds[cp] { xml += "<w:p><w:pPr>" + sp + "</w:pPr>" + runs + "</w:p>"; runs = "" }
                else { runs += "<w:r><w:br w:type=\"page\"/></w:r>" }
            case 0x09: flush(); runs += "<w:r><w:tab/></w:r>"
            case 0x1E: cur.append(0x2011)
            case 0x1F: break
            case 0x02:
                flush()
                if !ctx.noteKind.isEmpty, k == 0 { runs += "<w:r>" + rpr + "<w:\(ctx.noteKind)Ref/></w:r>" }
                else if let id = ctx.footnotes[cp] { runs += "<w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:footnoteReference w:id=\"\(id)\"/></w:r>" }
                else if let id = ctx.endnotes[cp] { runs += "<w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:endnoteReference w:id=\"\(id)\"/></w:r>" }
            case 0x08:
                if let x = ctx.shapes[cp] { if x.behind { back += x.xml } else { front += x.xml } }
            case 0x01:
                if let f = ctx.picture, let o = DocProps.sprms(curG).last(where: { $0.op == 0x6A03 }), let x = f(OfficeArt.u32(o.operand, 0)) { flush(); runs += x }
            case 0x05:
                if let id = ctx.comments[cp] { flush(); runs += "<w:r><w:commentReference w:id=\"\(id)\"/></w:r>" }
            case 0x13: fields.append(Field())
            case 0x14:
                if !fields.isEmpty {
                    fields[fields.count - 1].inInstr = false
                    if instrLive(fields[fields.count - 1]) {
                        fields[fields.count - 1].live = true
                        flush(); runs += fld("begin") + instrRun(fields[fields.count - 1]) + fld("separate")
                    }
                }
            case 0x15:
                if let f = fields.popLast() {
                    flush()
                    if f.live { runs += fld("end") }
                    else if f.inInstr, instrLive(f) { runs += fld("begin") + instrRun(f) + fld("end") }
                }
            default:
                if c >= 0x20 {
                    if let sy = sym, c == 0x28 { flush(); runs += "<w:r>" + rpr + "<w:sym w:font=\"\(sy.0)\" w:char=\"\(sy.1)\"/></w:r>" }
                    else { cur.append(c) }
                }
            }
        }
        flush()
        closeNest(to: 0)
        if !tblRows.isEmpty { endTable(); xml += "<w:p/>" }
        if !runs.isEmpty || !back.isEmpty || !front.isEmpty { xml += "<w:p>" + back + runs + front + "</w:p>" }
        return xml
    }

    /// The .docx parts of a binary Word document, or nil when it is not one this reader takes
    /// (not Word 97 or later, or encrypted).
    static func parts(_ cf: CompoundFile) -> [ZipEntry]? {
        guard let w = cf.stream("WordDocument"), let fib = DocFib(w), fib.nFib >= 193, !fib.encrypted else { return nil }
        guard let tbl = cf.stream(fib.tableStream), let clxRange = fib.range(DocFib.fcClx),
              clxRange.fc >= 0, clxRange.fc + clxRange.lcb <= tbl.count else { return nil }
        let pcs = pieces(clx: Array(tbl[clxRange.fc ..< clxRange.fc + clxRange.lcb]))
        let chp = fib.range(DocFib.fcPlcfBteChpx).map { DocProps.runs(w: w, t: tbl, at: $0.fc, count: $0.lcb, pieces: pcs, paragraph: false) } ?? []
        let pap = fib.range(DocFib.fcPlcfBtePapx).map { DocProps.runs(w: w, t: tbl, at: $0.fc, count: $0.lcb, pieces: pcs, paragraph: true) } ?? []
        let fonts = fib.range(DocFib.fcSttbfFfn).map { DocProps.fonts(tbl, at: $0.fc, count: $0.lcb) } ?? []
        let st = fib.range(DocFib.fcStshf).map { DocProps.styles(tbl, at: $0.fc, count: $0.lcb, fonts: fonts) }
        let hddEnd = fib.ccpText + fib.ccpFtn + fib.ccpHdd
        let all = text(w, pieces: pcs, count: hddEnd + fib.ccpAtn + fib.ccpEdn + fib.ccpTxbx + fib.ccpHdrTxbx)
        func slice(_ a: Int, _ b: Int) -> [UInt16] { (a >= 0 && b <= all.count && a < b) ? Array(all[a ..< b]) : [] }
        func story(_ a: Int, _ b: Int, _ ctx: StoryContext = StoryContext()) -> String {
            var c = ctx; c.base = a; c.styles = st?.xml ?? ""
            return paragraphs(slice(a, b), chp: chp, pap: pap, fonts: fonts, ctx: c)
        }
        // A header or footer story's last paragraph mark closes the story: it takes no line of its own.
        var extra: [ZipEntry] = [], rels = "", types = ""
        func e(_ name: String, _ s: String) -> ZipEntry { ZipEntry(name: name, data: Data(s.utf8)) }
        let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\" xmlns:wpg=\"http://schemas.microsoft.com/office/word/2010/wordprocessingGroup\" xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\""
        let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        let relBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
        let ctBase = "application/vnd.openxmlformats-officedocument.wordprocessingml."
        // The shapes and pictures of a header or footer story [a, b): set once the drawings are read (below).
        var headerDrawings: (Int, Int) -> (shapes: [Int: (xml: String, behind: Bool)], rels: () -> String, picture: (Int) -> String?) = { _, _ in ([:], { "" }, { _ in nil }) }
        // Headers and footers: six stories per section after the six note separators.
        let hdd = fib.range(DocFib.fcPlcfHdd).flatMap { DocProps.plex(tbl, at: $0.fc, count: $0.lcb, size: 0) }
        func refs(section k: Int) -> String {
            guard let hdd else { return "" }
            var x = ""
            // even header, odd header, even footer, odd footer, first header, first footer
            let kinds = [("header", "even"), ("header", "default"), ("footer", "even"), ("footer", "default"), ("header", "first"), ("footer", "first")]
            for (j, (tag, type)) in kinds.enumerated() {
                let n = 6 + 6 * k + j
                guard n + 1 < hdd.cps.count else { continue }
                let a = fib.ccpText + fib.ccpFtn + hdd.cps[n], b = fib.ccpText + fib.ccpFtn + hdd.cps[n + 1]
                guard b > a, b <= hddEnd else { continue }
                let id = "rIdH\(k)_\(j)"
                let part = "\(tag)\(k)_\(j).xml"
                let hd = headerDrawings(a, b)
                var hc = StoryContext(); hc.shapes = hd.shapes; hc.picture = hd.picture
                extra.append(e("word/" + part, head + "<w:\(tag == "header" ? "hdr" : "ftr") \(ns)>" + story(a, storyEnd(a, b), hc) + "</w:\(tag == "header" ? "hdr" : "ftr")>"))
                let partRels = hd.rels()   // after the story: its inline pictures add theirs while it is read
                if !partRels.isEmpty { extra.append(e("word/_rels/" + part + ".rels", head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + partRels + "</Relationships>")) }
                rels += "<Relationship Id=\"\(id)\" Type=\"\(relBase)\(tag)\" Target=\"\(part)\"/>"
                types += "<Override PartName=\"/word/\(part)\" ContentType=\"\(ctBase)\(tag).xml\"/>"
                x += "<w:\(tag)Reference w:type=\"\(type)\" r:id=\"\(id)\"/>"
            }
            return x
        }
        // Notes: the reference marks in the text, and each note's own text.
        func notes(_ refIdx: Int, _ txtIdx: Int, storyStart: Int, kind: String) -> [Int: Int] {
            guard let rr = fib.range(refIdx), let tr = fib.range(txtIdx),
                  let rf = DocProps.plex(tbl, at: rr.fc, count: rr.lcb, size: 2), let tx = DocProps.plex(tbl, at: tr.fc, count: tr.lcb, size: 0) else { return [:] }
            var map: [Int: Int] = [:], body = ""
            for k in 0 ..< min(rf.cps.count - 1, tx.cps.count - 1) {
                let id = k + 2
                map[rf.cps[k]] = id
                var c = StoryContext(); c.noteKind = kind
                body += "<w:\(kind) w:id=\"\(id)\">" + story(storyStart + tx.cps[k], storyStart + tx.cps[k + 1], c) + "</w:\(kind)>"
            }
            let sep = "<w:\(kind) w:type=\"separator\" w:id=\"0\"><w:p><w:r><w:separator/></w:r></w:p></w:\(kind)><w:\(kind) w:type=\"continuationSeparator\" w:id=\"1\"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:\(kind)>"
            let part = kind + "s.xml"
            extra.append(e("word/" + part, head + "<w:\(kind)s \(ns)>" + sep + body + "</w:\(kind)s>"))
            rels += "<Relationship Id=\"rId_\(kind)\" Type=\"\(relBase)\(kind)s\" Target=\"\(part)\"/>"
            types += "<Override PartName=\"/word/\(part)\" ContentType=\"\(ctBase)\(kind)s+xml\"/>"
            return map
        }
        let fnMap = notes(2, 3, storyStart: fib.ccpText, kind: "footnote")
        let enMap = notes(46, 47, storyStart: hddEnd + fib.ccpAtn, kind: "endnote")
        // Comments: the reference marks in the text, each comment's text and its author and initials.
        var cmMap: [Int: Int] = [:]
        if fib.ccpAtn > 0, let rr = fib.range(4), let tr = fib.range(5),
           let rf = DocProps.plex(tbl, at: rr.fc, count: rr.lcb, size: 30), let tx = DocProps.plex(tbl, at: tr.fc, count: tr.lcb, size: 0) {
            var owners: [String] = []
            if let og = fib.range(35) {
                var q = og.fc
                while q + 2 <= min(og.fc + og.lcb, tbl.count) {
                    let n = OfficeArt.u16(tbl, q); q += 2
                    guard q + 2 * n <= tbl.count else { break }
                    owners.append(esc((0 ..< n).map { OfficeArt.u16(tbl, q + 2 * $0) }.map { UInt16($0) }))
                    q += 2 * n
                }
            }
            var body = ""
            for k in 0 ..< min(rf.cps.count - 1, tx.cps.count - 1) {
                cmMap[rf.cps[k]] = k
                let a = rf.at + 30 * k
                let ni = min(OfficeArt.u16(tbl, a), 9)
                let initials = esc((0 ..< ni).map { UInt16(OfficeArt.u16(tbl, a + 2 + 2 * $0)) })
                let ib = OfficeArt.u16(tbl, a + 20)
                let author = ib < owners.count ? owners[ib] : ""
                body += "<w:comment w:id=\"\(k)\" w:author=\"\(author)\" w:initials=\"\(initials)\">" + story(hddEnd + tx.cps[k], hddEnd + tx.cps[k + 1]) + "</w:comment>"
            }
            if !body.isEmpty {
                extra.append(e("word/comments.xml", head + "<w:comments \(ns)>" + body + "</w:comments>"))
                rels += "<Relationship Id=\"rId_cm\" Type=\"\(relBase)comments\" Target=\"comments.xml\"/>"
                types += "<Override PartName=\"/word/comments.xml\" ContentType=\"\(ctBase)comments+xml\"/>"
            }
        }
        // Drawings: pictures in the line (Data stream), and shapes the text anchors (PlcSpaMom), with their text boxes.
        var media: [ZipEntry] = []
        var imageTypes = Set<String>()
        func addMedia(_ b: ArtBlip) -> Int {
            let n = media.count + 1
            media.append(ZipEntry(name: "word/media/image\(n).\(b.ext)", data: Data(b.data)))
            imageTypes.insert(b.ext)
            return n
        }
        func imageRel(_ n: Int, _ ext: String) -> String { "<Relationship Id=\"rIdImg\(n)\" Type=\"\(relBase)image\" Target=\"media/image\(n).\(ext)\"/>" }
        func addImage(_ b: ArtBlip) -> String {
            let n = addMedia(b)
            rels += imageRel(n, b.ext)
            return "rIdImg\(n)"
        }
        let dataStream = cf.stream("Data") ?? []
        var inlineCache: [Int: String?] = [:]
        let picture: (Int) -> String? = { off in
            if let c = inlineCache[off] { return c }
            let r = DocArt.inline(data: dataStream, at: off, rid: addImage)
            inlineCache[off] = r
            return r
        }
        // The drawing runs of the shapes in `spas`, by the character each is anchored at (`shift` moves a story's own
        // positions into the document's), with the pictures added through `add` and text box text from `boxes`.
        func shapeRuns(_ spas: [DocArt.Spa], shift: Int, art: DocArt.Art, boxes: (cps: [Int], at: Int)?, boxStart: Int, add: (ArtBlip) -> String, pic: @escaping (Int) -> String?) -> [Int: (xml: String, behind: Bool)] {
            var out: [Int: (xml: String, behind: Bool)] = [:]
            for (k, sp) in spas.enumerated() {
                let shape = art.shapes[sp.spid]
                if let shape, shape.flags & 1 != 0, shape.groupRect != nil {
                    // a group: its members are drawn inside it, in its own coordinate space
                    let cx = DocArt.emu(max(0, sp.right - sp.left)), cy = DocArt.emu(max(0, sp.bottom - sp.top))
                    let g = DocArt.group(shape, art: art, cx: cx, cy: cy) { m in
                        var rid: String?
                        if m.pib > 0, m.pib <= art.blips.count, let b = art.blips[m.pib - 1] { rid = add(b) }
                        var content: String?
                        if rid == nil, let tx = m.props[0x80], let boxes, (tx >> 16) - 1 >= 0, (tx >> 16) - 1 < boxes.cps.count - 1 {
                            var c = StoryContext(); c.picture = pic
                            content = story(boxStart + boxes.cps[(tx >> 16) - 1], boxStart + boxes.cps[(tx >> 16)], c)
                        }
                        return (rid, content)
                    }
                    if let g { out[shift + sp.cp] = (DocArt.floating(sp, shape: shape, rid: nil, content: nil, order: k, group: g), sp.behind) }
                    continue
                }
                var rid: String?
                if let pib = shape?.pib, pib > 0, pib <= art.blips.count, let b = art.blips[pib - 1] { rid = add(b) }
                var content: String?
                if rid == nil, let shape, let tx = shape.props[0x80], let boxes {
                    let i = (tx >> 16) - 1
                    if i >= 0, i < boxes.cps.count - 1 {
                        var c = StoryContext(); c.picture = pic
                        content = story(boxStart + boxes.cps[i], boxStart + boxes.cps[i + 1], c)
                    }
                }
                if rid == nil, content == nil, !(shape.map({ DocArt.drawable($0) }) ?? false) { continue }
                out[shift + sp.cp] = (DocArt.floating(sp, shape: shape, rid: rid, content: content, order: k), sp.behind)
            }
            return out
        }
        // A header or footer with no drawn shapes can still hold inline pictures (a letterhead logo): they
        // read from the Data stream and get the part's own relationships.
        headerDrawings = { _, _ in
            var hrels = ""
            func add(_ bl: ArtBlip) -> String { let n = addMedia(bl); hrels += imageRel(n, bl.ext); return "rIdImg\(n)" }
            let pic: (Int) -> String? = { off in DocArt.inline(data: dataStream, at: off, rid: { bl in add(bl) }) }
            return ([:], { hrels }, pic)
        }
        var mainShapes: [Int: (xml: String, behind: Bool)] = [:]
        if let dg = fib.range(50) {
            let art = DocArt.art(t: tbl, w: w, at: dg.fc, count: dg.lcb)
            let boxStart = hddEnd + fib.ccpAtn + fib.ccpEdn
            if let sr = fib.range(40) {
                let boxes = fib.range(56).flatMap { DocProps.plex(tbl, at: $0.fc, count: $0.lcb, size: 22) }
                mainShapes = shapeRuns(DocArt.spas(tbl, at: sr.fc, count: sr.lcb), shift: 0, art: art, boxes: boxes, boxStart: boxStart, add: addImage, pic: picture)
            }
            if let hr = fib.range(41) {
                let hspas = DocArt.spas(tbl, at: hr.fc, count: hr.lcb)
                let hboxes = fib.range(58).flatMap { DocProps.plex(tbl, at: $0.fc, count: $0.lcb, size: 22) }
                let hStart = fib.ccpText + fib.ccpFtn
                headerDrawings = { a, b in
                    // each header part has its own relationships, so its pictures are added to its own list
                    var hrels = ""
                    func add(_ bl: ArtBlip) -> String { let n = addMedia(bl); hrels += imageRel(n, bl.ext); return "rIdImg\(n)" }
                    let mine = hspas.filter { hStart + $0.cp >= a && hStart + $0.cp < b }
                    let pic: (Int) -> String? = { off in DocArt.inline(data: dataStream, at: off, rid: { bl in add(bl) }) }
                    let runs = shapeRuns(mine, shift: hStart, art: art, boxes: hboxes, boxStart: boxStart + fib.ccpTxbx, add: add, pic: pic)
                    return (runs, { hrels }, pic)
                }
            }
        }
        // Sections: each ends at a section mark; the last one's properties close the body.
        var ends: [Int: String] = [:]
        var last = "", lastEnd = fib.ccpText
        if let sed = fib.range(DocFib.fcPlcfSed).flatMap({ DocProps.plex(tbl, at: $0.fc, count: $0.lcb, size: 12) }), sed.cps.count > 1 {
            for k in 0 ..< sed.cps.count - 1 {
                let fc = OfficeArt.u32(tbl, sed.at + 12 * k + 2)
                var g: [UInt8] = []
                if fc != 0xFFFF_FFFF, fc + 2 <= w.count { let n = OfficeArt.u16(w, fc); if fc + 2 + n <= w.count { g = Array(w[fc + 2 ..< fc + 2 + n]) } }
                let sp = DocProps.sectPr(g, refs: refs(section: k))
                let end = min(sed.cps[k + 1], fib.ccpText)
                if k == sed.cps.count - 2 { last = sp; lastEnd = end } else if end > 0 { ends[end - 1] = sp }
            }
        }
        if last.isEmpty { last = DocProps.sectPr([], refs: "") }
        var ctx = StoryContext(); ctx.sectEnds = ends; ctx.footnotes = fnMap; ctx.endnotes = enMap; ctx.comments = cmMap; ctx.shapes = mainShapes; ctx.picture = picture
        let body = story(0, fib.ccpText, ctx)
        for x in imageTypes.sorted() {
            let ct = ["png": "image/png", "jpeg": "image/jpeg", "bmp": "image/bmp", "emf": "image/x-emf", "wmf": "image/x-wmf", "tiff": "image/tiff", "pict": "image/pict"][x] ?? "application/octet-stream"
            types += "<Default Extension=\"\(x)\" ContentType=\"\(ct)\"/>"
        }
        _ = lastEnd
        let df = st.flatMap { $0.font < fonts.count && !fonts[$0.font].isEmpty ? fonts[$0.font] : nil } ?? "Times New Roman"
        let dfe = st.flatMap { $0.fontFE < fonts.count && !fonts[$0.fontFE].isEmpty ? fonts[$0.fontFE] : nil } ?? df
        let dflt = "<w:rFonts w:ascii=\"\(df)\" w:hAnsi=\"\(df)\" w:eastAsia=\"\(dfe)\" w:cs=\"\(df)\"/>"
        // Odd and even pages have their own headers when the document properties say so (the first flag of the DOP).
        let facing = fib.range(31).map { $0.fc < tbl.count && tbl[$0.fc] & 1 != 0 } ?? false
        // (The DOP's default tab stop, dxaTab at byte 10, in twips: Word's tabs run on it; es-7289450bf2's 708 puts four tabs 2.4 pt short of 720's.)
        let tabStop: Int? = fib.range(31).flatMap { $0.fc + 12 <= tbl.count && $0.lcb >= 12 ? Int(tbl[$0.fc + 10]) | Int(tbl[$0.fc + 11]) << 8 : nil }.flatMap { $0 > 0 && $0 != 720 ? $0 : nil }
        // A binary file lays out as Word's earlier modes do: the mark of a paragraph that ends in a page break
        // stands on the page the break opens (the flag a 2013-era docx carries for the same behaviour).
        var settings: [ZipEntry] = []
        settings = [e("word/settings.xml", head + settingsXML(facing: facing, tabStop: tabStop))]
        rels += "<Relationship Id=\"rIdSet\" Type=\"\(relBase)settings\" Target=\"settings.xml\"/>"
        types += "<Override PartName=\"/word/settings.xml\" ContentType=\"\(ctBase)settings+xml\"/>"
        if let ls = fib.range(73), let nx = DocProps.numbering(tbl, lst: ls, lfo: fib.range(74), fonts: fonts) {
            extra.append(e("word/numbering.xml", head + "<w:numbering \(ns)>" + nx + "</w:numbering>"))
            rels += "<Relationship Id=\"rIdNum\" Type=\"\(relBase)numbering\" Target=\"numbering.xml\"/>"
            types += "<Override PartName=\"/word/numbering.xml\" ContentType=\"\(ctBase)numbering+xml\"/>"
        }
        let styleXml = (st?.xml.isEmpty ?? true) ? "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"S0\"><w:name w:val=\"Normal\"/></w:style>" : st!.xml
        return [
            e("[Content_Types].xml", head + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"\(ctBase)document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"\(ctBase)styles+xml\"/>" + types + "</Types>"),
            e("_rels/.rels", head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(relBase)officeDocument\" Target=\"word/document.xml\"/></Relationships>"),
            e("word/_rels/document.xml.rels", head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(relBase)styles\" Target=\"styles.xml\"/>" + rels + "</Relationships>"),
            e("word/styles.xml", head + "<w:styles \(ns)><w:docDefaults><w:rPrDefault><w:rPr>\(dflt)<w:sz w:val=\"20\"/><w:szCs w:val=\"20\"/></w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults>" + styleXml + "</w:styles>"),
            e("word/document.xml", head + "<w:document \(ns)><w:body>" + body + last + "</w:body></w:document>"),
        ] + extra + settings + media
    }

    /// A binary Word document as a .docx package, or nil.
    static func docx(_ data: Data) -> Data? {
        guard let cf = try? CompoundFile([UInt8](data)), let ps = parts(cf) else { return nil }
        return try? Zip.write(ps)
    }
}
