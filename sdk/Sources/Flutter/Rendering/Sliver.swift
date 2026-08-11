// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Sliver layout model types.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/sliver.dart`

import FlutterSwiftBridge
// MARK: - ItemExtentBuilder

/// Called to get the item extent by the index of item.
///
/// Should return nil if asked to build an item extent with a greater index than
/// exists.
///
/// Used by `ListView.itemExtentBuilder` and `SliverVariedExtentList.itemExtentBuilder`.
///
/// **Dart Source:** `sliver.dart:37`
public typealias ItemExtentBuilder = (_ index: Int, _ dimensions: SliverLayoutDimensions) -> Double?

// MARK: - SliverLayoutDimensions

/// Relates the dimensions of the `RenderSliver` during layout.
///
/// Used by `ListView.itemExtentBuilder` and `SliverVariedExtentList.itemExtentBuilder`.
///
/// **Dart Source:** `sliver.dart:43-93`
public struct SliverLayoutDimensions: Hashable, CustomStringConvertible, Sendable {

    /// The scroll offset, in this sliver's coordinate system, that corresponds to
    /// the earliest visible part of this sliver.
    ///
    /// **Dart Source:** `sliver.dart:53`
    public let scrollOffset: Double

    /// The scroll distance that has been consumed by all `RenderSliver`s that
    /// came before this `RenderSliver`.
    ///
    /// **Dart Source:** `sliver.dart:56`
    public let precedingScrollExtent: Double

    /// The number of pixels the viewport can display in the main axis.
    ///
    /// For a vertical list, this is the height of the viewport.
    ///
    /// **Dart Source:** `sliver.dart:61`
    public let viewportMainAxisExtent: Double

    /// The number of pixels in the cross-axis.
    ///
    /// For a vertical list, this is the width of the sliver.
    ///
    /// **Dart Source:** `sliver.dart:66`
    public let crossAxisExtent: Double

    /// Constructs a `SliverLayoutDimensions` with the specified parameters.
    ///
    /// **Dart Source:** `sliver.dart:45-50`
    public init(
        scrollOffset: Double,
        precedingScrollExtent: Double,
        viewportMainAxisExtent: Double,
        crossAxisExtent: Double
    ) {
        self.scrollOffset = scrollOffset
        self.precedingScrollExtent = precedingScrollExtent
        self.viewportMainAxisExtent = viewportMainAxisExtent
        self.crossAxisExtent = crossAxisExtent
    }

    // MARK: - CustomStringConvertible

    /// A string representation of this `SliverLayoutDimensions`.
    ///
    /// **Dart Source:** `sliver.dart:83-88`
    public var description: String {
        "scrollOffset: \(scrollOffset)"
            + " precedingScrollExtent: \(precedingScrollExtent)"
            + " viewportMainAxisExtent: \(viewportMainAxisExtent)"
            + " crossAxisExtent: \(crossAxisExtent)"
    }
}

// MARK: - GrowthDirection

/// The direction in which a sliver's contents are ordered, relative to the
/// scroll offset axis.
///
/// For example, a vertical alphabetical list that is going `AxisDirection.down`
/// with a `GrowthDirection.forward` would have the A at the top and the Z at
/// the bottom, with the A adjacent to the origin, as would such a list going
/// `AxisDirection.up` with a `GrowthDirection.reverse`. On the other hand, a
/// vertical alphabetical list that is going `AxisDirection.down` with a
/// `GrowthDirection.reverse` would have the Z at the top (at scroll offset
/// zero) and the A below it.
///
/// Most scroll views by default are ordered `GrowthDirection.forward`.
/// Changing the default values of `ScrollView.anchor`,
/// `ScrollView.center`, or both, can configure a scroll view for
/// `GrowthDirection.reverse`.
///
/// See also:
///
///  - `applyGrowthDirectionToAxisDirection`, which returns the direction in
///    which the scroll offset increases.
///
/// **Dart Source:** `sliver.dart:129-149`
public enum GrowthDirection: Sendable {
    /// This sliver's contents are ordered in the same direction as the
    /// `AxisDirection`. For example, a vertical alphabetical list that is going
    /// `AxisDirection.down` with a `GrowthDirection.forward` would have the A at
    /// the top and the Z at the bottom, with the A adjacent to the origin.
    ///
    /// **Dart Source:** `sliver.dart:139`
    case forward

    /// This sliver's contents are ordered in the opposite direction of the
    /// `AxisDirection`.
    ///
    /// **Dart Source:** `sliver.dart:148`
    case reverse
}

// MARK: - Growth Direction Helper Functions

/// Flips the `AxisDirection` if the `GrowthDirection` is `GrowthDirection.reverse`.
///
/// Specifically, returns `axisDirection` if `growthDirection` is
/// `GrowthDirection.forward`, otherwise returns `flipAxisDirection` applied to
/// `axisDirection`.
///
/// This function is useful in `RenderSliver` subclasses that are given both an
/// `AxisDirection` and a `GrowthDirection` and wish to compute the
/// `AxisDirection` in which growth will occur.
///
/// **Dart Source:** `sliver.dart:160-168`
public func applyGrowthDirectionToAxisDirection(
    _ axisDirection: AxisDirection,
    _ growthDirection: GrowthDirection
) -> AxisDirection {
    switch growthDirection {
    case .forward:
        return axisDirection
    case .reverse:
        return flipAxisDirection(axisDirection)
    }
}

/// Flips the `ScrollDirection` if the `GrowthDirection` is `GrowthDirection.reverse`.
///
/// Specifically, returns `scrollDirection` if `growthDirection` is
/// `GrowthDirection.forward`, otherwise returns `flipScrollDirection` applied to
/// `scrollDirection`.
///
/// This function is useful in `RenderSliver` subclasses that are given both a
/// `ScrollDirection` and a `GrowthDirection` and wish to compute the
/// `ScrollDirection` in which growth will occur.
///
/// **Dart Source:** `sliver.dart:180-188`
public func applyGrowthDirectionToScrollDirection(
    _ scrollDirection: ScrollDirection,
    _ growthDirection: GrowthDirection
) -> ScrollDirection {
    switch growthDirection {
    case .forward:
        return scrollDirection
    case .reverse:
        return flipScrollDirection(scrollDirection)
    }
}

// MARK: - SliverConstraints

/// Immutable layout constraints for `RenderSliver` layout.
///
/// The `SliverConstraints` describe the current scroll state of the viewport
/// from the point of view of the sliver receiving the constraints. For example,
/// a `scrollOffset` of zero means that the leading edge of the sliver is
/// visible in the viewport, not that the viewport itself has a zero scroll
/// offset.
///
/// **Dart Source:** `sliver.dart:197-634`
public struct SliverConstraints: Constraints, Hashable, CustomStringConvertible {

    // MARK: - Properties

    /// The direction in which the `scrollOffset` and `remainingPaintExtent`
    /// increase.
    ///
    /// **Dart Source:** `sliver.dart:256`
    public let axisDirection: AxisDirection

    /// The direction in which the contents of slivers are ordered, relative to
    /// the `axisDirection`.
    ///
    /// For example, if the `axisDirection` is `AxisDirection.up`, and the
    /// `growthDirection` is `GrowthDirection.forward`, then an alphabetical list
    /// will have A at the bottom, then B, then C, and so forth, with Z at the
    /// top, with the bottom of the A at scroll offset zero, and the top of the Z
    /// at the highest scroll offset.
    ///
    /// **Dart Source:** `sliver.dart:281`
    public let growthDirection: GrowthDirection

    /// The direction in which the user is attempting to scroll, relative to the
    /// `axisDirection` and `growthDirection`.
    ///
    /// For example, if `growthDirection` is `GrowthDirection.forward` and
    /// `axisDirection` is `AxisDirection.down`, then a
    /// `ScrollDirection.reverse` means that the user is scrolling down, in the
    /// positive `scrollOffset` direction.
    ///
    /// If the user is not scrolling, this will return `ScrollDirection.idle`
    /// even if there is (for example) a `ScrollActivity` currently animating the
    /// position.
    ///
    /// **Dart Source:** `sliver.dart:301`
    public let userScrollDirection: ScrollDirection

    /// The scroll offset, in this sliver's coordinate system, that corresponds to
    /// the earliest visible part of this sliver in the `AxisDirection` if
    /// `growthDirection` is `GrowthDirection.forward` or in the opposite
    /// `AxisDirection` direction if `growthDirection` is `GrowthDirection.reverse`.
    ///
    /// This value is typically used to compute whether this sliver should still
    /// protrude into the viewport via `SliverGeometry.paintExtent` and
    /// `SliverGeometry.layoutExtent` considering how far the beginning of the
    /// sliver is above the beginning of the viewport.
    ///
    /// **Dart Source:** `sliver.dart:331`
    public let scrollOffset: Double

    /// The scroll distance that has been consumed by all `RenderSliver`s that
    /// came before this `RenderSliver`.
    ///
    /// `RenderSliver`s often lazily create their internal content as layout
    /// occurs. In this case, when `RenderSliver`s exceed the viewport, their
    /// children are built lazily, and the `RenderSliver` does not have enough
    /// information to estimate its total extent; `precedingScrollExtent` will be
    /// `Double.infinity` for all `RenderSliver`s that appear after the lazily
    /// constructed child.
    ///
    /// **Dart Source:** `sliver.dart:356`
    public let precedingScrollExtent: Double

    /// The number of pixels from where the pixels corresponding to the
    /// `scrollOffset` will be painted up to the first pixel that has not yet been
    /// painted on by an earlier sliver, in the `axisDirection`.
    ///
    /// For example, if the previous sliver had a `SliverGeometry.paintExtent` of
    /// 100.0 pixels but a `SliverGeometry.layoutExtent` of only 50.0 pixels,
    /// then the `overlap` of this sliver will be 50.0.
    ///
    /// **Dart Source:** `sliver.dart:368`
    public let overlap: Double

    /// The number of pixels of content that the sliver should consider providing.
    /// (Providing more pixels than this is inefficient.)
    ///
    /// The actual number of pixels provided should be specified in the
    /// `RenderSliver.geometry` as `SliverGeometry.paintExtent`.
    ///
    /// This value may be infinite if the viewport is an unconstrained
    /// `RenderShrinkWrappingViewport`, or 0.0 if the sliver is scrolled off the
    /// bottom of a downwards vertical viewport.
    ///
    /// **Dart Source:** `sliver.dart:381`
    public let remainingPaintExtent: Double

