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
                       Rect.fromLTWH(0, 0, size.width, size.height), canvas, cache: cache, pxPerPt: px)
        canvas.save()
        canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height))
        let area = Rect.fromLTWH(0, 0, size.width, size.height)
        let backdrop = slide.background ?? slide.inheritedBackground ?? theme.backgroundFill
        // The master's and layout's own shapes, part of the backdrop.
        for shape in slide.decorations {
            Self.paintShape(shape, canvas, pxPerPt: px, cache: cache, theme: theme, text: true, slide: area, backdrop: backdrop)
        }
        if !shapesOnly {
            for shape in slide.shapes {
                let f = shape.frame
                let box = Rect.fromLTWH(f.left * px, f.top * px, f.width * px, f.height * px)
                let draw = {
                    Self.paintShape(shape, canvas, pxPerPt: px, cache: self.cache, theme: self.theme, text: true,
                                    paragraphs: self.reveals.paragraphs[shape.id], slide: area, backdrop: backdrop)
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
                           paragraphs: [Int: ShapeReveal]? = nil, slide: Rect? = nil, backdrop: SlideFill? = nil) {
        if shape.invisible { return }
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
                // A negative crop pads: the picture sits inside the frame.
                let src = Rect.fromLTRB(max(0, c.left) * w, max(0, c.top) * h,
                                        w - max(0, c.right) * w, h - max(0, c.bottom) * h)
                let spanX = 1 - c.left - c.right, spanY = 1 - c.top - c.bottom
                let r = spanX > 0 && spanY > 0 ? Rect.fromLTRB(
                    r.left + (max(0, c.left) - c.left) / spanX * r.width,
                    r.top + (max(0, c.top) - c.top) / spanY * r.height,
                    r.left + (1 - max(0, c.right) - c.left) / spanX * r.width,
                    r.top + (1 - max(0, c.bottom) - c.top) / spanY * r.height) : r
                canvas.save()
                if let g = shape.pictureGeometry, !g.isLine { canvas.clipPath(Self.geometryPath(g, r)) }
                if shape.flipH || shape.flipV {
                    let c = r.center
                    canvas.translate(c.dx, c.dy)
                    canvas.scale(shape.flipH ? -1 : 1, shape.flipV ? -1 : 1)
                    canvas.translate(-c.dx, -c.dy)
                }
                canvas.drawImageRect(decoded, src, r, imagePaint(alpha: shape.pictureAlpha, duotone: shape.pictureDuotone))
                canvas.restore()
            } else {
                let p = Paint()
                p.style = .fill
                p.color = Color(0xFFEDEDED)
                canvas.drawRect(r, p)
            }
        }
        if let chart = shape.chart {
            if let style = shape.fillStyle { paintFill(style, r, canvas, cache: cache, pxPerPt: px) }
            ChartPainter.paint(chart, canvas, r, pxPerPt: px, theme: theme)
        }
        if shape.fillsWithBackground, let backdrop, let slide {
            // A window onto the slide's background, in the shape's outline.
            canvas.save()
            if let freeform = shape.opaque?.freeform ?? shape.customPath {
                canvas.clipPath(Self.combinedPath(freeform, r))
            } else if let preset = shape.preset ?? shape.inheritedPreset, !preset.isLine {
                canvas.clipPath(geometryPath(preset, r))
            } else {
                canvas.clipRect(r)
            }
            paintFill(backdrop, slide, canvas, cache: cache, pxPerPt: px)
            canvas.restore()
        }
        if let opaque = shape.opaque, let freeform = opaque.freeform {
            // A freeform along its own path, in the shape's fill and line.
            for sub in freeform.subpaths {
                let path = FreeformGeometry.path(sub, in: r)
                if sub.fill, let fill = shape.fill {
                    let p = Paint()
                    p.style = .fill
                    p.isAntiAlias = true
                    p.color = fill
                    canvas.drawPath(path, p)
                }
                if sub.stroke, let line = shape.outline {
                    let p = Paint()
                    p.style = .stroke
                    p.isAntiAlias = true
                    p.strokeWidth = max(0.5, shape.outlineWidth * px)
                    p.color = line
                    canvas.drawPath(path, p)
                }
            }
        } else if shape.opaque != nil, !shape.rendered.isEmpty {
            // The object's own drawing (a SmartArt's), shape by shape.
            for sub in shape.rendered {
                paintShape(sub, canvas, pxPerPt: px, cache: cache, theme: theme, text: text, slide: slide, backdrop: backdrop)
            }
        } else if let opaque = shape.opaque {
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
        let preset = shape.preset ?? shape.inheritedPreset
        let path: Path? = preset.flatMap { $0.isLine ? nil : geometryPath($0, r) }
            ?? shape.customPath.map { Self.combinedPath($0, r) }
        let drawnAlready = shape.opaque?.freeform != nil
        if let style = shape.fillStyle, !drawnAlready, shape.chart == nil {
            // A gradient or picture fill, within the shape's outline.
            canvas.save()
            if let path { canvas.clipPath(path) } else { canvas.clipRect(r) }
            paintFill(style, r, canvas, cache: cache, pxPerPt: px)
            canvas.restore()
        } else if let fill = shape.fill, shape.preset?.isOpenPath != true, !drawnAlready {
            let p = Paint()
            p.style = .fill
            p.isAntiAlias = true
            p.color = fill
            if let path { canvas.drawPath(path, p) } else { canvas.drawRect(r, p) }
        }
        if let line = shape.outline, !drawnAlready {
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
        // (An empty table still has its rows' fills and borders to draw.)
        if text, !shape.isEmptyText || shape.kind == .table, let layout = cache.layout(shape, pxPerPt: px), let doc = shape.text?.document {
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
    static func paintFill(_ fill: SlideFill, _ r: Rect, _ canvas: any Canvas, cache: SlideTextCache, pxPerPt: Double = 1) {
        let p = Paint()
        p.style = .fill
        p.color = fill.color ?? Color(0xFFFFFFFF)
        if fill.stops.count >= 2 {
            let a = fill.angle * .pi / 180
            let c = r.center
            let half = (abs(cos(a)) * r.width + abs(sin(a)) * r.height) / 2
            let d = Offset(cos(a) * half, sin(a) * half)
            let (colors, positions) = Self.linearLight(fill.stops)
            p.shader = Gradient(linear: Offset(c.dx - d.dx, c.dy - d.dy), to: Offset(c.dx + d.dx, c.dy + d.dy),
                                colors: colors, colorStops: positions)
            // The paint's own alpha scales the shader: a first stop that is
            // transparent must not make the whole gradient so.
            p.color = Color(0xFFFFFFFF)
        }
        canvas.drawRect(r, p)
        if let image = fill.image, let decoded = cache.image(image) {
            let src = Rect.fromLTWH(0, 0, Double(decoded.width), Double(decoded.height))
            let paint = imagePaint(alpha: fill.imageAlpha, duotone: fill.duotone)
            let tw = max(1, Double(decoded.width) * 0.75 * fill.tileScale * pxPerPt)
            let th = max(1, Double(decoded.height) * 0.75 * fill.tileScale * pxPerPt)
            // A tile larger than the area in both directions is a photo
            // marked "tile": PowerPoint shows it fitted, not cropped.
            if fill.tiled, tw < r.width || th < r.height {
                // At the picture's own size (96/in) times the tile scale.
                canvas.save()
                canvas.clipRect(r)
                var y = r.top
                while y < r.bottom {
                    var x = r.left
                    while x < r.right {
                        canvas.drawImageRect(decoded, src, Rect.fromLTWH(x, y, tw, th), paint)
                        x += tw
                    }
                    y += th
                }
                canvas.restore()
            } else {
                canvas.drawImageRect(decoded, src, r, paint)
            }
        }
    }

    /// The paint for a picture: its transparency, and a duotone as a colour
    /// matrix (luminance maps from the first colour to the second).
    static func imagePaint(alpha: Double, duotone: [Color]?) -> Paint {
        let p = Paint()
        if alpha < 1 { p.color = Color(0xFFFFFFFF).withOpacity(alpha) }
        if let d = duotone, d.count == 2 {
            func ch(_ c: Color, _ sh: Int) -> Double { Double((c.value >> sh) & 0xFF) }
            var m: [Double] = []
            for sh in [16, 8, 0] {
                let lo = ch(d[0], sh), hi = ch(d[1], sh), k = hi - lo
                m += [0.299 * k / 255, 0.587 * k / 255, 0.114 * k / 255, 0, lo]
            }
            m += [0, 0, 0, 1, 0]
            p.colorFilter = ColorFilter(matrix: m)
        }
        return p
    }

    /// The presets `geometryPath` draws as themselves; any other is a box.
    static let drawablePresets: Set<String> = [
        "rect", "roundRect", "round2DiagRect", "ellipse", "flowChartConnector", "flowChartTerminator", "triangle",
        "rtTriangle", "diamond", "flowChartDecision", "parallelogram", "flowChartInputOutput", "hexagon", "homePlate",
        "chevron", "plus", "mathPlus", "mathMinus", "leftArrow", "upArrow", "downArrow", "leftBrace", "rightBrace",
        "leftBracket", "rightBracket", "rightArrow", "star5", "wedgeRectCallout", "line",
    ]

    /// Every filled subpath of a freeform as one path (its holes cut).
    static func combinedPath(_ g: FreeformGeometry, _ r: Rect) -> Path {
        let path = Path()
        path.fillType = .evenOdd
        for sub in g.subpaths where sub.fill { path.addPath(FreeformGeometry.path(sub, in: r), Offset.zero) }
        return path
    }

    /// PowerPoint blends gradient stops in linear light, so the middle of
    /// red-to-green is a bright orange, not the sRGB midpoint's brown. The
    /// shader blends in sRGB; these are the stops with linear-light
    /// in-betweens spelled out, so it lands where PowerPoint does.
    static func linearLight(_ stops: [SlideFill.GradientStop]) -> ([Color], [Double]) {
        func lin(_ v: Int) -> Double { let c = Double(v) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func srgb(_ l: Double) -> Int { let c = l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055; return Int((max(0, min(1, c)) * 255).rounded()) }
        var colors: [Color] = [], positions: [Double] = []
        for i in 0 ..< stops.count {
            let s = stops[i]
            if i > 0 {
                let a = stops[i - 1]
                let steps = 8
                for k in 1 ..< steps {
                    let t = Double(k) / Double(steps)
                    func part(_ c: Color, _ sh: Int) -> Int { (c.value >> sh) & 0xFF }
                    func ch(_ sh: Int) -> Int {
                        let from = lin(part(a.color, sh)), to = lin(part(s.color, sh))
                        return srgb(from * (1 - t) + to * t)
                    }
                    let aa = Double(part(a.color, 24)), sa = Double(part(s.color, 24))
                    let alpha = Int((aa * (1 - t) + sa * t).rounded())
                    let red = ch(16), green = ch(8), blue = ch(0)
                    let packed: Int = (alpha << 24) | (red << 16) | (green << 8) | blue
                    colors.append(Color(packed))
                    positions.append(a.position + (s.position - a.position) * t)
                }
            }
            colors.append(s.color)
            positions.append(s.position)
        }
        return (colors, positions)
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
        case "mathMinus":
            path.addRect(Rect.fromLTWH(l + w * 0.1, t + h * (0.5 - 0.1176), w * 0.8, h * 0.2352))
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
