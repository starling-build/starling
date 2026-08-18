// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What is installed on this machine, for the dock and the launcher.
//
// The Linux shell reads Starling's own app registry — `catalog.d/*.app` plus
// what `app-install` records. Windows has no equivalent, and the thing that
// stands in for it is the START MENU: a tree of `.lnk` shortcuts under a
// machine-wide folder and a per-user one. Explorer's own Start reads exactly
// this, so a shell that reads it sees the same apps the user expects to see,
// including ones installed after we started.

#if os(Windows)
import FlutterWin32Bridge
import Foundation

/// One installed application.
public struct Win32App: Sendable, Equatable, Identifiable {
    /// The shortcut's path — the id, because two apps can share a display
    /// name and a target (Chrome's per-profile shortcuts, for one).
    public let shortcutPath: String
    public var id: String { shortcutPath }
    /// What the Start Menu calls it: the shortcut's file name without `.lnk`.
    public let name: String
    /// The executable the shortcut starts, lowercased for comparison against
    /// `Win32Window.executablePath`. Empty when the shortcut stores an
    /// item-ID list rather than a path (Store apps, mostly) — those still
    /// launch, they just cannot be matched to a running window this way.
    public let target: String
    /// Where in the Start Menu tree it sits — "Accessories", "" for the top
    /// level. The launcher groups by this.
    public let category: String
}

public enum Win32AppCatalog {

    /// Everything in both Start Menu trees, sorted by name, de-duplicated by
    /// target so an app installed both machine-wide and per-user appears once.
    ///
    /// This walks a few hundred files and resolves each through COM, so it is
    /// tens of milliseconds — a startup and refresh cost, not a per-frame one.
    public static func apps() -> [Win32App] {
        var byKey: [String: Win32App] = [:]
        for which in Int32(0)...Int32(1) {
            guard let root = knownFolder(which) else { continue }
            for app in scan(root) {
                // Keyed by target when there is one, so the machine-wide and
                // per-user copies of the same app collapse; by shortcut path
                // otherwise, which keeps unresolvable ones distinct.
                let key = app.target.isEmpty ? app.shortcutPath.lowercased() : app.target
                if byKey[key] == nil { byKey[key] = app }
            }
        }
        return byKey.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Starts an app. Through the shell, so a `.lnk` works — which is what
    /// every entry here is.
    @discardableResult
    public static func launch(_ app: Win32App) -> Bool {
        flwin32_launch(app.shortcutPath, nil) != 0
    }

    /// Starts anything the shell can open: a path, a document, a URL.
    @discardableResult
    public static func open(_ path: String, arguments: String? = nil) -> Bool {
        flwin32_launch(path, arguments) != 0
    }

    // MARK: - Private

    private static func knownFolder(_ which: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_known_folder(which, $0.baseAddress, 1024)
        }
        guard n > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func scan(_ root: String) -> [Win32App] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: root) else { return [] }
        var out: [Win32App] = []
        for case let relative as String in walker {
            guard relative.lowercased().hasSuffix(".lnk") else { continue }
            let full = root + "\\" + relative
            let name = (relative as NSString).lastPathComponent
            // The folder the shortcut sits in, which is the Start Menu's own
            // grouping — "Accessories", "Microsoft Office", and so on.
            let folder = (relative as NSString).deletingLastPathComponent
            out.append(Win32App(
                shortcutPath: full,
                name: String(name.dropLast(4)),
                target: target(of: full).lowercased(),
                category: (folder as NSString).lastPathComponent))
        }
        return out
    }

    private static func target(of shortcut: String) -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_shortcut_target(shortcut, $0.baseAddress, 1024)
        }
        guard n > 0 else { return "" }
        return String(cString: buffer)
    }
}
#endif
