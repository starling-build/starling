// Embedded OpenType (.fntdata in a pptx) to a plain sfnt font.
//
// PowerPoint stores an embedded font as EOT: a header, then the font data,
// here compressed with MicroType Express (MTX, W3C Submission "MicroType
// Express (MTX) Font Format"): three LZCOMP blocks (the tables, the glyph
// push data, the glyph instructions), the outlines in a packed "CTF" form.
// This reads it from that specification and rebuilds the TrueType tables.
// Shared-code safe (no legacy Foundation): bytes and arrays only.

import Foundation

enum EmbeddedEot {
    /// The font a `.fntdata` part holds, as sfnt bytes; nil if it is not one
    /// this reads (an XOR-encrypted one, or damaged).
    static func sfnt(_ eot: Data) -> Data? {
        let d = [UInt8](eot)
        guard d.count > 82 else { return nil }
        func le32(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24 }
        let size = le32(0), fontSize = le32(4), flags = le32(12)
        guard size <= d.count, fontSize > 0, fontSize <= size else { return nil }
        var font = Array(d[(size - fontSize) ..< size])
        if flags & 0x1000_0000 != 0 { for i in 0 ..< font.count { font[i] ^= 0x50 } }
        if flags & 0x4 == 0 { return Data(font) }       // not compressed: the font itself
        var out = try? decodeMtx(font)
        if out == nil { out = nil }
        return out.map { Data($0) }
    }

    private struct Bad: Error {}

    // MARK: LZCOMP

    private final class Huffman {
        let range: Int
        var weight: [Int], up: [Int], left: [Int], right: [Int], code: [Int], symbolIndex: [Int]
        init(range: Int, training: [(Int, Int)]) {
            self.range = range
            let n = 2 * range
            weight = Array(repeating: 0, count: n)
            up = Array(repeating: 0, count: n)
            left = Array(repeating: 0, count: n)
            right = Array(repeating: 0, count: n)
            code = Array(repeating: -1, count: n)
            symbolIndex = Array(repeating: 0, count: range)
            for i in 2 ..< n { weight[i] = 1; up[i] = i / 2 }
            for i in 0 ..< range { left[i] = 2 * i; right[i] = 2 * i + 1 }
            for i in range ..< n { code[i] = i - range; symbolIndex[i - range] = i }
            var i = range - 1
            while i >= 1 { weight[i] = weight[2 * i] + weight[2 * i + 1]; i -= 1 }
            for (symbol, times) in training { for _ in 0 ..< times { update(symbolIndex[symbol]) } }
        }
        func swap(_ a: Int, _ b: Int) {
            let ua = up[a], ub = up[b]
            weight.swapAt(a, b); left.swapAt(a, b); right.swapAt(a, b); code.swapAt(a, b)
            up[a] = ua; up[b] = ub
            for x in [a, b] {
                if code[x] < 0 { up[left[x]] = x; up[right[x]] = x } else { symbolIndex[code[x]] = x }
            }
        }
        func update(_ start: Int) {
            var a = start
            while a != 1 {
                let w = weight[a]
                var b = a - 1
                if weight[b] == w {
                    while weight[b] == w { b -= 1 }
                    b += 1
                    if b > 1 { swap(a, b); a = b }
                }
                weight[a] += 1
                a = up[a]
            }
            weight[1] += 1
        }
        func read(_ bits: BitReader) throws -> Int {
            var a = 1
            while code[a] < 0 { a = try bits.bit() == 1 ? right[a] : left[a] }
            let c = code[a]
            update(a)
            return c
        }
    }

    private final class BitReader {
        let d: [UInt8]
        var pos = 0
        init(_ d: [UInt8]) { self.d = d }
        func bit() throws -> Int {
            guard pos >> 3 < d.count else { throw Bad() }
            let b = Int(d[pos >> 3] >> UInt8(7 - (pos & 7))) & 1
            pos += 1
            return b
        }
        func bits(_ n: Int) throws -> Int {
            var v = 0
            for _ in 0 ..< n { v = v << 1 | (try bit()) }
            return v
        }
    }

