// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// One painter for a slide at any size: the thumbnail pane, the slide show
// and PDF export all draw through it, and the editing canvas uses the same
// text measurement to anchor its live editors. Thumbnails cannot be the
// canvas widget shrunk inside a RepaintBoundary — interior repaint
// boundaries paint nothing in this framework (RenderObject.swift,
// `_compositeChild`) — so they are drawn, not composited.

import Flutter
import FlutterSwiftBridge
import Foundation

/// Laid-out text bodies, reused while the words, the width and the scale
/// stay put.
final class SlideTextCache {
    private struct Entry {
        let revision: Int
        let width: Double
        let scale: Double
        let layout: RichLayout
    }
    private var _entries: [ObjectIdentifier: Entry] = [:]

    /// The body of `shape` laid out at `pxPerPt` device pixels per point.
    func layout(_ shape: SlideShape, pxPerPt: Double) -> RichLayout? {
        guard let text = shape.text, let theme = shape.textTheme else { return nil }
        let width = max(1, (shape.frame.width - shape.insets.left - shape.insets.right) * pxPerPt)
        let scale = pxPerPt / theme.pixelsPerPoint
        let key = ObjectIdentifier(text)
        if let e = _entries[key], e.revision == text.revision, e.width == width, e.scale == scale {
            return e.layout
        }
        let layout = RichLayout(theme: theme, paragraphCount: text.document.paragraphs.count)
        layout.scale = scale
        layout.width = width
        layout.ensureLaidOut(text.document)
        _entries[key] = Entry(revision: text.revision, width: width, scale: scale, layout: layout)
        return layout
    }

    /// Where the first line starts below the shape's top edge, in pixels:
    /// the top inset plus whatever the vertical anchor leaves above the text.
    /// Text taller than the box overflows the way the anchor points (down
    /// for top, both ways for middle, up for bottom), so this can be
    /// negative, as PowerPoint's can.
    func textTop(_ shape: SlideShape, pxPerPt: Double) -> Double {
        let top = shape.insets.top * pxPerPt
        guard let layout = layout(shape, pxPerPt: pxPerPt) else { return top }
        let room = (shape.frame.height - shape.insets.top - shape.insets.bottom) * pxPerPt
        let spare = room - layout.totalHeight
        switch shape.anchor {
        case .top: return top
        case .middle: return top + spare / 2
        case .bottom: return top + spare
        }
    }

    func forget(_ shapes: [SlideShape]) {
        for s in shapes { if let t = s.text { _entries[ObjectIdentifier(t)] = nil } }
    }
}

/// Draws one shape (no text) in slide coordinates at `pxPerPt` — a layer
/// of the editing canvas, so that shapes and their live editors stack in
/// the slide's z-order.
final class ShapePainter: CustomPainter {
    let shape: SlideShape
    let px: Double
    let revision: Int
    let cache: SlideTextCache

    init(shape: SlideShape, px: Double, revision: Int, cache: SlideTextCache) {
        self.shape = shape
        self.px = px
        self.revision = revision
        self.cache = cache
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        SlidePainter.paintShape(shape, canvas, pxPerPt: px, cache: cache, text: false)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? ShapePainter else { return true }
        return old.shape !== shape || old.revision != revision || old.px != px
    }
}

/// Draws a slide scaled so that it fills `size`.
final class SlidePainter: CustomPainter {
    let slide: Slide
    let theme: DeckTheme
    let slideSize: Size
    let revision: Int
    let cache: SlideTextCache
    /// Only the background (the editing canvas draws shapes as layers).
    let shapesOnly: Bool

