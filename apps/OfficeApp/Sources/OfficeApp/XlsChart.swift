// Legacy .xls charts: the BIFF chart substream of an embedded chart object
// becomes an ordinary chart part (chartSpace XML), which the xlsx reader draws.
// Shared code (also built for the web): no legacy Foundation calls.

import Foundation

/// A rectangle of cells of one sheet.
struct XlsChartRef {
    var sheet = 0, r1 = 0, c1 = 0, r2 = 0, c2 = 0
}

/// One series as the chart substream describes it.
private struct XlsSer {
    var name: XlsChartRef? = nil
    var nameText: String? = nil
    var cats: XlsChartRef? = nil
    var vals: XlsChartRef? = nil
    var catText = false          // the categories are text
    var group = 0
    var line: (rgb: String, style: Int, weight: Int, auto: Bool)? = nil
    var fill: (rgb: String, pattern: Int, auto: Bool)? = nil
    var marker: (type: Int, size: Int, fg: String, bg: String)? = nil
    var points: [Int: String] = [:]      // data point index → fill colour
    var showVal = false, showCat = false, showPct = false
    var smooth = false
    var parent = -1                      // a trendline's own pseudo-series: the series it belongs to
    var trend: (type: Int, order: Int, fwd: Double, back: Double, eq: Bool, rsq: Bool)? = nil
    var trends: [XlsSer] = []
}

private struct XlsGrp {
    var type = 0                 // 0x1017 bar, 0x1018 line, 0x1019 pie, 0x101a area, 0x101b scatter
    var flags = 0
    var gap = 150, overlap = 0
    var angle = 0, donut = 0
}

private struct XlsAx {
    var type = 0
    var min: Double? = nil, max: Double? = nil, major: Double? = nil, minor: Double? = nil
    var log = false, reverse = false, between = true
    var marks = (major: 2, minor: 0), labelPos = 3
    var grid = false, minorGrid = false
    var line: String? = nil
    var title: String? = nil
}

enum XlsChart {
    static func decodeRef(_ t: [UInt8], ctx: XlsFormulaContext) -> XlsChartRef? {
        func u16(_ k: Int) -> Int { k + 1 < t.count ? Int(t[k]) | Int(t[k + 1]) << 8 : 0 }
        guard let op = t.first else { return nil }
        func sheet(_ ixti: Int) -> Int? { ixti < ctx.xtis.count ? ctx.xtis[ixti].0 : nil }
        switch op & 0x7F {
        case 0x3B where t.count >= 11:
            guard let s = sheet(u16(1)) else { return nil }
            return XlsChartRef(sheet: s, r1: u16(3), c1: u16(7) & 0xFF, r2: u16(5), c2: u16(9) & 0xFF)
        case 0x3A where t.count >= 7:
            guard let s = sheet(u16(1)) else { return nil }
            return XlsChartRef(sheet: s, r1: u16(3), c1: u16(5) & 0xFF, r2: u16(3), c2: u16(5) & 0xFF)
        default: return nil
        }
    }

    static func refText(_ r: XlsChartRef, names: [String]) -> String {
        let n = r.sheet < names.count ? names[r.sheet] : "Sheet1"
        let a = "$" + XlsBuild.colName(r.c1) + "$" + String(r.r1 + 1)
        let b = "$" + XlsBuild.colName(r.c2) + "$" + String(r.r2 + 1)
        return XlsBuild.quotedSheet(n) + "!" + (a == b ? a : a + ":" + b)
    }

    private static func hex(_ b: [UInt8], _ o: Int) -> String {
        guard o + 3 <= b.count else { return "000000" }
        let d = Array("0123456789ABCDEF")
        return [b[o], b[o + 1], b[o + 2]].map { String([d[Int($0) >> 4], d[Int($0) & 15]]) }.joined()
    }

