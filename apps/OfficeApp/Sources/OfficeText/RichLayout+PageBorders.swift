import Flutter
import FlutterSwiftBridge
import Foundation

// Page borders (`w:pgBorders`): a box drawn round each page of a section.
// Line borders only; art borders (`w:val` of a picture name) are not drawn.

extension RichLayout {
    /// The `w:pgBorders` of the section page `p` is in, or nil.
    func _pageBordersXML(_ p: Int, _ document: RichDocument) -> String? {
        guard theme.wordRules, p >= 0, p < _pageSection.count else { return document.pageBordersXML }
        let section = _pageSection[p]
        var n = 0
        for (i, para) in document.paragraphs.enumerated() where para.cell == nil {
            guard para.style.sectionPage != nil, i < document.paragraphs.count - 1 else { continue }
            if n == section {
                guard let xml = para.style.sectionXML, let r = xml.rangeOfSubstring("<w:pgBorders"),
                      let e = xml.rangeOfSubstring("</w:pgBorders>") else { return nil }
                return String(xml[r.lowerBound ..< e.upperBound])
            }
            n += 1
        }
        return document.pageBordersXML
    }

    private static func _attr(_ sub: Substring, _ name: String) -> String? {
        let tag = String(sub)
        guard let r = tag.rangeOfSubstring(name + "=\"") else { return nil }
        let rest = tag[r.upperBound...]
        guard let q = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[rest.startIndex ..< q])
    }

    func _paintPageBorders(_ p: Int, _ canvas: any Canvas, _ document: RichDocument) {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, let xml = _pageBordersXML(p, document) else { return }
        let headEnd = xml.firstIndex(of: ">") ?? xml.endIndex
        let head = xml[xml.startIndex ..< headEnd]
        let display = Self._attr(head, "w:display") ?? "allPages"
        let first = p == 0 || p >= _pageSection.count || _pageSection[p - 1] != _pageSection[p]
        if display == "firstPage" && !first { return }
        if display == "notFirstPage" && first { return }
        let fromText = (Self._attr(head, "w:offsetFrom") ?? "text") == "text"
        let page = pageRect(p)
        let s = pageSetup(forPage: p)

        struct Side { var style: String; var width: Double; var space: Double; var color: Int64 }
        func side(_ name: String) -> Side? {
            guard let r = xml.rangeOfSubstring("<w:" + name + " ") else { return nil }
            let tail = xml[r.lowerBound...]
            let tag = tail[tail.startIndex ..< (tail.firstIndex(of: ">") ?? tail.endIndex)]
            guard let val = Self._attr(tag, "w:val"), val != "nil", val != "none" else { return nil }
            // (Art borders name a picture; those are not line styles.)
            let lines: Set<String> = ["single", "thick", "double", "dotted", "dashed", "dotDash", "dotDotDash", "triple",
                                      "thinThickSmallGap", "thickThinSmallGap", "thinThickThinSmallGap",
                                      "thinThickMediumGap", "thickThinMediumGap", "thinThickThinMediumGap",
                                      "thinThickLargeGap", "thickThinLargeGap", "thinThickThinLargeGap"]
            guard lines.contains(val) else { return nil }
            let sz = Double(Self._attr(tag, "w:sz") ?? "") ?? 4
            let space = Double(Self._attr(tag, "w:space") ?? "") ?? 0
            var color: Int64 = 0
            if let c = Self._attr(tag, "w:color"), c.count == 6, let v = Int64(c, radix: 16) { color = v }
            return Side(style: val, width: max(0.25, sz / 8), space: space, color: color)
        }

        // The outer edge of each side, in pixels.
        let top = side("top"), left = side("left"), bottom = side("bottom"), right = side("right")
        let pxTopText = page.top + _pxMarginTop(p)
        let pxLeftText = page.left + _pxMarginLeft(p)
        let pxRightText = page.right - _px(s.marginRight)
        let pxBottomText = page.bottom - _px(s.marginBottom)
        // The strokes of a style as (offset inward, thickness) in points.
        func strokes(_ sd: Side, thickOutside: Bool) -> [(Double, Double)] {
            let w = sd.width
            switch sd.style {
            case "double": return [(0, w), (2 * w, w)]
            case "triple": return [(0, w), (2 * w, w), (4 * w, w)]
            case "thinThickSmallGap", "thinThickMediumGap", "thinThickLargeGap":
                let thin = min(0.75, w / 2)
                return [(0, thin), (thin + 0.75, w)]
            case "thickThinSmallGap", "thickThinMediumGap", "thickThinLargeGap":
                let thin = min(0.75, w / 2)
                return [(0, w), (w + 0.75, thin)]
            case "thinThickThinSmallGap", "thinThickThinMediumGap", "thinThickThinLargeGap":
                let thin = min(0.75, w / 2)
                return [(0, thin), (thin + 0.75, w), (thin + w + 1.5, thin)]
            default: return [(0, w)]
            }
        }
        // (From the text, `space` is to the line's INNER edge, so the outer
        // one lies the line's own width further out: lo-811b5975's box.)
        func extent(_ sd: Side) -> Double { strokes(sd, thickOutside: false).map { $0.0 + $0.1 }.max() ?? sd.width }
        let tEdge = top.map { fromText ? pxTopText - _px($0.space + extent($0)) : page.top + _px($0.space) }
        let lEdge = left.map { fromText ? pxLeftText - _px($0.space + extent($0)) : page.left + _px($0.space) }
        let bEdge = bottom.map { fromText ? pxBottomText + _px($0.space + extent($0)) : page.bottom - _px($0.space) }
        let rEdge = right.map { fromText ? pxRightText + _px($0.space + extent($0)) : page.right - _px($0.space) }

        let x0 = lEdge ?? page.left, x1 = rEdge ?? page.right
        let y0 = tEdge ?? page.top, y1 = bEdge ?? page.bottom

        func fill(_ r: Rect, _ color: Int64) {
            let paint = Paint()
            paint.color = Color(Int64(0xFF000000) | color)
            paint.style = .fill
            canvas.drawRect(r, paint)
        }
        func ink(_ sd: Side, _ along: (Double, Double) -> Rect) {
            for (off, th) in strokes(sd, thickOutside: false) { fill(along(_px(off), _px(th)), sd.color) }
        }
        if let sd = top {
            ink(sd) { off, th in Rect.fromLTWH(x0, y0 + off, x1 - x0, th) }
        }
        if let sd = bottom {
            ink(sd) { off, th in Rect.fromLTWH(x0, y1 - off - th, x1 - x0, th) }
        }
        if let sd = left {
            ink(sd) { off, th in Rect.fromLTWH(x0 + off, y0, th, y1 - y0) }
        }
        if let sd = right {
            ink(sd) { off, th in Rect.fromLTWH(x1 - off - th, y0, th, y1 - y0) }
        }
    }
}
