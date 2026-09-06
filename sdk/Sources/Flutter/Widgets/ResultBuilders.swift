// ResultBuilders.swift
//
// Trailing-closure syntax for widget composition.
//
// DIFFERENCE FROM DART: This file has no Dart counterpart. It is a Swift-only
// ergonomic overlay.
// REASON: A Swift array literal is an expression, so `if`/`for` cannot appear
// inside one. Dart has collection-if and collection-for, which lets upstream
// write conditional children directly inside the list literal; without an
// equivalent, ported call sites have to build `var children: [Widget] = []`
// imperatively above the tree, or stand a `SizedBox()` in for "no child".
// A `@resultBuilder` restores that capability using Swift's own mechanism.
//
// Nothing here replaces anything. Every ported initializer keeps its
// `children: [Widget]` / `child: Widget` form, and those remain the canonical
// 1:1 mapping to Dart — these are additional overloads that delegate straight
// to them. Both spellings compile to the identical widget tree:
//
//     Column(crossAxisAlignment: .start, children: [   Column(crossAxisAlignment: .start) {
//         Text("Discover"),                                Text("Discover")
//         SizedBox(height: 16),               ==>          SizedBox(height: 16)
//         _featuredCard(featured),                         _featuredCard(featured)
//     ])                                               }
//
// The builder is compile-time only: it produces the same `[Widget]` the array
// literal would, so element reconciliation (`Widget.canUpdate` plus the
// `updateChildren` diff) cannot observe which spelling was used.

import FlutterSwiftBridge

// MARK: - Builders

/// Assembles the child list of a multi-child widget from a statement block.
///
/// Supports `if`, `if`/`else`, `switch`, `for`, and `if #available`. A branch
/// that contributes nothing yields no child at all, rather than a placeholder:
///
///     Column {
///         Text("Volume")
///         if isMuted { MutedBadge() }        // contributes 0 or 1 children
///         for name in devices { DeviceRow(name) }
///     }
///
/// A bare `[Widget]` splices in place, so existing helpers that return arrays
/// can be dropped into a block unchanged.
@resultBuilder
public enum ChildrenBuilder {
    public static func buildExpression(_ widget: Widget) -> [Widget] { [widget] }

    public static func buildExpression(_ widget: Widget?) -> [Widget] {
        guard let widget else { return [] }
        return [widget]
    }

    public static func buildExpression(_ widgets: [Widget]) -> [Widget] { widgets }

    public static func buildBlock(_ components: [Widget]...) -> [Widget] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [Widget]?) -> [Widget] {
        component ?? []
    }

    public static func buildEither(first component: [Widget]) -> [Widget] { component }

    public static func buildEither(second component: [Widget]) -> [Widget] { component }

    public static func buildArray(_ components: [[Widget]]) -> [Widget] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [Widget]) -> [Widget] {
        component
    }
}

/// Assembles the single child of a single-child widget from a statement block.
///
/// Deliberately narrower than `ChildrenBuilder`: it provides `buildEither` but
/// *not* `buildOptional` or `buildArray`, so `if`/`else` and `switch` are
/// available while a bare `if` or a `for` is a compile error. That is the
/// correct constraint — these initializers take exactly one child, and a block
/// that might produce zero of them has no meaning. To omit the child entirely,
/// use the ported initializer and pass nothing: `Center()`.
@resultBuilder
public enum ChildBuilder {
    public static func buildBlock(_ component: Widget) -> Widget { component }

    public static func buildEither(first component: Widget) -> Widget { component }

    public static func buildEither(second component: Widget) -> Widget { component }

    public static func buildLimitedAvailability(_ component: Widget) -> Widget { component }
}

// MARK: - Multi-child layout

extension Flex {
    public convenience init(
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
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(
            key: key,
            direction: direction,
            mainAxisAlignment: mainAxisAlignment,
            mainAxisSize: mainAxisSize,
            crossAxisAlignment: crossAxisAlignment,
            textDirection: textDirection,
            verticalDirection: verticalDirection,
            textBaseline: textBaseline,
            clipBehavior: clipBehavior,
            spacing: spacing,
            children: children()
        )
    }
}