    /// The number of pixels in the cross-axis.
    ///
    /// For a vertical list, this is the width of the sliver.
    ///
    /// **Dart Source:** `sliver.dart:386`
    public let crossAxisExtent: Double

    /// The direction in which children should be placed in the cross axis.
    ///
    /// Typically used in vertical lists to describe whether the ambient
    /// `TextDirection` is `TextDirection.rtl` or `TextDirection.ltr`.
    ///
    /// **Dart Source:** `sliver.dart:392`
    public let crossAxisDirection: AxisDirection

    /// The number of pixels the viewport can display in the main axis.
    ///
    /// For a vertical list, this is the height of the viewport.
    ///
    /// **Dart Source:** `sliver.dart:397`
    public let viewportMainAxisExtent: Double

    /// Where the cache area starts relative to the `scrollOffset`.
    ///
    /// Slivers that fall into the cache area located before the leading edge and
    /// after the trailing edge of the viewport should still render content
    /// because they are about to become visible when the user scrolls.
    ///
    /// The `cacheOrigin` describes where the `remainingCacheExtent` starts
    /// relative to the `scrollOffset`. A cache origin of 0 means that the sliver
    /// does not have to provide any content before the current `scrollOffset`. A
    /// `cacheOrigin` of -250.0 means that even though the first visible part of
    /// the sliver will be at the provided `scrollOffset`, the sliver should
    /// render content starting 250.0 before the `scrollOffset` to fill the
    /// cache area of the viewport.
    ///
    /// The `cacheOrigin` is always negative or zero and will never exceed
    /// `-scrollOffset`. In other words, a sliver is never asked to provide
    /// content before its zero `scrollOffset`.
    ///
    /// **Dart Source:** `sliver.dart:420`
    public let cacheOrigin: Double

    /// Describes how much content the sliver should provide starting from the
    /// `cacheOrigin`.
    ///
    /// Not all content in the `remainingCacheExtent` will be visible as some
    /// of it might fall into the cache area of the viewport.
    ///
    /// Each sliver should start laying out content at the `cacheOrigin` and
    /// try to provide as much content as the `remainingCacheExtent` allows.
    ///
    /// The `remainingCacheExtent` is always larger or equal to the
    /// `remainingPaintExtent`. Content that falls in the `remainingCacheExtent`,
    /// but is outside of the `remainingPaintExtent` is currently not visible
    /// in the viewport.
    ///
    /// **Dart Source:** `sliver.dart:439`
    public let remainingCacheExtent: Double

    // MARK: - Initializer

    /// Creates sliver constraints with the given information.
    ///
    /// **Dart Source:** `sliver.dart:199-212`
    public init(
        axisDirection: AxisDirection,
        growthDirection: GrowthDirection,
        userScrollDirection: ScrollDirection,
        scrollOffset: Double,
        precedingScrollExtent: Double,
        overlap: Double,
        remainingPaintExtent: Double,
        crossAxisExtent: Double,
        crossAxisDirection: AxisDirection,
        viewportMainAxisExtent: Double,
        remainingCacheExtent: Double,
        cacheOrigin: Double
    ) {
        self.axisDirection = axisDirection
        self.growthDirection = growthDirection
        self.userScrollDirection = userScrollDirection
        self.scrollOffset = scrollOffset
        self.precedingScrollExtent = precedingScrollExtent
        self.overlap = overlap
        self.remainingPaintExtent = remainingPaintExtent
        self.crossAxisExtent = crossAxisExtent
        self.crossAxisDirection = crossAxisDirection
        self.viewportMainAxisExtent = viewportMainAxisExtent
        self.remainingCacheExtent = remainingCacheExtent
        self.cacheOrigin = cacheOrigin
    }

    // MARK: - Computed Properties

    /// The axis along which the `scrollOffset` and `remainingPaintExtent` are measured.
    ///
    /// **Dart Source:** `sliver.dart:442`
    public var axis: Axis {
        axisDirectionToAxis(axisDirection)
    }

    /// Return what the `growthDirection` would be if the `axisDirection` was
    /// either `AxisDirection.down` or `AxisDirection.right`.
    ///
    /// This is the same as `growthDirection` unless the `axisDirection` is either
    /// `AxisDirection.up` or `AxisDirection.left`, in which case it is the
    /// opposite growth direction.
    ///
    /// This can be useful in combination with `axis` to view the `axisDirection`
    /// and `growthDirection` in different terms.
    ///
    /// **Dart Source:** `sliver.dart:453-461`
    public var normalizedGrowthDirection: GrowthDirection {
        if axisDirectionIsReversed(axisDirection) {
            switch growthDirection {
            case .forward: return .reverse
            case .reverse: return .forward
            }
        }
        return growthDirection
    }

    // MARK: - Constraints Protocol

    /// Whether there is exactly one size possible given these constraints.
    ///
    /// Always returns `false` for sliver constraints.
    ///
    /// **Dart Source:** `sliver.dart:464`
    public var isTight: Bool { false }

    /// Whether the constraints are expressed in a consistent manner.
    ///
    /// **Dart Source:** `sliver.dart:467-473`
    public var isNormalized: Bool {
        scrollOffset >= 0.0
            && crossAxisExtent >= 0.0
            && axisDirectionToAxis(axisDirection) != axisDirectionToAxis(crossAxisDirection)
            && viewportMainAxisExtent >= 0.0
            && remainingPaintExtent >= 0.0
    }

    // MARK: - copyWith

    /// Creates a copy of this object but with the given fields replaced with the
    /// new values.
    ///
    /// **Dart Source:** `sliver.dart:216-244`
    public func copyWith(
        axisDirection: AxisDirection? = nil,
        growthDirection: GrowthDirection? = nil,
        userScrollDirection: ScrollDirection? = nil,
        scrollOffset: Double? = nil,
        precedingScrollExtent: Double? = nil,
        overlap: Double? = nil,
        remainingPaintExtent: Double? = nil,
        crossAxisExtent: Double? = nil,
        crossAxisDirection: AxisDirection? = nil,
        viewportMainAxisExtent: Double? = nil,
        remainingCacheExtent: Double? = nil,
        cacheOrigin: Double? = nil
    ) -> SliverConstraints {
        SliverConstraints(
            axisDirection: axisDirection ?? self.axisDirection,
            growthDirection: growthDirection ?? self.growthDirection,
            userScrollDirection: userScrollDirection ?? self.userScrollDirection,
            scrollOffset: scrollOffset ?? self.scrollOffset,
            precedingScrollExtent: precedingScrollExtent ?? self.precedingScrollExtent,
            overlap: overlap ?? self.overlap,
            remainingPaintExtent: remainingPaintExtent ?? self.remainingPaintExtent,
            crossAxisExtent: crossAxisExtent ?? self.crossAxisExtent,
            crossAxisDirection: crossAxisDirection ?? self.crossAxisDirection,
            viewportMainAxisExtent: viewportMainAxisExtent ?? self.viewportMainAxisExtent,
            remainingCacheExtent: remainingCacheExtent ?? self.remainingCacheExtent,
            cacheOrigin: cacheOrigin ?? self.cacheOrigin
        )
    }

    // MARK: - asBoxConstraints

    /// Returns `BoxConstraints` that reflects the sliver constraints.
    ///
    /// The `minExtent` and `maxExtent` are used as the constraints in the main
    /// axis. If non-nil, the given `crossAxisExtent` is used as a tight
    /// constraint in the cross axis. Otherwise, the `crossAxisExtent` from this
    /// object is used as a constraint in the cross axis.
    ///
    /// Useful for slivers that have `RenderBox` children.
    ///
    /// **Dart Source:** `sliver.dart:483-505`
    public func asBoxConstraints(
        minExtent: Double = 0.0,
        maxExtent: Double = .infinity,
        crossAxisExtent: Double? = nil
    ) -> BoxConstraints {
        let effectiveCrossAxisExtent = crossAxisExtent ?? self.crossAxisExtent
        switch axis {
        case .horizontal:
            return BoxConstraints(
                minWidth: minExtent,
                maxWidth: maxExtent,
                minHeight: effectiveCrossAxisExtent,
                maxHeight: effectiveCrossAxisExtent
            )
        case .vertical:
            return BoxConstraints(
                minWidth: effectiveCrossAxisExtent,
                maxWidth: effectiveCrossAxisExtent,
                minHeight: minExtent,
                maxHeight: maxExtent
            )
        }
    }

    // MARK: - debugAssertIsValid

    /// Asserts that the constraints are valid.
    ///
    /// This might involve checks more detailed than `isNormalized`.
    ///
    /// If the `isAppliedConstraint` argument is true, then even stricter rules
    /// are enforced. This argument is set to true when checking constraints that
    /// are about to be applied to a `RenderObject` during layout.
    ///
    /// Returns the same as `isNormalized` if asserts are disabled.
    ///
    /// **Dart Source:** `sliver.dart:508-575`
    @discardableResult
    public func debugAssertIsValid(
        isAppliedConstraint: Bool = false,
        informationCollector: InformationCollector? = nil
    ) -> Bool {
        assert({
            var hasErrors = false
            var errorMessage = "\n"

            func verify(_ check: Bool, _ message: String) {
                if check { return }
                hasErrors = true
                errorMessage += "  \(message)\n"
            }

            func verifyDouble(
                _ property: Double,
                _ name: String,
                mustBePositive: Bool = false,
                mustBeNegative: Bool = false
            ) {
                if property.isNaN {
                    var additional = "."
                    if mustBePositive {
                        additional = ", expected greater than or equal to zero."
                    } else if mustBeNegative {
                        additional = ", expected less than or equal to zero."
                    }
                    verify(false, "The \"\(name)\" is NaN\(additional)")
                } else if mustBePositive {
                    verify(property >= 0.0, "The \"\(name)\" is negative.")
                } else if mustBeNegative {
                    verify(property <= 0.0, "The \"\(name)\" is positive.")
                }
            }

            verifyDouble(scrollOffset, "scrollOffset")
            verifyDouble(overlap, "overlap")
            verifyDouble(crossAxisExtent, "crossAxisExtent")
            verifyDouble(scrollOffset, "scrollOffset", mustBePositive: true)
            verify(
                axisDirectionToAxis(axisDirection) != axisDirectionToAxis(crossAxisDirection),
                "The \"axisDirection\" and the \"crossAxisDirection\" are along the same axis."
            )
            verifyDouble(viewportMainAxisExtent, "viewportMainAxisExtent", mustBePositive: true)
            verifyDouble(remainingPaintExtent, "remainingPaintExtent", mustBePositive: true)
            verifyDouble(remainingCacheExtent, "remainingCacheExtent", mustBePositive: true)
            verifyDouble(cacheOrigin, "cacheOrigin", mustBeNegative: true)
            verifyDouble(precedingScrollExtent, "precedingScrollExtent", mustBePositive: true)
            verify(isNormalized, "The constraints are not normalized.")

            if hasErrors {
                var diagnostics: [any DiagnosticsNodeProtocol] = [
                    ErrorSummary("SliverConstraints is not valid: \(errorMessage)")
                ]
                if let collector = informationCollector {
                    diagnostics.append(contentsOf: collector())
                }
                diagnostics.append(
                    DiagnosticsProperty<SliverConstraints>(
                        "The offending constraints were",
                        self,
                        style: .errorProperty
                    )
                )
                let error = FlutterError(fromParts: diagnostics)
                fatalError("\(error)")
            }
            return true
        }())
        return true
    }

