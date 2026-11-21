import Foundation
import Flutter
import FlutterSwiftBridge

/// A four-component (CMYK) JPEG. The codec turns it to RGB the naive way
/// (R = (1-C)(1-K)), which comes out far more saturated than PowerPoint
/// prints it: PowerPoint converts through a press profile (reds near
/// (180,49,41) where the naive result is (195,0,0)). The picture is
/// re-coloured with a linear map fitted to PowerPoint's print of such a
/// picture, anchored so white stays white.
enum CmykJpeg {
    static func isCmyk(_ b: [UInt8]) -> Bool {
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return false }
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let m = b[i + 1]
            if m == 0xFF { i += 1; continue }
            if m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7) { i += 2; continue }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if (m >= 0xC0 && m <= 0xCF) && m != 0xC4 && m != 0xC8 && m != 0xCC { return b[i + 9] == 4 }
            if m == 0xDA { return false }
            i += 2 + len
        }
        return false
    }

    /// `image` re-coloured, as a new image (nil when it cannot be).
    @MainActor
    static func recoloured(_ image: Image) async -> Image? {
        guard let data = try? image.toByteData(format: .rawRgba) else { return nil }
        let w = image.width, h = image.height
        var px = [UInt8](data)
        guard px.count >= w * h * 4 else { return nil }
        let m: [[Double]] = [[241.233, 13.82, 4.595], [47.555, 201.435, -4.324], [58.288, -12.413, 213.157]]
        func clamp(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        var b = [UInt8]()
        let row = w * 3, pad = (4 - row % 4) % 4
        let size = 54 + (row + pad) * h
        b.reserveCapacity(size)
        func u16(_ v: Int) { b += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func u32(_ v: Int) { u16(v & 0xFFFF); u16((v >> 16) & 0xFFFF) }
        b += [0x42, 0x4D]; u32(size); u32(0); u32(54)
        u32(40); u32(w); u32(h); u16(1); u16(24); u32(0); u32(size - 54); u32(2835); u32(2835); u32(0); u32(0)
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in 0 ..< w {
                let o = (y * w + x) * 4
                let d0 = Double(px[o]) / 255 - 1, d1 = Double(px[o + 1]) / 255 - 1, d2 = Double(px[o + 2]) / 255 - 1
                let r = 255 + m[0][0] * d0 + m[0][1] * d1 + m[0][2] * d2
                let g = 255 + m[1][0] * d0 + m[1][1] * d1 + m[1][2] * d2
                let bl = 255 + m[2][0] * d0 + m[2][1] * d1 + m[2][2] * d2
                b += [clamp(bl), clamp(g), clamp(r)]
            }
            b += [UInt8](repeating: 0, count: pad)
        }
        px.removeAll()
        guard let codec = try? await instantiateImageCodec(b) else { return nil }
        let out = (try? await codec.getNextFrame())?.image
        codec.dispose()
        return out
    }
}
