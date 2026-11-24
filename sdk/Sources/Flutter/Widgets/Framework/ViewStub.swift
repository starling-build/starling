// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import FlutterSwiftBridge

// MARK: - View Stub

/// Minimal stub for the `View` widget from `widgets/view.dart`.
///
/// Provides `View.of(context)` which returns the `FlutterView` for the given
/// context. The full `View` widget implementation will replace this stub.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/view.dart`
public enum View {
    /// The `FlutterView` that `context` renders into, or nil when `context` is not under a view's root.
    ///
    /// Each view's tree is rooted in its own `RenderObjectToWidgetAdapter`, which holds that view's `RenderView`, so
    /// this walks up to it: with several windows each asks about its own view, never the first one's.
    ///
    /// **Dart Source:** `view.dart` (View.maybeOf)
    public static func maybeOf(_ context: any BuildContext) -> FlutterView? {
        var element = context as? Element
        while let e = element {
            if let adapter = e.widget as? RenderObjectToWidgetAdapter { return adapter.container.flutterView }
            element = e._parent
        }
        return nil
    }

    /// Returns the `FlutterView` that the given context is rendering into.
    ///
    /// **Dart Source:** `view.dart` (View.of)
    public static func of(_ context: any BuildContext) -> FlutterView {
        guard let view = maybeOf(context) else {
            fatalError("View.of() called with a context that is not under a view's root.")
        }
        return view
    }
}
