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

/// What a sheet's drawing layer produced: the picture slots it uses (indexes into the book's picture store) and one anchor element per picture.
struct XlsDrawingOut {
    var pics: [Int] = []
    var anchors: [String] = []
    /// The chart substreams of the sheet; an anchor holds "@CHARTk@" where chart k's relationship id goes.
    var charts: [[BiffRecord]] = []
    /// The cached values of the sheet's cells (text, is a number), for the chart caches.
    var values: [Int: [Int: (String, Bool)]] = [:]
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
    /// An Office 2007-2010 theme colour (index as in a cell colour: 0 light 1, 1 dark 1, 2 light 2, 3 dark 2, 4-9 accents)
    /// with Excel's tint (lighter above 0, darker below), as RRGGBB.
    static func themeTintHex(_ idx: Int, _ tint: Double) -> String? {
        let base = ["FFFFFF", "000000", "EEECE1", "1F497D", "4F81BD", "C0504D", "9BBB59", "8064A2", "4BACC6", "F79646"]
        guard idx >= 0, idx < base.count else { return nil }
        let v = Array(base[idx].utf8)
        func hv(_ x: UInt8) -> Int { Int(x >= 65 ? x - 55 : x - 48) }
        let r = Double(hv(v[0]) * 16 + hv(v[1])) / 255, g = Double(hv(v[2]) * 16 + hv(v[3])) / 255, b = Double(hv(v[4]) * 16 + hv(v[5])) / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        var h = 0.0, s = 0.0, l = (mx + mn) / 2
        if mx != mn {
            let d = mx - mn
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h /= 6
        }
        l = tint < 0 ? l * (1 + tint) : l * (1 - tint) + tint
        func f(_ p: Double, _ q: Double, _ tt: Double) -> Double {
            var t = tt; if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        var rgb = [l, l, l]
        if s != 0 {
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
            rgb = [f(p, q, h + 1.0 / 3), f(p, q, h), f(p, q, h - 1.0 / 3)]
        }
        return rgb.map { x -> String in let n = Int((x * 255).rounded()); let d = Array("0123456789ABCDEF"); return String(d[n / 16]) + String(d[n % 16]) }.joined()
    }

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
        var xfExt: [Int: (fg: String?, bg: String?)] = [:]
        var sheets: [Xls.SheetInfo] = []
        var xtis: [(Int, Int)] = []
        var nameRecs: [BiffRecord] = []
        var internalBooks: Set<Int> = [], supBooks = 0
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
            case 0x87D where r.body.count >= 20:
                // XFExt: FrtHeader(12), reserved(2), ixfe, reserved(2), cexts, then ExtProps.
                c.skip(12); c.skip(2); let ixfe = c.u16(); c.skip(2); let n = c.u16()
                var e: (fg: String?, bg: String?) = (nil, nil)
                for _ in 0 ..< n where c.pos + 4 <= r.body.count {
                    let t = c.u16(), cb = c.u16()
                    let end = c.pos + cb - 4
                    if (t == 4 || t == 5), cb == 20, c.pos + 16 <= r.body.count {
                        let kind = c.u16(); let tintRaw = Int(Int16(truncatingIfNeeded: c.u16()))
                        if kind == 3, c.pos + 4 <= r.body.count {
                            let idx = Int(c.u32())
                            if let hex = themeTintHex(idx, Double(tintRaw) / 32767) { if t == 4 { e.fg = hex } else { e.bg = hex } }
                        } else if kind == 2 {
                            let rr = c.u8(), gg = c.u8(), bb = c.u8()
                            let hex = [rr, gg, bb].map { (String($0, radix: 16, uppercase: true).count == 1 ? "0" : "") + String($0, radix: 16, uppercase: true) }.joined()
                            if t == 4 { e.fg = hex } else { e.bg = hex }
                        }
                    }
                    c.pos = max(c.pos, min(end, r.body.count))
                }
                xfExt[ixfe] = e
            case 0x92:
                let n = c.u16()
                var k = 0
                while k < n, k < 56, c.pos + 4 <= r.body.count {
                    palette[k] = (c.u8(), c.u8(), c.u8()); c.skip(1)
                    k += 1
                }
            case 0x17:
                let n = c.u16()
                for _ in 0 ..< n where c.pos + 6 <= r.body.count { let sup = c.u16(); let a = c.u16(); c.skip(2); xtis.append((a, sup)) }
            case 0x1AE:
                // An internal SUPBOOK (this workbook) is 4 bytes ending 0x0401.
                if r.body.count == 4, r.body[2] == 0x01, r.body[3] == 0x04 { internalBooks.insert(supBooks) }
                supBooks += 1
            case 0x18: nameRecs.append(r)
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
        // Excel 2007 and later writes its default theme-body font as black (colour index 8, theme colour 1);
        // a copy saved with a localized body face (Malgun Gothic, SimSun) is reloaded by an English Excel as
        // the theme's body font (Calibri): same face as font 0, 11 pt, colour index 8, East Asian charset.
        if let f0 = fonts.first, f0.name != "Calibri", f0.height == 220, f0.color == 8, f0.charset >= 128, f0.charset != 255 {
            for k in fonts.indices where fonts[k].name == f0.name && fonts[k].height == 220 && fonts[k].color == 8 { fonts[k].name = "Calibri" }
        }
        var ctx = XlsFormulaContext(xtis: xtis, internalBooks: internalBooks, sheetNames: sheets.map { $0.name }, names: [])
        ctx.names = nameRecs.map { nameText($0) }
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
        wb += "</sheets>"
        wb += definedNamesXML(nameRecs, xtis: xtis, sheetNames: sheets.map { $0.name }, kept: kept.map { $0.offset })
        wb += "</workbook>"
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
        st += styleBody(fonts: fonts, xfs: xfs, palette: palette, xfExt: xfExt)
        var dxfs: [String] = []
        var blips: [ArtBlip?] = []
        if let g = recs.first(where: { $0.type == 0xEB }) { blips = OfficeArt.blips(group: g.body) }

        var built: [(links: [String], drawing: XlsDrawingOut)] = []
        for (n, e) in kept.enumerated() {
            var links: [String] = []
            var drawing = XlsDrawingOut()
            let xml = sheetXML(recs, from: e.element.position, sst: sst, xfCount: max(1, xfs.count), ctx: ctx, palette: palette, dxfs: &dxfs, links: &links, blips: blips, drawing: &drawing)
            add("xl/worksheets/sheet\(n + 1).xml", xml)
            built.append((links, drawing))
        }
        var chartCount = 0
        var keptValues: [Int: [Int: [Int: (String, Bool)]]] = [:]
        for (n, e) in kept.enumerated() { keptValues[e.offset] = built[n].drawing.values }
        func swapText(_ s: String, _ a: String, _ b: String) -> String {
            guard let r = s.rangeOfSubstring(a) else { return s }
            return String(s[s.startIndex ..< r.lowerBound]) + b + String(s[r.upperBound...])
        }
        for (n, b) in built.enumerated() {
            let links = b.links
            var drawing = b.drawing
            var srels = links.enumerated().map { "<Relationship Id=\"rIdL\($0.offset + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(esc($0.element))\" TargetMode=\"External\"/>" }.joined()
            var drels = ""
            for (k, bi) in drawing.pics.enumerated() {
                guard let bl = blips[bi] else { continue }
                drels += "<Relationship Id=\"rId\(k + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image\(bi + 1).\(bl.ext)\"/>"
                if !out.contains(where: { $0.name == "xl/media/image\(bi + 1).\(bl.ext)" }) { out.append(ZipEntry(name: "xl/media/image\(bi + 1).\(bl.ext)", data: Data(bl.data))) }
            }
            // Charts: each substream becomes a chart part; an anchor whose chart is not supported is dropped.
            for (k, cr) in drawing.charts.enumerated() {
                let marker = "r:id=\"@CHART\(k)@\""
                let xml = XlsChart.build(cr, ctx: ctx, fontHeights: fonts.map { $0.height }, cell: { sh, r, c in
                    keptValues[sh]?[r]?[c]
                })
                if let xml = xml {
                    chartCount += 1
                    add("xl/charts/chart\(chartCount).xml", xml)
                    drels += "<Relationship Id=\"rIdC\(k + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"../charts/chart\(chartCount).xml\"/>"
                    drawing.anchors = drawing.anchors.map { swapText($0, marker, "r:id=\"rIdC\(k + 1)\"") }
                } else {
                    drawing.anchors.removeAll { $0.containsSubstring(marker) }
                }
            }
            if !drawing.anchors.isEmpty {
                srels += "<Relationship Id=\"rIdD1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing\" Target=\"../drawings/drawing\(n + 1).xml\"/>"
                add("xl/drawings/drawing\(n + 1).xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><xdr:wsDr xmlns:xdr=\"http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">" + drawing.anchors.joined() + "</xdr:wsDr>")
                add("xl/drawings/_rels/drawing\(n + 1).xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + drels + "</Relationships>")
            }
            if !srels.isEmpty {
                add("xl/worksheets/_rels/sheet\(n + 1).xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + srels + "</Relationships>")
            }
        }
        // styles.xml last: the conditional formats' differential formats are collected by the sheets.
        out.removeAll { $0.name == "xl/styles.xml" }
        add("xl/styles.xml", st + (dxfs.isEmpty ? "" : "<dxfs count=\"\(dxfs.count)\">" + dxfs.joined() + "</dxfs>") + "</styleSheet>")
        return out
    }

    private static func sheetXML(_ recs: [BiffRecord], from position: Int, sst: [String], xfCount: Int, ctx: XlsFormulaContext, palette: [(Int, Int, Int)], dxfs: inout [String], links: inout [String], blips: [ArtBlip?], drawing: inout XlsDrawingOut) -> String {
        guard var i = recs.firstIndex(where: { $0.offset == position && $0.type == 0x809 }) else { return emptySheet }
        var cells: [Int: [Int: String]] = [:]
        var rows: [Int: String] = [:]
        var cols: [String] = []
        var merges: [String] = []
        var cfGroups: [(sqref: String, base: (Int, Int), rules: [String])] = []
        var validations: [String] = []
        var tabColor = ""
        var colSpans: [(Int, Int, Int)] = [], rowTwips: [Int: Int] = [:]
        var art: [UInt8] = []
        var hyperlinks: [String] = []
        var cfPriority = 0
        var defColWidth: Int? = nil, stdWidth: Int? = nil
        var defRowHeight: (Int, Bool)? = nil
        var pendingFormula: (Int, Int, Int, String)? = nil
        // Shared and array formulas, by their first cell, found before the cells that use them.
        var shared: [Int: [UInt8]] = [:], sharedRanges: [(Int, Int, Int, Int, Int)] = [], arrays: [Int: (String, [UInt8])] = [:]
        do {
            var k = i, d = 0
            while k < recs.count {
                let q = recs[k]; k += 1
                if q.type == 0x809 { d += 1 }
                if q.type == 0x0A { d -= 1; if d <= 0 { break } }
                if d != 1 { continue }
                var bc = BiffCursor(q)
                if q.type == 0x4BC, q.body.count >= 10 {
                    let r1 = bc.u16(), r2 = bc.u16(), c1 = bc.u8(), c2 = bc.u8()
                    let n = Int(q.body[8]) | Int(q.body[9]) << 8
                    if 10 + n <= q.body.count { shared[r1 << 8 | c1] = Array(q.body[10 ..< 10 + n]); sharedRanges.append((r1, r2, c1, c2, r1 << 8 | c1)) }
                } else if q.type == 0x221, q.body.count >= 14 {
                    let r1 = bc.u16(), r2 = bc.u16(), c1 = bc.u8(), c2 = bc.u8()
                    let n = Int(q.body[12]) | Int(q.body[13]) << 8
                    if 14 + n <= q.body.count { arrays[r1 << 8 | c1] = (cellRange(r1, c1, r2, c2), Array(q.body[14 ..< 14 + n])) }
                }
            }
        }
        var setup: [Int: Int] = [:]
        var margins: [Double?] = [nil, nil, nil, nil]
        var hdrFtr: [String?] = [nil, nil]
        var fitToPage = false
        var win2: Int? = nil
        var summaryBelow = true, summaryRight = true
        var pane: (Int, Int, Int, Int, Int)? = nil
        var printGrid = false, printHeads = false, hCenter = false, vCenter = false
        var hBreaks: [(Int, Int, Int)] = [], vBreaks: [(Int, Int, Int)] = []
        var hdrFtrMargins: (Double, Double)? = nil
        var depth = 0
        var inChart = false
        var objTypes: [Int] = []
        func style(_ x: Int) -> String { x > 0 && x < xfCount ? " s=\"\(x)\"" : "" }
        func keep(_ r: Int, _ c: Int, _ v: String, _ isNum: Bool) { if drawing.values.count < 1_000_000 { drawing.values[r, default: [:]][c] = (v, isNum) } }
        func put(_ r: Int, _ c: Int, _ xml: String) { if r < 1_048_576, c < 16384 { cells[r, default: [:]][c] = xml } }
        func ref(_ r: Int, _ c: Int) -> String { colName(c) + String(r + 1) }
        while i < recs.count {
            let rec = recs[i]
            i += 1
            if rec.type == 0x809 {
                depth += 1
                if depth > 1 {
                    if depth == 2, rec.body.count >= 4, rec.body[2] == 0x20 { drawing.charts.append([]); inChart = true }
                    continue
                }
            }
            if rec.type == 0x0A { depth -= 1; if depth <= 0 { break }; if depth == 1 { inChart = false } }
            if depth != 1 { if inChart, !drawing.charts.isEmpty { drawing.charts[drawing.charts.count - 1].append(rec) }; continue }
            var c = BiffCursor(rec)
            switch rec.type {
            case 0x5D where rec.body.count >= 6 && rec.body[0] == 0x15: objTypes.append(Int(rec.body[4]) | Int(rec.body[5]) << 8)
            case 0xA1 where rec.body.count >= 34:
                for k in 0 ..< 6 { setup[k] = c.u16() }
                c.skip(4)
                func dbl() -> Double { let lo = UInt64(c.u32()); return Double(bitPattern: lo | UInt64(c.u32()) << 32) }
                let hd = dbl(), ft = dbl()
                hdrFtrMargins = (hd, ft)
            case 0x26, 0x27, 0x28, 0x29 where rec.body.count >= 8:
                let lo = UInt64(c.u32()); let d = Double(bitPattern: lo | UInt64(c.u32()) << 32)
                if d.isFinite { margins[Int(rec.type) - 0x26] = d }
            case 0x14, 0x15 where rec.body.count >= 3:
                let cch = c.u16()
                if cch > 0 { let f = c.u8(); hdrFtr[Int(rec.type) - 0x14] = c.chars(cch, wide: f & 1 == 1) }
            case 0x81 where rec.body.count >= 2:
                let g = c.u16()
                fitToPage = g & 0x100 != 0
                summaryBelow = g & 0x40 != 0; summaryRight = g & 0x80 != 0
            case 0x41 where rec.body.count >= 10: pane = (c.u16(), c.u16(), c.u16(), c.u16(), c.u16())
            case 0x23E where rec.body.count >= 2: win2 = c.u16()
            case 0x2A: printHeads = c.u16() != 0
            case 0x2B: printGrid = c.u16() != 0
            case 0x83: hCenter = c.u16() != 0
            case 0x84: vCenter = c.u16() != 0
            case 0x1B, 0x1A:
                let n = c.u16()
                var list: [(Int, Int, Int)] = []
                for _ in 0 ..< n where c.pos + 6 <= rec.body.count { let a = c.u16(), b = c.u16(), d = c.u16(); list.append((a, b, d)) }
                if rec.type == 0x1B { hBreaks = list } else { vBreaks = list }
            case 0xFD where rec.body.count >= 10:
                let r = c.u16(), col = c.u16(), x = c.u16(), k = Int(c.u32())
                if k < sst.count { put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"s\"><v>\(k)</v></c>"); keep(r, col, sst[k], false) }
            case 0x203 where rec.body.count >= 14:
                let r = c.u16(), col = c.u16(), x = c.u16()
                let d = Double(bitPattern: UInt64(c.u32()) | UInt64(c.u32()) << 32)
                if d.isFinite { put(r, col, "<c r=\"\(ref(r, col))\"\(style(x))><v>\(num(d))</v></c>"); keep(r, col, num(d), true) }
            case 0x27E where rec.body.count >= 10:
                let r = c.u16(), col = c.u16(), x = c.u16()
                let v = num(rk(c.u32()))
                put(r, col, "<c r=\"\(ref(r, col))\"\(style(x))><v>\(v)</v></c>"); keep(r, col, v, true)
            case 0xBD where rec.body.count >= 6:
                let r = c.u16(), first = c.u16()
                let last = Int(rec.body[rec.body.count - 2]) | Int(rec.body[rec.body.count - 1]) << 8
                var col = first
                while col <= last, c.pos + 6 <= rec.body.count - 2 {
                    let x = c.u16()
                    let v = num(rk(c.u32()))
                    put(r, col, "<c r=\"\(ref(r, col))\"\(style(x))><v>\(v)</v></c>"); keep(r, col, v, true)
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
                put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(s))</t></is></c>"); keep(r, col, s, false)
            case 0x06 where rec.body.count >= 22:
                let r = c.u16(), col = c.u16(), x = c.u16()
                let b = Array(rec.body[6 ..< 14])
                let cce = Int(rec.body[20]) | Int(rec.body[21]) << 8
                let rg = Array(rec.body[22 ..< min(rec.body.count, 22 + cce)])
                var f = ""
                if rg.count == 5, rg[0] == 0x01 {
                    let key = (Int(rg[1]) | Int(rg[2]) << 8) << 8 | (Int(rg[3]) | Int(rg[4]) << 8)
                    let fr = Int(rg[1]) | Int(rg[2]) << 8, fc = Int(rg[3]) | Int(rg[4]) << 8
                    if let (rng, ar) = arrays[key] {
                        if fr == r, fc == col, let t = XlsFormula.decompile(ar, row: r, col: col, relative: false, ctx: ctx) {
                            f = "<f t=\"array\" ref=\"\(rng)\">\(esc(t))</f>"
                        }
                    } else if let sh = shared[key] ?? sharedRanges.first(where: { fr >= $0.0 && fr <= $0.1 && fc >= $0.2 && fc <= $0.3 }).flatMap({ shared[$0.4] }), let t = XlsFormula.decompile(sh, row: r, col: col, relative: true, ctx: ctx) {
                        f = "<f>\(esc(t))</f>"
                    }
                } else if let t = XlsFormula.decompile(rg, row: r, col: col, relative: false, ctx: ctx) {
                    f = "<f>\(esc(t))</f>"
                }
                if b[6] == 0xFF, b[7] == 0xFF {
                    switch b[0] {
                    case 0: pendingFormula = (r, col, x, f)
                    case 1: put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"b\">\(f)<v>\(b[2] == 0 ? 0 : 1)</v></c>")
                    case 2: put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"e\">\(f)<v>\(errorText(Int(b[2])))</v></c>")
                    default: put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"str\">\(f)<v></v></c>")
                    }
                } else {
                    let d = Double(bitPattern: b.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << UInt64($1.offset * 8) })
                    if d.isFinite { put(r, col, "<c r=\"\(ref(r, col))\"\(style(x))>\(f)<v>\(num(d))</v></c>"); keep(r, col, num(d), true) }
                }
            case 0x207:
                if let (r, col, x, f) = pendingFormula {
                    let s = c.unicodeString16()
                    put(r, col, "<c r=\"\(ref(r, col))\"\(style(x)) t=\"str\">\(f)<v>\(esc(s))</v></c>"); keep(r, col, s, false)
                    pendingFormula = nil
                }
            case 0x208 where rec.body.count >= 16:
                let r = c.u16(); c.skip(4)
                let h = c.u16(); c.skip(4)
                let flags = c.u16(), x = c.u16()
                var a = ""
                if h & 0x8000 == 0, h > 0 { a += " ht=\"\(Double(h & 0x7FFF) / 20)\"" + (flags & 0x40 != 0 ? " customHeight=\"1\"" : "") }
                if flags & 0x20 != 0 { a += " hidden=\"1\"" }
                if flags & 7 != 0 { a += " outlineLevel=\"\(flags & 7)\"" }
                if flags & 0x10 != 0 { a += " collapsed=\"1\"" }
                if flags & 0x80 != 0, x & 0xFFF > 0, Int(x & 0xFFF) < xfCount { a += " s=\"\(x & 0xFFF)\" customFormat=\"1\"" }
                if !a.isEmpty { rows[r] = a }
                rowTwips[r] = flags & 0x20 != 0 ? 0 : (h & 0x8000 == 0 && h > 0 ? h & 0x7FFF : -1)
            case 0x7D where rec.body.count >= 10:
                let first = c.u16(), last = c.u16(), w = c.u16(), x = c.u16(), g = c.u16()
                colSpans.append((first, last, g & 1 != 0 ? 0 : w))
                if first < 16384 {
                    var col = "<col min=\"\(first + 1)\" max=\"\(min(last, 16383) + 1)\" width=\"\(Double(w) / 256)\" customWidth=\"1\""
                    if g & 1 != 0 { col += " hidden=\"1\"" }
                    if g >> 8 & 7 != 0 { col += " outlineLevel=\"\(g >> 8 & 7)\"" }
                    if g & 0x1000 != 0 { col += " collapsed=\"1\"" }
                    if x > 0 && x < xfCount { col += " style=\"\(x)\"" }
                    cols.append(col + "/>")
                }
            case 0x55 where rec.body.count >= 2: defColWidth = c.u16()
            case 0x99 where rec.body.count >= 2: stdWidth = c.u16()
            case 0x225 where rec.body.count >= 4:
                let g = c.u16(), h = c.u16()
                defRowHeight = (h, g & 1 != 0)
            case 0x1B0 where rec.body.count >= 18:
                // CONDFMT: ccf, grbit, bounding range, then the ranges the rules apply to.
                c.skip(4); let bound = (c.u16(), c.u16(), c.u16(), c.u16())
                let n = c.u16()
                var refs: [String] = []
                var k = 0
                while k < n, c.pos + 8 <= rec.body.count {
                    let r1 = c.u16(), r2 = c.u16(), c1 = c.u16(), c2 = c.u16()
                    if r1 <= r2, c1 <= c2 { refs.append(cellRange(r1, c1, r2, c2)) }
                    k += 1
                }
                cfGroups.append((refs.joined(separator: " "), (bound.0, bound.2), []))
            case 0x1B1 where rec.body.count >= 12 && !cfGroups.isEmpty:
                let ct = c.u8(), op = c.u8(), n1 = c.u16(), n2 = c.u16()
                let fl = c.u32(); c.skip(2)
                var font = "", border = "", fill = ""
                if fl & 0x0400_0000 != 0, c.pos + 118 <= rec.body.count {
                    let b = Array(rec.body[c.pos ..< c.pos + 118]); c.skip(118)
                    func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
                    let style = u32(68), weight = Int(b[72]) | Int(b[73]) << 8, ul = Int(b[76]), color = u32(80), opt = u32(88)
                    if opt & 2 == 0 {
                        if weight >= 700 { font += "<b/>" }
                        font += style & 2 != 0 ? "<i/>" : "<i val=\"0\"/>"
                    }
                    if opt & 0x80 == 0, style & 0x80 != 0 { font += "<strike/>" }
                    if opt & 0x10 == 0, ul != 0, ul != 0xFF { font += ul == 2 ? "<u val=\"double\"/>" : "<u/>" }
                    if UInt32(truncatingIfNeeded: color) != UInt32.max, color != 0x7FFF, let hex = rgb(color, palette) { font += "<color rgb=\"FF\(hex)\"/>" }
                }
                if fl & 0x1000_0000 != 0, c.pos + 8 <= rec.body.count {
                    let ls = c.u16(), cl = Int(c.u32()); c.skip(2)
                    func side(_ tag: String, _ st: Int, _ icv: Int) -> String {
                        guard st > 0, st < lineStyles.count else { return "" }
                        return "<\(tag) style=\"\(lineStyles[st])\">" + colorTag("color", icv, palette) + "</\(tag)>"
                    }
                    border = side("left", ls & 0xF, cl & 0x7F) + side("right", ls >> 4 & 0xF, cl >> 7 & 0x7F)
                        + side("top", ls >> 8 & 0xF, cl >> 16 & 0x7F) + side("bottom", ls >> 12 & 0xF, cl >> 23 & 0x7F)
                }
                if fl & 0x2000_0000 != 0, c.pos + 4 <= rec.body.count {
                    let pt = c.u16(), cl = c.u16()
                    let pat = pt >> 10 & 0x3F, fg = cl & 0x7F, bg = cl >> 7 & 0x7F
                    if pat > 0, pat < patterns.count {
                        // In a differential format a solid fill's colour is its background colour.
                        if pat == 1 { fill = "<patternFill patternType=\"solid\">" + colorTag("bgColor", bg, palette) + "</patternFill>" }
                        else { fill = "<patternFill patternType=\"\(patterns[pat])\">" + (fg == 64 ? "" : colorTag("fgColor", fg, palette)) + (bg == 65 ? "" : colorTag("bgColor", bg, palette)) + "</patternFill>" }
                    } else if pat == 0, bg != 65 { fill = "<patternFill>" + colorTag("bgColor", bg, palette) + "</patternFill>" }
                }
                let t1 = c.pos + n1 <= rec.body.count ? Array(rec.body[c.pos ..< c.pos + n1]) : []
                c.skip(n1)
                let t2 = c.pos + n2 <= rec.body.count ? Array(rec.body[c.pos ..< c.pos + n2]) : []
                let base = cfGroups[cfGroups.count - 1].base
                let f1 = n1 > 0 ? XlsFormula.decompile(t1, row: base.0, col: base.1, relative: true, ctx: ctx) : nil
                let f2 = n2 > 0 ? XlsFormula.decompile(t2, row: base.0, col: base.1, relative: true, ctx: ctx) : nil
                let ops = ["", "between", "notBetween", "equal", "notEqual", "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual"]
                guard let f1v = f1, ct == 1 || ct == 2 else { break }
                var d = "<dxf>"
                if !font.isEmpty { d += "<font>" + font + "</font>" }
                if !fill.isEmpty { d += "<fill>" + fill + "</fill>" }
                if !border.isEmpty { d += "<border>" + border + "</border>" }
                d += "</dxf>"
                let id: Int
                if let k = dxfs.firstIndex(of: d) { id = k } else { dxfs.append(d); id = dxfs.count - 1 }
                cfPriority += 1
                var rule = "<cfRule type=\"\(ct == 1 ? "cellIs" : "expression")\" dxfId=\"\(id)\" priority=\"\(cfPriority)\" stopIfTrue=\"1\""
                if ct == 1 { rule += " operator=\"\(op < ops.count && op > 0 ? ops[op] : "equal")\"" }
                rule += "><formula>\(esc(f1v))</formula>"
                if ct == 1, op == 1 || op == 2, let f2v = f2 { rule += "<formula>\(esc(f2v))</formula>" }
                rule += "</cfRule>"
                cfGroups[cfGroups.count - 1].rules.append(rule)
            case 0xEC: art += rec.body
            case 0x862 where rec.body.count >= 32:
                // SheetExt: after the header, a size, two flag words, then the tab colour's kind and value.
                let b = rec.body
                let kind = Int(b[24]) | Int(b[25]) << 8
                if kind == 2, rec.body.count >= 31 { 
                    let hx = b[28 ... 30].map { (String($0, radix: 16, uppercase: true).count == 1 ? "0" : "") + String($0, radix: 16, uppercase: true) }.joined()
                    tabColor = "<tabColor rgb=\"FF\(hx)\"/>"
                }
                else if kind == 3 { tabColor = "<tabColor theme=\"\(Int(b[28]))\"/>" }
                else if kind == 1 { tabColor = "<tabColor indexed=\"\(Int(b[28]))\"/>" }
            case 0x1BE where rec.body.count >= 20:
                // DV: flags, four texts (prompt title, error title, prompt, error), two formulas, the cells.
                let fl = Int(c.u32())
                let pt = c.unicodeString16(), et = c.unicodeString16(), pm = c.unicodeString16(), em = c.unicodeString16()
                let n1 = c.u16(); c.skip(2)
                let t1 = c.pos + n1 <= rec.body.count ? Array(rec.body[c.pos ..< c.pos + n1]) : []
                c.skip(n1)
                let n2 = c.u16(); c.skip(2)
                let t2 = c.pos + n2 <= rec.body.count ? Array(rec.body[c.pos ..< c.pos + n2]) : []
                c.skip(n2)
                let n = c.u16()
                var refs: [(Int, Int, Int, Int)] = []
                var k = 0
                while k < n, c.pos + 8 <= rec.body.count {
                    let r1 = c.u16(), r2 = c.u16(), c1 = c.u16(), c2 = c.u16()
                    if r1 <= r2, c1 <= c2 { refs.append((r1, c1, r2, c2)) }
                    k += 1
                }
                guard let first = refs.first else { break }
                let types = ["none", "whole", "decimal", "list", "date", "time", "textLength", "custom"]
                let ty = fl & 0xF
                guard ty > 0, ty < types.count else { break }
                let ops = ["between", "notBetween", "equal", "notEqual", "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual"]
                let op = fl >> 20 & 0xF
                var a = "<dataValidation type=\"\(types[ty])\""
                if fl >> 4 & 7 == 1 { a += " errorStyle=\"warning\"" } else if fl >> 4 & 7 == 2 { a += " errorStyle=\"information\"" }
                if op > 0, op < ops.count { a += " operator=\"\(ops[op])\"" }
                if fl & 0x100 != 0 { a += " allowBlank=\"1\"" }
                if fl & 0x200 != 0, ty == 3 { a += " showDropDown=\"1\"" }
                if fl & 0x40000 != 0 { a += " showInputMessage=\"1\"" }
                if fl & 0x80000 != 0 { a += " showErrorMessage=\"1\"" }
                if !et.isEmpty, et != "\0" { a += " errorTitle=\"\(esc(et))\"" }
                if !em.isEmpty, em != "\0" { a += " error=\"\(esc(em))\"" }
                if !pt.isEmpty, pt != "\0" { a += " promptTitle=\"\(esc(pt))\"" }
                if !pm.isEmpty, pm != "\0" { a += " prompt=\"\(esc(pm))\"" }
                a += " sqref=\"" + refs.map { cellRange($0.0, $0.1, $0.2, $0.3) }.joined(separator: " ") + "\">"
                if n1 > 0, let f = XlsFormula.decompile(t1, row: first.0, col: first.1, relative: true, ctx: ctx) { a += "<formula1>\(esc(f))</formula1>" }
                if n2 > 0, let f = XlsFormula.decompile(t2, row: first.0, col: first.1, relative: true, ctx: ctx) { a += "<formula2>\(esc(f))</formula2>" }
                validations.append(a + "</dataValidation>")
            case 0x1B8 where rec.body.count >= 32:
                // HLINK: the cells, a GUID, then flags and the optional parts in a fixed order.
                let r1 = c.u16(), r2 = c.u16(), c1 = c.u16(), c2 = c.u16()
                c.skip(20)
                let fl = Int(c.u32())
                let b = rec.body
                func str() -> String {   // u32 count of UTF-16 units, the last being a null
                    guard c.pos + 4 <= b.count else { return "" }
                    let n = Int(c.u32())
                    guard n >= 0, n < 10000, c.pos + 2 * n <= b.count else { c.pos = b.count; return "" }
                    var u: [UInt16] = []
                    for k in 0 ..< n { u.append(UInt16(b[c.pos + 2 * k]) | UInt16(b[c.pos + 2 * k + 1]) << 8) }
                    c.skip(2 * n)
                    while u.last == 0 { u.removeLast() }
                    return String(decoding: u, as: UTF16.self)
                }
                var display = "", url = "", loc = ""
                if fl & 0x14 == 0x14 { display = str() }
                if fl & 0x80 != 0 { _ = str() }
                if fl & 1 != 0 {
                    if fl & 0x100 != 0 { url = str() }
                    else if c.pos + 20 <= b.count {
                        let g0 = b[c.pos]
                        c.skip(16)
                        if g0 == 0xE0 {   // URL moniker: byte length, then the UTF-16 address
                            let n = Int(c.u32())
                            if n >= 2, n < 20000, c.pos + n <= b.count {
                                var u: [UInt16] = []
                                var k = 0
                                while k + 1 < n { u.append(UInt16(b[c.pos + k]) | UInt16(b[c.pos + k + 1]) << 8); k += 2 }
                                while u.last == 0 { u.removeLast() }
                                url = String(decoding: u, as: UTF16.self)
                            }
                        }
                    }
                }
                if fl & 8 != 0, !(fl & 1 != 0 && url.isEmpty) { loc = str() }
                guard r1 <= r2, c1 <= c2, !url.isEmpty || !loc.isEmpty else { break }
                var a = "<hyperlink ref=\"\(cellRange(r1, c1, r2, c2))\""
                if !url.isEmpty { links.append(url); a += " r:id=\"rIdL\(links.count)\"" }
                if !loc.isEmpty { a += " location=\"\(esc(loc))\"" }
                if !display.isEmpty { a += " display=\"\(esc(display))\"" }
                hyperlinks.append(a + "/>")
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
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        if fitToPage || !summaryBelow || !summaryRight || !tabColor.isEmpty {
            x += "<sheetPr>" + tabColor
            if !summaryBelow || !summaryRight { x += "<outlinePr" + (summaryBelow ? "" : " summaryBelow=\"0\"") + (summaryRight ? "" : " summaryRight=\"0\"") + "/>" }
            if fitToPage { x += "<pageSetUpPr fitToPage=\"1\"/>" }
            x += "</sheetPr>"
        }
        var fmt = ""
        if let s = stdWidth { fmt += " defaultColWidth=\"\(Double(s) / 256)\"" }
        else if let d = defColWidth, d != 8 {
            let units: Int = (d * 7 + 5) * 256 / 7
            let w: Double = Double(units) / 256
            fmt += " defaultColWidth=\"\(w)\""
        }
        var view = "<sheetViews><sheetView"
        if let w = win2 {
            if w & 0x02 == 0 { view += " showGridLines=\"0\"" }
            if w & 0x04 == 0 { view += " showRowColHeaders=\"0\"" }
            if w & 0x10 == 0 { view += " showZeros=\"0\"" }
        }
        view += " workbookViewId=\"0\">"
        if let (px, py, top, left, pnn) = pane, let w = win2, w & 0x08 != 0, px > 0 || py > 0 {
            var pa = "<pane"
            if px > 0 { pa += " xSplit=\"\(px)\"" }
            if py > 0 { pa += " ySplit=\"\(py)\"" }
            let active = ["bottomRight", "topRight", "bottomLeft", "topLeft"][min(pnn, 3)]
            pa += " topLeftCell=\"\(colName(left))\(top + 1)\" activePane=\"\(active)\" state=\"\(w & 0x100 != 0 ? "frozen" : "frozenSplit")\"/>"
            view += pa
        }
        x += view + "</sheetView></sheetViews>"
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
        for g in cfGroups where !g.rules.isEmpty && !g.sqref.isEmpty {
            x += "<conditionalFormatting sqref=\"\(g.sqref)\">" + g.rules.joined() + "</conditionalFormatting>"
        }
        if !validations.isEmpty { x += "<dataValidations count=\"\(validations.count)\">" + validations.joined() + "</dataValidations>" }
        if !hyperlinks.isEmpty { x += "<hyperlinks>" + hyperlinks.joined() + "</hyperlinks>" }
        x += pageXML(setup: setup, margins: margins, hdrFtr: hdrFtr, margin2: hdrFtrMargins, grid: printGrid, heads: printHeads, hc: hCenter, vc: vCenter, hBreaks: hBreaks, vBreaks: vBreaks)
        if !art.isEmpty {
            let dw = Double(stdWidth ?? (defColWidth.map { $0 * 256 + 1280 } ?? 2340)) / 256 * 7
            let dh = Double(defRowHeight?.0 ?? 255) / 20
            func colPx(_ c: Int) -> Double { if let sp = colSpans.last(where: { $0.0 <= c && c <= $0.1 }) { return Double(sp.2) / 256 * 7 }; return dw }
            func rowPt(_ r: Int) -> Double { if let t = rowTwips[r], t >= 0 { return Double(t) / 20 }; return dh }
            func emu(_ v: Double) -> Int { Int(v.rounded()) }
            var chartNo = 0
            for (k, sh) in OfficeArt.shapes(drawing: art).filter({ $0.anchor != nil }).enumerated() {
                guard let a = sh.anchor else { continue }
                let isChart = k < objTypes.count && objTypes[k] == 5
                var slot = 0
                if isChart { guard chartNo < drawing.charts.count else { continue }; chartNo += 1 }
                else if sh.type != 20 || sh.pib != 0 {
                    guard sh.pib > 0, sh.pib <= blips.count, blips[sh.pib - 1] != nil else { continue }
                    slot = drawing.pics.firstIndex(of: sh.pib - 1) ?? { drawing.pics.append(sh.pib - 1); return drawing.pics.count - 1 }()
                }
                var w = 0.0, h = 0.0
                if a[4] >= a[0] { for c in a[0] ... a[4] { w += colPx(c) } }
                if a[6] >= a[2] { for r in a[2] ... a[6] { h += rowPt(r) } }
                let x0 = colPx(a[0]) * Double(a[1]) / 1024, x1 = colPx(a[4]) * Double(a[5]) / 1024
                let y0 = rowPt(a[2]) * Double(a[3]) / 256, y1 = rowPt(a[6]) * Double(a[7]) / 256
                let cx = emu((w - x0 - (colPx(a[4]) - x1)) * 9525), cy = emu((h - y0 - (rowPt(a[6]) - y1)) * 12700)
                let head = "<xdr:twoCellAnchor editAs=\"oneCell\"><xdr:from><xdr:col>\(a[0])</xdr:col><xdr:colOff>\(emu(x0 * 9525))</xdr:colOff><xdr:row>\(a[2])</xdr:row><xdr:rowOff>\(emu(y0 * 12700))</xdr:rowOff></xdr:from><xdr:to><xdr:col>\(a[4])</xdr:col><xdr:colOff>\(emu(x1 * 9525))</xdr:colOff><xdr:row>\(a[6])</xdr:row><xdr:rowOff>\(emu(y1 * 12700))</xdr:rowOff></xdr:to>"
                if sh.type == 20, sh.pib == 0 {
                    // A straight line (msosptLine): its colour and width are the shape's own, black and 0.75 pt when it names none.
                    let lc = sh.props[0x1C0] ?? 0x8000040
                    let hex = lc >> 24 == 0 ? [lc & 255, lc >> 8 & 255, lc >> 16 & 255].map { (v: Int) -> String in let d = Array("0123456789ABCDEF"); return String([d[v >> 4], d[v & 15]]) }.joined() : "000000"
                    let lw = sh.props[0x1CB] ?? 9525
                    if let flags = sh.props[0x1FF], flags & 8 == 0 { continue }
                    let wh = max(0, (w - x0 - (colPx(a[4]) - x1)) * 9525), hh = max(0, (h - y0 - (rowPt(a[6]) - y1)) * 12700)
                    drawing.anchors.append(head + "<xdr:sp macro=\"\" textlink=\"\"><xdr:nvSpPr><xdr:cNvPr id=\"\(sh.id)\" name=\"Line \(sh.id)\"/><xdr:cNvSpPr/></xdr:nvSpPr><xdr:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(emu(wh))\" cy=\"\(emu(hh))\"/></a:xfrm><a:prstGeom prst=\"line\"><a:avLst/></a:prstGeom><a:noFill/><a:ln w=\"\(lw)\"><a:solidFill><a:srgbClr val=\"\(hex)\"/></a:solidFill></a:ln></xdr:spPr></xdr:sp><xdr:clientData/></xdr:twoCellAnchor>")
                    continue
                }
                if isChart {
                    drawing.anchors.append(head + "<xdr:graphicFrame macro=\"\"><xdr:nvGraphicFramePr><xdr:cNvPr id=\"\(sh.id)\" name=\"Chart \(chartNo)\"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></xdr:xfrm><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" r:id=\"@CHART\(chartNo - 1)@\"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>")
                } else {
                    drawing.anchors.append(head + "<xdr:pic><xdr:nvPicPr><xdr:cNvPr id=\"\(sh.id)\" name=\"Picture \(drawing.anchors.count + 1)\"/><xdr:cNvPicPr/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed=\"rId\(slot + 1)\"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:twoCellAnchor>")
                }
            }
            if !drawing.pics.isEmpty || !drawing.anchors.isEmpty { x += "<drawing r:id=\"rIdD1\"/>" }
        }
        return x + "</worksheet>"
    }

