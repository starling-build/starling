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
    var phType: String? = nil
    var phIdx: String? = nil
    var fillScheme: String? = nil
    /// A picture's crop, as fractions cut from each edge.
    var crop: EdgeInsets? = nil
    var fileId: Int? = nil
    var sourceXML: String? = nil
    var sourceText: RichDocument? = nil
    var sourcePart: String? = nil
    var sourceChart: Chart? = nil
    var field: SlideField? = nil
    var group: ShapeGroup? = nil
    var keptLine: KeptLine? = nil
    var autofit = false
    var fontScale = 1.0
    var keptLook: KeptLook? = nil
}

extension ShapeState {
    var chart: Chart? {
        if case .chart(let c) = kind { return c }
        return nil
    }
}

struct SlideState: Equatable {
    var id: Int
    var layout: SlideLayoutKind
    var hidden: Bool
    var notes: RichDocument
    var shapes: [ShapeState]
    var layoutPart: String? = nil
    var backgroundXML: String? = nil
    var background: SlideFill? = nil
    var inheritedBackground: SlideFill? = nil
    var sourcePart: String? = nil
    var transition = SlideTransition()
    var timingXML: String? = nil
    var footerFrames: [String: Rect] = [:]
    var animations: [ShapeAnimation] = []
    var sourceAnimations: [ShapeAnimation]? = nil
}

