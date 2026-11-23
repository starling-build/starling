// OfficeArt (Escher): the drawing records shared by the legacy .xls drawing
// layer (MSODRAWINGGROUP / MSODRAWING) and, later, legacy .ppt slides.
// A record is an 8-byte header (version+instance, type, length) and a body; a
// container (version 0xF) holds records. No spreadsheet types in here.
//
// Shared code (also built for the web): no legacy Foundation calls.

import Foundation

struct ArtRecord {
    var ver: Int
    var inst: Int
    var type: Int
    var body: Range<Int>
    var isContainer: Bool { ver == 0xF }
}

/// A picture as stored in a file: `ext` is the file extension its bytes use.
struct ArtBlip {
    var ext: String
    var data: [UInt8]
}

/// One shape of a drawing: its id, type, the picture it shows (1-based index
/// into the picture store, 0 for none), its cell anchor and the text it holds.
struct ArtShape {
    var id = 0
    var type = 0
    var flags = 0
    var pib = 0
    var anchor: [Int]? = nil      // colL dxL rwT dyT colR dxR rwB dyB
    var props: [Int: Int] = [:]
    var name: String? = nil
}

enum OfficeArt {
    static func u16(_ b: [UInt8], _ k: Int) -> Int { k + 1 < b.count && k >= 0 ? Int(b[k]) | Int(b[k + 1]) << 8 : 0 }
    static func u32(_ b: [UInt8], _ k: Int) -> Int { u16(b, k) | u16(b, k + 2) << 16 }

    /// The records directly inside `range` (not their children).
    static func records(_ b: [UInt8], in range: Range<Int>) -> [ArtRecord] {
        var out: [ArtRecord] = []
        var p = range.lowerBound
        let end = min(range.upperBound, b.count)
        while p + 8 <= end {
            let vi = u16(b, p), type = u16(b, p + 2), len = u32(b, p + 4)
            let stop = min(end, p + 8 + len)
            out.append(ArtRecord(ver: vi & 0xF, inst: vi >> 4, type: type, body: p + 8 ..< stop))
            p = p + 8 + len
        }
        return out
    }

    /// Every picture of the drawing group's store, in order (a slot that
    /// holds no picture is nil, so indexes stay aligned).
    static func blips(group b: [UInt8]) -> [ArtBlip?] {
        var out: [ArtBlip?] = []
        func walk(_ r: Range<Int>) {
            for rec in records(b, in: r) {
                if rec.type == 0xF001 { for e in records(b, in: rec.body) { out.append(e.type == 0xF007 ? fbse(b, e) : blipRecord(b, e)) } }
                else if rec.isContainer { walk(rec.body) }
            }
        }
        walk(0 ..< b.count)
        return out
    }

    private static func fbse(_ b: [UInt8], _ e: ArtRecord) -> ArtBlip? {
        // btWin32, btMacOS, uid (16), tag, size, cRef, foDelay, unused, cbName, unused, unused, name, then the picture.
        let s = e.body.lowerBound
        let cbName = Int(b.indices.contains(s + 33) ? b[s + 33] : 0)
        let at = s + 36 + cbName
        guard at + 8 <= e.body.upperBound else { return nil }
        return blipRecord(b, ArtRecord(ver: u16(b, at) & 0xF, inst: u16(b, at) >> 4, type: u16(b, at + 2), body: at + 8 ..< min(e.body.upperBound, at + 8 + u32(b, at + 4))))
    }

    private static func blipRecord(_ b: [UInt8], _ r: ArtRecord) -> ArtBlip? {
        var p = r.body.lowerBound
        let end = r.body.upperBound
        switch r.type {
        case 0xF01D, 0xF01E, 0xF02A, 0xF029:     // JPEG, PNG, JPEG (CMYK), TIFF: uid, [uid2], tag, data
            let two = [0x46B, 0x6E3, 0x6E1, 0x6E5, 0x7A9, 0x3D5].contains(r.inst)
            p += two ? 33 : 17
            guard p < end else { return nil }
            return ArtBlip(ext: r.type == 0xF01E ? "png" : r.type == 0xF029 ? "tiff" : "jpeg", data: Array(b[p ..< end]))
        case 0xF01F:                              // DIB: no file header, so one is put in front
            p += r.inst == 0x7A9 ? 33 : 17
            guard p + 16 <= end else { return nil }
            let dib = Array(b[p ..< end])
            let hdr = u32(dib, 0)
            let colors = hdr >= 36 ? u32(dib, 32) : 0
            let off = 14 + hdr + (dib.count > 14 + hdr && u16(dib, 14) <= 8 ? 4 * (colors > 0 ? colors : 1 << u16(dib, 14)) : 0)
            var f: [UInt8] = [0x42, 0x4D]
            for v in [14 + dib.count, 0, off] { f += [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24 & 255)] }
            return ArtBlip(ext: "bmp", data: f + dib)
        case 0xF01A, 0xF01B, 0xF01C:              // EMF, WMF, PICT: uid, [uid2], a 34-byte header, then the (deflated) data
            let two = [0x3D5, 0x217, 0x543].contains(r.inst)
            p += two ? 32 : 16
            guard p + 34 <= end else { return nil }
            let compressed = b[p + 32] == 0
            let size = u32(b, p)
            p += 34
            guard p < end else { return nil }
            var data = Array(b[p ..< end])
            if compressed {
                guard data.count > 2, let d = try? Zip.inflate(Data(data[2...]), expected: size) else { return nil }
                data = [UInt8](d)
            }
            return ArtBlip(ext: r.type == 0xF01A ? "emf" : r.type == 0xF01B ? "wmf" : "pict", data: data)
        default: return nil
        }
    }

    /// The shapes of a sheet's drawing, in file order. `stream` is every
    /// MSODRAWING record of the sheet joined.
    static func shapes(drawing b: [UInt8]) -> [ArtShape] {
        var out: [ArtShape] = []
        func walk(_ r: Range<Int>) {
            for rec in records(b, in: r) where rec.isContainer {
                if rec.type == 0xF004 {
                    var s = ArtShape()
                    for c in records(b, in: rec.body) {
                        switch c.type {
                        case 0xF00A: s.type = c.inst; s.id = u32(b, c.body.lowerBound); s.flags = u32(b, c.body.lowerBound + 4)
                        case 0xF00B:
                            // Properties: id (14 bits) + flags, value; complex ones keep their data after the table.
                            let n = c.inst
                            for k in 0 ..< n {
                                let o = c.body.lowerBound + 6 * k
                                guard o + 6 <= c.body.upperBound else { break }
                                let pid = u16(b, o), v = u32(b, o + 2)
                                s.props[pid & 0x3FFF] = v
                                if pid & 0x3FFF == 0x104 { s.pib = v }
                            }
                        case 0xF010:
                            let o = c.body.lowerBound
                            if c.body.count >= 18 { s.anchor = [u16(b, o + 2), u16(b, o + 4), u16(b, o + 6), u16(b, o + 8), u16(b, o + 10), u16(b, o + 12), u16(b, o + 14), u16(b, o + 16)] }
                        default: break
                        }
                    }
                    out.append(s)
                } else { walk(rec.body) }
            }
        }
        walk(0 ..< b.count)
        return out
    }
}
