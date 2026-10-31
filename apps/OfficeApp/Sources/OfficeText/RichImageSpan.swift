// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import FlutterSwiftBridge

/// The span a picture inline with text occupies: a placeholder of the
/// picture's size, sitting on the baseline. `RichLayout` hands the
/// painter the dimensions and paints the picture into the placeholder's
/// box; the span itself only reserves the room, as a `WidgetSpan` would.
final class RichImageSpan: PlaceholderSpan {
    override func build(
        _ builder: any FlutterSwiftBridge.ParagraphBuilder,
        textScaler: any TextScaler = TextScalers.noScaling,
        dimensions: [PlaceholderDimensions]? = nil
    ) {
        let hasStyle = style != nil
        if hasStyle { builder.pushStyle(style!.getTextStyle(textScaler: textScaler)) }
        let index = builder.placeholderCount
        if let dimensions, index < dimensions.count {
            let d = dimensions[index]
            builder.addPlaceholder(d.size.width, d.size.height, d.alignment,
                                   scale: 1.0, baselineOffset: d.baselineOffset, baseline: d.baseline)
        } else {
            builder.addPlaceholder(0, 0, alignment, scale: 1.0, baselineOffset: nil, baseline: baseline)
        }
        if hasStyle { builder.pop() }
    }

    override func debugAssertIsValid() -> Bool { true }
}
