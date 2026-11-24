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

    /// The focus scope (window) this node lives in: set by its first `requestFocus()` and never changed (a node is in
    /// one widget tree). See `FocusManager.resolveScope`.
    var _scope: Int?

    /// Whether this node holds the focus of the window the keys go to.
    public var hasFocus: Bool {
        return FocusManager.instance.focusedNode === self
    }

    /// Makes this node the focus owner of its window (and, if that window is the one the keys go to, of the keys).
    public func requestFocus() {
        let manager = FocusManager.instance
        let scope = _scope ?? manager.resolveScope()
        _scope = scope
        manager._setFocus(self, scope: scope)
    }

    /// Gives up focus if this node holds it.
    public func unfocus() {
        guard let scope = _scope else { return }
        FocusManager.instance._clearFocus(self, scope: scope)
    }

    /// Releases focus; call from `State.dispose()`.
    public func dispose() {
        unfocus()
        onKeyData = nil
        onFocusChange = nil
    }
}

/// Tracks the focused `FocusNode` of each window and routes key events to the one the keys go to.
///
/// A window is a focus scope: view 0 (and every view not registered as a window, such as another monitor's view or a
/// popup, which share view 0's scope), and each view shown with `runView(id:)`. Each scope keeps its own focused node,
/// so a second window being touched does not take the first window's focus away for good: the scope the user last
/// touched is the KEY scope; its node has the keys (and the text input, the caret); the node of the scope that stopped
/// being key hears `onFocusChange(false)` and hears `true` again when its window is touched.
///
/// `PlatformDispatcher.onKeyData` is pointed at `dispatchKeyData` during
/// `runApp` setup; hosts with their own key handling (e.g. the desktop shell
/// forwarding keys to native windows) should fall back to
/// `FocusManager.instance.dispatchKeyData` for unclaimed events.
public class FocusManager {
    /// The app-wide focus manager.
    nonisolated(unsafe) public static let instance = FocusManager()

    /// The views that are windows of their own (`runView`); every other view is in scope 0.
    public var windowViewIds: Set<Int> = []

    /// The scope the keys go to.
    public private(set) var keyScope = 0

    /// The scope a view's focus belongs to.
    public func scope(ofView viewId: Int) -> Int { windowViewIds.contains(viewId) ? viewId : 0 }

    /// The view being mounted right now, so a node that asks for focus in its `initState` belongs to that view's
    /// scope (set by the frame loop around a new view's first build).
    var mountingViewId: Int?

    /// The view whose pointer event is being dispatched.
    var dispatchingViewId: Int?

    private var _focusedByScope: [Int: FocusNode] = [:]

    /// The node that currently holds keyboard focus (in the key scope), if any.
    public var focusedNode: FocusNode? { _focusedByScope[keyScope] }

    /// Creates a focus manager.
    public init() {}

    /// Registers global input handlers. (Legacy framework.dart hook; the key
    /// handler is installed by `runApp` setup instead.)
    public func registerGlobalHandlers() {}

    /// Which scope a node that has none yet belongs to: the view of the pointer event being handled, else the view
    /// being mounted, else the one the keys go to.
    func resolveScope() -> Int {
        if let v = dispatchingViewId { return scope(ofView: v) }
        if let v = mountingViewId { return scope(ofView: v) }
        return keyScope
    }

    /// The user touched view `viewId`: its window becomes the key one.
    public func viewTouched(_ viewId: Int) {
        let target = scope(ofView: viewId)
        guard target != keyScope else { return }
        let old = _focusedByScope[keyScope]
        keyScope = target
        old?.onFocusChange?(false)
        SoftKeyboard.focusMoved()
        _focusedByScope[target]?.onFocusChange?(true)
    }

    /// Makes `node` the focused node of `scope`. In the key scope the old node is told it lost focus and the new one
    /// that it gained it; in another scope the change is silent until that scope becomes the key one.
    internal func _setFocus(_ node: FocusNode, scope: Int) {
        let old = _focusedByScope[scope]
        guard old !== node else { return }
        _focusedByScope[scope] = node
        guard scope == keyScope else { return }
        old?.onFocusChange?(false)
        SoftKeyboard.focusMoved()
        node.onFocusChange?(true)
    }

    /// A window's view was removed: its focus is gone, and if the keys were going to it they go back to scope 0.
    func windowRemoved(_ viewId: Int) {
        windowViewIds.remove(viewId)
        let hadKeys = keyScope == viewId
        _focusedByScope[viewId] = nil
        if hadKeys {
            keyScope = 0
            SoftKeyboard.focusMoved()
            _focusedByScope[0]?.onFocusChange?(true)
        }
    }

    /// For test drivers: each scope's focused node and which scope has the keys.
    public var debugSummary: String {
        let parts = _focusedByScope.keys.sorted().map { "\($0): \(_focusedByScope[$0]?.debugLabel ?? "?")" }
        return "scopes=[\(parts.joined(separator: ", "))] keys=\(keyScope)"
    }

    /// `node` gives up focus in `scope`, if it holds it.
    internal func _clearFocus(_ node: FocusNode, scope: Int) {
        guard _focusedByScope[scope] === node else { return }
        _focusedByScope[scope] = nil
        guard scope == keyScope else { return }
        node.onFocusChange?(false)
        SoftKeyboard.focusMoved()
    }

    /// Handlers that see a key before the focused node does, newest first:
    /// for something that is open OVER the focused thing without taking
    /// its focus — a menu, which must close on Escape while the text it
    /// was opened from keeps its selection and caret.
    private var _keyInterceptors: [(id: Int, handler: (KeyData) -> Bool)] = []
    private var _nextInterceptor = 0

    /// Puts `handler` ahead of the focused node; it returns `true` for a
    /// key it consumed. The returned token takes it out again.
    public func addKeyInterceptor(_ handler: @escaping (KeyData) -> Bool) -> Int {
        _nextInterceptor += 1
        _keyInterceptors.append((id: _nextInterceptor, handler: handler))
        return _nextInterceptor
    }

    public func removeKeyInterceptor(_ token: Int) {
        _keyInterceptors.removeAll { $0.id == token }
    }

    /// Routes a key event to the focused node. Returns `true` if consumed.
    public func dispatchKeyData(_ data: KeyData) -> Bool {
        for interceptor in _keyInterceptors.reversed() where interceptor.handler(data) { return true }
        guard let node = focusedNode, let handler = node.onKeyData else {
            return false
        }
        return handler(data)
    }
}

/// Stub for `FocusScopeNode`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/focus_manager.dart`
public class FocusScopeNode {
    /// Creates a focus scope node.
    public init() {}
}
