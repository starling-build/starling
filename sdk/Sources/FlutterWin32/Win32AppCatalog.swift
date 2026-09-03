// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What is installed on this machine, for the dock and the launcher.
//
// The Linux shell reads Starling's own app registry — `catalog.d/*.app` plus
// what `app-install` records. Windows has no equivalent, and what stands in
// for it is TWO catalogs:
//
//   - the START MENU, a tree of `.lnk` shortcuts under a machine-wide folder
//     and a per-user one. It says the most: the target, its arguments, and
//     the folder the launcher groups by.
//   - the APPSFOLDER, a virtual shell folder keyed by AppUserModelID, which
//     is where a PACKAGED app (MSIX/Store/UWP) lives — it has no shortcut
//     anywhere on disk. Reading the Start Menu alone means Settings, the
//     Store, Photos, Notepad, Terminal and Calculator are not just missing
//     from the launcher: they cannot be started from this shell at all.
//
// Explorer's own Start reads both, and so does this. The shortcut wins where
// the two describe the same app, because it is the one carrying detail.

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
    /// The AppUserModelID, for an entry that came from the AppsFolder rather
    /// than a shortcut. Empty for everything the `.lnk` walk produced — and
    /// non-empty is what marks an app that can only be started by id.
    public let appUserModelID: String

    public init(shortcutPath: String, name: String, target: String,
                category: String, arguments: String, workingDirectory: String,
                appUserModelID: String = "") {
        self.shortcutPath = shortcutPath
        self.name = name
        self.target = target
        self.category = category
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.appUserModelID = appUserModelID
    }
}

public enum Win32AppCatalog {

    /// What a merge treats as "the same app": the program AND the switches it
    /// is started with.
    ///
    /// The target alone is wrong, and wrong in the direction that loses apps.
    /// Measured on the test machine, 91 Start Menu shortcuts collapse to **76**
    /// entries keyed by target and **88** keyed by target and arguments —
    /// twelve apps that simply were not in the launcher. Six of them share
    /// `cmd.exe` (Command Prompt and all five Visual Studio developer
    /// prompts), three share `wslg.exe` (every Linux app published into the
    /// Start Menu), three share the 32-bit `powershell.exe`, and each Python
    /// installation shares its `python.exe` with its own Module Docs entry.
    /// The switches are what make them different programs to a user.
    ///
    /// The duplicate this key exists to collapse — the same app installed
    /// machine-wide and per-user — still collapses, because those two
    /// shortcuts carry the same arguments as well as the same target.
    private static func identity(target: String, arguments: String,
                                 fallback: String) -> String {
        guard !target.isEmpty else { return fallback.lowercased() }
        return target.lowercased() + "\u{1}" + arguments.lowercased()
    }

