// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Ported from: fluent_ui/lib/src/controls/form/number_box.dart (simplified)
// This is a simplified version with no text editing — display only with
// increment/decrement buttons.

import FlutterSwiftBridge

// MARK: - NumberBox

/// A simplified number box with a display label and increment/decrement buttons.
///
/// Layout: Row with decrement button (-) + value display (Text) + increment button (+).
/// No text editing — display only.
public class NumberBox: StatelessWidget {
    /// The current value. If nil, displays empty.
    public let value: Double?

    /// Called when the value changes via increment/decrement.
    /// If nil, the NumberBox is disabled.
    public let onChanged: ((Double?) -> Void)?

    /// The minimum allowed value. If nil, no lower limit.
    public let min: Double?

    /// The maximum allowed value. If nil, no upper limit.
    public let max: Double?

    /// The amount to change when pressing +/- buttons. Defaults to 1.
    public let smallChange: Double

    /// The amount for large changes (not used in this simplified version). Defaults to 10.
    public let largeChange: Double

    /// The style for the value text.
    public let textStyle: TextStyle?

    public init(
        key: (any Key)? = nil,
        value: Double? = nil,
        onChanged: ((Double?) -> Void)? = nil,
        min: Double? = nil,
        max: Double? = nil,
        smallChange: Double = 1,
        largeChange: Double = 10,
        textStyle: TextStyle? = nil
    ) {
        self.value = value
        self.onChanged = onChanged
        self.min = min
        self.max = max
        self.smallChange = smallChange
        self.largeChange = largeChange
        self.textStyle = textStyle
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let isDisabled = onChanged == nil

        let displayText: String
        if let v = value {
            if v == v.rounded() && v >= -1e15 && v <= 1e15 {
                displayText = "\(Int(v))"
            } else {
                displayText = "\(v)"
            }
        } else {
            displayText = ""
        }

        let valueText: Widget = Text(
            displayText,
            style: textStyle ?? TextStyle(
                color: isDisabled
                    ? theme.resources.textFillColorDisabled
                    : theme.resources.textFillColorPrimary,
                fontSize: 14
            )
        )

        let valueContent: Widget = SizedBox(
            width: 60,
            child: Center(child: valueText)
        )

        let valuePadded: Widget = Padding(
            padding: EdgeInsets(left: 12, top: 6, right: 12, bottom: 6),
            child: valueContent
        )

        let valueDisplay: Widget = _NumberBoxDecoratedBox(
            decoration: BoxDecoration(
                color: isDisabled
                    ? theme.resources.controlFillColorDisabled
                    : theme.resources.controlFillColorDefault,
                border: Border.all(
                    color: theme.resources.controlStrokeColorDefault
                ),
                borderRadius: BorderRadius.circular(4)
            ),
            child: valuePadded
        )

        let decrementButton: Widget = _NumberBoxButton(
            label: "-",  // hyphen-minus: U+2212 is not in Selawik
            onPressed: isDisabled ? nil : { [self] in
                _decrement()
            },
            theme: theme
        )

        let incrementButton: Widget = _NumberBoxButton(
            label: "+",
            onPressed: isDisabled ? nil : { [self] in
                _increment()
            },
            theme: theme
        )

        return Row(
            mainAxisSize: .min,
            children: [
                decrementButton,
                SizedBox(width: 2),
                valueDisplay,
                SizedBox(width: 2),
                incrementButton
            ]
        )
    }

    private func _increment() {
        guard let onChanged = onChanged else { return }
        let current = value ?? 0
        var newValue = current + smallChange
        if let max = max {
            newValue = Swift.min(newValue, max)
        }
        onChanged(newValue)
    }

    private func _decrement() {
        guard let onChanged = onChanged else { return }
        let current = value ?? 0
        var newValue = current - smallChange
        if let min = min {
            newValue = Swift.max(newValue, min)
        }
        onChanged(newValue)
    }
}

// MARK: - _NumberBoxButton

/// An internal button used for the increment/decrement controls.
private class _NumberBoxButton: StatelessWidget {
    let label: String
    let onPressed: (() -> Void)?
    let theme: FluentThemeData

    init(
        key: (any Key)? = nil,
        label: String,
        onPressed: (() -> Void)?,
        theme: FluentThemeData
    ) {
        self.label = label
        self.onPressed = onPressed
        self.theme = theme
        super.init(key: key)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let isDisabled = onPressed == nil

        return HoverButton(
            builder: { context, states in
                let bgColor: Color = Set<WidgetState>.forStates(
                    states,
                    disabled: self.theme.resources.controlFillColorDisabled,
                    none: self.theme.resources.controlFillColorDefault,
                    pressed: self.theme.resources.controlFillColorTertiary,
                    hovering: self.theme.resources.controlFillColorSecondary
                )

                let fgColor: Color = isDisabled
                    ? self.theme.resources.textFillColorDisabled
                    : self.theme.resources.textFillColorPrimary

                let text: Widget = Text(
                    self.label,
                    style: TextStyle(
                        color: fgColor,
                        fontSize: 16
                    )
                )

                let content: Widget = Padding(
                    padding: EdgeInsets(left: 8, top: 4, right: 8, bottom: 4),
                    child: Center(child: text)
                )

                return _NumberBoxDecoratedBox(
                    decoration: BoxDecoration(
                        color: bgColor,
                        border: Border.all(
                            color: self.theme.resources.controlStrokeColorDefault
                        ),
                        borderRadius: BorderRadius.circular(4)
                    ),
                    child: content
                )
            },
            onPressed: onPressed
        )
    }
}

// MARK: - _NumberBoxDecoratedBox

/// A widget that paints a Decoration behind its child.
private class _NumberBoxDecoratedBox: SingleChildRenderObjectWidget {
    let decoration: Decoration

    init(
        key: (any Key)? = nil,
        decoration: Decoration,
        child: Widget? = nil
    ) {
        self.decoration = decoration
        super.init(key: key, child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderDecoratedBox(decoration: decoration)
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderDecoratedBox
        ro.decoration = decoration
    }
}
