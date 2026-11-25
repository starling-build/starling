// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CH-1b: a chart from the file keeps its own part; a title or legend edit changes only `c:title` / `c:legend` in it
// (and `c:autoTitleDeleted`), every other byte as the file wrote it.

import Foundation

enum ChartPartEdit: Equatable {
    /// A new title text, or a legend side ("b", "t", "r", "l", "tr").
    case set(String)
    case remove
}

/// Axis options set on the value axis (X-CH-3): its lowest and highest value, the distance between major ticks, and its number format.
/// `nil` is automatic (min, max, major) or "linked to the cells" (format).
struct ChartAxisEdit: Equatable {
    var min: Double? = nil
    var max: Double? = nil
    var major: Double? = nil
    var format: String? = nil
}

/// One series of a chart as Select Data edits it: where it came from in the part (`source`, its position among the part's series; nil for a new one) and the cells it reads.
/// A colour set in Format Data Series on a file's chart: a series of the part (its place in the first chart group), or one point of it; nil is automatic.
/// Data Labels: what a chart's labels show and where they stand (the first chart group's series).
struct ChartLabelEdit: Equatable {
    var show = false
    var value = true, category = false, series = false, percent = false
    /// `c:dLblPos` ("ctr", "inEnd", "inBase", "outEnd", "t", "b", "l", "r", "bestFit"); nil leaves the type's own.
    var position: String? = nil
    /// The `c:dLblPos` values a chart group allows (nil: the group takes none, and Excel refuses a file that gives one).
    static func positions(group tag: String, stacked: Bool) -> [String] {
        switch tag {
        case "barChart": return stacked ? ["ctr", "inEnd", "inBase"] : ["ctr", "inEnd", "inBase", "outEnd"]
        case "lineChart", "scatterChart", "radarChart": return tag == "radarChart" ? [] : ["ctr", "l", "r", "t", "b"]
        case "pieChart": return ["bestFit", "ctr", "inEnd", "outEnd"]
        default: return []
        }
    }
}

struct ChartColorEdit: Equatable {
    var series: Int; var point: Int?; var hex: String?
    /// A theme slot ("accent2") with its lumMod / lumOff in percent, written as a scheme colour so a new theme recolours it; wins over `hex`.
    var scheme: String? = nil; var lumMod: Int = 100; var lumOff: Int = 0
    /// The colour element to write; nil is automatic.
    var element: String? {
        if let scheme {
            var mods = ""
            if lumMod != 100 { mods += "<a:lumMod val=\"\(lumMod * 1000)\"/>" }
            if lumOff != 0 { mods += "<a:lumOff val=\"\(lumOff * 1000)\"/>" }
            return mods.isEmpty ? "<a:schemeClr val=\"\(scheme)\"/>" : "<a:schemeClr val=\"\(scheme)\">\(mods)</a:schemeClr>"
        }
        return hex.map { "<a:srgbClr val=\"\($0)\"/>" }
    }
}
struct ChartSeriesRef: Equatable {
    var source: Int?
    var name: String?
    var cat: String?
    var val: String?
}

/// The look a brand-new chart title gets: what the host application itself writes for a new title. A run with no
/// size is drawn at about 20 pt by Excel, so the default is always written (as the paragraph's defRPr).
struct ChartTitleStyle: Equatable {
    /// Font size in hundredths of a point.
    var size: Int
    static let excel = ChartTitleStyle(size: 1400)
    static let powerPoint = ChartTitleStyle(size: 1862)
    /// Regular weight, the theme's text colour at 65 %, the theme's body font.
    var paragraphProperties: String {
        "<a:pPr><a:defRPr sz=\"\(size)\" b=\"0\" i=\"0\" u=\"none\" strike=\"noStrike\" kern=\"1200\" baseline=\"0\">"
            + "<a:solidFill><a:schemeClr val=\"tx1\"><a:lumMod val=\"65000\"/><a:lumOff val=\"35000\"/></a:schemeClr></a:solidFill>"
            + "<a:latin typeface=\"+mn-lt\"/><a:ea typeface=\"+mn-ea\"/><a:cs typeface=\"+mn-cs\"/></a:defRPr></a:pPr>"
    }
}

/// Patches on a chart part's XML text, shared by Sheets and Slides: each changes only the elements it names.
enum ChartPartPatch {
    private static func _esc(_ s: String) -> String {
        s.replacingAll("&", with: "&amp;").replacingAll("<", with: "&lt;").replacingAll(">", with: "&gt;").replacingAll("\"", with: "&quot;")
    }

    /// The chart's own title (not an axis title: those stand inside the plot area).
    static func title(_ xml: String, _ edit: ChartPartEdit, style: ChartTitleStyle = .excel) -> String {
        guard let chartOpen = xml.findRange(of: "<c:chart>", in: xml.startIndex ..< xml.endIndex) else { return xml }
        let plot = xml.findRange(of: "<c:plotArea>", in: chartOpen.upperBound ..< xml.endIndex)?.lowerBound ?? xml.endIndex
        var x = xml
        // The existing title, if any, sits before the plot area.
        var existing: Range<String.Index>? = nil
        if let t0 = x.findRange(of: "<c:title>", in: chartOpen.upperBound ..< plot),
           let t1 = x.findRange(of: "</c:title>", in: t0.upperBound ..< x.endIndex) {
            existing = t0.lowerBound ..< t1.upperBound
        }
        switch edit {
        case .remove:
            if let r = existing { x.replaceSubrange(r, with: "") }
            x = setAutoTitleDeleted(x, true)
        case .set(let text):
            let esc = _esc(text)
            if let r = existing {
                x.replaceSubrange(r, with: retext(String(x[r]), esc))
            } else {
                x.insert(contentsOf: "<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p>\(style.paragraphProperties)<a:r><a:rPr lang=\"en-US\"/><a:t>\(esc)</a:t></a:r></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title>",
                         at: x.findRange(of: "<c:chart>", in: x.startIndex ..< x.endIndex)!.upperBound)
            }
            x = setAutoTitleDeleted(x, false)
        }
        return x
    }

