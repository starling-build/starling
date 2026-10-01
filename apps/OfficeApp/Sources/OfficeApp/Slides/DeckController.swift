// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - Snapshots (undo)

/// Everything a shape is, as a value: what undo stores and restores.
struct ShapeState: Equatable {
    var id: Int
    var name: String
    var kind: ShapeKind
    var frame: Rect
    var rotation: Double
    var fill: Color?
    var outline: Color?
    var outlineWidth: Double
    var anchor: TextAnchor
    var insets: EdgeInsets
    var prompt: String?
    var text: RichDocument?
    var font: String?
    var size: Double
    var color: Color
    var listIndent: Double
}

struct SlideState: Equatable {
    var id: Int
    var layout: SlideLayoutKind
    var hidden: Bool
    var notes: RichDocument
    var shapes: [ShapeState]
}

struct DeckState: Equatable {
    var slides: [SlideState]
    var current: Int
    var slideSize: Size
}

/// Every change to a deck goes through here. Listeners hear about slide
/// edits and about typing in any text body (thumbnails and anchored text
/// both follow the words), and `revision` moves on each.
///
/// Undo is by snapshot: each edit pushes the deck as it was. Text typed in
/// a body has its own undo inside the body's controller while it is being
/// edited; when editing ends (or any deck edit interrupts it) the whole
/// session becomes one deck step, so ⌘Z after leaving a box takes its
/// typing back as PowerPoint does.
final class DeckController: ChangeNotifier {
    private(set) var slides: [Slide] = []
    private(set) var current = 0
    /// The slide in points: 16:9 Widescreen by default, PowerPoint's own
    /// default since 2013 (13.333 x 7.5 in).
    private(set) var slideSize = Size(960, 540)
    var theme = DeckTheme()
    private(set) var revision = 0
    /// Shapes selected on the current slide, in selection order.
    private(set) var selection: [SlideShape] = []
    private var _nextId = 1

    private var _undo: [DeckState] = []
    private var _redo: [DeckState] = []
    private var _session: (state: DeckState, revisions: [ObjectIdentifier: Int])? = nil
    private var _sessionWanted = false
    private static let _undoLimit = 100

    override init() {
        super.init()
        newDeck()
    }

    var currentSlide: Slide { slides[current] }
    var canUndo: Bool { !_undo.isEmpty || _sessionChanged }
    var canRedo: Bool { !_redo.isEmpty }

    // MARK: Deck

    /// A fresh deck: one title slide, and no history.
    func newDeck() {
        for slide in slides { _unwatch(slide) }
        slides = [_makeSlide(.titleSlide)]
        current = 0
        selection = []
        _undo = []
        _redo = []
        _session = nil
        _changed()
    }

    func setSlideSize(_ size: Size) {
        guard size != slideSize else { return }
        _checkpoint()
        let sx = size.width / slideSize.width
        let sy = size.height / slideSize.height
        for slide in slides {
            for shape in slide.shapes {
                let f = shape.frame
                shape.frame = Rect.fromLTWH(f.left * sx, f.top * sy, f.width * sx, f.height * sy)
            }
        }
        slideSize = size
        _changed()
    }

    // MARK: Slides

    func select(_ index: Int) {
        let i = max(0, min(slides.count - 1, index))
        guard i != current else { return }
        current = i
        selection = []
        _changed()
    }

    /// A new slide after the current one. With no layout given it follows
    /// PowerPoint: after the title slide comes Title and Content, otherwise
    /// the current slide's layout repeats.
    @discardableResult
    func addSlide(_ layout: SlideLayoutKind? = nil) -> Slide {
        _checkpoint()
        let base = slides.isEmpty ? SlideLayoutKind.titleSlide : currentSlide.layout
        let kind = layout ?? (base == .titleSlide ? .titleAndContent : base)
        let slide = _makeSlide(kind)
        let at = slides.isEmpty ? 0 : current + 1
        slides.insert(slide, at: at)
        current = at
        selection = []
        _changed()
        return slide
    }

    func duplicateSlide(_ index: Int) {
        guard slides.indices.contains(index) else { return }
        _checkpoint()
        let source = slides[index]
        let copy = Slide(id: _id(), layout: source.layout, shapes: source.shapes.map { _copy($0) },
                         notes: _textController(source.notes.document))
        copy.hidden = source.hidden
        _watch(copy)
        slides.insert(copy, at: index + 1)
        current = index + 1
        selection = []
        _changed()
    }

    func deleteSlide(_ index: Int) {
        guard slides.indices.contains(index), slides.count > 1 else { return }
        _checkpoint()
        _unwatch(slides[index])
        slides.remove(at: index)
        if index < current || current >= slides.count { current = max(0, current - 1) }
        selection = []
        _changed()
    }

