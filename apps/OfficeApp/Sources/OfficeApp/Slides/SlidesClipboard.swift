import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// S-ED-1 step 2: shapes on the system clipboard.
///
/// A copy of shapes puts four flavours there at once: their text (for any text field), a PNG of them (for any app
/// that takes a picture), `shapesMime` holding a token for this deck's copy, and `shapesPptxMime` holding the shapes
/// themselves as a one-slide deck, pictures and all, for another deck or another window of the app. A paste takes
/// the best flavour it can: this deck's own copy (`shapeClipboard`, so a paste repeats exactly), then the shapes
/// from the one-slide deck, then the picture, then the text. A copy made anywhere since replaces them all, so a
/// paste never brings back stale shapes.
extension DeckController {
    static let shapesMime = "application/x-starling-slides-shapes"
    static let shapesPptxMime = "application/x-starling-slides-pptx"
    /// Slides copied in the thumbnail pane or the sorter: a token naming this deck's copy, and the slides
    /// themselves as a deck of their own.
    static let slidesMime = "application/x-starling-slides-slides"
    static let slidesPptxMime = "application/x-starling-slides-deck"

    /// Ask the clipboard to read Slides' private flavours along with the standard ones.
    static func registerClipboardFormats() {
        for mime in [shapesMime, shapesPptxMime, slidesMime, slidesPptxMime] where !Clipboard.readFormats.contains(mime) {
            Clipboard.readFormats.append(mime)
        }
    }

    private nonisolated(unsafe) static var _shapesSerial = 0
    private static let _processTag = String(UInt64.random(in: 1 ... UInt64.max), radix: 36)

    static func nextShapesToken() -> String {
        _shapesSerial += 1
        return "slides:\(_processTag):\(_shapesSerial)"
    }

    /// The selection as clipboard flavours: the text of its shapes, a picture of it, and `token`.
    func shapesClipboardData(token: String) -> ClipboardData {
        let text = selection.compactMap { $0.text?.document.plainText() }.filter { !$0.isEmpty }.joined(separator: "\n")
        var custom = [DeckController.shapesMime: Data(token.utf8)]
        custom[DeckController.shapesPptxMime] = shapesPptx(copySelection())
        return ClipboardData(text: text, png: selectionPng(), custom: custom)
    }

    /// `states` as a .pptx of one blank slide this deck's size, in this deck's theme.
    func shapesPptx(_ states: [ShapeState]) -> Data? {
        guard !states.isEmpty else { return nil }
        let slide = SlideState(id: 1, layout: .blank, hidden: false, notes: RichDocument(), shapes: states)
        return try? PptxWriter.write(DeckState(slides: [slide], current: 0, slideSize: slideSize), theme: theme, package: nil)
    }

    /// The shapes of `shapesPptx`'s first slide and the theme they were made in, or nil when `data` is not such a deck.
    static func shapes(fromPptx data: Data) -> (shapes: [ShapeState], theme: DeckTheme)? {
        guard let (state, theme, _) = try? Pptx.read(data), let shapes = state.slides.first?.shapes, !shapes.isEmpty else { return nil }
        return (shapes, theme)
    }

    // MARK: Slides

    /// The picked slides as clipboard flavours: their titles as text, `token`, and the slides as a deck of their
    /// own (with this deck's masters and theme, so Keep Source Formatting has them to keep).
    func slidesClipboardData(token: String) -> ClipboardData {
        let picked = selectedSlides
        let titles = picked.compactMap { i in
            slides[i].shapes.first { $0.role == .title || $0.role == .ctrTitle }?.text?.document.plainText()
        }.filter { !$0.isEmpty }
        var custom = [DeckController.slidesMime: Data(token.utf8)]
        custom[DeckController.slidesPptxMime] = slidesPptx(picked)
        return ClipboardData(text: titles.joined(separator: "\n"), custom: custom)
    }

    /// The slides at `indices` as a .pptx: the deck as a save would write it, with only those slides.
    func slidesPptx(_ indices: [Int]) -> Data? {
        var state = snapshot()
        let picked = indices.filter { state.slides.indices.contains($0) }.map { state.slides[$0] }
        guard !picked.isEmpty else { return nil }
        state.slides = picked
        state.current = 0
        state.sections = []
        state.customShows = []
        return try? PptxWriter.write(state, theme: theme, package: package, ownTemplates: ownTemplates ?? false,
                                     recolourTheme: recolourTheme ?? false)
    }

