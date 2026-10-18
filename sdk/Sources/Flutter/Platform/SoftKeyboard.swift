// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The seam between a widget that wants an on-screen keyboard and the host that
// owns one.
//
// It is an installed hook rather than a direct call for two reasons, and both
// are structural. This module must never import a platform's UI headers — the
// C++-interop importer walks everything it can see, and <UIKit/UIKit.h>
// reaching it is the same containment failure the GTK and Cocoa bridges exist
// to prevent. And the host packages depend on this one, so calling into
// FlutterUIKit from here would be a cycle regardless.
//
// So the direction is inverted: the host installs, widgets ask. On a platform
// with no on-screen keyboard nothing installs anything and every call is a
// no-op, which is the correct behaviour for a desktop rather than a special
// case anyone has to write.

import Foundation

/// The on-screen keyboard, if the running host has one.
public enum SoftKeyboard {

    /// Installed by the host at startup. `nil` everywhere that types on real
    /// keys — every desktop, and iOS before the host has finished starting.
    public nonisolated(unsafe) static var handler: Handler?

    public struct Handler {
        public let show: () -> Void
        public let hide: () -> Void
        public let isVisible: () -> Bool

        public init(
            show: @escaping () -> Void,
            hide: @escaping () -> Void,
            isVisible: @escaping () -> Bool
        ) {
            self.show = show
            self.hide = hide
            self.isVisible = isVisible
        }
    }

    /// True when a host has one to offer at all — the question a widget asks
    /// before drawing anything that would only make sense with one.
    public static var isAvailable: Bool { handler != nil }

    public static var isVisible: Bool { handler?.isVisible() ?? false }

    public static func show() {
        _generation &+= 1
        handler?.show()
    }

    public static func hide() { handler?.hide() }

    /// Focus is moving. `FocusManager` calls this between telling the old
    /// owner and the new one: a text field gaining focus asks to `show`,
    /// which keeps the keyboard up with no gap; focus landing anywhere
    /// else — a button, nothing — lets it go a beat later. Deferred rather
    /// than immediate so that a form's blur-then-focus between two fields
    /// never closes it.
    public static func focusMoved() {
        guard let handler, handler.isVisible() else { return }
        _generation &+= 1
        let generation = _generation
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
            if _generation == generation { handler.hide() }
        }
    }

    private nonisolated(unsafe) static var _generation = 0
}