struct DeckState: Equatable {
    var slides: [SlideState]
    var current: Int
    var slideSize: Size
    /// Undo restores the look too: applying a theme is one step.
    var theme: DeckTheme? = nil
    var ownTemplates: Bool? = nil
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
    /// Moves on every change to the content (not on selection or moving
    /// between slides): what "unsaved" compares against.
    private(set) var edits = 0
    /// The file the deck was read from, kept whole so a save can write its
    /// masters, layouts, theme and anything not modelled back untouched.
    private(set) var package: PptxPackage? = nil
    /// Write with our own master, layouts and theme even though the deck
    /// came from a file — set once a theme of ours is applied. The package
    /// still supplies kept objects' parts.
    private(set) var ownTemplates = false
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
        slideSize = Size(960, 540)
        theme = DeckTheme()
        package = nil
        ownTemplates = false
        current = 0
        selection = []
        _undo = []
        _redo = []
        _session = nil
        _changed()
    }

    /// Replace the deck with one read from a file: its slides, size, theme
    /// and the package to write back through. No history.
    func load(_ state: DeckState, theme: DeckTheme, package: PptxPackage?) {
        for slide in slides { _unwatch(slide) }
        slides = []
        self.theme = theme
        self.package = package
        ownTemplates = package == nil
        _undo = []
        _redo = []
        _session = nil
        restore(state)
        current = 0
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
        // Same master, same footer positions.
        if !slides.isEmpty { slide.footerFrames = currentSlide.footerFrames }
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
        let shapes = source.shapes.map { _copy($0) }
        let copy = Slide(id: _id(), layout: source.layout, shapes: shapes,
                         notes: _textController(source.notes.document))
        copy.hidden = source.hidden
        // The copy's animations, aimed at the copies of their shapes.
        var map: [Int: Int] = [:]
        for (a, b) in zip(source.shapes, shapes) { map[a.id] = b.id }
        copy.animations = source.animations.compactMap { a in
            map[a.shapeId].map { var c = a; c.shapeId = $0; return c }
        }
        copy.transition = source.transition
        copy.footerFrames = source.footerFrames
        copy.layoutPart = source.layoutPart
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

    /// The current slide's transition, or every slide's.
    func setTransition(_ kind: SlideTransition.Kind? = nil, direction: SlideTransition.Direction? = nil,
                       duration: Double? = nil, all: Bool = false) {
        _checkpoint()
        for slide in all ? slides : [currentSlide] {
            var t = all ? currentSlide.transition : slide.transition
            if let kind { t.kind = kind }
            if let direction { t.direction = direction }
            if let duration { t.duration = max(0.1, min(10, duration)) }
            t.raw = nil
            slide.transition = t
        }
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
        shape.fillScheme = "accent1"
        shape.outlineWidth = preset.isLine ? 1.5 : 1
        currentSlide.shapes.append(shape)
        _watch(shape)
        selection = [shape]
        _changed()
        return shape
    }

    /// A picture, centred, at its natural size shrunk to fit four fifths of
    /// the slide.
    @discardableResult
    func addPicture(_ image: ImageAttachment, naturalSize: Size) -> SlideShape {
        _checkpoint()
        var w = naturalSize.width, h = naturalSize.height
        let fit = min(1, slideSize.width * 0.8 / max(w, 1), slideSize.height * 0.8 / max(h, 1))
        w *= fit; h *= fit
        let shape = SlideShape(id: _id(), name: "Picture \(_nextId)", kind: .picture(image),
                               frame: Rect.fromLTWH((slideSize.width - w) / 2, (slideSize.height - h) / 2, w, h),
                               text: nil, textTheme: nil)
        currentSlide.shapes.append(shape)
        selection = [shape]
        _changed()
        return shape
    }

    // MARK: Animations

    /// The current slide's animations can be edited here (not kept as the
    /// file had them).
    var canAnimate: Bool { !currentSlide.animationsKept }

    /// The selected shapes' entrance animations, in slide order.
    var selectedAnimations: [ShapeAnimation] {
        currentSlide.animations.filter { a in selection.contains { $0.id == a.shapeId } }
    }

    /// The gallery: each selected shape gets `effect` (nil takes its
    /// animation away) — every paragraph of a build by paragraph — keeping
    /// its place, start and timing; a shape without one goes to the end, on
    /// a click.
    func setEntrance(_ effect: ShapeAnimation.Effect?) {
        guard canAnimate, !selection.isEmpty else { return }
        _checkpoint()
        let slide = currentSlide
        for shape in selection {
            let mine = slide.animations.indices.filter { slide.animations[$0].shapeId == shape.id }
            guard !mine.isEmpty else {
                if let effect { slide.animations.append(ShapeAnimation(shapeId: shape.id, effect: effect)) }
                continue
            }
            guard let effect else {
                slide.animations.removeAll { $0.shapeId == shape.id }
                continue
            }
            for i in mine {
                let was = slide.animations[i].effect
                slide.animations[i].effect = effect
                if was == .appear || effect == .appear { slide.animations[i].duration = effect.defaultDuration }
            }
        }
        _changed()
    }

    /// Effect Options → Sequence: the selected text shapes' entrances as
    /// one object, or a paragraph at a time (the first as the shape's
    /// start, the rest on clicks), as PowerPoint offers it.
    func setByParagraph(_ on: Bool) {
        guard canAnimate else { return }
        let slide = currentSlide
        let shapes = selection.filter { s in s.text != nil && slide.animations.contains { $0.shapeId == s.id } }
        guard !shapes.isEmpty else { return }
        _checkpoint()
        for shape in shapes {
            guard let at = slide.animations.firstIndex(where: { $0.shapeId == shape.id }) else { continue }
            let first = slide.animations[at]
            slide.animations.removeAll { $0.shapeId == shape.id }
            var entries: [ShapeAnimation] = []
            if on {
                let paras = shape.text?.document.paragraphs ?? []
                for (i, p) in paras.enumerated() where !p.text.isEmpty {
                    var a = first
                    a.paragraph = i
                    if !entries.isEmpty { a.start = .onClick; a.delay = 0 }
                    entries.append(a)
                }
            }
            if entries.isEmpty { var a = first; a.paragraph = nil; entries = [a] }
            slide.animations.insert(contentsOf: entries, at: min(at, slide.animations.count))
        }
        _changed()
    }

    /// Whether the selection's text comes in a paragraph at a time.
    var selectionByParagraph: Bool {
        selectedAnimations.contains { $0.paragraph != nil }
    }

    /// Change the selected shapes' animations: start, direction, timing.
    func editAnimations(_ edit: (inout ShapeAnimation) -> Void) {
        guard canAnimate, !selectedAnimations.isEmpty else { return }
        _checkpoint()
        let slide = currentSlide
        for i in slide.animations.indices where selection.contains(where: { $0.id == slide.animations[i].shapeId }) {
            edit(&slide.animations[i])
        }
        _changed()
    }

    /// Move animation `index` of the current slide one place earlier (-1)
    /// or later (+1).
    func moveAnimation(_ index: Int, by step: Int) {
        let slide = currentSlide
        let to = index + step
        guard canAnimate, slide.animations.indices.contains(index), slide.animations.indices.contains(to) else { return }
        _checkpoint()
        slide.animations.swapAt(index, to)
        _changed()
    }

    func removeAnimation(_ index: Int) {
        let slide = currentSlide
        guard canAnimate, slide.animations.indices.contains(index) else { return }
        _checkpoint()
        slide.animations.remove(at: index)
        _changed()
    }

    // MARK: Find

    /// Replace every occurrence of `query` in the deck's text — shapes,
    /// tables and notes — as one undo step; returns how many.
    @discardableResult
    func replaceEverywhere(_ query: String, with replacement: String) -> Int {
        let count = matches(query).count
        guard count > 0 else { return 0 }
        _checkpoint()
        for i in slides.indices {
            for body in textStops(i) { body.controller.replaceAll(query, with: replacement) }
        }
        _changed()
        return count
    }

    // MARK: Header and footer

    /// PowerPoint's Header & Footer settings for slides.
    struct HeaderFooter: Equatable {
        var date = false
        /// The date as fixed text; nil updates automatically (a field).
        var fixedDate: String? = nil
        var slideNumber = false
        /// Footer text; nil for none.
        var footer: String? = nil
        var skipTitleSlides = false
    }

    static let footerTypes = ["dt", "ftr", "sldNum"]

    /// What `slide` shows now: where the dialog starts.
    func headerFooter(of slide: Slide) -> HeaderFooter {
        var hf = HeaderFooter()
        for shape in slide.shapes {
            switch shape.phType {
            case "dt":
                hf.date = true
                if shape.field == nil { hf.fixedDate = shape.text?.document.plainText() ?? "" }
            case "ftr": hf.footer = shape.text?.document.plainText() ?? ""
            case "sldNum": hf.slideNumber = true
            default: break
            }
        }
        hf.skipTitleSlides = slides.contains { $0.layout == .titleSlide }
            && slides.filter { $0.layout == .titleSlide }.allSatisfy { s in !s.shapes.contains { Self.footerTypes.contains($0.phType ?? "") } }
            && slides.contains { s in s.shapes.contains { Self.footerTypes.contains($0.phType ?? "") } }
        return hf
    }

    /// Date, footer and slide number placed (or taken away) on the current
    /// slide or every slide, where the slide's layout keeps them. One undo
    /// step.
    func applyHeaderFooter(_ hf: HeaderFooter, toAll: Bool) {
        _checkpoint()
        let targets = toAll ? slides : [currentSlide]
        for slide in targets {
            let removed = slide.shapes.filter { Self.footerTypes.contains($0.phType ?? "") }
            for shape in removed { _unwatch(shape) }
            slide.shapes.removeAll { Self.footerTypes.contains($0.phType ?? "") }
            if hf.skipTitleSlides && slide.layout == .titleSlide { continue }
            var add: [SlideShape] = []
            if hf.date {
                let field = hf.fixedDate == nil ? SlideField(type: "datetime1", id: SlideField.newId()) : nil
                add.append(_footerShape("dt", text: hf.fixedDate ?? "", field: field, slide: slide))
            }
            if let text = hf.footer { add.append(_footerShape("ftr", text: text, field: nil, slide: slide)) }
            if hf.slideNumber {
                add.append(_footerShape("sldNum", text: "", field: SlideField(type: "slidenum", id: SlideField.newId()), slide: slide))
            }
            for shape in add { _watch(shape) }
            slide.shapes += add
        }
        selection = selection.filter { s in slides.contains { $0.shapes.contains { $0 === s } } }
        _changed()
    }

    /// PowerPoint's own positions on a 16:9 slide, scaled to this one.
    private func _footerFrame(_ type: String, slide: Slide) -> Rect {
        if let f = slide.footerFrames[type] { return f }
        let sx = slideSize.width / 960, sy = slideSize.height / 540
        let left: Double, width: Double
        switch type {
        case "dt": left = 66; width = 216
        case "ftr": left = 318; width = 324
        default: left = 678; width = 216
        }
        return Rect.fromLTWH(left * sx, 500.5 * sy, width * sx, 28.75 * sy)
    }

    private func _footerShape(_ type: String, text: String, field: SlideField?, slide: Slide) -> SlideShape {
        let align: ParagraphAlignment = type == "dt" ? .left : type == "ftr" ? .center : .right
        let style = RichParagraphStyle(alignment: align, spaceBefore: 0, spaceAfter: 0, lineSpacing: 0.9)
        let doc = RichDocument(paragraphs: [RichParagraph(text: text, style: style)])
        let name = type == "dt" ? "Date Placeholder" : type == "ftr" ? "Footer Placeholder" : "Slide Number Placeholder"
        let shape = SlideShape(id: _id(), name: "\(name) \(_nextId)", kind: .placeholder(.body),
                               frame: _footerFrame(type, slide: slide), text: _textController(doc),
                               textTheme: _textTheme(font: theme.bodyFont, size: 12, color: theme.subtle),
                               anchor: .middle)
        shape.phType = type
        shape.phIdx = type == "dt" ? "10" : type == "ftr" ? "11" : "12"
        shape.field = field
        return shape
    }

    // MARK: Charts

    /// A chart of `type` on PowerPoint's sample data, centred, three fifths
    /// of the slide each way.
    @discardableResult
    func addChart(_ type: ChartType) -> SlideShape {
        _checkpoint()
        let w = (slideSize.width * 0.6).rounded(), h = (slideSize.height * 0.6).rounded()
        let shape = SlideShape(id: _id(), name: "Chart \(_nextId)", kind: .chart(.sample(type)),
                               frame: Rect.fromLTWH(((slideSize.width - w) / 2).rounded(), ((slideSize.height - h) / 2).rounded(), w, h),
                               text: nil, textTheme: nil)
        currentSlide.shapes.append(shape)
        selection = [shape]
        _changed()
        return shape
    }

    /// The one selected chart, for the Chart Design tab and the data grid.
    var selectedChart: SlideShape? {
        selection.count == 1 && selection[0].chart != nil ? selection[0] : nil
    }

    private var _chartEdit: (key: String, at: Int)? = nil

    /// A chart's data or settings replaced: one undo step — or, with
    /// `coalesce`, one step for a run of edits with the same key and nothing
    /// in between (typing into one cell of the data grid).
    func setChart(_ shape: SlideShape, _ chart: Chart, coalesce key: String? = nil) {
        guard shape.chart != nil, shape.chart != chart else { return }
        if let key, let last = _chartEdit, last.key == key, last.at == edits {
            edits += 1
        } else {
            _checkpoint()
        }
        _chartEdit = key.map { ($0, edits) }
        shape.kind = .chart(chart)
        _changed()
    }

    /// The selected pictures back to their natural proportions (the width
    /// kept), and uncropped.
    func resetPictures() {
        let pics = selection.filter { $0.picture != nil }
        guard !pics.isEmpty else { return }
        _checkpoint()
        for s in pics {
            guard let img = s.picture else { continue }
            s.crop = nil
            if let nw = img.naturalWidth, let nh = img.naturalHeight, nw > 0 {
                s.frame = Rect.fromLTWH(s.frame.left, s.frame.top, s.frame.width, s.frame.width * nh / nw)
            }
        }
        _changed()
    }

    /// Crop the selected pictures to a shape: width over height, centred.
    func cropPictures(aspect: Double) {
        let pics = selection.filter { $0.picture != nil }
        guard !pics.isEmpty, aspect > 0 else { return }
        _checkpoint()
        for s in pics {
            guard let img = s.picture else { continue }
            let nw = img.naturalWidth ?? s.frame.width, nh = img.naturalHeight ?? s.frame.height
            let natural = nw / max(nh, 0.001)
            var c = EdgeInsets.zero
            if natural > aspect {
                let cut = (1 - aspect / natural) / 2
                c = EdgeInsets(left: cut, top: 0, right: cut, bottom: 0)
            } else {
                let cut = (1 - natural / aspect) / 2
                c = EdgeInsets(left: 0, top: cut, right: 0, bottom: cut)
            }
            s.crop = c
            // The cropped picture fits inside the box it had, centred.
            let f = s.frame
            let w = min(f.width, f.height * aspect), h = w / aspect
            s.frame = Rect.fromLTWH(f.center.dx - w / 2, f.center.dy - h / 2, w, h)
        }
        _changed()
    }

    /// PowerPoint's default table look in the theme's first accent: a
    /// filled header with white bold text, banded rows, white rules.
    func tableStyle(accent: Color) -> TableStyle {
        TableStyle(borders: true, headerRow: true, headerFill: accent,
                   bandFill: Self.tint(accent, 0.40), bandAltFill: Self.tint(accent, 0.20),
                   borderColor: Color(0xFFFFFFFF))
    }

    /// A table centred on the slide, a column 144 pt wide (at most four
    /// fifths of the slide across), rows as tall as their text.
    @discardableResult
    func addTable(rows: Int, columns: Int) -> SlideShape {
        _checkpoint()
        let rows = max(1, rows), cols = max(1, columns)
        let id = UUID().uuidString
        var paragraphs: [RichParagraph] = []
        let header = CharStyle(bold: true, color: Color(0xFFFFFFFF))
        for r in 0 ..< rows {
            for c in 0 ..< cols {
                var p = RichParagraph(text: "", runs: r == 0 ? [Run(length: 0, style: header)] : nil,
                                      style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))
                p.cell = CellRef(table: id, row: r, column: c)
                paragraphs.append(p)
            }
        }
        var doc = RichDocument(paragraphs: paragraphs)
        doc.tableStyles[id] = tableStyle(accent: theme.accents[0])
        let w = min(slideSize.width * 0.8, Double(cols) * 144)
        let h = Double(rows) * 30
        let shape = SlideShape(id: _id(), name: "Table \(_nextId)", kind: .table,
                               frame: Rect.fromLTWH((slideSize.width - w) / 2, (slideSize.height - h) / 2, w, h),
                               text: _textController(doc),
                               textTheme: _textTheme(font: theme.bodyFont, size: 18, color: theme.text))
        shape.insets = EdgeInsets(left: 0, top: 0, right: 0, bottom: 0)
        shape.fillScheme = "accent1"
        currentSlide.shapes.append(shape)
        _watch(shape)
        selection = [shape]
        _changed()
        return shape
    }

    /// A table's height follows its rows: no undo step of its own, it is
    /// part of the typing that grew it.
    func fitHeight(_ shape: SlideShape, _ height: Double) {
        guard abs(shape.frame.height - height) > 0.5 else { return }
        let f = shape.frame
        shape.frame = Rect.fromLTWH(f.left, f.top, f.width, height)
        revision += 1
        notifyListeners()
    }

    static func tint(_ c: Color, _ amount: Double) -> Color {
        let v = c.value
        func mix(_ x: Int) -> Int { Int(Double(x) * amount + 255 * (1 - amount)) }
        return Color(0xFF00_0000 | (mix((v >> 16) & 0xFF) << 16) | (mix((v >> 8) & 0xFF) << 8) | mix(v & 0xFF))
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
            s.fileId = nil
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

    func setFill(_ color: Color?, scheme: String? = nil) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection where s.preset?.isLine != true {
            s.fill = color
            s.fillScheme = scheme
        }
        _changed()
    }

    // MARK: Design

    /// Restyle the deck with one of our themes. Placeholders take its fonts
    /// and text colour, shapes coloured from the old theme take the new
    /// one's, and text that simply followed the old theme follows this one.
    /// A deck read from a file is written with our master and layouts from
    /// here on (its kept objects still travel with it).
    func applyTheme(_ new: DeckTheme) {
        _checkpoint()
        let old = theme
        theme = new
        ownTemplates = true
        for slide in slides {
            slide.layoutPart = nil
            slide.backgroundXML = nil
            slide.inheritedBackground = nil
            if let bg = slide.background, bg.image == nil { slide.background = nil }
            for shape in slide.shapes {
                if shape.kind == .table, shape.fillScheme != nil, let id = shape.tableId, let text = shape.text {
                    var doc = text.document
                    doc.tableStyles[id] = tableStyle(accent: new.accents[0])
                    text.load(doc)
                } else if let scheme = shape.fillScheme, let i = Int(scheme.dropFirst(6)), (1 ... 6).contains(i) {
                    let c = new.accents[i - 1]
                    if shape.preset?.isLine == true { shape.outline = c } else {
                        shape.fill = c
                        shape.outline = Self.darker(c)
                    }
                }
                guard let tt = shape.textTheme, let text = shape.text else { continue }
                let heading = shape.role == .title || shape.role == .ctrTitle
                if shape.role != nil || shape.kind == .textBox {
                    let fresh = _textTheme(font: heading ? new.headingFont : new.bodyFont, size: tt.fontSize,
                                           color: tt.textColor == old.subtle ? new.subtle : new.text)
                    fresh.listIndent = tt.listIndent
                    shape.textTheme = fresh
                }
                // Runs that spelled out the old theme's look follow the new one.
                var doc = text.document
                var touched = false
                for p in doc.paragraphs.indices {
                    for r in doc.paragraphs[p].runs.indices {
                        var st = doc.paragraphs[p].runs[r].style
                        if st.color == old.text || st.color == old.subtle { st.color = nil; touched = true }
                        if st.fontFamily == old.headingFont || st.fontFamily == old.bodyFont { st.fontFamily = nil; touched = true }
                        doc.paragraphs[p].runs[r].style = st
                    }
                }
                if touched { text.load(doc) }
            }
        }
        _changed()
    }

    /// The current slide's background, or every slide's; nil returns to
    /// the theme's.
    func setBackground(_ fill: SlideFill?, all: Bool = false) {
        _checkpoint()
        for slide in all ? slides : [currentSlide] {
            slide.background = fill
            slide.backgroundXML = nil
        }
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
        edits += 1
        _flushSession()
        _undo.append(snapshot())
        if _undo.count > Self._undoLimit { _undo.removeFirst() }
        _redo.removeAll()
    }

    func snapshot() -> DeckState {
        DeckState(slides: slides.map { slide in
            SlideState(id: slide.id, layout: slide.layout, hidden: slide.hidden,
                       notes: slide.notes.document, shapes: slide.shapes.map(_state),
                       layoutPart: slide.layoutPart, backgroundXML: slide.backgroundXML,
                       background: slide.background, inheritedBackground: slide.inheritedBackground,
                       sourcePart: slide.sourcePart,
                       transition: slide.transition, timingXML: slide.timingXML,
                       footerFrames: slide.footerFrames, animations: slide.animations,
                       sourceAnimations: slide.sourceAnimations)
        }, current: current, slideSize: slideSize, theme: theme, ownTemplates: ownTemplates)
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
                if let shape = oldShapes[st.id], shape.kind.sameObject(st.kind), (shape.text == nil) == (st.text == nil) {
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
            slide.layoutPart = ss.layoutPart
            slide.backgroundXML = ss.backgroundXML
            slide.background = ss.background
            slide.inheritedBackground = ss.inheritedBackground
            slide.sourcePart = ss.sourcePart
            slide.transition = ss.transition
            slide.timingXML = ss.timingXML
            slide.footerFrames = ss.footerFrames
            slide.animations = ss.animations
            slide.sourceAnimations = ss.sourceAnimations
            next.append(slide)
        }
        for slide in slides {
            if !kept.contains(ObjectIdentifier(slide)) { slide.notes.removeListeners(owner: self) }
            for shape in slide.shapes where !kept.contains(ObjectIdentifier(shape)) { _unwatch(shape) }
        }
        slides = next
        slideSize = state.slideSize
        if let t = state.theme { theme = t }
        if let o = state.ownTemplates { ownTemplates = o }
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
                   color: s.textTheme?.textColor ?? theme.text, listIndent: s.textTheme?.listIndent ?? 18,
                   phType: s.phType, phIdx: s.phIdx, fillScheme: s.fillScheme, crop: s.crop, fileId: s.fileId,
                   sourceXML: s.sourceXML, sourceText: s.sourceText, sourcePart: s.sourcePart,
                   sourceChart: s.sourceChart, field: s.field, group: s.group, keptLine: s.keptLine,
                   autofit: s.autofit, fontScale: s.fontScale, keptLook: s.keptLook)
    }

    private func _apply(_ st: ShapeState, to shape: SlideShape) {
        shape.name = st.name
        shape.kind = st.kind
        shape.frame = st.frame
        shape.rotation = st.rotation
        shape.fill = st.fill
        shape.outline = st.outline
        shape.outlineWidth = st.outlineWidth
        shape.anchor = st.anchor
        shape.insets = st.insets
        shape.prompt = st.prompt
        shape.phType = st.phType
        shape.phIdx = st.phIdx
        // The text's look: a new theme object when it differs (undoing a
        // theme), never an edit in place.
        if st.text != nil, let tt = shape.textTheme,
           tt.fontFamily != st.font || tt.fontSize != st.size || tt.textColor != st.color || tt.listIndent != st.listIndent {
            let fresh = _textTheme(font: st.font ?? theme.bodyFont, size: st.size, color: st.color)
            fresh.listIndent = st.listIndent
            shape.textTheme = fresh
        }
        shape.crop = st.crop
        shape.fileId = st.fileId
        shape.fillScheme = st.fillScheme
        shape.sourceXML = st.sourceXML
        shape.sourceText = st.sourceText
        shape.sourcePart = st.sourcePart
        shape.sourceChart = st.sourceChart
        shape.field = st.field
        shape.fieldShown = nil
        shape.group = st.group
        shape.keptLine = st.keptLine
        shape.autofit = st.autofit
        shape.fontScale = st.fontScale
        shape.keptLook = st.keptLook
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
        let shape = SlideShape(id: _id(), name: spec.name, kind: .placeholder(spec.role),
                               frame: Rect.fromLTWH(f.left * sx, f.top * sy, f.width * sx, f.height * sy),
                               text: _textController(doc), textTheme: theme, anchor: spec.anchor,
                               prompt: spec.prompt)
        shape.phType = spec.phType
        shape.phIdx = spec.phIdx
        // PowerPoint's placeholders shrink their text to fit.
        shape.autofit = true
        return shape
    }

    /// The scale an autofit shape's text is drawn at, as the shell measures
    /// it: not an edit of its own (the typing that needed it is).
    func setFontScale(_ shape: SlideShape, _ scale: Double) {
        guard shape.autofit, abs(shape.fontScale - scale) > 1e-6 else { return }
        shape.fontScale = scale
        revision += 1
        notifyListeners()
    }

    private func _copy(_ shape: SlideShape, offset: Double = 0) -> SlideShape {
        var st = _state(shape)
        st.id = _id()
        st.fileId = nil
        st.sourceXML = nil
        st.group = nil
        st.keptLine = nil
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

    static func darker(_ c: Color) -> Color { shade(c, 0.7) }

    /// DrawingML's `shade`: each channel scaled toward black.
    static func shade(_ c: Color, _ amount: Double) -> Color {
        let v = c.value
        let r = Int(Double((v >> 16) & 0xFF) * amount), g = Int(Double((v >> 8) & 0xFF) * amount)
        let b = Int(Double(v & 0xFF) * amount)
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
        // A field showing its new value is not an edit.
        if _updatingFields { return }
        edits += 1
        revision += 1
        notifyListeners()
    }

    private func _notify() {
        revision += 1
        notifyListeners()
    }

    /// After an edit. An open text session restarts from here, so the edit
    /// and the typing after it are separate steps.
    private var _updatingFields = false

    /// Fields show what they stand for now: a slide number follows the
    /// slide's place, a date is today's. Text typed over a field makes it
    /// text, as in PowerPoint.
    private func _updateFields() {
        _updatingFields = true
        defer { _updatingFields = false }
        for (i, slide) in slides.enumerated() {
            for shape in slide.shapes {
                guard let field = shape.field, let c = shape.text else { continue }
                var doc = c.document
                let at = doc.paragraphs.firstIndex { !$0.text.isEmpty } ?? 0
                guard doc.paragraphs.indices.contains(at) else { continue }
                let shown = doc.paragraphs[at].text
                if let last = shape.fieldShown, last != shown {
                    shape.field = nil
                    shape.fieldShown = nil
                    continue
                }
                let want = field.value(slide: i + 1)
                shape.fieldShown = want
                guard shown != want else { continue }
                let style = doc.paragraphs[at].runs.first?.style ?? CharStyle()
                doc.paragraphs[at].text = want
                doc.paragraphs[at].runs = [Run(length: want.utf16.count, style: style)]
                c.load(doc)
            }
        }
    }

    private func _changed(keepSession: Bool = false) {
        _updateFields()
        // A shape that went takes its animations with it.
        for slide in slides where !slide.animations.isEmpty {
            let ids = Set(slide.shapes.map(\.id))
            slide.animations.removeAll { !ids.contains($0.shapeId) }
        }
        if _sessionWanted && !keepSession && _session == nil {
            _session = (snapshot(), _textRevisions())
        }
        _lastTextRevisions = _textRevisions()
        revision += 1
        notifyListeners()
    }
}