    /// Whether `data` holds slides this deck can paste: its own copy, or another deck's.
    func canPasteSlides(_ data: ClipboardData) -> Bool { _ownSlides(data) || _otherDeckSlides(data) != nil }

    /// Paste the clipboard's slides after the last picked one, in this deck's theme (PowerPoint's default). False
    /// when it holds no slides.
    @discardableResult func pasteSlides(from data: ClipboardData?) -> Bool {
        guard let data else { return false }
        return pasteSlides(data, way: .destinationTheme, at: (selectedSlides.last ?? current) + 1)
    }

    /// Paste the clipboard's slides as `way` (Use Destination Theme or Keep Source Formatting) at slide index `at`,
    /// in one undo step, and keep it for the Paste Options button.
    @discardableResult func pasteSlides(_ data: ClipboardData, way: SlidePasteWay, at: Int) -> Bool {
        guard SlidePasteWay.slideWays.contains(way) else { return false }
        let copies: [Slide]
        if _ownSlides(data) {
            // This deck's own slides are in its theme already: either way pastes them as they are.
            copies = slideClipboard.map { _cloneSlide($0) }
        } else if let (state, theme, package) = _otherDeckSlides(data) {
            copies = _foreignSlides(state, theme: theme, package: package, way: way)
        } else { return false }
        guard !copies.isEmpty else { return false }
        _insertSlides(copies, at: at)
        _lastSlidesPaste = SlidesPasteRecord(data: data, way: way, at: max(0, min(slides.count - copies.count, at)),
                                             count: copies.count, revision: revision)
        return true
    }

    /// The way the last slide paste was made, while nothing has changed since (its Paste Options button shows then).
    var slidesPasteOptions: SlidePasteWay? {
        guard let p = _lastSlidesPaste, p.revision == revision else { return nil }
        return p.way
    }

    /// The index of the last slide the last paste put in, while its Paste Options button shows.
    var lastPastedSlide: Int? {
        guard let p = _lastSlidesPaste, p.revision == revision else { return nil }
        return p.at + p.count - 1
    }

    /// Redo the last slide paste as `way`: the paste is undone and made again, so one Undo still takes it all out.
    func repasteSlides(_ way: SlidePasteWay) {
        guard let p = _lastSlidesPaste, p.revision == revision, p.way != way, SlidePasteWay.slideWays.contains(way),
              canUndo else { return }
        undo()
        pasteSlides(p.data, way: way, at: p.at)
    }

    private func _ownSlides(_ data: ClipboardData) -> Bool {
        let token = data.custom[DeckController.slidesMime].map { String(decoding: $0, as: UTF8.self) }
        return token != nil && token == slideClipboardToken && canPasteSlides
    }

    private func _otherDeckSlides(_ data: ClipboardData) -> (DeckState, DeckTheme, PptxPackage)? {
        guard let pptx = data.custom[DeckController.slidesPptxMime], !pptx.isEmpty,
              let read = try? Pptx.read(pptx), !read.0.slides.isEmpty else { return nil }
        return read
    }

