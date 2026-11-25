// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// Where everything on the ruler is, in widget pixels, and what a pointer at a place means.
/// Pure, so the drag rules are tested without a screen.
struct RulerGeometry {
    let setup: PageSetup
    let px: Double          // pixels per point at this zoom
    let pad: Double
    let width: Double       // the ruler widget's width
    static let top = 4.0, band = 14.0
    /// Painted rows are 22 high; a touch ruler is taller (44) and its rows sit in the middle, so a finger's slop above and below
    /// the markers is still on the ruler. This is how far a finger may be off the rows, vertically.
    static let touchSlop = 11.0
    /// How far from a marker a finger still takes it, pixels (a 44-point target).
    static let touchNear = 22.0
    static let snap = 4.5   // points: a new or dragged stop lands on a 1/16 inch

    var pageW: Double { setup.width * px }
    var originX: Double { max(pad, ((width - pageW) / 2).rounded()) }
    var contentL: Double { originX + setup.marginLeft * px }
    var contentW: Double { setup.contentWidth * px }
    var mid: Double { Self.top + Self.band / 2 }
    /// Points from the left margin for a pixel x.
    func points(_ x: Double) -> Double { (x - contentL) / px }
    func x(_ points: Double) -> Double { contentL + points * px }

    enum Target: Equatable { case firstLine, leftIndent, rightIndent, tab(Int), newTab, kindBox }

    /// What a press at `p` grabs: an indent marker (top half = first line, bottom half = left and right
    /// indents), an existing tab stop, the kind box, or empty ruler inside the text column (a new stop).
    func target(at p: Offset, style: RichParagraphStyle, touch: Bool = false) -> Target? {
        let slop = touch ? Self.touchSlop : 0
        guard p.dy >= Self.top - 2 - slop, p.dy <= Self.top + Self.band + 2 + slop else { return nil }
        if p.dx < originX - 2 && p.dx >= 2 && originX - 2 >= 22 { return .kindBox }
        let top = p.dy <= mid
        if touch {
            // A finger covers more than a marker: the nearest marker within 44 points wide takes it (the first-line marker only
            // from the upper half, the indents from the lower, a tab stop from either); a tie goes to an indent.
            var best: (Target, Double)?
            func consider(_ t: Target, _ markerX: Double) {
                let d = abs(p.dx - markerX)
                if d <= Self.touchNear, d < (best?.1 ?? .infinity) { best = (t, d) }
            }
            if top { consider(.firstLine, x(style.indentLeft + style.firstLineIndent)) }
            else {
                consider(.leftIndent, x(style.indentLeft))
                consider(.rightIndent, x(setup.contentWidth - style.indentRight))
            }
            for (i, t) in style.tabStops.enumerated() { consider(.tab(i), x(t.position)) }
            if let best { return best.0 }
        } else {
            let near = 6.0
            if top, abs(p.dx - x(style.indentLeft + style.firstLineIndent)) <= near { return .firstLine }
            if !top {
                if abs(p.dx - x(style.indentLeft)) <= near { return .leftIndent }
                if abs(p.dx - x(setup.contentWidth - style.indentRight)) <= near { return .rightIndent }
            }
            if let i = style.tabStops.indices.min(by: { abs(x(style.tabStops[$0].position) - p.dx) < abs(x(style.tabStops[$1].position) - p.dx) }),
               abs(x(style.tabStops[i].position) - p.dx) <= 4 { return .tab(i) }
        }
        if p.dx >= contentL, p.dx <= contentL + contentW { return .newTab }
        return nil
    }

    /// Where `target`'s marker is, in pixels, or nil for one that is not at a place (a new stop, the kind box).
    func markerX(_ target: Target, style: RichParagraphStyle) -> Double? {
        switch target {
        case .firstLine: return x(style.indentLeft + style.firstLineIndent)
        case .leftIndent: return x(style.indentLeft)
        case .rightIndent: return x(setup.contentWidth - style.indentRight)
        case .tab(let i): return style.tabStops.indices.contains(i) ? x(style.tabStops[i].position) : nil
        case .newTab, .kindBox: return nil
        }
    }

    /// What the magnified readout says while `target` is dragged to `p`: the value the drop would set, in inches from the left
    /// margin (the right indent from the right margin), or that dropping would remove a tab stop.
    func readout(_ target: Target, to p: Offset, style: RichParagraphStyle) -> String? {
        let pt = max(0, min(setup.contentWidth, points(p.dx)))
        func inches(_ v: Double) -> String { LengthUnit.inch.format(points: v) }
        switch target {
        case .firstLine: return "First line " + inches(max(0, snapped(pt)))
        case .leftIndent: return "Left " + inches(max(0, snapped(pt)))
        case .rightIndent: return "Right " + inches(max(0, snapped(setup.contentWidth - pt)))
        case .tab:
            if p.dy < Self.top - 12 || p.dy > Self.top + Self.band + 12 { return "Remove tab" }
            return "Tab " + inches(snapped(pt))
        case .newTab: return "Tab " + inches(snapped(pt))
        case .kindBox: return nil
        }
    }

