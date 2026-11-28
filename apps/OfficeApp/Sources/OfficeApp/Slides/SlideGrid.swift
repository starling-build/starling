// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// View > Show: the grid and the drawing guides, as PowerPoint keeps them in `ppt/viewProps.xml`
// (`p:cSldViewPr snapToGrid / snapToObjects / showGuides`, `p:guideLst`, `p:gridSpacing`). Whether the
// ruler and the grid are SHOWN is PowerPoint's own setting, not the file's (no corpus deck stores either), so those
// two live on the deck controller for the session only.

import Foundation
import Flutter

/// A drawing guide: a vertical line at `at` points from the slide's left edge, or a horizontal one from its top.
struct DrawingGuide: Equatable {
    var vertical: Bool
    var at: Double
}

struct SlideGridSettings: Equatable {
    /// Snap objects to grid (PowerPoint's default is on; a file says `snapToGrid="0"` to turn it off).
    var snapToGrid = true
    /// Snap objects to other objects.
    var snapToObjects = false
    /// Display drawing guides on screen.
    var showGuides = false
    /// The grid's spacing in points (PowerPoint's default 1/12 inch, `gridSpacing cx="76200"`).
    var spacing = 6.0
    var guides: [DrawingGuide] = []

    /// A guide's `pos` counts eighths of a point (576 to the inch): `pos="2880"` is 360 pt.
    static let guideUnit = 8.0
    static let emuPerPoint = 12700.0

    /// PowerPoint's Grid and Guides spacing choices, in inches, and its range (0.01 to 2 in).
    static let spacingPresets: [(String, Double)] = [("1/24\"", 3), ("1/16\"", 4.5), ("1/12\"", 6), ("1/10\"", 7.2),
                                                       ("1/8\"", 9), ("1/6\"", 12), ("1/5\"", 14.4), ("1/4\"", 18),
                                                       ("1/3\"", 24), ("1/2\"", 36), ("1\"", 72), ("2\"", 144)]
    static let spacingRange = 0.72 ... 144.0

    /// The settings in a `p:viewPr` (nil: none, which is PowerPoint's defaults).
    static func read(_ viewPr: XNode?) -> SlideGridSettings {
        var g = SlideGridSettings()
        guard let viewPr else { return g }
        if let c = viewPr.first("p:slideViewPr")?.first("p:cSldViewPr") {
            g.snapToGrid = !_false(c["snapToGrid"], default: true)
            g.snapToObjects = _on(c["snapToObjects"])
            g.showGuides = _on(c["showGuides"])
            for gd in c.first("p:guideLst")?.all("p:guide") ?? [] {
                guard let pos = gd["pos"].flatMap(Double.init) else { continue }
                g.guides.append(DrawingGuide(vertical: gd["orient"] != "horz", at: pos / guideUnit))
            }
        }
        if let cx = viewPr.first("p:gridSpacing")?["cx"].flatMap(Double.init), cx > 0 {
            g.spacing = cx / emuPerPoint
        }
        return g
    }

    private static func _on(_ v: String?) -> Bool { v == "1" || v == "true" || v == "on" }
    private static func _false(_ v: String?, default d: Bool) -> Bool {
        guard let v else { return !d }
        return v == "0" || v == "false" || v == "off"
    }

    /// Whether the slide view holds nothing but PowerPoint's defaults (a deck without one need not get one).
    var viewIsDefault: Bool { snapToGrid && !snapToObjects && !showGuides && guides.isEmpty }

    var spacingEMU: Int { Int((spacing * Self.emuPerPoint).rounded()) }

    /// `p:cSldViewPr`'s attributes: only those that differ from the defaults, as PowerPoint writes them.
    var viewAttributes: String {
        (snapToGrid ? "" : " snapToGrid=\"0\"") + (snapToObjects ? " snapToObjects=\"1\"" : "") + (showGuides ? " showGuides=\"1\"" : "")
    }

    var guideListXML: String {
        guard !guides.isEmpty else { return "<p:guideLst/>" }
        return "<p:guideLst>" + guides.map { g in
            "<p:guide" + (g.vertical ? "" : " orient=\"horz\"") + " pos=\"\(Int((g.at * Self.guideUnit).rounded()))\"/>"
        }.joined() + "</p:guideLst>"
    }

