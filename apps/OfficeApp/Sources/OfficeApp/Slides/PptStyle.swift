// StyleTextPropAtom (MS-PPT 2.9.30): the paragraph and character runs of a text, each field present
// only when its mask bit is set. A field left nil is inherited from the master; it is never zero.
//
// Shared code (also built for the web): bounds-checked, never traps.

import Foundation

/// A colour as the atom stores it: r, g, b, index. Index 0xFE: the RGB is literal; 0 to 7 names a scheme colour;
/// 0xFF is "not set".
struct PptColorRef: Equatable {
    var rgb = 0
    var scheme: Int? = nil
}

struct PptParaRun {
    var count = 0
    var level = 0
    var hasBullet: Bool? = nil
    var bulletHasFont: Bool? = nil
    var bulletChar: Int? = nil
    var bulletFont: Int? = nil
    var bulletSize: Int? = nil
    var bulletColor: PptColorRef? = nil
    var align: Int? = nil
    var lineSpacing: Int? = nil
    var spaceBefore: Int? = nil
    var spaceAfter: Int? = nil
    var leftMargin: Int? = nil
    var indent: Int? = nil
    var defaultTab: Int? = nil
    var tabs: [(position: Int, type: Int)]? = nil
    var fontAlign: Int? = nil
    var textDirection: Int? = nil
}

struct PptCharRun {
    var count = 0
    var bold: Bool? = nil
    var italic: Bool? = nil
    var underline: Bool? = nil
    var shadow: Bool? = nil
    var emboss: Bool? = nil
    var font: Int? = nil
    var eastAsianFont: Int? = nil
    var symbolFont: Int? = nil
    var size: Int? = nil
    var color: PptColorRef? = nil
    var position: Int? = nil
}

enum PptStyle {
    /// A little-endian cursor that never leaves its range: past the end it reads zero and clears `ok`.
    private struct Reader {
        let b: [UInt8]
        var k: Int
        let end: Int
        var ok = true
        mutating func u16() -> Int {
            guard k + 2 <= end else { ok = false; k = end; return 0 }
            defer { k += 2 }
            return Int(b[k]) | Int(b[k + 1]) << 8
        }
        mutating func i16() -> Int { let v = u16(); return v >= 0x8000 ? v - 0x10000 : v }
        mutating func u32() -> Int { let lo = u16(); return lo | u16() << 16 }
        mutating func color() -> PptColorRef? {
            guard k + 4 <= end else { ok = false; k = end; return nil }
            defer { k += 4 }
            let r = Int(b[k]), g = Int(b[k + 1]), bl = Int(b[k + 2]), index = Int(b[k + 3])
            if index == 0xFF { return nil }
            if index == 0xFE { return PptColorRef(rgb: r << 16 | g << 8 | bl, scheme: nil) }
            return index < 8 ? PptColorRef(rgb: 0, scheme: index) : PptColorRef(rgb: r << 16 | g << 8 | bl, scheme: nil)
        }
    }

    private static func readPara(_ r: inout Reader, into p: inout PptParaRun) {
        let m = r.u32()
        let bulletFlags = m & 0xF != 0 ? r.u16() : 0
        if m & 0x1 != 0 { p.hasBullet = bulletFlags & 1 != 0 }
        if m & 0x2 != 0 { p.bulletHasFont = bulletFlags & 2 != 0 }
        if m & 0x80 != 0 { p.bulletChar = r.u16() }
        if m & 0x10 != 0 { p.bulletFont = r.u16() }
        if m & 0x40 != 0 { p.bulletSize = r.i16() }
        if m & 0x20 != 0 { p.bulletColor = r.color() }
        if m & 0x800 != 0 { p.align = r.u16() }
        if m & 0x1000 != 0 { p.lineSpacing = r.i16() }
        if m & 0x2000 != 0 { p.spaceBefore = r.i16() }
        if m & 0x4000 != 0 { p.spaceAfter = r.i16() }
        if m & 0x100 != 0 { p.leftMargin = r.i16() }
        if m & 0x400 != 0 { p.indent = r.i16() }
        if m & 0x8000 != 0 { p.defaultTab = r.u16() }
        if m & 0x10_0000 != 0 {
            let n = min(r.u16(), 32)
            var t: [(position: Int, type: Int)] = []
            for _ in 0 ..< n { let pos = r.i16(); t.append((pos, r.u16())) }
            p.tabs = t
        }
        if m & 0x1_0000 != 0 { p.fontAlign = r.u16() }
        if m & 0xE_0000 != 0 { _ = r.u16() }
        if m & 0x20_0000 != 0 { p.textDirection = r.u16() }
    }

