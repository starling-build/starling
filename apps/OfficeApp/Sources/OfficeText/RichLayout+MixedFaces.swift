import Foundation
import Flutter
import FlutterSwiftBridge

extension RichLayout {
    /// Slides: PowerPoint's line that holds more than one face (labs verdana-mf and mf2, Windows prints, 27 cells
    /// within 0.11 pt). Each piece (a run, and the paragraph's end mark in its own face at the size of the run
    /// before it) has its face's plain split of a single line, scaled to its size; the line is as tall as the
    /// largest piece's single line, and its baseline stands where the tallest ascent and the deepest depth,
    /// scaled to that height, put it: H * A / (A + D). One face gives its own split back. Single lines at single
    /// spacing only: nil elsewhere, or when the paragraph holds one face.
    func _mixedFaceSpan(_ span: TextSpan, _ p: RichParagraph) -> TextSpan? {
        guard theme.exactLinesAsPowerPoint, let single = theme.singleLineHeight, p.style.lineHeightPoints == nil,
              abs(max(0.1, p.style.lineSpacing - theme.lineSpacingReduction) - 1) < 1e-9 else { return nil }
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
        let up = height * ascent / (ascent + depth), down = height * depth / (ascent + depth)
        func apply(_ s: InlineSpan) -> InlineSpan {
            guard let t = s as? TextSpan else { return s }
            var st = t.style
            if let text = t.text, !text.isEmpty, let x = st, let size = x.fontSize, size > 0.5 {
                st = x.copyWith(ascentOverride: up, descentOverride: down, height: height / size)
            }
            return TextSpan(text: t.text, children: t.children?.map { apply($0) }, style: st, recognizer: t.recognizer, locale: t.locale)
        }
        return apply(span) as? TextSpan
    }
}
