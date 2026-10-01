// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The editing canvas: the current slide, zoomed to fit the space it is
// given. Each shape is a painted layer with, for a text body, a live
// RichEditable over it, stacked in the slide's z-order; on top sit the
// selection frames, handles and smart guides.
//
// Two rules keep the editors alive (both learned the hard way, S1):
// every per-shape subtree is keyed by the shape's id, and its own child
// list has the same shape every build — an element that moves index
// remounts, and a remounted editor loses the typing under the click.

import Flutter
import FlutterSwiftBridge
import Foundation

final class SlideCanvas: StatefulWidget {
    let deck: DeckController
    let cache: SlideTextCache
    /// The shape whose text is being edited, if any.
    let active: SlideShape?
    /// Start (or with nil, stop) editing a shape's text.
    let onEdit: (SlideShape?) -> Void
    let onShortcut: (KeyData, KeyModifiers) -> Bool
    let spellChecker: RichSpellChecker?

    init(key: (any Key)? = nil, deck: DeckController, cache: SlideTextCache, active: SlideShape?,
         onEdit: @escaping (SlideShape?) -> Void,
         onShortcut: @escaping (KeyData, KeyModifiers) -> Bool,
         spellChecker: RichSpellChecker?) {
        self.deck = deck
        self.cache = cache
        self.active = active
        self.onEdit = onEdit
        self.onShortcut = onShortcut
        self.spellChecker = spellChecker
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { SlideCanvasState() }
}

/// A smart guide: a line through the slide at `at` points.
struct SlideGuide: Equatable {
    let vertical: Bool
    let at: Double
}

final class SlideCanvasState: State<StatefulWidget> {
    private var _area = Size.zero
    private var _focus: [Int: FocusNode] = [:]
    private weak var _box: RenderBox?
    // Where the slide sits in the canvas, at the last build.
    private var _ox = 0.0
    private var _oy = 0.0
    private var _px = 0.0

    private enum Drag {
        case move(start: Offset, frames: [(SlideShape, Rect)], shape: SlideShape, wasSelected: Bool, moved: Bool)
        case resize(shape: SlideShape, handle: Int, start: Offset, frame: Rect)
        case rotate(shape: SlideShape, startAngle: Double, startRotation: Double)
        case marquee(start: Offset, now: Offset)
    }
    private var _drag: Drag? = nil
    private var _guides: [SlideGuide] = []

    private var _w: SlideCanvas { widget as! SlideCanvas }
    private var deck: DeckController { _w.deck }

    override func dispose() {
        for node in _focus.values { node.dispose() }
        _focus.removeAll()
        super.dispose()
    }

    /// The focus node for a shape's editor, made on first use.
    func focusNode(for shape: SlideShape) -> FocusNode {
        if let n = _focus[shape.id] { return n }
        let n = FocusNode(debugLabel: "slide shape \(shape.id)")
        _focus[shape.id] = n
        return n
    }

    // MARK: Geometry

    /// Device pixels per point at the current fit.
    private func _pxPerPt(_ slide: Size) -> Double {
        let margin = 32.0
        guard _area.width > margin * 2, _area.height > margin * 2 else { return 0 }
        return min((_area.width - margin * 2) / slide.width, (_area.height - margin * 2) / slide.height)
    }

    /// A window position as a point on the slide.
    private func _slidePoint(_ global: Offset) -> Offset {
        let local = _box?.globalToLocal(global) ?? global
        return Offset((local.dx - _ox) / max(_px, 0.001), (local.dy - _oy) / max(_px, 0.001))
    }

    static func rotate(_ v: Offset, _ degrees: Double) -> Offset {
        let a = degrees * .pi / 180
        return Offset(v.dx * cos(a) - v.dy * sin(a), v.dx * sin(a) + v.dy * cos(a))
    }

    /// Unit position of handle `i` (clockwise from top-left).
    static let handleUnits: [(Double, Double)] = [
        (0, 0), (0.5, 0), (1, 0), (1, 0.5), (1, 1), (0.5, 1), (0, 1), (0, 0.5),
    ]

    /// A point of the shape's frame, in slide points, rotation included.
    private static func _framePoint(_ shape: SlideShape, _ ux: Double, _ uy: Double) -> Offset {
        let f = shape.frame
        let local = Offset((ux - 0.5) * f.width, (uy - 0.5) * f.height)
        let r = rotate(local, shape.rotation)
        return Offset(f.center.dx + r.dx, f.center.dy + r.dy)
    }

