// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Basic widgets — convenience wrappers around render objects.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/basic.dart`

import FlutterSwiftBridge
// Selective imports: a full `import Foundation` would make `Locale` (used
// below) ambiguous with the framework's own Locale type. We only need these
// two symbols for unbuffered diagnostic logging.
import class Foundation.FileHandle
import struct Foundation.Data

// MARK: - Directionality

/// A widget that determines the ambient directionality of text and
/// text-direction-sensitive render objects.
///
/// **Dart Source:** `basic.dart:166`
public class Directionality: InheritedWidget {
    /// The text direction for this subtree.
    public let textDirection: TextDirection

    public init(
        key: (any Key)? = nil,
        textDirection: TextDirection,
        child: Widget
    ) {
        self.textDirection = textDirection
        super.init(key: key, child: child)
    }

    /// The text direction from the closest instance of this class that encloses
    /// the given context.
    public static func of(_ context: any BuildContext) -> TextDirection {
        let widget = context.dependOnInheritedWidgetOfExactType(Directionality.self)!
        return widget.textDirection
    }

    /// The text direction from the closest instance of this class that encloses
    /// the given context, or nil if there is none.
    public static func maybeOf(_ context: any BuildContext) -> TextDirection? {
        let widget = context.dependOnInheritedWidgetOfExactType(Directionality.self)
        return widget?.textDirection
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        return textDirection != (oldWidget as! Directionality).textDirection
    }
}

// MARK: - Opacity

/// Makes its child partially transparent.
///
/// **Dart Source:** `basic.dart:331`
public class Opacity: SingleChildRenderObjectWidget {
    public let opacity: Double
    public let alwaysIncludeSemantics: Bool

    public init(
        key: (any Key)? = nil,
        opacity: Double,
        alwaysIncludeSemantics: Bool = false,
        child: Widget? = nil
    ) {
        assert(opacity >= 0.0 && opacity <= 1.0)
        self.opacity = opacity
        self.alwaysIncludeSemantics = alwaysIncludeSemantics
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderOpacity(
            opacity: opacity,
            alwaysIncludeSemantics: alwaysIncludeSemantics
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderOpacity
        ro.opacity = opacity
        ro.alwaysIncludeSemantics = alwaysIncludeSemantics
    }
}

// MARK: - CustomPaint

/// A widget that provides a canvas on which to draw during the paint phase.
///
/// **Dart Source:** `basic.dart:773`
public class CustomPaint: SingleChildRenderObjectWidget {
    public let painter: CustomPainter?
    public let foregroundPainter: CustomPainter?
    public let preferredSize: Size
    public let isComplex: Bool
    public let willChange: Bool

    public init(
        key: (any Key)? = nil,
        painter: CustomPainter? = nil,
        foregroundPainter: CustomPainter? = nil,
        size: Size = .zero,
        isComplex: Bool = false,
        willChange: Bool = false,
        child: Widget? = nil
    ) {
        self.painter = painter
        self.foregroundPainter = foregroundPainter
        self.preferredSize = size
        self.isComplex = isComplex
        self.willChange = willChange
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderCustomPaint(
            painter: painter,
            foregroundPainter: foregroundPainter,
            preferredSize: preferredSize,
            isComplex: isComplex,
            willChange: willChange
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderCustomPaint
        ro.painter = painter
        ro.foregroundPainter = foregroundPainter
        ro.preferredSize = preferredSize
        ro.isComplex = isComplex
        ro.willChange = willChange
    }
}

// MARK: - ClipRect

/// Clips its child using a rectangle.
///
/// **Dart Source:** `basic.dart:892`
public class ClipRect: SingleChildRenderObjectWidget {
    public let clipper: CustomClipper<Rect>?
    public let clipBehavior: Clip

    public init(
        key: (any Key)? = nil,
        clipper: CustomClipper<Rect>? = nil,
        clipBehavior: Clip = .hardEdge,
        child: Widget? = nil
    ) {
        self.clipper = clipper
        self.clipBehavior = clipBehavior
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderClipRect(
            clipper: clipper,
            clipBehavior: clipBehavior
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderClipRect
        ro.clipper = clipper
        ro.clipBehavior = clipBehavior
    }
}

// MARK: - ClipRRect

/// Clips its child using a rounded rectangle.
///
/// **Dart Source:** `basic.dart:975`
public class ClipRRect: SingleChildRenderObjectWidget {
    public let borderRadius: BorderRadiusGeometry
    public let clipper: CustomClipper<RRect>?
    public let clipBehavior: Clip

    public init(
        key: (any Key)? = nil,
        borderRadius: BorderRadiusGeometry = BorderRadius.zero,
        clipper: CustomClipper<RRect>? = nil,
        clipBehavior: Clip = .antiAlias,
        child: Widget? = nil
    ) {
        self.borderRadius = borderRadius
        self.clipper = clipper
        self.clipBehavior = clipBehavior
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderClipRRect(
            borderRadius: borderRadius,
            clipper: clipper,
            clipBehavior: clipBehavior
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderClipRRect
        ro.borderRadius = borderRadius
        ro.clipper = clipper
        ro.clipBehavior = clipBehavior
    }
}

// MARK: - ClipOval

/// Clips its child using an oval.
///
/// **Dart Source:** `basic.dart:1157`
public class ClipOval: SingleChildRenderObjectWidget {
    public let clipper: CustomClipper<Rect>?
    public let clipBehavior: Clip

    public init(
        key: (any Key)? = nil,
        clipper: CustomClipper<Rect>? = nil,
        clipBehavior: Clip = .antiAlias,
        child: Widget? = nil
    ) {
        self.clipper = clipper
        self.clipBehavior = clipBehavior
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderClipOval(
            clipper: clipper,
            clipBehavior: clipBehavior
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderClipOval
        ro.clipper = clipper
        ro.clipBehavior = clipBehavior
    }
}

// MARK: - PhysicalModel

/// A widget representing a physical layer that clips its children to a shape.
///
/// **Dart Source:** `basic.dart:1313`
public class PhysicalModel: SingleChildRenderObjectWidget {
    public let shape: BoxShape
    public let clipBehavior: Clip
    public let borderRadius: BorderRadius?
    public let elevation: Double
    public let color: Color
    public let shadowColor: Color

