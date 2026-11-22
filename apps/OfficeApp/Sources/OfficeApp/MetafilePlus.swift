// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// EMF+ (MS-EMFPLUS): the GDI+ records an EMF carries inside EMR_COMMENT records. A "dual" file holds each
/// drawing twice, as EMF+ records and as the plain EMF records an old player draws instead; a GDI+ player draws the
/// EMF+ ones and skips the EMF ones, except those a GetDC record asks for (PowerPoint's print of 2175d386 p6: the
/// nodes' grey fill is an EMF record under ROP2 "dest AND pen" that GDI+ never plays, and the nodes print white).
///
/// This plays the records the Office pictures use (solid brushes and pens, paths, rectangles, regions as clips,
/// the world and page transforms, save and restore, driver strings) into `Metafile.Step`s in the picture's device
/// units. A file that holds a record it does not play is left to its EMF records (`EmfPlus.plays`).
struct EmfPlus {
    /// A GDI+ matrix: x' = m11·x + m21·y + dx, y' = m12·x + m22·y + dy.
    struct Matrix {
        var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0
        func apply(_ x: Double, _ y: Double) -> Offset { Offset(a * x + c * y + e, b * x + d * y + f) }
        /// `self` first, then `next`.
        func then(_ n: Matrix) -> Matrix {
            Matrix(a: a * n.a + b * n.c, b: a * n.b + b * n.d, c: c * n.a + d * n.c, d: c * n.b + d * n.d,
                   e: e * n.a + f * n.c + n.e, f: e * n.b + f * n.d + n.f)
        }
        /// The mean scale (the root of the determinant's size).
        var scale: Double { abs(a * d - b * c).squareRoot() }
    }

    struct PlusPath { var points: [Offset] = []; var types: [UInt8] = [] }
    indirect enum Region { case rect(Rect), path(PlusPath), infinite, empty, combine(Int, Region, Region) }
    struct Pen { var width = 1.0, unit = 0, color = Color(0xFF000000), solid = true, plain = true }
    struct Font { var size = 12.0, unit = 0, family = "Arial", bold = false, italic = false, underline = false }
    enum Object { case brush(Color?), pen(Pen), path(PlusPath), region(Region), font(Font), other }

    static let ident: Int64 = 0x2B46_4D45   // "EMF+"

    var dual = false
    /// A GetDC record is in force: the EMF records up to the next EMF+ record are played.
    var getDC = false
    var dpiX = 96.0, dpiY = 96.0
    var pageUnit = 2, pageScale = 1.0
    var world = Matrix()
    var objects: [Int: Object] = [:]
    var clip: Path? = nil
    var stack: [(Matrix, Path?)] = []
    var savedIndex: [Int: Int] = [:]
    /// Device units per millimetre, across and down (the EMF header's device size over its size in millimetres).
    var perMMX = 1.0, perMMY = 1.0
    var steps: [Metafile.Step] = []
    var bounds = Rect.zero

    // MARK: Reading

    /// Whether every EMF+ record in `bytes` (an EMF) is one this plays: then its EMF records are skipped but for GetDC's.
    static func plays(_ bytes: [UInt8]) -> Bool {
        func u32(_ at: Int) -> Int { at + 4 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 : 0 }
        func u16(_ at: Int) -> Int { at + 2 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : 0 }
        var p = 0, seen = false, dualFile = false
        while p + 8 <= bytes.count {
            let type = u32(p), size = u32(p + 4)
            guard size >= 8, p + size <= bytes.count else { break }
            if type == 70, size >= 16, u32(p + 12) == Int(ident) {
                var q = p + 16
                while q + 12 <= p + size {
                    let rt = u16(q), fl = u16(q + 2), sz = u32(q + 4), ds = u32(q + 8)
                    guard sz >= 12, q + sz <= p + size else { return false }
                    seen = true
                    switch rt {
                    case 0x4001: dualFile = fl & 1 == 1
                    case 0x4002, 0x4004, 0x401D...0x4024, 0x4025, 0x4026, 0x402A...0x402F, 0x4030, 0x4031...0x4034, 0x4014, 0x4015,
                         0x400A, 0x4009, 0x400C, 0x4036, 0x4003:
                        break
                    case 0x4008:
                        // An object: a brush must be solid, a pen plain, nothing an image or a custom cap.
                        let kind = (fl >> 8) & 0x7F
                        guard fl & 0x8000 == 0 else { return false }
                        switch kind {
                        case 1: if u32(q + 12 + 4) != 0 { return false }
                        case 2: if !plainPen(bytes, q + 12, ds) { return false }
                        case 3, 4, 6, 7, 8: break
                        default: return false
                        }
                    default: return false
                    }
                    q += sz
                    _ = ds
                }
            }
            p += size
        }
        return seen && dualFile
    }