    // MARK: - Hashable

    /// **Dart Source:** `sliver.dart:601-614`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(axisDirection)
        hasher.combine(growthDirection)
        hasher.combine(userScrollDirection)
        hasher.combine(scrollOffset)
        hasher.combine(precedingScrollExtent)
        hasher.combine(overlap)
        hasher.combine(remainingPaintExtent)
        hasher.combine(crossAxisExtent)
        hasher.combine(crossAxisDirection)
        hasher.combine(viewportMainAxisExtent)
        hasher.combine(remainingCacheExtent)
        hasher.combine(cacheOrigin)
    }

    // MARK: - CustomStringConvertible

    /// A string representation of this `SliverConstraints`.
    ///
    /// **Dart Source:** `sliver.dart:617-633`
    public var description: String {
        var properties: [String] = [
            "\(axisDirection)",
            "\(growthDirection)",
            "\(userScrollDirection)",
            "scrollOffset: \(String(format: "%.1f", scrollOffset))",
            "precedingScrollExtent: \(String(format: "%.1f", precedingScrollExtent))",
            "remainingPaintExtent: \(String(format: "%.1f", remainingPaintExtent))",
        ]
        if overlap != 0.0 {
            properties.append("overlap: \(String(format: "%.1f", overlap))")
        }
        properties.append(contentsOf: [
            "crossAxisExtent: \(String(format: "%.1f", crossAxisExtent))",
            "crossAxisDirection: \(crossAxisDirection)",
            "viewportMainAxisExtent: \(String(format: "%.1f", viewportMainAxisExtent))",
            "remainingCacheExtent: \(String(format: "%.1f", remainingCacheExtent))",
            "cacheOrigin: \(String(format: "%.1f", cacheOrigin))",
        ])
        return "SliverConstraints(\(properties.joined(separator: ", ")))"
    }
}
// MARK: - _debugCompareFloats

/// Private helper function that compares two doubles for debug assertions.
///
/// Returns a list of diagnostic nodes describing the comparison, using
/// fixed-point formatting when the values are distinguishable at one decimal
/// place, or full precision with a hint about floating point rounding when
/// they are very close.
///
/// **Dart Source:** `sliver.dart:1151-1171`
private func _debugCompareFloats(
    _ labelA: String,
    _ valueA: Double,
    _ labelB: String,
    _ valueB: Double
) -> [any DiagnosticsNodeProtocol] {
    let fixedA = String(format: "%.1f", valueA)
    let fixedB = String(format: "%.1f", valueB)
    if fixedA != fixedB {
        return [
            ErrorDescription(
                "The \(labelA) is \(fixedA), but "
                + "the \(labelB) is \(fixedB)."
            )
        ]
    } else {
        return [
            ErrorDescription(
                "The \(labelA) is \(valueA), but the \(labelB) is \(valueB)."
            ),
            ErrorHint(
                "Maybe you have fallen prey to floating point rounding errors, and should explicitly "
                + "apply the min() or max() functions, or the clamp() method, to the \(labelB)?"
            ),
        ]
    }
}

// MARK: - SliverGeometry

/// Describes the amount of space occupied by a `RenderSliver`.
///
/// A sliver reports its geometry by returning a `SliverGeometry` from its
/// `RenderSliver.performLayout` function. The geometry describes the amount of
/// space the sliver occupies for painting, hit testing, layout of subsequent
/// slivers, and scrolling.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/sliver.dart:641-943`
public struct SliverGeometry: CustomStringConvertible, Sendable {

    // MARK: - Initializer

    /// Creates an object that describes the amount of space occupied by a sliver.
    ///
    /// If the `layoutExtent` argument is nil, `layoutExtent` defaults to the
    /// `paintExtent`. If the `hitTestExtent` argument is nil, `hitTestExtent`
    /// defaults to the `paintExtent`. If `visible` is nil, `visible` defaults to
    /// whether `paintExtent` is greater than zero.
    ///
    /// **Dart Source:** `sliver.dart:648-665`
    public init(
        scrollExtent: Double = 0.0,
        paintExtent: Double = 0.0,
        paintOrigin: Double = 0.0,
        layoutExtent: Double? = nil,
        maxPaintExtent: Double = 0.0,
        maxScrollObstructionExtent: Double = 0.0,
        crossAxisExtent: Double? = nil,
        hitTestExtent: Double? = nil,
        visible: Bool? = nil,
        hasVisualOverflow: Bool = false,
        scrollOffsetCorrection: Double? = nil,
        cacheExtent: Double? = nil
    ) {
        assert(scrollOffsetCorrection != 0.0,
               "The \"scrollOffsetCorrection\" is zero.")

        self.scrollExtent = scrollExtent
        self.paintExtent = paintExtent
        self.paintOrigin = paintOrigin
        self.layoutExtent = layoutExtent ?? paintExtent
        self.maxPaintExtent = maxPaintExtent
        self.maxScrollObstructionExtent = maxScrollObstructionExtent
        self.crossAxisExtent = crossAxisExtent
        self.hitTestExtent = hitTestExtent ?? paintExtent
        self.visible = visible ?? (paintExtent > 0.0)
        self.hasVisualOverflow = hasVisualOverflow
        self.scrollOffsetCorrection = scrollOffsetCorrection
        self.cacheExtent = cacheExtent ?? layoutExtent ?? paintExtent
    }

    // MARK: - Static Constants

    /// A sliver that occupies no space at all.
    ///
    /// **Dart Source:** `sliver.dart:698`
    public static let zero = SliverGeometry()

    // MARK: - Properties

    /// The (estimated) total scrollable extent that this sliver has content for.
    ///
    /// This is the amount of scrolling the user needs to do to get from the
    /// beginning of this sliver to the end of this sliver.
    ///
    /// The value is used to calculate the `SliverConstraints.scrollOffset` of
    /// all slivers in the scrollable and thus should be provided whether the
    /// sliver is currently in the viewport or not.
    ///
    /// In a typical scrolling scenario, the `scrollExtent` is constant for a
    /// sliver throughout the scrolling while `paintExtent` and `layoutExtent`
    /// will progress from `0` when offscreen to between `0` and `scrollExtent`
    /// as the sliver scrolls partially into and out of the screen and is
    /// equal to `scrollExtent` while the sliver is entirely on screen. However,
    /// these relationships can be customized to achieve more special effects.
    ///
    /// This value must be accurate if the `paintExtent` is less than the
    /// `SliverConstraints.remainingPaintExtent` provided during layout.
    ///
    /// **Dart Source:** `sliver.dart:700-718`
    public let scrollExtent: Double

    /// The visual location of the first visible part of this sliver relative to
    /// its layout position.
    ///
    /// For example, if the sliver wishes to paint visually before its layout
    /// position, the `paintOrigin` is negative. The coordinate system this sliver
    /// uses for painting is relative to this `paintOrigin`. In other words,
    /// when `RenderSliver.paint` is called, the (0, 0) position of the `Offset`
    /// given to it is at this `paintOrigin`.
    ///
    /// The coordinate system used for the `paintOrigin` itself is relative
    /// to the start of this sliver's layout position rather than relative to
    /// its current position on the viewport. In other words, in a typical
    /// scrolling scenario, `paintOrigin` remains constant at 0.0 rather than
    /// tracking from 0.0 to `SliverConstraints.viewportMainAxisExtent` as the
    /// sliver scrolls past the viewport.
    ///
    /// This value does not affect the layout of subsequent slivers. The next
    /// sliver is still placed at `layoutExtent` after this sliver's layout
    /// position. This value does affect where the `paintExtent` extent is
    /// measured from when computing the `SliverConstraints.overlap` for the next
    /// sliver.
    ///
    /// Defaults to 0.0, which means slivers start painting at their layout
    /// position by default.
    ///
    /// **Dart Source:** `sliver.dart:720-744`
    public let paintOrigin: Double

    /// The amount of currently visible visual space that was taken by the sliver
    /// to render the subset of the sliver that covers all or part of the
    /// `SliverConstraints.remainingPaintExtent` in the current viewport.
    ///
    /// This value does not affect how the next sliver is positioned. In other
    /// words, if this value was 100 and `layoutExtent` was 0, typical slivers
    /// placed after it would end up drawing in the same 100 pixel space while
    /// painting.
    ///
    /// This must be between zero and `SliverConstraints.remainingPaintExtent`.
    ///
    /// This value is typically 0 when outside of the viewport and grows or
    /// shrinks from 0 or to 0 as the sliver is being scrolled into and out of the
    /// viewport unless the sliver wants to achieve a special effect and paint
    /// even when scrolled away.
    ///
    /// This contributes to the calculation for the next sliver's
    /// `SliverConstraints.overlap`.
    ///
    /// **Dart Source:** `sliver.dart:746-764`
    public let paintExtent: Double