    func moveSlide(_ from: Int, to: Int) {
        guard slides.indices.contains(from) else { return }
        let target = max(0, min(slides.count - 1, to))
        guard target != from else { return }
        _checkpoint()
        let slide = slides.remove(at: from)
        slides.insert(slide, at: target)
        current = target
        _changed()
    }

    func toggleHidden(_ index: Int) {
        guard slides.indices.contains(index) else { return }
        _checkpoint()
        slides[index].hidden.toggle()
        _changed()
    }

    /// Re-lay a slide onto another layout. Text moves by role and order:
    /// the title stays the title, the n-th body the n-th body; a body the
    /// new layout has no room for keeps its text in a placeholder of its own
    /// at the old position, as PowerPoint does.
    func applyLayout(_ layout: SlideLayoutKind, to index: Int) {
        guard slides.indices.contains(index) else { return }
        let slide = slides[index]
        guard slide.layout != layout else { return }
        _checkpoint()
        let old = slide.shapes
        var oldTitle = old.first { $0.role == .title || $0.role == .ctrTitle }
        var oldBodies = old.filter { $0.role == .body || $0.role == .subTitle }
        var next: [SlideShape] = []
        for spec in layout.placeholders {
            let shape = _makeShape(spec)
            let isTitle = spec.role == .title || spec.role == .ctrTitle
            let donor: SlideShape?
            if isTitle { donor = oldTitle; oldTitle = nil } else { donor = oldBodies.isEmpty ? nil : oldBodies.removeFirst() }
            if let donor, !donor.isEmptyText, let text = donor.text, let target = shape.text {
                target.load(text.document)
            }
            next.append(shape)
        }
        // Leftovers with text survive where they were; empty ones go.
        for shape in ([oldTitle].compactMap { $0 } + oldBodies) where !shape.isEmptyText {
            next.append(shape)
        }
        // Everything that is not a placeholder (text boxes, shapes,
        // pictures) stays on top, untouched.
        next.append(contentsOf: old.filter { $0.role == nil })
        for shape in old where !next.contains(where: { $0 === shape }) { _unwatch(shape) }
        slide.shapes = next
        slide.layout = layout
        for shape in next { _watch(shape) }
        selection = []
        _changed()
    }

    // MARK: Selection

    func selectShapes(_ shapes: [SlideShape]) {
        let mine = shapes.filter { s in currentSlide.shapes.contains { $0 === s } }
        guard mine.count != selection.count || zip(mine, selection).contains(where: { $0 !== $1 }) else { return }
        selection = mine
        _notify()
    }

    func isSelected(_ shape: SlideShape) -> Bool { selection.contains { $0 === shape } }

    // MARK: Shapes

