// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The editing canvas: the current slide, zoomed to fit the space it is
// given, with a live RichEditable over every text body. Shape fills and the
// background come from SlidePainter; text is the editors' own paint, so
// what you type is exactly what the thumbnail and the show draw (both lay
// out through the same RichLayout).

import Flutter
import FlutterSwiftBridge
import Foundation

final class SlideCanvas: StatefulWidget {
    let deck: DeckController
    let cache: SlideTextCache
    /// The shape whose text is being edited, if any.
    let active: SlideShape?
    let onActivate: (SlideShape?) -> Void
    let onShortcut: (KeyData, KeyModifiers) -> Bool
    let spellChecker: RichSpellChecker?

    init(key: (any Key)? = nil, deck: DeckController, cache: SlideTextCache, active: SlideShape?,
         onActivate: @escaping (SlideShape?) -> Void,
         onShortcut: @escaping (KeyData, KeyModifiers) -> Bool,
         spellChecker: RichSpellChecker?) {
        self.deck = deck
        self.cache = cache
        self.active = active
        self.onActivate = onActivate
        self.onShortcut = onShortcut
        self.spellChecker = spellChecker
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { SlideCanvasState() }
}

final class SlideCanvasState: State<StatefulWidget> {
    private var _area = Size.zero
    private var _focus: [Int: FocusNode] = [:]

    private var _w: SlideCanvas { widget as! SlideCanvas }

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

    /// Device pixels per point at the current fit.
    private func _pxPerPt(_ slide: Size) -> Double {
        let margin = 32.0
        guard _area.width > margin * 2, _area.height > margin * 2 else { return 0 }
        return min((_area.width - margin * 2) / slide.width, (_area.height - margin * 2) / slide.height)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let dark = fluent.brightness == .dark
        let backdrop = dark ? Color(0xFF202020) : Color(0xFFE6E6E6)
        let deck = _w.deck
        let slide = deck.currentSlide
        let px = _pxPerPt(deck.slideSize)
        var layers: [Widget] = [
            // A click on the backdrop or on bare slide ends text editing.
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: GestureDetector(
                onTap: { [weak self] in
                    FocusManager.instance.focusedNode?.unfocus()
                    self?._w.onActivate(nil)
                },
                child: ColoredBox(color: backdrop, child: SizedBox(expand: ())))),
        ]
        if px > 0 {
            let w = (deck.slideSize.width * px).rounded()
            let h = (deck.slideSize.height * px).rounded()
            let ox = ((_area.width - w) / 2).rounded()
            let oy = ((_area.height - h) / 2).rounded()
            // Shadow, then the slide's background and shape fills.
            layers.append(Positioned(left: ox - 1, top: oy + 1, width: w + 2, height: h + 2, child: IgnorePointer(
                child: ColoredBox(color: Color(0x33000000), child: SizedBox(expand: ())))))
            layers.append(Positioned(left: ox, top: oy, width: w, height: h, child: IgnorePointer(child: CustomPaint(
                painter: SlidePainter(slide: slide, theme: deck.theme, slideSize: deck.slideSize,
                                      revision: deck.revision, cache: _w.cache, shapesOnly: true),
                child: SizedBox(expand: ())))))
            for shape in slide.shapes {
                guard shape.text != nil else { continue }
                layers.append(_textShape(shape, ox: ox, oy: oy, px: px, fluent: fluent))
            }
        }
        return SizeReporter(onSize: { [weak self] size in
            guard let self, self.mounted, size != self._area else { return }
            self.setState { self._area = size }
        }, child: Stack(children: layers))
    }

    private func _textShape(_ shape: SlideShape, ox: Double, oy: Double, px: Double,
                            fluent: FluentThemeData) -> Widget {
        guard let controller = shape.text, let theme = shape.textTheme else {
            return SizedBox(width: 0, height: 0, child: nil)
        }
        let f = shape.frame
        let editing = _w.active === shape
        let empty = shape.isEmptyText
        let textTop = _w.cache.textTop(shape, pxPerPt: px)
        let pad = EdgeInsets(left: shape.insets.left * px, top: max(0, textTop),
                             right: shape.insets.right * px, bottom: shape.insets.bottom * px)
        // The same three children every build — outline, prompt, editor —
        // whatever is shown. A Stack whose child list changes shape when
        // editing starts remounts the editor under the click: its state is
        // rebuilt mid-gesture and the typing it takes never paints.
        var stack: [Widget] = []
        // Placeholders show their outline (dashed in PowerPoint; a hairline
        // here) while empty or being edited.
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        let outlined = editing || (empty && shape.role != nil)
        stack.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(
                color: !outlined ? Color(0x00000000) : editing ? accent : Color(0xFFA0A0A0),
                width: editing ? 1.5 : 1)),
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
                self._w.onActivate(shape)
            },
            behavior: .translucent,
            child: RichEditable(
                key: ValueKey(shape.id),
                controller: controller, theme: theme, padding: pad,
                focusNode: focusNode(for: shape), autofocus: false,
                backgroundColor: nil, zoom: px / theme.pixelsPerPoint,
                onShortcut: _w.onShortcut,
                spellChecker: _w.spellChecker))))
        return Positioned(left: ox + f.left * px, top: oy + f.top * px,
                          width: f.width * px, height: f.height * px,
                          child: Stack(children: stack))
    }
}
