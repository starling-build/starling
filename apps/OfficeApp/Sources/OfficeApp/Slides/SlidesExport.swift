// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
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
        // (A text shadow's blur is in the PDF's units, points; see below.)
        RichTextTheme.shadowBlurDeviceScale = 1 / 20.0
        defer { RichTextTheme.shadowBlurDeviceScale = nil }
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
        guard PdfDocument.write(to: path, pages: pages, title: title, author: PdfExport.authorName()) else { return false }
        if let data = FileManager.default.contents(atPath: path), let smooth = smoothPictures(data) {
            try? smooth.write(to: URL(fileURLWithPath: path))
        }
        return true
    }

    /// The PDF with every picture marked `/Interpolate true`, as
    /// PowerPoint marks one drawn larger than its pixels: a viewer then
    /// smooths it, as the slide on screen does, where unmarked a 16-pixel
    /// icon shown an inch across is blocks (tdf93830's). Nil when the file
    /// is not laid out as the PDF backend writes it — one classic
    /// cross-reference table — and is left as it is.
    static func smoothPictures(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        let mark = Array("/Subtype /Image".utf8), add = Array("\n/Interpolate true".utf8)
        // (Not the soft mask of a grey picture: PowerPoint leaves such a
        // mask unmarked, so an enlarged grey icon's edge stays sharp
        // where its shades blend — lo-narration-non-media-shape's and
        // oox-graphic-stroke's 64-pixel grey-and-alpha logos — and marks
        // a colour picture's, tdf93830's 16-pixel icons.)
        var masks: Set<Int> = []
        let smask = Array("/SMask ".utf8)
        func number(after k0: Int) -> Int? {
            var k = k0, n = 0, digits = 0
            while k < bytes.count, (0x30 ... 0x39).contains(bytes[k]) { n = n * 10 + Int(bytes[k] - 0x30); k += 1; digits += 1 }
            return digits > 0 ? n : nil
        }
        func value(_ key: String, in dict: ArraySlice<UInt8>) -> Int? {
            let k = Array(key.utf8)
            guard let r = _find(k, in: Array(dict), from: 0) else { return nil }
            return number(after: dict.startIndex + r + k.count)
        }
        var j = 0
        while let r = _find(smask, in: bytes, from: j) {
            j = r + smask.count
            guard let mask = number(after: j) else { continue }
            // The picture's own dictionary and stream: grey when every
            // pixel's three values are one.
            guard let open = (0 ..< r).reversed().first(where: { bytes[$0] == 0x3C && bytes[$0 + 1] == 0x3C }),
                  let close = _find(Array(">>".utf8), in: bytes, from: r) else { continue }
            let dict = bytes[open ..< close]
            guard let w = value("/Width ", in: dict), let h = value("/Height ", in: dict),
                  let length = value("/Length ", in: dict),
                  let start = _find(Array("stream\n".utf8), in: bytes, from: close).map({ $0 + 7 }),
                  start + length <= bytes.count, length > 2, w > 0, h > 0, w * h <= 4_000_000 else { continue }
            guard let pixels = try? Zip.inflate(Data(bytes[(start + 2) ..< (start + length)]), expected: w * h * 3),
                  pixels.count >= w * h * 3 else { continue }
            let grey = pixels.withUnsafeBytes { (b: UnsafeRawBufferPointer) -> Bool in
                for i in 0 ..< w * h where b[i * 3] != b[i * 3 + 1] || b[i * 3] != b[i * 3 + 2] { return false }
                return true
            }
            if grey { masks.insert(mask) }
        }
        /// The number of the object a byte offset lies in ("N 0 obj" before it).
        func object(before offset: Int) -> Int? {
            let obj = Array(" 0 obj".utf8)
            var k = offset - obj.count
            while k > 0 {
                if bytes[k] == 0x20, Array(bytes[k ..< k + obj.count]) == obj {
                    var b = k - 1, n = 0, scale = 1
                    while b >= 0, (0x30 ... 0x39).contains(bytes[b]) { n += Int(bytes[b] - 0x30) * scale; scale *= 10; b -= 1 }
                    return scale > 1 ? n : nil
                }
                k -= 1
            }
            return nil
        }
        var at: [Int] = []  // where each mark ends
        var i = 0
        while let r = _find(mark, in: bytes, from: i) {
            if masks.isEmpty || object(before: r).map({ !masks.contains($0) }) ?? true { at.append(r + mark.count) }
            i = r + mark.count
        }
        guard !at.isEmpty, let sx = _find(Array("startxref\n".utf8), in: bytes, from: max(0, bytes.count - 64)),
              let end = bytes[(sx + 10)...].firstIndex(of: 0x0A), let table = Int(String(decoding: bytes[(sx + 10) ..< end], as: UTF8.self)),
              table > at.last!, table + 5 < bytes.count, Array(bytes[table ..< table + 5]) == Array("xref\n".utf8)
        else { return nil }
        func moved(_ offset: Int) -> Int { offset + add.count * at.filter { $0 <= offset }.count }
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + add.count * at.count)
        var from = 0
        for a in at { out += bytes[from ..< a]; out += add; from = a }
        out += bytes[from ..< table]
        // The table: "0 N" then N twenty-byte entries, offsets moved.
        var lines = String(decoding: bytes[table ..< sx], as: UTF8.self).components(separatedBy: "\n")
        guard lines.count > 2, lines[0] == "xref" else { return nil }
        for k in 2 ..< lines.count {
            let f = lines[k].split(separator: " ")
            guard f.count == 3, f[2] == "n", let o = Int(f[0]) else { continue }
            let digits = String(moved(o))
            lines[k] = String(repeating: "0", count: max(0, 10 - digits.count)) + digits + " \(f[1]) n "
        }
        out += Array(lines.joined(separator: "\n").utf8)
        out += Array("startxref\n\(moved(table))\n%%EOF\n".utf8)
        return Data(out)
    }

    private static func _find(_ needle: [UInt8], in hay: [UInt8], from: Int) -> Int? {
        guard needle.count <= hay.count else { return nil }
        var i = from
        while i + needle.count <= hay.count {
            if hay[i] == needle[0], Array(hay[i ..< i + needle.count]) == needle { return i }
            i += 1
        }
        return nil
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