    func addTextBox(at frame: Rect) -> SlideShape {
        _checkpoint()
        let theme = _textTheme(font: self.theme.bodyFont, size: 18, color: self.theme.text)
        let style = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)
        let shape = SlideShape(id: _id(), name: "TextBox \(_nextId)", kind: .textBox, frame: frame,
                               text: _textController(RichDocument(paragraphs: [RichParagraph(text: "", style: style)])),
                               textTheme: theme)
        currentSlide.shapes.append(shape)
        _watch(shape)
        selection = [shape]
        _changed()
        return shape
    }

    /// A drawn shape from the gallery, centred on the slide, in the theme's
    /// first accent with white text — PowerPoint's default look.
    @discardableResult
    func addShape(_ preset: ShapePreset) -> SlideShape {
        _checkpoint()
        let w = preset.isLine ? 192.0 : 144.0
        let h = preset.isLine ? 0.0 : (preset == .rightArrow ? 72.0 : 108.0)
        let frame = Rect.fromLTWH((slideSize.width - w) / 2, (slideSize.height - h) / 2, w, h)
        let accent = theme.accents[0]
        let theme = _textTheme(font: self.theme.bodyFont, size: 18, color: Color(0xFFFFFFFF))
        let style = RichParagraphStyle(alignment: .center, spaceAfter: 0, lineSpacing: 1.0)
        let shape = SlideShape(id: _id(), name: "\(preset.name) \(_nextId)", kind: .geometry(preset), frame: frame,
                               text: preset.isLine ? nil
                                   : _textController(RichDocument(paragraphs: [RichParagraph(text: "", style: style)])),
                               textTheme: preset.isLine ? nil : theme, anchor: .middle)
        shape.fill = preset.isLine ? nil : accent
        shape.outline = preset.isLine ? accent : Self.darker(accent)
        shape.outlineWidth = preset.isLine ? 1.5 : 1
        currentSlide.shapes.append(shape)
        _watch(shape)
        selection = [shape]
        _changed()
        return shape
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for shape in selection { _unwatch(shape) }
        currentSlide.shapes.removeAll { s in selection.contains { $0 === s } }
        selection = []
        _changed()
    }

    /// Copies of the selection, nudged down and right, selected in its place.
    func duplicateSelection(offset: Double = 18) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        let copies = selection.map { _copy($0, offset: offset) }
        currentSlide.shapes.append(contentsOf: copies)
        for c in copies { _watch(c) }
        selection = copies
        _changed()
    }

    /// The selection as values, for the shape clipboard.
    func copySelection() -> [ShapeState] { selection.map(_state) }

    func paste(_ states: [ShapeState], offset: Double = 18) {
        guard !states.isEmpty else { return }
        _checkpoint()
        var pasted: [SlideShape] = []
        for var s in states {
            s.id = _id()
            s.frame = s.frame.shift(Offset(offset, offset))
            let shape = _make(s)
            pasted.append(shape)
            _watch(shape)
        }
        currentSlide.shapes.append(contentsOf: pasted)
        selection = pasted
        _changed()
    }

    // Moves and resizes come in three calls so a drag is one undo step and
    // every frame between is cheap: begin (checkpoint), live updates (no
    // history), end.

    func beginFrameEdit() { _checkpoint() }

    func setFramesLive(_ frames: [(SlideShape, Rect)]) {
        for (shape, frame) in frames { shape.frame = frame }
        _changed(keepSession: true)
    }

    /// The drag is over: typing after it is a step of its own.
    func endFrameEdit() { _changed() }

    func setRotationLive(_ shape: SlideShape, _ degrees: Double) {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        shape.rotation = d
        _changed(keepSession: true)
    }

    func nudgeSelection(dx: Double, dy: Double) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection { s.frame = s.frame.shift(Offset(dx, dy)) }
        _changed()
    }

    func setFill(_ color: Color?) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection where s.preset?.isLine != true { s.fill = color }
        _changed()
    }

    func setOutline(_ color: Color?) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection { s.outline = color }
        _changed()
    }

    func setOutlineWidth(_ width: Double) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection { s.outlineWidth = width }
        _changed()
    }

    enum Arrange { case front, back, forward, backward }

    func arrange(_ how: Arrange) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        var shapes = currentSlide.shapes
        let picked = shapes.filter { s in selection.contains { $0 === s } }
        switch how {
        case .front:
            shapes.removeAll { s in picked.contains { $0 === s } }
            shapes.append(contentsOf: picked)
        case .back:
            shapes.removeAll { s in picked.contains { $0 === s } }
            shapes.insert(contentsOf: picked, at: 0)
        case .forward:
            for s in picked.reversed() {
                guard let i = shapes.firstIndex(where: { $0 === s }), i + 1 < shapes.count else { continue }
                shapes.swapAt(i, i + 1)
            }
        case .backward:
            for s in picked {
                guard let i = shapes.firstIndex(where: { $0 === s }), i > 0 else { continue }
                shapes.swapAt(i, i - 1)
            }
        }
        currentSlide.shapes = shapes
        _changed()
    }

    enum Align { case left, center, right, top, middle, bottom }

    /// One shape aligns to the slide; several align to the box around them.
    func align(_ how: Align) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        let box: Rect = selection.count == 1
            ? Rect.fromLTWH(0, 0, slideSize.width, slideSize.height)
            : selection.dropFirst().reduce(selection[0].frame) { $0.expandToInclude($1.frame) }
        for s in selection {
            let f = s.frame
            var x = f.left, y = f.top
            switch how {
            case .left: x = box.left
            case .center: x = box.left + (box.width - f.width) / 2
            case .right: x = box.right - f.width
            case .top: y = box.top
            case .middle: y = box.top + (box.height - f.height) / 2
            case .bottom: y = box.bottom - f.height
            }
            s.frame = Rect.fromLTWH(x, y, f.width, f.height)
        }
        _changed()
    }

    // MARK: Undo

    /// Editing of a text body began: its typing collects into one step.
    func beginTextSession() {
        _sessionWanted = true
        if _session == nil { _session = (snapshot(), _textRevisions()) }
    }

    /// Editing ended: the typing, if any, becomes one undo step.
    func endTextSession() {
        _flushSession()
        _sessionWanted = false
    }

    func undo() {
        _flushSession()
        guard let state = _undo.popLast() else { return }
        _redo.append(snapshot())
        restore(state)
    }

    func redo() {
        _flushSession()
        guard let state = _redo.popLast() else { return }
        _undo.append(snapshot())
        restore(state)
    }

    private var _sessionChanged: Bool {
        guard let s = _session else { return false }
        return _textRevisions() != s.revisions
    }

    private func _flushSession() {
        if let s = _session, _textRevisions() != s.revisions {
            _undo.append(s.state)
            if _undo.count > Self._undoLimit { _undo.removeFirst() }
            _redo.removeAll()
        }
        _session = nil
    }

    /// Called first by every edit: what the deck was becomes an undo step.
    private func _checkpoint() {
        _flushSession()
        _undo.append(snapshot())
        if _undo.count > Self._undoLimit { _undo.removeFirst() }
        _redo.removeAll()
    }

    func snapshot() -> DeckState {
        DeckState(slides: slides.map { slide in
            SlideState(id: slide.id, layout: slide.layout, hidden: slide.hidden,
                       notes: slide.notes.document, shapes: slide.shapes.map(_state))
        }, current: current, slideSize: slideSize)
    }

    /// Put the deck back as `state` was. Objects that still exist are kept
    /// (and their text reloaded only when it differs), so an editor bound to
    /// a body stays bound.
    func restore(_ state: DeckState) {
        var oldSlides: [Int: Slide] = [:]
        var oldShapes: [Int: SlideShape] = [:]
        for slide in slides {
            oldSlides[slide.id] = slide
            for shape in slide.shapes { oldShapes[shape.id] = shape }
        }
        var kept = Set<ObjectIdentifier>()
        var next: [Slide] = []
        for ss in state.slides {
            let shapes: [SlideShape] = ss.shapes.map { st in
                if let shape = oldShapes[st.id], shape.kind == st.kind, (shape.text == nil) == (st.text == nil) {
                    _apply(st, to: shape)
                    kept.insert(ObjectIdentifier(shape))
                    return shape
                }
                let shape = _make(st)
                _watch(shape)
                return shape
            }
            let slide: Slide
            if let old = oldSlides[ss.id] {
                slide = old
                slide.shapes = shapes
                slide.layout = ss.layout
                kept.insert(ObjectIdentifier(slide))
                if slide.notes.document != ss.notes { slide.notes.load(ss.notes) }
            } else {
                slide = Slide(id: ss.id, layout: ss.layout, shapes: shapes, notes: _textController(ss.notes))
                slide.notes.addListener({ [weak self] in self?._textChanged() }, owner: self)
            }
            slide.hidden = ss.hidden
            next.append(slide)
        }
        for slide in slides {
            if !kept.contains(ObjectIdentifier(slide)) { slide.notes.removeListeners(owner: self) }
            for shape in slide.shapes where !kept.contains(ObjectIdentifier(shape)) { _unwatch(shape) }
        }
        slides = next
        slideSize = state.slideSize
        current = max(0, min(state.current, slides.count - 1))
        selection = []
        _nextId = max(_nextId, (state.slides.flatMap { [$0.id] + $0.shapes.map(\.id) }.max() ?? 0) + 1)
        _changed()
    }

    private func _state(_ s: SlideShape) -> ShapeState {
        ShapeState(id: s.id, name: s.name, kind: s.kind, frame: s.frame, rotation: s.rotation,
                   fill: s.fill, outline: s.outline, outlineWidth: s.outlineWidth, anchor: s.anchor,
                   insets: s.insets, prompt: s.prompt, text: s.text?.document,
                   font: s.textTheme?.fontFamily, size: s.textTheme?.fontSize ?? 18,
                   color: s.textTheme?.textColor ?? theme.text, listIndent: s.textTheme?.listIndent ?? 18)
    }

    private func _apply(_ st: ShapeState, to shape: SlideShape) {
        shape.name = st.name
        shape.frame = st.frame
        shape.rotation = st.rotation
        shape.fill = st.fill
        shape.outline = st.outline
        shape.outlineWidth = st.outlineWidth
        shape.anchor = st.anchor
        shape.insets = st.insets
        shape.prompt = st.prompt
        if let doc = st.text, let c = shape.text, c.document != doc { c.load(doc) }
    }

    private func _make(_ st: ShapeState) -> SlideShape {
        let theme = st.text == nil ? nil : _textTheme(font: st.font ?? self.theme.bodyFont, size: st.size, color: st.color)
        theme?.listIndent = st.listIndent
        let shape = SlideShape(id: st.id, name: st.name, kind: st.kind, frame: st.frame,
                               text: st.text.map(_textController), textTheme: theme,
                               anchor: st.anchor, prompt: st.prompt)
        _apply(st, to: shape)
        return shape
    }

    // MARK: Building

    private func _id() -> Int {
        defer { _nextId += 1 }
        return _nextId
    }

    private func _makeSlide(_ layout: SlideLayoutKind) -> Slide {
        let shapes = layout.placeholders.map(_makeShape)
        let notes = _textController(RichDocument(paragraphs: [
            RichParagraph(text: "", style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)),
        ]))
        let slide = Slide(id: _id(), layout: layout, shapes: shapes, notes: notes)
        _watch(slide)
        return slide
    }

    private func _makeShape(_ spec: PlaceholderSpec) -> SlideShape {
        let sx = slideSize.width / 960
        let sy = slideSize.height / 540
        let f = spec.frame
        let theme = _textTheme(font: spec.heading ? self.theme.headingFont : self.theme.bodyFont,
                               size: spec.fontSize,
                               color: spec.subtle ? self.theme.subtle : self.theme.text)
        // PowerPoint's master: 90% line spacing, 10 pt before each body
        // paragraph, nothing after.
        let style = RichParagraphStyle(alignment: spec.alignment, spaceBefore: spec.bullets ? 10 : 0,
                                       spaceAfter: 0, lineSpacing: 0.9,
                                       list: spec.bullets ? .bullet : nil)
        let doc = RichDocument(paragraphs: [RichParagraph(text: "", style: style)])
        return SlideShape(id: _id(), name: spec.name, kind: .placeholder(spec.role),
                          frame: Rect.fromLTWH(f.left * sx, f.top * sy, f.width * sx, f.height * sy),
                          text: _textController(doc), textTheme: theme, anchor: spec.anchor,
                          prompt: spec.prompt)
    }

    private func _copy(_ shape: SlideShape, offset: Double = 0) -> SlideShape {
        var st = _state(shape)
        st.id = _id()
        st.frame = st.frame.shift(Offset(offset, offset))
        return _make(st)
    }

    private func _textTheme(font: String, size: Double, color: Color) -> RichTextTheme {
        let theme = RichTextTheme(fontFamily: font, fontSize: size, textColor: color, caretColor: color,
                                  headingColor: nil, listIndent: 18)
        theme.fontFamilyResolver = OfficeFonts.substitute
        return theme
    }

    private func _textController(_ doc: RichDocument) -> RichDocumentController {
        let c = RichDocumentController()
        c.clipboardCodec = OfficeClipboardCodec()
        c.load(doc)
        return c
    }

    static func darker(_ c: Color) -> Color {
        let v = c.value
        let r = Int(Double((v >> 16) & 0xFF) * 0.7), g = Int(Double((v >> 8) & 0xFF) * 0.7)
        let b = Int(Double(v & 0xFF) * 0.7)
        return Color(0xFF00_0000 | (r << 16) | (g << 8) | b)
    }

    // MARK: Change tracking

    private func _watch(_ slide: Slide) {
        slide.notes.addListener({ [weak self] in self?._textChanged() }, owner: self)
        for shape in slide.shapes { _watch(shape) }
    }

    private func _watch(_ shape: SlideShape) {
        shape.text?.addListener({ [weak self] in self?._textChanged() }, owner: self)
    }

    private func _unwatch(_ slide: Slide) {
        slide.notes.removeListeners(owner: self)
        for shape in slide.shapes { _unwatch(shape) }
    }

    private func _unwatch(_ shape: SlideShape) {
        shape.text?.removeListeners(owner: self)
    }

    private func _textRevisions() -> [ObjectIdentifier: Int] {
        var r: [ObjectIdentifier: Int] = [:]
        for slide in slides {
            r[ObjectIdentifier(slide.notes)] = slide.notes.revision
            for c in slide.shapes.compactMap(\.text) { r[ObjectIdentifier(c)] = c.revision }
        }
        return r
    }

    private var _lastTextRevisions: [ObjectIdentifier: Int] = [:]

    /// Caret moves notify too; only a change to the words moves the deck on.
    private func _textChanged() {
        let now = _textRevisions()
        guard now != _lastTextRevisions else { return }
        _lastTextRevisions = now
        revision += 1
        notifyListeners()
    }

    private func _notify() {
        revision += 1
        notifyListeners()
    }

    /// After an edit. An open text session restarts from here, so the edit
    /// and the typing after it are separate steps.
    private func _changed(keepSession: Bool = false) {
        if _sessionWanted && !keepSession && _session == nil {
            _session = (snapshot(), _textRevisions())
        }
        _lastTextRevisions = _textRevisions()
        revision += 1
        notifyListeners()
    }
}
