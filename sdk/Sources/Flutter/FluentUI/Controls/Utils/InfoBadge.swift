// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Ported from: fluent_ui/lib/src/controls/utils/info_badge.dart

import FlutterSwiftBridge

// MARK: - InfoBadgeSeverity

/// The severity level of an InfoBadge.
public enum InfoBadgeSeverity {
    /// Informational (accent blue).
    case info
    /// Warning / attention (orange/yellow).
    case warning
    /// Success (green).
    case success
    /// Critical / error (red).
    case error
}

// MARK: - InfoBadge

/// A small colored dot or number badge used for notifications or status.
///
/// Badging is a non-intrusive and intuitive way to display notifications or
/// bring focus to an area within an app.
public class InfoBadge: StatelessWidget {
    /// The source content of the badge (e.g., a Text with a number).
    /// If nil, the badge is displayed as a small dot.
    public let source: Widget?

    /// The background color of the badge.
    /// If nil, the color is determined by the severity.
    public let color: Color?

    /// The foreground color (text/icon color).
    public let foregroundColor: Color?

    /// The severity of the badge.
    public let severity: InfoBadgeSeverity

    public init(
        key: (any Key)? = nil,
        source: Widget? = nil,
        color: Color? = nil,
        foregroundColor: Color? = nil,
        severity: InfoBadgeSeverity = .info
    ) {
        self.source = source
        self.color = color
        self.foregroundColor = foregroundColor
        self.severity = severity
        super.init(key: key)
    }

    /// Creates an attention info badge.
    public convenience init(
        attention key: (any Key)? = nil,
        source: Widget? = nil,
        foregroundColor: Color? = nil
    ) {
        self.init(
            key: key,
            source: source,
            color: nil,
            foregroundColor: foregroundColor,
            severity: .warning
        )
    }

    /// Creates an informational info badge.
    public convenience init(
        informational key: (any Key)? = nil,
        source: Widget? = nil,
        foregroundColor: Color? = nil
    ) {
        self.init(
            key: key,
            source: source,
            color: nil,
            foregroundColor: foregroundColor,
            severity: .info
        )
    }

    /// Creates a success info badge.
    public convenience init(
        success key: (any Key)? = nil,
        source: Widget? = nil,
        foregroundColor: Color? = nil
    ) {
        self.init(
            key: key,
            source: source,
            color: nil,
            foregroundColor: foregroundColor,
            severity: .success
        )
    }

    /// Creates a critical info badge.
    public convenience init(
        critical key: (any Key)? = nil,
        source: Widget? = nil,
        foregroundColor: Color? = nil
    ) {
        self.init(
            key: key,
            source: source,
            color: nil,
            foregroundColor: foregroundColor,
            severity: .error
        )
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        // Resolve background color based on severity
        let resolvedColor: Color = self.color ?? {
            switch severity {
            case .info:
                return theme.accentColor.defaultBrushFor(theme.brightness)
            case .warning:
                // WinUI's Caution badge: the caution fill, not the attention
                // background (which is the near-white page grey).
                return theme.resources.systemFillColorCaution
            case .success:
                return theme.resources.systemFillColorSuccess
            case .error:
                return theme.resources.systemFillColorCritical
            }
        }()

        let resolvedForeground: Color = self.foregroundColor
            ?? theme.resources.textOnAccentFillColorPrimary

        // Dot badge (no source content)
        if source == nil {
            return _InfoBadgeDot(
                decoration: BoxDecoration(
                    color: resolvedColor,
                    borderRadius: BorderRadius.circular(100)
                ),
                dotSize: 6.0
            )
        }

        // Badge with content
        return _InfoBadgeWithContent(
            decoration: BoxDecoration(
                color: resolvedColor,
                borderRadius: BorderRadius.circular(100)
            ),
            child: DefaultTextStyle(
                style: TextStyle(color: resolvedForeground, fontSize: 11),
                child: Padding(
                    padding: EdgeInsets(left: 4, top: 0, right: 4, bottom: 1),
                    child: source!
                )
            )
        )
    }
}

// MARK: - _InfoBadgeDot

/// Renders a small circular dot.
private class _InfoBadgeDot: SingleChildRenderObjectWidget {
    let decoration: BoxDecoration
    let dotSize: Double

    init(
        key: (any Key)? = nil,
        decoration: BoxDecoration,
        dotSize: Double
    ) {
        self.decoration = decoration
        self.dotSize = dotSize
        super.init(key: key, child: nil)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return _RenderInfoBadgeDot(decoration: decoration, dotSize: dotSize)
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! _RenderInfoBadgeDot
        ro.decoration = decoration
        ro.dotSize = dotSize
    }
}

private class _RenderInfoBadgeDot: RenderDecoratedBox {
    var dotSize: Double {
        didSet { if dotSize != oldValue { markNeedsLayout() } }
    }

    init(decoration: BoxDecoration, dotSize: Double) {
        self.dotSize = dotSize
        super.init(decoration: decoration)
    }

    override func performLayout() {
        size = Size(dotSize, dotSize)
    }
}

// MARK: - _InfoBadgeWithContent

/// Renders a badge with a minimum size constraint and decoration.
private class _InfoBadgeWithContent: SingleChildRenderObjectWidget {
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
        return _RenderInfoBadgeWithContent(decoration: decoration)
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! _RenderInfoBadgeWithContent
        ro.decoration = decoration
    }
}

private class _RenderInfoBadgeWithContent: RenderDecoratedBox {
    override func performLayout() {
        let boxConstraints = constraints as! BoxConstraints
        if let child = child as? RenderBox {
            let childConstraints = BoxConstraints(
                minWidth: 16,
                maxWidth: boxConstraints.maxWidth,
                minHeight: 16,
                maxHeight: 16
            )
            child.layout(childConstraints, parentUsesSize: true)
            let childSize = child.size
            size = boxConstraints.constrain(Size(
                max(childSize.width, 16),
                16
            ))
            // Center child vertically
            if let parentData = child.parentData as? BoxParentData {
                parentData.offset = Offset(
                    (size.width - childSize.width) / 2.0,
                    (size.height - childSize.height) / 2.0
                )
            }
        } else {
            size = boxConstraints.constrain(Size(16, 16))
        }
    }
}