extension Row {
    public convenience init(
        key: (any Key)? = nil,
        mainAxisAlignment: MainAxisAlignment = .start,
        mainAxisSize: MainAxisSize = .max,
        crossAxisAlignment: CrossAxisAlignment = .center,
        textDirection: TextDirection? = nil,
        verticalDirection: VerticalDirection = .down,
        textBaseline: TextBaseline? = nil,
        spacing: Double = 0.0,
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(
            key: key,
            mainAxisAlignment: mainAxisAlignment,
            mainAxisSize: mainAxisSize,
            crossAxisAlignment: crossAxisAlignment,
            textDirection: textDirection,
            verticalDirection: verticalDirection,
            textBaseline: textBaseline,
            spacing: spacing,
            children: children()
        )
    }
}

extension Column {
    public convenience init(
        key: (any Key)? = nil,
        mainAxisAlignment: MainAxisAlignment = .start,
        mainAxisSize: MainAxisSize = .max,
        crossAxisAlignment: CrossAxisAlignment = .center,
        textDirection: TextDirection? = nil,
        verticalDirection: VerticalDirection = .down,
        textBaseline: TextBaseline? = nil,
        spacing: Double = 0.0,
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(
            key: key,
            mainAxisAlignment: mainAxisAlignment,
            mainAxisSize: mainAxisSize,
            crossAxisAlignment: crossAxisAlignment,
            textDirection: textDirection,
            verticalDirection: verticalDirection,
            textBaseline: textBaseline,
            spacing: spacing,
            children: children()
        )
    }
}

extension Stack {
    public convenience init(
        key: (any Key)? = nil,
        alignment: any AlignmentGeometry = AlignmentDirectional.topStart,
        textDirection: TextDirection? = nil,
        fit: StackFit = .loose,
        clipBehavior: Clip = .hardEdge,
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(
            key: key,
            alignment: alignment,
            textDirection: textDirection,
            fit: fit,
            clipBehavior: clipBehavior,
            children: children()
        )
    }
}

extension IndexedStack {
    public convenience init(
        key: (any Key)? = nil,
        alignment: any AlignmentGeometry = AlignmentDirectional.topStart,
        textDirection: TextDirection? = nil,
        clipBehavior: Clip = .hardEdge,
        sizing: StackFit = .loose,
        index: Int? = 0,
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(
            key: key,
            alignment: alignment,
            textDirection: textDirection,
            clipBehavior: clipBehavior,
            sizing: sizing,
            index: index,
            children: children()
        )
    }
}

extension Wrap {
    public convenience init(
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
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(
            key: key,
            direction: direction,
            alignment: alignment,
            spacing: spacing,
            runAlignment: runAlignment,
            runSpacing: runSpacing,
            crossAxisAlignment: crossAxisAlignment,
            textDirection: textDirection,
            verticalDirection: verticalDirection,
            clipBehavior: clipBehavior,
            children: children()
        )
    }
}

extension ListBody {
    public convenience init(
        key: (any Key)? = nil,
        mainAxis: Axis = .vertical,
        reverse: Bool = false,
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(key: key, mainAxis: mainAxis, reverse: reverse, children: children())
    }
}

// MARK: - Scrolling

extension ListView {
    public convenience init(
        key: (any Key)? = nil,
        scrollDirection: Axis = .vertical,
        reverse: Bool = false,
        controller: ScrollController? = nil,
        physics: ScrollPhysics? = nil,
        shrinkWrap: Bool = false,
        padding: (any EdgeInsetsGeometry)? = nil,
        itemExtent: Double? = nil,
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(
            key: key,
            scrollDirection: scrollDirection,
            reverse: reverse,
            controller: controller,
            physics: physics,
            shrinkWrap: shrinkWrap,
            padding: padding,
            itemExtent: itemExtent,
            children: children()
        )
    }
}

extension GridView {
    public convenience init(
        key: (any Key)? = nil,
        scrollDirection: Axis = .vertical,
        reverse: Bool = false,
        controller: ScrollController? = nil,
        physics: ScrollPhysics? = nil,
        shrinkWrap: Bool = false,
        padding: (any EdgeInsetsGeometry)? = nil,
        gridDelegate: SliverGridDelegate,
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(
            key: key,
            scrollDirection: scrollDirection,
            reverse: reverse,
            controller: controller,
            physics: physics,
            shrinkWrap: shrinkWrap,
            padding: padding,
            gridDelegate: gridDelegate,
            children: children()
        )
    }
}

extension SliverList {
    public convenience init(
        key: (any Key)? = nil,
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(key: key, children: children())
    }
}

