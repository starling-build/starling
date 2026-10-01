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
        /// The text theme laid out with: a new one (a theme applied) is a miss.
        let theme: ObjectIdentifier
        let layout: RichLayout
    }
    private var _entries: [ObjectIdentifier: Entry] = [:]
    private var _images: [String: Image] = [:]
    private var _decoding: Set<String> = []
    /// Called when a picture finishes decoding: repaint.
    var onImageDecoded: (() -> Void)?
    /// Another cache whose decoded pictures this one uses (the show's text
    /// is laid out at its own size; its pictures are the editor's).
    weak var imageSource: SlideTextCache?

    /// The decoded picture, or nil while it decodes (the request starts
    /// here, once).
    func image(_ attachment: ImageAttachment) -> Image? {
        if let source = imageSource { return source.image(attachment) }
        if let image = _images[attachment.id] { return image }
        if _decoding.contains(attachment.id) { return nil }
        _decoding.insert(attachment.id)
        let bytes = [UInt8](attachment.data)
        let id = attachment.id
        Task { @MainActor [weak self] in
            var decoded: Image? = nil
            if let codec = try? await instantiateImageCodec(bytes) {
                decoded = (try? await codec.getNextFrame())?.image
                codec.dispose()
            }
            guard let self else { decoded?.dispose(); return }
            self._decoding.remove(id)
            if let decoded {
                self._images[id] = decoded
                self.onImageDecoded?()
            }
        }
        return nil
    }

    /// PowerPoint's autofit steps, largest first.
    static let autofitSteps = [1.0, 0.925, 0.85, 0.775, 0.7, 0.625, 0.55, 0.475, 0.4, 0.325, 0.25]

    /// The largest step at which `shape`'s text fits its box.
    static func autofitScale(_ shape: SlideShape) -> Double {
        guard let text = shape.text, let theme = shape.textTheme else { return 1 }
        let room = shape.frame.height - shape.insets.top - shape.insets.bottom
        let width = max(1, shape.frame.width - shape.insets.left - shape.insets.right)
        for scale in autofitSteps {
            let layout = RichLayout(theme: theme, paragraphCount: text.document.paragraphs.count)
            layout.scale = scale / theme.pixelsPerPoint
            layout.width = width
            layout.ensureLaidOut(text.document)
            if layout.totalHeight <= room + 0.5 { return scale }
        }
        return autofitSteps.last!
    }

    /// The body of `shape` laid out at `pxPerPt` device pixels per point.
    func layout(_ shape: SlideShape, pxPerPt: Double) -> RichLayout? {
        guard let text = shape.text, let theme = shape.textTheme else { return nil }
        let width = max(1, (shape.frame.width - shape.insets.left - shape.insets.right) * pxPerPt)
        let scale = pxPerPt * shape.fontScale / theme.pixelsPerPoint
        let key = ObjectIdentifier(text)
        if let e = _entries[key], e.revision == text.revision, e.width == width, e.scale == scale,
           e.theme == ObjectIdentifier(theme) {
            return e.layout
        }
        let layout = RichLayout(theme: theme, paragraphCount: text.document.paragraphs.count)
        layout.scale = scale
        layout.width = width
        layout.ensureLaidOut(text.document)
        _entries[key] = Entry(revision: text.revision, width: width, scale: scale, theme: ObjectIdentifier(theme),
                              layout: layout)
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
    let theme: DeckTheme

    init(shape: SlideShape, px: Double, revision: Int, cache: SlideTextCache, theme: DeckTheme) {
        self.shape = shape
        self.px = px
        self.revision = revision
        self.cache = cache
        self.theme = theme
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        SlidePainter.paintShape(shape, canvas, pxPerPt: px, cache: cache, theme: theme, text: false)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? ShapePainter else { return true }
        return old.shape !== shape || old.revision != revision || old.px != px || old.theme != theme
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
    /// Entrances under way in the show; shapes absent are drawn whole.
    let reveals: ShapeReveals

    init(slide: Slide, theme: DeckTheme, slideSize: Size, revision: Int, cache: SlideTextCache,
         shapesOnly: Bool = false, reveals: ShapeReveals = ShapeReveals()) {
        self.slide = slide
        self.theme = theme
        self.slideSize = slideSize
        self.revision = revision
        self.cache = cache
        self.shapesOnly = shapesOnly
        self.reveals = reveals
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let px = size.width / slideSize.width
        Self.paintFill(slide.background ?? slide.inheritedBackground ?? theme.backgroundFill,
                       Rect.fromLTWH(0, 0, size.width, size.height), canvas, cache: cache)
        canvas.save()
        canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height))
        if !shapesOnly {
            let area = Rect.fromLTWH(0, 0, size.width, size.height)
            for shape in slide.shapes {
                let f = shape.frame
                let box = Rect.fromLTWH(f.left * px, f.top * px, f.width * px, f.height * px)
                let draw = {
                    Self.paintShape(shape, canvas, pxPerPt: px, cache: self.cache, theme: self.theme, text: true,
                                    paragraphs: self.reveals.paragraphs[shape.id], slide: area)
                }
                if let r = reveals.whole[shape.id] {
                    Self.reveal(r, box, slide: area, canvas, draw)
                } else {
                    draw()
                }
            }
        }
        canvas.restore()
    }

    /// Draw `draw` (which paints within `box`) as far into entrance `r` as
    /// it has got: nothing at 0, all of it at 1. `slide` is the slide's
    /// rectangle in the same coordinates, which Fly In comes in from beyond.
    static func reveal(_ r: ShapeReveal, _ box: Rect, slide: Rect, _ canvas: any Canvas, _ draw: () -> Void) {
        guard r.progress > 0 else { return }
        guard r.progress < 1 else { draw(); return }
        let t = r.progress
        let e = 1 - pow(1 - t, 3)
        canvas.save()
        func faded(_ alpha: Double, _ bounds: Rect) {
            let p = Paint()
            p.color = Color(Int((max(0, min(1, alpha)) * 255).rounded()) << 24)
            canvas.saveLayer(bounds, p)
            draw()
            canvas.restore()
        }
        switch r.effect {
        case .appear:
            draw()
        case .fade:
            faded(t, box.inflate(4))
        case .flyIn:
            var dx = 0.0, dy = 0.0
            switch r.direction {
            case .bottom: dy = (slide.bottom - box.top) * (1 - e)
            case .top: dy = (slide.top - box.bottom) * (1 - e)
            case .left: dx = (slide.left - box.right) * (1 - e)
            case .right: dx = (slide.right - box.left) * (1 - e)
            }
            canvas.translate(dx, dy)
            draw()
        case .wipe:
            let clip: Rect
            switch r.direction {
            case .bottom: clip = Rect.fromLTRB(box.left - 4, box.bottom - box.height * t, box.right + 4, box.bottom + 4)
            case .top: clip = Rect.fromLTRB(box.left - 4, box.top - 4, box.right + 4, box.top + box.height * t)
            case .left: clip = Rect.fromLTRB(box.left - 4, box.top - 4, box.left + box.width * t, box.bottom + 4)
            case .right: clip = Rect.fromLTRB(box.right - box.width * t, box.top - 4, box.right + 4, box.bottom + 4)
            }
            canvas.clipRect(clip)
            draw()
        case .zoom:
            let c = box.center
            canvas.translate(c.dx, c.dy)
            canvas.scale(max(0.01, e), max(0.01, e))
            canvas.translate(-c.dx, -c.dy)
            faded(t, box.inflate(4))
        }
        canvas.restore()
    }

    static func paintShape(_ shape: SlideShape, _ canvas: any Canvas, pxPerPt px: Double,
                           cache: SlideTextCache, theme: DeckTheme, text: Bool,
                           paragraphs: [Int: ShapeReveal]? = nil, slide: Rect? = nil) {
        let f = shape.frame
        let r = Rect.fromLTWH(f.left * px, f.top * px, f.width * px, f.height * px)
        canvas.save()
        if shape.rotation != 0 {
            let c = r.center
            canvas.translate(c.dx, c.dy)
            canvas.rotate(shape.rotation * .pi / 180)
            canvas.translate(-c.dx, -c.dy)
        }
        if let image = shape.picture {
            if let decoded = cache.image(image) {
                let w = Double(decoded.width), h = Double(decoded.height)
                let c = shape.crop ?? .zero
                let src = Rect.fromLTRB(c.left * w, c.top * h, w - c.right * w, h - c.bottom * h)
                canvas.drawImageRect(decoded, src, r, Paint())
            } else {
                let p = Paint()
                p.style = .fill
                p.color = Color(0xFFEDEDED)
                canvas.drawRect(r, p)
            }
        }
        if let chart = shape.chart {
            ChartPainter.paint(chart, canvas, r, pxPerPt: px, theme: theme)
        }
        if let opaque = shape.opaque {
            // What the deck cannot draw yet: a labelled box where it sits.
            let p = Paint()
            p.style = .fill
            p.color = Color(0xFFF1F3F6)
            canvas.drawRect(r, p)
            p.style = .stroke
            p.strokeWidth = 1
            p.color = Color(0xFF9AA4B2)
            canvas.drawRect(r, p)
            let tp = TextPainter(text: TextSpan(text: opaque.label, style: Flutter.TextStyle(
                color: Color(0xFF5A6472), fontSize: max(6, 14 * px), fontFamily: OfficeFonts.sans)),
                textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: max(1, r.width))
            tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2))
            tp.dispose()
        }
        let path: Path? = shape.preset.flatMap { $0.isLine ? nil : geometryPath($0, r) }
        if let fill = shape.fill, shape.preset?.isOpenPath != true {
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
            let ox = r.left + shape.insets.left * px, oy = r.top + cache.textTop(shape, pxPerPt: px)
            canvas.translate(ox, oy)
            let visible = Rect.fromLTWH(0, -10_000, layout.width, layout.totalHeight + 20_000)
            if let paragraphs, !paragraphs.isEmpty {
                // Built by paragraph: each paragraph's band drawn on its own,
                // as far into its entrance as it has got.
                let area = (slide ?? Rect.fromLTWH(0, 0, 10_000, 10_000)).shift(Offset(-ox, -oy))
                for i in 0 ..< layout.count {
                    let g = layout.geometry(i)
                    let band = Rect.fromLTRB(-10_000, g.top, 10_000, g.top + g.height)
                    let draw = {
                        canvas.save()
                        canvas.clipRect(band)
                        layout.paint(canvas, visible: visible, document: doc, selection: nil, caret: nil)
                        canvas.restore()
                    }
                    if let rv = paragraphs[i] {
                        Self.reveal(rv, Rect.fromLTWH(0, g.top, layout.width, g.height), slide: area, canvas, draw)
                    } else {
                        draw()
                    }
                }
            } else {
                layout.paint(canvas, visible: visible, document: doc, selection: nil, caret: nil)
            }
        }
        canvas.restore()
    }

    /// A colour, gradient or picture filling `r`.
    static func paintFill(_ fill: SlideFill, _ r: Rect, _ canvas: any Canvas, cache: SlideTextCache) {
        let p = Paint()
        p.style = .fill
        p.color = fill.color ?? Color(0xFFFFFFFF)
        if fill.stops.count >= 2 {
            let a = fill.angle * .pi / 180
            let c = r.center
            let half = (abs(cos(a)) * r.width + abs(sin(a)) * r.height) / 2
            let d = Offset(cos(a) * half, sin(a) * half)
            p.shader = Gradient(linear: Offset(c.dx - d.dx, c.dy - d.dy), to: Offset(c.dx + d.dx, c.dy + d.dy),
                                colors: fill.stops.map(\.color), colorStops: fill.stops.map(\.position))
        }
        canvas.drawRect(r, p)
        if let image = fill.image, let decoded = cache.image(image) {
            canvas.drawImageRect(decoded, Rect.fromLTWH(0, 0, Double(decoded.width), Double(decoded.height)), r, Paint())
        }
    }

    /// The outline of a preset shape filling `r`, with PowerPoint's default
    /// adjustments.
    static func geometryPath(_ preset: ShapePreset, _ r: Rect) -> Path {
        let path = Path()
        let w = r.width, h = r.height, l = r.left, t = r.top
        let ss = min(w, h)
        switch preset.rawValue {
        case "roundRect":
            path.addRRect(RRect(fromRectAndRadius: r, Radius(circular: ss * 0.1667)))
        case "round2DiagRect":
            path.addRRect(RRect(fromLTRBAndCorners: l, t, r.right, r.bottom,
                                topLeft: Radius(circular: ss * 0.1667), topRight: .zero,
                                bottomRight: Radius(circular: ss * 0.1667), bottomLeft: .zero))
        case "ellipse", "flowChartConnector":
            path.addOval(r)
        case "flowChartTerminator":
            path.addRRect(RRect(fromRectAndRadius: r, Radius(circular: h / 2)))
        case "triangle":
            path.addPolygon([Offset(l + w / 2, t), Offset(r.right, r.bottom), Offset(l, r.bottom)], true)
        case "rtTriangle":
            path.addPolygon([Offset(l, t), Offset(r.right, r.bottom), Offset(l, r.bottom)], true)
        case "diamond", "flowChartDecision":
            path.addPolygon([Offset(l + w / 2, t), Offset(r.right, t + h / 2), Offset(l + w / 2, r.bottom),
                             Offset(l, t + h / 2)], true)
        case "parallelogram", "flowChartInputOutput":
            let k = ss * 0.25
            path.addPolygon([Offset(l + k, t), Offset(r.right, t), Offset(r.right - k, r.bottom), Offset(l, r.bottom)], true)
        case "hexagon":
            let k = ss * 0.25
            path.addPolygon([Offset(l + k, t), Offset(r.right - k, t), Offset(r.right, t + h / 2),
                             Offset(r.right - k, r.bottom), Offset(l + k, r.bottom), Offset(l, t + h / 2)], true)
        case "homePlate":
            let k = ss * 0.5
            path.addPolygon([Offset(l, t), Offset(r.right - k, t), Offset(r.right, t + h / 2),
                             Offset(r.right - k, r.bottom), Offset(l, r.bottom)], true)
        case "chevron":
            let k = ss * 0.5
            path.addPolygon([Offset(l, t), Offset(r.right - k, t), Offset(r.right, t + h / 2),
                             Offset(r.right - k, r.bottom), Offset(l, r.bottom), Offset(l + k, t + h / 2)], true)
        case "plus", "mathPlus":
            let k = ss * 0.25
            path.addPolygon([Offset(l + k, t), Offset(r.right - k, t), Offset(r.right - k, t + k), Offset(r.right, t + k),
                             Offset(r.right, r.bottom - k), Offset(r.right - k, r.bottom - k), Offset(r.right - k, r.bottom),
                             Offset(l + k, r.bottom), Offset(l + k, r.bottom - k), Offset(l, r.bottom - k),
                             Offset(l, t + k), Offset(l + k, t + k)], true)
        case "leftArrow":
            let head = ss * 0.5
            path.addPolygon([Offset(r.right, t + h * 0.25), Offset(l + head, t + h * 0.25), Offset(l + head, t),
                             Offset(l, t + h / 2), Offset(l + head, r.bottom), Offset(l + head, t + h * 0.75),
                             Offset(r.right, t + h * 0.75)], true)
        case "upArrow", "downArrow":
            let head = ss * 0.5
            let up = preset.rawValue == "upArrow"
            let tip = up ? t : r.bottom, base = up ? t + head : r.bottom - head, tail = up ? r.bottom : t
            path.addPolygon([Offset(l + w * 0.25, tail), Offset(l + w * 0.25, base), Offset(l, base),
                             Offset(l + w / 2, tip), Offset(r.right, base), Offset(l + w * 0.75, base),
                             Offset(l + w * 0.75, tail)], true)
        case "leftBrace", "rightBrace":
            // Two quarter curls each side of a point, as PowerPoint's brace.
            let left = preset.rawValue == "leftBrace"
            let x0 = left ? r.right : l, x1 = left ? l + w / 2 : r.right - w / 2, x2 = left ? l : r.right
            let q = min(h * 0.083, w)
            path.moveTo(x0, t)
            path.quadraticBezierTo(x1, t, x1, t + q)
            path.lineTo(x1, t + h / 2 - q)
            path.quadraticBezierTo(x1, t + h / 2, x2, t + h / 2)
            path.quadraticBezierTo(x1, t + h / 2, x1, t + h / 2 + q)
            path.lineTo(x1, r.bottom - q)
            path.quadraticBezierTo(x1, r.bottom, x0, r.bottom)
        case "leftBracket", "rightBracket":
            let left = preset.rawValue == "leftBracket"
            let x0 = left ? r.right : l, x1 = left ? l : r.right
            path.moveTo(x0, t); path.lineTo(x1, t); path.lineTo(x1, r.bottom); path.lineTo(x0, r.bottom)
        case _ where preset.rawValue.hasPrefix("bentConnector") || preset.rawValue.hasPrefix("curvedConnector"):
            path.moveTo(l, t); path.lineTo(l + w / 2, t); path.lineTo(l + w / 2, r.bottom); path.lineTo(r.right, r.bottom)
        case "rightArrow":
            let head = min(w, h) * 0.5
            let shaftTop = t + h * 0.25, shaftBottom = t + h * 0.75
            path.addPolygon([
                Offset(l, shaftTop), Offset(r.right - head, shaftTop), Offset(r.right - head, t),
                Offset(r.right, t + h / 2), Offset(r.right - head, r.bottom), Offset(r.right - head, shaftBottom),
                Offset(l, shaftBottom),
            ], true)
        case "star5":
            let c = r.center
            var points: [Offset] = []
            for i in 0 ..< 10 {
                let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
                let k = i % 2 == 0 ? 1.0 : 0.382
                points.append(Offset(c.dx + cos(angle) * w / 2 * k, c.dy + sin(angle) * h / 2 * k))
            }
            path.addPolygon(points, true)
        case "wedgeRectCallout":
            // The tail leaves the bottom edge and points below-left, outside
            // the frame, as PowerPoint's default callout does.
            path.addPolygon([
                Offset(l, t), Offset(r.right, t), Offset(r.right, r.bottom),
                Offset(l + w * 0.4167, r.bottom), Offset(l + w * 0.2917, t + h * 1.125),
                Offset(l + w * 0.1667, r.bottom), Offset(l, r.bottom),
            ], true)
        default:
            // rect, flowChartProcess and every preset not drawn exactly yet.
            path.addRect(r)
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