    // MARK: Page setup and defined names

    static func pageXML(setup: [Int: Int], margins: [Double?], hdrFtr: [String?], margin2: (Double, Double)?, grid: Bool, heads: Bool, hc: Bool, vc: Bool,
                        hBreaks: [(Int, Int, Int)], vBreaks: [(Int, Int, Int)]) -> String {
        var x = ""
        var po = ""
        if hc { po += " horizontalCentered=\"1\"" }
        if vc { po += " verticalCentered=\"1\"" }
        if heads { po += " headings=\"1\"" }
        if grid { po += " gridLines=\"1\"" }
        if !po.isEmpty { x += "<printOptions\(po)/>" }
        let m: [Double] = [margins[0] ?? 0.75, margins[1] ?? 0.75, margins[2] ?? 1.0, margins[3] ?? 1.0]
        let h = margin2?.0 ?? 0.5, f = margin2?.1 ?? 0.5
        x += "<pageMargins left=\"\(num(m[0]))\" right=\"\(num(m[1]))\" top=\"\(num(m[2]))\" bottom=\"\(num(m[3]))\" header=\"\(num(h))\" footer=\"\(num(f))\"/>"
        if let g = setup[5] {
            var a = ""
            // fNoPls: the printer settings are not valid, so paper, scale and fit counts mean nothing.
            let noPls = g & 4 != 0
            let paper = noPls ? 0 : (setup[0] ?? 0)
            if paper != 0 { a += " paperSize=\"\(paper)\"" }
            let scale = noPls ? 100 : (setup[1] ?? 100)
            if scale != 100, scale >= 10, scale <= 400 { a += " scale=\"\(scale)\"" }
            if g & 0x80 != 0 {
                let n = Int16(truncatingIfNeeded: setup[2] ?? 1)
                if n != 1 { a += " firstPageNumber=\"\(n)\"" }
                a += " useFirstPageNumber=\"1\""
            }
            if !noPls, setup[3] ?? 1 != 1 { a += " fitToWidth=\"\(setup[3] ?? 1)\"" }
            if !noPls, setup[4] ?? 1 != 1 { a += " fitToHeight=\"\(setup[4] ?? 1)\"" }
            if g & 1 != 0 { a += " pageOrder=\"overThenDown\"" }
            if g & 4 == 0, g & 0x40 == 0 { a += " orientation=\"\(g & 2 != 0 ? "portrait" : "landscape")\"" } else { a += " orientation=\"portrait\"" }
            if g & 8 != 0 { a += " blackAndWhite=\"1\"" }
            if g & 0x10 != 0 { a += " draft=\"1\"" }
            x += "<pageSetup\(a)/>"
        }
        if hdrFtr[0] != nil || hdrFtr[1] != nil {
            x += "<headerFooter>"
            if let t = hdrFtr[0] { x += "<oddHeader>\(esc(t))</oddHeader>" }
            if let t = hdrFtr[1] { x += "<oddFooter>\(esc(t))</oddFooter>" }
            x += "</headerFooter>"
        }
        if !hBreaks.isEmpty {
            x += "<rowBreaks count=\"\(hBreaks.count)\" manualBreakCount=\"\(hBreaks.count)\">" + hBreaks.map { "<brk id=\"\($0.0)\" min=\"\($0.1)\" max=\"\($0.2)\" man=\"1\"/>" }.joined() + "</rowBreaks>"
        }
        if !vBreaks.isEmpty {
            x += "<colBreaks count=\"\(vBreaks.count)\" manualBreakCount=\"\(vBreaks.count)\">" + vBreaks.map { "<brk id=\"\($0.0)\" min=\"\($0.1)\" max=\"\($0.2)\" man=\"1\"/>" }.joined() + "</colBreaks>"
        }
        return x
    }

