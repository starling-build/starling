// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// Every change to a deck goes through here. Listeners hear about slide
/// edits and about typing in any text body (thumbnails and anchored text
/// both follow the words), and `revision` moves on each.
final class DeckController: ChangeNotifier {
    private(set) var slides: [Slide] = []
    private(set) var current = 0
    /// The slide in points: 16:9 Widescreen by default, PowerPoint's own
    /// default since 2013 (13.333 x 7.5 in).
    private(set) var slideSize = Size(960, 540)
    var theme = DeckTheme()
    private(set) var revision = 0
    private var _nextId = 1

    override init() {
        super.init()
        newDeck()
    }

    var currentSlide: Slide { slides[current] }

    // MARK: Deck

    /// A fresh deck: one title slide.
    func newDeck() {
        for slide in slides { _unwatch(slide) }
        slides = [_makeSlide(.titleSlide)]
        current = 0
        _changed()
    }

    func setSlideSize(_ size: Size) {
        guard size != slideSize else { return }
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
        _changed()
    }

    /// A new slide after the current one. With no layout given it follows
    /// PowerPoint: after the title slide comes Title and Content, otherwise
    /// the current slide's layout repeats.
    @discardableResult
    func addSlide(_ layout: SlideLayoutKind? = nil) -> Slide {
        let base = slides.isEmpty ? SlideLayoutKind.titleSlide : currentSlide.layout
        let kind = layout ?? (base == .titleSlide ? .titleAndContent : base)
        let slide = _makeSlide(kind)
        let at = slides.isEmpty ? 0 : current + 1
        slides.insert(slide, at: at)
        current = at
        _changed()
        return slide
    }

    func duplicateSlide(_ index: Int) {
        guard slides.indices.contains(index) else { return }
        let source = slides[index]
        let copy = Slide(id: _id(), layout: source.layout, shapes: source.shapes.map(_copy),
                         notes: _textController(source.notes.document))
        copy.hidden = source.hidden
        _watch(copy)
        slides.insert(copy, at: index + 1)
        current = index + 1
        _changed()
    }

    func deleteSlide(_ index: Int) {
        guard slides.indices.contains(index), slides.count > 1 else { return }
        _unwatch(slides[index])
        slides.remove(at: index)
        current = min(current, slides.count - 1)
        if index < current { current -= 1 }
        _changed()
    }

    func moveSlide(_ from: Int, to: Int) {
        guard slides.indices.contains(from) else { return }
        let target = max(0, min(slides.count - 1, to))
        guard target != from else { return }
        let slide = slides.remove(at: from)
        slides.insert(slide, at: target)
        current = target
        _changed()
    }

    func toggleHidden(_ index: Int) {
        guard slides.indices.contains(index) else { return }
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
        // Everything that is not a placeholder (text boxes, later shapes and
        // pictures) stays on top, untouched.
        next.append(contentsOf: old.filter { $0.role == nil })
        for shape in old { _unwatch(shape) }
        slide.shapes = next
        slide.layout = layout
        for shape in next { _watch(shape) }
        _changed()
    }

    // MARK: Shapes

    func addTextBox(at frame: Rect) -> SlideShape {
        let theme = _textTheme(font: self.theme.bodyFont, size: 18, color: self.theme.text)
        let style = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)
        let shape = SlideShape(id: _id(), name: "TextBox \(_nextId)", kind: .textBox, frame: frame,
                               text: _textController(RichDocument(paragraphs: [RichParagraph(text: "", style: style)])),
                               textTheme: theme)
        currentSlide.shapes.append(shape)
        _watch(shape)
        _changed()
        return shape
    }

    func deleteShape(_ shape: SlideShape) {
        guard let i = currentSlide.shapes.firstIndex(where: { $0 === shape }) else { return }
        _unwatch(shape)
        currentSlide.shapes.remove(at: i)
        _changed()
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

    private func _copy(_ shape: SlideShape) -> SlideShape {
        let theme = shape.textTheme.map { t -> RichTextTheme in
            let c = _textTheme(font: t.fontFamily ?? self.theme.bodyFont, size: t.fontSize, color: t.textColor)
            c.listIndent = t.listIndent
            return c
        }
        let copy = SlideShape(id: _id(), name: shape.name, kind: shape.kind, frame: shape.frame,
                              text: shape.text.map { _textController($0.document) },
                              textTheme: theme, anchor: shape.anchor, prompt: shape.prompt)
        copy.fill = shape.fill
        copy.outline = shape.outline
        copy.outlineWidth = shape.outlineWidth
        copy.insets = shape.insets
        return copy
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

    private var _lastTextRevisions: [ObjectIdentifier: Int] = [:]

    /// Caret moves notify too; only a change to the words moves the deck on.
    private func _textChanged() {
        var moved = false
        for slide in slides {
            for c in [slide.notes] + slide.shapes.compactMap(\.text) {
                let key = ObjectIdentifier(c)
                if _lastTextRevisions[key] != c.revision {
                    _lastTextRevisions[key] = c.revision
                    moved = true
                }
            }
        }
        if moved {
            revision += 1
            notifyListeners()
        }
    }

    private func _changed() {
        revision += 1
        notifyListeners()
    }
}
