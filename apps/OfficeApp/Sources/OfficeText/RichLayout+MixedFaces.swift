import Foundation
import Flutter
import FlutterSwiftBridge

extension RichLayout {
    /// Slides: PowerPoint's line that holds more than one face (labs verdana-mf and mf2, Windows prints, 27 cells
    /// within 0.11 pt). Each piece (a run, and the paragraph's end mark in its own face at the size of the run
    /// before it) has its face's plain split of a single line, scaled to its size; the line is as tall as the
    /// largest piece's single line, and its baseline stands where the tallest ascent and the deepest depth,
    /// scaled to that height, put it: H * A / (A + D). One face gives its own split back. Single lines at single
    /// spacing only: nil elsewhere, or when the paragraph holds one face. Right-to-left lines too (lab verdana-rtl, Hebrew and
    /// Arabic with a Latin run and an end mark in another face, 90/100/110%, 60 cells within 0.16 pt).
    func _mixedFaceSpan(_ span: TextSpan, _ p: RichParagraph) -> (span: TextSpan, depth: Double, size: Double)? {
        guard theme.exactLinesAsPowerPoint, let single = theme.singleLineHeight, p.style.lineHeightPoints == nil else { return nil }
        let multiple = max(0.1, p.style.lineSpacing - theme.lineSpacingReduction)
        var pieces: [(name: String, size: Double, depth: Double)] = []
        func depthShare(_ name: String, drawn: String?, bold: Bool, italic: Bool) -> Double {
            theme.ownDescentShare?(name) ?? theme.descentShare(family: drawn, bold: bold, italic: italic)
        }
        func gather(_ s: InlineSpan) {
            guard let t = s as? TextSpan else { return }
            if let text = t.text, !text.isEmpty, let x = t.style, let size = x.fontSize, size > 0.5 {
                // (copyWith wraps a style's label as "(name).copyWith": back to the name.)
                var name = x.debugLabel ?? x.fontFamily ?? ""
                while name.hasSuffix(".copyWith") || name.hasPrefix("(") { name = name.hasSuffix(".copyWith") ? String(name.dropLast(9)) : name; if name.hasPrefix("(") && name.hasSuffix(")") { name = String(name.dropFirst().dropLast()) } else { break } }
                pieces.append((name.trimmingWhitespace().lowercased(), size,
                               depthShare(name, drawn: x.fontFamily, bold: x.fontWeight == .bold, italic: x.fontStyle == .italic) * single))
            }
            for c in t.children ?? [] { gather(c) }
        }
        gather(span)
        guard let last = pieces.last else { return nil }
        if let mark = p.style.endMarkFace {
            let drawn = theme.fontFamilyResolver?(mark) ?? mark
            pieces.append((mark.trimmingWhitespace().lowercased(), last.size, depthShare(mark, drawn: drawn, bold: false, italic: false) * single))
        }
        guard Set(pieces.map(\.name)).count > 1 else { return nil }
        let ascent = pieces.map { ($0.size) * (single - $0.depth) }.max() ?? 0
        let depth = pieces.map { $0.size * $0.depth }.max() ?? 0
        let height = single * (pieces.map(\.size).max() ?? 0)
        guard ascent + depth > 0 else { return nil }
        let up = multiple * height * ascent / (ascent + depth), down = multiple * height * depth / (ascent + depth)
        func apply(_ s: InlineSpan) -> InlineSpan {
            guard let t = s as? TextSpan else { return s }
            var st = t.style
            if let text = t.text, !text.isEmpty, let x = st, let size = x.fontSize, size > 0.5 {
                st = x.copyWith(ascentOverride: up, descentOverride: down, height: multiple * height / size)
            }
            return TextSpan(text: t.text, children: t.children?.map { apply($0) }, style: st, recognizer: t.recognizer, locale: t.locale)
        }
        guard let out = apply(span) as? TextSpan else { return nil }
        return (out, depth / (ascent + depth), height / single)
    }
}

