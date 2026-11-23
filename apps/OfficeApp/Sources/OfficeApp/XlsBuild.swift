// .xls M1: BIFF records to SpreadsheetML parts (values, number formats, sizes,
// merges), which the existing xlsx reader then reads. Every read is
// bounds-checked; damaged records are skipped, never trapped on.
//
// Shared code (also built for the web).

import Foundation

/// A read position in a BIFF record body, aware of CONTINUE boundaries.
struct BiffCursor {
    let r: BiffRecord
    var pos = 0
    init(_ r: BiffRecord, at pos: Int = 0) { self.r = r; self.pos = pos }
    var atEnd: Bool { pos >= r.body.count }
    mutating func u8() -> Int { defer { pos += 1 }; return pos >= 0 && pos < r.body.count ? Int(r.body[pos]) : 0 }
    mutating func u16() -> Int { let a = u8(); return a | u8() << 8 }
    mutating func u32() -> UInt32 { let a = UInt32(u16()); return a | UInt32(u16()) << 16 }
    mutating func skip(_ n: Int) { pos += max(0, n) }

    /// `cch` characters of a BIFF8 string whose flag byte was just read. At a
    /// CONTINUE boundary inside the characters a fresh flag byte starts the
    /// next segment, and it may change between 1 and 2 bytes per character.
    mutating func chars(_ cch: Int, wide w: Bool) -> String {
        var wide = w
        var units: [UInt16] = []
        var left = cch
        while left > 0, pos < r.body.count {
            if pos > 0, r.segments.contains(pos) { wide = u8() & 1 == 1; if pos >= r.body.count { break } }
            if wide { units.append(UInt16(u16())) } else { units.append(UInt16(u8())) }
            left -= 1
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// A string with a 16-bit length (SST entries, FORMAT, LABEL); skips run
    /// and phonetic data that follows the characters.
    mutating func unicodeString16() -> String {
        let cch = u16(), flags = u8()
        let runs = flags & 8 != 0 ? u16() : 0
        let ext = flags & 4 != 0 ? Int(u32()) : 0
        let s = chars(cch, wide: flags & 1 == 1)
        skip(runs * 4 + ext)
        return s
    }
}

enum XlsBuild {
    static func esc(_ s: String) -> String {
        var o = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "&": o += "&amp;"
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "\"": o += "&quot;"
            default:
                // XML 1.0 has no room for most control characters.
                if ch.value < 32 && ch != "\t" && ch != "\n" && ch != "\r" { continue }
                o.unicodeScalars.append(ch)
            }
        }
        return o
    }

    static func colName(_ c: Int) -> String {
        var n = c + 1
        var s = ""
        while n > 0 { let m = (n - 1) % 26; s = String(UnicodeScalar(UInt8(65 + m))) + s; n = (n - 1) / 26 }
        return s
    }

    static func rk(_ v: UInt32) -> Double {
        var d: Double
        if v & 2 != 0 { d = Double(Int32(bitPattern: v) >> 2) } else { d = Double(bitPattern: UInt64(v & 0xFFFF_FFFC) << 32) }
        if v & 1 != 0 { d /= 100 }
        return d
    }

    static func errorText(_ code: Int) -> String {
        switch code {
        case 0x00: return "#NULL!"
        case 0x07: return "#DIV/0!"
        case 0x0F: return "#VALUE!"
        case 0x17: return "#REF!"
        case 0x1D: return "#NAME?"
        case 0x24: return "#NUM!"
        case 0x2A: return "#N/A"
        default: return "#VALUE!"
        }
    }

    static func num(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return "\(d)"
    }

