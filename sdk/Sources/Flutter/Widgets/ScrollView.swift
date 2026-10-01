// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Scroll view widgets — `SingleChildScrollView`, `ListView`, `GridView`,
/// and supporting sliver widget infrastructure.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/scroll_view.dart`
/// **Dart Source:** `packages/flutter/lib/src/widgets/single_child_scroll_view.dart`
/// **Dart Source:** `packages/flutter/lib/src/widgets/sliver.dart` (SliverChildDelegate, SliverList, SliverGrid)

import FlutterSwiftBridge

// =============================================================================
// MARK: - SliverChildDelegate
// =============================================================================

/// A delegate that supplies children for slivers.
///
/// Many slivers lazily construct their box children to avoid creating more
/// children than are visible through the `Viewport`. Rather than receiving
/// their children as an explicit `List<Widget>`, they receive their children
/// using a `SliverChildDelegate`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/sliver.dart:62-161`
public protocol SliverChildDelegate: AnyObject {

    /// Returns the child with the given index.
    ///
    /// Should return nil if asked to build a widget with a greater index than
    /// exists. Returning nil indicates that the child count has been reached.
    ///
    /// **Dart Source:** `sliver.dart:85`
    func build(_ context: any BuildContext, index: Int) -> Widget?

    /// Returns an estimate of the number of children this delegate will build.
    ///
    /// **Dart Source:** `sliver.dart:100`
    var estimatedChildCount: Int? { get }
}

// MARK: - SliverChildListDelegate

/// A delegate that supplies children for slivers using an explicit list.
///
/// Many slivers lazily construct their box children to avoid creating more
/// children than are visible through the `Viewport`. This delegate provides
/// children using an explicit list, which is convenient and useful in cases
/// where all the children are already available.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/sliver.dart:359-417`
public class SliverChildListDelegate: SliverChildDelegate {

    /// The widgets in the child list.
    ///
    /// **Dart Source:** `sliver.dart:387`
    public let children: [Widget]

    /// Creates a delegate that supplies children for slivers using an explicit list.
    ///
    /// **Dart Source:** `sliver.dart:368`
    public init(
        _ children: [Widget]
    ) {
        self.children = children
    }

    /// **Dart Source:** `sliver.dart:392`
    public func build(_ context: any BuildContext, index: Int) -> Widget? {
        if index < 0 || index >= children.count {
            return nil
        }
        return children[index]
    }

    /// **Dart Source:** `sliver.dart:410`
    public var estimatedChildCount: Int? {
        children.count
    }
}

// MARK: - SliverChildBuilderDelegate

/// A delegate that supplies children for slivers using a builder callback.
///
/// Many slivers lazily construct their box children to avoid creating more
/// children than are visible through the `Viewport`. This delegate provides
/// children using a builder callback, which is appropriate for slivers that
/// build children on demand.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/sliver.dart:189-357`
public class SliverChildBuilderDelegate: SliverChildDelegate {

    /// The builder callback that creates a child widget for a given index.
    public let builder: (any BuildContext, Int) -> Widget?

    /// The total number of children this delegate can provide.
    ///
    /// If nil, the number of children is determined by the least
    /// index for which `builder` returns nil.
    public let childCount: Int?

    /// Creates a delegate that supplies children for slivers using a builder
    /// callback.
    ///
    /// **Dart Source:** `sliver.dart:208-222`
    public init(
        _ builder: @escaping (any BuildContext, Int) -> Widget?,
        childCount: Int? = nil
    ) {
        self.builder = builder
        self.childCount = childCount
    }

    /// **Dart Source:** `sliver.dart:297-319`
    public func build(_ context: any BuildContext, index: Int) -> Widget? {
        if let childCount = childCount, index >= childCount {
            return nil
        }
        return builder(context, index)
    }

    /// **Dart Source:** `sliver.dart:322`
    public var estimatedChildCount: Int? {
        childCount
    }
}

// =============================================================================
// MARK: - SliverMultiBoxAdaptorWidget
// =============================================================================

/// A base class for sliver widgets that have multiple box children.
///
/// Helps by defining the common property `delegate` for managing children.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/sliver.dart:820-845`
///
/// DIFFERENCE FROM DART: In Dart, this creates a `SliverMultiBoxAdaptorElement`
/// which implements `RenderSliverBoxChildManager`. This simplified version
/// creates a `_SliverMultiBoxAdaptorElement` that eagerly builds all children.
/// REASON: The full lazy child management system is complex; this provides
/// functional scrolling first.
public class SliverMultiBoxAdaptorWidget: RenderObjectWidget {
    /// The delegate that provides children for this widget.
    public let delegate: SliverChildDelegate

    /// Creates a sliver with a delegate to provide children.
    public init(key: (any Key)? = nil, delegate: SliverChildDelegate) {
        self.delegate = delegate
        super.init(key: key)
    }

    public override func createElement() -> Element {
        return _SliverMultiBoxAdaptorElement(self)
    }
}

// MARK: - SliverList Widget

/// A sliver that places multiple box children in a linear array along the main
/// axis.
///
/// Each child is forced to have the `SliverConstraints.crossAxisExtent` in the
/// cross axis but determines its own main axis extent.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/sliver.dart:1076-1130`
public class SliverList: SliverMultiBoxAdaptorWidget {