extension SliverFixedExtentList {
    public convenience init(
        key: (any Key)? = nil,
        itemExtent: Double,
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(key: key, children: children(), itemExtent: itemExtent)
    }
}

extension SliverGrid {
    public convenience init(
        key: (any Key)? = nil,
        crossAxisCount: Int,
        mainAxisSpacing: Double = 0.0,
        crossAxisSpacing: Double = 0.0,
        childAspectRatio: Double = 1.0,
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(
            key: key,
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: crossAxisSpacing,
            childAspectRatio: childAspectRatio,
            children: children()
        )
    }
}

// MARK: - Single child: layout

extension Padding {
    public convenience init(
        key: (any Key)? = nil,
        padding: any EdgeInsetsGeometry,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, padding: padding, child: child())
    }
}

extension Align {
    public convenience init(
        key: (any Key)? = nil,
        alignment: any AlignmentGeometry = Alignment.center,
        widthFactor: Double? = nil,
        heightFactor: Double? = nil,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(
            key: key,
            alignment: alignment,
            widthFactor: widthFactor,
            heightFactor: heightFactor,
            child: child()
        )
    }
}

extension Center {
    public convenience init(
        key: (any Key)? = nil,
        widthFactor: Double? = nil,
        heightFactor: Double? = nil,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, widthFactor: widthFactor, heightFactor: heightFactor, child: child())
    }
}

extension SizedBox {
    public convenience init(
        key: (any Key)? = nil,
        width: Double? = nil,
        height: Double? = nil,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, width: width, height: height, child: child())
    }
}

extension ConstrainedBox {
    public convenience init(
        key: (any Key)? = nil,
        constraints: BoxConstraints,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, constraints: constraints, child: child())
    }
}

extension LimitedBox {
    public convenience init(
        key: (any Key)? = nil,
        maxWidth: Double = .infinity,
        maxHeight: Double = .infinity,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, maxWidth: maxWidth, maxHeight: maxHeight, child: child())
    }
}

extension FractionallySizedBox {
    public convenience init(
        key: (any Key)? = nil,
        alignment: any AlignmentGeometry = Alignment.center,
        widthFactor: Double? = nil,
        heightFactor: Double? = nil,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(
            key: key,
            alignment: alignment,
            widthFactor: widthFactor,
            heightFactor: heightFactor,
            child: child()
        )
    }
}

extension AspectRatio {
    public convenience init(
        key: (any Key)? = nil,
        aspectRatio: Double,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, aspectRatio: aspectRatio, child: child())
    }
}

extension FittedBox {
    public convenience init(
        key: (any Key)? = nil,
        fit: BoxFit = .contain,
        alignment: any AlignmentGeometry = Alignment.center,
        clipBehavior: Clip = .none,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(
            key: key,
            fit: fit,
            alignment: alignment,
            clipBehavior: clipBehavior,
            child: child()
        )
    }
}

extension IntrinsicWidth {
    public convenience init(
        key: (any Key)? = nil,
        stepWidth: Double? = nil,
        stepHeight: Double? = nil,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, stepWidth: stepWidth, stepHeight: stepHeight, child: child())
    }
}

extension IntrinsicHeight {
    public convenience init(
        key: (any Key)? = nil,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, child: child())
    }
}

extension RotatedBox {
    public convenience init(
        key: (any Key)? = nil,
        quarterTurns: Int,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, quarterTurns: quarterTurns, child: child())
    }
}

// MARK: - Single child: flex and stack participants

extension Expanded {
    public convenience init(
        key: (any Key)? = nil,
        flex: Int = 1,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, flex: flex, child: child())
    }
}

extension Flexible {
    public convenience init(
        key: (any Key)? = nil,
        flex: Int = 1,
        fit: FlexFit = .loose,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, flex: flex, fit: fit, child: child())
    }
}

extension Positioned {
    public convenience init(
        key: (any Key)? = nil,
        left: Double? = nil,
        top: Double? = nil,
        right: Double? = nil,
        bottom: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(
            key: key,
            left: left,
            top: top,
            right: right,
            bottom: bottom,
            width: width,
            height: height,
            child: child()
        )
    }
}

// MARK: - Single child: paint and hit-test wrappers

extension ColoredBox {
    public convenience init(
        key: (any Key)? = nil,
        color: Color,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, color: color, child: child())
    }
}

extension DecoratedBox {
    public convenience init(
        key: (any Key)? = nil,
        decoration: any Decoration,
        position: DecorationPosition = .background,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, decoration: decoration, position: position, child: child())
    }
}