    /// A title's XML with its words replaced: the first run keeps its formatting, later runs go.
    private static func retext(_ title: String, _ esc: String) -> String {
        guard let t0 = title.findRange(of: "<a:t>", in: title.startIndex ..< title.endIndex),
              let t1 = title.findRange(of: "</a:t>", in: t0.upperBound ..< title.endIndex) else {
            // A title from a cell (c:strRef) or without runs: a plain one in its place.
            return "<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>\(esc)</a:t></a:r></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title>"
        }
        var out = String(title[title.startIndex ..< t0.upperBound]) + esc + "</a:t>"
        var rest = String(title[t1.upperBound...])
        // Later runs in the same paragraph.
        while let r0 = rest.findRange(of: "<a:r>", in: rest.startIndex ..< rest.endIndex),
              let r1 = rest.findRange(of: "</a:r>", in: r0.upperBound ..< rest.endIndex) {
            rest.replaceSubrange(r0.lowerBound ..< r1.upperBound, with: "")
        }
        out += rest
        return out
    }

    private static func setAutoTitleDeleted(_ xml: String, _ deleted: Bool) -> String {
        let want = "<c:autoTitleDeleted val=\"\(deleted ? 1 : 0)\"/>"
        if let a = xml.findRange(of: "<c:autoTitleDeleted ", in: xml.startIndex ..< xml.endIndex),
           let e = xml.findRange(of: "/>", in: a.upperBound ..< xml.endIndex) {
            var x = xml
            x.replaceSubrange(a.lowerBound ..< e.upperBound, with: want)
            return x
        }
        // Absent: it follows the title, so open the chart's children with it.
        guard let plot = xml.findRange(of: "<c:plotArea>", in: xml.startIndex ..< xml.endIndex) else { return xml }
        var x = xml
        x.insert(contentsOf: want, at: plot.lowerBound)
        return x
    }

    /// The legend: its side, or none.
    static func legend(_ xml: String, _ edit: ChartPartEdit) -> String {
        var x = xml
        guard let plotEnd = x.findRange(of: "</c:plotArea>", in: x.startIndex ..< x.endIndex) else { return xml }
        var existing: Range<String.Index>? = nil
        if let l0 = x.findRange(of: "<c:legend>", in: plotEnd.upperBound ..< x.endIndex),
           let l1 = x.findRange(of: "</c:legend>", in: l0.upperBound ..< x.endIndex) {
            existing = l0.lowerBound ..< l1.upperBound
        }
        switch edit {
        case .remove:
            if let r = existing { x.replaceSubrange(r, with: "") }
        case .set(let pos):
            if let r = existing {
                var leg = String(x[r])
                if let p0 = leg.findRange(of: "<c:legendPos ", in: leg.startIndex ..< leg.endIndex),
                   let p1 = leg.findRange(of: "/>", in: p0.upperBound ..< leg.endIndex) {
                    leg.replaceSubrange(p0.lowerBound ..< p1.upperBound, with: "<c:legendPos val=\"\(pos)\"/>")
                } else if let o = leg.findRange(of: "<c:legend>", in: leg.startIndex ..< leg.endIndex) {
                    leg.insert(contentsOf: "<c:legendPos val=\"\(pos)\"/>", at: o.upperBound)
                }
                x.replaceSubrange(r, with: leg)
            } else {
                x.insert(contentsOf: "<c:legend><c:legendPos val=\"\(pos)\"/><c:overlay val=\"0\"/></c:legend>", at: plotEnd.upperBound)
            }
        }
        return x
    }

    enum Axis { case category, value }