    /// Creates a sliver that places box children in a linear array.
    ///
    /// **Dart Source:** `sliver.dart:1079`
    public override init(key: (any Key)? = nil, delegate: SliverChildDelegate) {
        super.init(key: key, delegate: delegate)
    }

    /// Creates a `SliverList` with an explicit list of children.
    ///
    /// Convenience factory similar to `SliverList.list` in Flutter.
    ///
    /// **Dart Source:** `sliver.dart:1092` (SliverList.list)
    public convenience init(
        key: (any Key)? = nil,
        children: [Widget]
    ) {
        self.init(key: key, delegate: SliverChildListDelegate(children))
    }

    /// Creates a `SliverList` with a builder callback.
    ///
    /// Convenience factory similar to `SliverList.builder` in Flutter.
    ///
    /// **Dart Source:** `sliver.dart:1082` (SliverList.builder)
    public convenience init(
        key: (any Key)? = nil,
        itemCount: Int? = nil,
        itemBuilder: @escaping (any BuildContext, Int) -> Widget?
    ) {
        self.init(key: key, delegate: SliverChildBuilderDelegate(itemBuilder, childCount: itemCount))
    }

    /// **Dart Source:** `sliver.dart:1124-1126`
    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        let element = context as! _SliverMultiBoxAdaptorElement
        return RenderSliverList(childManager: element)
    }
}

// MARK: - SliverFixedExtentList Widget

/// A sliver that places multiple box children with the same main axis extent in
/// a linear array.
///
/// `SliverFixedExtentList` places its children in a linear array along the main
/// axis starting at offset zero and without gaps. Each child is forced to have
/// the `itemExtent` in the main axis and the
/// `SliverConstraints.crossAxisExtent` in the cross axis.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/sliver.dart:1143-1212`
public class SliverFixedExtentList: SliverMultiBoxAdaptorWidget {

    /// The extent the children are forced to have in the main axis.
    public let itemExtent: Double

    /// Creates a sliver that places box children with the same main axis extent
    /// in a linear array.
    ///
    /// **Dart Source:** `sliver.dart:1148`
    public init(
        key: (any Key)? = nil,
        delegate: SliverChildDelegate,
        itemExtent: Double
    ) {
        self.itemExtent = itemExtent
        super.init(key: key, delegate: delegate)
    }

    /// Creates a `SliverFixedExtentList` with an explicit list of children.
    ///
    /// **Dart Source:** `sliver.dart:1164` (SliverFixedExtentList.list)
    public convenience init(
        key: (any Key)? = nil,
        children: [Widget],
        itemExtent: Double
    ) {
        self.init(key: key, delegate: SliverChildListDelegate(children), itemExtent: itemExtent)
    }

    /// **Dart Source:** `sliver.dart:1204-1207`
    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        let element = context as! _SliverMultiBoxAdaptorElement
        return RenderSliverFixedExtentList(childManager: element, itemExtent: itemExtent)
    }

    /// **Dart Source:** `sliver.dart:1210-1213`
    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderSliverFixedExtentList
        ro.setItemExtent(itemExtent)
    }
}

// MARK: - SliverGrid Widget

/// A sliver that places multiple box children in a two dimensional arrangement.
///
/// `SliverGrid` places its children in arbitrary positions determined by
/// `gridDelegate`. Each child is forced to have the size specified by the
/// `gridDelegate`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/sliver.dart:1226-1327`
public class SliverGrid: SliverMultiBoxAdaptorWidget {

    /// The delegate that controls the size and position of the children.
    public let gridDelegate: SliverGridDelegate

    /// Creates a sliver that places multiple box children in a two dimensional
    /// arrangement.
    ///
    /// **Dart Source:** `sliver.dart:1231`
    public init(
        key: (any Key)? = nil,
        delegate: SliverChildDelegate,
        gridDelegate: SliverGridDelegate
    ) {
        self.gridDelegate = gridDelegate
        super.init(key: key, delegate: delegate)
    }

    /// Creates a `SliverGrid` with an explicit list of children and a fixed
    /// cross-axis count.
    ///
    /// **Dart Source:** `sliver.dart:1267` (SliverGrid.count)
    public convenience init(
        key: (any Key)? = nil,
        crossAxisCount: Int,
        mainAxisSpacing: Double = 0.0,
        crossAxisSpacing: Double = 0.0,
        childAspectRatio: Double = 1.0,
        children: [Widget]
    ) {
        self.init(
            key: key,
            delegate: SliverChildListDelegate(children),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: mainAxisSpacing,
                crossAxisSpacing: crossAxisSpacing,
                childAspectRatio: childAspectRatio
            )
        )
    }

    /// **Dart Source:** `sliver.dart:1316-1319`
    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        let element = context as! _SliverMultiBoxAdaptorElement
        return RenderSliverGrid(childManager: element, gridDelegate: gridDelegate)
    }

    /// **Dart Source:** `sliver.dart:1322-1327`
    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderSliverGrid
        ro.gridDelegate = gridDelegate
    }
}

// =============================================================================
// MARK: - _SliverMultiBoxAdaptorElement
// =============================================================================

