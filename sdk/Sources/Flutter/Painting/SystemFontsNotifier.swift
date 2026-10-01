// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// System fonts notifier for painting binding.
///
/// **Dart Source:** `packages/flutter/lib/src/painting/binding.dart`

import FlutterSwiftBridge

// MARK: - SystemFontsNotifier

/// A notifier that notifies listeners when the system fonts change.
///
/// This is used by `PaintingBinding` to notify widgets that depend on system
/// fonts (like text widgets) when the system fonts have changed and they need
/// to re-layout or repaint.
///
/// This class implements `Listenable` to allow widgets to subscribe to
/// font change notifications.
///
/// Note: In Dart, closures have stable equality, so `removeListener` can
/// identify which closure to remove. In Swift, closures lack stable identity,
/// so `removeListener` removes the most recently added listener (LIFO order).
/// Callers needing precise removal control should use a class-based listener
/// wrapper.
///
/// **Dart Source:** `packages/flutter/lib/src/painting/binding.dart`
/// **Original Name:** `_SystemFontsNotifier`
/// **Lines:** 188-206
public final class SystemFontsNotifier: Listenable {
    /// Creates a new `SystemFontsNotifier`.
    public init() {}

    /// Storage for listener boxes.
    ///
    /// **Dart Source:** `binding.dart:189`
    private var _listeners = ListenerList()

    /// Notifies all registered listeners that the system fonts have changed.
    ///
    /// This is called by `PaintingBinding.handleSystemMessage` when a
    /// 'fontsChange' message is received from the platform.
    ///
    /// **Dart Source:** `binding.dart:191-195`
    public func notifyListeners() {
        for listener in _listeners {
            listener()
        }
    }

    /// Registers a callback to be called when system fonts change.
    ///
    /// Each call adds a new listener entry.
    ///
    /// **Dart Source:** `binding.dart:197-200`
    public func addListener(_ listener: @escaping VoidCallback) {
        _listeners.append(listener)
    }

    /// Removes the most recently added unkeyed listener; see `ListenerList`.
    ///
    /// **Dart Source:** `binding.dart:202-205`
    public func removeListener(_ listener: @escaping VoidCallback) {
        _listeners.removeLast()
    }

    public func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        _listeners.append(listener, owner: owner)
    }

    public func removeListeners(owner: AnyObject) {
        _listeners.remove(owner: owner)
    }

    /// The number of registered listeners.
    ///
    /// This is useful for testing to verify listener registration.
    public var listenerCount: Int {
        _listeners.count
    }
}