    /// The distance from the first visible part of this sliver to the first
    /// visible part of the next sliver, assuming the next sliver's
    /// `SliverConstraints.scrollOffset` is zero.
    ///
    /// This must be between zero and `paintExtent`. It defaults to `paintExtent`.
    ///
    /// This value is typically 0 when outside of the viewport and grows or
    /// shrinks from 0 or to 0 as the sliver is being scrolled into and out of the
    /// viewport unless the sliver wants to achieve a special effect and push
    /// down the layout start position of subsequent slivers before the sliver is
    /// even scrolled into the viewport.
    ///
    /// **Dart Source:** `sliver.dart:766-777`
    public let layoutExtent: Double

    /// The (estimated) total paint extent that this sliver would be able to
    /// provide if the `SliverConstraints.remainingPaintExtent` was infinite.
    ///
    /// This is used by viewports that implement shrink-wrapping.
    ///
    /// By definition, this cannot be less than `paintExtent`.
    ///
    /// **Dart Source:** `sliver.dart:779-785`
    public let maxPaintExtent: Double

    /// The maximum extent by which this sliver can reduce the area in which
    /// content can scroll if the sliver were pinned at the edge.
    ///
    /// Slivers that never get pinned at the edge, should return zero.
    ///
    /// A pinned app bar is an example for a sliver that would use this setting:
    /// When the app bar is pinned to the top, the area in which content can
    /// actually scroll is reduced by the height of the app bar.
    ///
    /// **Dart Source:** `sliver.dart:787-795`
    public let maxScrollObstructionExtent: Double

    /// The distance from where this sliver started painting to the bottom of
    /// where it should accept hits.
    ///
    /// This must be between zero and `paintExtent`. It defaults to `paintExtent`.
    ///
    /// **Dart Source:** `sliver.dart:797-801`
    public let hitTestExtent: Double

    /// Whether this sliver should be painted.
    ///
    /// By default, this is true if `paintExtent` is greater than zero, and
    /// false if `paintExtent` is zero.
    ///
    /// **Dart Source:** `sliver.dart:803-807`
    public let visible: Bool

    /// Whether this sliver has visual overflow.
    ///
    /// By default, this is false, which means the viewport does not need to clip
    /// its children. If any slivers have visual overflow, the viewport will apply
    /// a clip to its children.
    ///
    /// **Dart Source:** `sliver.dart:809-814`
    public let hasVisualOverflow: Bool

    /// If this is non-zero after `RenderSliver.performLayout` returns, the scroll
    /// offset will be adjusted by the parent and then the entire layout of the
    /// parent will be rerun.
    ///
    /// When the value is non-zero, the `RenderSliver` does not need to compute
    /// the rest of the values when constructing the `SliverGeometry` or call
    /// `RenderObject.layout` on its children since `RenderSliver.performLayout`
    /// will be called again on this sliver in the same frame after the
    /// `SliverConstraints.scrollOffset` correction has been applied, when the
    /// proper `SliverGeometry` and layout of its children can be computed.
    ///
    /// If the parent is also a `RenderSliver`, it must propagate this value
    /// in its own `RenderSliver.geometry` property until a viewport which adjusts
    /// its offset based on this value.
    ///
    /// **Dart Source:** `sliver.dart:816-830`
    public let scrollOffsetCorrection: Double?

    /// How many pixels the sliver has consumed in the
    /// `SliverConstraints.remainingCacheExtent`.
    ///
    /// This value should be equal to or larger than the `layoutExtent` because
    /// the sliver always consumes at least the `layoutExtent` from the
    /// `SliverConstraints.remainingCacheExtent` and possibly more if it falls
    /// into the cache area of the viewport.
    ///
    /// See also:
    ///
    ///  * `RenderViewport.cacheExtent` for a description of a viewport's cache area.
    ///
    /// **Dart Source:** `sliver.dart:832-843`
    public let cacheExtent: Double

    /// The amount of space allocated to the cross axis.
    ///
    /// This value will be typically nil unless it is different from
    /// `SliverConstraints.crossAxisExtent`. If nil, then the cross axis extent of
    /// the sliver is assumed to be the same as the `SliverConstraints.crossAxisExtent`.
    /// This is because slivers typically consume all of the extent that is available
    /// in the cross axis.
    ///
    /// See also:
    ///
    ///  * `SliverConstrainedCrossAxis` for an example of a sliver which takes up
    ///    a smaller cross axis extent than the provided constraint.
    ///  * `SliverCrossAxisGroup` for an example of a sliver which makes use of this
    ///    `crossAxisExtent` to lay out their children.
    ///
    /// **Dart Source:** `sliver.dart:845-859`
    public let crossAxisExtent: Double?

    // MARK: - copyWith

    /// Creates a copy of this object but with the given fields replaced with the
    /// new values.
    ///
    /// **Dart Source:** `sliver.dart:669-695`
    public func copyWith(
        scrollExtent: Double? = nil,
        paintExtent: Double? = nil,
        paintOrigin: Double? = nil,
        layoutExtent: Double? = nil,
        maxPaintExtent: Double? = nil,
        maxScrollObstructionExtent: Double? = nil,
        crossAxisExtent: Double? = nil,
        hitTestExtent: Double? = nil,
        visible: Bool? = nil,
        hasVisualOverflow: Bool? = nil,
        cacheExtent: Double? = nil
    ) -> SliverGeometry {
        return SliverGeometry(
            scrollExtent: scrollExtent ?? self.scrollExtent,
            paintExtent: paintExtent ?? self.paintExtent,
            paintOrigin: paintOrigin ?? self.paintOrigin,
            layoutExtent: layoutExtent ?? self.layoutExtent,
            maxPaintExtent: maxPaintExtent ?? self.maxPaintExtent,
            maxScrollObstructionExtent: maxScrollObstructionExtent ?? self.maxScrollObstructionExtent,
            crossAxisExtent: crossAxisExtent ?? self.crossAxisExtent,
            hitTestExtent: hitTestExtent ?? self.hitTestExtent,
            visible: visible ?? self.visible,
            hasVisualOverflow: hasVisualOverflow ?? self.hasVisualOverflow,
            cacheExtent: cacheExtent ?? self.cacheExtent
        )
    }

    // MARK: - Validation

    /// Asserts that this geometry is internally consistent.
    ///
    /// Does nothing if asserts are disabled. Always returns true.
    ///
    /// **Dart Source:** `sliver.dart:864-907`
    @discardableResult
    public func debugAssertIsValid(informationCollector: InformationCollector? = nil) -> Bool {
        assert({
            func verify(_ check: Bool, _ summary: String, details: [any DiagnosticsNodeProtocol]? = nil) {
                if check {
                    return
                }
                var diagnostics: [any DiagnosticsNodeProtocol] = [
                    ErrorSummary(
                        "\(objectRuntimeType(self, "SliverGeometry")) is not valid: \(summary)"
                    )
                ]
                if let details = details {
                    diagnostics.append(contentsOf: details)
                }
                if let collector = informationCollector {
                    diagnostics.append(contentsOf: collector())
                }
                let error = FlutterError(fromParts: diagnostics)
                fatalError("\(error)")
            }

            verify(scrollExtent >= 0.0, "The \"scrollExtent\" is negative.")
            verify(paintExtent >= 0.0, "The \"paintExtent\" is negative.")
            verify(layoutExtent >= 0.0, "The \"layoutExtent\" is negative.")
            verify(cacheExtent >= 0.0, "The \"cacheExtent\" is negative.")
            if layoutExtent > paintExtent {
                verify(
                    false,
                    "The \"layoutExtent\" exceeds the \"paintExtent\".",
                    details: _debugCompareFloats(
                        "paintExtent", paintExtent,
                        "layoutExtent", layoutExtent
                    )
                )
            }
            // If the paintExtent is slightly more than the maxPaintExtent, but the difference is still less
            // than precisionErrorTolerance, we will not throw the assert below.
            if paintExtent - maxPaintExtent > precisionErrorTolerance {
                var details = _debugCompareFloats(
                    "maxPaintExtent", maxPaintExtent,
                    "paintExtent", paintExtent
                )
                details.append(
                    ErrorDescription(
                        "By definition, a sliver can't paint more than the maximum that it can paint!"
                    )
                )
                verify(
                    false,
                    "The \"maxPaintExtent\" is less than the \"paintExtent\".",
                    details: details
                )
            }
            verify(hitTestExtent >= 0.0, "The \"hitTestExtent\" is negative.")
            verify(scrollOffsetCorrection != 0.0, "The \"scrollOffsetCorrection\" is zero.")
            return true
        }())
        return true
    }

    // MARK: - CustomStringConvertible

    /// A brief textual description of this `SliverGeometry`.
    ///
    /// **Dart Source:** `sliver.dart:910`
    public var description: String {
        return objectRuntimeType(self, "SliverGeometry") + "(" + _descriptionParts().joined(separator: ", ") + ")"
    }

    /// Returns the parts of the description as an array of strings,
    /// omitting default values for brevity.
    private func _descriptionParts() -> [String] {
        var parts: [String] = []
        parts.append("scrollExtent: \(debugFormatDouble(scrollExtent))")
        if paintExtent > 0.0 {
            parts.append(
                "paintExtent: \(debugFormatDouble(paintExtent))"
                + (visible ? "" : " but not painting")
            )
        } else if paintExtent == 0.0 {
            if visible {
                parts.append("paintExtent: \(debugFormatDouble(paintExtent))")
            }
            if !visible {
                parts.append("hidden")
            }
        } else {
            // Negative paintExtent!
            parts.append("paintExtent: \(debugFormatDouble(paintExtent))(!)")
        }
        if paintOrigin != 0.0 {
            parts.append("paintOrigin: \(debugFormatDouble(paintOrigin))")
        }
        if layoutExtent != paintExtent {
            parts.append("layoutExtent: \(debugFormatDouble(layoutExtent))")
        }
        parts.append("maxPaintExtent: \(debugFormatDouble(maxPaintExtent))")
        if hitTestExtent != paintExtent {
            parts.append("hitTestExtent: \(debugFormatDouble(hitTestExtent))")
        }
        if hasVisualOverflow {
            parts.append("hasVisualOverflow: true")
        }
        if scrollOffsetCorrection != nil {
            parts.append("scrollOffsetCorrection: \(debugFormatDouble(scrollOffsetCorrection!))")
        }
        if cacheExtent != 0.0 {
            parts.append("cacheExtent: \(debugFormatDouble(cacheExtent))")
        }
        return parts
    }

    // MARK: - Debug Properties

