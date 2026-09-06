// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// MARK: - Focus (minimal)
//
// A minimal focus system: a single global focus owner plus key-event routing.
// Not a full focus_manager.dart port (no scopes, traversal, or directional
// focus) — just enough for click-to-focus text input. The stub types needed
// by framework.dart (`registerGlobalHandlers`, `FocusScopeNode`) are kept.

import FlutterSwiftBridge

/// A leaf that can hold keyboard focus.
///
/// Widgets create one, call `requestFocus()` (e.g. on tap), and receive key
/// events through `onKeyData` while focused. `onFocusChange` fires on both
/// gain and loss.
public final class FocusNode {
    /// Handles a key event while this node has focus. Return `true` if the
    /// event was consumed.
    public var onKeyData: ((KeyData) -> Bool)?

    /// Called with `true` when this node gains focus and `false` when it
    /// loses focus.
    public var onFocusChange: ((Bool) -> Void)?

    /// A label used in debug descriptions.
    public let debugLabel: String?

    public init(debugLabel: String? = nil) {
        self.debugLabel = debugLabel
    }

    /// Whether this node currently holds the global focus.
    public var hasFocus: Bool {
        return FocusManager.instance.focusedNode === self
    }

    /// Makes this node the global focus owner.
    public func requestFocus() {
        FocusManager.instance._setFocus(self)
    }

    /// Gives up focus if this node holds it.
    public func unfocus() {
        if hasFocus {
            FocusManager.instance._setFocus(nil)
        }
    }

    /// Releases focus; call from `State.dispose()`.
    public func dispose() {
        unfocus()
        onKeyData = nil
        onFocusChange = nil
    }
}

/// Tracks the single focused `FocusNode` and routes key events to it.
///
/// `PlatformDispatcher.onKeyData` is pointed at `dispatchKeyData` during
/// `runApp` setup; hosts with their own key handling (e.g. the desktop shell
/// forwarding keys to native windows) should fall back to
/// `FocusManager.instance.dispatchKeyData` for unclaimed events.
public class FocusManager {
    /// The app-wide focus manager.
    nonisolated(unsafe) public static let instance = FocusManager()

    /// The node that currently holds keyboard focus, if any.
    public private(set) var focusedNode: FocusNode?

    /// Creates a focus manager.
    public init() {}

    /// Registers global input handlers. (Legacy framework.dart hook; the key
    /// handler is installed by `runApp` setup instead.)
    public func registerGlobalHandlers() {}

    /// Moves focus to `node` (or clears it when nil), notifying both sides.
    internal func _setFocus(_ node: FocusNode?) {
        guard focusedNode !== node else { return }
        let old = focusedNode
        focusedNode = node
        old?.onFocusChange?(false)
        node?.onFocusChange?(true)
    }

    /// Routes a key event to the focused node; an Escape the node does not
    /// claim closes the topmost transient surface (`DismissStack`).
    /// Returns `true` if consumed.
    public func dispatchKeyData(_ data: KeyData) -> Bool {
        if let node = focusedNode, let handler = node.onKeyData, handler(data) {
            return true
        }
        if data.type == .down, DismissStack.isEscape(data) {
            return DismissStack.dismissTop()
        }
        return false
    }
}

/// Stub for `FocusScopeNode`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/focus_manager.dart`
public class FocusScopeNode {
    /// Creates a focus scope node.
    public init() {}
}