    static func quotedSheet(_ n: String) -> String {
        let plain = !n.isEmpty && n.unicodeScalars.allSatisfy { $0.properties.isAlphabetic || $0 == "_" || ("0" ... "9").contains($0) } && !(("0" ... "9").contains(n.unicodeScalars.first!))
        if plain { return n }
        var q = ""
        for ch in n { q += ch == "'" ? "''" : String(ch) }
        return "'" + q + "'"
    }

    /// Print areas, print titles and filter ranges: the ranges of a NAME formula (BIFF8 ptg tokens 0x3A/0x3B reference an EXTERNSHEET entry).
    static func nameText(_ r: BiffRecord) -> String {
        guard r.body.count >= 14 else { return "" }
        var c = BiffCursor(r)
        let flags = c.u16(); c.skip(1)
        let cch = c.u8()
        c.skip(10)
        if flags & 0x20 != 0 {
            c.skip(1)
            switch c.u8() { case 6: return "_xlnm.Print_Area"; case 7: return "_xlnm.Print_Titles"; case 0xD: return "_xlnm._FilterDatabase"; default: return "" }
        }
        let f = c.u8()
        return c.chars(cch, wide: f & 1 == 1)
    }

    static func cellRange(_ r1: Int, _ c1: Int, _ r2: Int, _ c2: Int) -> String {
        let a = colName(c1) + String(r1 + 1)
        return r1 == r2 && c1 == c2 ? a : a + ":" + colName(c2) + String(r2 + 1)
    }