    /// Fills the given `DiagnosticPropertiesBuilder` with debug information
    /// describing this `SliverGeometry`.
    ///
    /// **Dart Source:** `sliver.dart:912-942`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(DoubleProperty("scrollExtent", scrollExtent))
        if paintExtent > 0.0 {
            properties.add(
                DoubleProperty(
                    "paintExtent", paintExtent,
                    unit: visible ? nil : " but not painting"
                )
            )
        } else if paintExtent == 0.0 {
            if visible {
                properties.add(
                    DoubleProperty(
                        "paintExtent", paintExtent,
                        unit: visible ? nil : " but visible"
                    )
                )
            }
            properties.add(FlagProperty("visible", value: visible, ifFalse: "hidden"))
        } else {
            // Negative paintExtent!
            properties.add(DoubleProperty("paintExtent", paintExtent, tooltip: "!"))
        }
        properties.add(DoubleProperty("paintOrigin", paintOrigin, defaultValue: 0.0))
        properties.add(DoubleProperty("layoutExtent", layoutExtent, defaultValue: paintExtent))
        properties.add(DoubleProperty("maxPaintExtent", maxPaintExtent))
        properties.add(DoubleProperty("hitTestExtent", hitTestExtent, defaultValue: paintExtent))
        properties.add(
            DiagnosticsProperty<Bool>("hasVisualOverflow", hasVisualOverflow, defaultValue: false)
        )
        properties.add(
            DoubleProperty("scrollOffsetCorrection", scrollOffsetCorrection, defaultValue: nil)
        )
        properties.add(DoubleProperty("cacheExtent", cacheExtent, defaultValue: 0.0))
    }
}
// =============================================================================
// MARK: - S4: Hit Testing Types
// =============================================================================

// MARK: - SliverHitTest

/// Signature used by `SliverHitTestResult.addWithAxisOffset` to hit test
/// sliver children.
///
/// **Dart Source:** `sliver.dart:954-959`
public typealias SliverHitTest = (
    _ result: SliverHitTestResult,
    _ mainAxisPosition: Double,
    _ crossAxisPosition: Double
) -> Bool

// MARK: - SliverHitTestResult

/// The result of performing a hit test on `RenderSliver`s.
///
/// An instance of this class is provided to `RenderSliver.hitTest` to record
/// the result of the hit test.
///
/// **Dart Source:** `sliver.dart:965-1030`
public class SliverHitTestResult: HitTestResult {

    /// Creates an empty hit test result for hit testing on `RenderSliver`.
    ///
    /// **Dart Source:** `sliver.dart:967`
    public override init() {
        super.init()
    }

    /// Wraps `result` to create a `HitTestResult` that implements the
    /// `SliverHitTestResult` protocol for hit testing on `RenderSliver`s.
    ///
    /// The `HitTestEntry` instances added to the returned `SliverHitTestResult`
    /// are also added to the wrapped `result` (both share the same underlying
    /// data structure to store `HitTestEntry` instances).
    ///
    /// **Dart Source:** `sliver.dart:987`
    public init(wrapping result: HitTestResult) {
        super.init(wrap: result)
    }

    /// Transforms `mainAxisPosition` and `crossAxisPosition` to the local
    /// coordinate system of a child for hit-testing the child.
    ///
    /// The actual hit testing of the child needs to be implemented in the
    /// provided `hitTest` callback, which is invoked with the transformed
    /// positions as arguments.
    ///
    /// For the transform, `mainAxisOffset` is subtracted from
    /// `mainAxisPosition` and `crossAxisOffset` is subtracted from
    /// `crossAxisPosition`.
    ///
    /// The `paintOffset` describes how the paint position of a point painted at
    /// the provided `mainAxisPosition` and `crossAxisPosition` would change
    /// after `mainAxisOffset` and `crossAxisOffset` have been applied. This
    /// `paintOffset` is used to properly convert `PointerEvent`s to the local
    /// coordinate system of the event receiver.
    ///
    /// The `paintOffset` may be nil if `mainAxisOffset` and `crossAxisOffset`
    /// are both zero.
    ///
    /// The function returns the return value of `hitTest`.
    ///
    /// **Dart Source:** `sliver.dart:1009-1029`
    public func addWithAxisOffset(
        paintOffset: Offset?,
        mainAxisOffset: Double,
        crossAxisOffset: Double,
        mainAxisPosition: Double,
        crossAxisPosition: Double,
        hitTest: SliverHitTest
    ) -> Bool {
        if let paintOffset = paintOffset {
            pushOffset(-paintOffset)
        }
        let isHit = hitTest(
            self,
            mainAxisPosition - mainAxisOffset,
            crossAxisPosition - crossAxisOffset
        )
        if paintOffset != nil {
            popTransform()
        }
        return isHit
    }
}

// MARK: - SliverHitTestEntry

/// A hit test entry used by `RenderSliver`.
///
/// The coordinate system used by this hit test entry is relative to the
/// `AxisDirection` of the target sliver.
///
/// **Dart Source:** `sliver.dart:1036-1068`
public class SliverHitTestEntry: HitTestEntry<AnyHitTestTarget> {

    /// Creates a sliver hit test entry.
    ///
    /// **Dart Source:** `sliver.dart:1038-1042`
    public init(
        _ target: RenderSliver,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) {
        self.mainAxisPosition = mainAxisPosition
        self.crossAxisPosition = crossAxisPosition
        self._sliverTarget = target
        super.init(AnyHitTestTarget(target))
    }

    /// The `RenderSliver` that was hit.
    private let _sliverTarget: RenderSliver

    /// The distance in the `AxisDirection` from the edge of the sliver's
    /// painted area (as given by the `SliverConstraints.scrollOffset`) to the
    /// hit point.
    ///
    /// This can be an unusual direction, for example in the `AxisDirection.up`
    /// case this is a distance from the _bottom_ of the sliver's painted area.
    ///
    /// **Dart Source:** `sliver.dart:1048`
    public let mainAxisPosition: Double

    /// The distance to the hit point in the axis opposite the
    /// `SliverConstraints.axis`.
    ///
    /// If the cross axis is horizontal (i.e. the
    /// `SliverConstraints.axisDirection` is either `.down` or `.up`), then the
    /// `crossAxisPosition` is a distance from the left edge of the sliver.
    /// If the cross axis is vertical (i.e. the
    /// `SliverConstraints.axisDirection` is either `.right` or `.left`), then
    /// the `crossAxisPosition` is a distance from the top edge of the sliver.
    ///
    /// This is always a distance from the left or top of the parent, never a
    /// distance from the right or bottom.
    ///
    /// **Dart Source:** `sliver.dart:1063`
    public let crossAxisPosition: Double

    // MARK: - CustomStringConvertible

    /// **Dart Source:** `sliver.dart:1066-1067`
    public override var description: String {
        "\(describeIdentity(_sliverTarget))@(mainAxis: \(mainAxisPosition), crossAxis: \(crossAxisPosition))"
    }
}

// =============================================================================
// MARK: - S5: ParentData Classes
// =============================================================================

// MARK: - SliverLogicalParentData

/// Parent data structure used by parents of slivers that position their
/// children using layout offsets.
///
/// This data structure is optimized for fast layout. It is best used by
/// parents that expect to have many children whose relative positions don't
/// change even when the scroll offset does.
///
/// **Dart Source:** `sliver.dart:1076-1092`
open class SliverLogicalParentData: ParentData {

    /// The position of the child relative to the zero scroll offset.
    ///
    /// The number of pixels from the zero scroll offset of the parent sliver
    /// (the line at which its `SliverConstraints.scrollOffset` is zero) to the
    /// side of the child closest to that offset. A `layoutOffset` can be nil
    /// when it cannot be determined. The value will be set after layout.
    ///
    /// In a typical list, this does not change as the parent is scrolled.
    ///
    /// Defaults to nil.
    ///
    /// **Dart Source:** `sliver.dart:1087`
    public var layoutOffset: Double?

    /// **Dart Source:** `sliver.dart:1090-1091`
    open override var description: String {
        "layoutOffset=\(layoutOffset.map { String(format: "%.1f", $0) } ?? "None")"
    }
}

// MARK: - SliverLogicalContainerParentData

/// Parent data for slivers that have multiple children and that position
/// their children using layout offsets.
///
/// Combines `SliverLogicalParentData` with `ContainerParentDataProtocol`
/// to provide both layout offset and linked-list child pointers.
///
/// **Dart Source:** `sliver.dart:1096-1097`
open class SliverLogicalContainerParentData: SliverLogicalParentData,
    ContainerParentDataProtocol
{
    /// The previous sibling in the parent's child list.
    /// `weak`: back-pointer only — see ContainerBoxParentData.previousSibling
    /// for why a strong one leaks whole dropped child lists under ARC.
    public weak var previousSibling: RenderSliver?

    /// The next sibling in the parent's child list.
    public var nextSibling: RenderSliver?
}

// MARK: - SliverPhysicalParentData

/// Parent data structure used by parents of slivers that position their
/// children using absolute coordinates.
///
/// For example, used by `RenderViewport`.
///
/// This data structure is optimized for fast painting, at the cost of
/// requiring additional work during layout when the children change their
/// offsets. It is best used by parents that expect to have few children,
/// especially if those children will themselves be very tall relative to the
/// parent.
///
/// **Dart Source:** `sliver.dart:1108-1144`
open class SliverPhysicalParentData: ParentData {

    /// The position of the child relative to the parent.
    ///
    /// This is the distance from the top left visible corner of the parent to
    /// the top left visible corner of the sliver.
    ///
    /// **Dart Source:** `sliver.dart:1113`
    public var paintOffset: Offset = .zero

    /// The `crossAxisFlex` factor to use for this sliver child.
    ///
    /// If used outside of a `SliverCrossAxisGroup` widget, this value has no
    /// meaning.
    ///
    /// If nil or zero, the child is inflexible and determines its own size in
    /// the cross axis. If non-zero, the amount of space the child can occupy
    /// in the cross axis is determined by dividing the free space (after
    /// placing the inflexible children) according to the flex factors of the
    /// flexible children.
    ///
    /// This value is only used by the `SliverCrossAxisGroup` widget to
    /// determine how to allocate its `SliverConstraints.crossAxisExtent` to
    /// its children.
    ///
    /// **Dart Source:** `sliver.dart:1131`
    public var crossAxisFlex: Int?