    /// An axis's own title: its text set, or the title taken off. The category axis is the first c:catAx / c:dateAx,
    /// else (a scatter chart) the first c:valAx; the value axis is the other c:valAx. Everything else stays as written.
    static func axisTitle(_ xml: String, _ axis: Axis, _ edit: ChartPartEdit) -> String {
        var spans: [(tag: String, r: Range<String.Index>)] = []
        for tag in ["catAx", "dateAx", "valAx"] {
            var from = xml.startIndex
            while let o = xml.findRange(of: "<c:\(tag)>", in: from ..< xml.endIndex),
                  let c = xml.findRange(of: "</c:\(tag)>", in: o.upperBound ..< xml.endIndex) {
                spans.append((tag, o.lowerBound ..< c.upperBound)); from = c.upperBound
            }
        }
        spans.sort { $0.r.lowerBound < $1.r.lowerBound }
        let cat = spans.first(where: { $0.tag != "valAx" }) ?? spans.first(where: { $0.tag == "valAx" })
        let val = spans.first(where: { $0.tag == "valAx" && $0.r != cat?.r })
        guard let target = (axis == .category ? cat : val) else { return xml }
        var ax = String(xml[target.r])
        let vertical = ax.containsSubstring("<c:axPos val=\"l\"") || ax.containsSubstring("<c:axPos val=\"r\"")
        var existing: Range<String.Index>? = nil
        if let t0 = ax.findRange(of: "<c:title>", in: ax.startIndex ..< ax.endIndex),
           let t1 = ax.findRange(of: "</c:title>", in: t0.upperBound ..< ax.endIndex) { existing = t0.lowerBound ..< t1.upperBound }
        switch edit {
        case .remove:
            if let r = existing { ax.replaceSubrange(r, with: "") }
        case .set(let text):
            if let r = existing {
                ax.replaceSubrange(r, with: retext(String(ax[r]), _esc(text)))
            } else {
                let body = vertical ? "<a:bodyPr rot=\"-5400000\" vert=\"horz\"/>" : "<a:bodyPr/>"
                let title = "<c:title><c:tx><c:rich>\(body)<a:lstStyle/><a:p><a:pPr><a:defRPr sz=\"1000\" b=\"1\"/></a:pPr><a:r><a:rPr lang=\"en-US\"/><a:t>\(_esc(text))</a:t></a:r></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title>"
                // Schema order: ... axPos, majorGridlines, minorGridlines, title, numFmt, majorTickMark ...
                guard let pos = ax.findRange(of: "<c:axPos ", in: ax.startIndex ..< ax.endIndex),
                      let posEnd = ax.findRange(of: "/>", in: pos.upperBound ..< ax.endIndex) else { return xml }
                var at = posEnd.upperBound
                // Past the gridlines, whose own children (spPr) are not the axis's.
                for name in ["majorGridlines", "minorGridlines"] {
                    guard ax.findRange(of: "<c:\(name)", in: at ..< ax.endIndex)?.lowerBound == at,
                          let open = ax.findRange(of: ">", in: at ..< ax.endIndex) else { continue }
                    if ax[ax.index(before: open.lowerBound)] == "/" { at = open.upperBound }
                    else if let c = ax.findRange(of: "</c:\(name)>", in: at ..< ax.endIndex) { at = c.upperBound }
                }
                ax.insert(contentsOf: title, at: at)
            }
        }
        var out = xml
        out.replaceSubrange(target.r, with: ax)
        return out
    }

    // MARK: Series (Select Data)

    private static func _firstValue(_ x: String, _ tag: String) -> Int? {
        guard let a = x.findRange(of: "<c:\(tag) val=\"", in: x.startIndex ..< x.endIndex),
              let b = x.findRange(of: "\"", in: a.upperBound ..< x.endIndex) else { return nil }
        return Int(x[a.upperBound ..< b.lowerBound])
    }

    /// `<c:tag>…</c:tag>` (or the tag's self-closed form) within `x`, as a range.
    private static func _element(_ x: String, _ tag: String) -> Range<String.Index>? {
        guard let a = x.findRange(of: "<c:\(tag)>", in: x.startIndex ..< x.endIndex),
              let b = x.findRange(of: "</c:\(tag)>", in: a.upperBound ..< x.endIndex) else { return nil }
        return a.lowerBound ..< b.upperBound
    }

    private static func _formula(_ element: String) -> String? {
        guard let a = element.findRange(of: "<c:f>", in: element.startIndex ..< element.endIndex),
              let b = element.findRange(of: "</c:f>", in: a.upperBound ..< element.endIndex) else { return nil }
        return String(element[a.upperBound ..< b.lowerBound]).replacingAll("&lt;", with: "<").replacingAll("&gt;", with: ">")
            .replacingAll("&quot;", with: "\"").replacingAll("&apos;", with: "'").replacingAll("&amp;", with: "&")
    }

    /// A series with one of its cell references set (nil takes the element off); an element already reading that text stays as written, cache and all.
    private static func _setRef(_ ser: String, _ tag: String, _ ref: String?, numeric: Bool) -> String {
        var x = ser
        let existing = _element(x, tag)
        if let r = existing, _formula(String(x[r])) == ref { return x }
        guard let ref else {
            if let r = existing { x.replaceSubrange(r, with: "") }
            return x
        }
        let kind = numeric ? "numRef" : "strRef"
        let element = "<c:\(tag)><c:\(kind)><c:f>\(_esc(ref))</c:f></c:\(kind)></c:\(tag)>"
        if let r = existing { x.replaceSubrange(r, with: element); return x }
        // Where the schema puts it: the name after the order, categories before the values, values before what trails them.
        var at = x.endIndex
        if tag == "tx" {
            if let o = x.findRange(of: "<c:order val=\"", in: x.startIndex ..< x.endIndex), let e = x.findRange(of: "/>", in: o.upperBound ..< x.endIndex) { at = e.upperBound }
        } else {
            let before = tag == "cat" || tag == "xVal" ? ["<c:val>", "<c:yVal>", "<c:smooth", "<c:extLst>", "</c:ser>"] : ["<c:smooth", "<c:extLst>", "</c:ser>"]
            at = before.compactMap { a in x.findRange(of: a, in: x.startIndex ..< x.endIndex)?.lowerBound }.min() ?? x.endIndex
        }
        x.insert(contentsOf: element, at: at)
        return x
    }

