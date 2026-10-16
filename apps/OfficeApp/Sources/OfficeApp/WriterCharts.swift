// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Charts in Writer: a .docx keeps a chart (`c:chart` in a drawing) as an
// object of its size, which the layout cannot draw. Its part is read as
// Slides reads a chart (`ChartXML.read`) against the document's theme,
// and drawn by Slides' painter through `RichLayout.objectPainter`, by the
// attachment's id. Without this, 61745's page — two charts and nothing
// else — printed blank.

import Flutter
import FlutterSwiftBridge
import Foundation

enum WriterCharts {
    private struct Entry {
        let chart: Chart
        let theme: DeckTheme
        /// The chart area's own fill and border (`c:chartSpace/c:spPr`):
        /// Word's default is white with a light grey line.
        let fill: Color?
        let line: Color?
        let lineWidth: Double
    }

    private nonisolated(unsafe) static var entries: [String: Entry] = [:]
    private static let lock = NSLock()

    /// Reads the chart in `space` (a chart part's `c:chartSpace`), its
    /// colours from `themePart` (the document's `a:theme`), for the
    /// object attachment `id`; false where it is no chart this can draw.
    @discardableResult
    static func register(_ space: XNode, for id: String, themePart: Data?) -> Bool {
        let pptxTheme = PptxTheme(themePart.flatMap { XNode.parse($0) })
        let colors = ColorContext(theme: pptxTheme)
        guard let chart = ChartXML.read(space, color: { colors.color(in: $0) }) else { return false }
        var theme = DeckTheme()
        theme.headingFont = pptxTheme.major
        theme.bodyFont = pptxTheme.minor
        if let text = colors.scheme("tx1") { theme.text = text }
        if let background = colors.scheme("bg1") { theme.background = background }
        let accents = (1 ... 6).compactMap { colors.scheme("accent\($0)") }
        if accents.count == 6 { theme.accents = accents }
        let area = space.first("c:spPr")
        let fill = area?.first("a:solidFill").flatMap { colors.color(in: $0) }
        let ln = area?.first("a:ln")
        let line = ln?.first("a:solidFill").flatMap { colors.color(in: $0) }
        let entry = Entry(chart: chart, theme: theme, fill: fill, line: line,
                          lineWidth: (ln?["w"]).flatMap { Double($0) }.map { $0 / 12700 } ?? 0.75)
        lock.lock()
        entries[id] = entry
        lock.unlock()
        installHooks()
        return true
    }

    /// Whether a chart is registered for `attachment`.
    static func has(_ attachment: ImageAttachment) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[attachment.id] != nil
    }

    /// Draws the chart registered for `attachment` into `rect`; false
    /// where none is.
    static func paint(_ attachment: ImageAttachment, _ canvas: any Canvas, _ rect: Rect, _ pxPerPt: Double) -> Bool {
        lock.lock()
        let entry = entries[attachment.id]
        lock.unlock()
        guard let entry else { return false }
        if let fill = entry.fill {
            let p = Paint()
            p.style = .fill
            p.color = fill
            canvas.drawRect(rect, p)
        }
        ChartPainter.paint(entry.chart, canvas, rect, pxPerPt: pxPerPt, theme: entry.theme)
        if let line = entry.line {
            let p = Paint()
            p.style = .stroke
            p.strokeWidth = max(1, entry.lineWidth * pxPerPt)
            p.color = line
            canvas.drawRect(rect, p)
        }
        return true
    }

    /// The layout's hooks for the objects Writer draws itself: charts,
    /// and the metafile pictures of embedded objects (`WriterMetafiles`).
    static func installHooks() {
        if RichLayout.drawsObject == nil {
            RichLayout.drawsObject = { WriterCharts.has($0) || WriterMetafiles.has($0) || WriterGroups.has($0) }
        }
        if RichLayout.objectPainter == nil {
            RichLayout.objectPainter = { attachment, canvas, rect, pxPerPt in
                WriterCharts.paint(attachment, canvas, rect, pxPerPt) || WriterMetafiles.paint(attachment, canvas, rect)
                    || WriterGroups.paint(attachment, canvas, rect, pxPerPt)
            }
        }
    }
}