    public init(
        key: (any Key)? = nil,
        shape: BoxShape = .rectangle,
        clipBehavior: Clip = .none,
        borderRadius: BorderRadius? = nil,
        elevation: Double = 0.0,
        color: Color,
        shadowColor: Color = Color(0xFF000000),
        child: Widget? = nil
    ) {
        self.shape = shape
        self.clipBehavior = clipBehavior
        self.borderRadius = borderRadius
        self.elevation = elevation
        self.color = color
        self.shadowColor = shadowColor
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderPhysicalModel(
            shape: shape,
            clipBehavior: clipBehavior,
            borderRadius: borderRadius,
            elevation: elevation,
            color: color,
            shadowColor: shadowColor
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderPhysicalModel
        ro.shape = shape
        ro.clipBehavior = clipBehavior
        ro.borderRadius = borderRadius
        ro.elevation = elevation
        ro.color = color
        ro.shadowColor = shadowColor
    }
}

// MARK: - Transform

/// A widget that applies a transformation before painting its child.
///
/// **Dart Source:** `basic.dart:1525`
public class Transform: SingleChildRenderObjectWidget {
    public let transform: Matrix4
    public let origin: Offset?
    public let alignment: (any AlignmentGeometry)?
    public let transformHitTests: Bool
    public let filterQuality: FilterQuality?

    public init(
        key: (any Key)? = nil,
        transform: Matrix4,
        origin: Offset? = nil,
        alignment: (any AlignmentGeometry)? = nil,
        transformHitTests: Bool = true,
        filterQuality: FilterQuality? = nil,
        child: Widget? = nil
    ) {
        self.transform = transform
        self.origin = origin
        self.alignment = alignment
        self.transformHitTests = transformHitTests
        self.filterQuality = filterQuality
        super.init(key: key, child: child)
    }

    /// Creates a widget that transforms its child using a rotation around the
    /// center.
    public convenience init(
        rotate angle: Double,
        key: (any Key)? = nil,
        origin: Offset? = nil,
        alignment: (any AlignmentGeometry)? = Alignment.center,
        transformHitTests: Bool = true,
        filterQuality: FilterQuality? = nil,
        child: Widget? = nil
    ) {
        self.init(
            key: key,
            transform: Matrix4.rotationZ(angle),
            origin: origin,
            alignment: alignment,
            transformHitTests: transformHitTests,
            filterQuality: filterQuality,
            child: child
        )
    }

    /// Creates a widget that transforms its child using a translation.
    public convenience init(
        translate offset: Offset,
        key: (any Key)? = nil,
        transformHitTests: Bool = true,
        filterQuality: FilterQuality? = nil,
        child: Widget? = nil
    ) {
        self.init(
            key: key,
            transform: Matrix4.translationValues(offset.dx, offset.dy, 0.0),
            transformHitTests: transformHitTests,
            filterQuality: filterQuality,
            child: child
        )
    }

    /// Creates a widget that scales its child uniformly.
    public convenience init(
        scale: Double,
        key: (any Key)? = nil,
        origin: Offset? = nil,
        alignment: (any AlignmentGeometry)? = Alignment.center,
        transformHitTests: Bool = true,
        filterQuality: FilterQuality? = nil,
        child: Widget? = nil
    ) {
        self.init(
            key: key,
            transform: Matrix4.diagonal3Values(scale, scale, 1.0),
            origin: origin,
            alignment: alignment,
            transformHitTests: transformHitTests,
            filterQuality: filterQuality,
            child: child
        )
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderTransform(
            transform: transform,
            origin: origin,
            alignment: alignment,
            textDirection: Directionality.maybeOf(context),
            transformHitTests: transformHitTests,
            filterQuality: filterQuality
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderTransform
        ro.transform = transform
        ro.origin = origin
        ro.alignment = alignment
        ro.textDirection = Directionality.maybeOf(context)
        ro.transformHitTests = transformHitTests
        ro.filterQuality = filterQuality
    }
}

// MARK: - FittedBox

/// Scales and positions its child within itself according to `fit`.
///
/// **Dart Source:** `basic.dart:2033`
public class FittedBox: SingleChildRenderObjectWidget {
    public let fit: BoxFit
    public let alignment: any AlignmentGeometry
    public let clipBehavior: Clip

    public init(
        key: (any Key)? = nil,
        fit: BoxFit = .contain,
        alignment: any AlignmentGeometry = Alignment.center,
        clipBehavior: Clip = .none,
        child: Widget? = nil
    ) {
        self.fit = fit
        self.alignment = alignment
        self.clipBehavior = clipBehavior
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderFittedBox(
            fit: fit,
            alignment: alignment,
            textDirection: Directionality.maybeOf(context),
            clipBehavior: clipBehavior
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderFittedBox
        ro.fit = fit
        ro.alignment = alignment
        ro.textDirection = Directionality.maybeOf(context)
        ro.clipBehavior = clipBehavior
    }
}

// MARK: - FractionalTranslation

/// Applies a translation expressed as a fraction of the box's size before
/// painting its child.
///
/// **Dart Source:** `basic.dart:2111`
public class FractionalTranslation: SingleChildRenderObjectWidget {
    public let translation: Offset
    public let transformHitTests: Bool

    public init(
        key: (any Key)? = nil,
        translation: Offset,
        transformHitTests: Bool = true,
        child: Widget? = nil
    ) {
        self.translation = translation
        self.transformHitTests = transformHitTests
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderFractionalTranslation(
            translation: translation,
            transformHitTests: transformHitTests
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderFractionalTranslation
        ro.translation = translation
        ro.transformHitTests = transformHitTests
    }
}

// MARK: - RotatedBox

/// Rotates its child by an integral number of quarter turns.
///
/// **Dart Source:** `basic.dart:2172`
public class RotatedBox: SingleChildRenderObjectWidget {
    public let quarterTurns: Int

    public init(
        key: (any Key)? = nil,
        quarterTurns: Int,
        child: Widget? = nil
    ) {
        self.quarterTurns = quarterTurns
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderRotatedBox(quarterTurns: quarterTurns)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderRotatedBox
        ro.quarterTurns = quarterTurns
    }
}

// MARK: - Padding

/// Insets its child by the given padding.
///
/// **Dart Source:** `basic.dart:2242`
public class Padding: SingleChildRenderObjectWidget {
    public let padding: any EdgeInsetsGeometry

    public init(
        key: (any Key)? = nil,
        padding: any EdgeInsetsGeometry,
        child: Widget? = nil
    ) {
        self.padding = padding
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderPadding(
            padding: padding,
            textDirection: Directionality.maybeOf(context)
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderPadding
        ro.padding = padding
        ro.textDirection = Directionality.maybeOf(context)
    }
}

// MARK: - Align

/// A widget that aligns its child within itself and optionally sizes itself
/// based on the child's size.
///
/// **Dart Source:** `basic.dart:2404`
public class Align: SingleChildRenderObjectWidget {
    public let alignment: any AlignmentGeometry
    public let widthFactor: Double?
    public let heightFactor: Double?

