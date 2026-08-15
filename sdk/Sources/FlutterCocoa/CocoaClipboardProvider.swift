// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(macOS)

import AppKit
import Flutter

/// `Clipboard` for an app in a Cocoa window, backed by NSPasteboard — so a
/// FlutterSwift app on macOS copies and pastes with the rest of the Mac, not
/// just with itself. The counterpart of `GtkClipboardProvider` and
/// `Win32ClipboardProvider`.
///
/// Installed by `CocoaHost`'s initializer rather than a host-boot hook,
/// because Cocoa surfaces reach that initializer down two roads —
/// `CocoaWindowedHost.install()` and the example hosts' direct `CocoaHost()`
/// — and the GTK precedent of installing at boot left the second road with
/// the process-local fallback clipboard.
///
/// NSPasteboard is synchronous, so `getText` answers immediately; the
/// completion still runs on the main thread exactly once, per the
/// `ClipboardProvider` contract.
public final class CocoaClipboardProvider: ClipboardProvider {
    public init() {}

    public func setText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    public func getText(_ completion: @escaping (String?) -> Void) {
        let text = NSPasteboard.general.string(forType: .string)
        if Thread.isMainThread {
            completion(text)
        } else {
            DispatchQueue.main.async { completion(text) }
        }
    }
}

#endif