/// Element for `SliverMultiBoxAdaptorWidget` that implements
/// `RenderSliverBoxChildManager`.
///
/// This element manages the creation and destruction of child render objects
/// for slivers that have multiple box children. The render object calls back
/// into this element during layout via the `RenderSliverBoxChildManager`
/// protocol to create, remove, and count children.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/sliver.dart:846-1073`
///
/// DIFFERENCE FROM DART: Simplified. The full Dart implementation has complex
/// lifecycle management, keep-alive handling, and more nuanced child management.
/// This version provides the essential createChild/removeChild callbacks that
/// the render sliver needs during layout.
/// REASON: Focus on getting functional sliver widgets working.
class _SliverMultiBoxAdaptorElement: RenderObjectElement, RenderSliverBoxChildManager {

    /// The widget providing the delegate.
    private var adaptorWidget: SliverMultiBoxAdaptorWidget {
        widget as! SliverMultiBoxAdaptorWidget
    }

    /// Map from child index to its element.
    private var _childElements: [Int: Element] = [:]

    /// Whether layout reported an underflow.
    private var _didUnderflow: Bool = false

    /// The index of the child currently being inflated or updated — Dart's
    /// `_currentlyUpdatingChildIndex`. `didAdoptChild` stamps it into the
    /// adopted child's parentData, which must happen *inside* the sliver's
    /// `insert()` (its child-order verification runs `indexOf` on every
    /// child, and asserts on a nil index) — stamping after `insert()`
    /// returns is too late for debug builds.
    private var _currentlyUpdatingChildIndex: Int? = nil

    // MARK: - Lifecycle

    override func mount(_ parent: Element?, _ newSlot: Any?) {
        super.mount(parent, newSlot)
        // Children are created lazily by createChild() during layout.
    }

    override func update(_ newWidget: Widget) {
        let oldWidget = widget as! SliverMultiBoxAdaptorWidget
        super.update(newWidget)
        let newAdaptorWidget = newWidget as! SliverMultiBoxAdaptorWidget
        if oldWidget.delegate !== newAdaptorWidget.delegate {
            // Rebuild the children that are already inflated with the new
            // delegate's widgets — a rebuilt list (setState) reaches its rows
            // through here. Rows keep their index, so the update is in place
            // and the render objects stay where the sliver put them. An index
            // the new delegate no longer provides (the list shrank) must be
            // dropped explicitly: this element's removeRenderObjectChild is
            // a no-op, so nothing else detaches the render object.
            for index in _childElements.keys.sorted() {
                guard let oldElement = _childElements[index] else { continue }
                if let newChildWidget = newAdaptorWidget.delegate.build(self, index: index) {
                    _currentlyUpdatingChildIndex = index
                    defer { _currentlyUpdatingChildIndex = nil }
                    _childElements[index] = updateChild(
                        oldElement, newWidget: newChildWidget, newSlot: index)
                } else {
                    if let ro = oldElement.findRenderObject() as? RenderBox,
                       let sliver = renderObject as? RenderSliverMultiBoxAdaptor,
                       ro.parent != nil {
                        sliver.remove(ro)
                    }
                    _childElements.removeValue(forKey: index)
                    deactivateChild(oldElement)
                }
            }
            // Force re-layout which will re-create children
            (renderObject as? RenderSliverMultiBoxAdaptor)?.markNeedsLayout()
        }
    }

    // MARK: - Render Object Child Management