    // MARK: Build

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let dark = fluent.brightness == .dark
        let backdrop = dark ? Color(0xFF202020) : Color(0xFFE6E6E6)
        let slide = deck.currentSlide
        let px = _pxPerPt(deck.slideSize)
        var layers: [Widget] = [
            // The backdrop: a click clears the selection and ends editing,
            // a drag draws a selection marquee.
            Positioned(key: ValueKey("backdrop"), left: 0, top: 0, right: 0, bottom: 0, child: Listener(
                onPointerDown: { [weak self] e in self?._backdropDown(e) },
                onPointerMove: { [weak self] e in self?._pointerMove(e) },
                onPointerUp: { [weak self] e in self?._pointerUp(e) },
                behavior: .opaque,
                child: ColoredBox(color: backdrop, child: SizedBox(expand: ())))),
        ]
        if px > 0 {
            let w = (deck.slideSize.width * px).rounded()
            let h = (deck.slideSize.height * px).rounded()
            let ox = ((_area.width - w) / 2).rounded()
            let oy = ((_area.height - h) / 2).rounded()
            _ox = ox; _oy = oy; _px = px
            layers.append(Positioned(key: ValueKey("shadow"), left: ox - 1, top: oy + 1, width: w + 2, height: h + 2,
                                     child: IgnorePointer(child: ColoredBox(color: Color(0x33000000), child: SizedBox(expand: ())))))
            layers.append(Positioned(key: ValueKey("background"), left: ox, top: oy, width: w, height: h,
                                     child: IgnorePointer(child: CustomPaint(
                painter: SlidePainter(slide: slide, theme: deck.theme, slideSize: deck.slideSize,
                                      revision: deck.revision, cache: _w.cache, shapesOnly: true),
                child: SizedBox(expand: ())))))
            for shape in slide.shapes {
                layers.append(_shapeLayer(shape, ox: ox, oy: oy, w: w, h: h, px: px, fluent: fluent))
            }
            layers.append(Positioned(key: ValueKey("chrome"), left: 0, top: 0, right: 0, bottom: 0,
                                     child: _selectionChrome(slide, ox: ox, oy: oy, px: px, fluent: fluent)))
        }
        return SizeReporter(onSize: { [weak self] size in
            guard let self, self.mounted, size != self._area else { return }
            self.setState { self._area = size }
        }, onBox: { [weak self] box in self?._box = box }, child: Stack(children: layers))
    }

    /// One shape: its painted body, its text editor if it has text, and the
    /// grip that selects and drags it. Always the same three children.
    private func _shapeLayer(_ shape: SlideShape, ox: Double, oy: Double, w: Double, h: Double,
                             px: Double, fluent: FluentThemeData) -> Widget {
        let f = shape.frame
        let editing = _w.active === shape
        let body = Positioned(left: 0, top: 0, right: 0, bottom: 0, child: IgnorePointer(child: CustomPaint(
            painter: ShapePainter(shape: shape, px: px, revision: deck.revision, cache: _w.cache),
            child: SizedBox(expand: ()))))
        let text: Widget = shape.text == nil
            ? Positioned(left: 0, top: 0, width: 0, height: 0, child: SizedBox(width: 0, height: 0, child: nil))
            : Positioned(left: f.left * px, top: f.top * px, width: f.width * px, height: f.height * px,
                         child: Transform(rotate: shape.rotation * .pi / 180,
                                          child: _textBody(shape, px: px, editing: editing, fluent: fluent)))
        // The grip: the whole shape for a drawn one (clicked to select,
        // dragged to move), only a band along the edges for a text box
        // (whose inside belongs to its editor). Off while its text is
        // being edited, so the editor takes the clicks.
        let band = 6.0
        let isLine = shape.preset?.isLine == true
        let gripRect = isLine
            ? Rect.fromLTRB(min(f.left, f.right) * px - band, min(f.top, f.bottom) * px - band,
                            max(f.left, f.right) * px + band, max(f.top, f.bottom) * px + band)
            : Rect.fromLTWH(f.left * px, f.top * px, f.width * px, f.height * px)
        let grip = Positioned(left: gripRect.left, top: gripRect.top, width: gripRect.width, height: gripRect.height,
                              child: Transform(rotate: shape.rotation * .pi / 180, child: IgnorePointer(
            ignoring: editing && !shape.editsOnFirstClick,
            child: _gripArea(shape, band: shape.editsOnFirstClick ? band : nil))))
        return Positioned(key: ValueKey("shape \(shape.id)"), left: ox, top: oy, width: w, height: h,
                          child: Stack(clipBehavior: .none, children: [body, text, grip]))
    }