    /// A picture of the selected shapes, cropped to them, at two pixels a point. A lone picture is its own PNG.
    func selectionPng() -> Data? {
        if selection.count == 1, case .picture(let image) = selection[0].kind, image.data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return image.data
        }
        guard let first = selection.first else { return nil }
        let box = selection.dropFirst().reduce(first.frame) { $0.expandToInclude($1.frame) }
        let px = 2.0
        let w = Int((box.width * px).rounded(.up)), h = Int((box.height * px).rounded(.up))
        guard w > 0, h > 0, w * h <= 64_000_000 else { return nil }
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, Double(w), Double(h)))
        canvas.translate(-box.left * px, -box.top * px)
        let cache = SlideTextCache()
        for shape in currentSlide.shapes where selection.contains(where: { $0 === shape }) {
            SlidePainter.paintShape(shape, canvas, pxPerPt: px, cache: cache, theme: theme, text: true, placeholders: false)
        }
        guard let image = recorder.endRecording().toImageSync(width: w, height: h) else { return nil }
        defer { image.dispose() }
        return try? image.toByteData(format: .png)
    }

    enum ClipboardPaste: Equatable { case shapes, deckShapes(Data), picture(Data), text(String), nothing }

    /// What a paste onto the slide makes of `data`: this deck's shapes when the token is this deck's last copy;
    /// shapes copied in another deck or window when their one-slide deck came along; otherwise a picture when
    /// there is one and the text is not text in its own right; otherwise the text.
    ///
    /// Text beside a picture is only a stand-in when there is no text in a richer form: an editor that copies text
    /// puts it as HTML or RTF too, while shapes, a screenshot or a picture from a browser bring a plain caption at
    /// most. (A copy of shapes from another Starling window comes as text and picture alone where the system
    /// clipboard keeps no private type, so it pastes as the picture, as PowerPoint pastes shapes from another app.)
    func pasteChoice(for data: ClipboardData?) -> ClipboardPaste {
        guard let data else { return .nothing }
        let token = data.custom[DeckController.shapesMime].map { String(decoding: $0, as: UTF8.self) }
        if let token, token == shapeClipboardToken, canPasteShapes { return .shapes }
        if let pptx = data.custom[DeckController.shapesPptxMime], !pptx.isEmpty { return .deckShapes(pptx) }
        let text = data.text ?? ""
        let richText = data.html != nil || data.rtf != nil
        if let png = data.png, !png.isEmpty, text.isEmpty || token != nil || !richText { return .picture(png) }
        return text.isEmpty ? .nothing : .text(text)
    }

    /// Paste `data` onto the slide as `pasteChoice` decides: shapes, a picture, or the text in a new text box. One
    /// undo step, which the Paste Options button can then redo another way. False when it made nothing.
    @discardableResult func pasteOnSlide(_ data: ClipboardData?) -> Bool {
        let way: SlidePasteWay
        switch pasteChoice(for: data) {
        case .shapes, .deckShapes: way = .destinationTheme
        case .picture: way = .picture
        case .text: way = .textOnly
        case .nothing: return false
        }
        if paste(data!, way: way) { return true }
        // Another deck's shapes that do not read back still came with their picture.
        return way == .destinationTheme && paste(data!, way: .picture)
    }

    /// Whether `data` can be pasted as `way`.
    func canPaste(_ data: ClipboardData, way: SlidePasteWay) -> Bool {
        switch way {
        case .destinationTheme, .keepSource:
            return _ownShapes(data) || _otherDeckShapes(data) != nil
        case .picture:
            return data.png.flatMap { ImageAttachment.pngPixelSize($0) } != nil
        case .textOnly:
            return data.text?.isEmpty == false
        }
    }

    /// Paste `data` as `way`, in one undo step, and keep it for the Paste Options button. False when it made nothing.
    ///
    /// A picture or the text of copied shapes goes where the shapes would have gone (`at`, else where a paste of them
    /// lands), as PowerPoint puts them; a picture or text from elsewhere goes in the middle of the slide.
    @discardableResult func paste(_ data: ClipboardData, way: SlidePasteWay, at: Rect? = nil) -> Bool {
        guard canPaste(data, way: way) else { return false }
        let place = at ?? _shapesBox(data)
        switch way {
        case .destinationTheme, .keepSource:
            if _ownShapes(data) {
                guard pasteShapes() else { return false }
            } else if let (states, source) = _otherDeckShapes(data) {
                paste(states, offset: 0)
                // Use Destination Theme: they look as if made here. Keep Source Formatting: they keep the colours
                // they had, and a theme applied later leaves them so.
                for shape in selection {
                    if way == .keepSource { shape.fillScheme = nil; shape.outlineScheme = nil }
                    else { restyleShape(shape, from: source, to: theme) }
                }
            } else { return false }
        case .picture:
            guard let png = data.png, _pastePicture(png, at: place) else { return false }
        case .textOnly:
            addTextBox(text: data.text ?? "", at: place)
        }
        _lastSlidePaste = SlidePasteRecord(data: data, way: way, revision: revision)
        return true
    }

    /// The way the last paste was made, while nothing has changed since (the Paste Options button shows then).
    var slidePasteOptions: SlidePasteWay? {
        guard let p = _lastSlidePaste, p.revision == revision else { return nil }
        return p.way
    }

    /// Whether the last paste can be redone as `way` (the menu greys the ways that cannot).
    func canRepaste(_ way: SlidePasteWay) -> Bool {
        guard let p = _lastSlidePaste, p.revision == revision else { return false }
        return canPaste(p.data, way: way)
    }

    /// Redo the last paste as `way`: the paste is undone and made again, so one Undo still takes it all out.
    func repaste(_ way: SlidePasteWay) {
        guard let p = _lastSlidePaste, p.revision == revision, p.way != way, canPaste(p.data, way: way), canUndo else { return }
        // Where the paste is now: what it is made into stays there.
        let box = selection.first.map { first in selection.dropFirst().reduce(first.frame) { $0.expandToInclude($1.frame) } }
        undo()
        if p.way == .keepSource || p.way == .destinationTheme, _ownShapes(p.data) { _unpasteShapes() }
        paste(p.data, way: way, at: box)
    }

    /// Where a paste of the shapes `data` carries would put them: this deck's own copy one cascade step further on,
    /// another deck's where they were on its slide. Nil when `data` carries no shapes.
    func _shapesBox(_ data: ClipboardData) -> Rect? {
        let frames: [Rect]
        if _ownShapes(data) {
            let step = 18 * Double(_pasteCount + 1)
            frames = shapeClipboard.map { $0.frame.shift(Offset(step, step)) }
        } else if let (states, _) = _otherDeckShapes(data) {
            frames = states.map(\.frame)
        } else { return nil }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.expandToInclude($1) }
    }

    /// The clipboard holds this deck's own copied shapes (its token matches).
    private func _ownShapes(_ data: ClipboardData) -> Bool {
        let token = data.custom[DeckController.shapesMime].map { String(decoding: $0, as: UTF8.self) }
        return token != nil && token == shapeClipboardToken && canPasteShapes
    }

    /// Shapes another deck window or process copied, read from their one-slide pptx.
    private func _otherDeckShapes(_ data: ClipboardData) -> (shapes: [ShapeState], theme: DeckTheme)? {
        guard let pptx = data.custom[DeckController.shapesPptxMime], !pptx.isEmpty else { return nil }
        return DeckController.shapes(fromPptx: pptx)
    }

    private func _pastePicture(_ png: Data, at: Rect? = nil) -> Bool {
        guard let size = ImageAttachment.pngPixelSize(png) else { return false }
        // Pixels read as 96 per inch, the convention pictures use.
        let w = Double(size.width) * 0.75, h = Double(size.height) * 0.75
        let image = ImageAttachment(data: png, width: w, height: h, name: "Picture", naturalWidth: w, naturalHeight: h)
        addPicture(image, naturalSize: Size(w, h), at: at)
        return true
    }
}