    public init(
        key: (any Key)? = nil,
        alignment: any AlignmentGeometry = Alignment.center,
        widthFactor: Double? = nil,
        heightFactor: Double? = nil,
        child: Widget? = nil
    ) {
        assert(widthFactor == nil || widthFactor! >= 0.0)
        assert(heightFactor == nil || heightFactor! >= 0.0)
        self.alignment = alignment
        self.widthFactor = widthFactor
        self.heightFactor = heightFactor
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderPositionedBox(
            widthFactor: widthFactor,
            heightFactor: heightFactor,
            alignment: alignment,
            textDirection: Directionality.maybeOf(context)
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderPositionedBox
        ro.alignment = alignment
        ro.widthFactor = widthFactor
        ro.heightFactor = heightFactor
        ro.textDirection = Directionality.maybeOf(context)
    }
}

// MARK: - Center

/// A widget that centers its child within itself.
///
/// **Dart Source:** `basic.dart:2492`
public class Center: Align {
    public init(
        key: (any Key)? = nil,
        widthFactor: Double? = nil,
        heightFactor: Double? = nil,
        child: Widget? = nil
    ) {
        super.init(
            key: key,
            alignment: Alignment.center,
            widthFactor: widthFactor,
            heightFactor: heightFactor,
            child: child
        )
    }
}

// MARK: - SizedBox

/// A box with a specified size.
///
/// If given a child, this widget forces it to have a specific width and/or
/// height (assuming values are permitted by the parent).
///
/// **Dart Source:** `basic.dart:2675`
public class SizedBox: SingleChildRenderObjectWidget {
    public let width: Double?
    public let height: Double?

    public init(
        key: (any Key)? = nil,
        width: Double? = nil,
        height: Double? = nil,
        child: Widget? = nil
    ) {
        self.width = width
        self.height = height
        super.init(key: key, child: child)
    }

    /// Creates a box that will become as large as its parent allows.
    public convenience init(
        expand _: Void = (),
        key: (any Key)? = nil,
        child: Widget? = nil
    ) {
        self.init(key: key, width: .infinity, height: .infinity, child: child)
    }

    /// Creates a box that will become as small as its parent allows.
    public convenience init(
        shrink _: Void = (),
        key: (any Key)? = nil,
        child: Widget? = nil
    ) {
        self.init(key: key, width: 0.0, height: 0.0, child: child)
    }

    /// Creates a box with the specified size.
    public convenience init(
        size: Size,
        key: (any Key)? = nil,
        child: Widget? = nil
    ) {
        self.init(key: key, width: size.width, height: size.height, child: child)
    }

    /// Creates a fixed-size square.
    public convenience init(
        square dimension: Double,
        key: (any Key)? = nil,
        child: Widget? = nil
    ) {
        self.init(key: key, width: dimension, height: dimension, child: child)
    }

    private var _additionalConstraints: BoxConstraints {
        return BoxConstraints.tightFor(width: width, height: height)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderConstrainedBox(additionalConstraints: _additionalConstraints)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderConstrainedBox
        ro.additionalConstraints = _additionalConstraints
    }
}

// MARK: - ConstrainedBox

/// A widget that imposes additional constraints on its child.
///
/// **Dart Source:** `basic.dart:2779`
public class ConstrainedBox: SingleChildRenderObjectWidget {
    public let constraints: BoxConstraints

    public init(
        key: (any Key)? = nil,
        constraints: BoxConstraints,
        child: Widget? = nil
    ) {
        self.constraints = constraints
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderConstrainedBox(additionalConstraints: constraints)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderConstrainedBox
        ro.additionalConstraints = constraints
    }
}

// MARK: - FractionallySizedBox

/// A widget that sizes its child to a fraction of the total available space.
///
/// **Dart Source:** `basic.dart:3156`
public class FractionallySizedBox: SingleChildRenderObjectWidget {
    public let alignment: any AlignmentGeometry
    public let widthFactor: Double?
    public let heightFactor: Double?

    public init(
        key: (any Key)? = nil,
        alignment: any AlignmentGeometry = Alignment.center,
        widthFactor: Double? = nil,
        heightFactor: Double? = nil,
        child: Widget? = nil
    ) {
        assert(widthFactor == nil || widthFactor! >= 0.0)
        assert(heightFactor == nil || heightFactor! >= 0.0)
        self.alignment = alignment
        self.widthFactor = widthFactor
        self.heightFactor = heightFactor
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderFractionallySizedOverflowBox(
            widthFactor: widthFactor,
            heightFactor: heightFactor,
            alignment: alignment,
            textDirection: Directionality.maybeOf(context)
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderFractionallySizedOverflowBox
        ro.widthFactor = widthFactor
        ro.heightFactor = heightFactor
        ro.alignment = alignment
        ro.textDirection = Directionality.maybeOf(context)
    }
}

// MARK: - LimitedBox

/// A box that limits its size only when it's unconstrained.
///
/// **Dart Source:** `basic.dart:3267`
public class LimitedBox: SingleChildRenderObjectWidget {
    public let maxWidth: Double
    public let maxHeight: Double

    public init(
        key: (any Key)? = nil,
        maxWidth: Double = .infinity,
        maxHeight: Double = .infinity,
        child: Widget? = nil
    ) {
        assert(maxWidth >= 0.0)
        assert(maxHeight >= 0.0)
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderLimitedBox(maxWidth: maxWidth, maxHeight: maxHeight)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderLimitedBox
        ro.maxWidth = maxWidth
        ro.maxHeight = maxHeight
    }
}

// MARK: - OverflowBox

/// A widget that imposes different constraints on its child than it gets
/// from its parent, possibly allowing the child to overflow the parent.
///
/// **Dart Source:** `basic.dart:3328`
public class OverflowBox: SingleChildRenderObjectWidget {
    public let alignment: any AlignmentGeometry
    public let minWidth: Double?
    public let maxWidth: Double?
    public let minHeight: Double?
    public let maxHeight: Double?
    public let fit: OverflowBoxFit

