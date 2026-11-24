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
}

enum PptText {
    static let headerType = 0x0F9F, charsType = 0x0FA0, bytesType = 0x0FA8, outlineRefType = 0x0F9E

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
            default: break
            }
        }
        return out
    }

    /// The paragraphs of a block's text: split at "\r", with line breaks ("\u{0B}") kept inside a paragraph.
    static func paragraphs(_ text: String) -> [[String]] {
        var paras = text.split(separator: "\r", omittingEmptySubsequences: false).map { p in
            p.split(separator: "\u{0B}", omittingEmptySubsequences: false).map(String.init)
        }
        // A text that ends in a paragraph mark does not hold a final empty paragraph.
        if paras.count > 1, paras.last == [""] { paras.removeLast() }
        return paras
    }
}