    /// The part's series (`c:ser`, in document order) made to be `list`: a kept series keeps everything but the cells it reads, one left out goes, a new one is a copy of the last kept series without its colours or cached data, with an idx and order of its own (PowerPoint and Excel refuse a chart with two series of one idx or order).
    static func series(_ xml: String, _ list: [ChartSeriesRef]) -> String {
        var sers: [Range<String.Index>] = []
        var at = xml.startIndex
        while let a = xml.findRange(of: "<c:ser>", in: at ..< xml.endIndex), let b = xml.findRange(of: "</c:ser>", in: a.upperBound ..< xml.endIndex) {
            sers.append(a.lowerBound ..< b.upperBound)
            at = b.upperBound
        }
        let allSers = sers
        // Only the first chart group's series are the model's (a second group, a secondary axis, is not listed): the others stay as written.
        if let g = xml.findRange(of: "<c:plotArea>", in: xml.startIndex ..< xml.endIndex),
           let first = sers.first(where: { $0.lowerBound >= g.upperBound }),
           let close = xml.findRange(of: "Chart>", in: first.upperBound ..< xml.endIndex) {
            sers = sers.filter { $0.lowerBound < close.lowerBound }
        }
        guard !sers.isEmpty else { return xml }
        let scatter = xml.containsSubstring("<c:scatterChart>")
        var maxIdx = -1, maxOrder = -1
        for r in allSers {
            let t = String(xml[r])
            maxIdx = max(maxIdx, _firstValue(t, "idx") ?? -1); maxOrder = max(maxOrder, _firstValue(t, "order") ?? -1)
        }
        let kept = list.compactMap(\.source).filter { sers.indices.contains($0) }
        guard let template = kept.max() else { return xml }
        func rewritten(_ t: String, _ ref: ChartSeriesRef) -> String {
            var s = _setRef(t, "tx", ref.name, numeric: false)
            s = _setRef(s, scatter ? "xVal" : "cat", ref.cat, numeric: scatter)
            return _setRef(s, scatter ? "yVal" : "val", ref.val, numeric: true)
        }
        func fresh(from t: String, _ ref: ChartSeriesRef) -> String {
            var s = t
            maxIdx += 1; maxOrder += 1
            for (tag, v) in [("idx", maxIdx), ("order", maxOrder)] {
                if let a = s.findRange(of: "<c:\(tag) val=\"", in: s.startIndex ..< s.endIndex),
                   let b = s.findRange(of: "/>", in: a.upperBound ..< s.endIndex) { s.replaceSubrange(a.lowerBound ..< b.upperBound, with: "<c:\(tag) val=\"\(v)\"/>") }
            }
            // Its own colours and data points go; the cells it reads are written afresh.
            while let a = s.findRange(of: "<c:dPt>", in: s.startIndex ..< s.endIndex), let b = s.findRange(of: "</c:dPt>", in: a.upperBound ..< s.endIndex) {
                s.replaceSubrange(a.lowerBound ..< b.upperBound, with: "")
            }
            // Its marker format goes too (own colours would otherwise sit beside an automatic line): the whole series is automatic.
            if let a = s.findRange(of: "<c:marker>", in: s.startIndex ..< s.endIndex), let b = s.findRange(of: "</c:marker>", in: a.upperBound ..< s.endIndex) {
                s.replaceSubrange(a.lowerBound ..< b.upperBound, with: "")
            }
            let head = ["<c:marker>", "<c:dLbls>", "<c:cat>", "<c:xVal>", "<c:val>", "<c:yVal>"].compactMap { s.findRange(of: $0, in: s.startIndex ..< s.endIndex)?.lowerBound }.min() ?? s.endIndex
            if let a = s.findRange(of: "<c:spPr>", in: s.startIndex ..< head), let b = s.findRange(of: "</c:spPr>", in: a.upperBound ..< s.endIndex) {
                s.replaceSubrange(a.lowerBound ..< b.upperBound, with: "")
            }
            for tag in ["tx", scatter ? "xVal" : "cat", scatter ? "yVal" : "val"] {
                if let r = _element(s, tag) { s.replaceSubrange(r, with: "") }
            }
            return rewritten(s, ref)
        }
        var x = xml
        for (k, r) in sers.enumerated().reversed() {
            guard let ref = list.first(where: { $0.source == k }) else { x.replaceSubrange(r, with: ""); continue }
            var out = rewritten(String(x[r]), ref)
            if k == template {
                for n in list where n.source == nil { out += fresh(from: String(xml[r]), n) }
            }
            x.replaceSubrange(r, with: out)
        }
        return x
    }

    // MARK: series colours (X-CH-1f: Format Data Series)