    public init(
        key: (any Key)? = nil,
        alignment: any AlignmentGeometry = Alignment.center,
        minWidth: Double? = nil,
        maxWidth: Double? = nil,
        minHeight: Double? = nil,
        maxHeight: Double? = nil,
        fit: OverflowBoxFit = .max,
        child: Widget? = nil
    ) {
        self.alignment = alignment
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.fit = fit
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderConstrainedOverflowBox(
            minWidth: minWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            maxHeight: maxHeight,
            fit: fit,
            alignment: alignment,
            textDirection: Directionality.maybeOf(context)
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderConstrainedOverflowBox
        ro.minWidth = minWidth
        ro.maxWidth = maxWidth
        ro.minHeight = minHeight
        ro.maxHeight = maxHeight
        ro.fit = fit
        ro.alignment = alignment
        ro.textDirection = Directionality.maybeOf(context)
    }
}

// MARK: - SizedOverflowBox

/// A widget that is a specific size but passes its original constraints
/// through to its child, which may then overflow.
///
/// **Dart Source:** `basic.dart:3437`
public class SizedOverflowBox: SingleChildRenderObjectWidget {
    public let alignment: any AlignmentGeometry
    public let requestedSize: Size

    public init(
        key: (any Key)? = nil,
        size: Size,
        alignment: any AlignmentGeometry = Alignment.center,
        child: Widget? = nil
    ) {
        self.requestedSize = size
        self.alignment = alignment
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderSizedOverflowBox(
            requestedSize: requestedSize,
            alignment: alignment,
            textDirection: Directionality.maybeOf(context)
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderSizedOverflowBox
        ro.requestedSize = requestedSize
        ro.alignment = alignment
        ro.textDirection = Directionality.maybeOf(context)
    }
}

// MARK: - Offstage

/// Lays the child out as if it was in the tree, but without painting anything,
/// without making the child available for hit testing, and without taking any
/// room in the parent.
///
/// **Dart Source:** `basic.dart:3525`
public class Offstage: SingleChildRenderObjectWidget {
    public let offstage: Bool

    public init(
        key: (any Key)? = nil,
        offstage: Bool = true,
        child: Widget? = nil
    ) {
        self.offstage = offstage
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderOffstage(offstage: offstage)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderOffstage
        ro.offstage = offstage
    }
}

// MARK: - AspectRatio

/// A widget that attempts to size the child to a specific aspect ratio.
///
/// **Dart Source:** `basic.dart:3650`
public class AspectRatio: SingleChildRenderObjectWidget {
    public let aspectRatio: Double

    public init(
        key: (any Key)? = nil,
        aspectRatio: Double,
        child: Widget? = nil
    ) {
        self.aspectRatio = aspectRatio
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderAspectRatio(aspectRatio: aspectRatio)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderAspectRatio
        ro.aspectRatio = aspectRatio
    }
}

// MARK: - IntrinsicWidth

/// A widget that sizes its child to the child's maximum intrinsic width.
///
/// **Dart Source:** `basic.dart:3714`
public class IntrinsicWidth: SingleChildRenderObjectWidget {
    public let stepWidth: Double?
    public let stepHeight: Double?

    public init(
        key: (any Key)? = nil,
        stepWidth: Double? = nil,
        stepHeight: Double? = nil,
        child: Widget? = nil
    ) {
        self.stepWidth = stepWidth
        self.stepHeight = stepHeight
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderIntrinsicWidth(stepWidth: stepWidth, stepHeight: stepHeight)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderIntrinsicWidth
        ro.stepWidth = stepWidth
        ro.stepHeight = stepHeight
    }
}

// MARK: - IntrinsicHeight

/// A widget that sizes its child to the child's intrinsic height.
///
/// **Dart Source:** `basic.dart:3789`
public class IntrinsicHeight: SingleChildRenderObjectWidget {
    public override init(
        key: (any Key)? = nil,
        child: Widget? = nil
    ) {
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderIntrinsicHeight()
    }
}

// MARK: - Baseline

/// A widget that positions its child according to the child's baseline.
///
/// **Dart Source:** `basic.dart:3816`
public class Baseline: SingleChildRenderObjectWidget {
    public let baseline: Double
    public let baselineType: TextBaseline

    public init(
        key: (any Key)? = nil,
        baseline: Double,
        baselineType: TextBaseline,
        child: Widget? = nil
    ) {
        self.baseline = baseline
        self.baselineType = baselineType
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderBaseline(baseline: baseline, baselineType: baselineType)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderBaseline
        ro.baseline = baseline
        ro.baselineType = baselineType
    }
}

// MARK: - ListBody

/// A widget that arranges its children sequentially along a given axis,
/// forcing them to the dimension of the parent in the other axis.
///
/// **Dart Source:** `basic.dart:4474`
public class ListBody: MultiChildRenderObjectWidget {
    public let mainAxis: Axis
    public let reverse: Bool

    public init(
        key: (any Key)? = nil,
        mainAxis: Axis = .vertical,
        reverse: Bool = false,
        children: [Widget] = []
    ) {
        self.mainAxis = mainAxis
        self.reverse = reverse
        super.init(key: key, children: children)
    }

    private var _axisDirection: AxisDirection {
        switch mainAxis {
        case .horizontal:
            return reverse ? .left : .right
        case .vertical:
            return reverse ? .up : .down
        }
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderListBody(axisDirection: _axisDirection)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderListBody
        ro.axisDirection = _axisDirection
    }
}

// MARK: - Stack

/// A widget that positions its children relative to the edges of its box.
///
/// **Dart Source:** `basic.dart:4628`
public class Stack: MultiChildRenderObjectWidget {
    public let alignment: any AlignmentGeometry
    public let textDirection: TextDirection?
    public let fit: StackFit
    public let clipBehavior: Clip

    public init(
        key: (any Key)? = nil,
        alignment: any AlignmentGeometry = AlignmentDirectional.topStart,
        textDirection: TextDirection? = nil,
        fit: StackFit = .loose,
        clipBehavior: Clip = .hardEdge,
        children: [Widget] = []
    ) {
        self.alignment = alignment
        self.textDirection = textDirection
        self.fit = fit
        self.clipBehavior = clipBehavior
        super.init(key: key, children: children)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderStack(
            alignment: alignment,
            textDirection: textDirection ?? Directionality.maybeOf(context),
            fit: fit,
            clipBehavior: clipBehavior
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderStack
        ro.alignment = alignment
        ro.textDirection = textDirection ?? Directionality.maybeOf(context)
        ro.fit = fit
        ro.clipBehavior = clipBehavior
    }
}

// MARK: - IndexedStack

/// A Stack that shows a single child from a list of children.
///
/// **Dart Source:** `basic.dart:4761`
public class IndexedStack: StatelessWidget {
    public let alignment: any AlignmentGeometry
    public let textDirection: TextDirection?
    public let clipBehavior: Clip
    public let sizing: StackFit
    public let index: Int?
    public let stackChildren: [Widget]