    override func insertRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        // Children are inserted by createChild, not by the element lifecycle.
    }

    override func moveRenderObjectChild(_ child: RenderObject, _ oldSlot: Any?, _ newSlot: Any?) {
        // Not needed for this simplified version.
    }

    override func removeRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        // Children are removed by removeChild, not by the element lifecycle.
    }

    // MARK: - RenderSliverBoxChildManager

    /// Called during layout when a new child is needed at the given index.
    ///
    /// Builds the widget from the delegate, inflates it, and inserts the
    /// resulting render object into the sliver's child list.
    ///
    /// **Dart Source:** `sliver.dart:909-957`
    func createChild(_ index: Int, after: RenderBox?) {
        guard let childWidget = adaptorWidget.delegate.build(self, index: index) else {
            return
        }

        // If we already have an element for this index, skip.
        if _childElements[index] != nil {
            return
        }

        // Inflate the widget to create an element and render object.
        _currentlyUpdatingChildIndex = index
        defer { _currentlyUpdatingChildIndex = nil }
        let childElement = inflateWidget(childWidget, index)
        _childElements[index] = childElement

        // Get the child's render object and insert it into the sliver. The
        // built widget is usually a component (ListTile, GestureDetector…),
        // so descend to the first render object rather than assuming the
        // element itself is a RenderObjectElement.
        if let childRO = childElement.findRenderObject() as? RenderBox {
            let renderSliver = renderObject as! RenderSliverMultiBoxAdaptor
            if childRO.parent == nil {
                // didAdoptChild stamps the index during this insert.
                renderSliver.insert(childRO, after: after)
            }
            // Also stamp directly for the already-attached path, where
            // insert() — and with it didAdoptChild — does not run.
            let parentData = childRO.parentData as? SliverMultiBoxAdaptorParentData
            parentData?.index = index
        }
    }

    /// Called by the render sliver to remove a child.
    ///
    /// **Dart Source:** `sliver.dart:959-977`
    func removeChild(_ child: RenderBox) {
        var foundIndex: Int?
        for (index, element) in _childElements {
            // Descend to the render object — children are usually component
            // widgets, not RenderObjectElements themselves.
            if element.findRenderObject() === child {
                foundIndex = index
                break
            }
        }
        if let index = foundIndex {
            if let element = _childElements.removeValue(forKey: index) {
                // Remove from render tree
                let renderSliver = renderObject as? RenderSliverMultiBoxAdaptor
                if child.parent != nil {
                    renderSliver?.remove(child)
                }
                deactivateChild(element)
            }
        }
    }

    /// Estimates the maximum scroll offset.
    ///
    /// **Dart Source:** `sliver.dart:979-1005`
    func estimateMaxScrollOffset(
        _ constraints: SliverConstraints,
        firstIndex: Int?,
        lastIndex: Int?,
        leadingScrollOffset: Double?,
        trailingScrollOffset: Double?
    ) -> Double {
        guard let firstIndex = firstIndex, let lastIndex = lastIndex,
              let leading = leadingScrollOffset, let trailing = trailingScrollOffset else {
            return 0.0
        }
        let totalChildCount = self.childCount
        if totalChildCount == 0 { return 0.0 }
        let visibleCount = lastIndex - firstIndex + 1
        if visibleCount <= 0 { return trailing }
        let averageExtent = (trailing - leading) / Double(visibleCount)
        return averageExtent * Double(totalChildCount)
    }

    /// The total number of children.
    ///
    /// **Dart Source:** `sliver.dart:1007`
    var childCount: Int {
        return adaptorWidget.delegate.estimatedChildCount ?? 0
    }

    /// The estimated number of children.
    var estimatedChildCount: Int? {
        return adaptorWidget.delegate.estimatedChildCount
    }

    /// Called when a child is adopted by the render object, from inside its
    /// `insert()`. Stamps the index onto the child's parentData right away —
    /// the sliver verifies child order (via `indexOf`, which asserts on a
    /// nil index) before `insert()` returns, so waiting for `createChild`
    /// to stamp it afterwards crashes debug builds.
    ///
    /// **Dart Source:** `sliver.dart:1027`
    func didAdoptChild(_ child: RenderBox) {
        guard let index = _currentlyUpdatingChildIndex else { return }
        let childParentData = child.parentData as? SliverMultiBoxAdaptorParentData
        childParentData?.index = index
    }

    /// Called to indicate whether the render object reported an underflow.
    func setDidUnderflow(_ value: Bool) {
        _didUnderflow = value
    }

    /// Called at the beginning of layout.
    func didStartLayout() {
        // No-op in simplified implementation.
    }

    /// Called at the end of layout.
    func didFinishLayout() {
        // No-op in simplified implementation.
    }

    // MARK: - Visiting

    override func visitChildElements(_ visitor: (Element) -> Void) {
        for index in _childElements.keys.sorted() {
            if let element = _childElements[index] {
                visitor(element)
            }
        }
    }

    override func forgetChild(_ child: Element) {
        var foundIndex: Int?
        for (index, element) in _childElements {
            if element === child {
                foundIndex = index
                break
            }
        }
        if let index = foundIndex {
            _childElements.removeValue(forKey: index)
        }
        super.forgetChild(child)
    }
}

// =============================================================================
// MARK: - SingleChildScrollView
// =============================================================================

/// A box in which a single widget can be scrolled.
///
/// This widget is useful when you have a single box that will normally be
/// entirely visible, for example a clock face in a time picker, but you need to
/// make sure it can be scrolled if the container gets too small in one axis
/// (the scroll direction).
///
/// It is also useful if you need to shrink-wrap in both axes (the main
/// scrolling direction as well as the cross axis), as one might see in a dialog
/// or popup menu. In that case, consider using a `SingleChildScrollView` with a
/// `ListBody` child.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/single_child_scroll_view.dart:80-157`
public class SingleChildScrollView: StatelessWidget {

    /// The axis along which the scroll view scrolls.
    ///
    /// **Dart Source:** `single_child_scroll_view.dart:111`
    public let scrollDirection: Axis

    /// Whether the scroll view scrolls in the reading direction.
    ///
    /// **Dart Source:** `single_child_scroll_view.dart:113`
    public let reverse: Bool

    /// An object that can be used to control the position to which this scroll
    /// view is scrolled.
    ///
    /// **Dart Source:** `single_child_scroll_view.dart:116`
    public let controller: ScrollController?

    /// How the scroll view should respond to user input.
    ///
    /// **Dart Source:** `single_child_scroll_view.dart:121`
    public let physics: ScrollPhysics?

    /// The amount of space by which to inset the child.
    ///
    /// **Dart Source:** `single_child_scroll_view.dart:124`
    public let padding: (any EdgeInsetsGeometry)?

    /// The widget that scrolls.
    ///
    /// **Dart Source:** `single_child_scroll_view.dart:132`
    public let child: Widget?

    /// Creates a box in which a single widget can be scrolled.
    ///
    /// **Dart Source:** `single_child_scroll_view.dart:82-102`
    public init(
        key: (any Key)? = nil,
        scrollDirection: Axis = .vertical,
        reverse: Bool = false,
        controller: ScrollController? = nil,
        physics: ScrollPhysics? = nil,
        padding: (any EdgeInsetsGeometry)? = nil,
        child: Widget? = nil
    ) {
        self.scrollDirection = scrollDirection
        self.reverse = reverse
        self.controller = controller
        self.physics = physics
        self.padding = padding
        self.child = child
        super.init(key: key)
    }