    /// A pen this draws: a solid brush, no dash, no compound lines, no custom caps (a dashed line drawn solid is worse than the EMF's).
    static func plainPen(_ b: [UInt8], _ at: Int, _ ds: Int) -> Bool {
        guard let p = Self.readPen(b, at, ds) else { return false }
        return p.solid && p.plain
    }

    static func readPen(_ b: [UInt8], _ at: Int, _ ds: Int) -> Pen? {
        func u32(_ o: Int) -> Int { o + 4 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 : 0 }
        func f32(_ o: Int) -> Double { Double(Float(bitPattern: UInt32(truncatingIfNeeded: u32(o)))) }
        guard ds >= 28, at + ds <= b.count else { return nil }
        var pen = Pen()
        let flags = u32(at + 8)
        pen.unit = u32(at + 12)
        pen.width = f32(at + 16)
        var o = at + 20
        if flags & 0x1 != 0 { o += 24 }      // transform
        if flags & 0x2 != 0 { o += 4 }       // start cap
        if flags & 0x4 != 0 { o += 4 }       // end cap
        if flags & 0x8 != 0 { o += 4 }       // join
        if flags & 0x10 != 0 { o += 4 }      // miter limit
        if flags & 0x20 != 0 {               // line style: solid 0 only
            if u32(o) != 0 { pen.plain = false }
            o += 4
        }
        if flags & 0x40 != 0 { o += 4 }      // dashed line cap
        if flags & 0x80 != 0 { o += 4 }      // dash offset
        if flags & 0x100 != 0 { pen.plain = false; o += 4 + 4 * u32(o) }
        if flags & 0x200 != 0 { o += 4 }     // alignment
        if flags & 0x400 != 0 { pen.plain = false; o += 4 + 4 * u32(o) }
        if flags & 0x800 != 0 { pen.plain = false; return pen }
        if flags & 0x1000 != 0 { pen.plain = false; return pen }
        guard o + 12 <= at + ds else { return nil }
        // The pen's brush: version, type (solid 0), colour.
        if u32(o + 4) != 0 { pen.solid = false; return pen }
        pen.color = Color(Int64(u32(o + 8)))
        return pen
    }
}

// MARK: Playing

extension EmfPlus {
    private static func u32(_ b: [UInt8], _ at: Int) -> Int {
        at >= 0 && at + 4 <= b.count ? Int(b[at]) | Int(b[at + 1]) << 8 | Int(b[at + 2]) << 16 | Int(b[at + 3]) << 24 : 0
    }
    private static func i16(_ b: [UInt8], _ at: Int) -> Double {
        at >= 0 && at + 2 <= b.count ? Double(Int16(truncatingIfNeeded: Int(b[at]) | Int(b[at + 1]) << 8)) : 0
    }
    private static func f32(_ b: [UInt8], _ at: Int) -> Double { Double(Float(bitPattern: UInt32(truncatingIfNeeded: u32(b, at)))) }

    /// Device units in one `unit` (GDI+'s unit enum): the pixel is the reference device's own, the physical ones follow its size.
    func perUnit(_ unit: Int) -> Double {
        let perInch = (perMMX + perMMY) / 2 * 25.4
        switch unit {
        case 3: return perInch / 72
        case 4: return perInch
        case 5: return perInch / 300
        case 6: return perInch / 25.4
        default: return 1
        }
    }
    /// Device units per page unit: the page unit and its scale, the frame's origin.
    var pageToDevice: Matrix {
        let k = pageScale * perUnit(pageUnit)
        return Matrix(a: k, d: k, e: bounds.left, f: bounds.top)
    }
    /// World units to device units.
    var toDevice: Matrix { world.then(pageToDevice) }