    /// Apply the `paintOffset` to the given `transform`.
    ///
    /// Used to implement `RenderObject.applyPaintTransform` by slivers that
    /// use `SliverPhysicalParentData`.
    ///
    /// **Dart Source:** `sliver.dart:1137-1140`
    public func applyPaintTransform(_ transform: inout Matrix4) {
        // Hit test logic relies on this always providing an invertible matrix.
        transform = Matrix4.translationValues(paintOffset.dx, paintOffset.dy, 0) * transform
    }

    /// **Dart Source:** `sliver.dart:1143`
    open override var description: String {
        "paintOffset=\(paintOffset)"
    }
}

// MARK: - SliverPhysicalContainerParentData

/// Parent data for slivers that have multiple children and that position
/// their children using absolute coordinates.
///
/// Combines `SliverPhysicalParentData` with `ContainerParentDataProtocol`
/// to provide both paint offset and linked-list child pointers.
///
/// **Dart Source:** `sliver.dart:1148-1149`
open class SliverPhysicalContainerParentData: SliverPhysicalParentData,
    ContainerParentDataProtocol
{
    /// The previous sibling in the parent's child list.
    /// `weak`: back-pointer only — see ContainerBoxParentData.previousSibling
    /// for why a strong one leaks whole dropped child lists under ARC.
    public weak var previousSibling: RenderSliver?

    /// The next sibling in the parent's child list.
    public var nextSibling: RenderSliver?
}

// =============================================================================
// MARK: - S6: RenderSliver Core
// =============================================================================

/// Base class for the render objects that implement scroll effects in
/// viewports.
///
/// A `RenderViewport` has a list of child slivers. Each sliver -- literally a
/// slice of the viewport's contents -- is laid out in turn, covering the
/// viewport in the process. (Every sliver is laid out each time, including
/// those that have zero extent because they are "scrolled off" or are beyond
/// the end of the viewport.)
///
/// Slivers participate in the _sliver protocol_, wherein during layout each
/// sliver receives a `SliverConstraints` object and computes a corresponding
/// `SliverGeometry` that describes where it fits in the viewport. This is
/// analogous to the box protocol used by `RenderBox`, which gets a
/// `BoxConstraints` as input and computes a `Size`.
///
/// **Dart Source:** `sliver.dart:1310-1842`
open class RenderSliver: RenderObject {

    // MARK: - Semantics

    /// Whether this sliver should be included in the semantics tree.
    ///
    /// This value is used by `RenderViewportBase` to ensure a sliver is
    /// included in the semantics tree regardless of its geometry.
    ///
    /// Defaults to `false`.
    ///
    /// **Dart Source:** `sliver.dart:1331`
    open var ensureSemantics: Bool { false }

    // MARK: - Constraints

    /// The most recently received sliver constraints from the parent.
    ///
    /// **Dart Source:** `sliver.dart:1335`
    public var sliverConstraints: SliverConstraints {
        return constraints as! SliverConstraints
    }

    // MARK: - Geometry

    /// The amount of space this sliver occupies.
    ///
    /// This value is stale whenever this object is marked as needing layout.
    /// During `performLayout`, do not read the `geometry` of a child unless
    /// you pass true for `parentUsesSize` when calling the child's `layout`
    /// function.
    ///
    /// The geometry of a sliver should be set only during the sliver's
    /// `performLayout` or `performResize` functions. If you wish to change the
    /// geometry of a sliver outside of those functions, call `markNeedsLayout`
    /// instead to schedule a layout of the sliver.
    ///
    /// **Dart Source:** `sliver.dart:1347-1393`
    public var geometry: SliverGeometry? {
        get { _geometry }
        set {
            // In Dart, the setter has complex debug assertions about when geometry
            // may be set (only during performLayout/performResize). We simplify
            // the assertions here.
            assert({
                // Geometry should only be set during layout.
                return true
            }())
            _geometry = newValue
        }
    }
    private var _geometry: SliverGeometry?

    // MARK: - Bounds

    /// **Dart Source:** `sliver.dart:1396`
    open var semanticBounds: Rect { paintBounds }

    /// **Dart Source:** `sliver.dart:1399-1406`
    open override var paintBounds: Rect {
        switch sliverConstraints.axis {
        case .horizontal:
            return Rect.fromLTWH(
                0.0, 0.0,
                geometry!.paintExtent,
                sliverConstraints.crossAxisExtent
            )
        case .vertical:
            return Rect.fromLTWH(
                0.0, 0.0,
                sliverConstraints.crossAxisExtent,
                geometry!.paintExtent
            )
        }
    }

    // MARK: - Debug Reset

    /// **Dart Source:** `sliver.dart:1409`
    open func debugResetSize() {}

    // MARK: - Debug Assert Does Meet Constraints

    /// **Dart Source:** `sliver.dart:1412-1443`
    open func debugAssertDoesMeetConstraints() {
        assert(
            geometry!.debugAssertIsValid(
                informationCollector: {
                    [ErrorDescription("The RenderSliver that returned the offending geometry was: \(self)")]
                }
            )
        )
        assert({
            if geometry!.paintOrigin + geometry!.paintExtent > sliverConstraints.remainingPaintExtent {
                var information: [any DiagnosticsNodeProtocol] = [
                    ErrorSummary(
                        "SliverGeometry has a paintOffset that exceeds the remainingPaintExtent from the constraints."
                    ),
                    ErrorDescription(
                        "The render object whose geometry violates the constraints is: \(self)"
                    ),
                ]
                information.append(contentsOf: _debugCompareFloats(
                    "remainingPaintExtent",
                    sliverConstraints.remainingPaintExtent,
                    "paintOrigin + paintExtent",
                    geometry!.paintOrigin + geometry!.paintExtent
                ))
                information.append(ErrorDescription(
                    "The paintOrigin and paintExtent must cause the child sliver to paint "
                    + "within the viewport, and so cannot exceed the remainingPaintExtent."
                ))
                let error = FlutterError(fromParts: information)
                fatalError("\(error)")
            }
            return true
        }())
    }

    // MARK: - Resize

    /// Called when the render object should resize itself based only on
    /// constraints.
    ///
    /// Slivers that do not use `sizedByParent` should not call this. The
    /// default implementation asserts that `sizedByParent` is false.
    ///
    /// **Dart Source:** `sliver.dart:1446-1448`
    open override func performResize() {
        assert(false, "RenderSliver.performResize should not be called; slivers are not sizedByParent.")
    }

    // MARK: - Center Offset Adjustment

    /// For a center sliver, the distance before the absolute zero scroll
    /// offset that this sliver can cover.
    ///
    /// For example, if an `AxisDirection.down` viewport with an
    /// `RenderViewport.anchor` of 0.5 has a single sliver with a height of
    /// 100.0 and its `centerOffsetAdjustment` returns 50.0, then the sliver
    /// will be centered in the viewport when the scroll offset is 0.0.
    ///
    /// The distance here is in the opposite direction of the
    /// `RenderViewport.axisDirection`, so values will typically be positive.
    ///
    /// **Dart Source:** `sliver.dart:1460`
    open var centerOffsetAdjustment: Double { 0.0 }

    // MARK: - Hit Testing

    /// Determines the set of render objects located at the given position.
    ///
    /// Returns true if the given point is contained in this render object or
    /// one of its descendants. Adds any render objects that contain the point
    /// to the given hit test result.
    ///
    /// The `mainAxisPosition` is the distance in the `AxisDirection` (after
    /// applying the `GrowthDirection`) from the edge of the sliver's painted
    /// area.
    ///
    /// The `crossAxisPosition` is the distance in the other axis.
    ///
    /// **Dart Source:** `sliver.dart:1500-1526`
    public func hitTest(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        if mainAxisPosition >= 0.0
            && mainAxisPosition < geometry!.hitTestExtent
            && crossAxisPosition >= 0.0
            && crossAxisPosition < sliverConstraints.crossAxisExtent
        {
            if hitTestChildren(
                result,
                mainAxisPosition: mainAxisPosition,
                crossAxisPosition: crossAxisPosition
            )
                || hitTestSelf(
                    mainAxisPosition: mainAxisPosition,
                    crossAxisPosition: crossAxisPosition
                )
            {
                result.add(
                    SliverHitTestEntry(
                        self,
                        mainAxisPosition: mainAxisPosition,
                        crossAxisPosition: crossAxisPosition
                    )
                )
                return true
            }
        }
        return false
    }

    /// Override this method if this render object can be hit even if its
    /// children were not hit.
    ///
    /// Used by `hitTest`. If you override `hitTest` and do not call this
    /// function, then you don't need to implement this function.
    ///
    /// **Dart Source:** `sliver.dart:1536`
    open func hitTestSelf(
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        return false
    }

    /// Override this method to check whether any children are located at the
    /// given position.
    ///
    /// Typically children should be hit-tested in reverse paint order so that
    /// hit tests at locations where children overlap hit the child that is
    /// visually "on top" (i.e., paints later).
    ///
    /// Used by `hitTest`. If you override `hitTest` and do not call this
    /// function, then you don't need to implement this function.
    ///
    /// **Dart Source:** `sliver.dart:1550-1554`
    open func hitTestChildren(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        return false
    }

    // MARK: - Paint / Cache Offset Calculations

    /// Computes the portion of the region from `from` to `to` that is visible,
    /// assuming that only the region from the `SliverConstraints.scrollOffset`
    /// that is `SliverConstraints.remainingPaintExtent` high is visible, and
    /// that the relationship between scroll offsets and paint offsets is linear.
    ///
    /// For example, if the constraints have a scroll offset of 100 and a
    /// remaining paint extent of 100, and the arguments to this method describe
    /// the region 50..150, then the returned value would be 50 (from scroll
    /// offset 100 to scroll offset 150).
    ///
    /// **Dart Source:** `sliver.dart:1573-1587`
    public func calculatePaintOffset(
        _ constraints: SliverConstraints,
        from: Double,
        to: Double
    ) -> Double {
        assert(from <= to)
        let a = constraints.scrollOffset
        let b = constraints.scrollOffset + constraints.remainingPaintExtent
        // The clamp on the next line is to avoid floating point rounding errors.
        return clampDouble(
            clampDouble(to, a, b) - clampDouble(from, a, b),
            0.0,
            constraints.remainingPaintExtent
        )
    }