    /// Computes the axis direction for the scroll view.
    private func _getDirection(_ context: any BuildContext) -> AxisDirection {
        return getAxisDirectionFromAxisReverseAndDirectionality(
            context, scrollDirection, reverse
        )
    }

    /// **Dart Source:** `single_child_scroll_view.dart:138-156`
    public override func build(_ context: any BuildContext) -> Widget {
        let axisDirection = _getDirection(context)

        var contents: Widget?
        if padding != nil, let child = child {
            contents = Padding(padding: padding!, child: child)
        } else {
            contents = child
        }

        return Scrollable(
            axisDirection: axisDirection,
            controller: controller,
            physics: physics,
            viewportBuilder: { context, offset in
                return _SingleChildViewport(
                    axisDirection: axisDirection,
                    offset: offset,
                    child: contents
                )
            }
        )
    }
}

// MARK: - _SingleChildViewport

/// A viewport widget for `SingleChildScrollView` that directly wraps a box
/// child. Uses `_RenderSingleChildViewport` which gives the child unbounded
/// constraints in the scroll axis and clips/offsets the painted output.
///
/// This matches the Dart implementation which uses a custom RenderBox rather
/// than the sliver infrastructure.
private class _SingleChildViewport: SingleChildRenderObjectWidget {
    let axisDirection: AxisDirection
    let offset: ViewportOffset

    init(
        key: (any Key)? = nil,
        axisDirection: AxisDirection,
        offset: ViewportOffset,
        child: Widget? = nil
    ) {
        self.axisDirection = axisDirection
        self.offset = offset
        super.init(key: key, child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return _RenderSingleChildViewport(
            axisDirection: axisDirection,
            offset: offset
        )
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! _RenderSingleChildViewport
        ro.axisDirection = axisDirection
        ro.offset = offset
    }
}

// MARK: - _RenderSingleChildViewport

/// A render box that lays out a single box child with unbounded constraints in
/// the scroll direction, then clips and offsets it according to `offset`.
///
/// **Dart Source:** `single_child_scroll_view.dart:313-577`
private class _RenderSingleChildViewport: RenderBox, SingleChildRenderObjectHost {
    var child: RenderBox? {
        didSet {
            // Must adopt/drop (not just set parentData): without a parent
            // pointer the child subtree's markNeedsLayout() walk dies here,
            // the viewport never re-lays-out a rebuilt child, and painting
            // freshly inserted descendants hits the "no constraints" fatal.
            if let oldChild = oldValue {
                dropChild(oldChild)
                oldChild.parentData = nil
            }
            if let newChild = child {
                adoptChild(newChild)
            } else {
                markNeedsLayout()
            }
        }
    }

    var axisDirection: AxisDirection {
        didSet {
            if oldValue != axisDirection { markNeedsLayout() }
        }
    }

    var offset: ViewportOffset {
        didSet {
            if oldValue !== offset {
                if attached {
                    oldValue.removeListeners(owner: self)
                    offset.addListener(_onOffsetChanged, owner: self)
                }
                markNeedsLayout()
            }
        }
    }

    private var axis: Axis {
        axisDirectionToAxis(axisDirection)
    }

    init(axisDirection: AxisDirection, offset: ViewportOffset) {
        self.axisDirection = axisDirection
        self.offset = offset
        super.init()
    }

    private func _onOffsetChanged() {
        markNeedsPaint()
    }

    override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        offset.addListener(_onOffsetChanged, owner: self)
    }

    override func detach() {
        offset.removeListeners(owner: self)
        super.detach()
    }

    // MARK: - Layout

    override func performLayout() {
        let constraints = self.boxConstraints
        if let child = child {
            // Give the child unbounded constraints in the scroll direction
            let childConstraints: BoxConstraints
            if axis == .vertical {
                childConstraints = BoxConstraints(
                    minWidth: constraints.maxWidth,
                    maxWidth: constraints.maxWidth,
                    minHeight: 0,
                    maxHeight: Double.infinity
                )
            } else {
                childConstraints = BoxConstraints(
                    minWidth: 0,
                    maxWidth: Double.infinity,
                    minHeight: constraints.maxHeight,
                    maxHeight: constraints.maxHeight
                )
            }
            child.layout(childConstraints, parentUsesSize: true)

            // Size ourselves to the incoming constraints
            size = constraints.constrain(child.size)

            // Update scroll extent
            let mainAxisExtent: Double
            let childMainAxisExtent: Double
            if axis == .vertical {
                mainAxisExtent = size.height
                childMainAxisExtent = child.size.height
            } else {
                mainAxisExtent = size.width
                childMainAxisExtent = child.size.width
            }
            let maxScrollExtent = max(0.0, childMainAxisExtent - mainAxisExtent)
            if let scrollPosition = offset as? ScrollPosition {
                scrollPosition.applyContentDimensions(0.0, maxScrollExtent)
                _ = scrollPosition.applyViewportDimension(mainAxisExtent)
            }
        } else {
            size = constraints.smallest
        }
    }

    // MARK: - Paint

