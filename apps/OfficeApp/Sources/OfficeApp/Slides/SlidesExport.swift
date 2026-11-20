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
        if let data = FileManager.default.contents(atPath: path), let exact = exactPageSize(data, width: size.width, height: size.height) {
            try? exact.write(to: URL(fileURLWithPath: path))
        }
        return true
    }

    /// The PDF with every picture that came from a JPEG marked
    /// `/Interpolate true`, as PowerPoint for Windows marks them (a picture
    /// from a PNG it marks false: lo-tdf146223's 2-pixel background is four
    /// blocks there, tdf93830's 16-pixel icon too): a viewer then smooths it. Nil when the file
    /// is not laid out as the PDF backend writes it — one classic
    /// cross-reference table — and is left as it is.
    static func smoothPictures(_ data: Data, jpeg jpegSizes: Set<UInt64> = SlideTextCache.jpegSizes, otherSizes: Set<UInt64> = []) -> Data? {
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
        let jpeg = jpegSizes
        while let r = _find(mark, in: bytes, from: i) {
            // (A picture with an alpha channel is not the JPEG: PowerPoint
            // writes one made so as false.)
            if let open = (0 ..< r).reversed().first(where: { bytes[$0] == 0x3C && bytes[$0 + 1] == 0x3C }),
               let close = _find(Array(">>".utf8), in: bytes, from: r),
               let w = value("/Width ", in: bytes[open ..< close]), let h = value("/Height ", in: bytes[open ..< close]),
               !jpeg.contains(UInt64(w) << 32 | UInt64(h)) || (_find(smask, in: Array(bytes[open ..< close]), from: 0) != nil && !SlideTextCache.alphaSmooth.contains(UInt64(w) << 32 | UInt64(h)))
                || (otherSizes.contains(UInt64(w) << 32 | UInt64(h)) && !_isGrey(bytes, dict: bytes[open ..< close], close: close, value: { value($0, in: $1) })) {
                i = r + mark.count
                continue
            }
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

    /// The PDF with every page's size as PowerPoint writes it: the slide's size
    /// in twelfths of a point of 1/600 inch (round(EMU / 1524) x 0.12 pt:
    /// 10077450 EMU is 793.56 pt, where Skia writes the whole point, 794).
    /// A page of another size is scored stretched against PowerPoint's, and a
    /// tiled background drifts across it. Nil when nothing changes or the file
    /// is not one classic cross-reference table.
    static func exactPageSize(_ data: Data, width: Double, height: Double) -> Data? {
        func units(_ pt: Double) -> Double { (pt * 12700 / 1524).rounded() * 0.12 }
        func text(_ v: Double) -> String {
            var t = String(Int((v * 100).rounded()))
            while t.count < 3 { t = "0" + t }
            let whole = String(t.dropLast(2)), frac = String(t.suffix(2))
            return frac == "00" ? whole : frac.hasSuffix("0") ? "\(whole).\(frac.prefix(1))" : "\(whole).\(frac)"
        }
        let bytes = [UInt8](data)
        let key = Array("/MediaBox [0 0 ".utf8)
        // (Skia lays a page's content from its foot, upward from the whole-point
        // height it wrote; the top edge stays there and the foot moves up.)
        var spans: [(Int, Int, [UInt8])] = []
        var i = 0
        while let r = _find(key, in: bytes, from: i) {
            guard let close = bytes[r...].firstIndex(of: 0x5D) else { return nil }
            let old = String(decoding: bytes[(r + key.count) ..< close], as: UTF8.self).split(separator: " ").compactMap { Double($0) }
            guard old.count == 2 else { return nil }
            let h = units(height)
            let new = Array("/MediaBox [0 \(text(old[1] - h)) \(text(units(width))) \(text(old[1]))]".utf8)
            if Array(bytes[r ... close]) != new { spans.append((r, close + 1, new)) }
            i = close + 1
        }
        guard !spans.isEmpty, let sx = _find(Array("startxref\n".utf8), in: bytes, from: max(0, bytes.count - 64)),
              let end = bytes[(sx + 10)...].firstIndex(of: 0x0A), let table = Int(String(decoding: bytes[(sx + 10) ..< end], as: UTF8.self)),
              table > spans.last!.1, table + 5 < bytes.count, Array(bytes[table ..< table + 5]) == Array("xref\n".utf8)
        else { return nil }
        func moved(_ offset: Int) -> Int {
            offset + spans.filter { $0.1 <= offset }.reduce(0) { $0 + $1.2.count - ($1.1 - $1.0) }
        }
        var out: [UInt8] = []
        var from = 0
        for (a, b, new) in spans { out += bytes[from ..< a]; out += new; from = b }
        out += bytes[from ..< table]
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

    /// Whether the picture whose dictionary is `dict` holds only grey pixels
    /// (a JPEG of one component, as Skia writes it: three equal channels).
    private static func _isGrey(_ bytes: [UInt8], dict: ArraySlice<UInt8>, close: Int, value: (String, ArraySlice<UInt8>) -> Int?) -> Bool {
        guard let w = value("/Width ", dict), let h = value("/Height ", dict), let length = value("/Length ", dict),
              let start = _find(Array("stream\n".utf8), in: bytes, from: close).map({ $0 + 7 }),
              start + length <= bytes.count, length > 2, w > 0, h > 0, w * h <= 4_000_000,
              let pixels = try? Zip.inflate(Data(bytes[(start + 2) ..< (start + length)]), expected: w * h * 3),
              pixels.count >= w * h * 3 else { return false }
        return pixels.withUnsafeBytes { (b: UnsafeRawBufferPointer) -> Bool in
            for i in 0 ..< w * h where b[i * 3] != b[i * 3 + 1] || b[i * 3] != b[i * 3 + 2] { return false }
            return true
        }
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