    static func definedNamesXML(_ recs: [BiffRecord], xtis: [(Int, Int)], sheetNames: [String], kept: [Int], xtiSheets: [(Int, Int)]? = nil) -> String {
        var out = ""
        for r in recs where r.body.count >= 14 {
            var c = BiffCursor(r)
            let flags = c.u16(); c.skip(1)
            let cch = c.u8(), cce = c.u16()
            c.skip(2)
            let itab = c.u16()
            c.skip(4)
            var name = ""
            var builtin = -1
            if flags & 0x20 != 0 {
                c.skip(1); builtin = c.u8()
                switch builtin { case 6: name = "_xlnm.Print_Area"; case 7: name = "_xlnm.Print_Titles"; case 0xD: name = "_xlnm._FilterDatabase"; default: continue }
            } else {
                let f = c.u8(); name = c.chars(cch, wide: f & 1 == 1)
                // A plain name spelled like a built-in one is that built-in (Excel's own conversion does the same).
                for b in ["Print_Area", "Print_Titles", "_FilterDatabase"] where name.lowercased() == b.lowercased() { name = "_xlnm." + b }
            }
            let end = min(r.body.count, c.pos + cce)
            guard let text = formulaRanges(Array(r.body[c.pos ..< end]), xtis: xtis, sheetNames: sheetNames), !text.isEmpty else { continue }
            var a = ""
            if itab > 0 {
                guard let k = kept.firstIndex(of: itab - 1) else { continue }
                a += " localSheetId=\"\(k)\""
            }
            if flags & 1 != 0 { a += " hidden=\"1\"" }
            out += "<definedName name=\"\(esc(name))\"\(a)>\(esc(text))</definedName>"
        }
        return out.isEmpty ? "" : "<definedNames>" + out + "</definedNames>"
    }