    override func paint(_ context: PaintingContext, _ paintOffset: Offset) {
        guard let child = child else { return }

        let scrollOffset = (self.offset as? ScrollPosition)?.pixels ?? 0.0

        let childOffset: Offset
        switch axisDirection {
        case .down:
            childOffset = Offset(paintOffset.dx, paintOffset.dy - scrollOffset)
        case .up:
            childOffset = Offset(paintOffset.dx, paintOffset.dy + scrollOffset)
        case .right:
            childOffset = Offset(paintOffset.dx - scrollOffset, paintOffset.dy)
        case .left:
            childOffset = Offset(paintOffset.dx + scrollOffset, paintOffset.dy)
        }

        // Clip to our bounds
        context.pushClipRect(
            false,
            paintOffset,
            Rect.fromLTRB(0, 0, size.width, size.height),
            { context, offset in
                // Adjust for the clip offset vs our paint offset
                let adjustedOffset = Offset(
                    childOffset.dx - paintOffset.dx + offset.dx,
                    childOffset.dy - paintOffset.dy + offset.dy
                )
                context.paintChild(child, adjustedOffset)
            }
        )
    }

    // MARK: - Hit Testing

    override func hitTestChildren(_ result: BoxHitTestResult, position: Offset) -> Bool {
        guard let child = child else { return false }
        let scrollOffset = (self.offset as? ScrollPosition)?.pixels ?? 0.0
        let childOffset: Offset
        switch axisDirection {
        case .down:
            childOffset = Offset(0, -scrollOffset)
        case .up:
            childOffset = Offset(0, scrollOffset)
        case .right:
            childOffset = Offset(-scrollOffset, 0)
        case .left:
            childOffset = Offset(scrollOffset, 0)
        }
        return result.addWithPaintOffset(
            offset: childOffset,
            position: position,
            hitTest: { result, transformed in
                child.hitTest(result, position: transformed)
            }
        )
    }

    // MARK: - Child management

    override func visitChildren(_ visitor: RenderObjectVisitor) {
        if let child = child { visitor(child) }
    }
}

// =============================================================================
// MARK: - ListView
// =============================================================================

/// A scrollable list of widgets arranged linearly.
///
/// `ListView` is the most commonly used scrolling widget. It displays its
/// children one after another in the scroll direction.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/scroll_view.dart:1275-1605`
///
/// DIFFERENCE FROM DART: Simplified. In Dart, `ListView` extends `BoxScrollView`
/// which extends `ScrollView` which is `StatefulWidget`. This version is a
/// `StatelessWidget` that composes `Scrollable` with a viewport and slivers.
/// REASON: Focus on getting functional list scrolling working.
public class ListView: StatelessWidget {

    /// The axis along which the scroll view scrolls.
    ///
    /// **Dart Source:** `scroll_view.dart:1410`
    public let scrollDirection: Axis

    /// Whether the scroll view scrolls in the reading direction.
    ///
    /// **Dart Source:** `scroll_view.dart:1412`
    public let reverse: Bool

    /// An object that can be used to control the position to which this scroll
    /// view is scrolled.
    ///
    /// **Dart Source:** `scroll_view.dart:1416`
    public let controller: ScrollController?

    /// How the scroll view should respond to user input.
    ///
    /// **Dart Source:** `scroll_view.dart:1420`
    public let physics: ScrollPhysics?

    /// The amount of space by which to inset the children.
    ///
    /// **Dart Source:** `scroll_view.dart:1427`
    public let padding: (any EdgeInsetsGeometry)?

    /// If non-nil, forces the children to have the given extent in the scroll
    /// direction.
    ///
    /// **Dart Source:** `scroll_view.dart:1455`
    public let itemExtent: Double?

    /// The delegate that provides children.
    ///
    /// **Dart Source:** `scroll_view.dart:1467`
    public let childrenDelegate: SliverChildDelegate

    /// Whether to shrink-wrap the scroll view contents.
    ///
    /// **Dart Source:** `scroll_view.dart:1415`
    public let shrinkWrap: Bool

    /// Creates a scrollable, linear array of widgets from an explicit `List`.
    ///
    /// This constructor is appropriate for list views with a small number of
    /// children because constructing the `List` requires doing work for every
    /// child that could possibly be displayed in the list view instead of just
    /// those children that are actually visible.
    ///
    /// **Dart Source:** `scroll_view.dart:1351-1390`
    public init(
        key: (any Key)? = nil,
        scrollDirection: Axis = .vertical,
        reverse: Bool = false,
        controller: ScrollController? = nil,
        physics: ScrollPhysics? = nil,
        shrinkWrap: Bool = false,
        padding: (any EdgeInsetsGeometry)? = nil,
        itemExtent: Double? = nil,
        children: [Widget] = []
    ) {
        self.scrollDirection = scrollDirection
        self.reverse = reverse
        self.controller = controller
        self.physics = physics
        self.shrinkWrap = shrinkWrap
        self.padding = padding
        self.itemExtent = itemExtent
        self.childrenDelegate = SliverChildListDelegate(children)
        super.init(key: key)
    }

    /// Creates a scrollable, linear array of widgets that are created on demand.
    ///
    /// This constructor is appropriate for list views with a large (or infinite)
    /// number of children because the builder is called only for those children
    /// that are actually visible.
    ///
    /// **Dart Source:** `scroll_view.dart:1315-1349` (ListView.builder)
    public init(
        key: (any Key)? = nil,
        scrollDirection: Axis = .vertical,
        reverse: Bool = false,
        controller: ScrollController? = nil,
        physics: ScrollPhysics? = nil,
        shrinkWrap: Bool = false,
        padding: (any EdgeInsetsGeometry)? = nil,
        itemExtent: Double? = nil,
        itemCount: Int? = nil,
        itemBuilder: @escaping (any BuildContext, Int) -> Widget?
    ) {
        self.scrollDirection = scrollDirection
        self.reverse = reverse
        self.controller = controller
        self.physics = physics
        self.shrinkWrap = shrinkWrap
        self.padding = padding
        self.itemExtent = itemExtent
        self.childrenDelegate = SliverChildBuilderDelegate(itemBuilder, childCount: itemCount)
        super.init(key: key)
    }