/// The ways a paste onto a slide can be made, as PowerPoint's Paste Options button lists them (S-ED-1 step 3).
enum SlidePasteWay: CaseIterable, Equatable {
    case destinationTheme, keepSource, picture, textOnly

    /// The ways a paste of whole slides offers.
    static let slideWays: [SlidePasteWay] = [.destinationTheme, .keepSource]
    /// Paste Special's formats: the shapes (in this deck's theme), a picture, the text.
    static let specialWays: [SlidePasteWay] = [.destinationTheme, .picture, .textOnly]

    /// The Paste Options menu's entry, with PowerPoint's letter.
    var label: String {
        switch self {
        case .destinationTheme: return "Use Destination Theme (H)"
        case .keepSource: return "Keep Source Formatting (K)"
        case .picture: return "Picture (U)"
        case .textOnly: return "Keep Text Only (T)"
        }
    }
    var letter: Character {
        switch self {
        case .destinationTheme: return "h"
        case .keepSource: return "k"
        case .picture: return "u"
        case .textOnly: return "t"
        }
    }
    /// Paste Special's name for the format.
    var formatLabel: String {
        switch self {
        case .destinationTheme, .keepSource: return "Starling Slides Shapes"
        case .picture: return "Picture (PNG)"
        case .textOnly: return "Unformatted Text"
        }
    }
}

/// The last paste onto a slide: what was on the clipboard, how it went in, and the deck's revision just after.
struct SlidePasteRecord {
    var data: ClipboardData
    var way: SlidePasteWay
    var revision: Int
}

/// The last paste of whole slides: what was on the clipboard, how it went in, where, and the deck's revision just after.
struct SlidesPasteRecord {
    var data: ClipboardData
    var way: SlidePasteWay
    var at: Int
    var count: Int
    var revision: Int
}
