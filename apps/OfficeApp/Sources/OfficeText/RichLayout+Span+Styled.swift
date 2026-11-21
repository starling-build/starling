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
        let spans = f.go()
        ctx = f.ctx
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