    /// The parts of an equivalent .xlsx, or nil when the file is not BIFF8.
    static func parts(_ recs: [BiffRecord]) -> [ZipEntry]? {
        guard let first = recs.first, first.type == 0x809, first.body.count >= 2,
              Int(first.body[0]) | Int(first.body[1]) << 8 == 0x600 else { return nil }
        var date1904 = false
        var activeTab = 0
        var sst: [String] = []
        var formats: [(Int, String)] = []
        var xfFormat: [Int] = []
        var sheets: [Xls.SheetInfo] = []
        // Globals end at the first EOF.
        var i = 0
        var depth = 0
        while i < recs.count {
            let r = recs[i]
            var c = BiffCursor(r)
            if r.type == 0x809 { depth += 1 }
            if r.type == 0x0A { depth -= 1; if depth <= 0 { i += 1; break } }
            switch r.type {
            case 0x22: date1904 = c.u16() == 1
            case 0x3D where r.body.count >= 12: c.skip(10); activeTab = c.u16()
            case 0x41E: let id = c.u16(); formats.append((id, c.unicodeString16()))
            case 0xE0: c.skip(2); xfFormat.append(c.u16())
            case 0xFC:
                c.skip(8)
                while !c.atEnd { sst.append(c.unicodeString16()) }
            default: break
            }
            i += 1
        }
        sheets = Xls.sheets(recs)
        var out: [ZipEntry] = []
        func add(_ n: String, _ s: String) { out.append(ZipEntry(name: n, data: Data(s.utf8))) }

        let kept = sheets.enumerated().filter { $0.element.kind == 0 || $0.element.kind == 2 }
        var wb = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        // (activeTab counts every BOUNDSHEET; our parts drop the module sheets.)
        let active = kept.firstIndex(where: { $0.offset == activeTab }) ?? 0
        wb += "<workbookPr" + (date1904 ? " date1904=\"1\"" : "") + "/><bookViews><workbookView activeTab=\"\(active)\"/></bookViews><sheets>"
        var rels = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for (n, e) in kept.enumerated() {
            let state = e.element.hidden == 1 ? " state=\"hidden\"" : e.element.hidden == 2 ? " state=\"veryHidden\"" : ""
            wb += "<sheet name=\"\(esc(e.element.name))\" sheetId=\"\(n + 1)\"\(state) r:id=\"rId\(n + 1)\"/>"
            rels += "<Relationship Id=\"rId\(n + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(n + 1).xml\"/>"
        }
        wb += "</sheets></workbook>"
        rels += "</Relationships>"
        add("xl/workbook.xml", wb)
        add("xl/_rels/workbook.xml.rels", rels)

        var ss = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"\(sst.count)\" uniqueCount=\"\(sst.count)\">"
        for s in sst { ss += "<si><t xml:space=\"preserve\">\(esc(s))</t></si>" }
        add("xl/sharedStrings.xml", ss + "</sst>")

        var st = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        let custom = formats.filter { $0.0 >= 164 }
        if !custom.isEmpty {
            st += "<numFmts count=\"\(custom.count)\">" + custom.map { "<numFmt numFmtId=\"\($0.0)\" formatCode=\"\(esc($0.1))\"/>" }.joined() + "</numFmts>"
        }
        st += "<fonts count=\"1\"><font><sz val=\"10\"/><name val=\"Arial\"/></font></fonts>"
        st += "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>"
        st += "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
        st += "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        let xfs = xfFormat.isEmpty ? [0] : xfFormat
        st += "<cellXfs count=\"\(xfs.count)\">" + xfs.map { "<xf numFmtId=\"\($0)\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>" }.joined() + "</cellXfs>"
        add("xl/styles.xml", st + "</styleSheet>")

        for (n, e) in kept.enumerated() {
            let xml = sheetXML(recs, from: e.element.position, sst: sst, xfCount: xfs.count)
            add("xl/worksheets/sheet\(n + 1).xml", xml)
        }
        return out
    }