    /// Computes the axis direction for the scroll view.
    private func _getDirection(_ context: any BuildContext) -> AxisDirection {
        return getAxisDirectionFromAxisReverseAndDirectionality(
            context, scrollDirection, reverse
        )
    }

    /// Builds the sliver that displays the list items.
    ///
    /// **Dart Source:** `scroll_view.dart:1569-1584`
    private func _buildSliver(_ context: any BuildContext) -> Widget {
        let sliver: Widget
        if let itemExtent = itemExtent {
            sliver = SliverFixedExtentList(delegate: childrenDelegate, itemExtent: itemExtent)
        } else {
            sliver = SliverList(delegate: childrenDelegate)
        }

        if let padding = padding {
            return SliverPadding(padding: padding, sliver: sliver)
        }
        return sliver
    }

    /// **Dart Source:** `scroll_view.dart:340-395`
    public override func build(_ context: any BuildContext) -> Widget {
        let axisDirection = _getDirection(context)
        let sliver = _buildSliver(context)

        return Scrollable(
            axisDirection: axisDirection,
            controller: controller,
            physics: physics,
            viewportBuilder: { context, offset in
                if self.shrinkWrap {
                    return _ShrinkWrapViewport(
                        axisDirection: axisDirection,
                        offset: offset,
                        slivers: [sliver]
                    )
                } else {
                    return _FullViewport(
                        axisDirection: axisDirection,
                        offset: offset,
                        slivers: [sliver]
                    )
                }
            }
        )
    }
}

// =============================================================================
// MARK: - GridView
// =============================================================================

/// A scrollable, 2D array of widgets.
///
/// The most commonly used grid layouts are `GridView.count`, which creates a
/// layout with a fixed number of tiles in the cross axis, and
/// `GridView.extent`, which creates a layout with tiles that have a maximum
/// cross-axis extent.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/scroll_view.dart:1619-1873`
///
/// DIFFERENCE FROM DART: Simplified as `StatelessWidget` instead of extending
/// `BoxScrollView` → `ScrollView`.
/// REASON: Focus on getting functional grid scrolling working.
public class GridView: StatelessWidget {

    /// The axis along which the scroll view scrolls.
    public let scrollDirection: Axis

    /// Whether the scroll view scrolls in the reading direction.
    public let reverse: Bool

    /// An object that can be used to control the scroll position.
    public let controller: ScrollController?

    /// How the scroll view should respond to user input.
    public let physics: ScrollPhysics?

    /// The amount of space by which to inset the children.
    public let padding: (any EdgeInsetsGeometry)?

    /// A delegate that controls the layout of the children within the `GridView`.
    ///
    /// **Dart Source:** `scroll_view.dart:1763`
    public let gridDelegate: SliverGridDelegate

    /// The delegate that provides children.
    public let childrenDelegate: SliverChildDelegate

    /// Whether to shrink-wrap the scroll view contents.
    public let shrinkWrap: Bool

    /// Creates a scrollable 2D array of widgets with a custom grid delegate.
    ///
    /// **Dart Source:** `scroll_view.dart:1698-1730`
    public init(
        key: (any Key)? = nil,
        scrollDirection: Axis = .vertical,
        reverse: Bool = false,
        controller: ScrollController? = nil,
        physics: ScrollPhysics? = nil,
        shrinkWrap: Bool = false,
        padding: (any EdgeInsetsGeometry)? = nil,
        gridDelegate: SliverGridDelegate,
        children: [Widget] = []
    ) {
        self.scrollDirection = scrollDirection
        self.reverse = reverse
        self.controller = controller
        self.physics = physics
        self.shrinkWrap = shrinkWrap
        self.padding = padding
        self.gridDelegate = gridDelegate
        self.childrenDelegate = SliverChildListDelegate(children)
        super.init(key: key)
    }

    /// Creates a scrollable 2D array of widgets with a builder callback.
    ///
    /// **Dart Source:** `scroll_view.dart:1664-1697` (GridView.builder)
    public init(
        key: (any Key)? = nil,
        scrollDirection: Axis = .vertical,
        reverse: Bool = false,
        controller: ScrollController? = nil,
        physics: ScrollPhysics? = nil,
        shrinkWrap: Bool = false,
        padding: (any EdgeInsetsGeometry)? = nil,
        gridDelegate: SliverGridDelegate,
        itemCount: Int? = nil,
        itemBuilder: @escaping (any BuildContext, Int) -> Widget?
    ) {
        self.scrollDirection = scrollDirection
        self.reverse = reverse
        self.controller = controller
        self.physics = physics
        self.shrinkWrap = shrinkWrap
        self.padding = padding
        self.gridDelegate = gridDelegate
        self.childrenDelegate = SliverChildBuilderDelegate(itemBuilder, childCount: itemCount)
        super.init(key: key)
    }