    private static func readChar(_ r: inout Reader, into c: inout PptCharRun) {
        let m = r.u32()
        let style = m & 0x3EB7 != 0 ? r.u16() : 0
        if m & 0x1 != 0 { c.bold = style & 0x1 != 0 }
        if m & 0x2 != 0 { c.italic = style & 0x2 != 0 }
        if m & 0x4 != 0 { c.underline = style & 0x4 != 0 }
        if m & 0x10 != 0 { c.shadow = style & 0x10 != 0 }
        if m & 0x200 != 0 { c.emboss = style & 0x200 != 0 }
        if m & 0x1_0000 != 0 { c.font = r.u16() }
        if m & 0x20_0000 != 0 { c.eastAsianFont = r.u16() }
        if m & 0x40_0000 != 0 { let ansi = r.u16(); if c.font == nil { c.font = ansi } }
        if m & 0x80_0000 != 0 { c.symbolFont = r.u16() }
        if m & 0x2_0000 != 0 { c.size = r.u16() }
        if m & 0x4_0000 != 0 { c.color = r.color() }
        if m & 0x8_0000 != 0 { c.position = r.i16() }
    }

    /// The runs of a StyleTextPropAtom body for a text of `length` UTF-16 units (the runs cover `length + 1`).
    static func parse(_ b: [UInt8], in range: Range<Int>, length: Int) -> (paras: [PptParaRun], chars: [PptCharRun]) {
        var r = Reader(b: b, k: range.lowerBound, end: min(range.upperBound, b.count))
        var paras: [PptParaRun] = [], chars: [PptCharRun] = []
        var covered = 0
        while covered < length + 1, r.ok, r.k < r.end {
            var p = PptParaRun()
            p.count = r.u32()
            p.level = r.u16()
            readPara(&r, into: &p)
            guard r.ok else { break }
            paras.append(p)
            covered += p.count
            if p.count == 0 { break }
        }
        covered = 0
        while covered < length + 1, r.ok, r.k < r.end {
            var c = PptCharRun()
            c.count = r.u32()
            readChar(&r, into: &c)
            guard r.ok else { break }
            chars.append(c)
            covered += c.count
            if c.count == 0 { break }
        }
        return (paras, chars)
    }

    /// One level of a TextMasterStyleAtom: its paragraph and character exceptions, with no count or level prefix.
    struct Level {
        var para = PptParaRun()
        var char = PptCharRun()
    }

    /// A TextCFExceptionAtom body: character properties on their own (the document's defaults).
    static func parseChar(_ b: [UInt8], in range: Range<Int>) -> PptCharRun {
        var r = Reader(b: b, k: range.lowerBound, end: min(range.upperBound, b.count))
        var c = PptCharRun()
        readChar(&r, into: &c)
        return c
    }

    /// A TextMasterStyleAtom body: the levels it holds (`type` is the atom's instance; 5 and up name the level first).
    static func parseMaster(_ b: [UInt8], in range: Range<Int>, type: Int) -> [Level] {
        var r = Reader(b: b, k: range.lowerBound, end: min(range.upperBound, b.count))
        let n = min(r.u16(), 5)
        var out: [Level] = []
        for k in 0 ..< n {
            var level = Level()
            if type >= 5 { _ = r.u16() }
            readPara(&r, into: &level.para)
            readChar(&r, into: &level.char)
            guard r.ok else { break }
            level.para.level = k
            out.append(level)
        }
        return out
    }
}
