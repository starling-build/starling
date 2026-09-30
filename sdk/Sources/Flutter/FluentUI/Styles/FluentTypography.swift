// Fluent UI typography definitions ported from fluent_ui/lib/src/styles/typography.dart

import FlutterSwiftBridge

// MARK: - Typography

/// Defines the text styles used throughout a Fluent UI application.
///
/// Implements the Windows 11 Type Ramp:
///
/// | Style       | Size | Weight   |
/// |:------------|-----:|:---------|
/// | display     | 68px | Semibold |
/// | titleLarge  | 40px | Semibold |
/// | title       | 28px | Semibold |
/// | subtitle    | 20px | Semibold |
/// | bodyLarge   | 18px | Regular  |
/// | bodyStrong  | 14px | Semibold |
/// | body        | 14px | Regular  |
/// | caption     | 12px | Light    |
public struct Typography: Equatable {
    public let display: TextStyle?
    public let titleLarge: TextStyle?
    public let title: TextStyle?
    public let subtitle: TextStyle?
    public let bodyLarge: TextStyle?
    public let bodyStrong: TextStyle?
    public let body: TextStyle?
    public let caption: TextStyle?

    /// Creates a new Typography with all style properties.
    public init(
        display: TextStyle? = nil,
        titleLarge: TextStyle? = nil,
        title: TextStyle? = nil,
        subtitle: TextStyle? = nil,
        bodyLarge: TextStyle? = nil,
        bodyStrong: TextStyle? = nil,
        body: TextStyle? = nil,
        caption: TextStyle? = nil
    ) {
        self.display = display
        self.titleLarge = titleLarge
        self.title = title
        self.subtitle = subtitle
        self.bodyLarge = bodyLarge
        self.bodyStrong = bodyStrong
        self.body = body
        self.caption = caption
    }

    /// Creates a typography with the Windows 11 type ramp values.
    ///
    /// The text color is determined by `brightness` or `color`:
    /// - If `color` is provided, it is used directly
    /// - If brightness is `.light`, a near-black color is used
    /// - If brightness is `.dark`, white is used
    public static func fromBrightness(
        brightness: Brightness? = nil,
        color: Color? = nil
    ) -> Typography {
        assert(brightness != nil || color != nil,
               "Either brightness or color must be provided")
        let resolvedColor = color ?? (brightness == .light
            ? Color(0xE4000000)
            : Color(0xFFFFFFFF))
        return Typography(
            display: TextStyle(
                color: resolvedColor,
                fontSize: 68,
                fontWeight: .w600,
                height: 92.0 / 68.0
            ),
            titleLarge: TextStyle(
                color: resolvedColor,
                fontSize: 40,
                fontWeight: .w600,
                height: 52.0 / 40.0
            ),
            title: TextStyle(
                color: resolvedColor,
                fontSize: 28,
                fontWeight: .w600,
                height: 36.0 / 28.0
            ),
            subtitle: TextStyle(
                color: resolvedColor,
                fontSize: 20,
                fontWeight: .w600,
                height: 28.0 / 20.0
            ),
            bodyLarge: TextStyle(
                color: resolvedColor,
                fontSize: 18,
                fontWeight: .normal,
                height: 24.0 / 18.0
            ),
            bodyStrong: TextStyle(
                color: resolvedColor,
                fontSize: 14,
                fontWeight: .w600,
                height: 20.0 / 14.0
            ),
            body: TextStyle(
                color: resolvedColor,
                fontSize: 14,
                fontWeight: .normal,
                height: 20.0 / 14.0
            ),
            caption: TextStyle(
                color: resolvedColor,
                fontSize: 12,
                fontWeight: .w300,
                height: 16.0 / 12.0
            )
        )
    }

