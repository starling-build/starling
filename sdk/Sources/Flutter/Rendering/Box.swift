// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Box layout model types.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart`

import FlutterSwiftBridge

// MARK: - BoxConstraints

/// Immutable layout constraints for `RenderBox` layout.
///
/// A `Size` respects a `BoxConstraints` if, and only if, all of the following
/// relations hold:
///
///   * `minWidth <= Size.width <= maxWidth`
///   * `minHeight <= Size.height <= maxHeight`
///
/// The constraints themselves must satisfy these relations:
///
///   * `0.0 <= minWidth <= maxWidth <= Double.infinity`
///   * `0.0 <= minHeight <= maxHeight <= Double.infinity`
///
/// `Double.infinity` is a legal value for each constraint.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:100-687`
public struct BoxConstraints: Constraints, Hashable, CustomStringConvertible {

    // MARK: - Properties

    /// The minimum width that satisfies the constraints.
    ///
    /// **Dart Source:** `box.dart:168-169`
    public let minWidth: Double

    /// The maximum width that satisfies the constraints.
    ///
    /// Might be `Double.infinity`.
    ///
    /// **Dart Source:** `box.dart:171-174`
    public let maxWidth: Double

    /// The minimum height that satisfies the constraints.
    ///
    /// **Dart Source:** `box.dart:176-177`
    public let minHeight: Double

    /// The maximum height that satisfies the constraints.
    ///
    /// Might be `Double.infinity`.
    ///
    /// **Dart Source:** `box.dart:179-182`
    public let maxHeight: Double

    // MARK: - Initializers

    /// Creates box constraints with the given constraints.
    ///
    /// **Dart Source:** `box.dart:101-107`
    public init(
        minWidth: Double = 0.0,
        maxWidth: Double = .infinity,
        minHeight: Double = 0.0,
        maxHeight: Double = .infinity
    ) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    // MARK: - Static Factory Methods

    /// Creates box constraints that are respected only by the given size.
    ///
    /// **Dart Source:** `box.dart:109-114`
    public static func tight(_ size: Size) -> BoxConstraints {
        BoxConstraints(
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            maxHeight: size.height
        )
    }

    /// Creates box constraints that require the given width or height.
    ///
    /// **Dart Source:** `box.dart:116-127`
    public static func tightFor(width: Double? = nil, height: Double? = nil) -> BoxConstraints {
        BoxConstraints(
            minWidth: width ?? 0.0,
            maxWidth: width ?? .infinity,
            minHeight: height ?? 0.0,
            maxHeight: height ?? .infinity
        )
    }

    /// Creates box constraints that require the given width or height,
    /// except if they are infinite.
    ///
    /// **Dart Source:** `box.dart:129-142`
    public static func tightForFinite(
        width: Double = .infinity,
        height: Double = .infinity
    ) -> BoxConstraints {
        BoxConstraints(
            minWidth: width != .infinity ? width : 0.0,
            maxWidth: width != .infinity ? width : .infinity,
            minHeight: height != .infinity ? height : 0.0,
            maxHeight: height != .infinity ? height : .infinity
        )
    }

    /// Creates box constraints that forbid sizes larger than the given size.
    ///
    /// **Dart Source:** `box.dart:144-149`
    public static func loose(_ size: Size) -> BoxConstraints {
        BoxConstraints(
            minWidth: 0.0,
            maxWidth: size.width,
            minHeight: 0.0,
            maxHeight: size.height
        )
    }

    /// Creates box constraints that expand to fill another box constraints.
    ///
    /// If width or height is given, the constraints will require exactly the
    /// given value in the given dimension.
    ///
    /// **Dart Source:** `box.dart:151-159`
    public static func expand(width: Double? = nil, height: Double? = nil) -> BoxConstraints {
        BoxConstraints(
            minWidth: width ?? .infinity,
            maxWidth: width ?? .infinity,
            minHeight: height ?? .infinity,
            maxHeight: height ?? .infinity
        )
    }

    /// Creates box constraints that match the given view constraints.
    ///
    /// **Dart Source:** `box.dart:161-166`
    public static func fromViewConstraints(_ constraints: ViewConstraints) -> BoxConstraints {
        BoxConstraints(
            minWidth: constraints.minWidth,
            maxWidth: constraints.maxWidth,
            minHeight: constraints.minHeight,
            maxHeight: constraints.maxHeight
        )
    }

    // MARK: - Copy / Transform Methods

    /// Creates a copy of this box constraints but with the given fields
    /// replaced with the new values.
    ///
    /// **Dart Source:** `box.dart:184-197`
    public func copyWith(
        minWidth: Double? = nil,
        maxWidth: Double? = nil,
        minHeight: Double? = nil,
        maxHeight: Double? = nil
    ) -> BoxConstraints {
        BoxConstraints(
            minWidth: minWidth ?? self.minWidth,
            maxWidth: maxWidth ?? self.maxWidth,
            minHeight: minHeight ?? self.minHeight,
            maxHeight: maxHeight ?? self.maxHeight
        )
    }

    /// Returns new box constraints that are smaller by the given edge
    /// dimensions.
    ///
    /// **Dart Source:** `box.dart:199-212`
    public func deflate(_ edges: any EdgeInsetsGeometry) -> BoxConstraints {
        assert(debugAssertIsValid())
        let horizontal = edges.horizontal
        let vertical = edges.vertical
        let deflatedMinWidth = max(0.0, minWidth - horizontal)
        let deflatedMinHeight = max(0.0, minHeight - vertical)
        return BoxConstraints(
            minWidth: deflatedMinWidth,
            maxWidth: max(deflatedMinWidth, maxWidth - horizontal),
            minHeight: deflatedMinHeight,
            maxHeight: max(deflatedMinHeight, maxHeight - vertical)
        )
    }

