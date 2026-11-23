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

    /// The paragraphs of a story as `w:p` elements: a paragraph mark (0D, or 07 for a cell or row end)
    /// ends one; a field's instruction (between 13 and 14) is dropped and its result kept.
    static func paragraphs(_ t: [UInt16]) -> String {
        var xml = ""
        var runs = "", cur: [UInt16] = []
        var fieldDepth = 0, hiding: [Bool] = []
        func flush() {
            if !cur.isEmpty { runs += "<w:r><w:t xml:space=\"preserve\">" + esc(cur) + "</w:t></w:r>"; cur = [] }
        }
        for c in t {
            if let h = hiding.last, h, c != 0x14, c != 0x15, c != 0x13 { continue }
            switch c {
            case 0x0D, 0x07: flush(); xml += "<w:p>" + runs + "</w:p>"; runs = ""
            case 0x0B: flush(); runs += "<w:r><w:br/></w:r>"
            case 0x0C: flush(); runs += "<w:r><w:br w:type=\"page\"/></w:r>"
            case 0x09: flush(); runs += "<w:r><w:tab/></w:r>"
            case 0x1E: cur.append(0x2011)
            case 0x1F: break
            case 0x13: fieldDepth += 1; hiding.append(true)
            case 0x14: if !hiding.isEmpty { hiding[hiding.count - 1] = false }
            case 0x15: if !hiding.isEmpty { hiding.removeLast(); fieldDepth -= 1 }
            default: if c >= 0x20 { cur.append(c) }
            }
        }
        flush()
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
        let body = paragraphs(text(w, pieces: pcs, count: fib.ccpText))
        func e(_ name: String, _ s: String) -> ZipEntry { ZipEntry(name: name, data: Data(s.utf8)) }
        let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
        return [
            e("[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/></Types>"),
            e("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"),
            e("word/_rels/document.xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"),
            e("word/styles.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:styles \(ns)><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\" w:eastAsia=\"Times New Roman\" w:cs=\"Times New Roman\"/><w:sz w:val=\"20\"/><w:szCs w:val=\"20\"/></w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style></w:styles>"),
            e("word/document.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:document \(ns)><w:body>" + body + "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1800\" w:bottom=\"1440\" w:left=\"1800\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>"),
        ]
    }

    /// A binary Word document as a .docx package, or nil.
    static func docx(_ data: Data) -> Data? {
        guard let cf = try? CompoundFile([UInt8](data)), let ps = parts(cf) else { return nil }
        return try? Zip.write(ps)
    }
}
