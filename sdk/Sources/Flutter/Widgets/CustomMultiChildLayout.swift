// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The widget layer over `RenderCustomMultiChildLayoutBox`: `LayoutId` and
/// `CustomMultiChildLayout`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/basic.dart` (LayoutId,
/// CustomMultiChildLayout)

import FlutterSwiftBridge
import class Foundation.FileHandle
import struct Foundation.Data

// MARK: - LayoutId

/// Metadata for identifying children of a `CustomMultiChildLayout`.
///
/// The `MultiChildLayoutDelegate.hasChild`, `MultiChildLayoutDelegate.layoutChild`,
/// and `MultiChildLayoutDelegate.positionChild` methods use these ids.
///
/// **Dart Source:** `basic.dart:2600`
public class LayoutId: ParentDataWidget<MultiChildLayoutParentData> {
    /// An object representing the identity of this child.
    public let id: AnyHashable

    /// Marks a child with a layout identifier.
    ///
    /// As in Dart, the key defaults to a `ValueKey` of the id so the element
    /// tree keeps children matched to their ids across reorders.
    public init(key: (any Key)? = nil, id: AnyHashable, child: Widget) {
        self.id = id
        super.init(key: key ?? ValueKey<AnyHashable>(id), child: child)
    }

    public override func applyParentData(_ renderObject: RenderObject) {
        // A `LayoutId` must be a direct child of a `CustomMultiChildLayout`.
        // Mirror Positioned's degrade-don't-crash policy: log and skip rather
        // than take the whole compositor down on one malformed subtree.
        guard let parentData = renderObject.parentData as? MultiChildLayoutParentData else {
            let msg = "[LayoutId] applyParentData: expected MultiChildLayoutParentData but got "
                + "\(type(of: renderObject.parentData)) on \(type(of: renderObject)) -- "
                + "LayoutId is not directly inside a CustomMultiChildLayout; skipping (id=\(id))\n"
            // try? — degrade-path warning; see Positioned.applyParentData.
            try? FileHandle.standardError.write(contentsOf: Data(msg.utf8))
            return
        }
        if parentData.id != id {
            parentData.id = id
            renderObject.parent?.markNeedsLayout()
        }
    }

    public override var debugTypicalAncestorWidgetClass: String {
        return "CustomMultiChildLayout"
    }
}

// MARK: - CustomMultiChildLayout

/// A widget that uses a delegate to size and position multiple children.
///
/// The delegate can determine the layout constraints for each child and can
/// decide where to position each child. The delegate can also determine the
/// size of the parent, but the size of the parent cannot depend on the sizes
/// of the children.
///
/// Each child must be wrapped in a `LayoutId` widget to identify the widget
/// for the delegate.
///
/// **Dart Source:** `basic.dart:2661`
public class CustomMultiChildLayout: MultiChildRenderObjectWidget {
    /// The delegate that controls the layout of the children.
    public let delegate: MultiChildLayoutDelegate

    /// Creates a custom multi-child layout.
    public init(
        key: (any Key)? = nil,
        delegate: MultiChildLayoutDelegate,
        children: [Widget] = []
    ) {
        self.delegate = delegate
        super.init(key: key, children: children)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderCustomMultiChildLayoutBox(delegate: delegate)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        (renderObject as! RenderCustomMultiChildLayoutBox).delegate = delegate
    }
}