    /// Computes the portion of the region from `from` to `to` that is within
    /// the cache extent of the viewport, assuming that only the region from
    /// the `SliverConstraints.cacheOrigin` that is
    /// `SliverConstraints.remainingCacheExtent` high is visible, and that the
    /// relationship between scroll offsets and paint offsets is linear.
    ///
    /// **Dart Source:** `sliver.dart:1597-1611`
    public func calculateCacheOffset(
        _ constraints: SliverConstraints,
        from: Double,
        to: Double
    ) -> Double {
        assert(from <= to)
        let a = constraints.scrollOffset + constraints.cacheOrigin
        let b = constraints.scrollOffset + constraints.remainingCacheExtent
        // The clamp on the next line is to avoid floating point rounding errors.
        return clampDouble(
            clampDouble(to, a, b) - clampDouble(from, a, b),
            0.0,
            constraints.remainingCacheExtent
        )
    }

    // MARK: - Child Position Methods

    /// Returns the distance from the leading _visible_ edge of the sliver to
    /// the side of the given child closest to that edge.
    ///
    /// For children that are `RenderSliver`s, the leading edge of the _child_
    /// will be the leading _visible_ edge of the child, not the part of the
    /// child that would locally be a scroll offset 0.0. For children that are
    /// not `RenderSliver`s, it's the actual distance to the edge of the box.
    ///
    /// Calling this for a child that is not visible is not valid.
    ///
    /// **Dart Source:** `sliver.dart:1640-1647`
    open func childMainAxisPosition(_ child: RenderObject) -> Double {
        assert({
            fatalError(
                "\(type(of: self)) does not implement childMainAxisPosition."
            )
        }())
        return 0.0
    }

    /// Returns the distance along the cross axis from the zero of the cross
    /// axis in this sliver's paint coordinate space to the nearest side of
    /// the given child.
    ///
    /// Calling this for a child that is not visible is not valid.
    ///
    /// **Dart Source:** `sliver.dart:1663`
    open func childCrossAxisPosition(_ child: RenderObject) -> Double {
        return 0.0
    }

    /// Returns the scroll offset for the leading edge of the given child.
    ///
    /// The `child` must be a child of this sliver.
    ///
    /// This method differs from `childMainAxisPosition` in that
    /// `childMainAxisPosition` gives the distance from the leading _visible_
    /// edge of the sliver whereas `childScrollOffset` gives the distance from
    /// the sliver's zero scroll offset.
    ///
    /// **Dart Source:** `sliver.dart:1677-1680`
    open func childScrollOffset(_ child: RenderObject) -> Double? {
        assert(child.parent === self)
        return 0.0
    }

    // MARK: - Paint Transform

    /// Applies the paint transform to a child.
    ///
    /// Used by coordinate conversion functions to translate coordinates local
    /// to a child to coordinates local to this render object.
    ///
    /// **Dart Source:** `sliver.dart:1683-1689`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        assert({
            fatalError(
                "\(type(of: self)) does not implement applyPaintTransform."
            )
        }())
    }

    // MARK: - Absolute Size Methods

    /// Returns a `Size` with dimensions relative to the leading edge of the
    /// sliver, specifically the same offset that is given to the `paint`
    /// method. This means that the dimensions may be negative.
    ///
    /// This is only valid after `layout` has completed.
    ///
    /// **Dart Source:** `sliver.dart:1701-1713`
    public func getAbsoluteSizeRelativeToOrigin() -> Size {
        assert(geometry != nil)
        assert(!debugNeedsLayout)
        switch applyGrowthDirectionToAxisDirection(
            sliverConstraints.axisDirection,
            sliverConstraints.growthDirection
        ) {
        case .up:
            return Size(sliverConstraints.crossAxisExtent, -geometry!.paintExtent)
        case .down:
            return Size(sliverConstraints.crossAxisExtent, geometry!.paintExtent)
        case .left:
            return Size(-geometry!.paintExtent, sliverConstraints.crossAxisExtent)
        case .right:
            return Size(geometry!.paintExtent, sliverConstraints.crossAxisExtent)
        }
    }

    /// Returns the absolute `Size` of the sliver.
    ///
    /// The dimensions are always positive and calling this is only valid after
    /// `layout` has completed.
    ///
    /// **Dart Source:** `sliver.dart:1725-1736`
    public func getAbsoluteSize() -> Size {
        assert(geometry != nil)
        assert(!debugNeedsLayout)
        switch sliverConstraints.axisDirection {
        case .up, .down:
            return Size(sliverConstraints.crossAxisExtent, geometry!.paintExtent)
        case .right, .left:
            return Size(geometry!.paintExtent, sliverConstraints.crossAxisExtent)
        }
    }

    // MARK: - Debug Paint

    /// Draws debug visualizations for this sliver.
    ///
    /// **Dart Source:** `sliver.dart:1738-1831`
    private func _debugDrawArrow(
        _ canvas: any Canvas,
        _ paint: Paint,
        _ p0: Offset,
        _ p1: Offset,
        _ direction: GrowthDirection
    ) {
        assert({
            if p0 == p1 {
                return true
            }
            assert(p0.dx == p1.dx || p0.dy == p1.dy)  // must be axis-aligned
            let d = (p1 - p0).distance * 0.2
            var drawP0 = p0
            var drawP1 = p1
            var dx1, dx2, dy1, dy2: Double
            switch direction {
            case .forward:
                dx1 = d; dx2 = d; dy1 = d; dy2 = d
            case .reverse:
                let temp = drawP0
                drawP0 = drawP1
                drawP1 = temp
                dx1 = -d; dx2 = -d; dy1 = -d; dy2 = -d
            }
            if drawP0.dx == drawP1.dx {
                dx2 = -dx2
            } else {
                dy2 = -dy2
            }
            let path = Path()
            path.moveTo(drawP0.dx, drawP0.dy)
            path.lineTo(drawP1.dx, drawP1.dy)
            path.moveTo(drawP1.dx - dx1, drawP1.dy - dy1)
            path.lineTo(drawP1.dx, drawP1.dy)
            path.lineTo(drawP1.dx - dx2, drawP1.dy - dy2)
            canvas.drawPath(path, paint)
            return true
        }())
    }

    /// **Dart Source:** `sliver.dart:1781-1831`
    open func debugPaint(_ context: PaintingContext, _ offset: Offset) {
        assert({
            if debugPaintSizeEnabled {
                let strokeWidth = min(4.0, geometry!.paintExtent / 30.0)
                let paint = Paint()
                paint.color = Color(0xFF33CC33)
                paint.strokeWidth = strokeWidth
                paint.style = .stroke
                paint.maskFilter = MaskFilter(blur: .solid, strokeWidth)
                let arrowExtent = geometry!.paintExtent
                let padding = max(2.0, strokeWidth)
                let canvas = context.canvas
                canvas.drawCircle(
                    offset.translate(padding, padding),
                    padding * 0.5,
                    paint
                )
                switch sliverConstraints.axis {
                case .vertical:
                    canvas.drawLine(
                        offset,
                        offset.translate(sliverConstraints.crossAxisExtent, 0.0),
                        paint
                    )
                    _debugDrawArrow(
                        canvas, paint,
                        offset.translate(sliverConstraints.crossAxisExtent * 1.0 / 4.0, padding),
                        offset.translate(
                            sliverConstraints.crossAxisExtent * 1.0 / 4.0,
                            arrowExtent - padding
                        ),
                        sliverConstraints.normalizedGrowthDirection
                    )
                    _debugDrawArrow(
                        canvas, paint,
                        offset.translate(sliverConstraints.crossAxisExtent * 3.0 / 4.0, padding),
                        offset.translate(
                            sliverConstraints.crossAxisExtent * 3.0 / 4.0,
                            arrowExtent - padding
                        ),
                        sliverConstraints.normalizedGrowthDirection
                    )
                case .horizontal:
                    canvas.drawLine(
                        offset,
                        offset.translate(0.0, sliverConstraints.crossAxisExtent),
                        paint
                    )
                    _debugDrawArrow(
                        canvas, paint,
                        offset.translate(padding, sliverConstraints.crossAxisExtent * 1.0 / 4.0),
                        offset.translate(
                            arrowExtent - padding,
                            sliverConstraints.crossAxisExtent * 1.0 / 4.0
                        ),
                        sliverConstraints.normalizedGrowthDirection
                    )
                    _debugDrawArrow(
                        canvas, paint,
                        offset.translate(padding, sliverConstraints.crossAxisExtent * 3.0 / 4.0),
                        offset.translate(
                            arrowExtent - padding,
                            sliverConstraints.crossAxisExtent * 3.0 / 4.0
                        ),
                        sliverConstraints.normalizedGrowthDirection
                    )
                }
            }
            return true
        }())
    }

    // MARK: - Event Handling

    /// Handle an event that hit this sliver.
    ///
    /// **Dart Source:** `sliver.dart:1835`
    open override func handleEvent(_ event: PointerEvent, entry: HitTestEntry<AnyHitTestTarget>) {
        // Default: do nothing
    }

    // MARK: - Debug Fill Properties

    /// **Dart Source:** `sliver.dart:1838-1841`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(DiagnosticsProperty<SliverGeometry>("geometry", geometry))
    }
}

// =============================================================================
// MARK: - S7: RenderSliverHelpers, RenderSliverSingleBoxAdapter, RenderSliverToBoxAdapter
// =============================================================================

// MARK: - RenderSliverHelpers

/// Protocol providing helper methods for `RenderSliver` subclasses that
/// contain `RenderBox` children.
///
/// Dart mixin `RenderSliverHelpers implements RenderSliver` is expressed
/// in Swift as a protocol with default implementations via extension.
/// These utility methods convert between the sliver coordinate system and
/// the Cartesian coordinate system used by `RenderBox`.
///
/// **Dart Source:** `sliver.dart:1845-1927`
public protocol RenderSliverHelpers: AnyObject {
    var sliverConstraints: SliverConstraints { get }
    var geometry: SliverGeometry? { get }
    func childMainAxisPosition(_ child: RenderObject) -> Double
    func childCrossAxisPosition(_ child: RenderObject) -> Double
}

extension RenderSliverHelpers {