    /// Returns new box constraints that remove the minimum width and height
    /// requirements.
    ///
    /// **Dart Source:** `box.dart:214-218`
    public func loosen() -> BoxConstraints {
        assert(debugAssertIsValid())
        return BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight)
    }

    /// Returns new box constraints that respect the given constraints while
    /// being as close as possible to the original constraints.
    ///
    /// **Dart Source:** `box.dart:220-229`
    public func enforce(_ constraints: BoxConstraints) -> BoxConstraints {
        BoxConstraints(
            minWidth: clampDouble(minWidth, constraints.minWidth, constraints.maxWidth),
            maxWidth: clampDouble(maxWidth, constraints.minWidth, constraints.maxWidth),
            minHeight: clampDouble(minHeight, constraints.minHeight, constraints.maxHeight),
            maxHeight: clampDouble(maxHeight, constraints.minHeight, constraints.maxHeight)
        )
    }

    /// Returns new box constraints with a tight width and/or height as close
    /// to the given width and height as possible while still respecting the
    /// original box constraints.
    ///
    /// **Dart Source:** `box.dart:231-241`
    public func tighten(width: Double? = nil, height: Double? = nil) -> BoxConstraints {
        BoxConstraints(
            minWidth: width == nil ? minWidth : clampDouble(width!, minWidth, maxWidth),
            maxWidth: width == nil ? maxWidth : clampDouble(width!, minWidth, maxWidth),
            minHeight: height == nil ? minHeight : clampDouble(height!, minHeight, maxHeight),
            maxHeight: height == nil ? maxHeight : clampDouble(height!, minHeight, maxHeight)
        )
    }

    // MARK: - Computed Properties

    /// A box constraints with the width and height constraints flipped.
    ///
    /// **Dart Source:** `box.dart:243-251`
    public var flipped: BoxConstraints {
        BoxConstraints(
            minWidth: minHeight,
            maxWidth: maxHeight,
            minHeight: minWidth,
            maxHeight: maxWidth
        )
    }

    /// Returns box constraints with the same width constraints but with
    /// unconstrained height.
    ///
    /// **Dart Source:** `box.dart:253-255`
    public func widthConstraints() -> BoxConstraints {
        BoxConstraints(minWidth: minWidth, maxWidth: maxWidth)
    }

    /// Returns box constraints with the same height constraints but with
    /// unconstrained width.
    ///
    /// **Dart Source:** `box.dart:257-259`
    public func heightConstraints() -> BoxConstraints {
        BoxConstraints(minHeight: minHeight, maxHeight: maxHeight)
    }

    /// The biggest size that satisfies the constraints.
    ///
    /// **Dart Source:** `box.dart:363-364`
    public var biggest: Size {
        Size(constrainWidth(), constrainHeight())
    }

    /// The smallest size that satisfies the constraints.
    ///
    /// **Dart Source:** `box.dart:366-367`
    public var smallest: Size {
        Size(constrainWidth(0.0), constrainHeight(0.0))
    }

    /// Whether there is exactly one width value that satisfies the
    /// constraints.
    ///
    /// **Dart Source:** `box.dart:369-370`
    public var hasTightWidth: Bool {
        minWidth >= maxWidth
    }

    /// Whether there is exactly one height value that satisfies the
    /// constraints.
    ///
    /// **Dart Source:** `box.dart:372-373`
    public var hasTightHeight: Bool {
        minHeight >= maxHeight
    }

    /// Whether there is exactly one size that satisfies the constraints.
    ///
    /// **Dart Source:** `box.dart:375-377`
    public var isTight: Bool {
        hasTightWidth && hasTightHeight
    }

    /// Whether there is an upper bound on the maximum width.
    ///
    /// **Dart Source:** `box.dart:379-386`
    public var hasBoundedWidth: Bool {
        maxWidth < .infinity
    }

    /// Whether there is an upper bound on the maximum height.
    ///
    /// **Dart Source:** `box.dart:388-395`
    public var hasBoundedHeight: Bool {
        maxHeight < .infinity
    }

    /// Whether the width constraint is infinite.
    ///
    /// Such a constraint is used to indicate that a box should grow as large as
    /// some other constraint (in this case, horizontally). If constraints are
    /// infinite, then they must have other (non-infinite) constraints enforced
    /// upon them, or must be tightened, before they can be used to derive a
    /// `Size` for a `RenderBox.size`.
    ///
    /// **Dart Source:** `box.dart:397-410`
    public var hasInfiniteWidth: Bool {
        minWidth >= .infinity
    }

    /// Whether the height constraint is infinite.
    ///
    /// Such a constraint is used to indicate that a box should grow as large as
    /// some other constraint (in this case, vertically). If constraints are
    /// infinite, then they must have other (non-infinite) constraints enforced
    /// upon them, or must be tightened, before they can be used to derive a
    /// `Size` for a `RenderBox.size`.
    ///
    /// **Dart Source:** `box.dart:412-425`
    public var hasInfiniteHeight: Bool {
        minHeight >= .infinity
    }

    // MARK: - Constrain Methods

    /// Returns the width that both satisfies the constraints and is as close
    /// as possible to the given width.
    ///
    /// **Dart Source:** `box.dart:261-266`
    public func constrainWidth(_ width: Double = .infinity) -> Double {
        assert(debugAssertIsValid())
        return clampDouble(width, minWidth, maxWidth)
    }

    /// Returns the height that both satisfies the constraints and is as close
    /// as possible to the given height.
    ///
    /// **Dart Source:** `box.dart:268-273`
    public func constrainHeight(_ height: Double = .infinity) -> Double {
        assert(debugAssertIsValid())
        return clampDouble(height, minHeight, maxHeight)
    }

    /// Returns the size that both satisfies the constraints and is as close
    /// as possible to the given size.
    ///
    /// **Dart Source:** `box.dart:285-299`
    public func constrain(_ size: Size) -> Size {
        Size(constrainWidth(size.width), constrainHeight(size.height))
    }

    /// Returns the size that both satisfies the constraints and is as close
    /// as possible to the given width and height.
    ///
    /// When you already have a `Size`, prefer `constrain(_:)`, which applies
    /// the same algorithm to a `Size` directly.
    ///
    /// **Dart Source:** `box.dart:301-308`
    public func constrainDimensions(_ width: Double, _ height: Double) -> Size {
        Size(constrainWidth(width), constrainHeight(height))
    }

    /// Returns a size that attempts to meet the following conditions, in order:
    ///
    ///  * The size must satisfy these constraints.
    ///  * The aspect ratio of the returned size matches the aspect ratio of the
    ///    given size.
    ///  * The returned size is as big as possible while still being equal to or
    ///    smaller than the given size.
    ///
    /// **Dart Source:** `box.dart:310-361`
    public func constrainSizeAndAttemptToPreserveAspectRatio(_ size: Size) -> Size {
        if isTight {
            return smallest
        }

        if size.isEmpty {
            return constrain(size)
        }

        var width = size.width
        var height = size.height
        let aspectRatio = width / height

        if width > maxWidth {
            width = maxWidth
            height = width / aspectRatio
        }

        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }

        if width < minWidth {
            width = minWidth
            height = width / aspectRatio
        }

        if height < minHeight {
            height = minHeight
            width = height * aspectRatio
        }

        return Size(constrainWidth(width), constrainHeight(height))
    }

    /// Whether the given size satisfies the constraints.
    ///
    /// **Dart Source:** `box.dart:427-434`
    public func isSatisfiedBy(_ size: Size) -> Bool {
        assert(debugAssertIsValid())
        return (minWidth <= size.width) &&
            (size.width <= maxWidth) &&
            (minHeight <= size.height) &&
            (size.height <= maxHeight)
    }

    // MARK: - Operators

    /// Scales each constraint parameter by the given factor.
    ///
    /// **Dart Source:** `box.dart:436-444`
    public static func * (lhs: BoxConstraints, rhs: Double) -> BoxConstraints {
        BoxConstraints(
            minWidth: lhs.minWidth * rhs,
            maxWidth: lhs.maxWidth * rhs,
            minHeight: lhs.minHeight * rhs,
            maxHeight: lhs.maxHeight * rhs
        )
    }

    /// Scales each constraint parameter by the inverse of the given factor.
    ///
    /// **Dart Source:** `box.dart:446-454`
    public static func / (lhs: BoxConstraints, rhs: Double) -> BoxConstraints {
        BoxConstraints(
            minWidth: lhs.minWidth / rhs,
            maxWidth: lhs.maxWidth / rhs,
            minHeight: lhs.minHeight / rhs,
            maxHeight: lhs.maxHeight / rhs
        )
    }

    /// Computes the remainder of each constraint parameter by the given value.
    ///
    /// **Dart Source:** `box.dart:466-474`
    public static func % (lhs: BoxConstraints, rhs: Double) -> BoxConstraints {
        BoxConstraints(
            minWidth: lhs.minWidth.truncatingRemainder(dividingBy: rhs),
            maxWidth: lhs.maxWidth.truncatingRemainder(dividingBy: rhs),
            minHeight: lhs.minHeight.truncatingRemainder(dividingBy: rhs),
            maxHeight: lhs.maxHeight.truncatingRemainder(dividingBy: rhs)
        )
    }

    // MARK: - Lerp

    /// Linearly interpolate between two `BoxConstraints`.
    ///
    /// If either is nil, this function interpolates from a `BoxConstraints`
    /// object whose fields are all set to 0.0.
    ///
    /// **Dart Source:** `box.dart:476-524`
    public static func lerp(_ a: BoxConstraints?, _ b: BoxConstraints?, _ t: Double) -> BoxConstraints? {
        if a == b {
            return a
        }
        if a == nil {
            return b! * t
        }
        if b == nil {
            return a! * (1.0 - t)
        }
        assert(a!.debugAssertIsValid())
        assert(b!.debugAssertIsValid())
        assert(
            (a!.minWidth.isFinite && b!.minWidth.isFinite) ||
            (a!.minWidth == .infinity && b!.minWidth == .infinity),
            "Cannot interpolate between finite constraints and unbounded constraints."
        )
        assert(
            (a!.maxWidth.isFinite && b!.maxWidth.isFinite) ||
            (a!.maxWidth == .infinity && b!.maxWidth == .infinity),
            "Cannot interpolate between finite constraints and unbounded constraints."
        )
        assert(
            (a!.minHeight.isFinite && b!.minHeight.isFinite) ||
            (a!.minHeight == .infinity && b!.minHeight == .infinity),
            "Cannot interpolate between finite constraints and unbounded constraints."
        )
        assert(
            (a!.maxHeight.isFinite && b!.maxHeight.isFinite) ||
            (a!.maxHeight == .infinity && b!.maxHeight == .infinity),
            "Cannot interpolate between finite constraints and unbounded constraints."
        )
        return BoxConstraints(
            minWidth: a!.minWidth.isFinite
                ? lerpDouble(a!.minWidth, b!.minWidth, t)!
                : .infinity,
            maxWidth: a!.maxWidth.isFinite
                ? lerpDouble(a!.maxWidth, b!.maxWidth, t)!
                : .infinity,
            minHeight: a!.minHeight.isFinite
                ? lerpDouble(a!.minHeight, b!.minHeight, t)!
                : .infinity,
            maxHeight: a!.maxHeight.isFinite
                ? lerpDouble(a!.maxHeight, b!.maxHeight, t)!
                : .infinity
        )
    }

    // MARK: - Validation

    /// Returns whether the object's constraints are normalized.
    ///
    /// Constraints are normalized if the minimums are less than or
    /// equal to the corresponding maximums.
    ///
    /// For example, a `BoxConstraints` object with a `minWidth` of 100.0
    /// and a `maxWidth` of 90.0 is not normalized.
    ///
    /// Most of the APIs on `BoxConstraints` expect the constraints to be
    /// normalized and have undefined behavior when they are not. In
    /// debug mode, many of these APIs will assert if the constraints
    /// are not normalized.
    ///
    /// **Dart Source:** `box.dart:526-540`
    public var isNormalized: Bool {
        minWidth >= 0.0 &&
        minWidth <= maxWidth &&
        minHeight >= 0.0 &&
        minHeight <= maxHeight
    }

    /// Asserts that the constraints are valid.
    ///
    /// This might involve checks more detailed than `isNormalized`.
    ///
    /// If the `isAppliedConstraint` argument is true, then even stricter rules
    /// are enforced. This argument is set to true when checking constraints that
    /// are about to be applied to a `RenderObject` during layout, as
    /// opposed to constraints that were given by the parent.
    ///
    /// Returns the same as `isNormalized` if asserts are disabled.
    ///
    /// **Dart Source:** `box.dart:542-621`
    @discardableResult
    public func debugAssertIsValid(
        isAppliedConstraint: Bool = false,
        informationCollector: InformationCollector? = nil
    ) -> Bool {
        assert({
            func throwError(_ message: ErrorSummary) -> Never {
                var diagnostics: [any DiagnosticsNodeProtocol] = [message]
                if let collector = informationCollector {
                    diagnostics.append(contentsOf: collector())
                }
                diagnostics.append(
                    DiagnosticsProperty<BoxConstraints>(
                        "The offending constraints were",
                        self,
                        style: .errorProperty
                    )
                )
                let error = FlutterError(fromParts: diagnostics)
                fatalError("\(error)")
            }

            if minWidth.isNaN || maxWidth.isNaN || minHeight.isNaN || maxHeight.isNaN {
                var affectedFieldsList: [String] = []
                if minWidth.isNaN { affectedFieldsList.append("minWidth") }
                if maxWidth.isNaN { affectedFieldsList.append("maxWidth") }
                if minHeight.isNaN { affectedFieldsList.append("minHeight") }
                if maxHeight.isNaN { affectedFieldsList.append("maxHeight") }
                assert(!affectedFieldsList.isEmpty)
                if affectedFieldsList.count > 1 {
                    let last = affectedFieldsList.removeLast()
                    affectedFieldsList.append("and \(last)")
                }
                let whichFields: String
                switch affectedFieldsList.count {
                case 1:
                    whichFields = affectedFieldsList[0]
                case 2:
                    whichFields = affectedFieldsList.joined(separator: " ")
                default:
                    whichFields = affectedFieldsList.joined(separator: ", ")
                }
                throwError(
                    ErrorSummary(
                        "BoxConstraints has \(affectedFieldsList.count == 1 ? "a NaN value" : "NaN values") in \(whichFields)."
                    )
                )
            }
            if minWidth < 0.0 && minHeight < 0.0 {
                throwError(
                    ErrorSummary(
                        "BoxConstraints has both a negative minimum width and a negative minimum height."
                    )
                )
            }
            if minWidth < 0.0 {
                throwError(
                    ErrorSummary("BoxConstraints has a negative minimum width.")
                )
            }
            if minHeight < 0.0 {
                throwError(
                    ErrorSummary("BoxConstraints has a negative minimum height.")
                )
            }
            if maxWidth < minWidth && maxHeight < minHeight {
                throwError(
                    ErrorSummary(
                        "BoxConstraints has both width and height constraints non-normalized."
                    )
                )
            }
            if maxWidth < minWidth {
                throwError(
                    ErrorSummary("BoxConstraints has non-normalized width constraints.")
                )
            }
            if maxHeight < minHeight {
                throwError(
                    ErrorSummary("BoxConstraints has non-normalized height constraints.")
                )
            }
            if isAppliedConstraint {
                if minWidth.isInfinite && minHeight.isInfinite {
                    throwError(
                        ErrorSummary(
                            "BoxConstraints forces an infinite width and infinite height."
                        )
                    )
                }
                if minWidth.isInfinite {
                    throwError(
                        ErrorSummary("BoxConstraints forces an infinite width.")
                    )
                }
                if minHeight.isInfinite {
                    throwError(
                        ErrorSummary("BoxConstraints forces an infinite height.")
                    )
                }
            }
            assert(isNormalized)
            return true
        }())
        return isNormalized
    }

    /// Returns a box constraints that is normalized.
    ///
    /// The returned `maxWidth` is at least as large as the `minWidth`. Similarly,
    /// the returned `maxHeight` is at least as large as the `minHeight`.
    ///
    /// **Dart Source:** `box.dart:623-639`
    public func normalize() -> BoxConstraints {
        if isNormalized {
            return self
        }
        let normalizedMinWidth = minWidth >= 0.0 ? minWidth : 0.0
        let normalizedMinHeight = minHeight >= 0.0 ? minHeight : 0.0
        return BoxConstraints(
            minWidth: normalizedMinWidth,
            maxWidth: normalizedMinWidth > maxWidth ? normalizedMinWidth : maxWidth,
            minHeight: normalizedMinHeight,
            maxHeight: normalizedMinHeight > maxHeight ? normalizedMinHeight : maxHeight
        )
    }

    // MARK: - Equatable & Hashable

    /// Returns whether two `BoxConstraints` are equal.
    ///
    /// **Dart Source:** `box.dart:641-656`
    public static func == (lhs: BoxConstraints, rhs: BoxConstraints) -> Bool {
        lhs.minWidth == rhs.minWidth &&
        lhs.maxWidth == rhs.maxWidth &&
        lhs.minHeight == rhs.minHeight &&
        lhs.maxHeight == rhs.maxHeight
    }

    /// Hashes the essential components of this `BoxConstraints`.
    ///
    /// **Dart Source:** `box.dart:658-662`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(minWidth)
        hasher.combine(maxWidth)
        hasher.combine(minHeight)
        hasher.combine(maxHeight)
    }

    // MARK: - CustomStringConvertible

    /// A string representation of this `BoxConstraints`.
    ///
    /// **Dart Source:** `box.dart:664-686`
    public var description: String {
        let annotation = isNormalized ? "" : "; NOT NORMALIZED"
        if minWidth == .infinity && minHeight == .infinity {
            return "BoxConstraints(biggest\(annotation))"
        }
        if minWidth == 0 && maxWidth == .infinity &&
           minHeight == 0 && maxHeight == .infinity {
            return "BoxConstraints(unconstrained\(annotation))"
        }
        func describe(_ min: Double, _ max: Double, _ dim: String) -> String {
            if min == max {
                return "\(dim)=\(String(format: "%.1f", min))"
            }
            return "\(String(format: "%.1f", min))<=\(dim)<=\(String(format: "%.1f", max))"
        }
        let width = describe(minWidth, maxWidth, "w")
        let height = describe(minHeight, maxHeight, "h")
        return "BoxConstraints(\(width), \(height)\(annotation))"
    }
}

