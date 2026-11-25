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

extension SheetDrawingsXML {
    /// The chart's own title (not an axis title: those stand inside the plot area).
    static func _patchChartTitle(_ xml: String, _ edit: ChartPartEdit) -> String {
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
            x = _setAutoTitleDeleted(x, true)
        case .set(let text):
            let esc = Xlsx._esc(text)
            if let r = existing {
                x.replaceSubrange(r, with: _retext(String(x[r]), esc))
            } else {
                x.insert(contentsOf: "<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>\(esc)</a:t></a:r></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title>",
                         at: x.findRange(of: "<c:chart>", in: x.startIndex ..< x.endIndex)!.upperBound)
            }
            x = _setAutoTitleDeleted(x, false)
        }
        return x
    }

    /// A title's XML with its words replaced: the first run keeps its formatting, later runs go.
    private static func _retext(_ title: String, _ esc: String) -> String {
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

    private static func _setAutoTitleDeleted(_ xml: String, _ deleted: Bool) -> String {
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
    static func _patchChartLegend(_ xml: String, _ edit: ChartPartEdit) -> String {
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
}
