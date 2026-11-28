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
import FluentSystemIcons
import OfficeText
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
    /// The modifier keys held now (Shift or Ctrl/Cmd + click adds to the selection).
    let modifiers: () -> KeyModifiers
    let spellChecker: RichSpellChecker?
    /// Number each animated shape by the click that brings it in, as
    /// PowerPoint does while its Animations tab is open.
    let animationBadges: Bool
    /// A right-click: where, and on which shape (nil for the empty slide).
    let onContextMenu: ((Offset, SlideShape?) -> Void)?
    /// The Paste Options button was pressed: open its menu at this window point (S-ED-1 step 3).
    let onPasteOptions: ((Offset) -> Void)?
    /// Ctrl/Cmd+click on a link in the text being edited (S-TX-4).
    let onFollowLink: ((String) -> Void)?

    init(key: (any Key)? = nil, deck: DeckController, cache: SlideTextCache, active: SlideShape?,
         onEdit: @escaping (SlideShape?) -> Void,
         onShortcut: @escaping (KeyData, KeyModifiers) -> Bool,
         modifiers: @escaping () -> KeyModifiers = { [] },
         spellChecker: RichSpellChecker?, animationBadges: Bool = false,
         onContextMenu: ((Offset, SlideShape?) -> Void)? = nil,
         onPasteOptions: ((Offset) -> Void)? = nil,
         onFollowLink: ((String) -> Void)? = nil) {
        self.onFollowLink = onFollowLink
        self.modifiers = modifiers
        self.onPasteOptions = onPasteOptions
        self.onContextMenu = onContextMenu
        self.animationBadges = animationBadges
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
        /// A crop handle of a picture in crop mode: the frame moves over the picture, which stays.
        case crop(shape: SlideShape, handle: Int, start: Offset, frame: Rect, crop: EdgeInsets?)
        /// A drag inside a picture in crop mode: the picture slides under the frame, which stays.
        case pan(shape: SlideShape, start: Offset, crop: EdgeInsets?, moved: Bool)
        /// A handle of one shape in a multi-selection: that shape resizes as alone, and every other selected shape
        /// scales by the same factors about its own opposite handle (PowerPoint's way).
        case resizeAll(lead: SlideShape, handle: Int, start: Offset, frames: [(SlideShape, Rect)])
        case rotate(shape: SlideShape, startAngle: Double, startRotation: Double)
        /// The yellow handle of an elbow's middle run.
        case elbowRun(shape: SlideShape, key: String, alongWidth: Bool)
        case adjust(shape: SlideShape, handle: Int)
        case marquee(start: Offset, now: Offset)
        /// A shape chosen from the gallery, being drawn by dragging out its box.
        case draw(preset: ShapePreset, start: Offset, now: Offset)
        /// A drawing guide being dragged; `at` is where it is now (slide points).
        case guide(index: Int, at: Double)
    }
    private var _drag: Drag? = nil
    /// A finger has touched the canvas: the handles get a fingertip's reach (they are drawn the same).
    private var _touchSeen = false
    private static let touchReach = 44.0
    /// How far above the top edge a finger's rotate handle sits (a mouse's is 22), clear of the top-middle handle's reach.
    private static let touchLift = 44.0
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
        bind(n)
        _focus[shape.id] = n
        return n
    }

    // MARK: Geometry

    /// Device pixels per point at the current fit.
    private func _pxPerPt(_ slide: Size) -> Double {
        let margin = 32.0
        guard _area.width > margin * 2, _area.height > margin * 2 else { return 0 }
        let fit = min((_area.width - margin * 2) / slide.width, (_area.height - margin * 2) / slide.height)
        if abs(deck.viewFitScale - fit) > 0.0005 {
            deck.viewFitScale = fit
            // The status bar shows the percent; tell it once this frame is done.
            FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in self?.deck.notifyViewChanged() }
        }
        return deck.viewScale ?? fit
    }

    /// A window position as a point on the slide.
    /// Where a slide point is on screen (the harness taps shapes by it).
    func screenPoint(_ p: Offset) -> Offset {
        let local = Offset(p.dx * _px + _ox, p.dy * _px + _oy)
        return _box?.localToGlobal(local) ?? local
    }

    private func _slidePoint(_ global: Offset) -> Offset {
        let local = _box?.globalToLocal(global) ?? global
        return Offset((local.dx - _ox) / max(_px, 0.001), (local.dy - _oy) / max(_px, 0.001))
    }

    /// Where a slide point is on the screen (tests and driver scripts aim at handles with it).
    func globalPoint(ofSlide p: Offset) -> Offset? {
        guard let box = _box else { return nil }
        return box.localToGlobal(Offset(_ox + p.dx * _px, _oy + p.dy * _px))
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
            // A slide bigger than the window is panned, never past its own edge.
            let panX = max(0, (w - _area.width) / 2 + 32), panY = max(0, (h - _area.height) / 2 + 32)
            let pan = deck.viewPan
            let ox = ((_area.width - w) / 2 + max(-panX, min(panX, pan.dx))).rounded()
            let oy = ((_area.height - h) / 2 + max(-panY, min(panY, pan.dy))).rounded()
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
        // (Clipped to the stage: a shape dragged past the slide's top
        // edge was painted over the ribbon — seen on screen 2026-10-13.)
        }, onBox: { [weak self] box in self?._box = box }, child: SlidesAccessibility.wrap(Listener(
            // The wheel over the slide or anything on it: with Ctrl (Cmd) held it zooms a step,
            // as PowerPoint's does; without, it pans a slide zoomed past the window.
            onPointerSignal: { [weak self] e in
                guard let self, let s = e as? PointerScrollEvent else { return }
                let m = self._w.modifiers()
                if m.contains(.control) || m.contains(.meta) { self.deck.wheelZoom(s.scrollDelta.dy) }
                else { self.deck.panView(dx: -s.scrollDelta.dx, dy: -s.scrollDelta.dy) }
            },
            child: ClipRect(child: Stack(children: layers))), deck: deck))
    }

    /// One shape: its painted body, its text editor if it has text, and the
    /// grip that selects and drags it. Always the same three children.
    private func _shapeLayer(_ shape: SlideShape, ox: Double, oy: Double, w: Double, h: Double,
                             px: Double, fluent: FluentThemeData) -> Widget {
        let f = shape.frame
        let editing = _w.active === shape
        let body = Positioned(left: 0, top: 0, right: 0, bottom: 0, child: IgnorePointer(child: CustomPaint(
            painter: ShapePainter(shape: shape, px: px, revision: deck.revision, cache: _w.cache, theme: deck.theme),
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
        // (6 pt on a slide shown at full size; a quarter of the box's shorter drawn side at most: on a slide shown at
        // 100 pt wide a 14 pt-tall box is 2 pt tall on screen, and two 6 pt bands would cover all of it, so a tap
        // could only select it, never edit its text — seen in a 375 pt Split View pane.)
        let isLine = shape.preset?.isLine == true
        // (A line has no inside to protect, and its frame can be zero tall: it keeps the full 6.)
        // (A finger takes a wider frame: 20 pt is about what the pad of a fingertip covers, and the frame is how a shape whose
        // text is being edited is moved by one.)
        let band = isLine ? 6.0 : max(1.0, min(_touchSeen ? 20.0 : 6.0, min(abs(f.width), abs(f.height)) * px / 4))
        let framed = shape.editsOnFirstClick || (editing && _touchSeen)
        let gripRect = isLine
            ? Rect.fromLTRB(min(f.left, f.right) * px - band, min(f.top, f.bottom) * px - band,
                            max(f.left, f.right) * px + band, max(f.top, f.bottom) * px + band)
            : Rect.fromLTWH(f.left * px, f.top * px, f.width * px, f.height * px)
        let grip = Positioned(left: gripRect.left, top: gripRect.top, width: gripRect.width, height: gripRect.height,
                              child: Transform(rotate: shape.rotation * .pi / 180, child: IgnorePointer(
            // (With the border pen or eraser on, a table's grip lets the press through to the table, which draws.)
            ignoring: (editing && !framed) || (shape.kind == .table && deck.tableTool != .none),
            child: _gripArea(shape, band: framed ? band : nil))))
        return Positioned(key: ValueKey("shape \(shape.id)"), left: ox, top: oy, width: w, height: h,
                          child: SlidesAccessibility.wrap(Stack(clipBehavior: .none, children: [body, text, grip]),
                                                          shape: shape, deck: deck))
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
                                            fontSize: theme.fontSize * px * shape.fontScale,
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
            onPointerDown: { [weak self] e in
                guard let self else { return }
                if self._eyedrop(e) { return }
                if e.kind == .touch { self._touchSeen = true }
                if e.buttons & kSecondaryMouseButton != 0, let menu = self._w.onContextMenu {
                    if self._w.active !== shape, !self.deck.isSelected(shape) { self.deck.selectWholeGroup(of: shape) }
                    self._rightClickAt = Date().timeIntervalSince1970
                    menu(e.position, shape)
                    return
                }
                guard self._w.active !== shape else { return }
                if shape.group != nil, !self._additive {
                    // The first click on a group selects it, the second its member; the third types.
                    let whole = self.deck.groupMembers(of: shape)
                    if !self.deck.isSelected(shape) { self.deck.selectShapes(whole); return }
                    if self.deck.selection.count == whole.count, whole.count > 1 { self.deck.selectShapes([shape]); return }
                }
                // Shift/Ctrl+click adds or removes the shape and does not start typing.
                if self._additive { self.deck.toggleSelected(shape); return }
                self.deck.selectShapes([shape])
                self._w.onEdit(shape)
            },
            behavior: .translucent,
            child: RichEditable(
                key: ValueKey(shape.id),
                controller: controller, theme: theme, padding: pad,
                focusNode: focusNode(for: shape), autofocus: false,
                backgroundColor: nil, zoom: px * shape.fontScale / theme.pixelsPerPoint,
                onShortcut: _w.onShortcut,
                onCellEdge: shape.kind == .table && deck.tableTool != .none
                    ? { [weak deck, weak shape] _, row, column, side in if let deck, let shape { deck.penTouch(shape, row: row, column: column, side: side) } } : nil,
                onCellEdgeStroke: shape.kind == .table && deck.tableTool != .none ? { [weak deck] on in deck?.penStroke(on) } : nil,
                onLinkActivate: _w.onFollowLink,
                onContextMenu: { [weak self] at in
                    // (A right click already opened the menu from the layer above: the editor's own would be a second.)
                    guard let self, Date().timeIntervalSince1970 - self._rightClickAt > 0.3 else { return }
                    self._w.onContextMenu?(at, shape)
                },
                onTouchMenu: { [weak controller, scene = self.officeScene] rect in
                    if let controller { scene.showTouchMenu(rect, controller: controller) }
                },
                spellChecker: _w.spellChecker,
                scrolls: false))))
        return Stack(children: stack)
    }

    // MARK: Selection chrome

    private func _selectionChrome(_ slide: Slide, ox: Double, oy: Double, px: Double,
                                  fluent: FluentThemeData) -> Widget {
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        var children: [Widget] = []
        // View > Show: gridlines, drawing guides and the rulers, under the selection's own chrome.
        let grid = deck.grid
        var guides = grid.showGuides ? grid.guides : []
        if case .guide(let i, let at)? = _drag, guides.indices.contains(i) { guides[i].at = at }
        if deck.showGridlines || !guides.isEmpty || deck.showRuler {
            children.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: IgnorePointer(child: CustomPaint(
                painter: SlideGridPainter(spacing: deck.showGridlines ? grid.spacing : 0, guides: guides,
                                          ruler: deck.showRuler, slideSize: deck.slideSize, ox: ox, oy: oy, px: px,
                                          dark: fluent.brightness == .dark),
                child: SizedBox(expand: ())))))
        }
        // A guide is grabbed anywhere along its line.
        for (i, g) in guides.enumerated() {
            let reach = 7.0
            let onDown: (PointerDownEvent) -> Void = { [weak self] e in
                guard let self else { return }
                self._drag = .guide(index: i, at: g.at)
                self.setState {}
            }
            let handle = Listener(onPointerDown: onDown,
                                  onPointerMove: { [weak self] e in self?._pointerMove(e) },
                                  onPointerUp: { [weak self] e in self?._pointerUp(e) },
                                  behavior: .opaque,
                                  child: MouseRegion(cursor: g.vertical ? SystemMouseCursors.resizeLeftRight
                                                                        : SystemMouseCursors.resizeUpDown,
                                                     child: SizedBox(expand: ())))
            children.append(g.vertical
                ? Positioned(key: ValueKey("guide-\(i)"), left: ox + g.at * px - reach, top: oy,
                             width: reach * 2, height: deck.slideSize.height * px, child: handle)
                : Positioned(key: ValueKey("guide-\(i)"), left: ox, top: oy + g.at * px - reach,
                             width: deck.slideSize.width * px, height: reach * 2, child: handle))
        }
        children += [
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: IgnorePointer(child: CustomPaint(
                painter: _ChromePainter(selection: deck.selection, active: _w.active, guides: _guides,
                                        marquee: _marqueeRect, slideSize: deck.slideSize,
                                        ox: ox, oy: oy, px: px, accent: accent,
                                        stalk: _touchSeen ? Self.touchLift - 6 : 16),
                child: SizedBox(expand: ())))),
        ]
        if _w.animationBadges, !slide.animations.isEmpty {
            children.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: IgnorePointer(child: CustomPaint(
                painter: _BadgePainter(slide: slide, selection: deck.selection, ox: ox, oy: oy, px: px, accent: accent,
                                       revision: deck.revision, cache: _w.cache),
                child: SizedBox(expand: ())))))
        }
        // Several shapes selected: each shows its own sizing handles, as PowerPoint's do. Dragging a box's handle resizes
        // every selected shape (see `.resizeAll`); a line's end handles are marks only, and a press there moves the
        // selection, as a press on the shape does.
        if deck.selection.count > 1 {
            let s = _touchSeen ? 14.0 : 9.0
            for (n, shape) in deck.selection.enumerated() {
                let isLine = shape.preset?.isLine == true || shape.isElbow
                let units: [(Double, Double)] = isLine ? [(0, 0), (1, 1)] : Self.handleUnits
                for (i, u) in units.enumerated() {
                    let p = shape.isElbow ? (i == 0 ? shape.lineStart : shape.lineEndPoint) : Self._framePoint(shape, u.0, u.1)
                    let mark: Widget
                    if isLine {
                        mark = IgnorePointer(child: DecoratedBox(
                            decoration: BoxDecoration(color: Color(0xFFFFFFFF),
                                                      border: Border.all(color: accent, width: 1.5),
                                                      borderRadius: BorderRadius.all(Radius(circular: 1))),
                            child: SizedBox(expand: ())))
                    } else {
                        mark = _handle(accent: accent, shown: s, cursor: Self._cursor(i, shape.rotation)) { [weak self] e in
                            guard let self else { return }
                            self._drag = .resizeAll(lead: shape, handle: i, start: self._slidePoint(e.position),
                                                    frames: self.deck.selection.map { ($0, $0.frame) })
                            self.deck.beginFrameEdit()
                        }
                    }
                    children.append(Positioned(key: ValueKey("multi-handle-\(n)-\(i)"),
                                               left: ox + p.dx * px - s / 2, top: oy + p.dy * px - s / 2, width: s, height: s,
                                               child: mark))
                }
            }
        }
        // Handles on a single selection.
        if deck.selection.count == 1, let shape = deck.selection.first {
            let s = _touchSeen ? 14.0 : 9.0
            // A finger's reach, where the shape leaves room: neighbouring handles are half the shape's short side
            // apart, so a hit area never grows past half of that and never over a neighbour's.
            let reach = _touchSeen ? max(s, min(Self.touchReach, min(shape.frame.width, shape.frame.height) * px / 2)) : s
            let isLine = shape.preset?.isLine == true || shape.isElbow
            let units: [(Int, (Double, Double))] = isLine
                ? [(0, (0, 0)), (4, (1, 1))]
                : Array(Self.handleUnits.enumerated()).map { ($0.offset, $0.element) }
            let cropping = deck.cropping === shape
            if cropping, let ghost = _cropGhost(shape, ox: ox, oy: oy, px: px) { children.append(ghost) }
            for (i, u) in units {
                let p = shape.isElbow ? (i == 0 ? shape.lineStart : shape.lineEndPoint) : Self._framePoint(shape, u.0, u.1)
                children.append(Positioned(left: ox + p.dx * px - reach / 2, top: oy + p.dy * px - reach / 2, width: reach, height: reach,
                                           child: _handle(accent: accent, crop: cropping, shown: s, cursor: Self._cursor(i, shape.rotation)) { [weak self] e in
                                               guard let self else { return }
                                               let at = self._slidePoint(e.position)
                                               self._drag = cropping
                                                   ? .crop(shape: shape, handle: i, start: at, frame: shape.frame, crop: shape.crop)
                                                   : .resize(shape: shape, handle: i, start: at, frame: shape.frame)
                                               self.deck.beginFrameEdit()
                                           }))
            }
            for hd in shape.elbowAdjustHandles {
                let p = hd.at
                children.append(Positioned(left: ox + p.dx * px - reach / 2, top: oy + p.dy * px - reach / 2, width: reach, height: reach,
                                           child: _handle(accent: Color(0xFFFFC000), round: true, shown: s, cursor: SystemMouseCursors.grab) { [weak self] _ in
                                               guard let self else { return }
                                               self._drag = .elbowRun(shape: shape, key: hd.key, alongWidth: hd.alongWidth)
                                               self.deck.beginFrameEdit()
                                           }))
            }
            for hd in shape.adjustHandles {
                let p = hd.at
                children.append(Positioned(left: ox + p.dx * px - reach / 2, top: oy + p.dy * px - reach / 2, width: reach, height: reach,
                                           child: _handle(accent: Color(0xFFFFC000), round: true, shown: 9, cursor: SystemMouseCursors.grab) { [weak self] _ in
                                               guard let self else { return }
                                               self._drag = .adjust(shape: shape, handle: hd.index)
                                               self.deck.beginFrameEdit()
                                           }))
            }
            if !isLine {
                let top = Self._framePoint(shape, 0.5, 0)
                let lift = _touchSeen ? Self.touchLift : 22.0
                let up = Self.rotate(Offset(0, -lift / px), shape.rotation)
                let p = Offset(top.dx + up.dx, top.dy + up.dy)
                let rr = _touchSeen ? Self.touchReach - 4 : 12.0
                children.append(Positioned(left: ox + p.dx * px - rr / 2, top: oy + p.dy * px - rr / 2, width: rr, height: rr,
                                           child: _handle(accent: accent, round: true, shown: _touchSeen ? 18 : 12, cursor: SystemMouseCursors.grab) { [weak self] e in
                                               guard let self else { return }
                                               let c = shape.frame.center
                                               let q = self._slidePoint(e.position)
                                               self._drag = .rotate(shape: shape,
                                                                    startAngle: atan2(q.dy - c.dy, q.dx - c.dx) * 180 / .pi,
                                                                    startRotation: shape.rotation)
                                               self.deck.beginFrameEdit()
                                           }))
                // What a finger reaches for with a shape selected, beside its handles: no keyboard to Cmd+D with.
                if _touchSeen, _drag == nil, _twist == nil, _w.active !== shape {
                    children.append(_touchActions(shape, ox: ox, oy: oy, px: px, fluent: fluent))
                }
            }
        }
        if let button = _pasteOptionsButton(ox: ox, oy: oy, px: px, fluent: fluent) { children.append(button) }
        return Stack(children: children)
    }

    /// Where the Paste Options button sits, in the canvas: just past the bottom right of what the last paste put
    /// on the slide, as PowerPoint puts it; nil while there is none to show.
    func pasteOptionsRect() -> Rect? {
        _pasteOptionsRect(ox: _ox, oy: _oy, px: _px)
    }

    private func _pasteOptionsRect(ox: Double, oy: Double, px: Double) -> Rect? {
        guard _w.onPasteOptions != nil, _w.active == nil, _drag == nil, deck.slidePasteOptions != nil,
              let first = deck.selection.first else { return nil }
        let box = deck.selection.dropFirst().reduce(first.frame) { $0.expandToInclude($1.frame) }
        let x = min(ox + box.right * px + 4, _area.width - 34), y = min(oy + box.bottom * px + 4, _area.height - 24)
        return Rect.fromLTWH(max(0, x), max(0, y), 30, 20)
    }

    private func _pasteOptionsButton(ox: Double, oy: Double, px: Double, fluent: FluentThemeData) -> Widget? {
        guard let r = _pasteOptionsRect(ox: ox, oy: oy, px: px) else { return nil }
        let ink = fluent.resources.textFillColorPrimary
        return Positioned(key: ValueKey("paste-options"), left: r.left, top: r.top, width: r.width, height: r.height,
                          child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                      borderRadius: BorderRadius.circular(3)),
            child: FlatButton(child: Icon(FluentSystemIcons.paste, size: 14, color: ink), tip: "Paste Options",
                              width: r.width, height: r.height,
                              action: { [weak self] in
                                  guard let self, let open = self._w.onPasteOptions else { return }
                                  let local = Offset(r.left, r.bottom)
                                  open(self._box?.localToGlobal(local) ?? local)
                              })))
    }

    /// The bar of 44 pt buttons over a selected shape on touch: Duplicate, Delete, and More (the shape's whole menu). It sits
    /// above the rotate handle, or below the shape when there is no room above.
    private func _touchActions(_ shape: SlideShape, ox: Double, oy: Double, px: Double, fluent: FluentThemeData) -> Widget {
        let buttonW = 96.0, h = 44.0, w = buttonW * 2 + 56
        let top = Self._framePoint(shape, 0.5, 0), bottom = Self._framePoint(shape, 0.5, 1)
        let cx = ox + top.dx * px
        var y = oy + top.dy * px - Self.touchLift - h - 28
        if y < 4 { y = oy + bottom.dy * px + 16 }
        let x = max(4, min(max(4, _area.width - w - 4), cx - w / 2))
        func button(_ key: String, _ label: String, _ width: Double, _ action: @escaping () -> Void) -> Widget {
            SizedBox(width: width, height: h, child: Button(key: ValueKey(key), onPressed: action, child: Text(label)))
        }
        return Positioned(key: ValueKey("touch-actions"), left: x, top: y, width: w, height: h, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 3), blurRadius: 10)]),
            child: Row(children: [
                button("touch-duplicate", "Duplicate", buttonW) { [weak self] in self?.deck.duplicateSelection() },
                button("touch-delete", "Delete", buttonW) { [weak self] in self?.deck.deleteSelection() },
                button("touch-more", "…", 56) { [weak self] in
                    guard let self else { return }
                    let at = self.screenPoint(Offset((cx - ox) / px, (y + h - oy) / px))
                    self._w.onContextMenu?(at, shape)
                },
            ])))
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

    /// `shown` is the handle as drawn; the widget is as big as the hit area, so the drawn square sits in its middle.
    /// Crop mode: the whole picture's extent, the part the crop cuts away shaded, so the handles can bring it back.
    private func _cropGhost(_ shape: SlideShape, ox: Double, oy: Double, px: Double) -> Widget? {
        let f = shape.frame, c = shape.crop ?? .zero
        let fullW = f.width / max(1 - c.left - c.right, 0.001), fullH = f.height / max(1 - c.top - c.bottom, 0.001)
        let full = Rect.fromLTWH(-c.left * fullW * px, -c.top * fullH * px, fullW * px, fullH * px)
        let w = f.width * px, h = f.height * px
        // The bands outside the frame (the chrome lies over the shapes, so the frame's own part stays clear).
        let bands = [Rect.fromLTRB(full.left, full.top, full.right, min(0, full.bottom)),
                     Rect.fromLTRB(full.left, max(h, full.top), full.right, full.bottom),
                     Rect.fromLTRB(full.left, max(0, full.top), min(0, full.right), min(h, full.bottom)),
                     Rect.fromLTRB(max(w, full.left), max(0, full.top), full.right, min(h, full.bottom))]
        // The cut-away part is the picture itself, faded (PowerPoint's look); grey until the picture has decoded.
        // (Slivers under half a pixel are rounding, not a cut.)
        let shown = bands.filter { $0.width > 0.5 && $0.height > 0.5 }
        var kids: [Widget] = [Positioned(left: 0, top: 0, width: w, height: h, child: CustomPaint(
            painter: CropGhostPainter(image: shape.picture.flatMap { _w.cache.image($0) }, full: full, bands: shown,
                                       revision: deck.revision),
            child: SizedBox(expand: ())))]
        kids.append(Positioned(left: full.left, top: full.top, width: full.width, height: full.height,
                               child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: Color(0xFF606060), width: 1)),
                                                   child: SizedBox(expand: ()))))
        return Positioned(left: ox + f.left * px, top: oy + f.top * px, width: w, height: h,
                          child: IgnorePointer(child: Transform(rotate: shape.rotation * .pi / 180,
                                                                child: Stack(clipBehavior: .none, children: kids))))
    }

    /// `crop`: a crop handle, black with a white rim as PowerPoint draws them.
    private func _handle(accent: Color, round: Bool = false, crop: Bool = false, shown: Double, cursor: MouseCursor,
                         onDown: @escaping (PointerDownEvent) -> Void) -> Widget {
        let box = DecoratedBox(
            decoration: BoxDecoration(color: crop ? Color(0xFF000000) : Color(0xFFFFFFFF),
                                      border: Border.all(color: crop ? Color(0xFFFFFFFF) : accent, width: 1.5),
                                      borderRadius: BorderRadius.all(Radius(circular: round ? 6 : 1))),
            child: SizedBox(expand: ()))
        return Listener(
            onPointerDown: onDown,
            onPointerMove: { [weak self] e in self?._pointerMove(e) },
            onPointerUp: { [weak self] e in self?._pointerUp(e) },
            behavior: .opaque,
            child: MouseRegion(cursor: cursor, child: Center(child: SizedBox(width: shown, height: shown, child: box))))
    }

    private var _marqueeRect: Rect? {
        let ends: (Offset, Offset)
        if case .marquee(let a, let b)? = _drag { ends = (a, b) } else if case .draw(_, let a, let b)? = _drag { ends = (a, b) } else { return nil }
        let (a, b) = ends
        return Rect.fromLTRB(min(a.dx, b.dx), min(a.dy, b.dy), max(a.dx, b.dx), max(a.dy, b.dy))
    }

    // MARK: Pointer

    private var _marqueeBase: [SlideShape] = []
    /// A finger held still on a shape (or the empty slide) opens the same menu a right click does: bumped at every press and
    /// release, so a stale timer finds it changed.
    private var _pressGeneration = 0
    private static let longPressDelay = 0.5

    private func _armLongPress(_ e: PointerDownEvent, on shape: SlideShape?) {
        _pressGeneration &+= 1
        guard e.kind == .touch, let menu = _w.onContextMenu else { return }
        let generation = _pressGeneration, at = e.position
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.longPressDelay) { [weak self] in
            guard let self, generation == self._pressGeneration else { return }
            switch self._drag {
            case .move(_, _, _, _, let moved)? where !moved: break
            case .marquee(let a, let b)? where shape == nil && a == b: break
            default: return
            }
            self._drag = nil
            self._pendingToggle = false
            self._guides = []
            if let shape {
                if !self.deck.isSelected(shape) { self.deck.selectWholeGroup(of: shape) }
            } else {
                self.deck.selectShapes([])
            }
            menu(at, shape)
        }
    }
    private var _pendingToggle = false
    /// Two fingers tapped together open the same menu a right click does (a finger held still is `_armLongPress`).
    private let _twoFinger = TouchMenuTrigger()
    private var _rightClickAt = 0.0
    private func _twoFingerMenu(_ at: Offset, on shape: SlideShape?) {
        guard let menu = _w.onContextMenu else { return }
        _pressGeneration &+= 1
        _drag = nil
        _pendingToggle = false
        _guides = []
        if let shape {
            if _w.active !== shape { FocusManager.instance.focusedNode?.unfocus(); _w.onEdit(nil) }
            if !deck.isSelected(shape) { deck.selectWholeGroup(of: shape) }
        } else {
            FocusManager.instance.focusedNode?.unfocus()
            _w.onEdit(nil)
            deck.selectShapes([])
        }
        menu(at, shape)
    }
    private var _additive: Bool { let m = _w.modifiers(); return deck.selectMultiple || m.contains(.shift) || m.contains(.control) || m.contains(.meta) }

    /// While the eyedropper is on, a click takes the colour under it for the fill or outline and does nothing else.
    private func _eyedrop(_ e: PointerDownEvent) -> Bool {
        guard let outline = deck.eyedropperFor else { return false }
        deck.eyedropperFor = nil
        deck.pickShapeColor(at: _slidePoint(e.position), outline: outline)
        return true
    }

    /// A shape chosen from the gallery waits for the drag (or click) that places it.
    private func _beginDraw(_ e: PointerDownEvent) -> Bool {
        guard let preset = deck.pendingInsert, e.buttons & kSecondaryMouseButton == 0 else { return false }
        FocusManager.instance.focusedNode?.unfocus()
        _w.onEdit(nil)
        let p = _slidePoint(e.position)
        _drag = .draw(preset: preset, start: p, now: p)
        return true
    }

    // MARK: Two-finger twist

    /// Where each finger on the canvas is (touch only), for the twist that turns the selected shape.
    private var _fingers: [Int: Offset] = [:]
    private var _twist: (shape: SlideShape, startAngle: Double, startRotation: Double, last: Double, total: Double, began: Bool)? = nil
    /// How far the fingers must turn before it is a twist and not a two-finger tap that wobbled.
    private static let twistStart = 5.0

    private func _trackFinger(_ e: PointerDownEvent) {
        if e.kind == .touch { _fingers[e.pointer] = e.position }
    }

    private func _fingerAngle() -> Double? {
        guard _fingers.count == 2 else { return nil }
        let two = _fingers.sorted { $0.key < $1.key }.map(\.value)
        return atan2(two[1].dy - two[0].dy, two[1].dx - two[0].dx) * 180 / .pi
    }

    /// A second finger landed: with one shape selected (not a line), the two fingers turning is a rotation of it.
    private func _beginTwist() {
        guard _twist == nil, let angle = _fingerAngle(), deck.selection.count == 1, let shape = deck.selection.first,
              shape.preset?.isLine != true, !shape.isElbow else { return }
        // The first finger may have begun a move: it ends where it is.
        if case .move(_, _, _, _, let moved)? = _drag, moved { deck.endFrameEdit() }
        _drag = nil
        _pressGeneration &+= 1
        _twist = (shape, angle, shape.rotation, angle, 0, false)
    }

    /// The fingers moved: turn the shape by the angle between them. True while a twist is on, so the move drags nothing.
    private func _updateTwist() -> Bool {
        guard var t = _twist, let angle = _fingerAngle() else { return _twist != nil }
        var step = angle - t.last
        if step > 180 { step -= 360 } else if step < -180 { step += 360 }
        t.last = angle
        t.total += step
        if !t.began {
            guard abs(t.total) > Self.twistStart else { _twist = t; return true }
            t.began = true
            _twoFinger.cancel()
            deck.beginFrameEdit()
        }
        var r = t.startRotation + t.total
        for target in stride(from: -360.0, through: 360, by: 90) where abs(r - target) < 3 { r = target }
        deck.setRotationLive(t.shape, r)
        _twist = t
        return true
    }

    private func _backdropDown(_ e: PointerDownEvent) {
        if _eyedrop(e) { return }
        if e.kind == .touch { _touchSeen = true }
        _trackFinger(e)
        if _twoFinger.down(e, hold: false, fire: { [weak self] p in self?._twoFingerMenu(p, on: nil) }) { _beginTwist(); return }
        if _beginDraw(e) { return }
        if e.buttons & kSecondaryMouseButton != 0, let menu = _w.onContextMenu {
            FocusManager.instance.focusedNode?.unfocus()
            _w.onEdit(nil)
            deck.selectShapes([])
            menu(e.position, nil)
            return
        }
        FocusManager.instance.focusedNode?.unfocus()
        _w.onEdit(nil)
        // With Shift or Ctrl held the marquee adds to what is selected.
        _marqueeBase = _additive ? deck.selection : []
        deck.selectShapes(_marqueeBase)
        let p = _slidePoint(e.position)
        _drag = .marquee(start: p, now: p)
        _armLongPress(e, on: nil)
    }

    private func _shapeDown(_ shape: SlideShape, _ e: PointerDownEvent) {
        if _eyedrop(e) { return }
        if e.kind == .touch { _touchSeen = true }
        _trackFinger(e)
        if _twoFinger.down(e, hold: false, fire: { [weak self] p in self?._twoFingerMenu(p, on: shape) }) { _beginTwist(); return }
        if _beginDraw(e) { return }
        Self._log("down on shape \(shape.id) at \(e.position)")
        if e.buttons & kSecondaryMouseButton != 0, let menu = _w.onContextMenu {
            if _w.active !== shape {
                FocusManager.instance.focusedNode?.unfocus()
                _w.onEdit(nil)
            }
            if !deck.isSelected(shape) { deck.selectWholeGroup(of: shape) }
            menu(e.position, shape)
            return
        }
        let wasSelected = deck.isSelected(shape)
        if _w.active !== shape {
            // Leaves any text being edited (a box's or the notes') and
            // gives the keyboard back to the deck: Delete, arrows, ⌘D.
            FocusManager.instance.focusedNode?.unfocus()
            _w.onEdit(nil)
        }
        _pendingToggle = false
        if _additive {
            // Shift/Ctrl+click adds or removes. A shape already selected may be
            // the start of a Shift (straight) or Ctrl (copy) drag, so it is
            // removed on release if the pointer never moved.
            if wasSelected { _pendingToggle = true } else { deck.toggleSelected(shape) }
        } else if !wasSelected { deck.selectWholeGroup(of: shape) }
        if deck.cropping === shape, !_additive {
            _drag = .pan(shape: shape, start: _slidePoint(e.position), crop: shape.crop, moved: false)
            return
        }
        let frames = deck.selection.map { ($0, $0.frame) }
        _drag = .move(start: _slidePoint(e.position), frames: frames, shape: shape,
                      wasSelected: wasSelected, moved: false)
        _armLongPress(e, on: shape)
    }

    private static let _debug = ProcessInfo.processInfo.environment["STARLING_SLIDES_DEBUG"] != nil
    private static func _log(_ m: String) {
        // Not in the browser: the web link has no FileHandle, and whether
        // this body reaches the linker there depends on what calls it.
        #if !os(WASI)
        guard _debug else { return }
        let line = m + "\n"
        FileHandle.standardError.write(Data(line.utf8))
        #endif
    }

    private func _pointerMove(_ e: PointerMoveEvent) {
        _twoFinger.moved(e.pointer, e.position)
        if _fingers[e.pointer] != nil {
            _fingers[e.pointer] = e.position
            if _updateTwist() { return }
        }
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
            var frames = frames
            let m = _w.modifiers()
            if !moved {
                guard abs(dx) * _px > 3 || abs(dy) * _px > 3 else { return }
                moved = true
                if m.contains(.control) || m.contains(.meta), !m.contains(.shift) {
                    // Ctrl+drag drags a copy and leaves the original where it was.
                    deck.duplicateSelection(offset: 0)
                    frames = deck.selection.map { ($0, $0.frame) }
                } else {
                    deck.beginFrameEdit()
                }
            }
            if m.contains(.shift) {
                // Shift keeps the move on one axis: the one dragged furthest.
                if abs(dx) >= abs(dy) { dy = 0 } else { dx = 0 }
            }
            if m.contains(.alt) {
                _guides = []
            } else {
                let snapped = _snapMove(frames.map(\.1), dx: dx, dy: dy)
                // A locked axis stays locked.
                if !m.contains(.shift) || dx != 0 { dx = snapped.dx }
                if !m.contains(.shift) || dy != 0 { dy = snapped.dy }
            }
            _drag = .move(start: start, frames: frames, shape: shape, wasSelected: wasSelected, moved: moved)
            deck.setFramesLive(frames.map { ($0.0, $0.1.shift(Offset(dx, dy))) })
        case .pan(let shape, let start, let crop, var moved):
            let dx = p.dx - start.dx, dy = p.dy - start.dy
            if !moved {
                guard abs(dx) * _px > 3 || abs(dy) * _px > 3 else { return }
                moved = true
                deck.beginFrameEdit()
                _drag = .pan(shape: shape, start: start, crop: crop, moved: true)
            }
            // The drag in the picture's own axes (it may be turned).
            let a = -shape.rotation * .pi / 180
            deck.setCropPanLive(shape, crop0: crop, by: Offset(dx * cos(a) - dy * sin(a), dx * sin(a) + dy * cos(a)))
        case .crop(let shape, let handle, let start, let frame, let crop):
            let r = Self.resizedFrame(frame, rotation: shape.rotation, handle: handle, delta: Offset(p.dx - start.dx, p.dy - start.dy))
            deck.setCropLive(shape, crop0: crop, frame0: frame, frame: r, handle: handle)
        case .resize(let shape, let handle, let start, let frame):
            let r = _resized(shape, frame, handle: handle, delta: Offset(p.dx - start.dx, p.dy - start.dy))
            if shape.isElbow {
                let m = _w.modifiers()
                deck.dragElbowEnd(shape, handle: handle, to: p, snap: !m.contains(.shift) && !m.contains(.alt))
            } else if shape.preset?.isLine == true {
                let m = _w.modifiers()
                deck.dragLineEnd(shape, handle: handle, frame: r, snap: !m.contains(.shift) && !m.contains(.alt))
            } else {
                deck.setFramesLive([(shape, r)])
            }
        case .resizeAll(let lead, let handle, let start, let frames):
            guard let leadFrame = frames.first(where: { $0.0 === lead })?.1 else { break }
            let r = _resized(lead, leadFrame, handle: handle, delta: Offset(p.dx - start.dx, p.dy - start.dy))
            deck.setFramesLive(Self.scaledTogether(frames, lead: lead, leadFrame: leadFrame, to: r, handle: handle,
                                                    fromCentre: _w.modifiers().contains(.control)))
        case .elbowRun(let shape, let key, let alongWidth):
            deck.setElbowRunLive(shape, key, alongWidth: alongWidth, to: p)
        case .adjust(let shape, let handle):
            deck.setAdjustHandleLive(shape, handle, to: p)
        case .rotate(let shape, let startAngle, let startRotation):
            let c = shape.frame.center
            let angle = atan2(p.dy - c.dy, p.dx - c.dx) * 180 / .pi
            var r = startRotation + angle - startAngle
            // Settle on the right angles when near them.
            let m = _w.modifiers()
            if m.contains(.shift) {
                r = (r / 15).rounded() * 15      // Shift turns in steps of 15°
            } else if !m.contains(.alt) {
                for target in stride(from: -360.0, through: 360, by: 90) where abs(r - target) < 3 { r = target }
            }
            deck.setRotationLive(shape, r)
        case .marquee(let start, _):
            _drag = .marquee(start: start, now: p)
            setState {}
        case .draw(let preset, let start, _):
            _drag = .draw(preset: preset, start: start, now: p)
            setState {}
        case .guide(let i, _):
            guard deck.grid.guides.indices.contains(i) else { return }
            let v = deck.grid.guides[i].vertical ? p.dx : p.dy
            // A guide moves in steps of the grid unless Alt is held, as PowerPoint's does.
            _drag = .guide(index: i, at: _w.modifiers().contains(.alt) ? v : deck.grid.snapped(v))
            setState {}
        }
    }

    private func _pointerUp(_ e: PointerUpEvent) {
        Self._log("up \(e.position)")
        _twoFinger.up(e.pointer)
        _fingers[e.pointer] = nil
        if let twist = _twist {
            _twist = nil
            if twist.began { deck.endFrameEdit() }
            return
        }
        _pressGeneration &+= 1
        _dragTo(e.position)
        guard let drag = _drag else { return }
        _drag = nil
        _guides = []
        switch drag {
        case .move(_, _, let shape, let wasSelected, let moved):
            if moved {
                deck.endFrameEdit()
            } else if _pendingToggle {
                deck.toggleSelected(shape)
            } else if wasSelected, !_additive, shape.group != nil, deck.selection.count > 1,
                      deck.selection.count == deck.groupMembers(of: shape).count {
                // A second click on a selected group picks the member.
                deck.selectShapes([shape])
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
        case .resize, .resizeAll, .crop, .rotate, .elbowRun, .adjust:
            deck.endFrameEdit()
        case .pan(_, _, _, let moved):
            if moved { deck.endFrameEdit() }
        case .draw(let preset, let a, let b):
            let m = _w.modifiers()
            deck.placeInsert(preset, from: a, to: b, keepProportions: m.contains(.shift))
            setState {}
        case .guide(let i, let at):
            var g = deck.grid
            guard g.guides.indices.contains(i) else { break }
            let extent = g.guides[i].vertical ? deck.slideSize.width : deck.slideSize.height
            // Dragged off the slide: the guide is deleted.
            if at < 0 || at > extent { g.guides.remove(at: i) } else { g.guides[i].at = at }
            if g != deck.grid { deck.setGrid(g) }
        case .marquee(let a, let b):
            let box = Rect.fromLTRB(min(a.dx, b.dx), min(a.dy, b.dy), max(a.dx, b.dx), max(a.dy, b.dy))
            if box.width > 2 || box.height > 2 {
                // PowerPoint selects what the marquee wholly contains.
                deck.selectShapes(_marqueeBase + deck.currentSlide.shapes.filter { s in
                    box.contains(s.frame.topLeft) && box.contains(s.frame.bottomRight)
                        && !_marqueeBase.contains { $0 === s }
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
            // A line's two ends move freely; Shift holds the angle to a multiple of 45 degrees.
            if _w.modifiers().contains(.shift) { return Self.lineEndSnapped(frame, handle: handle, delta: delta) }
            return handle == 0
                ? Rect.fromLTRB(frame.left + delta.dx, frame.top + delta.dy, frame.right, frame.bottom)
                : Rect.fromLTRB(frame.left, frame.top, frame.right + delta.dx, frame.bottom + delta.dy)
        }
        let m = _w.modifiers()
        let r = Self.resizedFrame(frame, rotation: shape.rotation, handle: handle, delta: delta,
                                  keepAspect: m.contains(.shift) != (shape.aspectLock == true), fromCentre: m.contains(.control))
        // Alt turns snapping off; a resize about the centre or by aspect has no edge to snap.
        guard shape.rotation == 0, !m.contains(.alt), !m.contains(.shift), shape.aspectLock != true, !m.contains(.control) else {
            _guides = []
            return r
        }
        return _snapResize(r, handle: handle)
    }

    /// A line with its end `handle` (0 = top left, 1 = bottom right) dragged by `delta`, the other end
    /// fixed, the angle turned to the nearest multiple of 45 degrees and the length kept.
    static func lineEndSnapped(_ frame: Rect, handle: Int, delta: Offset) -> Rect {
        let anchor = handle == 0 ? frame.bottomRight : frame.topLeft
        let end = handle == 0 ? Offset(frame.left + delta.dx, frame.top + delta.dy)
                              : Offset(frame.right + delta.dx, frame.bottom + delta.dy)
        let vx = end.dx - anchor.dx, vy = end.dy - anchor.dy
        let len = (vx * vx + vy * vy).squareRoot()
        guard len > 0 else { return frame }
        let step = Double.pi / 4
        let a = (atan2(vy, vx) / step).rounded() * step
        let e = Offset(anchor.dx + len * cos(a), anchor.dy + len * sin(a))
        return handle == 0 ? Rect.fromLTRB(e.dx, e.dy, frame.right, frame.bottom)
                           : Rect.fromLTRB(frame.left, frame.top, e.dx, e.dy)
    }

    /// A multi-selection resized from `handle` of `lead`, whose frame went from `leadFrame` to `to`: every other shape
    /// takes the same width and height factors, about its own handle opposite `handle` (its centre when the lead was
    /// resized about its centre), turned by its own rotation. A line scales its box the same way.
    static func scaledTogether(_ frames: [(SlideShape, Rect)], lead: SlideShape, leadFrame: Rect, to r: Rect,
                               handle: Int, fromCentre aboutCentre: Bool = false) -> [(SlideShape, Rect)] {
        let kx = leadFrame.width > 0 ? r.width / leadFrame.width : 1
        let ky = leadFrame.height > 0 ? r.height / leadFrame.height : 1
        return frames.map { shape, f in
            if shape === lead { return (shape, r) }
            let isLine = shape.preset?.isLine == true || shape.isElbow
            let w = isLine ? f.width * kx : max(4, f.width * kx)
            let h = isLine ? f.height * ky : max(4, f.height * ky)
            if aboutCentre { return (shape, Rect.fromLTWH(f.center.dx - w / 2, f.center.dy - h / 2, w, h)) }
            let (hx, hy) = handleUnits[handle]
            let ax = 1 - hx, ay = 1 - hy
            let rot = shape.rotation
            let before = rotate(Offset((ax - 0.5) * f.width, (ay - 0.5) * f.height), rot)
            let anchor = Offset(f.center.dx + before.dx, f.center.dy + before.dy)
            let after = rotate(Offset((ax - 0.5) * w, (ay - 0.5) * h), rot)
            let c = Offset(anchor.dx - after.dx, anchor.dy - after.dy)
            return (shape, Rect.fromLTWH(c.dx - w / 2, c.dy - h / 2, w, h))
        }
    }

    /// Pure resize geometry, for tests: the opposite handle stays put.
    /// `keepAspect` (Shift, corner handles) holds the shape's proportions;
    /// `fromCentre` (Ctrl) grows it both ways about its centre.
    static func resizedFrame(_ frame: Rect, rotation rot: Double, handle: Int, delta: Offset,
                             keepAspect: Bool = false, fromCentre: Bool = false) -> Rect {
        let (hx, hy) = handleUnits[handle]
        var d = rotate(delta, -rot)
        var sx = hx == 1 ? 1.0 : hx == 0 ? -1.0 : 0
        var sy = hy == 1 ? 1.0 : hy == 0 ? -1.0 : 0
        if fromCentre { d = Offset(d.dx * 2, d.dy * 2) }
        if keepAspect, frame.width > 0, frame.height > 0 {
            if sx != 0, sy != 0 {
                let k = max((frame.width + d.dx * sx) / frame.width, (frame.height + d.dy * sy) / frame.height)
                d = Offset(frame.width * (k - 1) * sx, frame.height * (k - 1) * sy)
            } else if sx != 0 {
                // An edge handle with Shift grows the other side too, about the shape's middle.
                let k = (frame.width + d.dx * sx) / frame.width
                d = Offset(d.dx, frame.height * (k - 1)); sy = 1
            } else if sy != 0 {
                let k = (frame.height + d.dy * sy) / frame.height
                d = Offset(frame.width * (k - 1), d.dy); sx = 1
            }
        }
        if fromCentre {
            let w = max(4, frame.width + d.dx * sx), h = max(4, frame.height + d.dy * sy)
            let c = frame.center
            return Rect.fromLTWH(c.dx - w / 2, c.dy - h / 2, w, h)
        }
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
        var xs: [Double] = [], ys: [Double] = []
        // With smart guides and snapping to objects both off, only the grid and the drawing guides catch a shape.
        let objects = deck.smartGuides || deck.grid.snapToObjects
        if objects {
            xs = [0, deck.slideSize.width / 2, deck.slideSize.width]
            ys = [0, deck.slideSize.height / 2, deck.slideSize.height]
        }
        for s in deck.currentSlide.shapes where objects && !excluding.contains(where: { $0 === s }) {
            let f = s.frame
            xs += [f.left, f.center.dx, f.right]
            ys += [f.top, f.center.dy, f.bottom]
        }
        // Shown drawing guides catch edges and centres too.
        if deck.grid.showGuides {
            for g in deck.grid.guides { if g.vertical { xs.append(g.at) } else { ys.append(g.at) } }
        }
        return (xs, ys)
    }

    /// How far `edge` moves to sit on the grid (0 when snap to grid is off).
    private func _gridShift(_ edge: Double) -> Double {
        deck.grid.snapToGrid ? deck.grid.snapped(edge) - edge : 0
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
        } else {
            // No line caught it: the top-left corner settles on the grid, as in PowerPoint.
            outX += _gridShift(box.left)
        }
        if let (target, edge) = _nearest([box.top, box.center.dy, box.bottom], ys) {
            outY += target - edge
            guides.append(SlideGuide(vertical: false, at: target))
        } else {
            outY += _gridShift(box.top)
        }
        _guides = deck.smartGuides ? guides : []
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
        } else if hx == 1 {
            out = Rect.fromLTRB(out.left, out.top, out.right + _gridShift(out.right), out.bottom)
        } else if hx == 0 {
            out = Rect.fromLTRB(out.left + _gridShift(out.left), out.top, out.right, out.bottom)
        }
        if hy != 0.5, let (target, edge) = _nearest([hy == 1 ? r.bottom : r.top], ys) {
            out = hy == 1 ? Rect.fromLTRB(out.left, out.top, out.right, out.bottom + target - edge)
                          : Rect.fromLTRB(out.left, out.top + target - edge, out.right, out.bottom)
            guides.append(SlideGuide(vertical: false, at: target))
        } else if hy == 1 {
            out = Rect.fromLTRB(out.left, out.top, out.right, out.bottom + _gridShift(out.bottom))
        } else if hy == 0 {
            out = Rect.fromLTRB(out.left, out.top + _gridShift(out.top), out.right, out.bottom)
        }
        _guides = deck.smartGuides ? guides : []
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
/// The click numbers beside animated shapes.
private final class _BadgePainter: CustomPainter {
    let slide: Slide
    let selection: [SlideShape]
    let ox: Double, oy: Double, px: Double
    let accent: Color
    let revision: Int
    let cache: SlideTextCache

    init(slide: Slide, selection: [SlideShape], ox: Double, oy: Double, px: Double, accent: Color, revision: Int,
         cache: SlideTextCache) {
        self.cache = cache
        self.slide = slide
        self.selection = selection
        self.ox = ox; self.oy = oy; self.px = px
        self.accent = accent
        self.revision = revision
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let numbers = AnimationPlan.clickNumbers(slide.animations)
        var stacked: [Int: Int] = [:]
        for (i, a) in slide.animations.enumerated() {
            guard let shape = slide.shapes.first(where: { $0.id == a.shapeId }) else { continue }
            let k = stacked[shape.id, default: 0]
            stacked[shape.id] = k + 1
            let selected = selection.contains { $0 === shape }
            let tp = TextPainter(text: TextSpan(text: "\(numbers[i])", style: Flutter.TextStyle(
                color: selected ? Color(0xFFFFFFFF) : Color(0xFF3B3B3B), fontSize: 10, fontFamily: OfficeFonts.sans)),
                textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: 100)
            let w = max(16, tp.width + 8), h = 15.0
            let x = ox + min(shape.frame.left, shape.frame.right) * px - w - 3
            var y = oy + min(shape.frame.top, shape.frame.bottom) * px + Double(k) * (h + 2)
            // A paragraph's badge sits beside that paragraph.
            if let p = a.paragraph, let layout = cache.layout(shape, pxPerPt: px), p < layout.count {
                let g = layout.geometry(p)
                y = oy + shape.frame.top * px + cache.textTop(shape, pxPerPt: px) + g.textTop + 2
            }
            let fill = Paint()
            fill.style = .fill
            fill.isAntiAlias = true
            fill.color = selected ? accent : Color(0xFFE4E4E4)
            canvas.drawRRect(RRect(fromRectAndRadius: Rect.fromLTWH(x, y, w, h), Radius(circular: 2)), fill)
            let edge = Paint()
            edge.style = .stroke
            edge.strokeWidth = 1
            edge.color = selected ? accent : Color(0xFF9A9A9A)
            canvas.drawRRect(RRect(fromRectAndRadius: Rect.fromLTWH(x + 0.5, y + 0.5, w - 1, h - 1), Radius(circular: 2)), edge)
            tp.paint(canvas, Offset(x + (w - tp.width) / 2, y + (h - tp.height) / 2))
            tp.dispose()
        }
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? _BadgePainter else { return true }
        return old.revision != revision || old.slide !== slide || old.px != px || old.ox != ox || old.oy != oy
            || old.selection.map(ObjectIdentifier.init) != selection.map(ObjectIdentifier.init)
    }
}

private final class _ChromePainter: CustomPainter {
    let selection: [SlideShape]
    let active: SlideShape?
    let guides: [SlideGuide]
    let marquee: Rect?
    let slideSize: Size
    let ox: Double, oy: Double, px: Double
    let accent: Color
    let stalk: Double

    init(selection: [SlideShape], active: SlideShape?, guides: [SlideGuide], marquee: Rect?, slideSize: Size,
         ox: Double, oy: Double, px: Double, accent: Color, stalk: Double = 16) {
        self.stalk = stalk
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
                    canvas.drawLine(Offset(r.center.dx, r.top), Offset(r.center.dx, r.top - stalk), line)
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

/// View > Show on the canvas: gridlines every `spacing` points (0: none), dashed drawing guides, and the rulers along
/// the top and left edges, in inches counted out from the slide's centre as PowerPoint's are.
final class SlideGridPainter: CustomPainter {
    let spacing: Double
    let guides: [DrawingGuide]
    let ruler: Bool
    let slideSize: Size
    let ox: Double, oy: Double, px: Double
    let dark: Bool

    init(spacing: Double, guides: [DrawingGuide], ruler: Bool, slideSize: Size, ox: Double, oy: Double, px: Double,
         dark: Bool) {
        self.spacing = spacing; self.guides = guides; self.ruler = ruler; self.slideSize = slideSize
        self.ox = ox; self.oy = oy; self.px = px; self.dark = dark
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let w = slideSize.width * px, h = slideSize.height * px
        if spacing > 0 {
            // A line every grid step from the centre out, thinned so lines are never closer than 6 px on screen.
            var step = spacing
            while step * px < 6 { step *= 2 }
            let dot = Paint()
            dot.style = .fill
            dot.color = Color(0x80808080)
            let cx = slideSize.width / 2, cy = slideSize.height / 2
            func lines(_ centre: Double, _ extent: Double) -> [Double] {
                var out: [Double] = []
                var k = (-(centre / step)).rounded(.up)
                while centre + k * step <= extent { out.append(centre + k * step); k += 1 }
                return out
            }
            // PowerPoint's gridlines are dotted: a dot every 2 px along each line.
            for x in lines(cx, slideSize.width) {
                var y = 0.0
                while y < h { canvas.drawRect(Rect.fromLTWH(ox + x * px, oy + y, 1, 1), dot); y += 3 }
            }
            for yv in lines(cy, slideSize.height) {
                var x = 0.0
                while x < w { canvas.drawRect(Rect.fromLTWH(ox + x, oy + yv * px, 1, 1), dot); x += 3 }
            }
        }
        if !guides.isEmpty {
            let line = Paint()
            line.style = .stroke
            line.strokeWidth = 1
            line.color = dark ? Color(0xFFBDBDBD) : Color(0xFF6E6E6E)
            for g in guides {
                // Dashed, 4 on and 3 off.
                let length = g.vertical ? h : w
                var t = 0.0
                while t < length {
                    let e = min(length, t + 4)
                    if g.vertical {
                        canvas.drawLine(Offset(ox + g.at * px, oy + t), Offset(ox + g.at * px, oy + e), line)
                    } else {
                        canvas.drawLine(Offset(ox + t, oy + g.at * px), Offset(ox + e, oy + g.at * px), line)
                    }
                    t += 7
                }
            }
        }
        if ruler { _rulers(canvas, size) }
    }

    private func _rulers(_ canvas: any Canvas, _ size: Size) {
        let band = 18.0
        let bg = Paint(); bg.style = .fill; bg.color = dark ? Color(0xFF2B2B2B) : Color(0xFFF3F3F3)
        let face = Paint(); face.style = .fill; face.color = dark ? Color(0xFF3C3C3C) : Color(0xFFFFFFFF)
        let tick = Paint(); tick.style = .stroke; tick.strokeWidth = 1; tick.color = dark ? Color(0xFFAAAAAA) : Color(0xFF707070)
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, band), bg)
        canvas.drawRect(Rect.fromLTWH(0, 0, band, size.height), bg)
        // The slide's extent shows white on each ruler.
        let w = slideSize.width * px, h = slideSize.height * px
        canvas.drawRect(Rect.fromLTWH(max(band, ox), 2, max(0, min(ox + w, size.width) - max(band, ox)), band - 4), face)
        canvas.drawRect(Rect.fromLTWH(2, max(band, oy), band - 4, max(0, min(oy + h, size.height) - max(band, oy))), face)
        let inch = 72 * px
        guard inch > 8 else { return }
        let cx = ox + w / 2, cy = oy + h / 2
        let color = dark ? Color(0xFFCCCCCC) : Color(0xFF444444)
        // Eighths of an inch: an inch tick is long and numbered, a half medium, the rest short.
        func marks(_ centre: Double, _ from: Double, _ to: Double, _ draw: (Double, Int) -> Void) {
            var k = ((from - centre) / (inch / 8)).rounded(.up)
            while centre + k * inch / 8 <= to { draw(centre + k * inch / 8, Int(k)); k += 1 }
        }
        marks(cx, band, size.width) { x, k in
            let len = k % 8 == 0 ? 0.0 : k % 4 == 0 ? 6 : 3
            if k % 8 == 0 {
                if k != 0 { _label(canvas, "\(abs(k / 8))", Offset(x, band / 2), color) }
            } else {
                canvas.drawLine(Offset(x, band / 2 - len / 2), Offset(x, band / 2 + len / 2), tick)
            }
        }
        marks(cy, band, size.height) { y, k in
            let len = k % 8 == 0 ? 0.0 : k % 4 == 0 ? 6 : 3
            if k % 8 == 0 {
                if k != 0 { _label(canvas, "\(abs(k / 8))", Offset(band / 2, y), color) }
            } else {
                canvas.drawLine(Offset(band / 2 - len / 2, y), Offset(band / 2 + len / 2, y), tick)
            }
        }
        canvas.drawRect(Rect.fromLTWH(0, 0, band, band), bg)
    }

    private func _label(_ canvas: any Canvas, _ text: String, _ centre: Offset, _ color: Color) {
        let tp = TextPainter(text: TextSpan(text: text, style: Flutter.TextStyle(color: color, fontSize: 9,
                                                                               fontFamily: OfficeFonts.sans)),
                             textDirection: .ltr)
        tp.layout(minWidth: 0, maxWidth: 40)
        tp.paint(canvas, Offset(centre.dx - tp.width / 2, centre.dy - tp.height / 2))
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool { true }
}

/// Crop mode's cut-away bands: the whole picture drawn over `full` (the frame's own part left to the shape), seen
/// through a white veil, so what the crop removes still shows and the handles can bring it back.
final class CropGhostPainter: CustomPainter {
    let image: Image?
    let full: Rect
    let bands: [Rect]
    let revision: Int

    init(image: Image?, full: Rect, bands: [Rect], revision: Int) {
        self.image = image; self.full = full; self.bands = bands; self.revision = revision
        super.init()
    }

    /// How much of the cut-away picture shows through the veil.
    static let opacity = 0.45

    override func paint(_ canvas: any Canvas, _ size: Size) {
        for band in bands {
            canvas.save()
            canvas.clipRect(band)
            if let image, image.width > 0, image.height > 0 {
                let p = SlidePainter.imagePaint(alpha: Self.opacity, duotone: nil)
                canvas.drawImageRect(image, Rect.fromLTWH(0, 0, Double(image.width), Double(image.height)), full, p)
            } else {
                let p = Paint(); p.color = Color(0x59808080)
                canvas.drawRect(band, p)
            }
            canvas.restore()
        }
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? CropGhostPainter else { return true }
        return old.image !== image || old.full != full || old.bands != bands || old.revision != revision
    }
}
