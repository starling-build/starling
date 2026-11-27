import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// S-ED-1 step 2: shapes on the system clipboard.
///
/// A copy of shapes puts three flavours there at once: their text (for any text field), a PNG of them (for any app
/// that takes a picture, and for another deck), and `shapesMime` holding a token for this deck's copy. The shapes
/// themselves stay in the deck (`shapeClipboard`): a picture names an image the deck holds, so the shapes paste back
/// as shapes only into the deck they came from. A paste takes the best flavour it can: this deck's shapes, then the
/// picture, then the text. A copy made anywhere since replaces the token, so a paste never brings back stale shapes.
extension DeckController {
    static let shapesMime = "application/x-starling-slides-shapes"

    private nonisolated(unsafe) static var _shapesSerial = 0
    private static let _processTag = String(UInt64.random(in: 1 ... UInt64.max), radix: 36)

    static func nextShapesToken() -> String {
        _shapesSerial += 1
        return "slides:\(_processTag):\(_shapesSerial)"
    }

    /// The selection as clipboard flavours: the text of its shapes, a picture of it, and `token`.
    func shapesClipboardData(token: String) -> ClipboardData {
        let text = selection.compactMap { $0.text?.document.plainText() }.filter { !$0.isEmpty }.joined(separator: "\n")
        return ClipboardData(text: text, png: selectionPng(), custom: [DeckController.shapesMime: Data(token.utf8)])
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

    enum ClipboardPaste: Equatable { case shapes, picture(Data), text(String), nothing }

    /// What a paste onto the slide makes of `data`: this deck's shapes when the token is this deck's last copy;
    /// otherwise a picture when there is one and either no text or shapes copied elsewhere (their text is only
    /// a stand-in); otherwise the text.
    func pasteChoice(for data: ClipboardData?) -> ClipboardPaste {
        guard let data else { return .nothing }
        let token = data.custom[DeckController.shapesMime].map { String(decoding: $0, as: UTF8.self) }
        if let token, token == shapeClipboardToken, canPasteShapes { return .shapes }
        let text = data.text ?? ""
        if let png = data.png, !png.isEmpty, text.isEmpty || token != nil { return .picture(png) }
        return text.isEmpty ? .nothing : .text(text)
    }

    /// Paste `data` onto the slide as `pasteChoice` decides. One undo step. False when it made nothing (text is
    /// the caller's: it goes to the text being edited).
    @discardableResult func pasteOnSlide(_ data: ClipboardData?) -> Bool {
        switch pasteChoice(for: data) {
        case .shapes:
            return pasteShapes()
        case .picture(let png):
            guard let size = ImageAttachment.pngPixelSize(png) else { return false }
            // Pixels read as 96 per inch, the convention pictures use.
            let w = Double(size.width) * 0.75, h = Double(size.height) * 0.75
            let image = ImageAttachment(data: png, width: w, height: h, name: "Picture", naturalWidth: w, naturalHeight: h)
            addPicture(image, naturalSize: Size(w, h))
            return true
        case .text, .nothing:
            return false
        }
    }
}