    public init(
        key: (any Key)? = nil,
        alignment: any AlignmentGeometry = AlignmentDirectional.topStart,
        textDirection: TextDirection? = nil,
        clipBehavior: Clip = .hardEdge,
        sizing: StackFit = .loose,
        index: Int? = 0,
        children: [Widget] = []
    ) {
        self.alignment = alignment
        self.textDirection = textDirection
        self.clipBehavior = clipBehavior
        self.sizing = sizing
        self.index = index
        self.stackChildren = children
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let wrappedChildren: [Widget] = stackChildren.enumerated().map { (i, child) in
            if i == index {
                return child
            }
            return Offstage(offstage: true, child: child)
        }
        return Stack(
            alignment: alignment,
            textDirection: textDirection,
            fit: sizing,
            clipBehavior: clipBehavior,
            children: wrappedChildren
        )
    }
}

// MARK: - Positioned

/// A widget that controls where a child of a Stack is positioned.
///
/// **Dart Source:** `basic.dart:4934`
public class Positioned: ParentDataWidget<StackParentData> {
    public let left: Double?
    public let top: Double?
    public let right: Double?
    public let bottom: Double?
    public let width: Double?
    public let height: Double?

    public init(
        key: (any Key)? = nil,
        left: Double? = nil,
        top: Double? = nil,
        right: Double? = nil,
        bottom: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        child: Widget
    ) {
        assert(left == nil || right == nil || width == nil)
        assert(top == nil || bottom == nil || height == nil)
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        self.width = width
        self.height = height
        super.init(key: key, child: child)
    }

    /// Creates a Positioned object with the values from the given Rect.
    public convenience init(
        fromRect rect: Rect,
        key: (any Key)? = nil,
        child: Widget
    ) {
        self.init(
            key: key,
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: child
        )
    }

    /// Creates a Positioned object with the values from the given RelativeRect.
    public convenience init(
        fromRelativeRect rect: RelativeRect,
        key: (any Key)? = nil,
        child: Widget
    ) {
        self.init(
            key: key,
            left: rect.left,
            top: rect.top,
            right: rect.right,
            bottom: rect.bottom,
            width: nil,
            height: nil,
            child: child
        )
    }

    /// Creates a Positioned object with left, top, right, and bottom set to 0.0
    /// unless a value for them is passed.
    public convenience init(
        fill _: Void,
        key: (any Key)? = nil,
        left: Double? = 0.0,
        top: Double? = 0.0,
        right: Double? = 0.0,
        bottom: Double? = 0.0,
        child: Widget
    ) {
        self.init(
            key: key,
            left: left,
            top: top,
            right: right,
            bottom: bottom,
            width: nil,
            height: nil,
            child: child
        )
    }

    public override func applyParentData(_ renderObject: RenderObject) {
        // A `Positioned` must be a direct child of a `Stack`. If its nearest
        // RenderObject ancestor is not a RenderStack, the child's parentData
        // is not a StackParentData. Real Flutter throws a catchable
        // FlutterError here; for the compositor we MUST NOT SIGILL the whole
        // process on one malformed subtree — a third-party/Android Wayland
        // client can trigger it — so log and degrade (the child is simply
        // laid out unpositioned instead of crashing every window on screen).
        guard let parentData = renderObject.parentData as? StackParentData else {
            let msg = "[Positioned] applyParentData: expected StackParentData but got "
                + "\(type(of: renderObject.parentData)) on \(type(of: renderObject)) -- "
                + "Positioned is not directly inside a Stack; skipping "
                + "(l=\(String(describing: left)) t=\(String(describing: top)) "
                + "r=\(String(describing: right)) b=\(String(describing: bottom)) "
                + "w=\(String(describing: width)) h=\(String(describing: height)))\n"
            // try? — the point of this path is to DEGRADE. FileHandle's
            // non-throwing write traps when the write fails (e.g. a Windows
            // GUI app with no stderr), which would turn the warning itself
            // into the crash it exists to avoid.
            try? FileHandle.standardError.write(contentsOf: Data(msg.utf8))
            return
        }
        var needsLayout = false

        if parentData.left != left {
            parentData.left = left
            needsLayout = true
        }
        if parentData.top != top {
            parentData.top = top
            needsLayout = true
        }
        if parentData.right != right {
            parentData.right = right
            needsLayout = true
        }
        if parentData.bottom != bottom {
            parentData.bottom = bottom
            needsLayout = true
        }
        if parentData.width != width {
            parentData.width = width
            needsLayout = true
        }
        if parentData.height != height {
            parentData.height = height
            needsLayout = true
        }

        if needsLayout {
            renderObject.parent?.markNeedsLayout()
        }
    }
}

// MARK: - Flex

/// A widget that displays its children in a one-dimensional array.
///
/// **Dart Source:** `basic.dart:5334`
public class Flex: MultiChildRenderObjectWidget {
    public let direction: Axis
    public let mainAxisAlignment: MainAxisAlignment
    public let mainAxisSize: MainAxisSize
    public let crossAxisAlignment: CrossAxisAlignment
    public let textDirection: TextDirection?
    public let verticalDirection: VerticalDirection
    public let textBaseline: TextBaseline?
    public let clipBehavior: Clip
    public let spacing: Double

