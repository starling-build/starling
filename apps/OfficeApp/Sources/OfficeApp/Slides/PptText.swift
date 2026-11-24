// Text of a legacy .ppt (MS-PPT 2.9): the text atoms that follow a TextHeaderAtom, in a slide's
// SlideListWithText or inside a shape's ClientTextbox.
//
// Shared code (also built for the web): bounds-checked, never traps.

import Foundation

struct PptTextBlock {
    /// TextHeaderAtom's text type: 0 title, 1 body, 2 notes, 4 other, 5 centre body, 6 centre title, 7 half body, 8 quarter body.
    var type = 4
    /// The text, paragraphs separated by "\r", line breaks as "\u{0B}".
    var text = ""
    /// StyleTextPropAtom's runs (empty when the block has none: the master style applies).
    var paraRuns: [PptParaRun] = []
    var charRuns: [PptCharRun] = []
    /// Field marks: text position -> DrawingML field type (the text there is the field's placeholder character).
    var fields: [Int: String] = [:]
    /// TextRulerAtom: per indent level, the left margin and indent this shape sets (master units).
    var ruler: [Int: (left: Int?, indent: Int?)] = [:]
}

enum PptText {
    static let headerType = 0x0F9F, charsType = 0x0FA0, bytesType = 0x0FA8, outlineRefType = 0x0F9E, styleType = 0x0FA1

    /// UTF-16LE (TextCharsAtom) or one byte per UTF-16 unit (TextBytesAtom: Latin-1, not a code page).
    static func decode(_ r: ArtRecord, in b: [UInt8]) -> String {
        var units: [UInt16] = []
        let lo = r.body.lowerBound, hi = min(r.body.upperBound, b.count)
        if r.type == charsType {
            var k = lo
            while k + 1 < hi { units.append(UInt16(b[k]) | UInt16(b[k + 1]) << 8); k += 2 }
        } else {
            for k in lo ..< max(lo, hi) { units.append(UInt16(b[k])) }
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// The text blocks among `records` (one per TextHeaderAtom; a text atom with no header is a block of type "other").
    /// TextRuler: a u32 mask (bit 0 level count, 1 default tab, 2 tab stops, 3-7 left margin 1-5, 8-12 indent 1-5),
    /// then the fields it names in that order, each an s16 (tab stops: a count and 4 bytes each).
    static func ruler(_ r: ArtRecord, in b: [UInt8]) -> [Int: (left: Int?, indent: Int?)] {
        let mask = OfficeArt.u32(b, r.body.lowerBound)
        var k = r.body.lowerBound + 4
        func s16() -> Int? {
            guard k + 2 <= r.body.upperBound else { return nil }
            let v = OfficeArt.u16(b, k); k += 2
            return v >= 0x8000 ? v - 0x10000 : v
        }
        if mask & 1 != 0 { _ = s16() }
        if mask & 2 != 0 { _ = s16() }
        if mask & 4 != 0 { k += 2 + 4 * max(s16() ?? 0, 0) }
        var left: [Int: Int] = [:], indent: [Int: Int] = [:]
        for n in 0 ..< 5 {
            if mask & (8 << n) != 0, let v = s16() { left[n] = v }
            if mask & (0x100 << n) != 0, let v = s16() { indent[n] = v }
        }
        var out: [Int: (left: Int?, indent: Int?)] = [:]
        for n in Set(left.keys).union(indent.keys) { out[n] = (left[n], indent[n]) }
        return out
    }

    static func blocks(_ records: [ArtRecord], in b: [UInt8]) -> [PptTextBlock] {
        var out: [PptTextBlock] = []
        var pendingType: Int? = nil
        for r in records {
            switch r.type {
            case headerType:
                pendingType = r.body.count >= 4 ? OfficeArt.u32(b, r.body.lowerBound) : 4
            case charsType, bytesType:
                out.append(PptTextBlock(type: pendingType ?? 4, text: decode(r, in: b)))
                pendingType = nil
            case 0x0FD8, 0x0FF7, 0x0FF8, 0x1015:
                // Slide number and date marks: u32 position in the text of the placeholder character.
                if !out.isEmpty, r.body.count >= 4 {
                    out[out.count - 1].fields[OfficeArt.u32(b, r.body.lowerBound)] = r.type == 0x0FD8 ? "slidenum" : "datetime1"
                }
            case 0x0FA6 where r.body.count >= 4:
                if !out.isEmpty { out[out.count - 1].ruler = ruler(r, in: b) }
            case styleType:
                if !out.isEmpty {
                    let parsed = PptStyle.parse(b, in: r.body, length: out[out.count - 1].text.utf16.count)
                    out[out.count - 1].paraRuns = parsed.paras
                    out[out.count - 1].charRuns = parsed.chars
                }
            default: break
            }
        }
        return out
    }
}