// MARK: - BoxHitTest Typedefs

/// Method signature for hit testing a `RenderBox`.
///
/// Used by `BoxHitTestResult.addWithPaintTransform` to hit test children
/// of a `RenderBox`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:698`
public typealias BoxHitTest = (_ result: BoxHitTestResult, _ position: Offset) -> Bool

/// Method signature for hit testing a `RenderBox` with a manually
/// managed position (one that is passed out-of-band).
///
/// Used by `RenderSliverSingleBoxAdapter.hitTestBoxChild` to hit test
/// `RenderBox` children of a `RenderSliver`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:710`
public typealias BoxHitTestWithOutOfBandPosition = (_ result: BoxHitTestResult) -> Bool

// MARK: - BoxHitTestResult

/// The result of performing a hit test on `RenderBox`es.
///
/// An instance of this class is provided to `RenderBox.hitTest` to record the
/// result of the hit test.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:716-939`
public class BoxHitTestResult: HitTestResult {

    /// Creates an empty hit test result for hit testing on `RenderBox`.
    ///
    /// **Dart Source:** `box.dart:718`
    public override init() {
        super.init()
    }

    /// Wraps `result` to create a `HitTestResult` that implements the
    /// `BoxHitTestResult` protocol for hit testing on `RenderBox`es.
    ///
    /// This method is used by `RenderObject`s that adapt between the
    /// `RenderBox`-world and the non-`RenderBox`-world to convert a (subtype of)
    /// `HitTestResult` to a `BoxHitTestResult` for hit testing on `RenderBox`es.
    ///
    /// The `HitTestEntry` instances added to the returned `BoxHitTestResult` are
    /// also added to the wrapped `result` (both share the same underlying data
    /// structure to store `HitTestEntry` instances).
    ///
    /// **Dart Source:** `box.dart:737`
    public init(wrapping result: HitTestResult) {
        super.init(wrap: result)
    }

    /// Transforms `position` to the local coordinate system of a child for
    /// hit-testing the child.
    ///
    /// The actual hit testing of the child needs to be implemented in the
    /// provided `hitTest` callback, which is invoked with the transformed
    /// `position` as argument.
    ///
    /// The provided paint `transform` (which describes the transform from the
    /// child to the parent in 3D) is processed by
    /// `PointerEvent.removePerspectiveTransform` to remove the
    /// perspective component and inverted before it is used to transform
    /// `position` from the coordinate system of the parent to the system of the
    /// child.
    ///
    /// If `transform` is nil it will be treated as the identity transform and
    /// `position` is provided to the `hitTest` callback as-is. If `transform`
    /// cannot be inverted, the `hitTest` callback is not invoked and false is
    /// returned. Otherwise, the return value of the `hitTest` callback is
    /// returned.
    ///
    /// The function returns the return value of the `hitTest` callback.
    ///
    /// **Dart Source:** `box.dart:799-812`
    public func addWithPaintTransform(
        transform: Matrix4?,
        position: Offset,
        hitTest: BoxHitTest
    ) -> Bool {
        var effectiveTransform = transform
        if effectiveTransform != nil {
            effectiveTransform = Matrix4.tryInvert(
                PointerEvent.removePerspectiveTransform(effectiveTransform!)
            )
            if effectiveTransform == nil {
                // Objects are not visible on screen and cannot be hit-tested.
                return false
            }
        }
        return addWithRawTransform(
            transform: effectiveTransform,
            position: position,
            hitTest: hitTest
        )
    }