    init(slide: Slide, theme: DeckTheme, slideSize: Size, revision: Int, cache: SlideTextCache,
         shapesOnly: Bool = false) {
        self.slide = slide
        self.theme = theme
        self.slideSize = slideSize
        self.revision = revision
        self.cache = cache
        self.shapesOnly = shapesOnly
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let px = size.width / slideSize.width
        let bg = Paint()
        bg.style = .fill
        bg.color = theme.background
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg)
        canvas.save()
        canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height))
        if !shapesOnly {
            for shape in slide.shapes {
                Self.paintShape(shape, canvas, pxPerPt: px, cache: cache, text: true)
            }
        }
        canvas.restore()
    }

    static func paintShape(_ shape: SlideShape, _ canvas: any Canvas, pxPerPt px: Double,
                           cache: SlideTextCache, text: Bool) {
        let f = shape.frame
        let r = Rect.fromLTWH(f.left * px, f.top * px, f.width * px, f.height * px)
        canvas.save()
        if shape.rotation != 0 {
            let c = r.center
            canvas.translate(c.dx, c.dy)
            canvas.rotate(shape.rotation * .pi / 180)
            canvas.translate(-c.dx, -c.dy)
        }
        let path: Path? = shape.preset.flatMap { $0.isLine ? nil : geometryPath($0, r) }
        if let fill = shape.fill {
            let p = Paint()
            p.style = .fill
            p.isAntiAlias = true
            p.color = fill
            if let path { canvas.drawPath(path, p) } else { canvas.drawRect(r, p) }
        }
        if let line = shape.outline {
            let p = Paint()
            p.style = .stroke
            p.isAntiAlias = true
            p.strokeWidth = max(0.5, shape.outlineWidth * px)
            p.color = line
            if shape.preset?.isLine == true {
                canvas.drawLine(Offset(r.left, r.top), Offset(r.right, r.bottom), p)
            } else if let path {
                canvas.drawPath(path, p)
            } else {
                canvas.drawRect(r, p)
            }
        }
        if text, !shape.isEmptyText, let layout = cache.layout(shape, pxPerPt: px), let doc = shape.text?.document {
            canvas.translate(r.left + shape.insets.left * px, r.top + cache.textTop(shape, pxPerPt: px))
            layout.paint(canvas, visible: Rect.fromLTWH(0, -10_000, layout.width, layout.totalHeight + 20_000),
                         document: doc, selection: nil, caret: nil)
        }
        canvas.restore()
    }

    /// The outline of a preset shape filling `r`, with PowerPoint's default
    /// adjustments.
    static func geometryPath(_ preset: ShapePreset, _ r: Rect) -> Path {
        let path = Path()
        let w = r.width, h = r.height, l = r.left, t = r.top
        switch preset {
        case .rect, .line:
            path.addRect(r)
        case .roundRect:
            path.addRRect(RRect(fromRectAndRadius: r, Radius(circular: min(w, h) * 0.1667)))
        case .ellipse:
            path.addOval(r)
        case .triangle:
            path.addPolygon([Offset(l + w / 2, t), Offset(r.right, r.bottom), Offset(l, r.bottom)], true)
        case .rightArrow:
            let head = min(w, h) * 0.5
            let shaftTop = t + h * 0.25, shaftBottom = t + h * 0.75
            path.addPolygon([
                Offset(l, shaftTop), Offset(r.right - head, shaftTop), Offset(r.right - head, t),
                Offset(r.right, t + h / 2), Offset(r.right - head, r.bottom), Offset(r.right - head, shaftBottom),
                Offset(l, shaftBottom),
            ], true)
        case .star5:
            let c = r.center
            var points: [Offset] = []
            for i in 0 ..< 10 {
                let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
                let k = i % 2 == 0 ? 1.0 : 0.382
                points.append(Offset(c.dx + cos(angle) * w / 2 * k, c.dy + sin(angle) * h / 2 * k))
            }
            path.addPolygon(points, true)
        case .wedgeRectCallout:
            // The tail leaves the bottom edge and points below-left, outside
            // the frame, as PowerPoint's default callout does.
            path.addPolygon([
                Offset(l, t), Offset(r.right, t), Offset(r.right, r.bottom),
                Offset(l + w * 0.4167, r.bottom), Offset(l + w * 0.2917, t + h * 1.125),
                Offset(l + w * 0.1667, r.bottom), Offset(l, r.bottom),
            ], true)
        }
        return path
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? SlidePainter else { return true }
        return old.slide !== slide || old.revision != revision || old.slideSize != slideSize
            || old.shapesOnly != shapesOnly
    }
}

/// Reports the size it is laid out at, one frame later. The framework has
/// no LayoutBuilder; this is the smallest thing that lets a widget fit its
/// content to the space it was given (the slide canvas zooms to fit).
final class SizeReporter: SingleChildRenderObjectWidget {
    let onSize: (Size) -> Void
    /// The box itself, for mapping window coordinates into it (pointer
    /// events here carry only window positions).
    let onBox: ((RenderBox) -> Void)?

    init(onSize: @escaping (Size) -> Void, onBox: ((RenderBox) -> Void)? = nil, child: Widget?) {
        self.onSize = onSize
        self.onBox = onBox
        super.init(key: nil, child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        let box = _RenderSizeReporter(onSize: onSize)
        onBox?(box)
        return box
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        (renderObject as! _RenderSizeReporter).onSize = onSize
        onBox?(renderObject as! RenderBox)
    }
}

private final class _RenderSizeReporter: RenderProxyBox {
    var onSize: (Size) -> Void
    private var _reported: Size? = nil

    init(onSize: @escaping (Size) -> Void) {
        self.onSize = onSize
        super.init()
    }

    override func performLayout() {
        super.performLayout()
        let s = size
        guard s != _reported else { return }
        _reported = s
        // Not during layout: the callback rebuilds.
        FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in
            self?.onSize(s)
        }
        PlatformDispatcher.instance.scheduleFrame()
    }
}