    private static func lzcomp(_ data: [UInt8]) throws -> [UInt8] {
        guard !data.isEmpty else { return [] }
        let br = BitReader(data)
        let runLength = try br.bit() == 1
        let outLen = try br.bits(24)
        guard outLen < 1 << 26 else { throw Bad() }
        var n = 1, distMax = 8
        while distMax < outLen { n += 1; distMax = 1 << (3 * n) }
        let dup2 = 256 + 8 * n, symbols = dup2 + 3
        let small = (0 ..< 8).map { ($0, 1) }
        let distance = Huffman(range: 8, training: small + small)
        let length = Huffman(range: 8, training: small + small)
        let sym = Huffman(range: symbols, training: [(256, 1), (257, 1), (symbols - 3, 12), (symbols - 2, 6)])
        var buf: [UInt8] = []
        buf.reserveCapacity(outLen + 7168)
        for k in 0 ..< 32 { for j in 0 ..< 96 { buf.append(UInt8(k)); buf.append(UInt8(j)) } }
        for j in 0 ..< 256 { for _ in 0 ..< 4 { buf.append(UInt8(j)) } }
        let pre = buf.count
        while buf.count - pre < outLen {
            let s = try sym.read(br)
            if s < 256 {
                buf.append(UInt8(s))
            } else if s >= dup2 {
                let back = 2 * (s - dup2 + 1)
                guard buf.count >= back else { throw Bad() }
                buf.append(buf[buf.count - back])
            } else {
                let d = s - 256
                let ranges = d / 8 + 1
                var chunk = d % 8, len = 0
                while true {
                    let stop = chunk & 4 == 0
                    len = len << 2 | (chunk & 3)
                    if stop { break }
                    chunk = try length.read(br)
                }
                len += 2
                var v = 0
                for _ in 0 ..< ranges { v = v << 3 | (try distance.read(br)) }
                let dist = v + 1
                if dist >= 512 { len += 1 }
                let start = buf.count - dist - len + 1
                guard start >= 0 else { throw Bad() }
                for i in 0 ..< len { buf.append(buf[start + i]) }
            }
        }
        let out = Array(buf[pre ..< pre + outLen])
        guard runLength else { return out }
        guard let escape = out.first else { return [] }
        var result: [UInt8] = []
        var i = 1
        while i < out.count {
            let b = out[i]
            i += 1
            if b == escape {
                guard i < out.count else { throw Bad() }
                let c = Int(out[i])
                i += 1
                if c == 0 { result.append(escape) } else {
                    guard i < out.count else { throw Bad() }
                    result.append(contentsOf: repeatElement(out[i], count: c))
                    i += 1
                }
            } else { result.append(b) }
        }
        return result
    }

    // MARK: CTF

    private struct Stream {
        let d: [UInt8]
        var p = 0
        init(_ d: [UInt8]) { self.d = d }
        mutating func u8() throws -> Int { guard p < d.count else { throw Bad() }; p += 1; return Int(d[p - 1]) }
        mutating func u16() throws -> Int { let a = try u8(); return a << 8 | (try u8()) }
        mutating func s16() throws -> Int { let v = try u16(); return v >= 0x8000 ? v - 0x10000 : v }
        mutating func take(_ n: Int) throws -> [UInt8] {
            guard n >= 0, p + n <= d.count else { throw Bad() }
            p += n
            return Array(d[p - n ..< p])
        }
        mutating func u255() throws -> Int {
            let b = try u8()
            if b < 253 { return b }
            if b == 253 { return try u16() }
            if b == 254 { return 506 + (try u8()) }
            return 253 + (try u8())
        }
        mutating func s255() throws -> Int {
            var negative = false
            var b = try u8()
            while b == 250 { negative.toggle(); b = try u8() }
            let v: Int
            switch b {
            case 253: v = try u16()
            case 255: v = 250 + (try u8())
            case 254: v = 500 + (try u8())
            default: v = b
            }
            return negative ? -v : v
        }
    }

    private static func pushValues(_ s: inout Stream, _ count: Int) throws -> [Int] {
        var vals: [Int] = []
        while vals.count < count {
            guard s.p < s.d.count else { throw Bad() }
            let b = s.d[s.p]
            if b == 251 {
                s.p += 1
                guard vals.count >= 2 else { throw Bad() }
                let a = vals[vals.count - 2]
                vals += [a, try s.s255(), a]
            } else if b == 252 {
                s.p += 1
                guard vals.count >= 2 else { throw Bad() }
                let a = vals[vals.count - 2]
                let x2 = try s.s255(), x3 = try s.s255()
                vals += [a, x2, a, x3, a]
            } else { vals.append(try s.s255()) }
        }
        return vals
    }

    private static func pushProgram(_ vals: [Int]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < vals.count {
            let isByte = (0 ... 255).contains(vals[i])
            var j = i
            while j < vals.count, j - i < 255, (0 ... 255).contains(vals[j]) == isByte { j += 1 }
            let n = j - i
            if isByte {
                if n <= 8 { out.append(UInt8(0xB0 + n - 1)) } else { out += [0x40, UInt8(n)] }
                for v in vals[i ..< j] { out.append(UInt8(v)) }
            } else {
                if n <= 8 { out.append(UInt8(0xB8 + n - 1)) } else { out += [0x41, UInt8(n)] }
                for v in vals[i ..< j] { out.append(UInt8((v >> 8) & 255)); out.append(UInt8(v & 255)) }
            }
            i = j
        }
        return out
    }

