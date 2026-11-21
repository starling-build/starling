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
}