    public init(
        key: (any Key)? = nil,
        direction: Axis,
        mainAxisAlignment: MainAxisAlignment = .start,
        mainAxisSize: MainAxisSize = .max,
        crossAxisAlignment: CrossAxisAlignment = .center,
        textDirection: TextDirection? = nil,
        verticalDirection: VerticalDirection = .down,
        textBaseline: TextBaseline? = nil,
        clipBehavior: Clip = .none,
        spacing: Double = 0.0,
        children: [Widget] = []
    ) {
        self.direction = direction
        self.mainAxisAlignment = mainAxisAlignment
        self.mainAxisSize = mainAxisSize
        self.crossAxisAlignment = crossAxisAlignment
        self.textDirection = textDirection
        self.verticalDirection = verticalDirection
        self.textBaseline = textBaseline
        self.clipBehavior = clipBehavior
        self.spacing = spacing
        super.init(key: key, children: children)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderFlex(
            direction: direction,
            mainAxisAlignment: mainAxisAlignment,
            mainAxisSize: mainAxisSize,
            crossAxisAlignment: crossAxisAlignment,
            textDirection: textDirection ?? Directionality.maybeOf(context),
            verticalDirection: verticalDirection,
            textBaseline: textBaseline,
            clipBehavior: clipBehavior,
            spacing: spacing
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderFlex
        ro.direction = direction
        ro.mainAxisAlignment = mainAxisAlignment
        ro.mainAxisSize = mainAxisSize
        ro.crossAxisAlignment = crossAxisAlignment
        ro.textDirection = textDirection ?? Directionality.maybeOf(context)
        ro.verticalDirection = verticalDirection
        ro.textBaseline = textBaseline
        ro.clipBehavior = clipBehavior
        ro.spacing = spacing
    }
}

// MARK: - Row

/// A widget that displays its children in a horizontal array.
///
/// **Dart Source:** `basic.dart:5735`
public class Row: Flex {
    public init(
        key: (any Key)? = nil,
        mainAxisAlignment: MainAxisAlignment = .start,
        mainAxisSize: MainAxisSize = .max,
        crossAxisAlignment: CrossAxisAlignment = .center,
        textDirection: TextDirection? = nil,
        verticalDirection: VerticalDirection = .down,
        textBaseline: TextBaseline? = nil,
        spacing: Double = 0.0,
        children: [Widget] = []
    ) {
        super.init(
            key: key,
            direction: .horizontal,
            mainAxisAlignment: mainAxisAlignment,
            mainAxisSize: mainAxisSize,
            crossAxisAlignment: crossAxisAlignment,
            textDirection: textDirection,
            verticalDirection: verticalDirection,
            textBaseline: textBaseline,
            spacing: spacing,
            children: children
        )
    }
}

// MARK: - Column

/// A widget that displays its children in a vertical array.
///
/// **Dart Source:** `basic.dart:5927`
public class Column: Flex {
    public init(
        key: (any Key)? = nil,
        mainAxisAlignment: MainAxisAlignment = .start,
        mainAxisSize: MainAxisSize = .max,
        crossAxisAlignment: CrossAxisAlignment = .center,
        textDirection: TextDirection? = nil,
        verticalDirection: VerticalDirection = .down,
        textBaseline: TextBaseline? = nil,
        spacing: Double = 0.0,
        children: [Widget] = []
    ) {
        super.init(
            key: key,
            direction: .vertical,
            mainAxisAlignment: mainAxisAlignment,
            mainAxisSize: mainAxisSize,
            crossAxisAlignment: crossAxisAlignment,
            textDirection: textDirection,
            verticalDirection: verticalDirection,
            textBaseline: textBaseline,
            spacing: spacing,
            children: children
        )
    }
}

// MARK: - Flexible

/// A widget that controls how a child of a Row, Column, or Flex flexes.
///
/// **Dart Source:** `basic.dart:5970`
public class Flexible: ParentDataWidget<FlexParentData> {
    public let flex: Int
    public let fit: FlexFit

    public init(
        key: (any Key)? = nil,
        flex: Int = 1,
        fit: FlexFit = .loose,
        child: Widget
    ) {
        self.flex = flex
        self.fit = fit
        super.init(key: key, child: child)
    }

    public override func applyParentData(_ renderObject: RenderObject) {
        // Mirror of Positioned: `Flexible`/`Expanded` must sit directly inside
        // a Row/Column/Flex. Degrade instead of crashing the compositor.
        guard let parentData = renderObject.parentData as? FlexParentData else {
            let msg = "[Flexible] applyParentData: expected FlexParentData but got "
                + "\(type(of: renderObject.parentData)) on \(type(of: renderObject)) -- "
                + "Flexible/Expanded is not directly inside a Row/Column/Flex; skipping\n"
            // try? — degrade-path warning; see Positioned.applyParentData.
            try? FileHandle.standardError.write(contentsOf: Data(msg.utf8))
            return
        }
        var needsLayout = false

        if parentData.flex != flex {
            parentData.flex = flex
            needsLayout = true
        }

        if parentData.fit != fit {
            parentData.fit = fit
            needsLayout = true
        }

        if needsLayout {
            renderObject.parent?.markNeedsLayout()
        }
    }
}

// MARK: - Expanded

/// A widget that expands a child of a Row, Column, or Flex so that the child
/// fills the available space.
///
/// **Dart Source:** `basic.dart:6061`
public class Expanded: Flexible {
    public init(
        key: (any Key)? = nil,
        flex: Int = 1,
        child: Widget
    ) {
        super.init(key: key, flex: flex, fit: .tight, child: child)
    }
}

// MARK: - Wrap

/// A widget that displays its children in multiple horizontal or vertical runs.
///
/// **Dart Source:** `basic.dart:6120`
public class Wrap: MultiChildRenderObjectWidget {
    public let direction: Axis
    public let alignment: WrapAlignment
    public let spacing: Double
    public let runAlignment: WrapAlignment
    public let runSpacing: Double
    public let crossAxisAlignment: WrapCrossAlignment
    public let textDirection: TextDirection?
    public let verticalDirection: VerticalDirection
    public let clipBehavior: Clip

    public init(
        key: (any Key)? = nil,
        direction: Axis = .horizontal,
        alignment: WrapAlignment = .start,
        spacing: Double = 0.0,
        runAlignment: WrapAlignment = .start,
        runSpacing: Double = 0.0,
        crossAxisAlignment: WrapCrossAlignment = .start,
        textDirection: TextDirection? = nil,
        verticalDirection: VerticalDirection = .down,
        clipBehavior: Clip = .none,
        children: [Widget] = []
    ) {
        self.direction = direction
        self.alignment = alignment
        self.spacing = spacing
        self.runAlignment = runAlignment
        self.runSpacing = runSpacing
        self.crossAxisAlignment = crossAxisAlignment
        self.textDirection = textDirection
        self.verticalDirection = verticalDirection
        self.clipBehavior = clipBehavior
        super.init(key: key, children: children)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderWrap(
            direction: direction,
            alignment: alignment,
            spacing: spacing,
            runAlignment: runAlignment,
            runSpacing: runSpacing,
            crossAxisAlignment: crossAxisAlignment,
            textDirection: textDirection ?? Directionality.maybeOf(context),
            verticalDirection: verticalDirection,
            clipBehavior: clipBehavior
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderWrap
        ro.direction = direction
        ro.alignment = alignment
        ro.spacing = spacing
        ro.runAlignment = runAlignment
        ro.runSpacing = runSpacing
        ro.crossAxisAlignment = crossAxisAlignment
        ro.textDirection = textDirection ?? Directionality.maybeOf(context)
        ro.verticalDirection = verticalDirection
        ro.clipBehavior = clipBehavior
    }
}

// MARK: - Flow

/// A widget that implements the flow layout algorithm.
///
/// **Dart Source:** `basic.dart:6396`
public class Flow: MultiChildRenderObjectWidget {
    public let delegate: FlowDelegate
    public let clipBehavior: Clip