    private func snapped(_ pts: Double) -> Double { (pts / Self.snap).rounded() * Self.snap }

    /// The paragraph format a drag of `target` to pixel `p` means. Moving a tab stop off the ruler
    /// (more than 12 px above or below the band) removes it.
    func format(_ target: Target, to p: Offset, style: RichParagraphStyle, kind: TabKind) -> RichDocumentController.ParagraphFormat? {
        let pt = max(0, min(setup.contentWidth, points(p.dx)))
        switch target {
        case .firstLine:
            let first = max(0, snapped(pt))
            return .init(firstLineIndent: first - style.indentLeft)
        case .leftIndent:
            let abs0 = style.indentLeft + style.firstLineIndent
            let left = max(0, snapped(pt))
            return .init(indentLeft: left, firstLineIndent: abs0 - left)
        case .rightIndent:
            return .init(indentRight: max(0, snapped(setup.contentWidth - pt)))
        case .tab(let i):
            guard style.tabStops.indices.contains(i) else { return nil }
            var stops = style.tabStops
            var t = stops.remove(at: i)
            if p.dy >= Self.top - 12 && p.dy <= Self.top + Self.band + 12 {
                t.position = snapped(pt)
                stops.removeAll { abs($0.position - t.position) < TabStopEditor.same }
                stops.append(t)
                stops.sort { $0.position < $1.position }
            }
            return .init(tabStops: stops)
        case .newTab:
            var ed = TabStopEditor(stops: style.tabStops)
            ed.set(at: snapped(pt), kind: kind, leader: .none)
            return .init(tabStops: ed.stops)
        case .kindBox:
            return nil
        }
    }
}

/// Word's horizontal ruler: inch ticks across the page width, the margins shaded, centred over the
/// page exactly as RichEditable centres it. The markers are live: drag the top triangle (first line),
/// the bottom triangle (left indent) or the right one (right indent); click the ruler to add a tab
/// stop of the kind in the box at its left end (click the box to change the kind); drag a stop to
/// move it, or off the ruler to remove it. One drag is one undo step.
final class Ruler: StatefulWidget {
    let setup: PageSetup
    let zoom: Double
    let pixelsPerPoint: Double
    let sidePadding: Double
    let style: RichParagraphStyle
    let onFormat: (RichDocumentController.ParagraphFormat) -> Void

    init(setup: PageSetup, zoom: Double, pixelsPerPoint: Double, sidePadding: Double, style: RichParagraphStyle,
         onFormat: @escaping (RichDocumentController.ParagraphFormat) -> Void = { _ in }) {
        self.setup = setup
        self.zoom = zoom
        self.pixelsPerPoint = pixelsPerPoint
        self.sidePadding = sidePadding
        self.style = style
        self.onFormat = onFormat
        super.init(key: ValueKey("ruler"))
    }

    /// The ruler's height: a finger's target (44) on a touch device, 22 with a pointer.
    static let height: Double = {
        #if os(iOS)
        return 44
        #else
        return 22
        #endif
    }()

    override func createState() -> State<StatefulWidget> { RulerState() }
}

final class RulerState: State<StatefulWidget> {
    private var _w: Ruler { widget as! Ruler }
    private(set) var kind = TabKind.left
    private var _drag: (target: RulerGeometry.Target, last: RichDocumentController.ParagraphFormat?)?
    /// The style while a drag is under way, so the markers follow the pointer.
    private var _live: RichParagraphStyle?
    /// The finger's magnified readout: its text and where the finger is, while a touch drag is under way.
    private(set) var readout: (text: String, x: Double)?
    private var _touchDrag = false
    /// Where the marker is from where the finger took it, pixels: a finger covers its marker, so it drags it by the offset it grabbed it at.
    private var _grabDX = 0.0

    private func _geometry() -> RulerGeometry? {
        guard let box = context?.findRenderObject() as? RenderBox else { return nil }
        return RulerGeometry(setup: _w.setup, px: _w.pixelsPerPoint * _w.zoom, pad: _w.sidePadding, width: box.size.width)
    }

