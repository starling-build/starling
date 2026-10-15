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
            RichLayout.drawsObject = { WriterCharts.has($0) || WriterMetafiles.has($0) }
        }
        if RichLayout.objectPainter == nil {
            RichLayout.objectPainter = { attachment, canvas, rect, pxPerPt in
                WriterCharts.paint(attachment, canvas, rect, pxPerPt) || WriterMetafiles.paint(attachment, canvas, rect)
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