/// Metafile pictures in Writer: an embedded object (`w:object`, an OLE
/// package or document) shows the WMF or EMF its `v:imagedata` names —
/// the icon and its caption, or the first page of the document. No image
/// codec reads those, so the object printed as nothing (tika-3388's
/// "約翰的測試文件 .msg", WordWithAttachments' five attachments). Played
/// by Slides' player, by the attachment's id; the bitmaps a metafile
/// carries are not drawn here.
enum WriterMetafiles {
    private nonisolated(unsafe) static var entries: [String: Metafile] = [:]
    private static let lock = NSLock()

    /// Plays `data` for the object attachment `id`; false where it is no
    /// metafile this can draw.
    @discardableResult
    static func register(_ data: Data, for id: String) -> Bool {
        guard let played = Metafile(data, id: id) else { return false }
        lock.lock()
        entries[id] = played
        lock.unlock()
        WriterCharts.installHooks()
        return true
    }

    static func has(_ attachment: ImageAttachment) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[attachment.id] != nil
    }

    static func paint(_ attachment: ImageAttachment, _ canvas: any Canvas, _ rect: Rect) -> Bool {
        lock.lock()
        let played = entries[attachment.id]
        lock.unlock()
        guard let played else { return false }
        played.paint(canvas, in: rect, image: { _ in nil }, font: OfficeFonts.substitute)
        return true
    }
}

/// The lines and boxes of a drawing group (`wpg:wgp`) in Writer, drawn
/// through `RichLayout.objectPainter` by the attachment's id, each at its
/// own place in the group; the group's text boxes are set by the layout
/// (`RichTextBox.parts`). The group was drawn as its first child alone,
/// stretched over the whole of it: zh-06c46ba9's tree of labelled boxes,
/// whose first child is a connector, printed as one diagonal line across
/// the figure and boxes with no edges.
enum WriterGroups {
    private struct Shape {
        var rect: Rect
        var fill: Color?
        var line: Color?
        var lineWidth: Double
        var isLine: Bool
        /// A line from the bottom left to the top right (flipped one way).
        var rising: Bool
    }
    private struct Entry {
        let width: Double
        let height: Double
        let shapes: [Shape]
    }
    private nonisolated(unsafe) static var entries: [String: Entry] = [:]
    private static let lock = NSLock()