    /// The pointer in the painted rows' space: a touch ruler is taller than the rows (see `RulerGeometry.touchSlop`), which sit in its middle.
    private func _local(_ e: PointerEvent) -> Offset {
        guard let box = context?.findRenderObject() as? RenderBox else { return e.localPosition }
        return Offset(e.localPosition.dx + _grabDX, e.localPosition.dy - ((box.size.height - 22) / 2).rounded())
    }

    private func _down(_ e: PointerEvent) {
        let touch = e.kind == .touch
        _grabDX = 0
        guard let g = _geometry(), let t = g.target(at: _local(e), style: _w.style, touch: touch) else { return }
        if t == .kindBox {
            let all = TabKind.allCases
            setState { self.kind = all[(all.firstIndex(of: self.kind)! + 1) % all.count] }
            return
        }
        _drag = (t, nil)
        _touchDrag = touch
        _grabDX = touch ? (g.markerX(t, style: _w.style).map { $0 - e.localPosition.dx } ?? 0) : 0
        _move(e)
    }

    private func _move(_ e: PointerEvent) {
        guard let d = _drag, let g = _geometry(),
              let f = g.format(d.target, to: _local(e), style: _w.style, kind: kind) else { return }
        _drag = (d.target, f)
        var s = _w.style
        if let v = f.indentLeft { s.indentLeft = v }
        if let v = f.indentRight { s.indentRight = v }
        if let v = f.firstLineIndent { s.firstLineIndent = v }
        if let v = f.tabStops { s.tabStops = v }
        let text = _touchDrag ? g.readout(d.target, to: _local(e), style: _w.style) : nil
        setState {
            self._live = s
            self.readout = text.map { ($0, _local(e).dx) }
        }
    }

    private func _up(_ e: PointerEvent) {
        _move(e)
        let f = _drag?.last
        _drag = nil
        _touchDrag = false
        _grabDX = 0
        setState { self._live = nil; self.readout = nil }
        if let f { _w.onFormat(f) }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let ruler = Listener(
            onPointerDown: { [weak self] e in self?._down(e) },
            onPointerMove: { [weak self] e in self?._move(e) },
            onPointerUp: { [weak self] e in self?._up(e) },
            child: SizedBox(width: nil, height: Ruler.height, child: CustomPaint(
                painter: _RulerPainter(setup: _w.setup, px: _w.pixelsPerPoint * _w.zoom, pad: _w.sidePadding,
                                       style: _live ?? _w.style, kind: kind,
                                       background: OfficeAppearance.canvas(fluent),
                                       paper: fluent.brightness == .dark ? Color(0xFF3A3A3A) : Color(0xFFFFFFFF),
                                       margin: fluent.brightness == .dark ? Color(0xFF28364E) : Color(0xFFDBE3F0),
                                       ink: fluent.resources.textFillColorSecondary,
                                       accent: fluent.accentColor.defaultBrushFor(fluent.brightness)),
                child: SizedBox(expand: ()))))
        // One Stack always, so the Listener holding a gesture is never remounted when the readout appears.
        var children: [Widget] = [ruler]
        if let readout {
            // The finger hides its own marker, so the value is shown big beside it, on the side with room.
            let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
            let pill = IgnorePointer(child: DecoratedBox(
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.all(Radius(circular: 8))),
                child: Padding(padding: EdgeInsets(left: 12, top: 4, right: 12, bottom: 4),
                               child: Text(readout.text, style: fluent.typography.bodyStrong?.copyWith(color: Color(0xFFFFFFFF), fontSize: 20)))))
            let width = (self.context?.findRenderObject() as? RenderBox)?.size.width ?? 800
            children.append(readout.x > width / 2
                ? Positioned(top: 4, right: max(0, width - readout.x + 40), child: pill)
                : Positioned(left: max(0, readout.x + 40), top: 4, child: pill))
        }
        return Stack(clipBehavior: .none, children: children)
    }
}

private final class _RulerPainter: CustomPainter {
    let setup: PageSetup
    let px: Double
    let pad: Double
    let style: RichParagraphStyle
    let kind: TabKind
    let background: Color
    let paper: Color
    let margin: Color
    let ink: Color
    let accent: Color

    init(setup: PageSetup, px: Double, pad: Double, style: RichParagraphStyle, kind: TabKind, background: Color,
         paper: Color, margin: Color, ink: Color, accent: Color) {
        self.setup = setup
        self.px = px
        self.pad = pad
        self.style = style
        self.kind = kind
        self.background = background
        self.paper = paper
        self.margin = margin
        self.ink = ink
        self.accent = accent
        super.init()
    }

