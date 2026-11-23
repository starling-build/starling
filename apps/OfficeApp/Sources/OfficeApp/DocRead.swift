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
}

enum DocRead {
    /// Windows-1252 for the bytes of a compressed piece (0x80-0x9F differ from Latin-1).
    private static let cp1252: [UInt16] = [
        0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
        0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
    ]

    /// The piece table out of the CLX (a run of grpprl "Prc"s, then the "Pcdt" holding the PlcPcd).
    static func pieces(clx: [UInt8]) -> [DocPiece] {
        var p = 0
        while p < clx.count, clx[p] == 0x01 { p += 3 + OfficeArt.u16(clx, p + 1) }
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
            out.append(DocPiece(cp: cp, cpEnd: end, fc: compressed ? fc / 2 : fc, compressed: compressed))
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
        var endnotes: [Int: Int] = [:]
        var noteKind = ""            // "footnote" or "endnote" inside a note's own text
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
        var tbl = "", rowCells: [String] = [], cellXml = ""
        func endTable() { if !tbl.isEmpty { xml += tbl + "</w:tbl>"; tbl = "" } }
        for (k, c) in t.enumerated() {
            let cp = ctx.base + k
            if !chp.isEmpty {
                let g = cover(chp, &ci, cp)?.grpprl ?? []
                if !cacheValid || g != cache { flush(); cache = g; cacheValid = true; rpr = DocProps.rPr(g, fonts: fonts) }
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
                if tf.inTable, tf.rowEnd, c == 0x07 {
                    // the mark that ends a table row carries the row's table properties
                    runs = ""
                    if let r = DocProps.row(pr?.grpprl ?? []) {
                        if tbl.isEmpty { tbl = "<w:tbl>" + r.tblPr + "<w:tblGrid>" + r.grid.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined() + "</w:tblGrid>" }
                        let all = rowCells.count == r.cells.count
                        var n = 0
                        tbl += "<w:tr>" + r.trPr
                        for cl in r.cells {
                            let body = n < rowCells.count ? rowCells[n] : ""
                            if !cl.merged || all { n += 1 }
                            if cl.merged { continue }
                            tbl += "<w:tc>" + cl.pr + (body.isEmpty ? "<w:p/>" : body) + "</w:tc>"
                        }
                        tbl += "</w:tr>"
                    }
                    rowCells = []; cellXml = ""
                    break
                }
                var pp = DocProps.pPr(pr?.grpprl ?? [], istd: pr?.istd ?? 0)
                if let sp = ctx.sectEnds[cp] { pp = pp.isEmpty ? "<w:pPr>" + sp + "</w:pPr>" : String(pp.dropLast(8)) + sp + "</w:pPr>" }
                let para = "<w:p>" + pp + runs + "</w:p>"; runs = ""
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
            default: if c >= 0x20 { cur.append(c) }
            }
        }
        flush()
        if !tbl.isEmpty { endTable(); xml += "<w:p/>" }
        if !runs.isEmpty { xml += "<w:p>" + runs + "</w:p>" }
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
        let all = text(w, pieces: pcs, count: hddEnd + fib.ccpAtn + fib.ccpEdn)
        func slice(_ a: Int, _ b: Int) -> [UInt16] { (a >= 0 && b <= all.count && a < b) ? Array(all[a ..< b]) : [] }
        func story(_ a: Int, _ b: Int, _ ctx: StoryContext = StoryContext()) -> String {
            var c = ctx; c.base = a
            return paragraphs(slice(a, b), chp: chp, pap: pap, fonts: fonts, ctx: c)
        }
        var extra: [ZipEntry] = [], rels = "", types = ""
        func e(_ name: String, _ s: String) -> ZipEntry { ZipEntry(name: name, data: Data(s.utf8)) }
        let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
        let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        let relBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
        let ctBase = "application/vnd.openxmlformats-officedocument.wordprocessingml."
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
                extra.append(e("word/" + part, head + "<w:\(tag == "header" ? "hdr" : "ftr") \(ns)>" + story(a, b) + "</w:\(tag == "header" ? "hdr" : "ftr")>"))
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
        var ctx = StoryContext(); ctx.sectEnds = ends; ctx.footnotes = fnMap; ctx.endnotes = enMap
        let body = story(0, fib.ccpText, ctx)
        _ = lastEnd
        let df = st.flatMap { $0.font < fonts.count && !fonts[$0.font].isEmpty ? fonts[$0.font] : nil } ?? "Times New Roman"
        let dflt = "<w:rFonts w:ascii=\"\(df)\" w:hAnsi=\"\(df)\" w:eastAsia=\"\(df)\" w:cs=\"\(df)\"/>"
        // Odd and even pages have their own headers when the document properties say so (the first flag of the DOP).
        let facing = fib.range(31).map { $0.fc < tbl.count && tbl[$0.fc] & 1 != 0 } ?? false
        var settings: [ZipEntry] = []
        if facing {
            settings = [e("word/settings.xml", head + "<w:settings \(ns)><w:evenAndOddHeaders/></w:settings>")]
            rels += "<Relationship Id=\"rIdSet\" Type=\"\(relBase)settings\" Target=\"settings.xml\"/>"
            types += "<Override PartName=\"/word/settings.xml\" ContentType=\"\(ctBase)settings+xml\"/>"
        }
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
        ] + extra + settings
    }

    /// A binary Word document as a .docx package, or nil.
    static func docx(_ data: Data) -> Data? {
        guard let cf = try? CompoundFile([UInt8](data)), let ps = parts(cf) else { return nil }
        return try? Zip.write(ps)
    }
}