    /// Convenience method for hit testing children, that are translated by
    /// an `Offset`.
    ///
    /// The actual hit testing of the child needs to be implemented in the
    /// provided `hitTest` callback, which is invoked with the transformed
    /// `position` as argument.
    ///
    /// This method can be used as a convenience over `addWithPaintTransform` if
    /// a parent paints a child at an `offset`.
    ///
    /// A nil value for `offset` is treated as if `Offset.zero` was provided.
    ///
    /// The function returns the return value of the `hitTest` callback.
    ///
    /// **Dart Source:** `box.dart:832-846`
    public func addWithPaintOffset(
        offset: Offset?,
        position: Offset,
        hitTest: BoxHitTest
    ) -> Bool {
        let transformedPosition = offset == nil ? position : position - offset!
        if offset != nil {
            pushOffset(-offset!)
        }
        let isHit = hitTest(self, transformedPosition)
        if offset != nil {
            popTransform()
        }
        return isHit
    }

    /// Transforms `position` to the local coordinate system of a child for
    /// hit-testing the child.
    ///
    /// The actual hit testing of the child needs to be implemented in the
    /// provided `hitTest` callback, which is invoked with the transformed
    /// `position` as argument.
    ///
    /// Unlike `addWithPaintTransform`, the provided `transform` matrix is used
    /// directly to transform `position` without any pre-processing.
    ///
    /// If `transform` is nil it will be treated as the identity transform and
    /// `position` is provided to the `hitTest` callback as-is.
    ///
    /// The function returns the return value of the `hitTest` callback.
    ///
    /// **Dart Source:** `box.dart:867-883`
    public func addWithRawTransform(
        transform: Matrix4?,
        position: Offset,
        hitTest: BoxHitTest
    ) -> Bool {
        let transformedPosition = transform == nil
            ? position
            : MatrixUtils.transformPoint(transform!, position)
        if transform != nil {
            pushTransform(transform!)
        }
        let isHit = hitTest(self, transformedPosition)
        if transform != nil {
            popTransform()
        }
        return isHit
    }

    /// Pass-through method for adding a hit test while manually managing
    /// the position transformation logic.
    ///
    /// The actual hit testing of the child needs to be implemented in the
    /// provided `hitTest` callback. The position needs to be handled by
    /// the caller.
    ///
    /// The function returns the return value of the `hitTest` callback.
    ///
    /// A `paintOffset`, `paintTransform`, or `rawTransform` should be
    /// passed to the method to update the hit test stack.
    ///
    ///  * `paintOffset` has the semantics of the `offset` passed to
    ///    `addWithPaintOffset`.
    ///
    ///  * `paintTransform` has the semantics of the `transform` passed to
    ///    `addWithPaintTransform`, except that it must be invertible; it
    ///    is the responsibility of the caller to ensure this.
    ///
    ///  * `rawTransform` has the semantics of the `transform` passed to
    ///    `addWithRawTransform`.
    ///
    /// Exactly one of these must be non-nil.
    ///
    /// **Dart Source:** `box.dart:913-938`
    public func addWithOutOfBandPosition(
        paintOffset: Offset? = nil,
        paintTransform: Matrix4? = nil,
        rawTransform: Matrix4? = nil,
        hitTest: BoxHitTestWithOutOfBandPosition
    ) -> Bool {
        assert(
            (paintOffset == nil && paintTransform == nil && rawTransform != nil)
                || (paintOffset == nil && paintTransform != nil && rawTransform == nil)
                || (paintOffset != nil && paintTransform == nil && rawTransform == nil),
            "Exactly one transform or offset argument must be provided."
        )
        if paintOffset != nil {
            pushOffset(-paintOffset!)
        } else if rawTransform != nil {
            pushTransform(rawTransform!)
        } else {
            assert(paintTransform != nil)
            let inverted = Matrix4.tryInvert(
                PointerEvent.removePerspectiveTransform(paintTransform!)
            )
            assert(inverted != nil, "paintTransform must be invertible.")
            pushTransform(inverted!)
        }
        let isHit = hitTest(self)
        popTransform()
        return isHit
    }
}

// MARK: - BoxHitTestEntry

/// A hit test entry used by `RenderBox`.
///
/// Note: In Dart this extends `HitTestEntry<RenderBox>`. Since `RenderBox`
/// is not yet migrated, this uses `AnyHitTestTarget` as the type parameter.
/// This will be updated when `RenderBox` is available.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:942-951`
public class BoxHitTestEntry: HitTestEntry<AnyHitTestTarget> {

    /// Creates a box hit test entry.
    ///
    /// **Dart Source:** `box.dart:944`
    public init(_ target: AnyHitTestTarget, _ localPosition: Offset) {
        self.localPosition = localPosition
        super.init(target)
    }

    /// The position of the hit test in the local coordinates of `target`.
    ///
    /// **Dart Source:** `box.dart:947`
    public let localPosition: Offset

    // MARK: - CustomStringConvertible

    /// **Dart Source:** `box.dart:950`
    public override var description: String {
        return "\(describeIdentity(target))@\(localPosition)"
    }
}

// MARK: - BoxParentData

/// Parent data used by `RenderBox` and its subclasses.
///
/// Stores an offset from the parent's origin used to position the child
/// during painting.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:953-969`
open class BoxParentData: ParentData {
    /// The offset at which to paint the child in the parent's coordinate system.
    ///
    /// **Dart Source:** `box.dart:965`
    public var offset: Offset = .zero

    /// **Dart Source:** `box.dart:967-968`
    open override var description: String {
        "offset=\(offset)"
    }
}

// MARK: - ContainerParentDataMixin

/// Protocol representing the `ContainerParentDataMixin<ChildType>` from Dart.
///
/// In Dart, this is a mixin on `ParentData` that provides linked-list pointers
/// for managing children in a `ContainerRenderObjectMixin`. Since Swift does
/// not support generic mixins, this is expressed as a protocol.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/object.dart:4200-4206`
public protocol ContainerParentDataProtocol: AnyObject {
    associatedtype ChildType: RenderObject

    /// The previous sibling in the parent's child list.
    ///
    /// **Dart Source:** `object.dart:4202`
    var previousSibling: ChildType? { get set }

    /// The next sibling in the parent's child list.
    ///
    /// **Dart Source:** `object.dart:4205`
    var nextSibling: ChildType? { get set }
}

// MARK: - ContainerBoxParentData

/// Abstract `ParentData` subclass for `RenderBox` subclasses that want the
/// `ContainerRenderObjectMixin`.
///
/// This is a convenience class that combines `BoxParentData` with
/// `ContainerParentDataProtocol`, providing both the offset for painting
/// and the linked-list pointers for child management.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:971-977`
open class ContainerBoxParentData<ChildType: RenderObject>: BoxParentData,
    ContainerParentDataProtocol
{
    /// The previous sibling in the parent's child list.
    ///
    /// `weak`, deliberately diverging from Dart, and load bearing. With both
    /// sibling pointers strong, every adjacent pair of children is a retain
    /// cycle through their parentData (A→pd_A.next→B, B→pd_B.previous→A).
    /// Removing children one at a time unlinks cleanly — but when a whole
    /// container render object is dropped (its element deactivated), nothing
    /// walks its child list, and the children then keep each other alive
    /// forever with everything they own. Dart's GC collects such cycles;
    /// under ARC this leaked one full row-set of RenderParagraphs per styled
    /// dump in the terminal (~20 MB/pass, unbounded). Ownership flows forward
    /// only: parent → firstChild → nextSibling → … keeps every child alive
    /// while the list is intact, so the weak back-pointer never dangles for
    /// a live list.
    ///
    /// **Dart Source:** `object.dart:4202`
    public weak var previousSibling: ChildType?

    /// The next sibling in the parent's child list.
    ///
    /// **Dart Source:** `object.dart:4205`
    public var nextSibling: ChildType?
}

// MARK: - BaselineOffset

/// A wrapper that represents the baseline location of a `RenderBox`.
///
/// A `nil` offset (accessed via `BaselineOffset.noBaseline`) indicates that
/// the associated `RenderBox` does not have any baselines.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:980-1010`
public struct BaselineOffset: Equatable, Sendable {
    /// The baseline offset value, or `nil` if there is no baseline.
    ///
    /// **Dart Source:** `box.dart:980`
    public let offset: Double?

    /// Creates a `BaselineOffset` with the given offset value.
    ///
    /// **Dart Source:** `box.dart:980`
    public init(_ offset: Double?) {
        self.offset = offset
    }

    /// A value that indicates that the associated `RenderBox` does not have any
    /// baselines.
    ///
    /// `BaselineOffset.noBaseline` is an identity element in most binary
    /// operations involving two `BaselineOffset`s (such as `minOf`), for render
    /// objects with no baselines typically do not contribute to the baseline
    /// offset of their parents.
    ///
    /// **Dart Source:** `box.dart:988`
    public static let noBaseline = BaselineOffset(nil)

    /// Returns a new baseline location that is `offset` pixels further away from
    /// the origin than this, or unchanged if this is `noBaseline`.
    ///
    /// **Dart Source:** `box.dart:992-995`
    public static func + (lhs: BaselineOffset, rhs: Double) -> BaselineOffset {
        guard let value = lhs.offset else {
            return lhs
        }
        return BaselineOffset(value + rhs)
    }

    /// Compares this `BaselineOffset` and `other`, and returns whichever is
    /// closer to the origin.
    ///
    /// When both this and `other` are `noBaseline`, this method returns
    /// `noBaseline`. When one of them is `noBaseline`, this method returns the
    /// other operand that's not `noBaseline`.
    ///
    /// **Dart Source:** `box.dart:1003-1009`
    public func minOf(_ other: BaselineOffset) -> BaselineOffset {
        switch (self.offset, other.offset) {
        case let (lhs?, rhs?):
            return lhs >= rhs ? other : self
        case let (lhs?, nil):
            return BaselineOffset(lhs)
        case (nil, _):
            return other
        }
    }
}

