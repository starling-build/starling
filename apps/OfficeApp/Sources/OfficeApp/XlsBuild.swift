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

struct XlsFont {
    var height = 200, flags = 0, color = 0x7FFF, weight = 400, script = 0, underline = 0, family = 0, charset = 0
    var name = "Arial"
}

struct XlsXF {
    var font = 0, format = 0, flags = 1, align = 0, indent = 0, border = 0, borderColor = 0
    var borderColor2: UInt32 = 0
    var fill: UInt16 = 0
    // (u16 reads return Int; the raw fields keep their natural width)
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
        var fonts: [XlsFont] = []
        var xfRecs: [XlsXF] = []
        var palette = defaultPalette
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
            case 0x31 where r.body.count >= 14:
                if fonts.count == 4 { fonts.append(fonts[0]) }   // font index 4 does not exist
                var f = XlsFont()
                f.height = c.u16(); f.flags = c.u16(); f.color = c.u16(); f.weight = c.u16(); f.script = c.u16()
                f.underline = c.u8(); f.family = c.u8(); f.charset = c.u8(); c.skip(1)
                let n = c.u8(), fl = c.u8()
                f.name = c.chars(n, wide: fl & 1 == 1)
                fonts.append(f)
            case 0xE0 where r.body.count >= 20:
                var x = XlsXF()
                x.font = c.u16(); x.format = c.u16(); x.flags = c.u16(); x.align = c.u16(); x.indent = c.u16()
                x.border = c.u16(); x.borderColor = c.u16(); x.borderColor2 = UInt32(truncatingIfNeeded: c.u32()); x.fill = UInt16(truncatingIfNeeded: c.u16())
                xfRecs.append(x)
            case 0x92:
                let n = c.u16()
                var k = 0
                while k < n, k < 56, c.pos + 4 <= r.body.count {
                    palette[k] = (c.u8(), c.u8(), c.u8()); c.skip(1)
                    k += 1
                }
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
        if fonts.isEmpty { fonts = [XlsFont()] }
        let xfs = resolveXFs(xfRecs)
        st += styleBody(fonts: fonts, xfs: xfs, palette: palette)
        add("xl/styles.xml", st + "</styleSheet>")