    public init(
        key: (any Key)? = nil,
        delegate: FlowDelegate,
        clipBehavior: Clip = .hardEdge,
        children: [Widget] = []
    ) {
        self.delegate = delegate
        self.clipBehavior = clipBehavior
        super.init(key: key, children: children)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderFlow(delegate: delegate, clipBehavior: clipBehavior)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderFlow
        ro.delegate = delegate
        ro.clipBehavior = clipBehavior
    }
}

// MARK: - RichText

/// A paragraph of rich text.
///
/// **Dart Source:** `basic.dart:6521`
public class RichText: MultiChildRenderObjectWidget {
    public let text: InlineSpan
    public let textAlign: TextAlign
    public let textDirection: TextDirection?
    public let softWrap: Bool
    public let overflow: TextOverflow
    public let textScaler: any TextScaler
    public let maxLines: Int?
    public let locale: Locale?
    public let strutStyle: StrutStyle?
    public let textWidthBasis: TextWidthBasis
    public let textHeightBehavior: TextHeightBehavior?
    public let selectionRegistrar: SelectionRegistrar?
    public let selectionColor: Color?

    public init(
        key: (any Key)? = nil,
        text: InlineSpan,
        textAlign: TextAlign = .start,
        textDirection: TextDirection? = nil,
        softWrap: Bool = true,
        overflow: TextOverflow = .clip,
        textScaler: (any TextScaler)? = nil,
        maxLines: Int? = nil,
        locale: Locale? = nil,
        strutStyle: StrutStyle? = nil,
        textWidthBasis: TextWidthBasis = .parent,
        textHeightBehavior: TextHeightBehavior? = nil,
        selectionRegistrar: SelectionRegistrar? = nil,
        selectionColor: Color? = nil,
        children: [Widget] = []
    ) {
        assert(maxLines == nil || maxLines! > 0)
        self.text = text
        self.textAlign = textAlign
        self.textDirection = textDirection
        self.softWrap = softWrap
        self.overflow = overflow
        self.textScaler = textScaler ?? TextScalers.noScaling
        self.maxLines = maxLines
        self.locale = locale
        self.strutStyle = strutStyle
        self.textWidthBasis = textWidthBasis
        self.textHeightBehavior = textHeightBehavior
        self.selectionRegistrar = selectionRegistrar
        self.selectionColor = selectionColor
        super.init(key: key, children: children)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderParagraph(
            text: text,
            textAlign: textAlign,
            textDirection: textDirection ?? Directionality.maybeOf(context) ?? .ltr,
            softWrap: softWrap,
            overflow: overflow,
            textScaler: textScaler,
            maxLines: maxLines,
            locale: locale,
            strutStyle: strutStyle,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior,
            selectionColor: selectionColor,
            registrar: selectionRegistrar
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderParagraph
        ro.text = text
        ro.textAlign = textAlign
        ro.textDirection = textDirection ?? Directionality.maybeOf(context) ?? .ltr
        ro.softWrap = softWrap
        ro.overflow = overflow
        ro.textScaler = textScaler
        ro.maxLines = maxLines
        ro.strutStyle = strutStyle
        ro.textWidthBasis = textWidthBasis
        ro.textHeightBehavior = textHeightBehavior
        ro.locale = locale
        ro.registrar = selectionRegistrar
        ro.selectionColor = selectionColor
    }
}

// MARK: - RepaintBoundary

/// A widget that creates a separate display list for its child.
///
/// **Dart Source:** `basic.dart:7564`
public class RepaintBoundary: SingleChildRenderObjectWidget {
    public override init(
        key: (any Key)? = nil,
        child: Widget? = nil
    ) {
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderRepaintBoundary()
    }
}

// MARK: - Listener

/// A widget that calls callbacks in response to common pointer events.
///
/// **Dart Source:** `basic.dart:7166`
public class Listener: SingleChildRenderObjectWidget {
    public let onPointerDown: PointerDownEventListener?
    public let onPointerMove: PointerMoveEventListener?
    public let onPointerUp: PointerUpEventListener?
    public let onPointerHover: PointerHoverEventListener?
    public let onPointerCancel: PointerCancelEventListener?
    public let onPointerPanZoomStart: PointerPanZoomStartEventListener?
    public let onPointerPanZoomUpdate: PointerPanZoomUpdateEventListener?
    public let onPointerPanZoomEnd: PointerPanZoomEndEventListener?
    public let onPointerSignal: PointerSignalEventListener?
    public let behavior: HitTestBehavior

    public init(
        key: (any Key)? = nil,
        onPointerDown: PointerDownEventListener? = nil,
        onPointerMove: PointerMoveEventListener? = nil,
        onPointerUp: PointerUpEventListener? = nil,
        onPointerHover: PointerHoverEventListener? = nil,
        onPointerCancel: PointerCancelEventListener? = nil,
        onPointerPanZoomStart: PointerPanZoomStartEventListener? = nil,
        onPointerPanZoomUpdate: PointerPanZoomUpdateEventListener? = nil,
        onPointerPanZoomEnd: PointerPanZoomEndEventListener? = nil,
        onPointerSignal: PointerSignalEventListener? = nil,
        behavior: HitTestBehavior = .deferToChild,
        child: Widget? = nil
    ) {
        self.onPointerDown = onPointerDown
        self.onPointerMove = onPointerMove
        self.onPointerUp = onPointerUp
        self.onPointerHover = onPointerHover
        self.onPointerCancel = onPointerCancel
        self.onPointerPanZoomStart = onPointerPanZoomStart
        self.onPointerPanZoomUpdate = onPointerPanZoomUpdate
        self.onPointerPanZoomEnd = onPointerPanZoomEnd
        self.onPointerSignal = onPointerSignal
        self.behavior = behavior
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderPointerListener(
            onPointerDown: onPointerDown,
            onPointerMove: onPointerMove,
            onPointerUp: onPointerUp,
            onPointerHover: onPointerHover,
            onPointerCancel: onPointerCancel,
            onPointerPanZoomStart: onPointerPanZoomStart,
            onPointerPanZoomUpdate: onPointerPanZoomUpdate,
            onPointerPanZoomEnd: onPointerPanZoomEnd,
            onPointerSignal: onPointerSignal,
            behavior: behavior
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderPointerListener
        ro.onPointerDown = onPointerDown
        ro.onPointerMove = onPointerMove
        ro.onPointerUp = onPointerUp
        ro.onPointerHover = onPointerHover
        ro.onPointerCancel = onPointerCancel
        ro.onPointerPanZoomStart = onPointerPanZoomStart
        ro.onPointerPanZoomUpdate = onPointerPanZoomUpdate
        ro.onPointerPanZoomEnd = onPointerPanZoomEnd
        ro.onPointerSignal = onPointerSignal
        ro.behavior = behavior
    }
}

// MARK: - MouseRegion

/// A widget that tracks the mouse being above it.
///
/// **Dart Source:** `basic.dart:7308`
public class MouseRegion: SingleChildRenderObjectWidget {
    public let onEnter: PointerEnterEventListener?
    public let onHover: PointerHoverEventListener?
    public let onExit: PointerExitEventListener?
    public let cursor: MouseCursor
    public let opaque: Bool
    public let hitTestBehavior: HitTestBehavior?

