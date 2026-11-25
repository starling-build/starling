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

/// One series of a chart as Select Data edits it: where it came from in the part (`source`, its position among the part's series; nil for a new one) and the cells it reads.
struct ChartSeriesRef: Equatable {
    var source: Int?
    var name: String?
    var cat: String?
    var val: String?
}

/// Patches on a chart part's XML text, shared by Sheets and Slides: each changes only the elements it names.
enum ChartPartPatch {
    private static func _esc(_ s: String) -> String {
        s.replacingAll("&", with: "&amp;").replacingAll("<", with: "&lt;").replacingAll(">", with: "&gt;").replacingAll("\"", with: "&quot;")
    }

    /// The chart's own title (not an axis title: those stand inside the plot area).
    static func title(_ xml: String, _ edit: ChartPartEdit) -> String {
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
                x.insert(contentsOf: "<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>\(esc)</a:t></a:r></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title>",
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
}