        for (n, e) in kept.enumerated() {
            let xml = sheetXML(recs, from: e.element.position, sst: sst, xfCount: max(1, xfs.count))
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

    // MARK: Styles

    static let defaultPalette: [(Int, Int, Int)] = {
        let hex: [UInt32] = [
            0x000000, 0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0xFF00FF, 0x00FFFF,
            0x800000, 0x008000, 0x000080, 0x808000, 0x800080, 0x008080, 0xC0C0C0, 0x808080,
            0x9999FF, 0x993366, 0xFFFFCC, 0xCCFFFF, 0x660066, 0xFF8080, 0x0066CC, 0xCCCCFF,
            0x000080, 0xFF00FF, 0xFFFF00, 0x00FFFF, 0x800080, 0x800000, 0x008080, 0x0000FF,
            0x00CCFF, 0xCCFFFF, 0xCCFFCC, 0xFFFF99, 0x99CCFF, 0xFF99CC, 0xCC99FF, 0xFFCC99,
            0x3366FF, 0x33CCCC, 0x99CC00, 0xFFCC00, 0xFF9900, 0xFF6600, 0x666699, 0x969696,
            0x003366, 0x339966, 0x003300, 0x333300, 0x993300, 0x993366, 0x333399, 0x333333]
        return hex.map { (Int($0 >> 16), Int($0 >> 8 & 255), Int($0 & 255)) }
    }()

    /// The colour of a BIFF colour index as RRGGBB, nil for the automatic colours.
    static func rgb(_ icv: Int, _ palette: [(Int, Int, Int)]) -> String? {
        var c: (Int, Int, Int)
        if icv < 8 { c = defaultPalette[icv] }
        else if icv >= 8, icv < 64, icv - 8 < palette.count { c = palette[icv - 8] }
        else { return nil }
        func h(_ v: Int) -> String { let d = Array("0123456789ABCDEF"); return String([d[v >> 4 & 15], d[v & 15]]) }
        return h(c.0) + h(c.1) + h(c.2)
    }

    /// Cell XFs take what their "used" bits leave unset from the parent style XF.
    static func resolveXFs(_ xs: [XlsXF]) -> [XlsXF] {
        var out = xs
        for (i, x) in xs.enumerated() where x.flags & 4 == 0 {
            let p = Int(x.flags >> 4)
            guard p < xs.count, p != i else { continue }
            let par = xs[p]
            var r = x
            if x.indent & 0x0400 == 0 { r.format = par.format }
            if x.indent & 0x0800 == 0 { r.font = par.font }
            if x.indent & 0x1000 == 0 { r.align = par.align; r.indent = (r.indent & 0xFC00) | (par.indent & 0x03FF) }
            if x.indent & 0x2000 == 0 {
                r.border = par.border
                r.borderColor = par.borderColor
                r.borderColor2 = (r.borderColor2 & 0xFC00_0000) | (par.borderColor2 & 0x03FF_FFFF)
            }
            if x.indent & 0x4000 == 0 {
                r.fill = par.fill
                r.borderColor2 = (r.borderColor2 & 0x03FF_FFFF) | (par.borderColor2 & 0xFC00_0000)
            }
            if x.indent & 0x8000 == 0 { r.flags = (r.flags & ~3) | (par.flags & 3) }
            out[i] = r
        }
        return out
    }

    private static let patterns = ["none", "solid", "mediumGray", "darkGray", "lightGray", "darkHorizontal", "darkVertical", "darkDown", "darkUp",
                                   "darkGrid", "darkTrellis", "lightHorizontal", "lightVertical", "lightDown", "lightUp", "lightGrid", "lightTrellis",
                                   "gray125", "gray0625"]
    private static let lineStyles = ["", "thin", "medium", "dashed", "dotted", "thick", "double", "hair", "mediumDashed", "dashDot",
                                     "mediumDashDot", "dashDotDot", "mediumDashDotDot", "slantDashDot"]

    private static func colorTag(_ name: String, _ icv: Int, _ palette: [(Int, Int, Int)]) -> String {
        if let c = rgb(icv, palette) { return "<\(name) rgb=\"FF\(c)\"/>" }
        return "<\(name) auto=\"1\"/>"
    }

    static func styleBody(fonts: [XlsFont], xfs: [XlsXF], palette: [(Int, Int, Int)]) -> String {
        var fx = "<fonts count=\"\(fonts.count)\">"
        for f in fonts {
            fx += "<font>"
            if f.weight >= 700 { fx += "<b/>" }
            if f.flags & 2 != 0 { fx += "<i/>" }
            if f.flags & 8 != 0 { fx += "<strike/>" }
            switch f.underline {
            case 1: fx += "<u/>"
            case 2: fx += "<u val=\"double\"/>"
            case 0x21: fx += "<u val=\"singleAccounting\"/>"
            case 0x22: fx += "<u val=\"doubleAccounting\"/>"
            default: break
            }
            if f.script == 1 { fx += "<vertAlign val=\"superscript\"/>" } else if f.script == 2 { fx += "<vertAlign val=\"subscript\"/>" }
            fx += "<sz val=\"\(Double(f.height) / 20)\"/>"
            if let c = rgb(f.color, palette) { fx += "<color rgb=\"FF\(c)\"/>" }
            fx += "<name val=\"\(esc(f.name))\"/>"
            fx += "<family val=\"\(f.family)\"/>"
            if f.charset != 0 { fx += "<charset val=\"\(f.charset)\"/>" }
            fx += "</font>"
        }
        fx += "</fonts>"

        var fills: [String] = ["<fill><patternFill patternType=\"none\"/></fill>", "<fill><patternFill patternType=\"gray125\"/></fill>"]
        var borders: [String] = []
        var xml = ""
        func intern(_ list: inout [String], _ item: String) -> Int {
            if let k = list.firstIndex(of: item) { return k }
            list.append(item); return list.count - 1
        }
        let list = xfs.isEmpty ? [XlsXF()] : xfs
        for x in list {
            // fill
            let pat = Int(x.borderColor2 >> 26) & 0x3F
            var fillId = 0
            if pat > 0, pat < patterns.count {
                let fg = Int(x.fill) & 0x7F, bg = Int(x.fill >> 7) & 0x7F
                let f = "<fill><patternFill patternType=\"\(patterns[pat])\">" + colorTag("fgColor", fg == 64 ? 0 : fg, palette) + colorTag("bgColor", bg == 65 ? 1 : bg, palette) + "</patternFill></fill>"
                fillId = intern(&fills, f)
            }
            // border
            let b = Int(x.border), bc = Int(x.borderColor), bc2 = Int(x.borderColor2)
            func side(_ tag: String, _ style: Int, _ icv: Int) -> String {
                guard style > 0, style < lineStyles.count else { return "<\(tag)/>" }
                return "<\(tag) style=\"\(lineStyles[style])\">" + colorTag("color", icv, palette) + "</\(tag)>"
            }
            let diagStyle = bc2 >> 21 & 0xF
            var bx = "<border" + (bc & 0x4000 != 0 ? " diagonalDown=\"1\"" : "") + (bc & 0x8000 != 0 ? " diagonalUp=\"1\"" : "") + ">"
            bx += side("left", b & 0xF, bc & 0x7F) + side("right", b >> 4 & 0xF, bc >> 7 & 0x7F)
            bx += side("top", b >> 8 & 0xF, bc2 & 0x7F) + side("bottom", b >> 12 & 0xF, bc2 >> 7 & 0x7F)
            bx += side("diagonal", bc & 0xC000 != 0 ? diagStyle : 0, bc2 >> 14 & 0x7F) + "</border>"
            let borderId = intern(&borders, bx)
            // alignment
            var al = ""
            let h = Int(x.align) & 7, v = Int(x.align >> 4) & 7, rot = Int(x.align >> 8) & 0xFF
            let hn = ["", "left", "center", "right", "fill", "justify", "centerContinuous", "distributed"]
            let vn = ["top", "center", "", "justify", "distributed"]
            if h > 0 { al += " horizontal=\"\(hn[h])\"" }
            if v < vn.count, !vn[v].isEmpty { al += " vertical=\"\(vn[v])\"" }
            if x.align & 8 != 0 { al += " wrapText=\"1\"" }
            if rot != 0 { al += " textRotation=\"\(rot)\"" }
            if x.indent & 0xF != 0 { al += " indent=\"\(x.indent & 0xF)\"" }
            if x.indent & 0x10 != 0 { al += " shrinkToFit=\"1\"" }
            let prot = x.flags & 1 == 0 || x.flags & 2 != 0
            var xf = "<xf numFmtId=\"\(x.format)\" fontId=\"\(Int(x.font) < fonts.count ? Int(x.font) : 0)\" fillId=\"\(fillId)\" borderId=\"\(borderId)\" xfId=\"0\" applyNumberFormat=\"1\" applyFont=\"1\" applyFill=\"1\" applyBorder=\"1\""
            xf += al.isEmpty ? "" : " applyAlignment=\"1\""
            xf += prot ? " applyProtection=\"1\"" : ""
            xf += ">"
            if !al.isEmpty { xf += "<alignment\(al)/>" }
            if prot { xf += "<protection locked=\"\(x.flags & 1)\" hidden=\"\(x.flags >> 1 & 1)\"/>" }
            xml += xf + "</xf>"
        }
        let fl = "<fills count=\"\(fills.count)\">" + fills.joined() + "</fills>"
        let bl = "<borders count=\"\(borders.count)\">" + borders.joined() + "</borders>"
        let csx = "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        return fx + fl + bl + csx + "<cellXfs count=\"\(list.count)\">" + xml + "</cellXfs>"
    }

    private static let emptySheet = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData/></worksheet>"
}