    /// One coordinate triplet's index to (extra bytes, how the value splits).
    private static func triplet(_ index: Int, _ value: Int) -> (Int, Int) {
        func sign(_ c: Int) -> (Int, Int) { (c & 1 != 0 ? 1 : -1, c & 2 != 0 ? 1 : -1) }
        switch index {
        case 0 ..< 10:
            return (0, (index & 1 != 0 ? 1 : -1) * (256 * (index >> 1) + value))
        case 10 ..< 20:
            return ((index & 1 != 0 ? 1 : -1) * (256 * ((index - 10) >> 1) + value), 0)
        case 20 ..< 84:
            let i = index - 20, a = i / 16, b = (i / 4) % 4
            let (sx, sy) = sign(i % 4)
            return (sx * ((value >> 4) + 1 + 16 * a), sy * ((value & 15) + 1 + 16 * b))
        case 84 ..< 120:
            let i = index - 84, a = i / 12, b = (i / 4) % 3
            let (sx, sy) = sign(i % 4)
            return (sx * ((value >> 8) + 1 + 256 * a), sy * ((value & 255) + 1 + 256 * b))
        case 120 ..< 124:
            let (sx, sy) = sign(index - 120)
            return (sx * (value >> 12), sy * (value & 0xFFF))
        default:
            let (sx, sy) = sign(index - 124)
            return (sx * (value >> 16), sy * (value & 0xFFFF))
        }
    }

    private static func tripletBytes(_ index: Int) -> Int {
        switch index {
        case 0 ..< 84: return 1
        case 84 ..< 120: return 2
        case 120 ..< 124: return 3
        default: return 4
        }
    }