    /// The part's first chart group's series (what the model lists), in document order, and that group's tag ("barChart", "lineChart"…).
    private static func _firstGroup(_ xml: String) -> (sers: [Range<String.Index>], tag: String)? {
        guard let g = xml.findRange(of: "<c:plotArea>", in: xml.startIndex ..< xml.endIndex) else { return nil }
        var sers: [Range<String.Index>] = []
        var at = g.upperBound
        while let a = xml.findRange(of: "<c:ser>", in: at ..< xml.endIndex), let b = xml.findRange(of: "</c:ser>", in: a.upperBound ..< xml.endIndex) {
            sers.append(a.lowerBound ..< b.upperBound)
            at = b.upperBound
        }
        guard let first = sers.first, let close = xml.findRange(of: "Chart>", in: first.upperBound ..< xml.endIndex) else { return nil }
        let head = String(xml[g.upperBound ..< first.lowerBound])
        // The group tag is the last "<c:xxxChart>" before the first series.
        var tag = ""
        var from = head.startIndex
        while let a = head.findRange(of: "<c:", in: from ..< head.endIndex) {
            guard let e = head.findRange(of: ">", in: a.upperBound ..< head.endIndex) else { break }
            let name = String(head[a.upperBound ..< e.lowerBound])
            if name.hasSuffix("Chart") { tag = name }
            from = e.upperBound
        }
        return tag.isEmpty ? nil : (sers.filter { $0.lowerBound < close.lowerBound }, tag)
    }

    private static let _fillTags = ["a:solidFill", "a:gradFill", "a:pattFill", "a:blipFill", "a:grpFill"]

    /// `t` without its own (top-level) fills.
    private static func _withoutFill(_ t: String) -> String {
        var x = t
        for tag in _fillTags {
            while let a = x.findRange(of: "<\(tag)", in: x.startIndex ..< x.endIndex) {
                if let e = x.findRange(of: "</\(tag)>", in: a.upperBound ..< x.endIndex) { x.replaceSubrange(a.lowerBound ..< e.upperBound, with: "") }
                else if let e = x.findRange(of: "/>", in: a.upperBound ..< x.endIndex) { x.replaceSubrange(a.lowerBound ..< e.upperBound, with: "") }
                else { break }
            }
        }
        while let a = x.findRange(of: "<a:noFill/>", in: x.startIndex ..< x.endIndex) { x.replaceSubrange(a, with: "") }
        return x
    }

    /// A solid fill of the colour element `clr` (a scheme or an sRGB colour).
    private static func _solid(_ clr: String) -> String { "<a:solidFill>\(clr)</a:solidFill>" }

    /// The `<a:ln …>…</a:ln>` (or `<a:ln …/>`) of a shape's properties, if any.
    private static func _lnRange(_ t: String) -> Range<String.Index>? {
        var from = t.startIndex
        while let a = t.findRange(of: "<a:ln", in: from ..< t.endIndex) {
            guard a.upperBound < t.endIndex else { return nil }
            let c = t[a.upperBound]
            if c == " " || c == ">" || c == "/" {
                guard let e = t.findRange(of: ">", in: a.upperBound ..< t.endIndex) else { return nil }
                if t[t.index(before: e.lowerBound)] == "/" { return a.lowerBound ..< e.upperBound }
                if let close = t.findRange(of: "</a:ln>", in: e.upperBound ..< t.endIndex) { return a.lowerBound ..< close.upperBound }
                return nil
            }
            from = a.upperBound
        }
        return nil
    }

    /// The shape properties' inside with its fill (or, for a line, the outline's fill) set to `hex`, or taken off when nil.
    private static func _paint(_ inner: String, _ hex: String?, line: Bool) -> String {
        if !line {
            if let ln = _lnRange(inner) {
                return (hex.map(_solid) ?? "") + _withoutFill(String(inner[inner.startIndex ..< ln.lowerBound])) + String(inner[ln]) + _withoutFill(String(inner[ln.upperBound ..< inner.endIndex]))
            }
            return (hex.map(_solid) ?? "") + _withoutFill(inner)
        }
        guard let ln = _lnRange(inner) else {
            guard let hex else { return inner }
            return inner + "<a:ln w=\"28575\" cap=\"rnd\">\(_solid(hex))<a:round/></a:ln>"
        }
        var l = String(inner[ln])
        var open: String, body: String, selfClosed = false
        if l.hasSuffix("/>") { open = String(l.dropLast(2)) + ">"; body = ""; selfClosed = true } else {
            let e = l.findRange(of: ">", in: l.startIndex ..< l.endIndex)!
            open = String(l[l.startIndex ..< e.upperBound]); body = String(l[e.upperBound ..< l.index(l.endIndex, offsetBy: -7)])
        }
        _ = selfClosed
        l = open + (hex.map(_solid) ?? "") + _withoutFill(body) + "</a:ln>"
        return String(inner[inner.startIndex ..< ln.lowerBound]) + l + String(inner[ln.upperBound ..< inner.endIndex])
    }

    /// Where a shape-properties element `<c:spPr>` of `s` sits: searched after `after` (a marker's own comes before a data point's).
    private static func _spPr(_ s: String, from: String.Index, before limit: String.Index) -> Range<String.Index>? {
        guard let a = s.findRange(of: "<c:spPr", in: from ..< limit) else { return nil }
        if let e = s.findRange(of: ">", in: a.upperBound ..< s.endIndex), s[s.index(before: e.lowerBound)] == "/" { return a.lowerBound ..< e.upperBound }
        guard let b = s.findRange(of: "</c:spPr>", in: a.upperBound ..< s.endIndex) else { return nil }
        return a.lowerBound ..< b.upperBound
    }

    private static func _inner(_ s: String, _ r: Range<String.Index>) -> String {
        let t = String(s[r])
        if t.hasSuffix("/>") { return "" }
        guard let e = t.findRange(of: ">", in: t.startIndex ..< t.endIndex) else { return "" }
        return String(t[e.upperBound ..< t.index(t.endIndex, offsetBy: -9)])
    }