// MARK: - CachedLayoutCalculation

/// Protocol for memoized layout computations.
///
/// Implementations cache the result of a layout computation keyed by input,
/// avoiding redundant work during the layout phase. The generic parameters
/// define the input constraint type and the output result type.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:1031-1043`
internal protocol CachedLayoutCalculation {
    associatedtype InputType: Hashable
    associatedtype OutputType

    /// Looks up or computes a cached layout value.
    ///
    /// If the `cacheStorage` already contains a result for `input`, the
    /// cached value is returned. Otherwise, `computer` is invoked to produce
    /// the result, which is then stored and returned.
    ///
    /// **Dart Source:** `box.dart:1035`
    func memoize(
        _ cacheStorage: LayoutCacheStorage,
        input: InputType,
        computer: (InputType) -> OutputType
    ) -> OutputType
}

// MARK: - DryLayoutCalculation

/// Cached layout calculation for dry layout (constraints to size).
///
/// Memoizes the result of `computeDryLayout` on a `RenderBox`, caching
/// the `Size` produced for each set of `BoxConstraints`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:1045-1070`
internal struct DryLayoutCalculation: CachedLayoutCalculation {
    typealias InputType = BoxConstraints
    typealias OutputType = Size

    /// Looks up or computes a cached dry layout size for the given constraints.
    ///
    /// **Dart Source:** `box.dart:1049-1058`
    func memoize(
        _ cacheStorage: LayoutCacheStorage,
        input: BoxConstraints,
        computer: (BoxConstraints) -> Size
    ) -> Size {
        if let cached = cacheStorage.cachedDryLayoutSizes[input] {
            return cached
        }
        let result = computer(input)
        cacheStorage.cachedDryLayoutSizes[input] = result
        return result
    }
}

// MARK: - BaselineCalculation

/// Cache key for baseline lookups, combining constraints and baseline type.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:1072-1104`
internal struct BaselineCacheKey: Hashable {
    let constraints: BoxConstraints
    let baseline: TextBaseline
}

/// Cached layout calculation for baseline offset computation.
///
/// Memoizes the result of `computeDryBaseline` on a `RenderBox`, caching
/// the `BaselineOffset` produced for each combination of `BoxConstraints`
/// and `TextBaseline`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:1072-1104`
internal struct BaselineCalculation: CachedLayoutCalculation {
    typealias InputType = BaselineCacheKey
    typealias OutputType = BaselineOffset

    /// Looks up or computes a cached baseline offset for the given key.
    ///
    /// The cache is partitioned by `TextBaseline` type (alphabetic vs
    /// ideographic), matching the Dart implementation's separate maps.
    ///
    /// **Dart Source:** `box.dart:1077-1089`
    func memoize(
        _ cacheStorage: LayoutCacheStorage,
        input: BaselineCacheKey,
        computer: (BaselineCacheKey) -> BaselineOffset
    ) -> BaselineOffset {
        let cache: [BoxConstraints: BaselineOffset]
        switch input.baseline {
        case .alphabetic:
            cache = cacheStorage.cachedAlphabeticBaseline
        case .ideographic:
            cache = cacheStorage.cachedIdeographicBaseline
        }
        if let cached = cache[input.constraints] {
            return cached
        }
        let result = computer(input)
        switch input.baseline {
        case .alphabetic:
            cacheStorage.cachedAlphabeticBaseline[input.constraints] = result
        case .ideographic:
            cacheStorage.cachedIdeographicBaseline[input.constraints] = result
        }
        return result
    }
}

// MARK: - IntrinsicDimensionKind

/// Discriminator for intrinsic dimension calculations.
///
/// Identifies which intrinsic dimension is being computed, used as part of
/// the cache key in `LayoutCacheStorage`.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:1108-1132`
internal enum IntrinsicDimensionKind: Hashable {
    /// The minimum width given a maximum height.
    case minWidth
    /// The maximum width given a maximum height.
    case maxWidth
    /// The minimum height given a maximum width.
    case minHeight
    /// The maximum height given a maximum width.
    case maxHeight
}

// MARK: - IntrinsicDimensionsCacheKey

/// Cache key for intrinsic dimension lookups, combining the dimension kind
/// and the input argument (the cross-axis extent).
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:1116-1117`
internal struct IntrinsicDimensionsCacheKey: Hashable {
    let kind: IntrinsicDimensionKind
    let argument: Double
}

// MARK: - LayoutCacheStorage

/// Storage for memoized layout computation results.
///
/// Holds dictionaries that cache intrinsic dimensions, dry layout sizes,
/// and baseline offsets. The `clear()` method resets all caches and returns
/// whether any cached data was present.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:1134-1157`
internal class LayoutCacheStorage {
    /// Cached intrinsic dimension results, keyed by dimension kind and argument.
    ///
    /// **Dart Source:** `box.dart:1135`
    var cachedIntrinsicDimensions: [IntrinsicDimensionsCacheKey: Double] = [:]

    /// Cached dry layout sizes, keyed by box constraints.
    ///
    /// **Dart Source:** `box.dart:1136`
    var cachedDryLayoutSizes: [BoxConstraints: Size] = [:]

    /// Cached alphabetic baseline offsets, keyed by box constraints.
    ///
    /// **Dart Source:** `box.dart:1137`
    var cachedAlphabeticBaseline: [BoxConstraints: BaselineOffset] = [:]

    /// Cached ideographic baseline offsets, keyed by box constraints.
    ///
    /// **Dart Source:** `box.dart:1138`
    var cachedIdeographicBaseline: [BoxConstraints: BaselineOffset] = [:]

    /// Clears all cached layout data.
    ///
    /// Returns `true` if any cached data was present before clearing.
    ///
    /// **Dart Source:** `box.dart:1142-1156`
    @discardableResult
    func clear() -> Bool {
        let hasCache =
            !cachedDryLayoutSizes.isEmpty
            || !cachedIntrinsicDimensions.isEmpty
            || !cachedAlphabeticBaseline.isEmpty
            || !cachedIdeographicBaseline.isEmpty

        if hasCache {
            cachedDryLayoutSizes.removeAll()
            cachedIntrinsicDimensions.removeAll()
            cachedAlphabeticBaseline.removeAll()
            cachedIdeographicBaseline.removeAll()
        }
        return hasCache
    }
}

// MARK: - RenderBox

/// A render object in a 2D Cartesian coordinate system.
///
/// The `size` of each box is expressed as a width and a height. Each box has
/// its own coordinate system in which its upper left corner is placed at (0,
/// 0). The lower right corner of the box is therefore at (width, height). The
/// box contains all the points including the upper left corner and extending
/// to, but not including, the lower right corner.
///
/// Box layout is performed by passing a `BoxConstraints` object down the tree.
/// The box constraints establish a min and max value for the child's width and
/// height. In determining its size, the child must respect the constraints
/// given to it by its parent.
///
/// This protocol is sufficient for expressing a number of common box layout
/// data flows. For example, to implement a width-in-height-out data flow, call
/// your child's `layout` function with a set of box constraints with a tight
/// width value (and pass true for parentUsesSize). After the child determines
/// its height, use the child's height to determine your size.
///
/// **Dart Source:** `box.dart:1159-3278`
open class RenderBox: RenderObject {

    // MARK: - Layout Cache Storage

    /// Storage for memoized layout computation results (intrinsic dimensions,
    /// dry layout sizes, baseline offsets).
    ///
    /// **Dart Source:** `box.dart:1580`
    private var _layoutCacheStorage = LayoutCacheStorage()

    // MARK: - Setup Parent Data

