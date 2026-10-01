// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// A deck to PDF: one page per slide (hidden ones left out, as a printed
/// show would), each drawn by SlidePainter into a recorded picture at one
/// pixel per point, so the page is the slide's own size in PDF points.
enum SlidesPdf {
    static func write(_ deck: DeckController, cache: SlideTextCache, to path: String, title: String) async -> Bool {
        // Pictures decode off the paint path; every one is waited for
        // first, or the page would record the grey placeholder.
        var images: [ImageAttachment] = []
        for slide in deck.slides {
            if let i = slide.background?.image { images.append(i) }
            for s in slide.shapes { if let i = s.picture { images.append(i) } }
        }
        await cache.preload(images)
        let size = deck.slideSize
        var pages: [PdfDocument.Page] = []
        for slide in deck.slides where !slide.hidden {
            let recorder = NativePictureRecorder()
            let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, size.width, size.height))
            let painter = SlidePainter(slide: slide, theme: deck.theme, slideSize: size, revision: deck.revision, cache: cache)
            painter.paint(canvas, size)
            pages.append(PdfDocument.Page(picture: recorder.endRecording(), width: size.width, height: size.height))
        }
        return PdfDocument.write(to: path, pages: pages, title: title, author: PdfExport.authorName())
    }
}

extension SlideTextCache {
    /// Decode every picture now, so a synchronous paint finds them all.
    func preload(_ images: [ImageAttachment]) async {
        for image in images where self.image(image) == nil {
            // `image(_:)` started the decode; wait for it to land.
            for _ in 0 ..< 200 {
                try? await Task.sleep(nanoseconds: 10_000_000)
                if self.image(image) != nil { break }
            }
        }
    }
}