    /// Both catalogs, merged and sorted by name: the two Start Menu trees
    /// de-duplicated by target so an app installed machine-wide and per-user
    /// appears once, then everything in the AppsFolder the shortcuts did not
    /// already account for.
    ///
    /// This walks a few hundred files and resolves each through COM, so it is
    /// tens of milliseconds — a startup and refresh cost, not a per-frame one.
    public static func apps() -> [Win32App] {
        var byKey: [String: Win32App] = [:]
        // Every name the shortcut walk produced, which is how an AppsFolder
        // entry is recognized as one we already have.
        var shortcutNames: Set<String> = []
        for which in Int32(0)...Int32(1) {
            guard let root = knownFolder(which) else { continue }
            for app in scan(root) {
                // Keyed by what the shortcut STARTS, program and switches
                // both (see `identity`); by shortcut path when the target
                // could not be resolved, which keeps those distinct.
                let key = identity(target: app.target, arguments: app.arguments,
                                   fallback: app.shortcutPath)
                if byKey[key] == nil { byKey[key] = app }
                shortcutNames.insert(app.name.lowercased())
            }
        }
        for entry in appsFolder() {
            guard !entry.appID.isEmpty, !entry.name.isEmpty else { continue }
            // The AppsFolder repeats every Start Menu shortcut — the same app
            // seen from the other side — so the shortcut wins: it carries a
            // target to match a window against, arguments, and the folder the
            // launcher groups by, none of which an AppsFolder entry has.
            //
            // By NAME, because the two sides share no other field: a shortcut
            // has a path and no id, and an entry here has an id and no path.
            // A collision between two genuinely different apps of the same
            // name costs one missing entry; not de-duplicating at all costs a
            // launcher listing everything twice.
            guard !shortcutNames.contains(entry.name.lowercased()) else { continue }
            guard let existing = byKey[entry.key] else {
                byKey[entry.key] = entry.app
                continue
            }
            // The same program, under a better name. Our walk names an entry
            // after its shortcut FILE — which for the old Administrative
            // Tools is "dfrgui" — while the shell names it what Windows
            // shows: "Defragment and Optimize Drives". Keep the shortcut's
            // launch data, take the shell's label, and the app stops
            // appearing twice under two names.
            byKey[entry.key] = Win32App(shortcutPath: existing.shortcutPath,
                                        name: entry.name,
                                        target: existing.target,
                                        category: existing.category,
                                        arguments: existing.arguments,
                                        workingDirectory: existing.workingDirectory,
                                        appUserModelID: existing.appUserModelID)
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
        // An app with no file behind it is started by ID: there is no
        // executable to run and no shortcut to open, and the activation
        // manager is what the Start menu itself uses.
        if !app.appUserModelID.isEmpty, app.target.isEmpty {
            return flwin32_launch_app_id(app.appUserModelID) != 0
        }
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

    /// What the user has pinned to WINDOWS' taskbar, in the order it records
    /// them: an executable path for a classic pin, an AppUserModelID for a
    /// packaged one.
    ///
    /// For seeding a fresh dock from the bar the person already has. There is
    /// no API for it — see `flwin32_taskbar_pins` for what is read — and the
    /// lines it returns are candidates rather than facts. A candidate can
    /// carry a stray leading character, so a `.lnk` is matched against the
    /// files that are ACTUALLY in the pinned folder by suffix; anything that
    /// matches nothing there is dropped rather than guessed at.
    ///
    /// Empty is an ordinary answer: a profile that has pinned nothing, or a
    /// Windows whose format has moved on.
    public static func windowsTaskbarPins() -> [String] {
        var buffer = [CChar](repeating: 0, count: 8192)
        let n = flwin32_taskbar_pins(&buffer, Int32(buffer.count))
        guard n > 0 else { return [] }
        let folder = (ProcessInfo.processInfo.environment["APPDATA"] ?? "")
            + "\\Microsoft\\Internet Explorer\\Quick Launch\\User Pinned\\TaskBar"
        let pinned = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []

        return String(cString: buffer)
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .compactMap { entry -> String? in
                guard entry.lowercased().hasSuffix(".lnk") else {
                    return entry          // an AppUserModelID, resolved by the caller
                }
                // The real file whose name this line ends with — which is how
                // `bMicrosoft Edge.lnk` becomes `Microsoft Edge.lnk` without
                // anyone deciding that the `b` looked wrong.
                guard let file = pinned.first(where: {
                    entry.lowercased().hasSuffix($0.lowercased())
                }) else { return nil }
                var target = [CChar](repeating: 0, count: 1024)
                guard flwin32_shortcut_target(folder + "\\" + file, &target,
                                              Int32(target.count)) != 0
                else { return nil }
                let path = String(cString: target)
                return path.isEmpty ? nil : path
            }
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

    /// One AppsFolder child: its AppUserModelID and what to call it.
    private struct AppsFolderEntry {
        let appID: String
        let name: String

        /// An id that IS a path is an ordinary program addressed by its own
        /// executable — the shell puts those in the AppsFolder too. Keeping
        /// it as the target means the entry matches a running window and
        /// starts without going through the shell at all.
        ///
        /// The test is a DRIVE or a UNC root, not merely a backslash, because
        /// a third shape looks like a path and is not:
        /// `{1AC14E77-…}\dfrgui.exe` is a known-folder id with a file name
        /// hung off it, and Windows 11 files most of the old Administrative
        /// Tools that way. Taken as a target it exists nowhere, so the entry
        /// draws the placeholder glyph forever (the image factory cannot
        /// resolve it either — only the full `shell:AppsFolder\…` can) while
        /// still launching, which reads as "some apps have no icon".
        var target: String {
            guard !appID.contains("!") else { return "" }
            // A KNOWN-FOLDER id is a path once it is resolved:
            // "{1AC14E77-…}\\dfrgui.exe" is System32's dfrgui.exe, and that
            // is how it matches the Start Menu shortcut for the same program.
            if appID.hasPrefix("{") {
                var buffer = [CChar](repeating: 0, count: 1024)
                let n = buffer.withUnsafeMutableBufferPointer {
                    flwin32_expand_known_folder_id(appID, $0.baseAddress, 1024)
                }
                return n > 0 ? String(cString: buffer).lowercased() : ""
            }
            let id = appID.lowercased()
            guard id.hasPrefix("\\\\") || id.dropFirst().hasPrefix(":\\") else {
                return ""
            }
            return id
        }

        /// Same identity as the shortcut walk, so an app already listed by
        /// its shortcut does not arrive a second time under its id. An entry
        /// here carries no arguments — the id IS the whole command — so it
        /// matches a shortcut that starts the same program with none.
        var key: String {
            target.isEmpty
                ? "shell:appsfolder\\" + appID.lowercased()
                : Win32AppCatalog.identity(target: target, arguments: "",
                                           fallback: appID)
        }

        /// The parsing name that opens it, used as the id and as the
        /// shell's own way in — `flwin32_launch` on this string works, which
        /// makes it a real fallback rather than a label.
        var app: Win32App {
            Win32App(shortcutPath: "shell:AppsFolder\\" + appID,
                     name: name,
                     target: target,
                     // No folder to group by: the AppsFolder is flat, exactly
                     // as Explorer's own "All apps" list is. Loose entries
                     // are what the launcher already does with a shortcut
                     // filed at the top level.
                     category: "",
                     arguments: "",
                     workingDirectory: "",
                     appUserModelID: appID)
        }
    }

    /// Everything in `shell:AppsFolder` — packaged apps, and the shell's own
    /// view of every shortcut. Asks the shell about every installed app, so
    /// it belongs off the UI thread with the rest of the catalog work.
    private static func appsFolder() -> [AppsFolderEntry] {
        guard let list = flwin32_apps_folder_list() else { return [] }
        defer { flwin32_apps_folder_free(list) }
        let count = flwin32_apps_folder_count(list)
        var out: [AppsFolderEntry] = []
        out.reserveCapacity(Int(count))
        var buffer = [CChar](repeating: 0, count: 1024)
        func field(_ index: Int32, _ which: Int32) -> String {
            let n = buffer.withUnsafeMutableBufferPointer {
                flwin32_apps_folder_field(list, index, which, $0.baseAddress, 1024)
            }
            return n > 0 ? String(cString: buffer) : ""
        }
        for index in 0..<count {
            out.append(AppsFolderEntry(appID: field(index, 0),
                                       name: field(index, 1)))
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