    /// Sets up `BoxParentData` for children.
    ///
    /// If the child's `parentData` is not already a `BoxParentData`, it is
    /// replaced with a new `BoxParentData` instance.
    ///
    /// **Dart Source:** `box.dart:1574-1579`
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is BoxParentData) {
            child.parentData = BoxParentData()
        }
    }

    // MARK: - Size Management

    /// The backing store for the render box's size.
    private var _size: Size?

    /// The size of this render box computed during layout.
    ///
    /// This value is stale whenever this object is marked as needing layout.
    /// During `performLayout`, do not read the size of a child unless you pass
    /// true for parentUsesSize when calling the child's `layout` function.
    ///
    /// The size of a box should be set only during the box's `performLayout` or
    /// `performResize` functions. If you wish to change the size of a box outside
    /// of those functions, call `markNeedsLayout` instead to schedule a layout of
    /// the box.
    ///
    /// **Dart Source:** `box.dart:2240-2366`
    public var size: Size {
        get {
            assert(hasSize, "RenderBox was not laid out: \(self)")
            assert(
                {
                    // In debug mode, the Dart source wraps the size in a _DebugSize
                    // that tracks ownership and validates access. We skip that
                    // complexity for now but validate that _size is non-nil.
                    // TODO: Add _DebugSize-equivalent tracking for parentUsesSize validation
                    return true
                }()
            )
            return _size!
        }
        set {
            assert(
                {
                    // In Dart, the setter validates that the size is being set
                    // from the correct context (performLayout or performResize).
                    // TODO: Add full debug validation matching box.dart:2312-2366
                    return true
                }()
            )
            _size = newValue
        }
    }

    /// Whether this render box has been laid out and has a `size`.
    ///
    /// **Dart Source:** `box.dart:2237-2238`
    public var hasSize: Bool { _size != nil }

    // MARK: - Constraints

    /// The box constraints most recently received from the parent.
    ///
    /// This is a convenience accessor that casts the generic `Constraints`
    /// from `RenderObject` to `BoxConstraints`.
    ///
    /// **Dart Source:** `box.dart` (implicit via `RenderObject.constraints`)
    public var boxConstraints: BoxConstraints {
        return constraints as! BoxConstraints
    }

    // MARK: - Mark Needs Layout

    /// Clears the layout cache when layout is invalidated, then calls super.
    ///
    /// If the layout cache had data, this indicates the parent may depend on
    /// this render box's intrinsic dimensions or baseline, so the parent is
    /// also marked as needing layout regardless of relayout boundaries.
    ///
    /// **Dart Source:** `box.dart:2838-2860`
    open override func markNeedsLayout() {
        if _layoutCacheStorage.clear() && parent != nil {
            markParentNeedsLayout()
            return
        }
        super.markNeedsLayout()
    }

    // MARK: - Layout

    /// Updates the render box's size using only the constraints.
    ///
    /// By default this method sets `size` to the result of `computeDryLayout`
    /// called with the current constraints. Instead of overriding this method,
    /// consider overriding `computeDryLayout`.
    ///
    /// This is called only if `sizedByParent` is true.
    ///
    /// **Dart Source:** `box.dart:2862-2872`
    open override func performResize() {
        // Default behavior for subclasses that have sizedByParent = true
        size = computeDryLayout(boxConstraints)
        assert(size.isFinite)
    }

    /// Do the work of computing the layout for this render object.
    ///
    /// Do not call this function directly: call `layout` instead. This function
    /// is called by `layout` when there is actually work to be done by this
    /// render object during layout.
    ///
    /// **Dart Source:** `box.dart:2874-2889`
    open override func performLayout() {
        assert(
            {
                if !sizedByParent {
                    assertionFailure(
                        "\(type(of: self)) did not implement performLayout(). "
                        + "RenderBox subclasses need to either override performLayout() to "
                        + "set a size and lay out any children, or, set sizedByParent to true "
                        + "so that performResize() sizes the render object."
                    )
                }
                return true
            }()
        )
    }

    // MARK: - Intrinsic Dimensions

    /// Returns the minimum width that this box could be without failing to
    /// correctly paint its contents within itself, without clipping.
    ///
    /// The height argument may give a specific height to assume. The given height
    /// can be infinite, meaning that the intrinsic width in an unconstrained
    /// environment is being requested. The given height should never be negative.
    ///
    /// This function should only be called on one's children. Calling this
    /// function couples the child with the parent so that when the child's layout
    /// changes, the parent is notified (via `markNeedsLayout`).
    ///
    /// Do not override this method. Instead, implement `computeMinIntrinsicWidth`.
    ///
    /// **Dart Source:** `box.dart:1636-1662`
    public func getMinIntrinsicWidth(_ height: Double) -> Double {
        assert(height >= 0.0, "The height argument to getMinIntrinsicWidth was negative.")
        let key = IntrinsicDimensionsCacheKey(kind: .minWidth, argument: height)
        if let cached = _layoutCacheStorage.cachedIntrinsicDimensions[key] {
            return cached
        }
        let result = computeMinIntrinsicWidth(height)
        assert(result >= 0.0)
        _layoutCacheStorage.cachedIntrinsicDimensions[key] = result
        return result
    }

    /// Returns the smallest width beyond which increasing the width never
    /// decreases the preferred height.
    ///
    /// The height argument may give a specific height to assume. The given height
    /// can be infinite, meaning that the intrinsic width in an unconstrained
    /// environment is being requested. The given height should never be negative.
    ///
    /// This function should only be called on one's children. Calling this
    /// function couples the child with the parent so that when the child's layout
    /// changes, the parent is notified (via `markNeedsLayout`).
    ///
    /// Do not override this method. Instead, implement `computeMaxIntrinsicWidth`.
    ///
    /// **Dart Source:** `box.dart:1770-1804`
    public func getMaxIntrinsicWidth(_ height: Double) -> Double {
        assert(height >= 0.0, "The height argument to getMaxIntrinsicWidth was negative.")
        let key = IntrinsicDimensionsCacheKey(kind: .maxWidth, argument: height)
        if let cached = _layoutCacheStorage.cachedIntrinsicDimensions[key] {
            return cached
        }
        let result = computeMaxIntrinsicWidth(height)
        assert(result >= 0.0)
        _layoutCacheStorage.cachedIntrinsicDimensions[key] = result
        return result
    }

    /// Returns the minimum height that this box could be without failing to
    /// correctly paint its contents within itself, without clipping.
    ///
    /// The width argument may give a specific width to assume. The given width
    /// can be infinite, meaning that the intrinsic height in an unconstrained
    /// environment is being requested. The given width should never be negative.
    ///
    /// This function should only be called on one's children. Calling this
    /// function couples the child with the parent so that when the child's layout
    /// changes, the parent is notified (via `markNeedsLayout`).
    ///
    /// Do not override this method. Instead, implement `computeMinIntrinsicHeight`.
    ///
    /// **Dart Source:** `box.dart:1848-1881`
    public func getMinIntrinsicHeight(_ width: Double) -> Double {
        assert(width >= 0.0, "The width argument to getMinIntrinsicHeight was negative.")
        let key = IntrinsicDimensionsCacheKey(kind: .minHeight, argument: width)
        if let cached = _layoutCacheStorage.cachedIntrinsicDimensions[key] {
            return cached
        }
        let result = computeMinIntrinsicHeight(width)
        assert(result >= 0.0)
        _layoutCacheStorage.cachedIntrinsicDimensions[key] = result
        return result
    }

    /// Returns the smallest height beyond which increasing the height never
    /// decreases the preferred width.
    ///
    /// The width argument may give a specific width to assume. The given width
    /// can be infinite, meaning that the intrinsic height in an unconstrained
    /// environment is being requested. The given width should never be negative.
    ///
    /// This function should only be called on one's children. Calling this
    /// function couples the child with the parent so that when the child's layout
    /// changes, the parent is notified (via `markNeedsLayout`).
    ///
    /// Do not override this method. Instead, implement `computeMaxIntrinsicHeight`.
    ///
    /// **Dart Source:** `box.dart:1923-1957`
    public func getMaxIntrinsicHeight(_ width: Double) -> Double {
        assert(width >= 0.0, "The width argument to getMaxIntrinsicHeight was negative.")
        let key = IntrinsicDimensionsCacheKey(kind: .maxHeight, argument: width)
        if let cached = _layoutCacheStorage.cachedIntrinsicDimensions[key] {
            return cached
        }
        let result = computeMaxIntrinsicHeight(width)
        assert(result >= 0.0)
        _layoutCacheStorage.cachedIntrinsicDimensions[key] = result
        return result
    }

    /// Computes the value returned by `getMinIntrinsicWidth`. Do not call this
    /// function directly, instead, call `getMinIntrinsicWidth`.
    ///
    /// Override in subclasses that implement `performLayout`. This method should
    /// return the minimum width that this box could be without failing to
    /// correctly paint its contents within itself, without clipping.
    ///
    /// The `height` argument will never be negative. It may be infinite.
    ///
    /// This function should never return a negative or infinite value.
    ///
    /// **Dart Source:** `box.dart:1664-1768`
    open func computeMinIntrinsicWidth(_ height: Double) -> Double {
        return 0.0
    }

    /// Computes the value returned by `getMaxIntrinsicWidth`. Do not call this
    /// function directly, instead, call `getMaxIntrinsicWidth`.
    ///
    /// Override in subclasses that implement `performLayout`. This should return
    /// the smallest width beyond which increasing the width never decreases the
    /// preferred height.
    ///
    /// The `height` argument will never be negative. It may be infinite.
    ///
    /// This function should never return a negative or infinite value.
    ///
    /// **Dart Source:** `box.dart:1806-1846`
    open func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        return 0.0
    }

    /// Computes the value returned by `getMinIntrinsicHeight`. Do not call this
    /// function directly, instead, call `getMinIntrinsicHeight`.
    ///
    /// Override in subclasses that implement `performLayout`. Should return the
    /// minimum height that this box could be without failing to correctly paint
    /// its contents within itself, without clipping.
    ///
    /// The `width` argument will never be negative. It may be infinite.
    ///
    /// This function should never return a negative or infinite value.
    ///
    /// **Dart Source:** `box.dart:1883-1921`
    open func computeMinIntrinsicHeight(_ width: Double) -> Double {
        return 0.0
    }

    /// Computes the value returned by `getMaxIntrinsicHeight`. Do not call this
    /// function directly, instead, call `getMaxIntrinsicHeight`.
    ///
    /// Override in subclasses that implement `performLayout`. Should return the
    /// smallest height beyond which increasing the height never decreases the
    /// preferred width.
    ///
    /// The `width` argument will never be negative. It may be infinite.
    ///
    /// This function should never return a negative or infinite value.
    ///
    /// **Dart Source:** `box.dart:1959-1999`
    open func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        return 0.0
    }

    // MARK: - Dry Layout

    /// Returns the `Size` that this `RenderBox` would like to be given the
    /// provided `BoxConstraints`.
    ///
    /// The size returned by this method is guaranteed to be the same size that
    /// this `RenderBox` computes for itself during layout given the same
    /// constraints.
    ///
    /// This layout is called "dry" layout as opposed to the regular "wet" layout
    /// run performed by `performLayout` because it computes the desired size for
    /// the given constraints without changing any internal state.
    ///
    /// Do not override this method. Instead, implement `computeDryLayout`.
    ///
    /// **Dart Source:** `box.dart:2001-2038`
    public func getDryLayout(_ constraints: BoxConstraints) -> Size {
        if let cached = _layoutCacheStorage.cachedDryLayoutSizes[constraints] {
            return cached
        }
        let result = computeDryLayout(constraints)
        _layoutCacheStorage.cachedDryLayoutSizes[constraints] = result
        return result
    }

    /// Computes the value returned by `getDryLayout`. Do not call this
    /// function directly, instead, call `getDryLayout`.
    ///
    /// Override in subclasses that implement `performLayout` or `performResize`
    /// or when setting `sizedByParent` to true without overriding
    /// `performResize`. This method should return the `Size` that this
    /// `RenderBox` would like to be given the provided `BoxConstraints`.
    ///
    /// The size returned by this method must match the `size` that the
    /// `RenderBox` will compute for itself in `performLayout` (or
    /// `performResize`, if `sizedByParent` is true).
    ///
    /// This layout is called "dry" layout as opposed to the regular "wet" layout
    /// run performed by `performLayout` because it computes the desired size for
    /// the given constraints without changing any internal state.
    ///
    /// **Dart Source:** `box.dart:2040-2086`
    open func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return .zero
    }

    // MARK: - Baselines

    /// Returns the distance from the top of the box to the first baseline of the
    /// box's contents for the given `constraints`, or `nil` if this `RenderBox`
    /// does not have any baselines.
    ///
    /// This method calls `computeDryBaseline` under the hood and caches the result.
    /// `RenderBox` subclasses typically don't override `getDryBaseline`. Instead,
    /// consider overriding `computeDryBaseline` such that it returns a baseline
    /// location that is consistent with `getDistanceToActualBaseline`.
    ///
    /// The "dry" in the method name means this method, like `getDryLayout`, has
    /// no observable side effects when called, as opposed to "wet" layout methods
    /// such as `performLayout`.
    ///
    /// **Dart Source:** `box.dart:2088-2131`
    public func getDryBaseline(_ constraints: BoxConstraints, _ baseline: TextBaseline) -> BaselineOffset {
        let cache: [BoxConstraints: BaselineOffset]
        switch baseline {
        case .alphabetic:
            cache = _layoutCacheStorage.cachedAlphabeticBaseline
        case .ideographic:
            cache = _layoutCacheStorage.cachedIdeographicBaseline
        }
        if let cached = cache[constraints] {
            return cached
        }
        let result = BaselineOffset(computeDryBaseline(constraints, baseline))
        switch baseline {
        case .alphabetic:
            _layoutCacheStorage.cachedAlphabeticBaseline[constraints] = result
        case .ideographic:
            _layoutCacheStorage.cachedIdeographicBaseline[constraints] = result
        }
        return result
    }

    /// Computes the value returned by `getDryBaseline`.
    ///
    /// This method is for overriding only and shouldn't be called directly. To
    /// get this `RenderBox`'s speculative baseline location for the given
    /// `constraints`, call `getDryBaseline` instead.
    ///
    /// The "dry" in the method name means the implementation must not produce
    /// observable side effects when called.
    ///
    /// The implementation must return a value that represents the distance from
    /// the top of the box to the first baseline of the box's contents, for the
    /// given `constraints`, or `nil` if the `RenderBox` has no baselines.
    ///
    /// **Dart Source:** `box.dart:2149-2197`
    open func computeDryBaseline(_ constraints: BoxConstraints, _ baseline: TextBaseline) -> Double? {
        return nil
    }

    /// Returns the distance from the y-coordinate of the position of the box to
    /// the y-coordinate of the first given baseline in the box's contents.
    ///
    /// Used by certain layout models to align adjacent boxes on a common
    /// baseline, regardless of padding, font size differences, etc. If there is
    /// no baseline, this function returns the distance from the y-coordinate of
    /// the position of the box to the y-coordinate of the bottom of the box
    /// (i.e., the height of the box) unless the caller passes true
    /// for `onlyReal`, in which case the function returns `nil`.
    ///
    /// Only call this function after calling `layout` on this box. You
    /// are only allowed to call this from the parent of this box during
    /// that parent's `performLayout` or `paint` functions.
    ///
    /// When implementing a `RenderBox` subclass, to override the baseline
    /// computation, override `computeDistanceToActualBaseline`.
    ///
    /// **Dart Source:** `box.dart:2450-2499`
    public func getDistanceToBaseline(_ baseline: TextBaseline, onlyReal: Bool = false) -> Double? {
        let result = getDistanceToActualBaseline(baseline)
        if result == nil && !onlyReal {
            return size.height
        }
        return result
    }

    /// Calls `computeDistanceToActualBaseline` and caches the result.
    ///
    /// This function must only be called from `getDistanceToBaseline` and
    /// `computeDistanceToActualBaseline`. Do not call this function directly
    /// from outside those two methods.
    ///
    /// **Dart Source:** `box.dart:2501-2519`
    open func getDistanceToActualBaseline(_ baseline: TextBaseline) -> Double? {
        let cache: [BoxConstraints: BaselineOffset]
        switch baseline {
        case .alphabetic:
            cache = _layoutCacheStorage.cachedAlphabeticBaseline
        case .ideographic:
            cache = _layoutCacheStorage.cachedIdeographicBaseline
        }
        if let cached = cache[boxConstraints] {
            return cached.offset
        }
        let result = BaselineOffset(computeDistanceToActualBaseline(baseline))
        switch baseline {
        case .alphabetic:
            _layoutCacheStorage.cachedAlphabeticBaseline[boxConstraints] = result
        case .ideographic:
            _layoutCacheStorage.cachedIdeographicBaseline[boxConstraints] = result
        }
        return result.offset
    }

    /// Returns the distance from the y-coordinate of the position of the box to
    /// the y-coordinate of the first given baseline in the box's contents, if
    /// any, or `nil` otherwise.
    ///
    /// Do not call this function directly. If you need to know the baseline of a
    /// child from an invocation of `performLayout` or `paint`, call
    /// `getDistanceToBaseline`.
    ///
    /// Subclasses should override this method to supply the distances to their
    /// baselines.
    ///
    /// **Dart Source:** `box.dart:2521-2555`
    open func computeDistanceToActualBaseline(_ baseline: TextBaseline) -> Double? {
        return nil
    }

    // MARK: - Hit Testing

    /// Determines the set of render objects located at the given position.
    ///
    /// Returns true, and adds any render objects that contain the point to the
    /// given hit test result, if this render object or one of its descendants
    /// absorbs the hit (preventing objects below this one from being hit).
    /// Returns false if the hit can continue to other objects below this one.
    ///
    /// The caller is responsible for transforming `position` from global
    /// coordinates to its location relative to the origin of this `RenderBox`.
    /// This `RenderBox` is responsible for checking whether the given position is
    /// within its bounds.
    ///
    /// **Dart Source:** `box.dart:2904-2958`
    public func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        assert(
            {
                if !hasSize {
                    if debugNeedsLayout {
                        fatalError(
                            "Cannot hit test a render box that has never been laid out."
                        )
                    }
                    fatalError(
                        "Cannot hit test a render box with no size."
                    )
                }
                return true
            }()
        )
        if size.contains(position) {
            if hitTestChildren(result, position: position) || hitTestSelf(position) {
                result.add(BoxHitTestEntry(AnyHitTestTarget(self), position))
                return true
            }
        }
        return false
    }

    /// Override this method if this render object can be hit even if its
    /// children were not hit.
    ///
    /// Returns true if the specified `position` should be considered a hit
    /// on this render object.
    ///
    /// The caller is responsible for transforming `position` from global
    /// coordinates to its location relative to the origin of this `RenderBox`.
    /// This `RenderBox` is responsible for checking whether the given position is
    /// within its bounds.
    ///
    /// Used by `hitTest`. If you override `hitTest` and do not call this
    /// function, then you don't need to implement this function.
    ///
    /// **Dart Source:** `box.dart:2960-2974`
    open func hitTestSelf(_ position: Offset) -> Bool { false }

    /// Override this method to check whether any children are located at the
    /// given position.
    ///
    /// Subclasses should return true if at least one child reported a hit at the
    /// specified position.
    ///
    /// Typically children should be hit-tested in reverse paint order so that
    /// hit tests at locations where children overlap hit the child that is
    /// visually "on top" (i.e., paints later).
    ///
    /// The caller is responsible for transforming `position` from global
    /// coordinates to its location relative to the origin of this `RenderBox`.
    /// Likewise, this `RenderBox` is responsible for transforming the position
    /// that it passes to its children when it calls `hitTest` on each child.
    ///
    /// Used by `hitTest`. If you override `hitTest` and do not call this
    /// function, then you don't need to implement this function.
    ///
    /// **Dart Source:** `box.dart:2976-3000`
    open func hitTestChildren(_ result: BoxHitTestResult, position: Offset) -> Bool { false }

    // MARK: - Paint Transform

    /// Multiply the transform from the parent's coordinate system to this box's
    /// coordinate system into the given transform.
    ///
    /// This function is used to convert coordinate systems between boxes.
    /// Subclasses that apply transforms during painting should override this
    /// function to factor those transforms into the calculation.
    ///
    /// The `RenderBox` implementation takes care of adjusting the matrix for the
    /// position of the given child as determined during layout and stored on the
    /// child's `parentData` in the `BoxParentData.offset` field.
    ///
    /// **Dart Source:** `box.dart:3002-3038`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        assert(child.parent === self)
        let childParentData = child.parentData as! BoxParentData
        let offset = childParentData.offset
        transform = Matrix4.translationValues(offset.dx, offset.dy, 0) * transform
    }

    // MARK: - Coordinate Transforms

    /// Convert the given point from the global coordinate system in logical pixels
    /// to the local coordinate system for this box.
    ///
    /// This method will un-project the point from the screen onto the widget,
    /// which makes it different from `MatrixUtils.transformPoint`.
    ///
    /// If the transform from global coordinates to local coordinates is
    /// degenerate, this function returns `Offset.zero`.
    ///
    /// If `ancestor` is non-nil, this function converts the given point from the
    /// coordinate system of `ancestor` (which must be an ancestor of this render
    /// object) instead of from the global coordinate system.
    ///
    /// This method is implemented in terms of `getTransformTo`.
    ///
    /// **Dart Source:** `box.dart:3040-3078`
    public func globalToLocal(_ point: Offset, ancestor: RenderObject? = nil) -> Offset {
        // We want to find point (p) that corresponds to a given point on the
        // screen (s), but that also physically resides on the local render plane,
        // so that it is useful for visually accurate gesture processing in the
        // local space. For that, we can't simply transform 2D screen point to
        // the 3D local space since the screen space lacks the depth component |z|,
        // and so there are many 3D points that correspond to the screen point.
        // We must first unproject the screen point onto the render plane to find
        // the true 3D point that corresponds to the screen point.
        // We do orthogonal unprojection after undoing perspective, in local space.
        // The render plane is specified by renderBox offset (o) and Z axis (n).
        // Unprojection is done by finding the intersection of the view vector (d)
        // with the local X-Y plane: (o-s).dot(n) == (p-s).dot(n), (p-s) == |z|*d.
        var transform = getTransformTo(ancestor)
        let det = transform.invert()
        if det == 0.0 {
            return Offset.zero
        }
        let n = Vector3(0.0, 0.0, 1.0)
        let i = transform.perspectiveTransform(Vector3(0.0, 0.0, 0.0))
        let d = transform.perspectiveTransform(Vector3(0.0, 0.0, 1.0)) - i
        let s = transform.perspectiveTransform(Vector3(point.dx, point.dy, 0.0))
        let p = s - d * (n.dot(s) / n.dot(d))
        return Offset(p.x, p.y)
    }

    /// Convert the given point from the local coordinate system for this box to
    /// the global coordinate system in logical pixels.
    ///
    /// If `ancestor` is non-nil, this function converts the given point to the
    /// coordinate system of `ancestor` (which must be an ancestor of this render
    /// object) instead of to the global coordinate system.
    ///
    /// This method is implemented in terms of `getTransformTo`. If the transform
    /// matrix puts the given `point` on the line at infinity (for instance, when
    /// the transform matrix is the zero matrix), this method returns (NaN, NaN).
    ///
    /// **Dart Source:** `box.dart:3080-3092`
    public func localToGlobal(_ point: Offset, ancestor: RenderObject? = nil) -> Offset {
        return MatrixUtils.transformPoint(getTransformTo(ancestor), point)
    }

    // MARK: - Paint Bounds

    /// Returns a rectangle that contains all the pixels painted by this box.
    ///
    /// The paint bounds can be larger or smaller than `size`, which is the amount
    /// of space this box takes up during layout. For example, if this box casts a
    /// shadow, that shadow might extend beyond the space allocated to this box
    /// during layout.
    ///
    /// The paint bounds are used to size the buffers into which this box paints.
    /// If the box attempts to paint outside its paint bounds, there might not be
    /// enough memory allocated to represent the box's visual appearance, which
    /// can lead to undefined behavior.
    ///
    /// The returned paint bounds are in the local coordinate system of this box.
    ///
    /// **Dart Source:** `box.dart:3094-3108`
    open override var paintBounds: Rect {
        return Offset.zero & size
    }

    // MARK: - Event Handling

    /// Override this method to handle pointer events that hit this render object.
    ///
    /// For `RenderBox` objects, the `entry` argument is a `BoxHitTestEntry`. From this
    /// object you can determine the `PointerDownEvent`'s position in local coordinates.
    /// (This is useful because `PointerEvent.position` is in global coordinates.)
    ///
    /// **Dart Source:** `box.dart:3110-3135`
    open override func handleEvent(_ event: PointerEvent, entry: HitTestEntry<AnyHitTestTarget>) {
        super.handleEvent(event, entry: entry)
    }
}

