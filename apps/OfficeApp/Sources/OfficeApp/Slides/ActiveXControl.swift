import Foundation

// An ActiveX control on a slide (`p:controls`), the MS Forms TextBox kind.
//
// PowerPoint for Windows draws the control itself from its stored settings
// (`activeXn.bin`, an OLE compound file whose `contents` stream is MS-OFORMS'
// "MorphData" block), not the fallback picture beside it: lo-activex_textbox's
// second control is a green box with a red border and its text in the
// control's font. This reads the block (as LibreOffice's oox/ole reads it:
// a 64-bit mask of the properties that are stored, the small ones in order,
// then the pair and the strings, then the font block) and builds the shapes
// that draw it: the box, and the text.

struct ActiveXTextBox {
    var flags: UInt32 = 0x2C80_481B
    var backColor: UInt32 = 0x8000_0005
    var textColor: UInt32 = 0x8000_0008
    var borderStyle = 0
    var passwordChar = 0
    var value = ""
    var borderColor: UInt32 = 0x8000_0006
    var fontName = ""
    var fontPoints = 8.0
    /// 1 left, 2 right, 3 centre (`fmTextAlign`).
    var align = 1

    var enabled: Bool { flags & 0x2 != 0 }
    var opaque: Bool { flags & 0x8 != 0 }

    static let classID = "{8BD21D10-EC42-11CE-9E0D-00AA006002F3}"

    /// The control's settings from its `contents` stream; nil when it is not
    /// one this reads.
    init?(contents b: [UInt8]) {
        var pos = 0
        func align(_ n: Int) { pos = (pos + n - 1) / n * n }
        func take(_ n: Int, aligned: Bool = true) -> UInt64? {
            if aligned { align(n) }
            guard pos + n <= b.count else { return nil }
            var v: UInt64 = 0
            for k in 0 ..< n { v |= UInt64(b[pos + k]) << (8 * UInt64(k)) }
            pos += n
            return v
        }
        // One property block: version, size, the mask of what is stored.
        struct Block {
            var mask: UInt64
            var next: UInt64 = 1
            var end: Int
            var strings: [(String, Int)] = []
            var pairs = 0
        }
        func open(wide: Bool) -> Block? {
            pos += 2
            guard let size = take(2, aligned: false), let mask = take(wide ? 8 : 4, aligned: false) else { return nil }
            return Block(mask: mask, end: pos - (wide ? 8 : 4) + Int(size) - 2 + 2)
        }
        func has(_ blk: inout Block) -> Bool {
            let h = blk.mask & blk.next != 0
            blk.next <<= 1
            return h
        }
        guard var m = open(wide: true) else { return nil }
        // (The size field counts from after itself: mask included.)
        m.end = 4 + Int(UInt16(b[2]) | UInt16(b[3]) << 8)
        if has(&m) { flags = UInt32(truncatingIfNeeded: take(4) ?? 0) }
        if has(&m) { backColor = UInt32(truncatingIfNeeded: take(4) ?? 0) }
        if has(&m) { textColor = UInt32(truncatingIfNeeded: take(4) ?? 0) }
        if has(&m) { _ = take(4) }                                  // max length
        if has(&m) { borderStyle = Int(take(1) ?? 0) }
        if has(&m) { _ = take(1) }                                  // scroll bars
        if has(&m) { _ = take(1) }                                  // display style
        if has(&m) { _ = take(1) }                                  // mouse pointer
        let hasSize = has(&m)                                       // the size pair
        if has(&m) { passwordChar = Int(take(2) ?? 0) }
        if has(&m) { _ = take(4) }                                  // list width
        for _ in 0 ..< 3 { if has(&m) { _ = take(2) } }             // bound / text column, column count
        if has(&m) { _ = take(2) }                                  // list rows
        if has(&m) { _ = take(2) }                                  // column info count
        if has(&m) { _ = take(1) }                                  // match entry
        if has(&m) { _ = take(1) }                                  // list style
        if has(&m) { _ = take(1) }                                  // show drop button
        _ = has(&m)                                                 // undefined
        if has(&m) { _ = take(1) }                                  // drop down style
        if has(&m) { _ = take(1) }                                  // multi select
        var sizes: [(String, Int)] = []
        if has(&m) { sizes.append(("value", Int(take(4) ?? 0))) }
        if has(&m) { sizes.append(("caption", Int(take(4) ?? 0))) }
        if has(&m) { _ = take(4) }                                  // picture position
        if has(&m) { borderColor = UInt32(truncatingIfNeeded: take(4) ?? 0) }
        if has(&m) { _ = take(4) }                                  // special effect
        if has(&m) { _ = take(2, aligned: true) }                   // mouse icon (stream)
        if has(&m) { _ = take(2, aligned: true) }                   // picture (stream)
        if has(&m) { _ = take(2) }                                  // accelerator
        _ = has(&m)                                                 // undefined
        _ = has(&m)                                                 // bool
        if has(&m) { sizes.append(("group", Int(take(4) ?? 0))) }
        // The large properties, each on a four-byte boundary.
        align(4)
        if hasSize { _ = take(4); _ = take(4); align(4) }
        for (name, n) in sizes {
            let count = n & 0x7FFF_FFFF
            guard pos + count <= b.count else { return nil }
            let raw = Array(b[pos ..< pos + count])
            pos += count
            align(4)
            if name == "value" {
                if n & 0x8000_0000 != 0 { value = String(decoding: raw, as: UTF8.self) }
                else {
                    value = String(decoding: stride(from: 0, to: raw.count - 1, by: 2).map { UInt16(raw[$0]) | UInt16(raw[$0 + 1]) << 8 },
                                   as: UTF16.self)
                }
            }
        }
        pos = m.end
        // The font: name, effects, height in twips, offset, charset, pitch,
        // alignment, weight.
        if pos + 4 <= b.count, var f = open(wide: false) {
            f.end = pos
            var nameSize: Int? = nil
            if has(&f) { nameSize = Int(take(4) ?? 0) }
            if has(&f) { _ = take(4) }
            var height = 0
            if has(&f) { height = Int(take(4) ?? 0) }
            if has(&f) { _ = take(4) }
            if has(&f) { _ = take(1) }
            if has(&f) { _ = take(1) }
            if has(&f) { self.align = Int(take(1) ?? 1) }
            if has(&f) { _ = take(2) }
            align(4)
            if let n = nameSize {
                let count = n & 0x7FFF_FFFF
                if pos + count <= b.count {
                    fontName = String(decoding: b[pos ..< pos + count], as: UTF8.self)
                }
            }
            if height > 0 { fontPoints = Double(height) / 20 }
        }
    }