    func device(_ m: Matrix, _ path: PlusPath) -> Path {
        let out = Path()
        var i = 0
        var open = false
        while i < path.points.count, i < path.types.count {
            let t = path.types[i]
            let p = m.apply(path.points[i].dx, path.points[i].dy)
            switch t & 0x0F {
            case 0:
                out.moveTo(p.dx, p.dy); open = true
            case 3 where i + 2 < path.points.count && i + 2 < path.types.count:
                let c2 = m.apply(path.points[i + 1].dx, path.points[i + 1].dy), e = m.apply(path.points[i + 2].dx, path.points[i + 2].dy)
                out.cubicTo(p.dx, p.dy, c2.dx, c2.dy, e.dx, e.dy)
                i += 2
                if path.types[i] & 0x80 != 0 { out.close() }
                i += 1
                continue
            default:
                if !open { out.moveTo(p.dx, p.dy); open = true } else { out.lineTo(p.dx, p.dy) }
            }
            if t & 0x80 != 0 { out.close() }
            i += 1
        }
        out.fillType = .evenOdd
        return out
    }

    func quad(_ m: Matrix, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
        let out = Path()
        let a = m.apply(x, y), b = m.apply(x + w, y), c = m.apply(x + w, y + h), d = m.apply(x, y + h)
        out.moveTo(a.dx, a.dy); out.lineTo(b.dx, b.dy); out.lineTo(c.dx, c.dy); out.lineTo(d.dx, d.dy); out.close()
        return out
    }

    /// A region as a device path; nil is the whole plane.
    func devicePath(_ m: Matrix, _ r: Region) -> Path? {
        switch r {
        case .infinite: return nil
        case .empty: return Path()
        case .rect(let q): return quad(m, q.left, q.top, q.width, q.height)
        case .path(let p): return device(m, p)
        case .combine(let op, let l, let rr):
            let a = devicePath(m, l), b = devicePath(m, rr)
            switch (a, b) {
            case (nil, nil): return nil
            case (nil, let y?):
                return op == 1 ? y : (op == 2 ? nil : (op == 5 ? Path.combine(.difference, Path(), y) : y))
            case (let x?, nil):
                return op == 1 ? x : (op == 2 ? nil : (op == 4 ? Path() : x))
            case (let x?, let y?):
                let o: PathOperation = op == 1 ? .intersect : op == 2 ? .union : op == 3 ? .xor : op == 4 ? .difference : .reverseDifference
                return Path.combine(o, x, y)
            }
        }
    }

    mutating func setClip(_ p: Path?) {
        clip = p
        steps.append(.clip(p))
    }

    mutating func combineClip(_ p: Path?, mode: Int) {
        switch (clip, p) {
        case (_, nil): if mode == 0 || mode == 2 { setClip(nil) }
        case (nil, let n?): if mode == 0 || mode == 1 { setClip(n) } else if mode == 5 { setClip(Path.combine(.difference, Path(), n)) }
        case (let old?, let n?):
            switch mode {
            case 0: setClip(n)
            case 1: setClip(Path.combine(.intersect, old, n))
            case 2: setClip(Path.combine(.union, old, n))
            case 3: setClip(Path.combine(.xor, old, n))
            case 4: setClip(Path.combine(.difference, old, n))
            default: setClip(Path.combine(.reverseDifference, old, n))
            }
        }
    }

    // MARK: Objects

    static func readPath(_ b: [UInt8], _ at: Int, _ end: Int) -> PlusPath {
        var out = PlusPath()
        guard at + 12 <= end else { return out }
        let n = u32(b, at + 4), flags = u32(b, at + 8)
        guard n > 0, n < 100_000 else { return out }
        let compressed = flags & 0x4000 != 0, relative = flags & 0x800 != 0
        var o = at + 12
        var x = 0.0, y = 0.0
        for _ in 0..<n {
            if compressed || relative {
                let px = i16(b, o), py = i16(b, o + 2)
                o += 4
                if relative { x += px; y += py } else { x = px; y = py }
            } else {
                x = f32(b, o); y = f32(b, o + 4); o += 8
            }
            out.points.append(Offset(x, y))
        }
        for i in 0..<n where o + i < end { out.types.append(b[o + i]) }
        return out
    }

    static func readRegion(_ b: [UInt8], _ at: Int, _ end: Int) -> Region {
        var o = at + 8   // version, node count
        func node() -> Region {
            guard o + 4 <= end else { return .empty }
            let t = u32(b, o); o += 4
            switch t {
            case 0x1000_0000:
                let r = Rect.fromLTWH(f32(b, o), f32(b, o + 4), f32(b, o + 8), f32(b, o + 12)); o += 16
                return .rect(r)
            case 0x1000_0001:
                let len = u32(b, o); o += 4
                let p = readPath(b, o, min(end, o + len)); o += len
                return .path(p)
            case 0x1000_0002: return .empty
            case 0x1000_0003: return .infinite
            default:
                let l = node(), r = node()
                return .combine(t, l, r)
            }
        }
        return node()
    }