    private static func sheetXML(_ recs: [BiffRecord], from position: Int, sst: [String], xfCount: Int) -> String {
        guard var i = recs.firstIndex(where: { $0.offset == position && $0.type == 0x809 }) else { return emptySheet }
        var cells: [Int: [Int: String]] = [:]
        var rows: [Int: String] = [:]
        var cols: [String] = []
        var merges: [String] = []
        var defColWidth: Int? = nil, stdWidth: Int? = nil
        var defRowHeight: (Int, Bool)? = nil
        var pendingFormula: (Int, Int, Int)? = nil
        var depth = 0
        func style(_ x: Int) -> String { x > 0 && x < xfCount ? " s=\"\(x)\"" : "" }
        func put(_ r: Int, _ c: Int, _ xml: String) { if r < 1_048_576, c < 16384 { cells[r, default: [:]][c] = xml } }
        func ref(_ r: Int, _ c: Int) -> String { colName(c) + String(r + 1) }
        while i < recs.count {
            let rec = recs[i]
            i += 1
            if rec.type == 0x809 { depth += 1; if depth > 1 { continue } }
            if rec.type == 0x0A { depth -= 1; if depth <= 0 { break } }
            if depth != 1 { continue }
            var c = BiffCursor(rec)
            switch rec.type {
            case 0xFD where rec.body.count >= 10:
                let r = c.u16(), col = c.u16(), x = c.u16(), k = Int(c.u32())
                if k < sst.count { put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"s\"><v>\(k)</v></c>") }
            case 0x203 where rec.body.count >= 14:
                let r = c.u16(), col = c.u16(), x = c.u16()
                let d = Double(bitPattern: UInt64(c.u32()) | UInt64(c.u32()) << 32)
                if d.isFinite { put(r, col, "<c r=\"\(ref(r, col))\"\(style(x))><v>\(num(d))</v></c>") }
            case 0x27E where rec.body.count >= 10:
                let r = c.u16(), col = c.u16(), x = c.u16()
                put(r, col, "<c r=\"\(ref(r, col))\"\(style(x))><v>\(num(rk(c.u32())))</v></c>")
            case 0xBD where rec.body.count >= 6:
                let r = c.u16(), first = c.u16()
                let last = Int(rec.body[rec.body.count - 2]) | Int(rec.body[rec.body.count - 1]) << 8
                var col = first
                while col <= last, c.pos + 6 <= rec.body.count - 2 {
                    let x = c.u16()
                    put(r, col, "<c r=\"\(ref(r, col))\"\(style(x))><v>\(num(rk(c.u32())))</v></c>")
                    col += 1
                }
            case 0x201 where rec.body.count >= 6:
                let r = c.u16(), col = c.u16(), x = c.u16()
                if x > 0 { put(r, col, "<c r=\"\(ref(r, col))\"\(style(x))/>") }
            case 0xBE where rec.body.count >= 6:
                let r = c.u16(), first = c.u16()
                let last = Int(rec.body[rec.body.count - 2]) | Int(rec.body[rec.body.count - 1]) << 8
                var col = first
                while col <= last, c.pos + 2 <= rec.body.count - 2 {
                    let x = c.u16()
                    if x > 0 { put(r, col, "<c r=\"\(ref(r, col))\"\(style(x))/>") }
                    col += 1
                }
            case 0x205 where rec.body.count >= 8:
                let r = c.u16(), col = c.u16(), x = c.u16(), v = c.u8(), isErr = c.u8()
                if isErr == 1 { put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"e\"><v>\(errorText(v))</v></c>") }
                else { put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"b\"><v>\(v == 0 ? 0 : 1)</v></c>") }
            case 0x204 where rec.body.count >= 8:
                let r = c.u16(), col = c.u16(), x = c.u16()
                let s = c.unicodeString16()
                put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(s))</t></is></c>")
            case 0x06 where rec.body.count >= 20:
                let r = c.u16(), col = c.u16(), x = c.u16()
                let b = Array(rec.body[6 ..< 14])
                if b[6] == 0xFF, b[7] == 0xFF {
                    switch b[0] {
                    case 0: pendingFormula = (r, col, x)
                    case 1: put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"b\"><v>\(b[2] == 0 ? 0 : 1)</v></c>")
                    case 2: put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"e\"><v>\(errorText(Int(b[2])))</v></c>")
                    default: put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"str\"><v></v></c>")
                    }
                } else {
                    let d = Double(bitPattern: b.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << UInt64($1.offset * 8) })
                    if d.isFinite { put(r, col, "<c r=\"\(ref(r, col))\"\(style(x))><v>\(num(d))</v></c>") }
                }
            case 0x207:
                if let (r, col, x) = pendingFormula {
                    let s = c.unicodeString16()
                    put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"str\"><v>\(esc(s))</v></c>")
                    pendingFormula = nil
                }
            case 0x208 where rec.body.count >= 16:
                let r = c.u16(); c.skip(4)
                let h = c.u16(); c.skip(4)
                let flags = c.u16(), x = c.u16()
                var a = ""
                if flags & 0x40 != 0 && h & 0x8000 == 0 { a += " ht=\"\(Double(h & 0x7FFF) / 20)\" customHeight=\"1\"" }
                if flags & 0x20 != 0 { a += " hidden=\"1\"" }
                if flags & 0x80 != 0, x & 0xFFF > 0, Int(x & 0xFFF) < xfCount { a += " s=\"\(x & 0xFFF)\" customFormat=\"1\"" }
                if !a.isEmpty { rows[r] = a }
            case 0x7D where rec.body.count >= 10:
                let first = c.u16(), last = c.u16(), w = c.u16(), x = c.u16(), g = c.u16()
                if first < 16384 {
                    var col = "<col min=\"\(first + 1)\" max=\"\(min(last, 16383) + 1)\" width=\"\(Double(w) / 256)\" customWidth=\"1\""
                    if g & 1 != 0 { col += " hidden=\"1\"" }
                    if x > 0 && x < xfCount { col += " style=\"\(x)\"" }
                    cols.append(col + "/>")
                }
            case 0x55 where rec.body.count >= 2: defColWidth = c.u16()
            case 0x99 where rec.body.count >= 2: stdWidth = c.u16()
            case 0x225 where rec.body.count >= 4:
                let g = c.u16(), h = c.u16()
                defRowHeight = (h, g & 2 != 0)
            case 0xE5 where rec.body.count >= 2:
                let n = c.u16()
                var k = 0
                while k < n, c.pos + 8 <= rec.body.count {
                    let r1 = c.u16(), r2 = c.u16(), c1 = c.u16(), c2 = c.u16()
                    if r1 <= r2, c1 <= c2 { merges.append("<mergeCell ref=\"\(ref(r1, c1)):\(ref(r2, c2))\"/>") }
                    k += 1
                }
            default: break
            }
        }
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        var fmt = ""
        if let s = stdWidth { fmt += " defaultColWidth=\"\(Double(s) / 256)\"" }
        else if let d = defColWidth, d != 8 {
            let units: Int = (d * 7 + 5) * 256 / 7
            let w: Double = Double(units) / 256
            fmt += " defaultColWidth=\"\(w)\""
        }
        if let (h, custom) = defRowHeight, h > 0 { fmt += " defaultRowHeight=\"\(Double(h) / 20)\"" + (custom ? " customHeight=\"1\"" : "") }
        if !fmt.isEmpty { x += "<sheetFormatPr\(fmt)/>" }
        if !cols.isEmpty { x += "<cols>" + cols.joined() + "</cols>" }
        x += "<sheetData>"
        for r in Set(cells.keys).union(rows.keys).sorted() {
            x += "<row r=\"\(r + 1)\"\(rows[r] ?? "")>"
            for c in (cells[r] ?? [:]).keys.sorted() { x += cells[r]![c]! }
            x += "</row>"
        }
        x += "</sheetData>"
        if !merges.isEmpty { x += "<mergeCells count=\"\(merges.count)\">" + merges.joined() + "</mergeCells>" }
        return x + "</worksheet>"
    }

    private static let emptySheet = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData/></worksheet>"
}
