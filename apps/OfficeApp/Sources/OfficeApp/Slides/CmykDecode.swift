import Foundation

/// A baseline (sequential Huffman) JPEG decoder for the four-component files, which the
/// image codec can only turn into RGB the naive way. Gives the ink amounts (0 to 255, 255 =
/// full ink) per pixel as C, M, Y, K, or nil for a file it does not read (progressive, arithmetic,
/// 12-bit): those stay with the codec.
enum CmykDecode {
    struct Result { var width: Int; var height: Int; var cmyk: [UInt8]; var hasICC: Bool }

    private static let zigzag: [Int] = [
        0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]

    private struct Huff {
        var maxcode = [Int](repeating: -1, count: 18), valptr = [Int](repeating: 0, count: 17), mincode = [Int](repeating: 0, count: 17)
        var vals: [UInt8] = []
        init() {}
        init(counts: [Int], vals: [UInt8]) {
            self.vals = vals
            var code = 0, k = 0
            for l in 1 ... 16 {
                valptr[l] = k; mincode[l] = code
                code += counts[l - 1]; k += counts[l - 1]
                maxcode[l] = counts[l - 1] > 0 ? code - 1 : -1
                code <<= 1
            }
        }
    }

    private struct Comp { var id = 0, h = 1, v = 1, tq = 0, td = 0, ta = 0, pred = 0; var plane: [Float] = []; var pw = 0 }