    mutating func object(_ b: [UInt8], flags: Int, at: Int, size: Int) {
        let id = flags & 0xFF, kind = (flags >> 8) & 0x7F, end = at + size
        switch kind {
        case 1:
            objects[id] = Self.u32(b, at + 4) == 0 ? .brush(Color(Int64(Self.u32(b, at + 8)))) : .brush(nil)
        case 2:
            objects[id] = Self.readPen(b, at, size).map { .pen($0) } ?? .other
        case 3: objects[id] = .path(Self.readPath(b, at, end))
        case 4: objects[id] = .region(Self.readRegion(b, at, end))
        case 6:
            var f = Font()
            f.size = Self.f32(b, at + 4); f.unit = Self.u32(b, at + 8)
            let style = Self.u32(b, at + 12), len = Self.u32(b, at + 20)
            f.bold = style & 1 != 0; f.italic = style & 2 != 0; f.underline = style & 4 != 0
            var u: [UInt16] = []
            for i in 0..<min(len, 128) where at + 24 + 2 * i + 2 <= end { u.append(UInt16(b[at + 24 + 2 * i]) | UInt16(b[at + 25 + 2 * i]) << 8) }
            f.family = String(decoding: u, as: UTF16.self)
            objects[id] = .font(f)
        default: objects[id] = .other
        }
    }

    // MARK: Records

    /// The brush a record names: its own colour (flag bit 15) or an object's.
    func brush(_ flags: Int, _ id: Int) -> Color? {
        if flags & 0x8000 != 0 { return Color(Int64(id)) }
        if case .brush(let c)? = objects[id & 0xFF] { return c }
        return nil
    }

    mutating func fill(_ p: Path, _ c: Color?) {
        guard let c, c.a > 0.002 else { return }
        steps.append(.fill(p, c))
    }

    /// Plays one EMF+ record of an EMF's comment: `type`, `flags`, and its data at `at` for `size` bytes.
    mutating func record(_ b: [UInt8], type: Int, flags: Int, at: Int, size: Int) {
        getDC = false
        let u = { (o: Int) in Self.u32(b, at + o) }, f = { (o: Int) in Self.f32(b, at + o) }
        let end = at + size
        switch type {
        case 0x4001:
            dual = flags & 1 == 1
            dpiX = max(1, Double(u(8))); dpiY = max(1, Double(u(12)))
        case 0x4004: getDC = true
        case 0x4030: pageUnit = flags & 0xFF; pageScale = f(0)
        case 0x402A: world = Matrix(a: f(0), b: f(4), c: f(8), d: f(12), e: f(16), f: f(20))
        case 0x402B: world = Matrix()
        case 0x402C, 0x402D, 0x402E, 0x402F:
            var m = Matrix()
            switch type {
            case 0x402C: m = Matrix(a: f(0), b: f(4), c: f(8), d: f(12), e: f(16), f: f(20))
            case 0x402D: m.e = f(0); m.f = f(4)
            case 0x402E: m.a = f(0); m.d = f(4)
            default:
                let t = f(0) * .pi / 180
                m = Matrix(a: cos(t), b: sin(t), c: -sin(t), d: cos(t))
            }
            world = flags & 0x2000 != 0 ? world.then(m) : m.then(world)
        case 0x4025: stack.append((world, clip)); savedIndex[u(0)] = stack.count - 1
        case 0x4026:
            if let i = savedIndex[u(0)], i < stack.count {
                let had = clip
                (world, clip) = stack[i]
                stack.removeSubrange(i...)
                savedIndex = savedIndex.filter { $0.value < i }
                if had != nil || clip != nil { steps.append(.clip(clip)) }
            }
        case 0x4008: object(b, flags: flags, at: at, size: size)
        case 0x4031: combineClip(nil, mode: 0)
        case 0x4032:
            combineClip(quad(toDevice, f(0), f(4), f(8), f(12)), mode: (flags >> 8) & 0xF)
        case 0x4033:
            if case .path(let p)? = objects[flags & 0xFF] { combineClip(device(toDevice, p), mode: (flags >> 8) & 0xF) }
        case 0x4034:
            if case .region(let r)? = objects[flags & 0xFF] { combineClip(devicePath(toDevice, r), mode: (flags >> 8) & 0xF) }
        case 0x4009:
            fill(quad(Matrix(), bounds.left, bounds.top, bounds.width, bounds.height), Color(Int64(u(0))))
        case 0x4014:
            if case .path(let p)? = objects[flags & 0xFF] { fill(device(toDevice, p), brush(flags, u(0))) }
        case 0x4015:
            if case .path(let p)? = objects[flags & 0xFF], case .pen(let pen)? = objects[u(0) & 0xFF] {
                let m = toDevice
                steps.append(.stroke(device(m, p), pen.color, penWidth(pen)))
            }
        case 0x400A:
            let count = u(4), packed = flags & 0x4000 != 0, c = brush(flags, u(0)), m = toDevice
            var o = 8
            for _ in 0..<min(count, 100_000) {
                guard at + o + (packed ? 8 : 16) <= end else { break }
                if packed { fill(quad(m, Self.i16(b, at + o), Self.i16(b, at + o + 2), Self.i16(b, at + o + 4), Self.i16(b, at + o + 6)), c); o += 8 }
                else { fill(quad(m, f(o), f(o + 4), f(o + 8), f(o + 12)), c); o += 16 }
            }
        case 0x400C:
            let count = u(4), packed = flags & 0x4000 != 0, m = toDevice
            var pts = PlusPath(), o = 8
            for i in 0..<min(count, 100_000) {
                guard at + o + (packed ? 4 : 8) <= end else { break }
                if packed { pts.points.append(Offset(Self.i16(b, at + o), Self.i16(b, at + o + 2))); o += 4 }
                else { pts.points.append(Offset(f(o), f(o + 4))); o += 8 }
                pts.types.append(i == 0 ? 0 : 1)
            }
            if !pts.types.isEmpty { pts.types[pts.types.count - 1] |= 0x80 }
            fill(device(m, pts), brush(flags, u(0)))
        case 0x4036: driverString(b, flags: flags, at: at, size: size)
        default: break
        }
    }

