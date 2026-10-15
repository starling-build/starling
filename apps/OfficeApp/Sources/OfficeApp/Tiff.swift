// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A TIFF's first image as a BMP file, which the image codec reads and
/// TIFF it does not: ArtisticEffectSample's slide-wide photograph is an
/// uncompressed RGBA TIFF, and was drawn as nothing.
///
/// Baseline only: 8-bit grey, RGB or RGBA (an extra sample as alpha,
/// premultiplied or not), chunky, in strips, uncompressed, PackBits or
/// LZW (with the horizontal predictor). Anything else is nil and the
/// picture stays undrawn, as before.
enum Tiff {
    static func isTiff(_ b: [UInt8]) -> Bool {
        b.count > 8 && ((b[0] == 0x49 && b[1] == 0x49 && b[2] == 42 && b[3] == 0) || (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0 && b[3] == 42))
    }

    static func bmp(_ b: [UInt8]) -> [UInt8]? {
        guard isTiff(b) else { return nil }
        let little = b[0] == 0x49
        func u16(_ o: Int) -> Int? {
            guard o >= 0, o + 2 <= b.count else { return nil }
            return little ? Int(b[o]) | Int(b[o + 1]) << 8 : Int(b[o]) << 8 | Int(b[o + 1])
        }
        func u32(_ o: Int) -> Int? {
            guard o >= 0, o + 4 <= b.count else { return nil }
            let v = little ? UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
                : UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
            return Int(v)
        }
        guard let ifd = u32(4), let count = u16(ifd), count < 1000 else { return nil }
        // Each tag's values: one or many, SHORT or LONG.
        var tags: [Int: [Int]] = [:]
        for i in 0 ..< count {
            let e = ifd + 2 + i * 12
            guard let tag = u16(e), let type = u16(e + 2), let n = u32(e + 4), n < 1 << 20 else { return nil }
            let size = type == 3 ? 2 : type == 4 ? 4 : 0
            guard size > 0 else { continue }
            let at = n * size <= 4 ? e + 8 : (u32(e + 8) ?? -1)
            var values: [Int] = []
            values.reserveCapacity(n)
            for k in 0 ..< n {
                guard let v = size == 2 ? u16(at + k * 2) : u32(at + k * 4) else { return nil }
                values.append(v)
            }
            tags[tag] = values
        }
        guard let width = tags[256]?.first, let height = tags[257]?.first, width > 0, height > 0, width * height <= 50_000_000,
              let offsets = tags[273], let lengths = tags[279], offsets.count == lengths.count else { return nil }
        let samples = tags[277]?.first ?? 1
        let bits = tags[258] ?? [1]
        let compression = tags[259]?.first ?? 1
        let photometric = tags[262]?.first ?? 1
        let predictor = tags[317]?.first ?? 1
        let rowsPerStrip = tags[278]?.first ?? height
        guard bits.allSatisfy({ $0 == 8 }), (tags[284]?.first ?? 1) == 1, [1, 5, 32773].contains(compression),
              [0, 1, 2].contains(photometric), (1 ... 4).contains(samples), rowsPerStrip > 0 else { return nil }
        let premultiplied = tags[338]?.first == 1
        let rowBytes = width * samples
        // The strips, decompressed, end to end.
        var pixels: [UInt8] = []
        pixels.reserveCapacity(rowBytes * height)
        for (offset, length) in zip(offsets, lengths) {
            guard offset >= 0, length >= 0, offset + length <= b.count else { return nil }
            let strip = Array(b[offset ..< offset + length])
            switch compression {
            case 1: pixels += strip
            case 32773: pixels += packBits(strip)
            default: pixels += lzw(strip)
            }
        }
        guard pixels.count >= rowBytes * height else { return nil }
        if predictor == 2 {
            for y in 0 ..< height {
                let row = y * rowBytes
                for x in samples ..< rowBytes { pixels[row + x] = pixels[row + x] &+ pixels[row + x - samples] }
            }
        }
        // BMP: a 108-byte V4 header, 32 bits a pixel, BGRA, rows top down.
        var out: [UInt8] = []
        let image = width * height * 4
        func le32(_ v: Int) { for k in 0 ..< 4 { out.append(UInt8(truncatingIfNeeded: v >> (8 * k))) } }
        func le16(_ v: Int) { out.append(UInt8(truncatingIfNeeded: v)); out.append(UInt8(truncatingIfNeeded: v >> 8)) }
        out += [0x42, 0x4D]; le32(14 + 108 + image); le32(0); le32(14 + 108)
        le32(108); le32(width); le32(-height); le16(1); le16(32); le32(3); le32(image); le32(2835); le32(2835); le32(0); le32(0)
        le32(0x00FF_0000); le32(0x0000_FF00); le32(0x0000_00FF); le32(Int(0xFF00_0000))
        le32(0x7352_4742)  // 'sRGB'
        for _ in 0 ..< 12 { le32(0) }
        out.reserveCapacity(out.count + image)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let p = y * rowBytes + x * samples
                var r: Int, g: Int, bl: Int, a = 255
                if samples >= 3 {
                    r = Int(pixels[p]); g = Int(pixels[p + 1]); bl = Int(pixels[p + 2])
                    if samples == 4 { a = Int(pixels[p + 3]) }
                } else {
                    let v = photometric == 0 ? 255 - Int(pixels[p]) : Int(pixels[p])
                    r = v; g = v; bl = v
                    if samples == 2 { a = Int(pixels[p + 1]) }
                }
                if premultiplied, a > 0, a < 255 {
                    r = min(255, r * 255 / a); g = min(255, g * 255 / a); bl = min(255, bl * 255 / a)
                }
                out += [UInt8(bl), UInt8(g), UInt8(r), UInt8(a)]
            }
        }
        return out
    }

    private static func packBits(_ s: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < s.count {
            let n = Int(Int8(bitPattern: s[i]))
            i += 1
            if n >= 0 {
                let end = min(s.count, i + n + 1)
                out += s[i ..< end]
                i = end
            } else if n != -128, i < s.count {
                out += [UInt8](repeating: s[i], count: 1 - n)
                i += 1
            }
        }
        return out
    }

    /// TIFF's LZW: MSB-first codes, 256 clear, 257 end, the width growing
    /// a code early.
    private static func lzw(_ s: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var table: [[UInt8]] = (0 ..< 256).map { [UInt8($0)] } + [[], []]
        var width = 9, bitPos = 0
        var previous: [UInt8]? = nil
        func next() -> Int? {
            guard bitPos + width <= s.count * 8 else { return nil }
            var v = 0
            for k in 0 ..< width {
                let bit = bitPos + k
                v = v << 1 | Int((s[bit >> 3] >> (7 - UInt8(bit & 7))) & 1)
            }
            bitPos += width
            return v
        }
        while let code = next() {
            if code == 257 { break }
            if code == 256 {
                table.removeSubrange(258...)
                width = 9
                previous = nil
                continue
            }
            let entry: [UInt8]
            if code < table.count {
                entry = table[code]
                if let p = previous { table.append(p + [entry[0]]) }
            } else if let p = previous {
                entry = p + [p[0]]
                table.append(entry)
            } else {
                break
            }
            out += entry
            previous = entry
            if table.count + 1 >= 1 << width, width < 12 { width += 1 }
        }
        return out
    }
}