extension Opacity {
    public convenience init(
        key: (any Key)? = nil,
        opacity: Double,
        alwaysIncludeSemantics: Bool = false,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(
            key: key,
            opacity: opacity,
            alwaysIncludeSemantics: alwaysIncludeSemantics,
            child: child()
        )
    }
}

extension ClipRect {
    public convenience init(
        key: (any Key)? = nil,
        clipper: CustomClipper<Rect>? = nil,
        clipBehavior: Clip = .hardEdge,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, clipper: clipper, clipBehavior: clipBehavior, child: child())
    }
}

extension ClipRRect {
    public convenience init(
        key: (any Key)? = nil,
        borderRadius: any BorderRadiusGeometry = BorderRadius.zero,
        clipper: CustomClipper<RRect>? = nil,
        clipBehavior: Clip = .antiAlias,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(
            key: key,
            borderRadius: borderRadius,
            clipper: clipper,
            clipBehavior: clipBehavior,
            child: child()
        )
    }
}

extension ClipOval {
    public convenience init(
        key: (any Key)? = nil,
        clipper: CustomClipper<Rect>? = nil,
        clipBehavior: Clip = .antiAlias,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, clipper: clipper, clipBehavior: clipBehavior, child: child())
    }
}

extension Offstage {
    public convenience init(
        key: (any Key)? = nil,
        offstage: Bool = true,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, offstage: offstage, child: child())
    }
}

extension IgnorePointer {
    public convenience init(
        key: (any Key)? = nil,
        ignoring: Bool = true,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, ignoring: ignoring, child: child())
    }
}

extension AbsorbPointer {
    public convenience init(
        key: (any Key)? = nil,
        absorbing: Bool = true,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, absorbing: absorbing, child: child())
    }
}

extension SingleChildScrollView {
    public convenience init(
        key: (any Key)? = nil,
        scrollDirection: Axis = .vertical,
        reverse: Bool = false,
        controller: ScrollController? = nil,
        physics: ScrollPhysics? = nil,
        padding: (any EdgeInsetsGeometry)? = nil,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(
            key: key,
            scrollDirection: scrollDirection,
            reverse: reverse,
            controller: controller,
            physics: physics,
            padding: padding,
            child: child()
        )
    }
}

// MARK: - Page scaffolds
//
// `children:` is not the trailing parameter on the ported entry points, so the
// builder overloads move it last. Everything else keeps its original name,
// order, and default.

extension ScaffoldPage {
    public static func scrollable(
        key: (any Key)? = nil,
        header: Widget? = nil,
        bottomBar: Widget? = nil,
        padding: EdgeInsets = EdgeInsets(left: 24, top: 0, right: 24, bottom: 24),
        @ChildrenBuilder children: () -> [Widget]
    ) -> ScaffoldPage {
        return scrollable(
            key: key,
            header: header,
            bottomBar: bottomBar,
            padding: padding,
            children: children()
        )
    }
}

extension MacosScaffold {
    public convenience init(
        key: (any Key)? = nil,
        toolBar: MacosToolBar? = nil,
        backgroundColor: Color? = nil,
        @ChildrenBuilder children: () -> [Widget]
    ) {
        self.init(
            key: key,
            children: children(),
            toolBar: toolBar,
            backgroundColor: backgroundColor
        )
    }
}

// MARK: - Fluent materials

extension Acrylic {
    public convenience init(
        key: (any Key)? = nil,
        recipe: FluentMaterialRecipe? = nil,
        tintColor: Color? = nil,
        tintOpacity: Double? = nil,
        luminosityOpacity: Double? = nil,
        blurAmount: Double? = nil,
        borderRadius: any BorderRadiusGeometry = BorderRadius.zero,
        enabled: Bool? = nil,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(
            key: key, child: child(), recipe: recipe, tintColor: tintColor,
            tintOpacity: tintOpacity, luminosityOpacity: luminosityOpacity,
            blurAmount: blurAmount, borderRadius: borderRadius, enabled: enabled)
    }
}

extension Mica {
    public convenience init(
        key: (any Key)? = nil,
        kind: MicaKind = .base,
        active: Bool = true,
        sample: Color? = nil,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, child: child(), kind: kind, active: active, sample: sample)
    }
}

extension Smoke {
    public convenience init(
        key: (any Key)? = nil,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, child: child())
    }
}