    /// Creates a scrollable 2D array of widgets with a fixed number of tiles
    /// in the cross axis.
    ///
    /// **Dart Source:** `scroll_view.dart:1745-1786` (GridView.count)
    public convenience init(
        key: (any Key)? = nil,
        scrollDirection: Axis = .vertical,
        reverse: Bool = false,
        controller: ScrollController? = nil,
        physics: ScrollPhysics? = nil,
        shrinkWrap: Bool = false,
        padding: (any EdgeInsetsGeometry)? = nil,
        crossAxisCount: Int,
        mainAxisSpacing: Double = 0.0,
        crossAxisSpacing: Double = 0.0,
        childAspectRatio: Double = 1.0,
        children: [Widget] = []
    ) {
        self.init(
            key: key,
            scrollDirection: scrollDirection,
            reverse: reverse,
            controller: controller,
            physics: physics,
            shrinkWrap: shrinkWrap,
            padding: padding,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: mainAxisSpacing,
                crossAxisSpacing: crossAxisSpacing,
                childAspectRatio: childAspectRatio
            ),
            children: children
        )
    }

    /// Computes the axis direction for the scroll view.
    private func _getDirection(_ context: any BuildContext) -> AxisDirection {
        return getAxisDirectionFromAxisReverseAndDirectionality(
            context, scrollDirection, reverse
        )
    }

    /// Builds the sliver that displays the grid items.
    private func _buildSliver(_ context: any BuildContext) -> Widget {
        let sliver: Widget = SliverGrid(
            delegate: childrenDelegate,
            gridDelegate: gridDelegate
        )
        if let padding = padding {
            return SliverPadding(padding: padding, sliver: sliver)
        }
        return sliver
    }

    /// **Dart Source:** (via ScrollView.build)
    public override func build(_ context: any BuildContext) -> Widget {
        let axisDirection = _getDirection(context)
        let sliver = _buildSliver(context)

        return Scrollable(
            axisDirection: axisDirection,
            controller: controller,
            physics: physics,
            viewportBuilder: { context, offset in
                if self.shrinkWrap {
                    return _ShrinkWrapViewport(
                        axisDirection: axisDirection,
                        offset: offset,
                        slivers: [sliver]
                    )
                } else {
                    return _FullViewport(
                        axisDirection: axisDirection,
                        offset: offset,
                        slivers: [sliver]
                    )
                }
            }
        )
    }
}

// =============================================================================
// MARK: - Viewport Widgets (Internal)
// =============================================================================

/// A viewport widget that expands to fill available space, using `RenderViewport`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/viewport.dart:20-156`
private class _FullViewport: MultiChildRenderObjectWidget {
    let axisDirection: AxisDirection
    let offset: ViewportOffset

    init(
        key: (any Key)? = nil,
        axisDirection: AxisDirection,
        offset: ViewportOffset,
        slivers: [Widget] = []
    ) {
        self.axisDirection = axisDirection
        self.offset = offset
        super.init(key: key, children: slivers)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        let crossAxis: AxisDirection
        switch axisDirection {
        case .down: crossAxis = .right
        case .up: crossAxis = .right
        case .right: crossAxis = .down
        case .left: crossAxis = .down
        }
        return RenderViewport(
            axisDirection: axisDirection,
            crossAxisDirection: crossAxis,
            offset: offset
        )
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderViewport
        ro.axisDirection = axisDirection
        ro.offset = offset
    }
}

/// A viewport widget that shrink-wraps its contents, using
/// `RenderShrinkWrappingViewport`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/viewport.dart:163-226`
private class _ShrinkWrapViewport: MultiChildRenderObjectWidget {
    let axisDirection: AxisDirection
    let offset: ViewportOffset

    init(
        key: (any Key)? = nil,
        axisDirection: AxisDirection,
        offset: ViewportOffset,
        slivers: [Widget] = []
    ) {
        self.axisDirection = axisDirection
        self.offset = offset
        super.init(key: key, children: slivers)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        let crossAxis: AxisDirection
        switch axisDirection {
        case .down: crossAxis = .right
        case .up: crossAxis = .right
        case .right: crossAxis = .down
        case .left: crossAxis = .down
        }
        return RenderShrinkWrappingViewport(
            axisDirection: axisDirection,
            crossAxisDirection: crossAxis,
            offset: offset
        )
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderShrinkWrappingViewport
        ro.axisDirection = axisDirection
        ro.offset = offset
    }
}

// =============================================================================
// MARK: - Helper: getAxisDirectionFromAxisReverseAndDirectionality
// =============================================================================

/// Determines the `AxisDirection` based on the scroll axis, reverse flag, and
/// text directionality.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/scroll_view.dart:28-52`
public func getAxisDirectionFromAxisReverseAndDirectionality(
    _ context: any BuildContext,
    _ axis: Axis,
    _ reverse: Bool
) -> AxisDirection {
    switch axis {
    case .horizontal:
        let textDirection = Directionality.maybeOf(context) ?? .ltr
        let axisDirection: AxisDirection = textDirectionToAxisDirection(textDirection)
        return reverse ? flipAxisDirection(axisDirection) : axisDirection
    case .vertical:
        return reverse ? .up : .down
    }
}

// textDirectionToAxisDirection and flipAxisDirection are defined in
// PaintingBasicTypes.swift and available module-wide.