    /// A tab stop's mark: an L, a mirrored L, a T, a T with a dot, or a bar.
    private func glyph(_ canvas: any Canvas, _ k: TabKind, x: Double, base: Double, _ line: Paint) {
        let h = 6.0
        switch k {
        case .bar: canvas.drawLine(Offset(x, base - 12), Offset(x, base), line)
        case .left: canvas.drawLine(Offset(x, base - h), Offset(x, base), line); canvas.drawLine(Offset(x, base), Offset(x + 4, base), line)
        case .right: canvas.drawLine(Offset(x, base - h), Offset(x, base), line); canvas.drawLine(Offset(x - 4, base), Offset(x, base), line)
        case .center: canvas.drawLine(Offset(x, base - h), Offset(x, base), line); canvas.drawLine(Offset(x - 4, base), Offset(x + 4, base), line)
        case .decimal:
            canvas.drawLine(Offset(x, base - h), Offset(x, base), line); canvas.drawLine(Offset(x - 4, base), Offset(x + 4, base), line)
            canvas.drawRect(Rect.fromLTWH(x + 2, base - 4, 1.5, 1.5), line)
        }
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let fill = Paint()
        fill.style = .fill
        fill.color = background
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), fill)

        let pageW = setup.width * px
        let originX = max(pad, ((size.width - pageW) / 2).rounded())
        // The rows are 22 high whatever the widget's height: a touch ruler (44) paints them in the middle.
        canvas.save()
        canvas.translate(0, ((size.height - 22) / 2).rounded())
        let top = 4.0
        let h = 14.0
        fill.color = margin
        canvas.drawRect(Rect.fromLTWH(originX, top, pageW, h), fill)
        let contentL = originX + setup.marginLeft * px
        let contentW = setup.contentWidth * px
        fill.color = paper
        canvas.drawRect(Rect.fromLTWH(contentL, top, contentW, h), fill)

        // Ticks every eighth of an inch from the left margin; numbers per inch.
        let line = Paint()
        line.style = .stroke
        line.strokeWidth = 1
        line.color = ink
        let inch = 72 * px
        var k = -Int((setup.marginLeft * px) / (inch / 8))
        let maxK = Int((pageW - setup.marginLeft * px) / (inch / 8))
        let mid = top + h / 2
        while k <= maxK {
            let x = (contentL + Double(k) * inch / 8).rounded() + 0.5
            if x >= originX && x <= originX + pageW {
                if k % 8 == 0 {
                    let n = abs(k / 8)
                    if n > 0 {
                        let tp = TextPainter(text: TextSpan(text: "\(n)", style: Flutter.TextStyle(color: ink, fontSize: 9)),
                                             textAlign: .center, textDirection: .ltr)
                        tp.layout(minWidth: 0, maxWidth: 20)
                        tp.paint(canvas, Offset(x - tp.width / 2, mid - tp.height / 2))
                        tp.dispose()
                    }
                } else if k % 4 == 0 {
                    canvas.drawLine(Offset(x, mid - 4), Offset(x, mid + 4), line)
                } else if k % 2 == 0 {
                    canvas.drawLine(Offset(x, mid - 2), Offset(x, mid + 2), line)
                }
            }
            k += 1
        }

        // Indent markers: the first-line triangle above, the left-indent triangle below, and the
        // right-indent triangle at the right end of the column.
        let marker = Paint()
        marker.style = .fill
        marker.color = accent
        let ix = contentL + style.indentLeft * px
        let fx = contentL + (style.indentLeft + style.firstLineIndent) * px
        let tri = Path()
        tri.moveTo(fx - 4, top)
        tri.lineTo(fx + 4, top)
        tri.lineTo(fx, top + 5)
        tri.close()
        canvas.drawPath(tri, marker)
        let tri2 = Path()
        tri2.moveTo(ix - 4, top + h)
        tri2.lineTo(ix + 4, top + h)
        tri2.lineTo(ix, top + h - 5)
        tri2.close()
        canvas.drawPath(tri2, marker)
        let rx = contentL + contentW - style.indentRight * px
        let tri3 = Path()
        tri3.moveTo(rx - 4, top + h)
        tri3.lineTo(rx + 4, top + h)
        tri3.lineTo(rx, top + h - 5)
        tri3.close()
        canvas.drawPath(tri3, marker)

        line.color = accent
        for t in style.tabStops { glyph(canvas, TabKind(t), x: (contentL + t.position * px).rounded() + 0.5, base: mid + 4, line) }
        if originX >= 24 {   // the box that says which kind a click adds
            line.color = ink
            canvas.drawRect(Rect.fromLTWH(2, top, 18, h), line)
            glyph(canvas, kind, x: 11, base: top + h - 3, line)
        }
        canvas.restore()
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool { true }
}