    /// Reads the straight lines and rectangles of `group` (a `wpg:wgp`),
    /// in points from its top left, for the object attachment `id`; false
    /// where it has none to draw.
    @discardableResult
    static func register(_ group: XNode, for id: String, themePart: Data?) -> Bool {
        let theme = PptxTheme(themePart.flatMap { XNode.parse($0) })
        let colors = ColorContext(theme: theme)
        guard let top = group.first("wpg:grpSpPr")?.first("a:xfrm") else { return false }
        func number(_ n: XNode?, _ key: String) -> Double { Double(n?[key] ?? "") ?? 0 }
        let width = number(top.first("a:ext"), "cx"), height = number(top.first("a:ext"), "cy")
        guard width > 0, height > 0 else { return false }
        // Child space → the group's, in EMU from its top left.
        typealias Map = (Rect) -> Rect
        func map(_ xfrm: XNode, outer: @escaping Map) -> Map {
            let off = xfrm.first("a:off"), ext = xfrm.first("a:ext")
            let chOff = xfrm.first("a:chOff"), chExt = xfrm.first("a:chExt")
            let kx = number(chExt, "cx") > 0 ? number(ext, "cx") / number(chExt, "cx") : 1
            let ky = number(chExt, "cy") > 0 ? number(ext, "cy") / number(chExt, "cy") : 1
            let ox = number(off, "x"), oy = number(off, "y"), cx = number(chOff, "x"), cy = number(chOff, "y")
            return { r in
                outer(Rect.fromLTWH(ox + (r.left - cx) * kx, oy + (r.top - cy) * ky, r.width * kx, r.height * ky))
            }
        }
        // The outermost group's own offset is where it stands, not a
        // place inside it.
        let root = map(top) { r in r.shift(Offset(-number(top.first("a:off"), "x"), -number(top.first("a:off"), "y"))) }
        var shapes: [Shape] = []
        func walk(_ node: XNode, _ place: @escaping Map) {
            for child in node.children {
                switch child.name {
                case "wpg:grpSp":
                    if let xfrm = child.first("wpg:grpSpPr")?.first("a:xfrm") { walk(child, map(xfrm, outer: place)) }
                case "wps:wsp":
                    guard let sp = child.first("wps:spPr"), let prst = sp.first("a:prstGeom")?["prst"],
                          ["line", "straightConnector1", "rect"].contains(prst), let xfrm = sp.first("a:xfrm") else { continue }
                    let at = place(Rect.fromLTWH(number(xfrm.first("a:off"), "x"), number(xfrm.first("a:off"), "y"),
                                                 number(xfrm.first("a:ext"), "cx"), number(xfrm.first("a:ext"), "cy")))
                    let style = child.first("wps:style")
                    func styled(_ ref: String) -> (Color?, Int) {
                        guard let r = style?.first(ref), let idx = Int(r["idx"] ?? ""), idx > 0 else { return (nil, 0) }
                        return (colors.color(in: r), idx)
                    }
                    let isLine = prst != "rect"
                    var fill: Color? = nil
                    if !isLine {
                        if sp.first("a:noFill") != nil { fill = nil }
                        else if let f = sp.first("a:solidFill") { fill = colors.color(in: f) }
                        else { fill = styled("a:fillRef").0 }
                    }
                    let ln = sp.first("a:ln")
                    var line: Color? = nil
                    var lineWidth = (ln?["w"]).flatMap { Double($0) }.map { $0 / 12700 }
                    if ln?.first("a:noFill") != nil { line = nil }
                    else if let f = ln?.first("a:solidFill") { line = colors.color(in: f) }
                    else {
                        let (c, idx) = styled("a:lnRef")
                        line = c
                        if lineWidth == nil, idx > 0, idx <= theme.lineWidths.count { lineWidth = theme.lineWidths[idx - 1] }
                    }
                    guard fill != nil || line != nil else { continue }
                    let flipH = xfrm["flipH"] == "1", flipV = xfrm["flipV"] == "1"
                    shapes.append(Shape(rect: Rect.fromLTWH(at.left / 12700, at.top / 12700, at.width / 12700, at.height / 12700),
                                        fill: fill, line: line, lineWidth: lineWidth ?? 0.75, isLine: isLine, rising: flipH != flipV))
                default: continue
                }
            }
        }
        walk(group, root)
        guard !shapes.isEmpty else { return false }
        lock.lock()
        entries[id] = Entry(width: width / 12700, height: height / 12700, shapes: shapes)
        lock.unlock()
        WriterCharts.installHooks()
        return true
    }

    static func has(_ attachment: ImageAttachment) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[attachment.id] != nil
    }

    static func paint(_ attachment: ImageAttachment, _ canvas: any Canvas, _ rect: Rect, _ pxPerPt: Double) -> Bool {
        lock.lock()
        let entry = entries[attachment.id]
        lock.unlock()
        guard let entry else { return false }
        let sx = rect.width / entry.width, sy = rect.height / entry.height
        for s in entry.shapes {
            let r = Rect.fromLTWH(rect.left + s.rect.left * sx, rect.top + s.rect.top * sy, s.rect.width * sx, s.rect.height * sy)
            if let fill = s.fill {
                let p = Paint()
                p.style = .fill
                p.color = fill
                canvas.drawRect(r, p)
            }
            if let line = s.line {
                let p = Paint()
                p.style = .stroke
                p.strokeWidth = max(1, s.lineWidth * pxPerPt)
                p.color = line
                if s.isLine {
                    canvas.drawLine(s.rising ? r.bottomLeft : r.topLeft, s.rising ? r.topRight : r.bottomRight, p)
                } else {
                    canvas.drawRect(r, p)
                }
            }
        }
        return true
    }
}