    public init(
        key: (any Key)? = nil,
        onEnter: PointerEnterEventListener? = nil,
        onHover: PointerHoverEventListener? = nil,
        onExit: PointerExitEventListener? = nil,
        cursor: MouseCursor = MouseCursor.defer_,
        opaque: Bool = true,
        hitTestBehavior: HitTestBehavior? = nil,
        child: Widget? = nil
    ) {
        self.onEnter = onEnter
        self.onHover = onHover
        self.onExit = onExit
        self.cursor = cursor
        self.opaque = opaque
        self.hitTestBehavior = hitTestBehavior
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderMouseRegion(
            onEnter: onEnter,
            onHover: onHover,
            onExit: onExit,
            cursor: cursor,
            opaque: opaque,
            hitTestBehavior: hitTestBehavior ?? .opaque
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderMouseRegion
        ro.onEnter = onEnter
        ro.onHover = onHover
        ro.onExit = onExit
        ro.cursor = cursor
        ro.opaque = opaque
    }
}

// MARK: - IgnorePointer

/// A widget that is invisible to hit testing.
///
/// **Dart Source:** `basic.dart:7643`
public class IgnorePointer: SingleChildRenderObjectWidget {
    public let ignoring: Bool

    public init(
        key: (any Key)? = nil,
        ignoring: Bool = true,
        child: Widget? = nil
    ) {
        self.ignoring = ignoring
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderIgnorePointer(ignoring: ignoring)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderIgnorePointer
        ro.ignoring = ignoring
    }
}

// MARK: - AbsorbPointer

/// A widget that absorbs pointers during hit testing.
///
/// **Dart Source:** `basic.dart:7756`
public class AbsorbPointer: SingleChildRenderObjectWidget {
    public let absorbing: Bool

    public init(
        key: (any Key)? = nil,
        absorbing: Bool = true,
        child: Widget? = nil
    ) {
        self.absorbing = absorbing
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderAbsorbPointer(absorbing: absorbing)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderAbsorbPointer
        ro.absorbing = absorbing
    }
}

// MARK: - ColoredBox

/// A widget that paints its area with a specified Color.
///
/// Uses RenderDecoratedBox with a BoxDecoration internally.
///
/// **Dart Source:** `basic.dart:8393`
public class ColoredBox: SingleChildRenderObjectWidget {
    public let color: Color

    public init(
        key: (any Key)? = nil,
        color: Color,
        child: Widget? = nil
    ) {
        self.color = color
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderDecoratedBox(decoration: BoxDecoration(color: color))
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderDecoratedBox
        ro.decoration = BoxDecoration(color: color)
    }
}

// MARK: - CompositedTransformTarget

/// A widget that can be targeted by a [CompositedTransformFollower].
///
/// When this widget is composited during the compositing phase, it provides
/// a [LayerLink] that can be used by [CompositedTransformFollower] to follow
/// the position of this widget.
///
/// A single [CompositedTransformTarget] can be followed by multiple
/// [CompositedTransformFollower] widgets.
///
/// The [CompositedTransformTarget] must come earlier in the paint order than
/// any linked [CompositedTransformFollower]s.
///
/// **Dart Source:** `basic.dart:1881`
public class CompositedTransformTarget: SingleChildRenderObjectWidget {
    /// The link object that connects this [CompositedTransformTarget] with one
    /// or more [CompositedTransformFollower]s.
    public let link: LayerLink

    public init(
        key: (any Key)? = nil,
        link: LayerLink,
        child: Widget? = nil
    ) {
        self.link = link
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderLeaderLayer(link: link)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderLeaderLayer
        ro.link = link
    }
}

// MARK: - CompositedTransformFollower

/// A widget that follows a [CompositedTransformTarget].
///
/// When this widget is composited during the compositing phase, it applies a
/// transformation that brings [targetAnchor] of the linked
/// [CompositedTransformTarget] and [followerAnchor] of this widget together.
/// The two anchor points will have the same global coordinates, unless [offset]
/// is not [Offset.zero], in which case [followerAnchor] will be offset by
/// [offset] in the linked [CompositedTransformTarget]'s coordinate space.
///
/// The [LayerLink] object used as the [link] must be the same object as that
/// provided to the matching [CompositedTransformTarget].
///
/// **Dart Source:** `basic.dart:1933`
public class CompositedTransformFollower: SingleChildRenderObjectWidget {
    /// The link object that connects this [CompositedTransformFollower] with a
    /// [CompositedTransformTarget].
    public let link: LayerLink

    /// Whether to show the widget's contents when there is no corresponding
    /// [CompositedTransformTarget] with the same [link].
    public let showWhenUnlinked: Bool

    /// The anchor point on the linked [CompositedTransformTarget] that
    /// [followerAnchor] will line up with.
    ///
    /// Defaults to [Alignment.topLeft].
    public let targetAnchor: Alignment

    /// The anchor point on this widget that will line up with [targetAnchor] on
    /// the linked [CompositedTransformTarget].
    ///
    /// Defaults to [Alignment.topLeft].
    public let followerAnchor: Alignment

    /// The additional offset to apply to the [targetAnchor] of the linked
    /// [CompositedTransformTarget] to obtain this widget's [followerAnchor]
    /// position.
    public let offset: Offset

    public init(
        key: (any Key)? = nil,
        link: LayerLink,
        showWhenUnlinked: Bool = true,
        offset: Offset = .zero,
        targetAnchor: Alignment = .topLeft,
        followerAnchor: Alignment = .topLeft,
        child: Widget? = nil
    ) {
        self.link = link
        self.showWhenUnlinked = showWhenUnlinked
        self.offset = offset
        self.targetAnchor = targetAnchor
        self.followerAnchor = followerAnchor
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderFollowerLayer(
            link: link,
            showWhenUnlinked: showWhenUnlinked,
            offset: offset,
            leaderAnchor: targetAnchor,
            followerAnchor: followerAnchor
        )
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderFollowerLayer
        ro.link = link
        ro.showWhenUnlinked = showWhenUnlinked
        ro.offset = offset
        ro.leaderAnchor = targetAnchor
        ro.followerAnchor = followerAnchor
    }
}