    /// The area that selects and drags a shape. With `band`, only a frame
    /// that wide around the edges; the middle passes clicks through.
    private func _gripArea(_ shape: SlideShape, band: Double?) -> Widget {
        let listener: (Widget) -> Widget = { [weak self] child in
            Listener(
                onPointerDown: { e in self?._shapeDown(shape, e) },
                onPointerMove: { e in self?._pointerMove(e) },
                onPointerUp: { e in self?._pointerUp(e) },
                behavior: .opaque,
                child: MouseRegion(cursor: SystemMouseCursors.move, child: child))
        }
        guard let b = band else {
            return listener(SizedBox(expand: ()))
        }
        // Left 0 / right 0 spans, not one-edge anchors: a Positioned with
        // `right:` and no width hit-tests as nothing (CLAUDE.md).
        return Stack(children: [
            Positioned(left: 0, top: 0, right: 0, height: b, child: listener(SizedBox(expand: ()))),
            Positioned(left: 0, right: 0, bottom: 0, height: b, child: listener(SizedBox(expand: ()))),
            Positioned(left: 0, top: 0, bottom: 0, width: b, child: listener(SizedBox(expand: ()))),
            Positioned(top: 0, right: 0, bottom: 0, width: b, child: listener(SizedBox(expand: ()))),
        ])
    }