    /// The chart part for one chart substream, or nil when its kind is not supported.
    /// `cell` gives the cached text of a cell and whether it is a number.
    static func build(_ recs: [BiffRecord], ctx: XlsFormulaContext, fontHeights: [Int], cell: (Int, Int, Int) -> (String, Bool)?) -> String? {
        var series: [XlsSer] = []
        var groups: [XlsGrp] = []
        var axes: [XlsAx] = []
        var curSeries = -1, curAxis = -1
        var titles: [Int: (String, Int)] = [:]          // object link (1 chart, 2 y axis, 3 x axis) → text, font height
        var pendingText: String? = nil
        var pendingFont = 0
        var legend: (pos: Int, rect: [Int])? = nil
        var plot: [Int]? = nil
        var dfSeries = -1, dfPoint = -1           // the data format being read
        var inGroup = false
        var axisParent = 0

        func u16(_ b: [UInt8], _ o: Int) -> Int { o + 1 < b.count && o >= 0 ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
        func i16(_ b: [UInt8], _ o: Int) -> Int { let v = u16(b, o); return v >= 0x8000 ? v - 0x10000 : v }
        func f64(_ b: [UInt8], _ o: Int) -> Double {
            guard o + 8 <= b.count else { return 0 }
            var v: UInt64 = 0
            for k in 0 ..< 8 { v |= UInt64(b[o + k]) << UInt64(8 * k) }
            return Double(bitPattern: v)
        }

        for r in recs {
            let b = r.body
            switch r.type {
            case 0x1003:
                var s = XlsSer()
                s.catText = u16(b, 0) == 3
                series.append(s); curSeries = series.count - 1; curAxis = -1; pendingText = nil
            case 0x1051 where b.count >= 8:
                guard curSeries >= 0, pendingText == nil, !inGroup else { break }
                let id = Int(b[0]), kind = Int(b[1]), cce = u16(b, 6)
                guard kind == 2, 8 + cce <= b.count else { break }
                let ref = decodeRef(Array(b[8 ..< 8 + cce]), ctx: ctx)
                switch id {
                case 0: series[curSeries].name = ref
                case 2: series[curSeries].cats = ref
                case 1: series[curSeries].vals = ref
                default: break
                }
            case 0x100D:
                // SERIESTEXT: id, then a length-prefixed string.
                let n = Int(b.count > 2 ? b[2] : 0), wide = b.count > 3 && b[3] & 1 == 1
                var s = ""
                if wide { var k = 0; while k < n, 4 + 2 * k + 1 < b.count { s.unicodeScalars.append(Unicode.Scalar(UInt32(u16(b, 4 + 2 * k))) ?? " "); k += 1 } }
                else { var k = 0; while k < n, 4 + k < b.count { s.unicodeScalars.append(Unicode.Scalar(b[4 + k])); k += 1 } }
                if pendingText != nil || curSeries < 0 || curAxis >= 0 { pendingText = s }
                else if series[curSeries].name == nil, series[curSeries].nameText == nil { series[curSeries].nameText = s }
            case 0x1025:
                pendingText = ""; pendingFont = 0; curAxis = -1
            case 0x1026 where pendingText != nil:
                pendingFont = u16(b, 0)
            case 0x1027 where pendingText != nil:
                if let t = pendingText, !t.isEmpty { titles[u16(b, 0)] = (t, pendingFont) }
                pendingText = nil
            case 0x104A where curSeries >= 0: series[curSeries].parent = u16(b, 0) - 1
            case 0x104B where curSeries >= 0 && b.count >= 28:
                func f64(_ k: Int) -> Double { var v: UInt64 = 0; for j in 0 ..< 8 { v |= UInt64(b[k + j]) << UInt64(8 * j) }; return Double(bitPattern: v) }
                series[curSeries].trend = (Int(b[0]), Int(b[1]), f64(12), f64(20), b[10] != 0, b[11] != 0)
            case 0x1045: if curSeries >= 0 { series[curSeries].group = u16(b, 0) }
            case 0x1014:
                groups.append(XlsGrp()); inGroup = true; curSeries = -1
            case 0x1017 where !groups.isEmpty:
                groups[groups.count - 1].type = 0x1017; groups[groups.count - 1].overlap = i16(b, 0); groups[groups.count - 1].gap = u16(b, 2)
                // Bar flags: bit 0 horizontal, bit 1 stacked, bit 2 100%; the emitter reads stacked as bit 0, 100% as bit 1, horizontal as bit 2.
                let raw = u16(b, 4)
                groups[groups.count - 1].flags = (raw & 1) << 2 | (raw >> 1) & 3
            case 0x1018 where !groups.isEmpty, 0x101A where !groups.isEmpty:
                groups[groups.count - 1].type = Int(r.type); groups[groups.count - 1].flags = u16(b, 0)
            case 0x1019 where !groups.isEmpty:
                groups[groups.count - 1].type = 0x1019; groups[groups.count - 1].angle = u16(b, 0); groups[groups.count - 1].donut = u16(b, 2)
            case 0x101B where !groups.isEmpty:
                groups[groups.count - 1].type = 0x101B
            case 0x103C where !groups.isEmpty, 0x103E where !groups.isEmpty, 0x103F where !groups.isEmpty:
                groups[groups.count - 1].type = Int(r.type)
            case 0x1041: axisParent = u16(b, 0)
                if axisParent == 0, b.count >= 18 { plot = [u16(b, 2) | u16(b, 4) << 16, u16(b, 6) | u16(b, 8) << 16, u16(b, 10) | u16(b, 12) << 16, u16(b, 14) | u16(b, 16) << 16] }
            case 0x101D where axisParent == 0:
                var a = XlsAx(); a.type = u16(b, 0); axes.append(a); curAxis = axes.count - 1
            case 0x1020 where curAxis >= 0:
                axes[curAxis].between = u16(b, 6) & 1 == 1
                axes[curAxis].reverse = u16(b, 6) & 4 != 0
            case 0x101F where curAxis >= 0 && b.count >= 42:
                let fl = u16(b, 40)
                if fl & 1 == 0 { axes[curAxis].min = f64(b, 0) }
                if fl & 2 == 0 { axes[curAxis].max = f64(b, 8) }
                if fl & 4 == 0 { axes[curAxis].major = f64(b, 16) }
                if fl & 8 == 0 { axes[curAxis].minor = f64(b, 24) }
                axes[curAxis].log = fl & 0x20 != 0
                axes[curAxis].reverse = fl & 0x40 != 0
            case 0x101E where curAxis >= 0:
                axes[curAxis].marks = (b.count > 0 ? Int(b[0]) : 2, b.count > 1 ? Int(b[1]) : 0)
                axes[curAxis].labelPos = b.count > 2 ? Int(b[2]) : 3
            case 0x1021 where curAxis >= 0:
                let k = u16(b, 0)
                if k == 1 { axes[curAxis].grid = true } else if k == 2 { axes[curAxis].minorGrid = true }
            case 0x1015 where b.count >= 20:
                legend = (Int(b[16]), [u16(b, 0) | u16(b, 2) << 16, u16(b, 4) | u16(b, 6) << 16, u16(b, 8) | u16(b, 10) << 16, u16(b, 12) | u16(b, 14) << 16])
            case 0x1006 where b.count >= 4:
                dfPoint = u16(b, 0) == 0xFFFF ? -1 : u16(b, 0); dfSeries = u16(b, 2)
            case 0x1066 where dfSeries >= 0 && dfSeries < series.count && dfPoint < 0 && b.count >= 8:
                // The 2007 shape properties: their fill colour (pid 0x181) is the one Excel draws, over the palette colour of the area record.
                for rec in OfficeArt.records(b, in: 0 ..< b.count) where rec.type == 0xF00B {
                    for k in 0 ..< rec.inst {
                        let o = rec.body.lowerBound + 6 * k
                        guard o + 6 <= rec.body.upperBound else { break }
                        if OfficeArt.u16(b, o) & 0x3FFF == 0x181, let f = series[dfSeries].fill {
                            series[dfSeries].fill = (hex(b, o + 2), f.1, f.2)
                        }
                    }
                }
            case 0x1007 where dfSeries >= 0 && dfSeries < series.count && dfPoint < 0:
                series[dfSeries].line = (hex(b, 0), u16(b, 4), i16(b, 6), u16(b, 8) & 1 == 1)
            case 0x100A where dfSeries >= 0 && dfSeries < series.count:
                if dfPoint >= 0 { series[dfSeries].points[dfPoint] = hex(b, 0) }
                else { series[dfSeries].fill = (hex(b, 0), u16(b, 8), u16(b, 10) & 1 == 1) }
            case 0x1009 where dfSeries >= 0 && dfSeries < series.count && dfPoint < 0 && b.count >= 20:
                series[dfSeries].marker = (u16(b, 8), (u16(b, 16) | u16(b, 18) << 16) / 20, hex(b, 0), hex(b, 4))
            case 0x100C where dfSeries >= 0 && dfSeries < series.count && dfPoint < 0:
                let fl = u16(b, 0)
                series[dfSeries].showVal = fl & 1 != 0; series[dfSeries].showPct = fl & 2 != 0 || fl & 4 != 0; series[dfSeries].showCat = fl & 8 != 0
            case 0x105D where dfSeries >= 0 && dfSeries < series.count:
                series[dfSeries].smooth = u16(b, 0) & 1 != 0
            default: break
            }
        }
        for i in series.indices.reversed() where series[i].parent >= 0 && series[i].parent < series.count && series[i].parent != i && series[i].trend != nil {
            series[series[i].parent].trends.insert(series[i], at: 0)
        }
        guard !series.isEmpty, !groups.isEmpty else { return nil }
        let supported: Set<Int> = [0x1017, 0x1018, 0x1019, 0x101A, 0x101B]
        guard groups.allSatisfy({ supported.contains($0.type) }) else { return nil }

        func esc(_ s: String) -> String { XlsBuild.esc(s) }
        func cache(_ r: XlsChartRef, numeric: Bool) -> String {
            var pts = "", n = 0
            for rr in r.r1 ... max(r.r1, r.r2) {
                for cc in r.c1 ... max(r.c1, r.c2) {
                    if let (t, isNum) = cell(r.sheet, rr, cc) {
                        if numeric ? isNum : true { pts += "<c:pt idx=\"\(n)\"><c:v>\(esc(t))</c:v></c:pt>" }
                    }
                    n += 1
                }
            }
            return numeric ? "<c:numCache><c:formatCode>General</c:formatCode><c:ptCount val=\"\(n)\"/>\(pts)</c:numCache>" : "<c:strCache><c:ptCount val=\"\(n)\"/>\(pts)</c:strCache>"
        }
        func ref(_ r: XlsChartRef, numeric: Bool) -> String {
            (numeric ? "<c:numRef>" : "<c:strRef>") + "<c:f>" + esc(refText(r, names: ctx.sheetNames)) + "</c:f>" + cache(r, numeric: numeric) + (numeric ? "</c:numRef>" : "</c:strRef>")
        }
        func solid(_ c: String) -> String { "<a:solidFill><a:srgbClr val=\"\(c)\"/></a:solidFill>" }
        func lineProps(_ l: (rgb: String, style: Int, weight: Int, auto: Bool)) -> String {
            if l.style == 5 { return "<a:ln><a:noFill/></a:ln>" }
            let w = l.weight < 0 ? 3175 : 12700 * (l.weight + 1)
            let dash = ["solid", "dash", "sysDot", "dashDot", "lgDashDotDot"][l.style >= 0 && l.style < 5 ? l.style : 0]
            return "<a:ln w=\"\(w)\">\(solid(l.rgb))<a:prstDash val=\"\(dash)\"/></a:ln>"
        }
        func richTitle(_ t: String, _ font: Int) -> String {
            let sz = font >= 0 && font < fontHeights.count && fontHeights[font] > 0 ? fontHeights[font] * 5 : 1000
            return "<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz=\"\(sz)\"/></a:pPr><a:r><a:rPr lang=\"en-US\" sz=\"\(sz)\"/><a:t>\(esc(t))</a:t></a:r></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title>"
        }
        func manual(_ r: [Int], target: Bool) -> String {
            guard r.count == 4, r[2] > 0, r[3] > 0 else { return "" }
            func f(_ v: Int) -> String { String(Double(v) / 4000) }
            return "<c:layout><c:manualLayout>" + (target ? "<c:layoutTarget val=\"inner\"/>" : "") + "<c:xMode val=\"edge\"/><c:yMode val=\"edge\"/><c:x val=\"\(f(r[0]))\"/><c:y val=\"\(f(r[1]))\"/><c:w val=\"\(f(r[2]))\"/><c:h val=\"\(f(r[3]))\"/></c:manualLayout></c:layout>"
        }

        var plotXML = ""
        let catAxId = 111_111, valAxId = 222_222
        var usesAxes = false
        for (gi, g) in groups.enumerated() {
            let members = series.enumerated().filter { $0.element.group == gi && !($0.element.parent >= 0 && $0.element.trend != nil) }
            guard !members.isEmpty else { continue }
            let isPie = g.type == 0x1019, isScatter = g.type == 0x101B, isLine = g.type == 0x1018, isBar = g.type == 0x1017
            var sers = ""
            for (k, (_, s)) in members.enumerated() {
                var x = "<c:ser><c:idx val=\"\(k)\"/><c:order val=\"\(k)\"/>"
                if let n = s.name { x += "<c:tx>" + ref(n, numeric: false) + "</c:tx>" }
                else if let t = s.nameText { x += "<c:tx><c:v>\(esc(t))</c:v></c:tx>" }
                // Shape properties: a line chart's series is its line; a bar's, its fill.
                if isLine || isScatter {
                    if let l = s.line { x += "<c:spPr>" + lineProps(l) + "</c:spPr>" }
                } else if let f = s.fill {
                    x += "<c:spPr>" + (f.pattern == 0 ? "<a:noFill/>" : solid(f.rgb)) + (s.line.map { lineProps($0) } ?? "") + "</c:spPr>"
                }
                if isBar { x += "<c:invertIfNegative val=\"0\"/>" }
                if isLine || isScatter {
                    if let m = s.marker, m.type > 0 {
                        let sym = ["none", "square", "diamond", "triangle", "x", "star", "dot", "dash", "circle", "plus"][min(m.type, 9)]
                        x += "<c:marker><c:symbol val=\"\(sym)\"/><c:size val=\"\(max(2, min(72, m.size)))\"/><c:spPr>\(solid(m.fg))<a:ln>\(solid(m.bg))</a:ln></c:spPr></c:marker>"
                    } else { x += "<c:marker><c:symbol val=\"none\"/></c:marker>" }
                }
                for p in s.points.keys.sorted() { x += "<c:dPt><c:idx val=\"\(p)\"/><c:bubble3D val=\"0\"/><c:spPr>\(solid(s.points[p] ?? "000000"))</c:spPr></c:dPt>" }
                if s.showVal || s.showCat || s.showPct {
                    x += "<c:dLbls><c:showLegendKey val=\"0\"/><c:showVal val=\"\(s.showVal ? 1 : 0)\"/><c:showCatName val=\"\(s.showCat ? 1 : 0)\"/><c:showSerName val=\"0\"/><c:showPercent val=\"\(s.showPct ? 1 : 0)\"/><c:showBubbleSize val=\"0\"/></c:dLbls>"
                }
                for t in s.trends {
                    guard let tr = t.trend else { continue }
                    let kind = ["poly", "exp", "log", "power", "movingAvg"][min(tr.type, 4)]
                    x += "<c:trendline>" + (t.line.map { "<c:spPr>" + lineProps($0) + "</c:spPr>" } ?? "")
                    x += "<c:trendlineType val=\"\(kind == "poly" && tr.order <= 1 ? "linear" : kind)\"/>"
                    if kind == "poly" && tr.order > 1 { x += "<c:order val=\"\(tr.order)\"/>" }
                    if kind == "movingAvg" { x += "<c:period val=\"\(max(2, tr.order))\"/>" }
                    if tr.fwd.isFinite && tr.fwd != 0 { x += "<c:forward val=\"\(tr.fwd)\"/>" }
                    if tr.back.isFinite && tr.back != 0 { x += "<c:backward val=\"\(tr.back)\"/>" }
                    x += "<c:dispRSqr val=\"\(tr.rsq ? 1 : 0)\"/><c:dispEq val=\"\(tr.eq ? 1 : 0)\"/></c:trendline>"
                }
                if isScatter {
                    if let c = s.cats { x += "<c:xVal>" + ref(c, numeric: true) + "</c:xVal>" }
                    if let v = s.vals { x += "<c:yVal>" + ref(v, numeric: true) + "</c:yVal>" }
                    x += "<c:smooth val=\"\(s.smooth ? 1 : 0)\"/>"
                } else {
                    if let c = s.cats { x += "<c:cat>" + ref(c, numeric: !s.catText) + "</c:cat>" }
                    if let v = s.vals { x += "<c:val>" + ref(v, numeric: true) + "</c:val>" }
                    if isLine { x += "<c:smooth val=\"\(s.smooth ? 1 : 0)\"/>" }
                }
                sers += x + "</c:ser>"
            }
            let grouping = g.flags & 2 != 0 ? "percentStacked" : g.flags & 1 != 0 ? "stacked" : "clustered"
            let axRefs = "<c:axId val=\"\(catAxId)\"/><c:axId val=\"\(valAxId)\"/>"
            switch g.type {
            case 0x1017:
                let stacked = g.flags & 3 != 0
                plotXML += "<c:barChart><c:barDir val=\"\(g.flags & 4 != 0 ? "bar" : "col")\"/><c:grouping val=\"\(grouping)\"/><c:varyColors val=\"0\"/>\(sers)<c:gapWidth val=\"\(g.gap)\"/>" + (stacked ? "<c:overlap val=\"100\"/>" : g.overlap != 0 ? "<c:overlap val=\"\(-g.overlap)\"/>" : "") + axRefs + "</c:barChart>"
                usesAxes = true
            case 0x1018:
                plotXML += "<c:lineChart><c:grouping val=\"\(g.flags & 2 != 0 ? "percentStacked" : g.flags & 1 != 0 ? "stacked" : "standard")\"/><c:varyColors val=\"0\"/>\(sers)<c:marker val=\"1\"/>" + axRefs + "</c:lineChart>"
                usesAxes = true
            case 0x101A:
                plotXML += "<c:areaChart><c:grouping val=\"\(g.flags & 2 != 0 ? "percentStacked" : g.flags & 1 != 0 ? "stacked" : "standard")\"/><c:varyColors val=\"0\"/>\(sers)" + axRefs + "</c:areaChart>"
                usesAxes = true
            case 0x101B:
                plotXML += "<c:scatterChart><c:scatterStyle val=\"lineMarker\"/><c:varyColors val=\"0\"/>\(sers)" + axRefs + "</c:scatterChart>"
                usesAxes = true
            default:
                if g.donut > 0 { plotXML += "<c:doughnutChart><c:varyColors val=\"1\"/>\(sers)<c:firstSliceAng val=\"\(g.angle)\"/><c:holeSize val=\"\(g.donut)\"/></c:doughnutChart>" }
                else { plotXML += "<c:pieChart><c:varyColors val=\"1\"/>\(sers)<c:firstSliceAng val=\"\(g.angle)\"/></c:pieChart>" }
            }
        }
        guard !plotXML.isEmpty else { return nil }

        let scatter = groups.contains { $0.type == 0x101B }
        let horizontal = groups.contains { $0.type == 0x1017 && $0.flags & 4 != 0 }
        if usesAxes {
            func axis(_ a: XlsAx?, cat: Bool, id: Int, cross: Int, pos: String) -> String {
                let a = a ?? XlsAx()
                var x = cat ? "<c:catAx>" : "<c:valAx>"
                x += "<c:axId val=\"\(id)\"/><c:scaling>" + (a.log ? "<c:logBase val=\"10\"/>" : "") + "<c:orientation val=\"\(a.reverse ? "maxMin" : "minMax")\"/>"
                if let m = a.max { x += "<c:max val=\"\(m)\"/>" }
                if let m = a.min { x += "<c:min val=\"\(m)\"/>" }
                x += "</c:scaling><c:delete val=\"0\"/><c:axPos val=\"\(pos)\"/>"
                if a.grid { x += "<c:majorGridlines/>" }
                if a.minorGrid { x += "<c:minorGridlines/>" }
                let link = (cat && !scatter) || (scatter && cat) ? 3 : 2
                if let t = titles[horizontal ? (link == 3 ? 2 : 3) : link] { x += richTitle(t.0, t.1) }
                x += "<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/>"
                func mark(_ v: Int) -> String { v == 1 ? "in" : v == 2 ? "out" : v == 3 ? "cross" : "none" }
                x += "<c:majorTickMark val=\"\(mark(a.marks.major))\"/><c:minorTickMark val=\"\(mark(a.marks.minor))\"/>"
                x += "<c:tickLblPos val=\"\(a.labelPos == 0 ? "none" : a.labelPos == 1 ? "low" : a.labelPos == 2 ? "high" : "nextTo")\"/>"
                x += "<c:crossAx val=\"\(cross)\"/><c:crosses val=\"autoZero\"/>"
                if cat { x += "<c:auto val=\"1\"/><c:lblAlgn val=\"ctr\"/><c:lblOffset val=\"100\"/><c:noMultiLvlLbl val=\"0\"/>" }
                else {
                    x += "<c:crossBetween val=\"\((axes.first { $0.type == 0 }?.between ?? true) && !scatter ? "between" : "midCat")\"/>"
                    if let m = a.major { x += "<c:majorUnit val=\"\(m)\"/>" }
                    if let m = a.minor { x += "<c:minorUnit val=\"\(m)\"/>" }
                }
                return x + (cat ? "</c:catAx>" : "</c:valAx>")
            }
            let catA = axes.first { $0.type == 0 }, valA = axes.first { $0.type == 1 }
            if scatter {
                plotXML += axis(catA, cat: false, id: catAxId, cross: valAxId, pos: "b") + axis(valA, cat: false, id: valAxId, cross: catAxId, pos: "l")
            } else {
                plotXML += axis(catA, cat: true, id: catAxId, cross: valAxId, pos: horizontal ? "l" : "b") + axis(valA, cat: false, id: valAxId, cross: catAxId, pos: horizontal ? "b" : "l")
            }
        }
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><c:roundedCorners val=\"0\"/><c:chart>"
        if let t = titles[1] { x += richTitle(t.0, t.1) + "<c:autoTitleDeleted val=\"0\"/>" } else { x += "<c:autoTitleDeleted val=\"1\"/>" }
        x += "<c:plotArea>" + (plot.map { manual($0, target: true) } ?? "<c:layout/>") + plotXML + "</c:plotArea>"
        if let l = legend {
            let pos = ["b", "tr", "t", "r", "l"][l.pos >= 0 && l.pos < 5 ? l.pos : 3]
            x += "<c:legend><c:legendPos val=\"\(pos)\"/>" + manual(l.rect, target: false) + "<c:overlay val=\"0\"/></c:legend>"
        }
        x += "<c:plotVisOnly val=\"1\"/><c:dispBlanksAs val=\"gap\"/></c:chart></c:chartSpace>"
        return x
    }
}