    /// Linearly interpolates between two Typography objects.
    public static func lerp(_ a: Typography?, _ b: Typography?, _ t: Double) -> Typography {
        return Typography(
            display: TextStyle.lerp(a?.display, b?.display, t),
            titleLarge: TextStyle.lerp(a?.titleLarge, b?.titleLarge, t),
            title: TextStyle.lerp(a?.title, b?.title, t),
            subtitle: TextStyle.lerp(a?.subtitle, b?.subtitle, t),
            bodyLarge: TextStyle.lerp(a?.bodyLarge, b?.bodyLarge, t),
            bodyStrong: TextStyle.lerp(a?.bodyStrong, b?.bodyStrong, t),
            body: TextStyle.lerp(a?.body, b?.body, t),
            caption: TextStyle.lerp(a?.caption, b?.caption, t)
        )
    }

    /// Merges another typography into this one. Non-nil values from the other
    /// typography take precedence.
    public func merge(_ other: Typography?) -> Typography {
        guard let other = other else { return self }
        return Typography(
            display: other.display ?? display,
            titleLarge: other.titleLarge ?? titleLarge,
            title: other.title ?? title,
            subtitle: other.subtitle ?? subtitle,
            bodyLarge: other.bodyLarge ?? bodyLarge,
            bodyStrong: other.bodyStrong ?? bodyStrong,
            body: other.body ?? body,
            caption: other.caption ?? caption
        )
    }

    /// Returns a new Typography with transformations applied to all text styles.
    public func apply(
        fontFamily: String? = nil,
        fontSizeFactor: Double = 1.0,
        fontSizeDelta: Double = 0.0,
        displayColor: Color? = nil,
        decoration: TextDecoration? = nil,
        decorationColor: Color? = nil,
        decorationStyle: TextDecorationStyle? = nil
    ) -> Typography {
        return Typography(
            display: display?.apply(
                color: displayColor,
                decoration: decoration,
                decorationColor: decorationColor,
                decorationStyle: decorationStyle,
                fontFamily: fontFamily,
                fontSizeFactor: fontSizeFactor,
                fontSizeDelta: fontSizeDelta
            ),
            titleLarge: titleLarge?.apply(
                color: displayColor,
                decoration: decoration,
                decorationColor: decorationColor,
                decorationStyle: decorationStyle,
                fontFamily: fontFamily,
                fontSizeFactor: fontSizeFactor,
                fontSizeDelta: fontSizeDelta
            ),
            title: title?.apply(
                color: displayColor,
                decoration: decoration,
                decorationColor: decorationColor,
                decorationStyle: decorationStyle,
                fontFamily: fontFamily,
                fontSizeFactor: fontSizeFactor,
                fontSizeDelta: fontSizeDelta
            ),
            subtitle: subtitle?.apply(
                color: displayColor,
                decoration: decoration,
                decorationColor: decorationColor,
                decorationStyle: decorationStyle,
                fontFamily: fontFamily,
                fontSizeFactor: fontSizeFactor,
                fontSizeDelta: fontSizeDelta
            ),
            bodyLarge: bodyLarge?.apply(
                color: displayColor,
                decoration: decoration,
                decorationColor: decorationColor,
                decorationStyle: decorationStyle,
                fontFamily: fontFamily,
                fontSizeFactor: fontSizeFactor,
                fontSizeDelta: fontSizeDelta
            ),
            bodyStrong: bodyStrong?.apply(
                color: displayColor,
                decoration: decoration,
                decorationColor: decorationColor,
                decorationStyle: decorationStyle,
                fontFamily: fontFamily,
                fontSizeFactor: fontSizeFactor,
                fontSizeDelta: fontSizeDelta
            ),
            body: body?.apply(
                color: displayColor,
                decoration: decoration,
                decorationColor: decorationColor,
                decorationStyle: decorationStyle,
                fontFamily: fontFamily,
                fontSizeFactor: fontSizeFactor,
                fontSizeDelta: fontSizeDelta
            ),
            caption: caption?.apply(
                color: displayColor,
                decoration: decoration,
                decorationColor: decorationColor,
                decorationStyle: decorationStyle,
                fontFamily: fontFamily,
                fontSizeFactor: fontSizeFactor,
                fontSizeDelta: fontSizeDelta
            )
        )
    }
}
