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

    /// Paste `data` onto the slide as `pasteChoice` decides. One undo step. False when it made nothing (text is
    /// the caller's: it goes to the text being edited).
    @discardableResult func pasteOnSlide(_ data: ClipboardData?) -> Bool {
        switch pasteChoice(for: data) {
        case .shapes:
            return pasteShapes()
        case .deckShapes(let pptx):
            if let states = DeckController.shapes(fromPptx: pptx) {
                paste(states, offset: 0)
                return true
            }
            guard let png = data?.png, !png.isEmpty else { return false }
            return _pastePicture(png)
        case .picture(let png):
            return _pastePicture(png)
        case .text, .nothing:
            return false
        }
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
