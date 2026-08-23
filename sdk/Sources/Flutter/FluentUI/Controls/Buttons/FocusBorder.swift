// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Ported from: fluent_ui/lib/src/controls/utils/focus.dart
//
// Simplified version — FluentTheme / FocusThemeData are not yet available,
// so we use hardcoded placeholder colors. Once FluentTheme lands (Phase 1.2),
// this should be updated to read colours from the theme.

import FlutterSwiftBridge

// MARK: - FocusThemeData

/// Theme data describing how a focus border should look.
///
/// Placeholder implementation — will be updated to integrate with FluentTheme.
public class FocusThemeData {
    /// The corner radius of the focus border.
    public let borderRadius: BorderRadius?

    /// The primary (outer) border side.
    public let primaryBorder: BorderSide?

    /// The secondary (inner) border side.
    public let secondaryBorder: BorderSide?

    /// Whether the focus border renders outside of the child.
    public let renderOutside: Bool?

    public init(
        borderRadius: BorderRadius? = nil,
        primaryBorder: BorderSide? = nil,
        secondaryBorder: BorderSide? = nil,
        renderOutside: Bool? = nil
    ) {
        self.borderRadius = borderRadius
        self.primaryBorder = primaryBorder
        self.secondaryBorder = secondaryBorder
        self.renderOutside = renderOutside
    }

    /// Standard focus theme — placeholder colours until FluentTheme is available.
    public static func standard() -> FocusThemeData {
        return FocusThemeData(
            borderRadius: BorderRadius.circular(6),
            primaryBorder: BorderSide(
                color: Color(0xFF000000),  // focusStrokeColorOuter placeholder
                width: 2
            ),
            secondaryBorder: BorderSide(
                color: Color(0xFFFFFFFF),  // focusStrokeColorInner placeholder
                width: 1
            ),
            renderOutside: true
        )
    }

    /// Merges this theme data with another, with the other taking precedence.
    public func merge(_ other: FocusThemeData?) -> FocusThemeData {
        guard let other = other else { return self }
        return FocusThemeData(
            borderRadius: other.borderRadius ?? borderRadius,
            primaryBorder: other.primaryBorder ?? primaryBorder,
            secondaryBorder: other.secondaryBorder ?? secondaryBorder,
            renderOutside: other.renderOutside ?? renderOutside
        )
    }
}

// MARK: - FocusBorder

/// A widget that draws a focus ring around its child when `focused` is true.
///
/// This is a simplified port of `FocusBorder` from fluent_ui. The full
/// version uses `FocusTheme.of(context)` for theming; this placeholder
/// uses hardcoded border styles until FluentTheme is available.
public class FocusBorder: StatelessWidget {
    /// The child that will receive the border.
    public let child: Widget

    /// Whether to show the focus border.
    public let focused: Bool

    /// Optional style overrides.
    public let style: FocusThemeData?

    /// Whether the border renders outside of the child.
    public let renderOutside: Bool?

    /// Whether to use a Stack-based approach (recommended for sized widgets).
    public let useStackApproach: Bool

    public init(
        key: (any Key)? = nil,
        child: Widget,
        focused: Bool = true,
        style: FocusThemeData? = nil,
        renderOutside: Bool? = nil,
        useStackApproach: Bool = true
    ) {
        self.child = child
        self.focused = focused
        self.style = style
        self.renderOutside = renderOutside
        self.useStackApproach = useStackApproach
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        // `focused` was stored and never read: the ring was painted whether or
        // not the child had focus, on every control that wraps one. Nothing on
        // Linux noticed because the shell and the apps are Fluent-free, and it
        // surfaced on Windows as a black rectangle around the Start menu's
        // search box that no combination of decorations could remove.
        guard focused else { return child }

        let resolvedStyle = FocusThemeData.standard().merge(style)
        let borderWidth =
            (resolvedStyle.primaryBorder?.width ?? 0)
            + (resolvedStyle.secondaryBorder?.width ?? 0)

        if useStackApproach {
            let outside = renderOutside ?? resolvedStyle.renderOutside ?? true
            let clipBehavior: Clip = outside ? .none : .hardEdge
            let inset = outside ? -borderWidth : 0.0

            return Stack(
                fit: .passthrough,
                clipBehavior: clipBehavior,
                children: [
                    child,
                    Positioned(
                        left: inset,
                        top: inset,
                        right: inset,
                        bottom: inset,
                        child: _buildBorder(resolvedStyle)
                    ),
                ]
            )
        } else {
            return _buildBorder(resolvedStyle, child: child)
        }
    }

    /// Builds a border decoration widget, optionally wrapping a child.
    private func _buildBorder(_ style: FocusThemeData, child: Widget? = nil) -> Widget {
        // Primary (outer) border
        let primaryDecoration = _buildPrimaryDecoration(style)
        // Secondary (inner) border
        let secondaryDecoration = _buildSecondaryDecoration(style)

        var inner: Widget = ColoredBox(
            color: Color(0x00000000),
            child: child
        )

        // Apply secondary border
        inner = _DecoratedBoxWidget(
            decoration: secondaryDecoration,
            child: inner
        )

        // Apply primary border, wrapped in IgnorePointer so focus ring
        // doesn't intercept hit testing.
        return IgnorePointer(
            child: _DecoratedBoxWidget(
                decoration: primaryDecoration,
                child: inner
            )
        )
    }

    private func _buildPrimaryDecoration(_ style: FocusThemeData) -> BoxDecoration {
        return BoxDecoration(
            border: focused
                ? Border.all(
                    color: style.primaryBorder?.color ?? Color(0xFF000000),
                    width: style.primaryBorder?.width ?? 2
                )
                : nil,
            borderRadius: style.borderRadius
        )
    }

    private func _buildSecondaryDecoration(_ style: FocusThemeData) -> BoxDecoration {
        return BoxDecoration(
            border: focused
                ? Border.all(
                    color: style.secondaryBorder?.color ?? Color(0xFFFFFFFF),
                    width: style.secondaryBorder?.width ?? 1
                )
                : nil,
            borderRadius: style.borderRadius
        )
    }
}

// MARK: - _DecoratedBoxWidget

/// A simple widget that paints a `BoxDecoration` around its child.
///
/// Uses `RenderDecoratedBox` directly (same as `ColoredBox`, but with
/// a full `BoxDecoration` instead of just a color).
class _DecoratedBoxWidget: SingleChildRenderObjectWidget {
    let decoration: BoxDecoration

    init(
        key: (any Key)? = nil,
        decoration: BoxDecoration,
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