    /// Determines whether the sliver contents are oriented the "right way up"
    /// (i.e. the growth direction matches the axis direction).
    ///
    /// **Dart Source:** `sliver.dart:1846-1851`
    fileprivate func _getRightWayUp(_ constraints: SliverConstraints) -> Bool {
        let reversed = axisDirectionIsReversed(constraints.axisDirection)
        switch constraints.growthDirection {
        case .forward:
            return !reversed
        case .reverse:
            return reversed
        }
    }

    /// Utility function for `hitTestChildren` for use when the children are
    /// `RenderBox` widgets.
    ///
    /// This function takes care of converting the position from the sliver
    /// coordinate system to the Cartesian coordinate system used by `RenderBox`.
    ///
    /// This function relies on `childMainAxisPosition` to determine the
    /// position of the child in question.
    ///
    /// Calling this for a child that is not visible is not valid.
    ///
    /// **Dart Source:** `sliver.dart:1854-1898`
    public func hitTestBoxChild(
        _ result: BoxHitTestResult,
        _ child: RenderBox,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        let rightWayUp = _getRightWayUp(sliverConstraints)
        var delta = childMainAxisPosition(child)
        let crossAxisDelta = childCrossAxisPosition(child)
        var absolutePosition = mainAxisPosition - delta
        let absoluteCrossAxisPosition = crossAxisPosition - crossAxisDelta
        let paintOffset: Offset
        let transformedPosition: Offset
        switch sliverConstraints.axis {
        case .horizontal:
            if !rightWayUp {
                absolutePosition = child.size.width - absolutePosition
                delta = geometry!.paintExtent - child.size.width - delta
            }
            paintOffset = Offset(delta, crossAxisDelta)
            transformedPosition = Offset(absolutePosition, absoluteCrossAxisPosition)
        case .vertical:
            if !rightWayUp {
                absolutePosition = child.size.height - absolutePosition
                delta = geometry!.paintExtent - child.size.height - delta
            }
            paintOffset = Offset(crossAxisDelta, delta)
            transformedPosition = Offset(absoluteCrossAxisPosition, absolutePosition)
        }
        return result.addWithOutOfBandPosition(
            paintOffset: paintOffset,
            hitTest: { (result: BoxHitTestResult) -> Bool in
                return child.hitTest(result, position: transformedPosition)
            }
        )
    }

    /// Utility function for `applyPaintTransform` for use when the children are
    /// `RenderBox` widgets.
    ///
    /// This function turns the value returned by `childMainAxisPosition` and
    /// `childCrossAxisPosition` for the child in question into a translation
    /// that it then applies to the given matrix.
    ///
    /// Calling this for a child that is not visible is not valid.
    ///
    /// **Dart Source:** `sliver.dart:1901-1926`
    public func applyPaintTransformForBoxChild(_ child: RenderBox, _ transform: inout Matrix4) {
        let rightWayUp = _getRightWayUp(sliverConstraints)
        var delta = childMainAxisPosition(child)
        let crossAxisDelta = childCrossAxisPosition(child)
        switch sliverConstraints.axis {
        case .horizontal:
            if !rightWayUp {
                delta = geometry!.paintExtent - child.size.width - delta
            }
            transform = Matrix4.translationValues(delta, crossAxisDelta, 0) * transform
        case .vertical:
            if !rightWayUp {
                delta = geometry!.paintExtent - child.size.height - delta
            }
            transform = Matrix4.translationValues(crossAxisDelta, delta, 0) * transform
        }
    }
}

// MARK: - RenderSliverSingleBoxAdapter

/// An abstract class for `RenderSliver`s that contains a single `RenderBox`.
///
/// In Dart, `RenderSliverSingleBoxAdapter` extends `RenderSliver` with the
/// `RenderObjectWithChildMixin<RenderBox>` and `RenderSliverHelpers` mixins.
/// In Swift, the single-child management from `RenderObjectWithChildMixin` is
/// integrated directly on the class (same pattern as `RenderShiftedBox`), and
/// `RenderSliverHelpers` is adopted as a protocol conformance.
///
/// See also:
///
///  - `RenderSliver`, which explains more about the Sliver protocol.
///  - `RenderBox`, which explains more about the Box protocol.
///  - `RenderSliverToBoxAdapter`, which extends this class to size the child
///    according to its preferred size.
///
/// **Dart Source:** `sliver.dart:1932-2021`
open class RenderSliverSingleBoxAdapter: RenderSliver, RenderSliverHelpers {

    // MARK: - Initializer

    /// Creates a `RenderSliver` that wraps a `RenderBox`.
    ///
    /// **Dart Source:** `sliver.dart:1945-1947`
    public init(child: RenderBox? = nil) {
        super.init()
        self.child = child
    }

    // MARK: - Child Management (RenderObjectWithChildMixin pattern)

    /// The single child of this render object.
    ///
    /// In Dart, `RenderSliverSingleBoxAdapter` uses
    /// `RenderObjectWithChildMixin<RenderBox>` to manage its single child.
    /// In Swift, since generic mixins are not supported, the child property
    /// is implemented directly.
    ///
    /// **Dart Source:** `sliver.dart:1943` (via RenderObjectWithChildMixin)
    public var child: RenderBox? {
        get { _child }
        set {
            if let oldChild = _child {
                oldChild.parentData = nil
            }
            _child = newValue
            if let newChild = _child {
                setupParentData(newChild)
            }
            markNeedsLayout()
        }
    }
    private var _child: RenderBox?

    // MARK: - Parent Data

    /// Sets up `SliverPhysicalParentData` for the given child.
    ///
    /// **Dart Source:** `sliver.dart:1949-1953`
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is SliverPhysicalParentData) {
            child.parentData = SliverPhysicalParentData()
        }
    }

    /// Sets the `SliverPhysicalParentData.paintOffset` for the given child
    /// according to the `SliverConstraints.axisDirection` and
    /// `SliverConstraints.growthDirection` and the given geometry.
    ///
    /// **Dart Source:** `sliver.dart:1956-1981`
    open func setChildParentData(
        _ child: RenderObject,
        _ constraints: SliverConstraints,
        _ geometry: SliverGeometry
    ) {
        let childParentData = child.parentData! as! SliverPhysicalParentData
        switch applyGrowthDirectionToAxisDirection(
            constraints.axisDirection,
            constraints.growthDirection
        ) {
        case .up:
            childParentData.paintOffset = Offset(
                0.0,
                geometry.paintExtent + constraints.scrollOffset - geometry.scrollExtent
            )
        case .left:
            childParentData.paintOffset = Offset(
                geometry.paintExtent + constraints.scrollOffset - geometry.scrollExtent,
                0.0
            )
        case .right:
            childParentData.paintOffset = Offset(-constraints.scrollOffset, 0.0)
        case .down:
            childParentData.paintOffset = Offset(0.0, -constraints.scrollOffset)
        }
    }

    // MARK: - Hit Testing

    /// **Dart Source:** `sliver.dart:1983-1998`
    open override func hitTestChildren(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        assert(geometry!.hitTestExtent > 0.0)
        if let child = child {
            return hitTestBoxChild(
                BoxHitTestResult(wrapping: result),
                child,
                mainAxisPosition: mainAxisPosition,
                crossAxisPosition: crossAxisPosition
            )
        }
        return false
    }

    // MARK: - Child Axis Position

    /// Returns the distance from the leading visible edge of the sliver to
    /// the side of the given child closest to that edge.
    ///
    /// **Dart Source:** `sliver.dart:2001-2003`
    open override func childMainAxisPosition(_ child: RenderObject) -> Double {
        return -sliverConstraints.scrollOffset
    }

    // MARK: - Paint Transform

    /// **Dart Source:** `sliver.dart:2006-2010`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        assert(child === self.child)
        let childParentData = child.parentData! as! SliverPhysicalParentData
        childParentData.applyPaintTransform(&transform)
    }

    // MARK: - Paint

    /// **Dart Source:** `sliver.dart:2013-2020`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if let child = child, geometry!.visible {
            let childParentData = child.parentData! as! SliverPhysicalParentData
            context.paintChild(child, offset + childParentData.paintOffset)
        }
    }
}

// MARK: - RenderSliverToBoxAdapter

/// A `RenderSliver` that contains a single `RenderBox`.
///
/// The child will not be laid out if it is not visible. It is sized according
/// to the child's preferences in the main axis, and with a tight constraint
/// forcing it to the dimensions of the viewport in the cross axis.
///
/// See also:
///
///  - `RenderSliver`, which explains more about the Sliver protocol.
///  - `RenderBox`, which explains more about the Box protocol.
///  - `RenderViewport`, which allows `RenderSliver` objects to be placed inside
///    a `RenderBox` (the opposite of this class).
///
/// **Dart Source:** `sliver.dart:2035-2067`
open class RenderSliverToBoxAdapter: RenderSliverSingleBoxAdapter {

    /// Creates a `RenderSliver` that wraps a `RenderBox`.
    ///
    /// **Dart Source:** `sliver.dart:2037`
    public override init(child: RenderBox? = nil) {
        super.init(child: child)
    }

    // MARK: - Layout

    /// Lays out the child box and computes the sliver geometry from
    /// the child's size.
    ///
    /// If there is no child, geometry is set to `SliverGeometry.zero`.
    /// Otherwise, the child is laid out with box constraints derived from
    /// the sliver constraints, and the sliver geometry is computed from the
    /// child's extent along the main axis.
    ///
    /// **Dart Source:** `sliver.dart:2039-2067`
    open override func performLayout() {
        guard let child = child else {
            geometry = .zero
            return
        }
        let constraints = self.sliverConstraints
        child.layout(constraints.asBoxConstraints(), parentUsesSize: true)
        let childExtent: Double
        switch constraints.axis {
        case .horizontal:
            childExtent = child.size.width
        case .vertical:
            childExtent = child.size.height
        }
        let paintedChildSize = calculatePaintOffset(constraints, from: 0.0, to: childExtent)
        let cacheExtent = calculateCacheOffset(constraints, from: 0.0, to: childExtent)

        assert(paintedChildSize.isFinite)
        assert(paintedChildSize >= 0.0)
        geometry = SliverGeometry(
            scrollExtent: childExtent,
            paintExtent: paintedChildSize,
            maxPaintExtent: childExtent,
            hitTestExtent: paintedChildSize,
            hasVisualOverflow:
                childExtent > constraints.remainingPaintExtent
                || constraints.scrollOffset > 0.0,
            cacheExtent: cacheExtent
        )
        setChildParentData(child, constraints, geometry!)
    }
}