extension RichLayout {
    /// The same for a paragraph that wraps (lab verdana-mf2, Windows print): PowerPoint sets the rule line by line, from
    /// the faces on each line, and the end mark's face only on the last. A line of one face keeps its face's own split.
    /// Single spacing only. Splits the runs at the lines `painter` made, gives each piece its line's split, and returns
    /// the span, or nil where no line holds two faces.
    func _mixedFaceLinesSpan(_ span: TextSpan, _ p: RichParagraph, _ painter: TextPainter) -> TextSpan? {
        guard theme.exactLinesAsPowerPoint, let single = theme.singleLineHeight, p.style.lineHeightPoints == nil,
              abs(max(0.1, p.style.lineSpacing - theme.lineSpacingReduction) - 1) < 1e-9 else { return nil }
        // The lines, as ranges of the painter's text.
        var lines: [(Int, Int)] = []
        var at = 0
        func length(_ s: InlineSpan) -> Int {
            guard let t = s as? TextSpan else { return 0 }
            return (t.text?.utf16.count ?? 0) + (t.children ?? []).reduce(0) { $0 + length($1) }
        }
        let total = length(span)
        while at < total, lines.count < 200 {
            let r = painter.getLineBoundary(TextPosition(offset: at))
            guard r.end > at else { return nil }
            lines.append((at, r.end)); at = r.end
        }
        guard lines.count > 1 else { return nil }
        func lineOf(_ o: Int) -> Int { lines.lastIndex(where: { $0.0 <= o }) ?? 0 }
        func faceName(_ x: TextStyle) -> String {
            var name = x.debugLabel ?? x.fontFamily ?? ""
            while name.hasSuffix(".copyWith") || name.hasPrefix("(") {
                name = name.hasSuffix(".copyWith") ? String(name.dropLast(9)) : name
                if name.hasPrefix("(") && name.hasSuffix(")") { name = String(name.dropFirst().dropLast()) } else { break }
            }
            return name
        }
        func depthShare(_ name: String, drawn: String?, bold: Bool, italic: Bool) -> Double {
            theme.ownDescentShare?(name) ?? theme.descentShare(family: drawn, bold: bold, italic: italic)
        }
        typealias Piece = (name: String, size: Double, depth: Double)
        var perLine = [[Piece]](repeating: [], count: lines.count)
        var offset = 0
        func gather(_ s: InlineSpan) {
            guard let t = s as? TextSpan else { return }
            if let text = t.text {
                let units = Array(text.utf16)
                if let x = t.style, let size = x.fontSize, size > 0.5, !units.isEmpty {
                    let name = faceName(x)
                    let depth = depthShare(name, drawn: x.fontFamily, bold: x.fontWeight == .bold, italic: x.fontStyle == .italic) * single
                    var k = 0
                    while k < units.count {
                        let l = lineOf(offset + k)
                        let end = min(units.count, lines[l].1 - offset)
                        let chunk = String(decoding: units[k..<max(end, k + 1)], as: UTF16.self)
                        if !chunk.trimmingWhitespace().isEmpty { perLine[l].append((name.trimmingWhitespace().lowercased(), size, depth)) }
                        k = max(end, k + 1)
                    }
                }
                offset += units.count
            }
            for c in t.children ?? [] { gather(c) }
        }
        gather(span)
        if let mark = p.style.endMarkFace, let last = perLine.lastIndex(where: { !$0.isEmpty }), let size = perLine[last].last?.size {
            let drawn = theme.fontFamilyResolver?(mark) ?? mark
            perLine[last].append((mark.trimmingWhitespace().lowercased(), size, depthShare(mark, drawn: drawn, bold: false, italic: false) * single))
        }
        guard Set(perLine.flatMap { $0.map(\.name) }).count > 1 else { return nil }
        // Each line's (ascent, descent, height) in the style's units.
        let splits: [(up: Double, down: Double, height: Double)?] = perLine.map { pieces in
            guard !pieces.isEmpty else { return nil }
            let a = pieces.map { $0.size * (single - $0.depth) }.max() ?? 0
            let d = pieces.map { $0.size * $0.depth }.max() ?? 0
            let h = single * (pieces.map(\.size).max() ?? 0)
            guard a + d > 0 else { return nil }
            return (h * a / (a + d), h * d / (a + d), h)
        }
        offset = 0
        func rebuild(_ s: InlineSpan) -> InlineSpan {
            guard let t = s as? TextSpan else { return s }
            var parts: [InlineSpan] = []
            if let text = t.text, !text.isEmpty {
                let units = Array(text.utf16)
                var k = 0
                while k < units.count {
                    let l = lineOf(offset + k)
                    let end = max(k + 1, min(units.count, lines[l].1 - offset))
                    var st = t.style
                    if let x = st, let size = x.fontSize, size > 0.5, let sp = splits[l] {
                        st = x.copyWith(ascentOverride: sp.up, descentOverride: sp.down, height: sp.height / size)
                    }
                    parts.append(TextSpan(text: String(decoding: units[k..<end], as: UTF16.self), style: st))
                    k = end
                }
                offset += units.count
            }
            let kids = (t.children ?? []).map { rebuild($0) }
            if parts.isEmpty { return TextSpan(text: t.text, children: kids.isEmpty ? nil : kids, style: t.style, recognizer: t.recognizer, locale: t.locale) }
            return TextSpan(text: nil, children: parts + kids, style: t.style, recognizer: t.recognizer, locale: t.locale)
        }
        return rebuild(span) as? TextSpan
    }
}
