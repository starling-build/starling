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
    /// The shortcut's command-line arguments, if any. Carried because we
    /// start the TARGET rather than the shortcut — see `launch`.
    public let arguments: String
    /// The shortcut's working directory, for the same reason.
    public let workingDirectory: String
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

    /// Starts an app — by its TARGET, not by its shortcut.
    ///
    /// Both work. The difference is that opening a `.lnk` through the shell
    /// measured **484ms the first time in a process and 73ms after**, against
    /// **8ms** for the executable it points at, cold or warm. That is the
    /// shell's link-resolution machinery, and it was being charged to the UI
    /// thread on the click that asked for it, with the launcher still on
    /// screen for every millisecond of it.
    ///
    /// We already resolve the target for every entry — it is how icons are
    /// rasterized and how a window is matched back to its app — so the fast
    /// path costs nothing extra. The arguments and working directory come
    /// along with it, because a shortcut is often an exe plus a switch and
    /// starting the exe alone would quietly do the wrong thing.
    ///
    /// The `.lnk` remains the fallback for entries with no target: Store apps
    /// store an item-ID list rather than a path, and only the shell can
    /// follow that.
    @discardableResult
    public static func launch(_ app: Win32App) -> Bool {
        guard canStartDirectly(app) else {
            return flwin32_launch(app.shortcutPath, nil, nil) != 0
        }
        return flwin32_launch(app.target,
                              app.arguments.isEmpty ? nil : app.arguments,
                              app.workingDirectory.isEmpty ? nil : app.workingDirectory) != 0
    }

    /// Extensions we are willing to start ourselves. Everything else goes
    /// back through the shell and the shortcut.
    ///
    /// `.msc` and `.cpl` are here because a third of the Start Menu is
    /// management consoles and control-panel applets, and they are started
    /// exactly like a program.
    private static let startableExtensions: Set<String> =
        ["exe", "com", "bat", "cmd", "msc", "cpl"]

    /// Whether the fast path is safe for this entry.
    ///
    /// Two guards, both paid for by a real shortcut on the test machine:
    ///
    /// - **The target is not always a program.** An MSI *advertised* shortcut
    ///   stores an installer descriptor, and asking it for a path hands back
    ///   whatever it has — the WSL entry's target is `wsl.ico`. Starting that
    ///   directly opens an image viewer. Only known-executable extensions take
    ///   the fast path.
    /// - **The target may not be there.** A shortcut whose program has moved
    ///   is something the shell can chase and we cannot, so a target that does
    ///   not exist on disk goes back to the shortcut rather than failing.
    private static func canStartDirectly(_ app: Win32App) -> Bool {
        guard !app.target.isEmpty else { return false }
        let ext = (app.target as NSString).pathExtension.lowercased()
        guard startableExtensions.contains(ext) else { return false }
        return FileManager.default.fileExists(atPath: app.target)
    }

    /// Starts anything the shell can open: a path, a document, a URL.
    @discardableResult
    public static func open(_ path: String, arguments: String? = nil) -> Bool {
        flwin32_launch(path, arguments, nil) != 0
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
            let info = info(of: full)
            out.append(Win32App(
                shortcutPath: full,
                name: String(name.dropLast(4)),
                target: info.target.lowercased(),
                category: (folder as NSString).lastPathComponent,
                arguments: info.arguments,
                workingDirectory: info.workingDirectory))
        }
        return out
    }

    /// One `.lnk` load for all three fields — the load is the expensive half,
    /// and the catalog walk does it once per shortcut across a few hundred.
    private static func info(
        of shortcut: String
    ) -> (target: String, arguments: String, workingDirectory: String) {
        var target = [CChar](repeating: 0, count: 1024)
        var args = [CChar](repeating: 0, count: 1024)
        var dir = [CChar](repeating: 0, count: 1024)
        target.withUnsafeMutableBufferPointer { t in
            args.withUnsafeMutableBufferPointer { a in
                dir.withUnsafeMutableBufferPointer { d in
                    _ = flwin32_shortcut_info(shortcut,
                                              t.baseAddress, 1024,
                                              a.baseAddress, 1024,
                                              d.baseAddress, 1024)
                }
            }
        }
        return (String(cString: target), String(cString: args), String(cString: dir))
    }
}
#endif