    /// A series element with its colour set to `hex` (nil: automatic, from its number).
    private static func _setSeriesColor(_ ser: String, _ hex: String?, line: Bool) -> String {
        var s = ser
        let stops = ["<c:marker>", "<c:dPt>", "<c:dLbls>", "<c:invertIfNegative", "<c:explosion", "<c:cat>", "<c:xVal>", "<c:val>", "<c:yVal>"]
        let head = stops.compactMap { s.findRange(of: $0, in: s.startIndex ..< s.endIndex)?.lowerBound }.min() ?? s.endIndex
        if let r = _spPr(s, from: s.startIndex, before: head) {
            let inner = _paint(_inner(s, r), hex, line: line)
            s.replaceSubrange(r, with: inner.isEmpty ? "" : "<c:spPr>\(inner)</c:spPr>")
        } else if let hex {
            let inner = _paint("", hex, line: line)
            var at = s.startIndex
            if let t = s.findRange(of: "</c:tx>", in: s.startIndex ..< s.endIndex) { at = t.upperBound }
            else if let o = s.findRange(of: "<c:order val=\"", in: s.startIndex ..< s.endIndex), let e = s.findRange(of: "/>", in: o.upperBound ..< s.endIndex) { at = e.upperBound }
            s.insert(contentsOf: "<c:spPr>\(inner)</c:spPr>", at: at)
        }
        // A line's markers follow it (their automatic colour follows the series number, not the line).
        if line, let a = s.findRange(of: "<c:marker>", in: s.startIndex ..< s.endIndex), let b = s.findRange(of: "</c:marker>", in: a.upperBound ..< s.endIndex),
           !s[a.lowerBound ..< b.upperBound].containsSubstring("<c:symbol val=\"none\"/>") {
            var m = String(s[a.lowerBound ..< b.upperBound])
            if let r = _spPr(m, from: m.startIndex, before: m.endIndex) { m.replaceSubrange(r, with: "") }
            if let hex { m = m.replacingAll("</c:marker>", with: "<c:spPr>\(_solid(hex))<a:ln w=\"9525\">\(_solid(hex))</a:ln></c:spPr></c:marker>") }
            s.replaceSubrange(a.lowerBound ..< b.upperBound, with: m)
        }
        return s
    }

    /// A series element with data point `p` (its bar, column or slice) coloured `hex`, or put back to automatic when nil.
    private static func _setPointColor(_ ser: String, _ p: Int, _ hex: String?, group: String) -> String {
        var s = ser
        var found: Range<String.Index>? = nil
        var from = s.startIndex
        while let a = s.findRange(of: "<c:dPt>", in: from ..< s.endIndex), let b = s.findRange(of: "</c:dPt>", in: a.upperBound ..< s.endIndex) {
            if s[a.upperBound ..< b.lowerBound].hasPrefix("<c:idx val=\"\(p)\"/>") { found = a.lowerBound ..< b.upperBound; break }
            from = b.upperBound
        }
        guard let hex else {
            if let f = found { s.removeSubrange(f) }
            return s
        }
        if let f = found {
            var d = String(s[f])
            let after = d.findRange(of: "</c:marker>", in: d.startIndex ..< d.endIndex)?.upperBound ?? d.startIndex
            if let r = _spPr(d, from: after, before: d.endIndex) {
                d.replaceSubrange(r, with: "<c:spPr>\(_paint(_inner(d, r), hex, line: false))</c:spPr>")
            } else { d = d.replacingAll("</c:dPt>", with: "<c:spPr>\(_solid(hex))</c:spPr></c:dPt>") }
            s.replaceSubrange(f, with: d)
            return s
        }
        let extra = group.hasPrefix("bar") ? "<c:invertIfNegative val=\"0\"/>" : (group.hasPrefix("pie") || group.hasPrefix("doughnut") ? "<c:bubble3D val=\"0\"/>" : "")
        let dpt = "<c:dPt><c:idx val=\"\(p)\"/>\(extra)<c:spPr>\(_solid(hex))</c:spPr></c:dPt>"
        let follow = ["<c:dLbls>", "<c:trendline>", "<c:errBars>", "<c:cat>", "<c:val>", "<c:xVal>", "<c:yVal>", "<c:bubbleSize>"]
        let at = follow.compactMap { s.findRange(of: $0, in: s.startIndex ..< s.endIndex)?.lowerBound }.min() ?? s.endIndex
        s.insert(contentsOf: dpt, at: at)
        return s
    }