    /// A control colour as `RRGGBB`: a COLORREF, or a system colour.
    static func rgb(_ c: UInt32, system: [UInt32: String] = [:]) -> String {
        if c & 0x8000_0000 != 0 {
            switch c & 0xFF {
            case 5: return "FFFFFF"      // window
            case 6: return "000000"      // window frame
            case 8: return "000000"      // window text
            case 0x0F: return "F0F0F0"   // button face
            case 0x12: return "000000"   // button text
            default: return "000000"
            }
        }
        func hex(_ v: UInt32) -> String { String(format: "%02X", v & 0xFF) }
        return hex(c) + hex(c >> 8) + hex(c >> 16)
    }

    /// The shapes that draw it in a box at (x, y) of w by h points, as a
    /// shape tree. nil for a control that PowerPoint draws as its picture
    /// (a sunken or raised field with no border of its own).
    func shapeTree(x: Double, y: Double, w: Double, h: Double) -> XNode? {
        guard borderStyle == 1 else { return nil }
        let emu = Pptx.emu
        func e(_ v: Double) -> Int { Int((v * emu).rounded()) }
        // PowerPoint's border is one device pixel (0.75pt) inside the box.
        let line = 0.75
        var xml = "<p:spTree>"
        var id = 9100
        func shape(_ x: Double, _ y: Double, _ w: Double, _ h: Double, fill: String?, line: String?, text: String? = nil,
                   color: String = "000000", algn: String = "l") -> String {
            id += 1
            let fillXML = fill.map { "<a:solidFill><a:srgbClr val=\"\($0)\"/></a:solidFill>" } ?? "<a:noFill/>"
            let lnXML = line.map { "<a:ln w=\"9525\"><a:solidFill><a:srgbClr val=\"\($0)\"/></a:solidFill></a:ln>" } ?? "<a:ln><a:noFill/></a:ln>"
            var body = ""
            if let text {
                let esc = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                body = "<p:txBody><a:bodyPr wrap=\"none\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" anchor=\"t\"/><a:lstStyle/>"
                    + "<a:p><a:pPr algn=\"\(algn)\"/><a:r><a:rPr lang=\"en-US\" sz=\"\(Int((fontPoints * 100).rounded()))\">"
                    + "<a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill>"
                    + "<a:latin typeface=\"\(fontName.isEmpty ? "Arial" : fontName)\"/></a:rPr><a:t>\(esc)</a:t></a:r></a:p></p:txBody>"
            }
            return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"control\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>"
                + "<a:xfrm><a:off x=\"\(e(x))\" y=\"\(e(y))\"/><a:ext cx=\"\(e(w))\" cy=\"\(e(h))\"/></a:xfrm>"
                + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>\(fillXML)\(lnXML)</p:spPr>\(body)</p:sp>"
        }
        xml += shape(x + line / 2, y + line / 2, w - line, h - line,
                     fill: opaque ? Self.rgb(backColor) : nil, line: Self.rgb(borderColor))
        // The text: the password character for each one, where one is set.
        var shown = value
        if passwordChar > 0, let u = Unicode.Scalar(passwordChar) { shown = String(repeating: String(Character(u)), count: value.count) }
        if !shown.isEmpty {
            // Where PowerPoint stands it: 2.8pt under the top, centred 3.2pt
            // right of the middle, flush right 1.9pt in, flush left 2pt in.
            let top = y + 2.8
            let lineH = fontPoints * 1.15
            let boxX: Double, boxW = w, algnName: String
            switch align {
            case 2: boxX = x - 1.9; algnName = "r"
            case 3: boxX = x + 3.2; algnName = "ctr"
            default: boxX = x + 2; algnName = "l"
            }
            if enabled {
                xml += shape(boxX, top, boxW, lineH, fill: nil, line: nil, text: shown, color: Self.rgb(textColor), algn: algnName)
            } else {
                // Disabled: the text twice, a white one a pixel down and
                // right, then grey (3-D shadow) over it.
                xml += shape(boxX + 0.75, top + 0.75, boxW, lineH, fill: nil, line: nil, text: shown, color: "FFFFFF", algn: algnName)
                xml += shape(boxX, top, boxW, lineH, fill: nil, line: nil, text: shown, color: "A0A0A0", algn: algnName)
            }
        }
        xml += "</p:spTree>"
        return XNode.parse(Data(xml.utf8))
    }
}
