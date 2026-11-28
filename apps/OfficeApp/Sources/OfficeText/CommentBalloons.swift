// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// Word's markup area on screen (All Markup, Show Comments on): the pages move left to leave a strip on their right,
/// each comment thread stands there in a card level with its text, a dashed line runs from the end of the text it
/// covers to its card, and the commented text is shaded. Screen only: the PDF's markup pane is `PdfMarkup`'s.
public enum CommentMargin {
    /// One card: the thread's top comment, where the card stands and where its text ends (canvas coordinates).
    public struct Balloon {
        public var id: String
        public var rect: Rect
        public var anchor: Rect
        public var shade: [Rect]
        public var done: Bool
        var lines: [(TextPainter, Offset)]
    }

    /// The strip's width in pixels: about 2.5 inches at 100%, as Word's balloons take.
    public static func width(_ layout: RichLayout) -> Double { 180 * layout.theme.pixelsPerPoint * layout.scale }

    /// The cards for `threads`, in a strip that starts at canvas x `left`: each at its text's top, pushed down below
    /// the card before it so none overlap.
    public static func layout(_ threads: [RichDocumentController.CommentThread], layout: RichLayout, document: RichDocument,
                              left: Double) -> [Balloon] {
        let px = layout.theme.pixelsPerPoint * layout.scale
        let gap = 8 * px, pad = 6 * px
        let cardW = width(layout) - 2 * gap
        var out: [Balloon] = []
        var floor = -Double.infinity
        let placed = threads.map { t -> (RichDocumentController.CommentThread, [Rect], Rect) in
            let sel = RichSelection(anchor: t.range.start, focus: t.range.end)
            let shade = t.range.start == t.range.end ? [] : layout.canvasSelectionRects(sel, document)
            let anchor = shade.last ?? layout.canvasCaretRect(t.range.end, document)
            return (t, shade, anchor)
        }.sorted { ($0.1.first ?? $0.2).top < ($1.1.first ?? $1.2).top }
        for (t, shade, anchor) in placed {
            let ink = t.comment.done ? Color(0xFF8A8A8A) : Color(0xFF1B1B1B)
            var lines: [(TextPainter, Offset)] = []
            var y = pad
            func add(_ text: String, bold: Bool = false, size: Double = 9, indent: Double = 0, color: Color? = nil) {
                guard !text.isEmpty else { return }
                let tp = TextPainter(text: TextSpan(text: text, style: TextStyle(color: color ?? ink, fontSize: size * px,
                                                                                 fontWeight: bold ? .bold : .normal)),
                                     textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: max(1, cardW - 2 * pad - indent))
                lines.append((tp, Offset(pad + indent, y)))
                y += tp.height + 1 * px
            }
            add(t.comment.author.isEmpty ? "Comment" : t.comment.author, bold: true)
            add(t.comment.text)
            for r in t.replies {
                y += 3 * px
                add(r.author.isEmpty ? "Reply" : r.author, bold: true, size: 8, indent: 8 * px)
                add(r.text, size: 8, indent: 8 * px)
            }
            if t.comment.done { y += 2 * px; add("Resolved", size: 8, color: Color(0xFF5C7F3A)) }
            let top = max(shade.first?.top ?? anchor.top, floor)
            let rect = Rect.fromLTWH(left + gap, top, cardW, y + pad - 1 * px)
            floor = rect.bottom + 4 * px
            out.append(Balloon(id: t.comment.id, rect: rect, anchor: anchor, shade: shade, done: t.comment.done, lines: lines))
        }
        return out
    }

    /// Paints the shading, the dashed lines and the cards that meet `visible`; the card of `current` (the comment at
    /// the caret) is framed in the accent colour.
    public static func paint(_ balloons: [Balloon], canvas: any Canvas, visible: Rect, pageRight: Double, current: String?,
                             px: Double) {
        let shade = Paint()
        shade.style = .fill
        for b in balloons {
            shade.color = b.done ? Color(0x22A0A0A0) : Color(0x55F5C26B)
            for r in b.shade where r.overlaps(visible) { canvas.drawRect(r, shade) }
        }
        let line = Paint()
        line.style = .stroke
        line.strokeWidth = max(1, px * 0.75)
        let fill = Paint()
        fill.style = .fill
        let edge = Paint()
        edge.style = .stroke
        for b in balloons where b.rect.overlaps(visible) || b.anchor.overlaps(visible) {
            let on = b.id == current
            line.color = on ? Color(0xFF2B579A) : Color(0xFFB4B4B4)
            let y = b.anchor.bottom
            let mid = Offset(pageRight, y)
            _dash(canvas, Offset(b.anchor.right, y), mid, line, px)
            _dash(canvas, mid, Offset(b.rect.left, b.rect.top + 8 * px), line, px)
            fill.color = b.done ? Color(0xFFF4F4F4) : Color(0xFFFFFFFF)
            edge.color = on ? Color(0xFF2B579A) : Color(0xFFC8C8C8)
            edge.strokeWidth = on ? max(1.5, px) : 1
            let card = RRect(fromRectAndRadius: b.rect, Radius(circular: 3 * px))
            canvas.drawRRect(card, fill)
            canvas.drawRRect(card, edge)
            for (tp, at) in b.lines { tp.paint(canvas, Offset(b.rect.left + at.dx, b.rect.top + at.dy)) }
        }
    }

    private static func _dash(_ canvas: any Canvas, _ a: Offset, _ b: Offset, _ paint: Paint, _ px: Double) {
        let dx = b.dx - a.dx, dy = b.dy - a.dy
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return }
        let on = 3 * px, step = 5 * px
        var s = 0.0
        while s < len {
            let e = min(len, s + on)
            canvas.drawLine(Offset(a.dx + dx * s / len, a.dy + dy * s / len), Offset(a.dx + dx * e / len, a.dy + dy * e / len), paint)
            s += step
        }
    }
}