    static func decode(_ b: [UInt8]) -> Result? {
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var q = [[Int]](repeating: [Int](repeating: 1, count: 64), count: 4)
        var dc = [Huff](repeating: Huff(), count: 4), ac = [Huff](repeating: Huff(), count: 4)
        var comps: [Comp] = []
        var w = 0, h = 0, restart = 0, adobe = -1, icc = false
        var i = 2
        var scanAt = -1
        while i + 4 <= b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let m = Int(b[i + 1])
            if m == 0xFF { i += 1; continue }
            if m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7) { i += 2; continue }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            guard i + 2 + len <= b.count else { return nil }
            let p = i + 4
            switch m {
            case 0xC0, 0xC1:
                guard b[p] == 8 else { return nil }
                h = Int(b[p + 1]) << 8 | Int(b[p + 2]); w = Int(b[p + 3]) << 8 | Int(b[p + 4])
                let n = Int(b[p + 5]); guard n == 4, len >= 8 + 3 * n else { return nil }
                comps = (0 ..< n).map { k in Comp(id: Int(b[p + 6 + 3 * k]), h: Int(b[p + 7 + 3 * k] >> 4), v: Int(b[p + 7 + 3 * k] & 15), tq: Int(b[p + 8 + 3 * k]) & 3) }
            case 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF: return nil
            case 0xDB:
                var k = p
                while k < i + 2 + len {
                    let pq = Int(b[k] >> 4), t = Int(b[k] & 15) & 3; k += 1
                    for z in 0 ..< 64 {
                        if pq == 0 { q[t][zigzag[z]] = Int(b[k]); k += 1 } else { q[t][zigzag[z]] = Int(b[k]) << 8 | Int(b[k + 1]); k += 2 }
                    }
                }
            case 0xC4:
                var k = p
                while k < i + 2 + len {
                    let tc = Int(b[k] >> 4), th = Int(b[k] & 15) & 3; k += 1
                    let counts = (0 ..< 16).map { Int(b[k + $0]) }; k += 16
                    let n = counts.reduce(0, +)
                    guard k + n <= b.count else { return nil }
                    let hf = Huff(counts: counts, vals: Array(b[k ..< k + n])); k += n
                    if tc == 0 { dc[th] = hf } else { ac[th] = hf }
                }
            case 0xDD: restart = Int(b[p]) << 8 | Int(b[p + 1])
            case 0xEE: if len >= 14, b[p ..< p + 5].elementsEqual([0x41, 0x64, 0x6F, 0x62, 0x65]) { adobe = Int(b[p + 11]) }
            case 0xE2: if len >= 16, b[p ..< p + 11].elementsEqual(Array("ICC_PROFILE".utf8)) { icc = true }
            case 0xDA:
                let n = Int(b[p]); guard n == comps.count else { return nil }
                for k in 0 ..< n {
                    let cid = Int(b[p + 1 + 2 * k]), t = Int(b[p + 2 + 2 * k])
                    guard let ci = comps.firstIndex(where: { $0.id == cid }) else { return nil }
                    comps[ci].td = (t >> 4) & 3; comps[ci].ta = t & 3
                }
                scanAt = i + 2 + len
            default: break
            }
            if scanAt >= 0 { break }
            i += 2 + len
        }
        guard scanAt >= 0, w > 0, h > 0, comps.count == 4 else { return nil }
        let hmax = comps.map { $0.h }.max()!, vmax = comps.map { $0.v }.max()!
        guard comps.allSatisfy({ $0.h >= 1 && $0.v >= 1 && hmax % $0.h == 0 && vmax % $0.v == 0 }) else { return nil }
        let mx = (w + 8 * hmax - 1) / (8 * hmax), my = (h + 8 * vmax - 1) / (8 * vmax)
        for k in 0 ..< 4 { comps[k].pw = mx * comps[k].h * 8; comps[k].plane = [Float](repeating: 0, count: comps[k].pw * my * comps[k].v * 8) }

        var pos = scanAt, bitBuf = 0, bitCnt = 0, hitMarker = false
        func readBit() -> Int {
            if bitCnt == 0 {
                var byte = 0
                if pos < b.count, !hitMarker {
                    byte = Int(b[pos]); pos += 1
                    if byte == 0xFF {
                        let n = pos < b.count ? Int(b[pos]) : 0
                        if n == 0 { pos += 1 } else { hitMarker = true; pos -= 1; byte = 0 }
                    }
                }
                bitBuf = byte; bitCnt = 8
            }
            bitCnt -= 1
            return (bitBuf >> bitCnt) & 1
        }
        func receive(_ n: Int) -> Int { var v = 0; for _ in 0 ..< n { v = v << 1 | readBit() }; return v }
        func extend(_ v: Int, _ n: Int) -> Int { n == 0 ? 0 : (v < 1 << (n - 1) ? v - (1 << n) + 1 : v) }
        func decodeHuff(_ t: Huff) -> Int {
            var code = 0
            for l in 1 ... 16 {
                code = code << 1 | readBit()
                if t.maxcode[l] >= 0, code <= t.maxcode[l], code >= t.mincode[l] {
                    let k = t.valptr[l] + code - t.mincode[l]
                    return k < t.vals.count ? Int(t.vals[k]) : 0
                }
            }
            return 0
        }
        // IDCT basis.
        var cosT = [Float](repeating: 0, count: 64)
        for x in 0 ..< 8 { for u in 0 ..< 8 { cosT[x * 8 + u] = (u == 0 ? Float(1 / 2.0.squareRoot()) : 1) * Float(cos(Double(2 * x + 1) * Double(u) * Double.pi / 16)) / 2 } }
        var blk = [Float](repeating: 0, count: 64), tmp = [Float](repeating: 0, count: 64)
        var coef = [Int](repeating: 0, count: 64)

        var mcu = 0
        let total = mx * my
        while mcu < total {
            if restart > 0, mcu > 0, mcu % restart == 0 {
                bitCnt = 0; hitMarker = false
                while pos + 1 < b.count, !(b[pos] == 0xFF && b[pos + 1] >= 0xD0 && b[pos + 1] <= 0xD7) { pos += 1 }
                pos += 2
                for k in 0 ..< 4 { comps[k].pred = 0 }
            }
            let mrow = mcu / mx, mcol = mcu % mx
            for k in 0 ..< 4 {
                for by in 0 ..< comps[k].v { for bx in 0 ..< comps[k].h {
                    for z in 0 ..< 64 { coef[z] = 0 }
                    let s = decodeHuff(dc[comps[k].td])
                    comps[k].pred += extend(receive(s), s)
                    coef[0] = comps[k].pred * q[comps[k].tq][0]
                    var z = 1
                    while z < 64 {
                        let rs = decodeHuff(ac[comps[k].ta]); let r = rs >> 4, sz = rs & 15
                        if sz == 0 { if r == 15 { z += 16; continue } else { break } }
                        z += r; if z > 63 { break }
                        coef[zigzag[z]] = extend(receive(sz), sz) * q[comps[k].tq][zigzag[z]]
                        z += 1
                    }
                    for y in 0 ..< 8 { for x in 0 ..< 8 {
                        var sum: Float = 0
                        for u in 0 ..< 8 { sum += cosT[x * 8 + u] * Float(coef[y * 8 + u]) }
                        tmp[y * 8 + x] = sum
                    } }
                    for x in 0 ..< 8 { for y in 0 ..< 8 {
                        var sum: Float = 0
                        for v in 0 ..< 8 { sum += cosT[y * 8 + v] * tmp[v * 8 + x] }
                        blk[y * 8 + x] = sum + 128
                    } }
                    let ox = (mcol * comps[k].h + bx) * 8, oy = (mrow * comps[k].v + by) * 8
                    for y in 0 ..< 8 { for x in 0 ..< 8 { comps[k].plane[(oy + y) * comps[k].pw + ox + x] = blk[y * 8 + x] } }
                } }
            }
            mcu += 1
        }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        func cl(_ v: Float) -> Float { min(255, max(0, v)) }
        for y in 0 ..< h { for x in 0 ..< w {
            func at(_ k: Int) -> Float { comps[k].plane[(y * comps[k].v / vmax) * comps[k].pw + x * comps[k].h / hmax] }
            let s0 = at(0), s1 = at(1), s2 = at(2), s3 = at(3)
            var i0 = s0, i1 = s1, i2 = s2, i3 = s3
            if adobe == 2 {  // YCCK: the colour channels are YCbCr of the inks themselves
                let cb = s1 - 128, cr = s2 - 128
                i0 = cl(s0 + 1.402 * cr); i1 = cl(s0 - 0.344136 * cb - 0.714136 * cr); i2 = cl(s0 + 1.772 * cb)
                i3 = 255 - s3
            } else if adobe >= 0 {  // Adobe stores the inks inverted (255 = none)
                i0 = 255 - s0; i1 = 255 - s1; i2 = 255 - s2; i3 = 255 - s3
            }
            let o = (y * w + x) * 4
            out[o] = UInt8(cl(i0).rounded()); out[o + 1] = UInt8(cl(i1).rounded()); out[o + 2] = UInt8(cl(i2).rounded()); out[o + 3] = UInt8(cl(i3).rounded())
        } }
        return Result(width: w, height: h, cmyk: out, hasICC: icc)
    }
}
