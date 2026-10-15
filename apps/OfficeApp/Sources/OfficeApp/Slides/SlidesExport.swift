// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// A deck to PDF: one page per slide (hidden ones left out, as a printed
/// show would), each drawn by SlidePainter into a recorded picture scaled so
/// the page is the slide's own size in PDF points.
enum SlidesPdf {
    @MainActor
    static func write(_ deck: DeckController, cache: SlideTextCache, to path: String, title: String) async -> Bool {
        // Pictures decode off the paint path; every one is waited for
        // first, or the page would record the grey placeholder.
        var images: [ImageAttachment] = []
        for slide in deck.slides {
            if let i = slide.background?.image { images.append(i) }
            if let i = slide.inheritedBackground?.image { images.append(i) }
            // (The layout's and master's shapes too, picture fills and all:
            // ArtisticEffectSample's layout logo is a box filled with one.)
            for s in slide.decorations + slide.shapes {
                if let i = s.picture { images.append(i) }
                if let i = s.fillStyle?.image { images.append(i) }
                for look in s.runLooks.joined() { if let i = look.fill?.image { images.append(i) } }
                // Picture bullets, drawn by the slide in their markers' place.
                for p in s.text?.document.paragraphs ?? [] { if let i = p.style.bulletPicture { images.append(i) } }
                for sub in s.rendered {
                    if let i = sub.picture { images.append(i) }
                    if let i = sub.fillStyle?.image { images.append(i) }
                }
            }
        }
        await cache.preload(images)
        let size = deck.slideSize
        var pages: [PdfDocument.Page] = []
        for slide in deck.slides where !slide.hidden {
            let recorder = NativePictureRecorder()
            let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, size.width, size.height))
            let painter = SlidePainter(slide: slide, theme: deck.theme, slideSize: size, revision: deck.revision, cache: cache,
                                       placeholders: false)
            // Laid out at twenty pixels a point and scaled back: the engine
            // sets a line on whole pixels, and at one a point a 12.8 pt
            // line is 13 — a third of a line astray by the foot of a body.
            // (At four, 12.6 was 12.5, and sixteen lines ended 1.6 pt high.)
            let k = 20.0
            canvas.scale(1 / k, 1 / k)
            painter.paint(canvas, Size(size.width * k, size.height * k))
            pages.append(PdfDocument.Page(picture: recorder.endRecording(), width: size.width, height: size.height))
        }
        return PdfDocument.write(to: path, pages: pages, title: title, author: PdfExport.authorName())
    }
}

extension SlideTextCache {
    /// Decode every picture now, so a synchronous paint finds them all.
    @MainActor
    func preload(_ images: [ImageAttachment]) async {
        // A metafile's own bitmaps are what there is to decode of it.
        let images = images.flatMap { metafile($0)?.bitmaps ?? [$0] }
        for image in images { await decodeNow(image) }
    }
}