    /// `xml` (a whole `ppt/viewProps.xml`) with these settings in place; everything else in it is kept.
    func apply(to xml: String) -> String {
        var s = xml
        // The slide view: rewrite cSldViewPr's own attributes and its guide list, keep its cViewPr (zoom and origin).
        if let open = s.rangeOfSubstring("<p:cSldViewPr"), s.rangeOfSubstring("<p:slideViewPr")?.lowerBound ?? s.endIndex < open.lowerBound,
           let tagEnd = s.rangeOfSubstring(">", in: open.upperBound ..< s.endIndex) {
            let selfClosing = s[s.index(before: tagEnd.lowerBound)] == "/"
            let keepAttrs = Self._otherAttributes(String(s[open.upperBound ..< (selfClosing ? s.index(before: tagEnd.lowerBound) : tagEnd.lowerBound)]))
            if selfClosing {
                s.replaceSubrange(open.lowerBound ..< tagEnd.upperBound,
                                  with: "<p:cSldViewPr\(keepAttrs)\(viewAttributes)>\(Self.defaultCViewPr)\(guideListXML)</p:cSldViewPr>")
            } else {
                s.replaceSubrange(open.lowerBound ..< tagEnd.upperBound, with: "<p:cSldViewPr\(keepAttrs)\(viewAttributes)>")
                // (Only this view's list: the notes view has a cSldViewPr and guides of its own.)
                if let close = s.rangeOfSubstring("</p:cSldViewPr>", in: open.lowerBound ..< s.endIndex) {
                    let own = open.lowerBound ..< close.lowerBound
                    if let gl = s.rangeOfSubstring("<p:guideLst/>", in: own) ?? Self._element("p:guideLst", in: s, own) {
                        s.replaceSubrange(gl, with: guideListXML)
                    } else {
                        s.insert(contentsOf: guideListXML, at: close.lowerBound)
                    }
                }
            }
        } else if !viewIsDefault {
            let block = "<p:slideViewPr><p:cSldViewPr\(viewAttributes)>\(Self.defaultCViewPr)\(guideListXML)</p:cSldViewPr></p:slideViewPr>"
            if let n = s.rangeOfSubstring("</p:normalViewPr>") {
                s.insert(contentsOf: block, at: n.upperBound)
            } else if let n = s.rangeOfSubstring("<p:normalViewPr"), let e = s.rangeOfSubstring("/>", in: n.upperBound ..< s.endIndex) {
                s.insert(contentsOf: block, at: e.upperBound)
            } else if let root = s.rangeOfSubstring("<p:viewPr"), let e = s.rangeOfSubstring(">", in: root.upperBound ..< s.endIndex) {
                s.insert(contentsOf: block, at: e.upperBound)
            }
        }
        // The grid's spacing, after every view (only extLst follows it).
        let spacingXML = "<p:gridSpacing cx=\"\(spacingEMU)\" cy=\"\(spacingEMU)\"/>"
        if let g = s.rangeOfSubstring("<p:gridSpacing"), let e = s.rangeOfSubstring("/>", in: g.upperBound ..< s.endIndex) {
            if spacingEMU != Self._spacing(String(s[g.lowerBound ..< e.upperBound])) {
                s.replaceSubrange(g.lowerBound ..< e.upperBound, with: spacingXML)
            }
        } else if let x = s.rangeOfSubstring("<p:extLst") ?? s.rangeOfSubstring("</p:viewPr>") {
            s.insert(contentsOf: spacingXML, at: x.lowerBound)
        }
        // cViewPr's scale and origin are in the drawing namespace.
        if s.rangeOfSubstring("<a:sx") != nil, s.rangeOfSubstring("xmlns:a=") == nil,
           let root = s.rangeOfSubstring("<p:viewPr") {
            s.insert(contentsOf: " xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"", at: root.upperBound)
        }
        return s
    }

    /// The zoom PowerPoint writes in a new deck's slide view (cViewPr's scale and origin are required).
    static let defaultCViewPr = "<p:cViewPr varScale=\"1\"><p:scale><a:sx n=\"100\" d=\"100\"/><a:sy n=\"100\" d=\"100\"/></p:scale><p:origin x=\"0\" y=\"0\"/></p:cViewPr>"

    private static func _spacing(_ tag: String) -> Int? {
        guard let r = tag.rangeOfSubstring("cx=\"") , let e = tag.rangeOfSubstring("\"", in: r.upperBound ..< tag.endIndex) else { return nil }
        return Int(tag[r.upperBound ..< e.lowerBound])
    }

    /// `attrs` (the inside of an open tag) without the three this type writes.
    private static func _otherAttributes(_ attrs: String) -> String {
        var out = ""
        var rest = Substring(attrs)
        while let eq = rest.firstIndex(of: "=") {
            let name = String(rest[..<eq]).trimmingWhitespace()
            guard let q1 = rest[eq...].firstIndex(where: { $0 == "\"" || $0 == "'" }) else { break }
            let quote = rest[q1]
            guard let q2 = rest[rest.index(after: q1)...].firstIndex(of: quote) else { break }
            if !["snapToGrid", "snapToObjects", "showGuides"].contains(name) { out += " " + String(rest[..<rest.index(after: q2)]).trimmingWhitespace() }
            rest = rest[rest.index(after: q2)...]
        }
        return out
    }

    private static func _element(_ name: String, in s: String, _ within: Range<String.Index>) -> Range<String.Index>? {
        guard let a = s.rangeOfSubstring("<\(name)>", in: within), let b = s.rangeOfSubstring("</\(name)>", in: a.upperBound ..< within.upperBound) else { return nil }
        return a.lowerBound ..< b.upperBound
    }

    /// The nearest grid line to `v` points.
    func snapped(_ v: Double) -> Double { spacing > 0 ? (v / spacing).rounded() * spacing : v }
}
