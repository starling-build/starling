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

/// Draws a slide scaled so that it fills `size`.
final class SlidePainter: CustomPainter {
    let slide: Slide
    let theme: DeckTheme
    let slideSize: Size
    let revision: Int
    let cache: SlideTextCache
    /// Skip text bodies (the editing canvas draws them live).
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
        for shape in slide.shapes {
            Self.paintShape(shape, canvas, pxPerPt: px, cache: cache, text: !shapesOnly)
        }
        canvas.restore()
    }

    static func paintShape(_ shape: SlideShape, _ canvas: any Canvas, pxPerPt px: Double,
                           cache: SlideTextCache, text: Bool) {
        let f = shape.frame
        let r = Rect.fromLTWH(f.left * px, f.top * px, f.width * px, f.height * px)
        if let fill = shape.fill {
            let p = Paint()
            p.style = .fill
            p.color = fill
            canvas.drawRect(r, p)
        }
        if let line = shape.outline {
            let p = Paint()
            p.style = .stroke
            p.strokeWidth = max(0.5, shape.outlineWidth * px)
            p.color = line
            canvas.drawRect(r, p)
        }
        guard text, !shape.isEmptyText, let layout = cache.layout(shape, pxPerPt: px),
              let doc = shape.text?.document else { return }
        canvas.save()
        canvas.translate(r.left + shape.insets.left * px, r.top + cache.textTop(shape, pxPerPt: px))
        layout.paint(canvas, visible: Rect.fromLTWH(0, -10_000, layout.width, layout.totalHeight + 20_000),
                     document: doc, selection: nil, caret: nil)
        canvas.restore()
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

    init(onSize: @escaping (Size) -> Void, child: Widget?) {
        self.onSize = onSize
        super.init(key: nil, child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        _RenderSizeReporter(onSize: onSize)
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        (renderObject as! _RenderSizeReporter).onSize = onSize
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