// MARK: - RenderBoxContainerDefaultsMixin

/// Protocol providing default implementations for container render boxes.
///
/// This mixin provides useful default implementations for hit testing,
/// painting, and baseline computation for boxes with children stored in
/// a linked list using ``ContainerBoxParentData``.
///
/// In Dart this is:
/// ```
/// mixin RenderBoxContainerDefaultsMixin<
///   ChildType extends RenderBox,
///   ParentDataType extends ContainerBoxParentData<ChildType>
/// > on RenderBox, ContainerRenderObjectMixin<ChildType, ParentDataType>
/// ```
///
/// Since Swift does not support generic mixins, this is expressed as a
/// protocol with default implementations via extension. Conforming types
/// must expose the linked-list child pointers (`firstChild`, `lastChild`,
/// `childAfter`, `childBefore`).
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/box.dart:3286-3387`
public protocol RenderBoxContainerDefaults: AnyObject {
    associatedtype ChildType: RenderBox

    /// The first child in the child list.
    var firstChild: ChildType? { get }

    /// The last child in the child list.
    var lastChild: ChildType? { get }

    /// Returns the next sibling of the given child.
    func childAfter(_ child: ChildType) -> ChildType?

    /// Returns the previous sibling of the given child.
    func childBefore(_ child: ChildType) -> ChildType?
}

extension RenderBoxContainerDefaults {

    // MARK: - Baseline Computation

    /// Returns the baseline of the first child with a baseline.
    ///
    /// Useful when the children are displayed vertically in the same order they
    /// appear in the child list.
    ///
    /// **Dart Source:** `box.dart:3295-3307`
    public func defaultComputeDistanceToFirstActualBaseline(_ baseline: TextBaseline) -> Double? {
        var child = firstChild
        while let currentChild = child {
            let childParentData = currentChild.parentData as! ContainerBoxParentData<ChildType>
            let result = currentChild.getDistanceToActualBaseline(baseline)
            if let result = result {
                return result + childParentData.offset.dy
            }
            child = childAfter(currentChild)
        }
        return nil
    }

    /// Returns the minimum baseline value among every child.
    ///
    /// Useful when the vertical position of the children isn't determined by the
    /// order in the child list.
    ///
    /// **Dart Source:** `box.dart:3313-3325`
    public func defaultComputeDistanceToHighestActualBaseline(_ baseline: TextBaseline) -> Double? {
        var minBaseline = BaselineOffset.noBaseline
        var child = firstChild
        while let currentChild = child {
            let childParentData = currentChild.parentData as! ContainerBoxParentData<ChildType>
            let candidate =
                BaselineOffset(currentChild.getDistanceToActualBaseline(baseline))
                + childParentData.offset.dy
            minBaseline = minBaseline.minOf(candidate)
            child = childAfter(currentChild)
        }
        return minBaseline.offset
    }

    // MARK: - Hit Testing

    /// Performs a hit test on each child by walking the child list backwards.
    ///
    /// Stops walking once after the first child reports that it contains the
    /// given point. Returns whether any children contain the given point.
    ///
    /// **Dart Source:** `box.dart:3336-3355`
    public func defaultHitTestChildren(_ result: BoxHitTestResult, position: Offset) -> Bool {
        var child = lastChild
        while let currentChild = child {
            let childParentData = currentChild.parentData as! ContainerBoxParentData<ChildType>
            let isHit = result.addWithPaintOffset(
                offset: childParentData.offset,
                position: position,
                hitTest: { result, transformed in
                    return currentChild.hitTest(result, position: transformed)
                }
            )
            if isHit {
                return true
            }
            child = childBefore(currentChild)
        }
        return false
    }

    // MARK: - Painting

    /// Paints each child by walking the child list forwards.
    ///
    /// **Dart Source:** `box.dart:3363-3370`
    public func defaultPaint(_ context: PaintingContext, _ offset: Offset) {
        var child = firstChild
        while let currentChild = child {
            let childParentData = currentChild.parentData as! ContainerBoxParentData<ChildType>
            context.paintChild(currentChild, childParentData.offset + offset)
            child = childAfter(currentChild)
        }
    }

    // MARK: - Child List Utilities

    /// Returns a list containing the children of this render object.
    ///
    /// This function is useful when you need random-access to the children of
    /// this render object. If you're accessing the children in order, consider
    /// walking the child list directly.
    ///
    /// **Dart Source:** `box.dart:3377-3387`
    public func getChildrenAsList() -> [ChildType] {
        var result: [ChildType] = []
        var child = firstChild
        while let currentChild = child {
            result.append(currentChild)
            child = childAfter(currentChild)
        }
        return result
    }
}
