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

    /// Ask the clipboard to read Slides' private flavours along with the standard ones.
    static func registerClipboardFormats() {
        for mime in [shapesMime, shapesPptxMime] where !Clipboard.readFormats.contains(mime) {
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

    /// The shapes of `shapesPptx`'s first slide, or nil when `data` is not such a deck.
    static func shapes(fromPptx data: Data) -> [ShapeState]? {
        guard let (state, _, _) = try? Pptx.read(data), let shapes = state.slides.first?.shapes, !shapes.isEmpty else { return nil }
        return shapes
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
        case .shapes, .deckShapes: way = .keepSource
        case .picture: way = .picture
        case .text: way = .textOnly
        case .nothing: return false
        }
        if paste(data!, way: way) { return true }
        // Another deck's shapes that do not read back still came with their picture.
        return way == .keepSource && paste(data!, way: .picture)
    }

    /// Whether `data` can be pasted as `way`.
    func canPaste(_ data: ClipboardData, way: SlidePasteWay) -> Bool {
        switch way {
        case .keepSource:
            return _ownShapes(data) || _otherDeckShapes(data) != nil
        case .picture:
            return data.png.flatMap { ImageAttachment.pngPixelSize($0) } != nil
        case .textOnly:
            return data.text?.isEmpty == false
        }
    }

    /// Paste `data` as `way`, in one undo step, and keep it for the Paste Options button. False when it made nothing.
    @discardableResult func paste(_ data: ClipboardData, way: SlidePasteWay) -> Bool {
        guard canPaste(data, way: way) else { return false }
        switch way {
        case .keepSource:
            if _ownShapes(data) {
                guard pasteShapes() else { return false }
            } else if let states = _otherDeckShapes(data) {
                paste(states, offset: 0)
            } else { return false }
        case .picture:
            guard let png = data.png, _pastePicture(png) else { return false }
        case .textOnly:
            addTextBox(text: data.text ?? "")
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
        undo()
        if p.way == .keepSource, _ownShapes(p.data) { _unpasteShapes() }
        paste(p.data, way: way)
    }

    /// The clipboard holds this deck's own copied shapes (its token matches).
    private func _ownShapes(_ data: ClipboardData) -> Bool {
        let token = data.custom[DeckController.shapesMime].map { String(decoding: $0, as: UTF8.self) }
        return token != nil && token == shapeClipboardToken && canPasteShapes
    }

    /// Shapes another deck window or process copied, read from their one-slide pptx.
    private func _otherDeckShapes(_ data: ClipboardData) -> [ShapeState]? {
        guard let pptx = data.custom[DeckController.shapesPptxMime], !pptx.isEmpty else { return nil }
        return DeckController.shapes(fromPptx: pptx)
    }

    private func _pastePicture(_ png: Data) -> Bool {
        guard let size = ImageAttachment.pngPixelSize(png) else { return false }
        // Pixels read as 96 per inch, the convention pictures use.
        let w = Double(size.width) * 0.75, h = Double(size.height) * 0.75
        let image = ImageAttachment(data: png, width: w, height: h, name: "Picture", naturalWidth: w, naturalHeight: h)
        addPicture(image, naturalSize: Size(w, h))
        return true
    }
}

/// The ways a paste onto a slide can be made, as PowerPoint's Paste Options button lists them (S-ED-1 step 3).
enum SlidePasteWay: CaseIterable, Equatable {
    case keepSource, picture, textOnly

    /// The Paste Options menu's entry, with PowerPoint's letter.
    var label: String {
        switch self {
        case .keepSource: return "Keep Source Formatting (K)"
        case .picture: return "Picture (U)"
        case .textOnly: return "Keep Text Only (T)"
        }
    }
    var letter: Character {
        switch self {
        case .keepSource: return "k"
        case .picture: return "u"
        case .textOnly: return "t"
        }
    }
    /// Paste Special's name for the format.
    var formatLabel: String {
        switch self {
        case .keepSource: return "Starling Slides Shapes"
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
