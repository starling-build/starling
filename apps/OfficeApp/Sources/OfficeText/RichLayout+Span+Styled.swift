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
        _markOpeningAFaceRun(&ctx, &spans, rawText, run, at: base)
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

extension RichLayout {
    /// A run that opens with a combining mark of a complex script, set in another complex-script face than
    /// the text before it, is shaped apart from that text in Word, and the mark with no letter to sit on is
    /// drawn on a dotted circle (U+25CC) with the circle's width. Word's print of dx2 c2c3a2f3 p3: a lone
    /// hamza (U+0654) in Times New Roman after B Zar text stands on a 8.3 pt circle, and its lines wrap with it;
    /// a mark opening a run in the same face attaches to the letter before it (lenovo-5, 7 dx2 docs).
    func _markOpeningAFaceRun(_ ctx: inout _SpanCtx, _ spans: inout [TextSpan], _ rawText: Substring, _ run: CharStyle, at base: Int) {
        guard theme.wordRules, base > 0, let mark = rawText.unicodeScalars.first,
              mark.properties.generalCategory == .nonspacingMark, mark.value >= 0x590, mark.value < 0x1100 else { return }
        let p = ctx.p, document = ctx.document
        var at = 0
        var before: Run?
        for r in p.runs {
            at += r.length
            if at == base { before = r; break }
            if at > base { return }
        }
        guard let before else { return }
        let named = _named(p, document)
        let normal = _normalChar(document)
        func face(_ s: CharStyle) -> String {
            (s.complexFontFamily ?? named?.char.complexFontFamily ?? normal?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
        }
        guard face(before.style) != face(run),
              let k = spans.firstIndex(where: { $0.text?.unicodeScalars.first == mark }), let text = spans[k].text else { return }
        RuleTrace.hit("word-mark-opening-a-run-in-another-face-stands-on-a-dotted-circle")
        let sp = spans[k]
        spans[k] = TextSpan(text: "\u{25CC}" + text, children: sp.children, style: sp.style, recognizer: sp.recognizer, locale: sp.locale)
        let slot = ctx.inserts.firstIndex(where: { $0 > base }) ?? ctx.inserts.count
        ctx.inserts.insert(base, at: slot)
    }
}