    /// A text body: outline, prompt, editor — the same three every build.
    private func _textBody(_ shape: SlideShape, px: Double, editing: Bool, fluent: FluentThemeData) -> Widget {
        guard let controller = shape.text, let theme = shape.textTheme else {
            return SizedBox(width: 0, height: 0, child: nil)
        }
        let f = shape.frame
        let empty = shape.isEmptyText
        let selected = deck.isSelected(shape)
        let textTop = _w.cache.textTop(shape, pxPerPt: px)
        let pad = EdgeInsets(left: shape.insets.left * px, top: max(0, textTop),
                             right: shape.insets.right * px, bottom: shape.insets.bottom * px)
        var stack: [Widget] = []
        // An empty placeholder shows a grey outline until it is selected
        // (the selection frame takes over then).
        let outlined = empty && shape.role != nil && !selected && !editing
        stack.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(
                color: outlined ? Color(0xFFA0A0A0) : Color(0x00000000), width: 1)),
            child: SizedBox(expand: ())))))
        // The prompt sits where the first line would, in the shape's own
        // size and alignment, greyed — after the bullet, in a list.
        let showPrompt = empty && !editing && shape.prompt != nil
        let first = controller.document.paragraphs.first?.style
        let promptStyle = Flutter.TextStyle(color: Color(0xFF8A8A8A),
                                            fontSize: theme.fontSize * px,
                                            height: first?.lineSpacing ?? 1.0,
                                            fontFamily: theme.fontFamilyResolver?(theme.fontFamily ?? "") ?? theme.fontFamily)
        let align = first?.alignment ?? .left
        let bullet = first?.list != nil ? theme.listIndent * px : 0
        let room = (f.height - shape.insets.top - shape.insets.bottom) * px
        let lineH = theme.fontSize * px * 1.2
        let promptTop: Double
        switch shape.anchor {
        case .top: promptTop = shape.insets.top * px + (first?.spaceBefore ?? 0) * px
        case .middle: promptTop = shape.insets.top * px + (room - lineH) / 2
        case .bottom: promptTop = shape.insets.top * px + room - lineH
        }
        stack.append(Positioned(left: pad.left + bullet, top: max(0, promptTop), right: pad.right, height: lineH * 1.5,
                                child: IgnorePointer(child: Text(
                                    showPrompt ? shape.prompt! : "", style: promptStyle,
                                    textAlign: align == .center ? .center : align == .right ? .right : .left))))
        stack.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Listener(
            onPointerDown: { [weak self] _ in
                guard let self, self._w.active !== shape else { return }
                self.deck.selectShapes([shape])
                self._w.onEdit(shape)
            },
            behavior: .translucent,
            child: RichEditable(
                key: ValueKey(shape.id),
                controller: controller, theme: theme, padding: pad,
                focusNode: focusNode(for: shape), autofocus: false,
                backgroundColor: nil, zoom: px / theme.pixelsPerPoint,
                onShortcut: _w.onShortcut,
                spellChecker: _w.spellChecker))))
        return Stack(children: stack)
    }

    // MARK: Selection chrome

    private func _selectionChrome(_ slide: Slide, ox: Double, oy: Double, px: Double,
                                  fluent: FluentThemeData) -> Widget {
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        var children: [Widget] = [
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: IgnorePointer(child: CustomPaint(
                painter: _ChromePainter(selection: deck.selection, active: _w.active, guides: _guides,
                                        marquee: _marqueeRect, slideSize: deck.slideSize,
                                        ox: ox, oy: oy, px: px, accent: accent),
                child: SizedBox(expand: ())))),
        ]
        // Handles on a single selection.
        if deck.selection.count == 1, let shape = deck.selection.first {
            let s = 9.0
            let isLine = shape.preset?.isLine == true
            let units: [(Int, (Double, Double))] = isLine
                ? [(0, (0, 0)), (4, (1, 1))]
                : Array(Self.handleUnits.enumerated()).map { ($0.offset, $0.element) }
            for (i, u) in units {
                let p = Self._framePoint(shape, u.0, u.1)
                children.append(Positioned(left: ox + p.dx * px - s / 2, top: oy + p.dy * px - s / 2, width: s, height: s,
                                           child: _handle(accent: accent, cursor: Self._cursor(i, shape.rotation)) { [weak self] e in
                                               guard let self else { return }
                                               self._drag = .resize(shape: shape, handle: i,
                                                                    start: self._slidePoint(e.position),
                                                                    frame: shape.frame)
                                               self.deck.beginFrameEdit()
                                           }))
            }
            if !isLine {
                let top = Self._framePoint(shape, 0.5, 0)
                let up = Self.rotate(Offset(0, -22 / px), shape.rotation)
                let p = Offset(top.dx + up.dx, top.dy + up.dy)
                children.append(Positioned(left: ox + p.dx * px - 6, top: oy + p.dy * px - 6, width: 12, height: 12,
                                           child: _handle(accent: accent, round: true, cursor: SystemMouseCursors.grab) { [weak self] e in
                                               guard let self else { return }
                                               let c = shape.frame.center
                                               let q = self._slidePoint(e.position)
                                               self._drag = .rotate(shape: shape,
                                                                    startAngle: atan2(q.dy - c.dy, q.dx - c.dx) * 180 / .pi,
                                                                    startRotation: shape.rotation)
                                               self.deck.beginFrameEdit()
                                           }))
            }
        }
        return Stack(children: children)
    }

    private static func _cursor(_ handle: Int, _ rotation: Double) -> MouseCursor {
        // The handle's direction turned by the shape's rotation, in eighths.
        let steps = Int((rotation / 45).rounded()) & 7
        switch (handle + steps) % 4 {
        case 0: return SystemMouseCursors.resizeUpLeftDownRight
        case 1: return SystemMouseCursors.resizeUpDown
        case 2: return SystemMouseCursors.resizeUpRightDownLeft
        default: return SystemMouseCursors.resizeLeftRight
        }
    }

    private func _handle(accent: Color, round: Bool = false, cursor: MouseCursor,
                         onDown: @escaping (PointerDownEvent) -> Void) -> Widget {
        Listener(
            onPointerDown: onDown,
            onPointerMove: { [weak self] e in self?._pointerMove(e) },
            onPointerUp: { [weak self] e in self?._pointerUp(e) },
            behavior: .opaque,
            child: MouseRegion(cursor: cursor, child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFFFFFFF),
                                          border: Border.all(color: accent, width: 1.5),
                                          borderRadius: BorderRadius.all(Radius(circular: round ? 6 : 1))),
                child: SizedBox(expand: ()))))
    }

    private var _marqueeRect: Rect? {
        guard case .marquee(let a, let b)? = _drag else { return nil }
        return Rect.fromLTRB(min(a.dx, b.dx), min(a.dy, b.dy), max(a.dx, b.dx), max(a.dy, b.dy))
    }

    // MARK: Pointer

    private func _backdropDown(_ e: PointerDownEvent) {
        FocusManager.instance.focusedNode?.unfocus()
        _w.onEdit(nil)
        deck.selectShapes([])
        let p = _slidePoint(e.position)
        _drag = .marquee(start: p, now: p)
    }

    private func _shapeDown(_ shape: SlideShape, _ e: PointerDownEvent) {
        Self._log("down on shape \(shape.id) at \(e.position)")
        let wasSelected = deck.isSelected(shape)
        if _w.active !== shape {
            // Leaves any text being edited (a box's or the notes') and
            // gives the keyboard back to the deck: Delete, arrows, ⌘D.
            FocusManager.instance.focusedNode?.unfocus()
            _w.onEdit(nil)
        }
        if !wasSelected { deck.selectShapes([shape]) }
        let frames = deck.selection.map { ($0, $0.frame) }
        _drag = .move(start: _slidePoint(e.position), frames: frames, shape: shape,
                      wasSelected: wasSelected, moved: false)
    }

    private static let _debug = ProcessInfo.processInfo.environment["STARLING_SLIDES_DEBUG"] != nil
    private static func _log(_ m: String) {
        guard _debug else { return }
        let line = m + "\n"
        _ = line.withCString { write(2, $0, strlen($0)) }
    }

    private func _pointerMove(_ e: PointerMoveEvent) {
        Self._log("move \(e.position) drag=\(_drag.map { "\($0)".prefix(12) } ?? "nil")")
        _dragTo(e.position)
    }

    /// Follow the pointer to `global`. The release goes through here too:
    /// moves can be coalesced away while a frame is busy, and the drag must
    /// end where the pointer did, not at the last move that got through.
    private func _dragTo(_ global: Offset) {
        guard let drag = _drag else { return }
        let p = _slidePoint(global)
        switch drag {
        case .move(let start, let frames, let shape, let wasSelected, var moved):
            var dx = p.dx - start.dx, dy = p.dy - start.dy
            if !moved {
                guard abs(dx) * _px > 3 || abs(dy) * _px > 3 else { return }
                moved = true
                deck.beginFrameEdit()
            }
            let snapped = _snapMove(frames.map(\.1), dx: dx, dy: dy)
            dx = snapped.dx; dy = snapped.dy
            _drag = .move(start: start, frames: frames, shape: shape, wasSelected: wasSelected, moved: moved)
            deck.setFramesLive(frames.map { ($0.0, $0.1.shift(Offset(dx, dy))) })
        case .resize(let shape, let handle, let start, let frame):
            deck.setFramesLive([(shape, _resized(shape, frame, handle: handle,
                                                 delta: Offset(p.dx - start.dx, p.dy - start.dy)))])
        case .rotate(let shape, let startAngle, let startRotation):
            let c = shape.frame.center
            let angle = atan2(p.dy - c.dy, p.dx - c.dx) * 180 / .pi
            var r = startRotation + angle - startAngle
            // Settle on the right angles when near them.
            for target in stride(from: -360.0, through: 360, by: 90) where abs(r - target) < 3 { r = target }
            deck.setRotationLive(shape, r)
        case .marquee(let start, _):
            _drag = .marquee(start: start, now: p)
            setState {}
        }
    }

    private func _pointerUp(_ e: PointerUpEvent) {
        Self._log("up \(e.position)")
        _dragTo(e.position)
        guard let drag = _drag else { return }
        _drag = nil
        _guides = []
        switch drag {
        case .move(_, _, let shape, let wasSelected, let moved):
            if moved {
                deck.endFrameEdit()
            } else if wasSelected, shape.text != nil, _w.active !== shape {
                // A click on a shape already selected starts typing into it,
                // at the end of its text.
                _w.onEdit(shape)
                FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in
                    guard let text = shape.text else { return }
                    self?.focusNode(for: shape).requestFocus()
                    let last = text.document.paragraphs.count - 1
                    text.moveTo(RichPosition(paragraph: last, offset: text.document.paragraphs[last].length),
                                extend: false)
                }
                PlatformDispatcher.instance.scheduleFrame()
            }
        case .resize, .rotate:
            deck.endFrameEdit()
        case .marquee(let a, let b):
            let box = Rect.fromLTRB(min(a.dx, b.dx), min(a.dy, b.dy), max(a.dx, b.dx), max(a.dy, b.dy))
            if box.width > 2 || box.height > 2 {
                // PowerPoint selects what the marquee wholly contains.
                deck.selectShapes(deck.currentSlide.shapes.filter {
                    box.contains($0.frame.topLeft) && box.contains($0.frame.bottomRight)
                })
            }
        }
        setState {}
    }

    // MARK: Resize and snapping

    /// The frame after dragging handle `handle` by `delta` (slide points),
    /// with the opposite handle pinned where it was on the slide — rotation
    /// included, so a turned shape grows along its own axes.
    private func _resized(_ shape: SlideShape, _ frame: Rect, handle: Int, delta: Offset) -> Rect {
        if shape.preset?.isLine == true {
            // A line's two ends move freely.
            return handle == 0
                ? Rect.fromLTRB(frame.left + delta.dx, frame.top + delta.dy, frame.right, frame.bottom)
                : Rect.fromLTRB(frame.left, frame.top, frame.right + delta.dx, frame.bottom + delta.dy)
        }
        let r = Self.resizedFrame(frame, rotation: shape.rotation, handle: handle, delta: delta)
        return shape.rotation == 0 ? _snapResize(r, handle: handle) : r
    }

    /// Pure resize geometry, for tests: the opposite handle stays put.
    static func resizedFrame(_ frame: Rect, rotation rot: Double, handle: Int, delta: Offset) -> Rect {
        let (hx, hy) = handleUnits[handle]
        let d = rotate(delta, -rot)
        let sx = hx == 1 ? 1.0 : hx == 0 ? -1.0 : 0
        let sy = hy == 1 ? 1.0 : hy == 0 ? -1.0 : 0
        let w = max(4, frame.width + d.dx * sx)
        let h = max(4, frame.height + d.dy * sy)
        let ax = 1 - hx, ay = 1 - hy
        let before = rotate(Offset((ax - 0.5) * frame.width, (ay - 0.5) * frame.height), rot)
        let anchor = Offset(frame.center.dx + before.dx, frame.center.dy + before.dy)
        let after = rotate(Offset((ax - 0.5) * w, (ay - 0.5) * h), rot)
        let c = Offset(anchor.dx - after.dx, anchor.dy - after.dy)
        return Rect.fromLTWH(c.dx - w / 2, c.dy - h / 2, w, h)
    }

    /// Lines a dragged edge or centre can settle on: the slide's edges and
    /// centre, and every other shape's.
    private func _targets(excluding: [SlideShape]) -> (xs: [Double], ys: [Double]) {
        var xs = [0, deck.slideSize.width / 2, deck.slideSize.width]
        var ys = [0, deck.slideSize.height / 2, deck.slideSize.height]
        for s in deck.currentSlide.shapes where !excluding.contains(where: { $0 === s }) {
            let f = s.frame
            xs += [f.left, f.center.dx, f.right]
            ys += [f.top, f.center.dy, f.bottom]
        }
        return (xs, ys)
    }

    private var _snapDistance: Double { 6 / max(_px, 0.001) }

    private func _snapMove(_ frames: [Rect], dx: Double, dy: Double) -> Offset {
        guard let first = frames.first else { return Offset(dx, dy) }
        let box = frames.dropFirst().reduce(first) { $0.expandToInclude($1) }.shift(Offset(dx, dy))
        let (xs, ys) = _targets(excluding: deck.selection)
        var guides: [SlideGuide] = []
        var outX = dx, outY = dy
        if let (target, edge) = _nearest([box.left, box.center.dx, box.right], xs) {
            outX += target - edge
            guides.append(SlideGuide(vertical: true, at: target))
        }
        if let (target, edge) = _nearest([box.top, box.center.dy, box.bottom], ys) {
            outY += target - edge
            guides.append(SlideGuide(vertical: false, at: target))
        }
        _guides = guides
        return Offset(outX, outY)
    }

    private func _snapResize(_ r: Rect, handle: Int) -> Rect {
        let (hx, hy) = Self.handleUnits[handle]
        let (xs, ys) = _targets(excluding: deck.selection)
        var out = r
        var guides: [SlideGuide] = []
        if hx != 0.5, let (target, edge) = _nearest([hx == 1 ? r.right : r.left], xs) {
            out = hx == 1 ? Rect.fromLTRB(out.left, out.top, out.right + target - edge, out.bottom)
                          : Rect.fromLTRB(out.left + target - edge, out.top, out.right, out.bottom)
            guides.append(SlideGuide(vertical: true, at: target))
        }
        if hy != 0.5, let (target, edge) = _nearest([hy == 1 ? r.bottom : r.top], ys) {
            out = hy == 1 ? Rect.fromLTRB(out.left, out.top, out.right, out.bottom + target - edge)
                          : Rect.fromLTRB(out.left, out.top + target - edge, out.right, out.bottom)
            guides.append(SlideGuide(vertical: false, at: target))
        }
        _guides = guides
        return out.width >= 4 && out.height >= 4 ? out : r
    }

    /// The closest (target, own line) pair within snapping distance.
    private func _nearest(_ own: [Double], _ targets: [Double]) -> (Double, Double)? {
        var best: (Double, Double)? = nil
        var bestD = _snapDistance
        for o in own {
            for t in targets where abs(t - o) < bestD {
                bestD = abs(t - o)
                best = (t, o)
            }
        }
        return best
    }
}