    /// The part's series coloured as `edits` say (series by their place in the part's first chart group). A line or scatter series is
    /// coloured on its line and markers; the others on their fill; a data point only on bars, columns, areas and pie slices.
    static func colors(_ xml: String, _ edits: [ChartColorEdit]) -> String {
        guard !edits.isEmpty, let g = _firstGroup(xml) else { return xml }
        let line = g.tag.hasPrefix("line") || g.tag.hasPrefix("scatter") || (g.tag == "radarChart" && !xml.containsSubstring("<c:radarStyle val=\"filled\""))
        var x = xml
        for (k, r) in g.sers.enumerated().reversed() {
            let mine = edits.filter { $0.series == k }
            if mine.isEmpty { continue }
            var s = String(x[r])
            for e in mine {
                if let p = e.point { if !line { s = _setPointColor(s, p, e.element, group: g.tag) } }
                else { s = _setSeriesColor(s, e.element, line: line) }
            }
            x.replaceSubrange(r, with: s)
        }
        return x
    }
    /// The part's labels as `edit` says, on every series of the first chart group: a series' own `c:dLbls` gets the shows and the
    /// position (its number format, text and per-point labels stay), or `c:delete` when the labels are off.
    static func labels(_ xml: String, _ edit: ChartLabelEdit) -> String {
        guard let g = _firstGroup(xml) else { return xml }
        let stacked = xml.containsSubstring("<c:grouping val=\"stacked\"/>") || xml.containsSubstring("<c:grouping val=\"percentStacked\"/>")
        let allowed = ChartLabelEdit.positions(group: g.tag, stacked: stacked)
        let pos = edit.position.flatMap { allowed.contains($0) ? $0 : nil }
        func flag(_ v: Bool) -> String { v ? "1" : "0" }
        let shows = (pos.map { "<c:dLblPos val=\"\($0)\"/>" } ?? "") + "<c:showLegendKey val=\"0\"/><c:showVal val=\"\(flag(edit.value))\"/><c:showCatName val=\"\(flag(edit.category))\"/><c:showSerName val=\"\(flag(edit.series))\"/><c:showPercent val=\"\(flag(edit.percent))\"/><c:showBubbleSize val=\"0\"/>"
        var x = xml
        for r in g.sers.reversed() {
            var s = String(x[r])
            if let a = s.findRange(of: "<c:dLbls>", in: s.startIndex ..< s.endIndex), let b = s.findRange(of: "</c:dLbls>", in: a.upperBound ..< s.endIndex) {
                if !edit.show { s.replaceSubrange(a.lowerBound ..< b.upperBound, with: "<c:dLbls><c:delete val=\"1\"/></c:dLbls>"); x.replaceSubrange(r, with: s); continue }
                let whole = String(s[a.upperBound ..< b.lowerBound])
                // The per-point labels (`c:dLbl`) keep their own shows; only what follows them is the series'.
                let cut = whole.findRange(of: "</c:dLbl>", in: whole.startIndex ..< whole.endIndex).map { _ -> String.Index in
                    var last = whole.startIndex
                    var from = whole.startIndex
                    while let q = whole.findRange(of: "</c:dLbl>", in: from ..< whole.endIndex) { last = q.upperBound; from = q.upperBound }
                    return last
                } ?? whole.startIndex
                let keep = String(whole[whole.startIndex ..< cut])
                var inner = String(whole[cut...])
                for t in ["delete", "dLblPos", "showLegendKey", "showVal", "showCatName", "showSerName", "showPercent", "showBubbleSize"] {
                    while let q = inner.findRange(of: "<c:\(t) val=\"", in: inner.startIndex ..< inner.endIndex),
                          let e = inner.findRange(of: "/>", in: q.upperBound ..< inner.endIndex) { inner.replaceSubrange(q.lowerBound ..< e.upperBound, with: "") }
                }
                var at = inner.endIndex
                for t in ["<c:separator", "<c:showLeaderLines", "<c:leaderLines", "<c:extLst"] {
                    if let q = inner.findRange(of: t, in: inner.startIndex ..< inner.endIndex), q.lowerBound < at { at = q.lowerBound }
                }
                inner.insert(contentsOf: shows, at: at)
                s.replaceSubrange(a.upperBound ..< b.lowerBound, with: keep + inner)
            } else if !edit.show {
                if xml.containsSubstring("<c:dLbls>") { s = _insertLabels(s, "<c:dLbls><c:delete val=\"1\"/></c:dLbls>") }
            } else if edit.show {
                s = _insertLabels(s, "<c:dLbls>\(shows)</c:dLbls>")
            }
            x.replaceSubrange(r, with: s)
        }
        // A group-level `c:dLbls` (a chart made here writes one) would still say the old thing for series that have none of their own: every series has its own now.
        if let end = x.findRange(of: "</c:\(g.tag)>", in: x.startIndex ..< x.endIndex) {
            var last: Range<String.Index>? = nil, from = x.startIndex
            while let q = x.findRange(of: "</c:ser>", in: from ..< end.lowerBound) { last = q; from = q.upperBound }
            if let l = last, x[l.upperBound...].hasPrefix("<c:dLbls>"),
               let b = x.findRange(of: "</c:dLbls>", in: l.upperBound ..< end.lowerBound) { x.removeSubrange(l.upperBound ..< b.upperBound) }
        }
        return x
    }

    /// Where inside `ax` (a `c:valAx` element) a new child goes: before its first direct child named in `after` (children of children, such as a
    /// gridline's `c:spPr` or a title's `c:txPr`, do not count), else at the end.
    private static func _axisInsertion(_ ax: String, before after: [String]) -> String.Index {
        guard let open = ax.findRange(of: ">", in: ax.startIndex ..< ax.endIndex) else { return ax.endIndex }
        var depth = 0
        var at = open.upperBound
        while let a = ax.findRange(of: "<", in: at ..< ax.endIndex), let b = ax.findRange(of: ">", in: a.upperBound ..< ax.endIndex) {
            let tag = String(ax[a.upperBound ..< b.lowerBound])
            at = b.upperBound
            if tag.hasPrefix("/") { if depth == 0 { return a.lowerBound }; depth -= 1; continue }
            let name = String(tag.split(whereSeparator: { $0 == " " || $0 == "/" }).first ?? "")
            if depth == 0, after.contains(name) { return a.lowerBound }
            if !tag.hasSuffix("/") { depth += 1 }
        }
        return ax.endIndex
    }

