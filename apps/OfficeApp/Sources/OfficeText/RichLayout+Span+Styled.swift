// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Span+Styled": the `styled` step of `_span` (once a closure inside it; a pure move: the variables it
// shares with `_span` are `_SpanCtx`, passed inout).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {
    func _spanStyled(_ ctx: inout _SpanCtx, _ rawText: Substring, _ run: CharStyle, at base: Int = 0, next: Character? = nil, symbolsShown: Bool = false) -> [TextSpan] {
        let f = _StyledFrame(self, ctx, rawText, run, base: base, next: next, symbolsShown: symbolsShown)
        var spans = f.go()
        ctx = f.ctx
        // (A pair that falls across two spans of a small-caps run's two sizes, a space and the capital after it or the
        // reverse, is kerned as inside one: PowerPoint's Times New Roman small caps set " A" and "A " 1.5 pt closer,
        // d41c3eb9 p29, and the line took the word it wraps. The kern is the stand-in's own pair, taken by the
        // glyph before it as spacing.)
        if run.smallCaps, !theme.wordRules, spans.count > 1 {
            var out: [TextSpan] = []
            for (k, sp) in spans.enumerated() {
                guard k + 1 < spans.count, let t = sp.text, let a = t.last, let b = spans[k + 1].text?.first, let st = sp.style,
                      st.fontSize != spans[k + 1].style?.fontSize else { out.append(sp); continue }
                let kern = _pairAdvance(st, a, b) - _glyphWidth(st, a)
                if abs(kern) < 0.01 || abs(kern) > (st.fontSize ?? 12) * 0.3 { out.append(sp); continue }
                let head = String(t.dropLast())
                if !head.isEmpty { out.append(TextSpan(text: head, style: st)) }
                out.append(TextSpan(text: String(a), style: st.copyWith(letterSpacing: (st.letterSpacing ?? 0) + kern)))
            }
            spans = out
        }
        return spans
    }

    // (Per-line top-aligned lift: a run is cut at the probe layout's line starts, each part set with its line's biggest size.)
    func _spanStyledByLine(_ ctx: inout _SpanCtx, _ sub: Substring, _ run: CharStyle, at base: Int, next: Character?) -> [TextSpan] {
        guard let table = _topLift, !sub.isEmpty else { return _spanStyled(&ctx, sub, run, at: base, next: next) }
        var out: [TextSpan] = []
        var from = sub.startIndex
        var off = base
        let end = base + sub.utf16.count
        while from < sub.endIndex {
            let seg = table.first(where: { $0.from <= off && off < $0.to })
            let nextFrom = table.map { $0.from }.filter { $0 > off }.min() ?? end
            let stop = min(end, seg.map { min($0.to, end) } ?? nextFrom)
            let cut = stop <= off ? sub.endIndex : sub.utf16.index(from, offsetBy: stop - off)
            _topLiftBig = seg?.big
            out += _spanStyled(&ctx, sub[from ..< cut], run, at: off, next: cut < sub.endIndex ? sub[cut] : next)
            _topLiftBig = nil
            from = cut
            off = max(stop, off + 1)
        }
        return out
    }
}