/// Selection frames, smart guides and the marquee.
private final class _ChromePainter: CustomPainter {
    let selection: [SlideShape]
    let active: SlideShape?
    let guides: [SlideGuide]
    let marquee: Rect?
    let slideSize: Size
    let ox: Double, oy: Double, px: Double
    let accent: Color

    init(selection: [SlideShape], active: SlideShape?, guides: [SlideGuide], marquee: Rect?, slideSize: Size,
         ox: Double, oy: Double, px: Double, accent: Color) {
        self.selection = selection
        self.active = active
        self.guides = guides
        self.marquee = marquee
        self.slideSize = slideSize
        self.ox = ox; self.oy = oy; self.px = px
        self.accent = accent
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let line = Paint()
        line.style = .stroke
        line.isAntiAlias = true
        line.strokeWidth = 1.25
        line.color = accent
        for shape in selection {
            let f = shape.frame
            let r = Rect.fromLTWH(ox + f.left * px, oy + f.top * px, f.width * px, f.height * px)
            canvas.save()
            if shape.rotation != 0 {
                canvas.translate(r.center.dx, r.center.dy)
                canvas.rotate(shape.rotation * .pi / 180)
                canvas.translate(-r.center.dx, -r.center.dy)
            }
            if shape.preset?.isLine != true {
                if shape === active {
                    // Editing text: PowerPoint's dashed frame.
                    Self._dashed(canvas, r, line)
                } else {
                    canvas.drawRect(r, line)
                }
                if selection.count == 1 {
                    // The stalk of the rotation handle.
                    canvas.drawLine(Offset(r.center.dx, r.top), Offset(r.center.dx, r.top - 16), line)
                }
            }
            canvas.restore()
        }
        let guide = Paint()
        guide.style = .stroke
        guide.strokeWidth = 1
        guide.color = Color(0xFFE8443A)
        for g in guides {
            if g.vertical {
                let x = ox + g.at * px
                canvas.drawLine(Offset(x, oy), Offset(x, oy + slideSize.height * px), guide)
            } else {
                let y = oy + g.at * px
                canvas.drawLine(Offset(ox, y), Offset(ox + slideSize.width * px, y), guide)
            }
        }
        if let m = marquee {
            let r = Rect.fromLTRB(ox + m.left * px, oy + m.top * px, ox + m.right * px, oy + m.bottom * px)
            let fill = Paint()
            fill.style = .fill
            fill.color = accent.withOpacity(0.12)
            canvas.drawRect(r, fill)
            canvas.drawRect(r, line)
        }
    }

    private static func _dashed(_ canvas: any Canvas, _ r: Rect, _ paint: Paint) {
        let dash = 5.0, gap = 3.0
        func run(_ a: Offset, _ b: Offset) {
            let len = hypot(b.dx - a.dx, b.dy - a.dy)
            guard len > 0 else { return }
            let ux = (b.dx - a.dx) / len, uy = (b.dy - a.dy) / len
            var t = 0.0
            while t < len {
                let e = min(len, t + dash)
                canvas.drawLine(Offset(a.dx + ux * t, a.dy + uy * t), Offset(a.dx + ux * e, a.dy + uy * e), paint)
                t = e + gap
            }
        }
        run(r.topLeft, r.topRight)
        run(r.topRight, r.bottomRight)
        run(r.bottomRight, r.bottomLeft)
        run(r.bottomLeft, r.topLeft)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool { true }
}
