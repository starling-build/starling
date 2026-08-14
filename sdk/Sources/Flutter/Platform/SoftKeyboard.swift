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

    public static func show() { handler?.show() }

    public static func hide() { handler?.hide() }
}
