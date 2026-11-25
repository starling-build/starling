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
                let title = "<c:title><c:tx><c:rich>\(body)<a:lstStyle/><a:p><a:r><a:t>\(_esc(text))</a:t></a:r></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title>"
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
}
