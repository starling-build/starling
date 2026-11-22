import Foundation
import Flutter
import FlutterSwiftBridge

/// A picture's pixels converted from its own RGB colour profile to sRGB, as PowerPoint does for a picture with
/// `a:alphaModFix` (lab icc-lab2: PNG and JPEG, Generic RGB and Display profiles converted, matching a
/// LittleCMS profile-to-sRGB transform within 0.3 on average; a plain picture prints its pixels raw).
/// Only matrix and curve RGB profiles are read; a profile that is sRGB itself, or any other kind, changes nothing.
enum IccConvert {
    /// The embedded profile: a PNG's `iCCP`, or a JPEG's `ICC_PROFILE` segments in order.
    static func profile(in b: [UInt8]) -> [UInt8]? {
        if Png.isPng(b) {
            var p = 8
            while p + 12 <= b.count {
                let n = Int(b[p]) << 24 | Int(b[p + 1]) << 16 | Int(b[p + 2]) << 8 | Int(b[p + 3])
                guard n >= 0, p + 12 + n <= b.count else { return nil }
                let type = String(decoding: b[p + 4 ..< p + 8], as: UTF8.self)
                if type == "iCCP" {
                    let d = Array(b[p + 8 ..< p + 8 + n])
                    guard let z = d.firstIndex(of: 0), z + 4 < d.count else { return nil }
                    return (try? Zip.inflate(Data(d[(z + 4)...]), expected: d.count * 12)).map { [UInt8]($0) }
                }
                if type == "IDAT" || type == "PLTE" { return nil }
                p += 12 + n
            }
            return nil
        }
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var parts: [Int: [UInt8]] = [:]
        var i = 2
        while i + 4 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let m = b[i + 1]
            if m == 0xFF { i += 1; continue }
            if m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7) { i += 2; continue }
            if m == 0xDA { break }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if m == 0xE2, len >= 16, i + 2 + len <= b.count, b[i + 4 ..< i + 15].elementsEqual(Array("ICC_PROFILE".utf8)) {
                parts[Int(b[i + 16])] = Array(b[(i + 18) ..< (i + 2 + len)])
            }
            i += 2 + len
        }
        guard !parts.isEmpty else { return nil }
        return parts.keys.sorted().flatMap { parts[$0]! }
    }

    private struct Matrix {
        var curves: [[Double]]      // three 256-entry tables, device value to linear
        var m: [Double]             // 3x3 row-major, linear RGB to XYZ (D50)
    }

    private static func u32(_ p: [UInt8], _ o: Int) -> Int { Int(p[o]) << 24 | Int(p[o + 1]) << 16 | Int(p[o + 2]) << 8 | Int(p[o + 3]) }
    private static func s15(_ p: [UInt8], _ o: Int) -> Double { Double(Int32(truncatingIfNeeded: u32(p, o))) / 65536 }

    private static func parse(_ p: [UInt8]) -> Matrix? {
        guard p.count > 132, String(decoding: p[16 ..< 20], as: UTF8.self) == "RGB ",
              String(decoding: p[20 ..< 24], as: UTF8.self) == "XYZ " else { return nil }
        var tags: [String: (Int, Int)] = [:]
        let n = u32(p, 128)
        guard n > 0, n < 200, 132 + 12 * n <= p.count else { return nil }
        for k in 0 ..< n {
            let o = 132 + 12 * k
            tags[String(decoding: p[o ..< o + 4], as: UTF8.self)] = (u32(p, o + 4), u32(p, o + 8))
        }
        func xyz(_ t: String) -> [Double]? {
            guard let (o, s) = tags[t], s >= 20, o + 20 <= p.count else { return nil }
            return [s15(p, o + 8), s15(p, o + 12), s15(p, o + 16)]
        }
        func curve(_ t: String) -> [Double]? {
            guard let (o, s) = tags[t], o + 12 <= p.count, s >= 12 else { return nil }
            let type = String(decoding: p[o ..< o + 4], as: UTF8.self)
            var out = [Double](repeating: 0, count: 256)
            if type == "curv" {
                let cnt = u32(p, o + 8)
                guard o + 12 + 2 * cnt <= p.count else { return nil }
                if cnt == 0 { for i in 0 ..< 256 { out[i] = Double(i) / 255 } }
                else if cnt == 1 {
                    let g = Double(Int(p[o + 12]) << 8 | Int(p[o + 13])) / 256
                    for i in 0 ..< 256 { out[i] = pow(Double(i) / 255, g) }
                } else {
                    for i in 0 ..< 256 {
                        let x = Double(i) / 255 * Double(cnt - 1)
                        let lo = min(cnt - 1, Int(x)), hi = min(cnt - 1, lo + 1), f = x - Double(lo)
                        let a = Double(Int(p[o + 12 + 2 * lo]) << 8 | Int(p[o + 13 + 2 * lo])) / 65535
                        let c = Double(Int(p[o + 12 + 2 * hi]) << 8 | Int(p[o + 13 + 2 * hi])) / 65535
                        out[i] = a + (c - a) * f
                    }
                }
                return out
            }
            if type == "para", o + 12 <= p.count {
                let ft = Int(p[o + 8]) << 8 | Int(p[o + 9])
                let cnt = [1, 3, 4, 5, 7]
                guard ft < cnt.count, o + 12 + 4 * cnt[ft] <= p.count else { return nil }
                let q = (0 ..< cnt[ft]).map { s15(p, o + 12 + 4 * $0) }
                for i in 0 ..< 256 {
                    let x = Double(i) / 255
                    var y: Double
                    switch ft {
                    case 0: y = pow(x, q[0])
                    case 1: y = x >= -q[2] / q[1] ? pow(q[1] * x + q[2], q[0]) : 0
                    case 2: y = x >= -q[2] / q[1] ? pow(q[1] * x + q[2], q[0]) + q[3] : q[3]
                    case 3: y = x >= q[4] ? pow(q[1] * x + q[2], q[0]) : q[3] * x
                    default: y = x >= q[4] ? pow(q[1] * x + q[2], q[0]) + q[5] : q[3] * x + q[6]
                    }
                    out[i] = max(0, min(1, y))
                }
                return out
            }
            return nil
        }
        guard let r = xyz("rXYZ"), let g = xyz("gXYZ"), let b = xyz("bXYZ"),
              let rc = curve("rTRC"), let gc = curve("gTRC"), let bc = curve("bTRC") else { return nil }
        return Matrix(curves: [rc, gc, bc], m: [r[0], g[0], b[0], r[1], g[1], b[1], r[2], g[2], b[2]])
    }

    /// XYZ (D50) to linear sRGB.
    private static let toSrgb: [Double] = [3.1338561, -1.6168667, -0.4906146, -0.9787684, 1.9161415, 0.0334540,
                                           0.0719453, -0.2289914, 1.4052427]
    private static let encode: [UInt8] = (0 ..< 4096).map { i in
        let v = Double(i) / 4095
        let e = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, (e * 255).rounded())))
    }

    private static func lookup(_ m: Matrix) -> (UInt8, UInt8, UInt8, UInt8) -> (UInt8, UInt8, UInt8) {
        let c = m.curves
        // The profile's whole matrix to sRGB, once.
        var t = [Double](repeating: 0, count: 9)
        for r in 0 ..< 3 { for k in 0 ..< 3 {
            t[r * 3 + k] = toSrgb[r * 3] * m.m[k] + toSrgb[r * 3 + 1] * m.m[3 + k] + toSrgb[r * 3 + 2] * m.m[6 + k]
        } }
        return { r, g, b, _ in
            let lr = c[0][Int(r)], lg = c[1][Int(g)], lb = c[2][Int(b)]
            func out(_ i: Int) -> UInt8 {
                let v = t[i * 3] * lr + t[i * 3 + 1] * lg + t[i * 3 + 2] * lb
                return encode[max(0, min(4095, Int((v * 4095).rounded())))]
            }
            return (out(0), out(1), out(2))
        }
    }

    /// The image with its pixels converted, or nil when the file has no profile this can read, the profile
    /// is sRGB already, or the pixels cannot be read back.
    @MainActor
    static func converted(_ image: Image, bytes: [UInt8]) async -> Image? {
        guard let icc = profile(in: bytes), let m = parse(icc) else { return nil }
        let f = lookup(m)
        // sRGB itself (or a profile within 2 levels of it everywhere probed) is left alone.
        let probes: [UInt8] = [0, 64, 128, 192, 255]
        var big = 0
        for r in probes { for g in probes { for b in probes {
            let o = f(r, g, b, 0)
            big = max(big, abs(Int(o.0) - Int(r)), abs(Int(o.1) - Int(g)), abs(Int(o.2) - Int(b)))
        } } }
        if big <= 2 { return nil }
        let w = image.width, h = image.height
        guard w > 0, h > 0, let data = try? image.toByteData(format: .rawStraightRgba), data.count >= w * h * 4 else { return nil }
        var px = [UInt8](data)
        var i = 0
        while i + 3 < w * h * 4 {
            let o = f(px[i], px[i + 1], px[i + 2], 0)
            let a = Int(px[i + 3])
            // (premultiplied, as the pixel format asks)
            px[i] = UInt8((Int(o.0) * a + 127) / 255); px[i + 1] = UInt8((Int(o.1) * a + 127) / 255); px[i + 2] = UInt8((Int(o.2) * a + 127) / 255)
            i += 4
        }
        return await withCheckedContinuation { (k: CheckedContinuation<Image?, Never>) in
            decodeImageFromPixels(px, width: w, height: h, format: .rgba8888, callback: { k.resume(returning: $0) })
        }
    }
}