    private static func cellRef(_ r: Int, _ c: Int, rowAbs: Bool, colAbs: Bool) -> String {
        (colAbs ? "$" : "") + colName(c & 0x3FFF) + (rowAbs ? "$" : "") + String(r + 1)
    }

    /// A formula made only of 3-D area/reference tokens and unions; nil for anything else.
    static func formulaRanges(_ t: [UInt8], xtis: [(Int, Int)], sheetNames: [String]) -> String? {
        var out: [String] = []
        var i = 0
        func u16(_ k: Int) -> Int { k + 1 < t.count ? Int(t[k]) | Int(t[k + 1]) << 8 : 0 }
        func sheetPrefix(_ ixti: Int) -> String? {
            guard ixti < xtis.count else { return nil }
            let n = xtis[ixti].0
            guard n < sheetNames.count else { return nil }
            return quotedSheet(sheetNames[n]) + "!"
        }
        while i < t.count {
            switch t[i] & 0x7F {
            case 0x3B where i + 11 <= t.count:
                guard let pre = sheetPrefix(u16(i + 1)) else { return nil }
                let r1 = u16(i + 3), r2 = u16(i + 5), c1 = u16(i + 7), c2 = u16(i + 9)
                let a = cellRef(r1, c1, rowAbs: c1 & 0x8000 == 0, colAbs: c1 & 0x4000 == 0)
                let b = cellRef(r2, c2, rowAbs: c2 & 0x8000 == 0, colAbs: c2 & 0x4000 == 0)
                if r1 == 0, r2 == 0xFFFF {
                    out.append(pre + "$" + colName(c1 & 0x3FFF) + ":$" + colName(c2 & 0x3FFF))
                } else if c1 & 0x3FFF == 0, c2 & 0x3FFF == 0xFF {
                    out.append(pre + "$" + String(r1 + 1) + ":$" + String(r2 + 1))
                } else { out.append(pre + a + ":" + b) }
                i += 11
            case 0x3A where i + 7 <= t.count:
                guard let pre = sheetPrefix(u16(i + 1)) else { return nil }
                let c1 = u16(i + 5)
                out.append(pre + cellRef(u16(i + 3), c1, rowAbs: c1 & 0x8000 == 0, colAbs: c1 & 0x4000 == 0))
                i += 7
            case 0x10: i += 1
            case 0x29: i += 1
            default: return nil
            }
        }
        return out.joined(separator: ",")
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
            // (A fill the cell XF carries itself prints though its "used" flag is clear: some writers never set it, and Excel shows the grey: xls-508d6f5812's label column.)
            if x.indent & 0x4000 == 0, x.borderColor2 >> 26 == 0 {
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

    static func styleBody(fonts: [XlsFont], xfs: [XlsXF], palette: [(Int, Int, Int)], xfExt: [Int: (fg: String?, bg: String?)] = [:]) -> String {
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
            fx += "<sz val=\"\(f.height >= 20 ? Double(f.height) / 20 : 10.0)\"/>"
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
        for (xi, x) in list.enumerated() {
            // fill
            let pat = Int(x.borderColor2 >> 26) & 0x3F
            var fillId = 0
            if pat > 0, pat < patterns.count {
                let fg = Int(x.fill) & 0x7F, bg = Int(x.fill >> 7) & 0x7F
                let ext = xfExt[xi]
                let fgTag = ext?.fg.map { "<fgColor rgb=\"FF\($0)\"/>" } ?? colorTag("fgColor", fg == 64 ? 0 : fg, palette)
                let bgTag = ext?.bg.map { "<bgColor rgb=\"FF\($0)\"/>" } ?? colorTag("bgColor", bg == 65 ? 1 : bg, palette)
                let f = "<fill><patternFill patternType=\"\(patterns[pat])\">" + fgTag + bgTag + "</patternFill></fill>"
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