    private static func be16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 255), UInt8(v & 255)] }
    private static func be32(_ v: Int) -> [UInt8] { [UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }

    private static func decodeMtx(_ fd: [UInt8]) throws -> [UInt8] {
        guard fd.count > 10, fd[0] > 0 else { throw Bad() }
        let o2 = Int(fd[4]) << 16 | Int(fd[5]) << 8 | Int(fd[6])
        let o3 = Int(fd[7]) << 16 | Int(fd[8]) << 8 | Int(fd[9])
        guard 10 <= o2, o2 <= o3, o3 <= fd.count else { throw Bad() }
        let b1 = try lzcomp(Array(fd[10 ..< o2]))
        let b2 = try lzcomp(Array(fd[o2 ..< o3]))
        let b3 = try lzcomp(Array(fd[o3...]))
        guard b1.count > 12 else { throw Bad() }
        let tag = Array(b1[0 ..< 4])
        let tableCount = Int(b1[4]) << 8 | Int(b1[5])
        guard b1.count >= 12 + 16 * tableCount else { throw Bad() }
        var order: [String] = []
        var spans: [String: (Int, Int)] = [:]
        func be(_ o: Int) -> Int { Int(b1[o]) << 24 | Int(b1[o + 1]) << 16 | Int(b1[o + 2]) << 8 | Int(b1[o + 3]) }
        for i in 0 ..< tableCount {
            let o = 12 + 16 * i
            let name = String(decoding: b1[o ..< o + 4], as: UTF8.self)
            let off = be(o + 8), len = be(o + 12)
            guard off >= 0, len >= 0, off + len <= b1.count else { throw Bad() }
            order.append(name)
            spans[name] = (off, len)
        }
        func raw(_ n: String) -> [UInt8] { spans[n].map { Array(b1[$0.0 ..< $0.0 + $0.1]) } ?? [] }
        var tables: [String: [UInt8]] = [:]
        for n in order where !["glyf", "loca", "cvt ", "hdmx", "VDMX"].contains(n) { tables[n] = raw(n) }
        if let glyfSpan = spans["glyf"], glyfSpan.1 > 0, var head = tables["head"], head.count >= 54, let maxp = tables["maxp"], maxp.count >= 6 {
            head[50] = 0; head[51] = 1
            tables["head"] = head
            let glyphs = Int(maxp[4]) << 8 | Int(maxp[5])
            if let cvtSpan = spans["cvt "], cvtSpan.1 > 0 {
                var s = Stream(raw("cvt "))
                let n = try s.u16()
                var v = 0
                var o: [UInt8] = []
                for _ in 0 ..< n {
                    let b = try s.u8()
                    let delta: Int
                    if b < 238 { delta = b } else if b == 238 { delta = try s.s16() } else if b < 248 { delta = -(238 * (b - 239) + (try s.u8())) } else { delta = 238 * (b - 247) + (try s.u8()) }
                    v = (v + delta) & 0xFFFF
                    o += be16(v)
                }
                tables["cvt "] = o
            }
            var gs = Stream(raw("glyf")), ps = Stream(b2), cs = Stream(b3)
            var glyf: [UInt8] = []
            var loca: [Int] = []
            for _ in 0 ..< glyphs {
                loca.append(glyf.count)
                if gs.p >= gs.d.count { continue }
                var contours = try gs.s16()
                if contours == -1 {
                    let bbox = try gs.take(8)
                    var comp: [UInt8] = []
                    var more = true, instructions = false
                    while more {
                        let fl = try gs.u16(), gi = try gs.u16()
                        comp += be16(fl) + be16(gi)
                        comp += try gs.take(fl & 1 != 0 ? 4 : 2)
                        if fl & 8 != 0 { comp += try gs.take(2) } else if fl & 0x40 != 0 { comp += try gs.take(4) } else if fl & 0x80 != 0 { comp += try gs.take(8) }
                        more = fl & 0x20 != 0
                        instructions = fl & 0x100 != 0
                    }
                    var body = be16(0xFFFF) + bbox + comp
                    if instructions {
                        let pc = try gs.u255(), cc = try gs.u255()
                        let code = pushProgram(try pushValues(&ps, pc)) + (try cs.take(cc))
                        body += be16(code.count) + code
                    }
                    glyf += body
                } else {
                    var bbox: [UInt8]? = nil
                    if contours == 0x7FFF { contours = try gs.s16(); bbox = try gs.take(8) }
                    if contours <= 0 { continue }
                    var ends: [Int] = []
                    var total = -1
                    for i in 0 ..< contours {
                        let v = try gs.u255()
                        total = i == 0 ? v : total + v
                        ends.append(total)
                    }
                    let count = total + 1
                    guard count > 0, count < 70000 else { throw Bad() }
                    var flagBytes: [Int] = []
                    for _ in 0 ..< count { flagBytes.append(try gs.u8()) }
                    var x = 0, y = 0
                    var pts: [(Int, Int, Int)] = []
                    for f in flagBytes {
                        var value = 0
                        for _ in 0 ..< tripletBytes(f & 0x7F) { value = value << 8 | (try gs.u8()) }
                        let (dx, dy) = triplet(f & 0x7F, value)
                        x += dx; y += dy
                        pts.append((x, y, f & 0x80 != 0 ? 0 : 1))
                    }
                    let pc = try gs.u255(), cc = try gs.u255()
                    let code = pushProgram(try pushValues(&ps, pc)) + (try cs.take(cc))
                    func clamp(_ v: Int) -> Int { max(-32768, min(32767, v)) }
                    let box = bbox ?? (be16(clamp(pts.map { $0.0 }.min()!)) + be16(clamp(pts.map { $0.1 }.min()!))
                        + be16(clamp(pts.map { $0.0 }.max()!)) + be16(clamp(pts.map { $0.1 }.max()!)))
                    var fb: [UInt8] = [], xb: [UInt8] = [], yb: [UInt8] = []
                    var px = 0, py = 0
                    for (cx, cy, on) in pts {
                        let dx = cx - px, dy = cy - py
                        px = cx; py = cy
                        var f = on
                        if dx == 0 { f |= 0x10 } else if abs(dx) <= 255 { f |= 2 | (dx > 0 ? 0x10 : 0); xb.append(UInt8(abs(dx))) } else { xb += be16(dx & 0xFFFF) }
                        if dy == 0 { f |= 0x20 } else if abs(dy) <= 255 { f |= 4 | (dy > 0 ? 0x20 : 0); yb.append(UInt8(abs(dy))) } else { yb += be16(dy & 0xFFFF) }
                        fb.append(UInt8(f))
                    }
                    glyf += be16(contours) + box
                    for e in ends { glyf += be16(e) }
                    glyf += be16(code.count) + code + fb + xb + yb
                }
                while glyf.count % 4 != 0 { glyf.append(0) }
            }
            loca.append(glyf.count)
            tables["glyf"] = glyf
            tables["loca"] = loca.flatMap { be32($0) }
        }
        // The directory, tables in tag order.
        let names = tables.keys.sorted()
        let n = names.count
        var sr = 1, es = 0
        while sr * 2 <= n { sr *= 2; es += 1 }
        var out: [UInt8] = tag + be16(n) + be16(sr * 16) + be16(es) + be16(n * 16 - sr * 16)
        var body: [UInt8] = []
        let base = 12 + 16 * n
        for name in names {
            let t = tables[name]!
            var sum = 0
            var i = 0
            while i < t.count {
                var w = 0
                for k in 0 ..< 4 { w = w << 8 | (i + k < t.count ? Int(t[i + k]) : 0) }
                sum = (sum + w) & 0xFFFF_FFFF
                i += 4
            }
            out += Array(name.utf8) + be32(sum) + be32(base + body.count) + be32(t.count)
            body += t
            while body.count % 4 != 0 { body.append(0) }
        }
        return out + body
    }
}