    /// A pen's width in device units: world units scale with the whole transform, the others by their unit alone.
    func penWidth(_ pen: Pen) -> Double {
        pen.unit == 0 ? pen.width * toDevice.scale : pen.width * perUnit(pen.unit)
    }

    mutating func driverString(_ b: [UInt8], flags: Int, at: Int, size: Int) {
        guard case .font(let font)? = objects[flags & 0xFF], let color = brush(flags, Self.u32(b, at)) else { return }
        let options = Self.u32(b, at + 4), matrixPresent = Self.u32(b, at + 8) != 0, count = Self.u32(b, at + 12)
        guard options & 1 != 0, options & 2 == 0, count > 0, count < 10_000, at + 16 + count * 2 <= at + size else { return }
        var chars: [UInt16] = []
        for i in 0..<count { chars.append(UInt16(b[at + 16 + 2 * i]) | UInt16(b[at + 17 + 2 * i]) << 8) }
        var pts: [Offset] = []
        var o = at + 16 + count * 2
        let realized = options & 4 != 0
        for _ in 0..<(realized ? 1 : count) {
            guard o + 8 <= at + size else { return }
            pts.append(Offset(Self.f32(b, o), Self.f32(b, o + 4))); o += 8
        }
        var m = toDevice
        if matrixPresent, o + 24 <= at + size {
            m = Matrix(a: Self.f32(b, o), b: Self.f32(b, o + 4), c: Self.f32(b, o + 8), d: Self.f32(b, o + 12), e: Self.f32(b, o + 16), f: Self.f32(b, o + 20)).then(m)
        }
        // The em: world units under the world transform, any other unit by itself.
        let em = font.unit == 0 ? font.size * m.scale : font.size * perUnit(font.unit)
        let angle = atan2(m.b, m.a)
        func run(_ s: String, _ p: Offset) {
            guard !s.allSatisfy({ $0 == " " || $0 == "\0" }) else { return }
            let d = m.apply(p.dx, p.dy)
            steps.append(.text(Metafile.TextRun(text: s, at: d, size: em, face: font.family, bold: font.bold, italic: font.italic,
                                                underline: font.underline, color: color, align: 24, angle: angle)))
        }
        if realized { run(String(decoding: chars, as: UTF16.self), pts[0]) }
        else { for (c, p) in zip(chars, pts) { run(String(decoding: [c], as: UTF16.self), p) } }
    }
}
