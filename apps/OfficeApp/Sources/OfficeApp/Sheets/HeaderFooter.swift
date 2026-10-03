// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Page headers and footers as Excel keeps them: one string per header or
// footer in the file's `<headerFooter>`, cut into left, centre and right
// sections by `&L`, `&C` and `&R`, with the rest of the ampersand codes
// Excel's Page Setup writes — `&P` page, `&N` pages, `&D` date, `&T`
// time, `&F` file, `&A` sheet, `&Z` path, `&B`/`&I`/`&U`/`&E`/`&S` to
// toggle bold, italic, underline, double underline and strikeout,
// `&"Font,Style"` and `&nn` for the font and its size, `&Kxxxxxx` for a
// colour, `&&` for an ampersand. Odd, even and first pages may each have
// their own.

import Foundation

struct HeaderFooter: Equatable {
    var oddHeader = "", oddFooter = ""
    var evenHeader = "", evenFooter = ""
    var firstHeader = "", firstFooter = ""
    var differentOddEven = false
    var differentFirst = false

    var isEmpty: Bool {
        [oddHeader, oddFooter, evenHeader, evenFooter, firstHeader, firstFooter].allSatisfy(\.isEmpty)
    }

    /// `page` is the page's position in the print job, from 1.
    func header(page: Int) -> String {
        if differentFirst && page == 1 { return firstHeader }
        if differentOddEven && page % 2 == 0 { return evenHeader }
        return oddHeader
    }

    func footer(page: Int) -> String {
        if differentFirst && page == 1 { return firstFooter }
        if differentOddEven && page % 2 == 0 { return evenFooter }
        return oddFooter
    }

    /// From the sheet's `<headerFooter>` element.
    static func read(_ node: XNode) -> HeaderFooter {
        var h = HeaderFooter()
        func flag(_ k: String) -> Bool { node[k] == "1" || node[k] == "true" }
        h.differentOddEven = flag("differentOddEven")
        h.differentFirst = flag("differentFirst")
        h.oddHeader = node.child("oddHeader")?.text ?? ""
        h.oddFooter = node.child("oddFooter")?.text ?? ""
        h.evenHeader = node.child("evenHeader")?.text ?? ""
        h.evenFooter = node.child("evenFooter")?.text ?? ""
        h.firstHeader = node.child("firstHeader")?.text ?? ""
        h.firstFooter = node.child("firstFooter")?.text ?? ""
        return h
    }
}

enum HeaderFooterText {
    struct RunStyle: Equatable {
        var bold = false, italic = false, underline = false, strike = false
        var size: Double? = nil
        var family: String? = nil
        var color: Int64? = nil
    }

    enum Piece: Equatable {
        case text(String)
        case page, pages, date, time, file, sheet, path
    }

    struct Item: Equatable {
        var piece: Piece
        var style: RunStyle
    }

    struct Sections: Equatable {
        var left: [Item] = [], center: [Item] = [], right: [Item] = []
    }

    /// What the codes stand in for on one page.
    struct Fields {
        var page = 1
        var pages = 1
        var file = ""
        var sheet = ""
        var path = ""
        var date = Date()
    }

    /// A resolved run: text in one style.
    struct Run: Equatable {
        var text: String
        var style: RunStyle
    }

    /// Text with no section code is centred, as Excel shows it.
    static func parse(_ s: String) -> Sections {
        var out = Sections()
        var section = 1   // 0 left, 1 centre, 2 right
        var style = RunStyle()
        var text = ""
        func flush() {
            guard !text.isEmpty else { return }
            add(.text(text))
            text = ""
        }
        func add(_ p: Piece) {
            let item = Item(piece: p, style: style)
            switch section {
            case 0: out.left.append(item)
            case 2: out.right.append(item)
            default: out.center.append(item)
            }
        }
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            guard c == "&", i + 1 < chars.count else { text.append(c); i += 1; continue }
            let code = chars[i + 1]
            i += 2
            switch code {
            case "&": text.append("&")
            case "L", "l": flush(); section = 0
            case "C", "c": flush(); section = 1
            case "R", "r": flush(); section = 2
            case "P", "p": flush(); add(.page)
            case "N", "n": flush(); add(.pages)
            case "D", "d": flush(); add(.date)
            case "T", "t": flush(); add(.time)
            case "F", "f": flush(); add(.file)
            case "A", "a": flush(); add(.sheet)
            case "Z", "z": flush(); add(.path)
            case "G", "g": break   // a picture: not drawn
            case "B", "b": flush(); style.bold.toggle()
            case "I", "i": flush(); style.italic.toggle()
            case "U", "u", "E", "e": flush(); style.underline.toggle()
            case "S", "s": flush(); style.strike.toggle()
            case "X", "x", "Y", "y", "O", "o", "H", "h": break   // super/subscript, outline, shadow
            case "K", "k":
                // Six characters: RRGGBB, or a theme colour (NN+TTT) left as is.
                if i + 6 <= chars.count {
                    let spec = String(chars[i ..< i + 6])
                    i += 6
                    if let v = Int64(spec, radix: 16) { flush(); style.color = 0xFF00_0000 | v }
                }
            case "\"":
                // &"Name,Style" — a name of "-" keeps the font.
                var j = i
                while j < chars.count, chars[j] != "\"" { j += 1 }
                let spec = String(chars[i ..< min(j, chars.count)])
                i = min(j + 1, chars.count)
                flush()
                let parts = spec.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if let name = parts.first, !name.isEmpty, name != "-" { style.family = name }
                if parts.count > 1 {
                    let st = parts[1].lowercased()
                    style.bold = st.contains("bold")
                    style.italic = st.contains("italic")
                }
            default:
                if code.isNumber {
                    var digits = String(code)
                    while i < chars.count, chars[i].isNumber, digits.count < 3 { digits.append(chars[i]); i += 1 }
                    if let n = Double(digits), n >= 1 { flush(); style.size = n }
                } else {
                    // An unknown code: keep the characters, Excel shows them.
                    text.append("&"); text.append(code)
                }
            }
        }
        flush()
        return out
    }

    private static let _dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private static let _timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// The items of one section as text, adjacent same-styled pieces merged.
    static func runs(_ items: [Item], fields: Fields) -> [Run] {
        var out: [Run] = []
        for item in items {
            let text: String
            switch item.piece {
            case .text(let s): text = s
            case .page: text = String(fields.page)
            case .pages: text = String(fields.pages)
            case .date: text = _dateFormat.string(from: fields.date)
            case .time: text = _timeFormat.string(from: fields.date)
            case .file: text = fields.file
            case .sheet: text = fields.sheet
            case .path: text = fields.path
            }
            if let last = out.last, last.style == item.style {
                out[out.count - 1].text += text
            } else {
                out.append(Run(text: text, style: item.style))
            }
        }
        return out
    }
}