    /// The first group's value axis (the one its second `c:axId` names; a scatter's y axis) with its scale and number format set.
    static func valueAxis(_ xml: String, _ edit: ChartAxisEdit) -> String {
        guard let g = _firstGroup(xml), let first = g.sers.first, let close = xml.findRange(of: "</c:\(g.tag)>", in: first.upperBound ..< xml.endIndex) else { return xml }
        // The ids the group names after its series: category (or x) axis first, value axis second.
        var ids: [String] = []
        var at = first.upperBound
        while let a = xml.findRange(of: "<c:axId val=\"", in: at ..< close.lowerBound), let b = xml.findRange(of: "\"", in: a.upperBound ..< close.lowerBound) {
            ids.append(String(xml[a.upperBound ..< b.lowerBound])); at = b.upperBound
        }
        guard ids.count >= 2 else { return xml }
        var from = xml.startIndex
        while let a = xml.findRange(of: "<c:valAx>", in: from ..< xml.endIndex), let b = xml.findRange(of: "</c:valAx>", in: a.upperBound ..< xml.endIndex) {
            from = b.upperBound
            var ax = String(xml[a.lowerBound ..< b.upperBound])
            guard ax.containsSubstring("<c:axId val=\"\(ids[1])\"/>") else { continue }
            func strip(_ tag: String, _ s: inout String) {
                while let q = s.findRange(of: "<c:\(tag) val=\"", in: s.startIndex ..< s.endIndex), let e = s.findRange(of: "/>", in: q.upperBound ..< s.endIndex) {
                    s.replaceSubrange(q.lowerBound ..< e.upperBound, with: "")
                }
            }
            func num(_ v: Double) -> String { v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v) }
            // Scale: orientation, then max, then min.
            if let sa = ax.findRange(of: "<c:scaling>", in: ax.startIndex ..< ax.endIndex), let sb = ax.findRange(of: "</c:scaling>", in: sa.upperBound ..< ax.endIndex) {
                var sc = String(ax[sa.upperBound ..< sb.lowerBound])
                strip("max", &sc); strip("min", &sc)
                let add = (edit.max.map { "<c:max val=\"\(num($0))\"/>" } ?? "") + (edit.min.map { "<c:min val=\"\(num($0))\"/>" } ?? "")
                if let o = sc.findRange(of: "<c:orientation val=\"", in: sc.startIndex ..< sc.endIndex), let e = sc.findRange(of: "/>", in: o.upperBound ..< sc.endIndex) { sc.insert(contentsOf: add, at: e.upperBound) }
                else { sc += add }
                ax.replaceSubrange(sa.upperBound ..< sb.lowerBound, with: sc)
            }
            // Major unit: after crossBetween, before minorUnit / dispUnits.
            strip("majorUnit", &ax)
            if let m = edit.major {
                let unit = "<c:majorUnit val=\"\(num(m))\"/>"
                let pos = _axisInsertion(ax, before: ["c:minorUnit", "c:dispUnits", "c:extLst"])
                ax.insert(contentsOf: unit, at: pos)
            }
            // Number format: after the title (or gridlines), before the tick marks.
            if let f = ax.findRange(of: "<c:numFmt ", in: ax.startIndex ..< ax.endIndex), let e = ax.findRange(of: "/>", in: f.upperBound ..< ax.endIndex) {
                ax.removeSubrange(f.lowerBound ..< e.upperBound)
            }
            if let code = edit.format {
                let pos = _axisInsertion(ax, before: ["c:majorTickMark", "c:minorTickMark", "c:tickLblPos", "c:spPr", "c:txPr", "c:crossAx", "c:crosses", "c:crossesAt", "c:crossBetween", "c:majorUnit", "c:minorUnit", "c:dispUnits", "c:extLst"])
                var esc = code
                esc = _esc(esc)
                ax.insert(contentsOf: "<c:numFmt formatCode=\"\(esc)\" sourceLinked=\"0\"/>", at: pos)
            } else {
                // Linked to the cells: the axis says so itself.
                let pos = _axisInsertion(ax, before: ["c:majorTickMark", "c:minorTickMark", "c:tickLblPos", "c:spPr", "c:txPr", "c:crossAx", "c:crosses", "c:crossesAt", "c:crossBetween", "c:majorUnit", "c:minorUnit", "c:dispUnits", "c:extLst"])
                ax.insert(contentsOf: "<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/>", at: pos)
            }
            var x = xml
            x.replaceSubrange(a.lowerBound ..< b.upperBound, with: ax)
            return x
        }
        return xml
    }

    /// `labels` placed in a series before the first thing the schema puts after them.
    private static func _insertLabels(_ ser: String, _ labels: String) -> String {
        var s = ser
        var at = s.endIndex
        for t in ["<c:trendline>", "<c:errBars>", "<c:cat>", "<c:val>", "<c:xVal>", "<c:yVal>", "<c:smooth", "<c:shape", "<c:bubbleSize>", "<c:extLst>"] {
            if let q = s.findRange(of: t, in: s.startIndex ..< s.endIndex), q.lowerBound < at { at = q.lowerBound }
        }
        s.insert(contentsOf: labels, at: at)
        return s
    }
}
