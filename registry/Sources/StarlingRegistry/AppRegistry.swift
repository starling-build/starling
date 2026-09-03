// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if canImport(Glibc)
import Glibc
#endif

/// The desktop's app registry — the single answer to "what apps are there,
/// which are installed, and which window belongs to which".
///
/// Two directories back it:
///
///   `catalog.d/`    shipped with the desktop, read-only. One record per app
///                   Starling knows about, installed or not: name, tile
///                   colour, store copy, how to install it, how to launch it.
///
///   `installed.d/`  written by `app-install` the moment an install succeeds,
///                   removed when it is uninstalled. Carries what is only
///                   knowable once the app is on disk: its `.desktop` entry,
///                   the window class it reports, its icon, its version.
///
/// The shell reads both and watches them, so an install lights up the
/// launcher without a relogin. Nothing writes back except `app-install` —
/// the user's dock arrangement is separate state and belongs to the shell.
public final class AppRegistry: @unchecked Sendable {

    public static let shared = AppRegistry()

    /// Resolves a first-party app's executable name to a path. Injected by
    /// the shell, which knows the staged/dev/packaged layouts; without it a
    /// first-party record falls back to FLUTTER_APPS_DIR alone (which is what
    /// the App Store needs, and all it has).
    public var firstPartyResolver: (@Sendable (String) -> String?)?

    private let lock = NSLock()
    private var _apps: [AppRecord] = []
    private var _loaded = false

    private init() {}

    // MARK: - Locations

    /// The shipped catalog. `$STARLING_CATALOG_DIR` overrides; otherwise the
    /// staged/installed layout is found relative to the running binary, which
    /// works for the shell (`lib/DesktopShellApp`) and for child apps
    /// (`lib/apps/AppStoreApp`) without either knowing where it was staged.
    public static var catalogDir: String {
        let env = ProcessInfo.processInfo.environment
        if let d = env["STARLING_CATALOG_DIR"], !d.isEmpty { return d }
        var candidates: [String] = []
        if let data = env["STARLING_DATA_DIR"], !data.isEmpty {
            candidates.append(data + "/catalog.d")
        }
        if let selfDir = executableDir {
            candidates.append(selfDir + "/../share/catalog.d")
            candidates.append(selfDir + "/../../share/catalog.d")
            // Repo dev tree: <repo>/registry/catalog.d, from a .build dir.
            var dir = selfDir
            for _ in 0..<8 {
                candidates.append(dir + "/registry/catalog.d")
                dir = (dir as NSString).deletingLastPathComponent
                if dir.isEmpty || dir == "/" { break }
            }
        }
        candidates.append("/usr/share/starling/catalog.d")
        let fm = FileManager.default
        for c in candidates {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: c, isDirectory: &isDir), isDir.boolValue {
                return (c as NSString).standardizingPath
            }
        }
        return "/usr/share/starling/catalog.d"
    }

    /// Where `app-install` records what it installed. System-wide, because
    /// the install is: apt put the app in /opt or /usr for every user.
    public static var installedDir: String {
        let env = ProcessInfo.processInfo.environment
        if let d = env["STARLING_APP_RECORDS"], !d.isEmpty { return d }
        return "/var/lib/starling/installed.d"
    }

    /// `path` if it exists, else the closest ancestor that does (never past
    /// "/", which always exists).
    static func nearestExisting(_ path: String) -> String {
        let fm = FileManager.default
        var p = path
        while p != "/" && !p.isEmpty {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
                return p
            }
            p = (p as NSString).deletingLastPathComponent
        }
        return "/"
    }

    private static var executableDir: String? {
        #if canImport(Glibc)
        guard let real = realpath("/proc/self/exe", nil) else { return nil }
        defer { free(real) }
        return (String(cString: real) as NSString).deletingLastPathComponent
        #else
        return Bundle.main.executablePath.map {
            ($0 as NSString).deletingLastPathComponent
        }
        #endif
    }

    // MARK: - Loading

    public var apps: [AppRecord] {
        lock.lock()
        defer { lock.unlock() }
        if !_loaded { loadLocked() }
        return _apps
    }

    /// Installed apps in launcher order.
    public var installedApps: [AppRecord] {
        apps.filter { $0.installed }
    }

    /// The default dock, in the order the catalog declares — filtered to what
    /// is actually installed, because a dock tile that launches nothing is
    /// worse than an absent one.
    public var defaultDock: [AppRecord] {
        apps.filter { $0.dockOrder != nil && $0.installed }
            .sorted { ($0.dockOrder ?? 0) < ($1.dockOrder ?? 0) }
    }

    public func app(id: String) -> AppRecord? {
        apps.first { $0.id == id }
    }

    /// The app a window belongs to, from the `app_id` it reported over
    /// `xdg_toplevel.set_app_id`.
    public func app(forAppId appId: String) -> AppRecord? {
        apps.first { $0.matches(appId: appId) }
    }

    /// The app a window belongs to, by title — only for records that declare
    /// `TitleMatch`, i.e. the windows that carry no usable app_id at all.
    public func app(forTitle title: String) -> AppRecord? {
        apps.first { $0.matches(title: title) }
    }

    public func reload() {
        lock.lock()
        defer { lock.unlock() }
        loadLocked()
    }

    private func loadLocked() {
        _loaded = true
        let fm = FileManager.default
        let catalog = Self.catalogDir
        let installedDir = Self.installedDir
        let files = (try? fm.contentsOfDirectory(atPath: catalog))?
            .filter { $0.hasSuffix(".app") }
            .sorted() ?? []

        var out: [AppRecord] = []
        for file in files {
            guard let kf = KeyFile(path: catalog + "/" + file, group: "Starling App")
            else { continue }
            let id = kf.string("Id")
                ?? String(file.dropLast(".app".count))
            let installedRecord = KeyFile(
                path: installedDir + "/" + id + ".app", group: "Starling App")
            out.append(makeRecord(id: id, catalog: kf, installed: installedRecord))
        }
        out.sort {
            $0.order != $1.order ? $0.order < $1.order : $0.name < $1.name
        }
        _apps = out
    }

    private func makeRecord(id: String, catalog kf: KeyFile,
                            installed rec: KeyFile?) -> AppRecord {
        let kind = AppRecord.Kind(rawValue: kf.string("Kind") ?? "host") ?? .host
        let exec = kf.string("Exec") ?? id
        let bins = kf.list("Bins")
        let desktopEntries = kf.list("DesktopEntry")

        // Installed by us: the record exists, and its facts win — they were
        // resolved against the real install rather than guessed.
        let recorded = rec != nil
        var wmClasses = kf.list("WmClass")
        if let w = rec?.string("WmClass") { wmClasses.insert(w, at: 0) }
        // Catalog `Icon` is the last-resort hint, for apps that ship neither a
        // `.desktop` entry nor a theme icon (IntelliJ's tarball drops one at
        // /opt/idea/bin/idea.png and registers nothing).
        var iconPath = rec?.string("Icon") ?? kf.string("Icon")
        var desktopFile = rec?.string("DesktopFile")

        // Installed outside the store (`apt install gimp` by hand) — no
        // record, so fall back to the same freedesktop lookup app-install
        // would have done. Costs a few stats per app at load; the alternative
        // is an app that works but has no icon and no dock identity.
        let presentOnDisk = Self.probe(kind: kind, exec: exec, bins: bins,
                                       resolver: firstPartyResolver)
        if !recorded, presentOnDisk, !desktopEntries.isEmpty,
           let resolved = DesktopEntry.resolve(entries: desktopEntries) {
            desktopFile = resolved.desktopFile.isEmpty ? nil : resolved.desktopFile
            iconPath = resolved.iconPath ?? iconPath
            wmClasses.insert(resolved.wmClass, at: 0)
        }
        // Never hand out a path that isn't there — the shell would attempt a
        // decode per launch and fall back to the glyph anyway.
        if let p = iconPath, !FileManager.default.fileExists(atPath: p) {
            iconPath = nil
        }

        // Every id a window of this app might report: what the host declared,
        // the catalog's fallbacks, the `.desktop` basenames (a client that
        // sets no explicit class reports its desktop id), and finally our own
        // app id.
        // Dedup on the literal id only: matching is tolerant of the .desktop
        // suffix on its own, so collapsing the two forms here would drop a
        // candidate for no gain.
        var appIds = wmClasses + desktopEntries + [id]
        var seen = Set<String>()
        appIds = appIds.filter { seen.insert($0.lowercased()).inserted }

        return AppRecord(
            id: id,
            name: kf.string("Name") ?? id,
            kind: kind,
            order: kf.int("Order") ?? 999,
            glyph: kf.string("Glyph") ?? "externalApp",
            color: kf.rgb("Color") ?? 0x5C8FD6,
            dockOrder: kf.int("Dock"),
            category: kf.string("Category") ?? "",
            publisher: kf.string("Publisher") ?? "",
            subtitle: kf.string("Subtitle") ?? "",
            sizeLabel: kf.string("Size") ?? "",
            details: kf.string("Description") ?? "",
            exec: exec,
            windowRect: Self.geometry(kf.string("Window")),
            installRecipe: kf.string("Install"),
            bins: bins,
            desktopEntries: desktopEntries,
            wmClasses: wmClasses,
            titleMatches: kf.list("TitleMatch"),
            renameWindows: kf.string("RenameWindows") == "1",
            discreteGpu: kf.string("Gpu") == "discrete",
            agentApp: kf.string("Agent") == "1",
            debURL: kf.string("DebUrl"),
            debMarker: kf.string("DebMarker"),
            desktopFile: desktopFile,
            iconPath: iconPath,
            version: rec?.string("Version"),
            installedAt: rec?.int("InstalledAt"),
            installed: recorded || presentOnDisk,
            appIds: appIds,
            urlSchemes: kf.list("UrlSchemes"),
            domain: kf.string("Domain"))
    }

    /// `Window=x,y,w,h` — where a first-party app's window opens.
    static func geometry(_ value: String?) -> AppRecord.WindowGeometry? {
        guard let parts = value?.split(separator: ","), parts.count == 4,
              let v = try? parts.map({ (p: Substring) -> Double in
                  guard let d = Double(p.trimmingCharacters(in: .whitespaces))
                  else { throw CocoaError(.formatting) }
                  return d
              })
        else { return nil }
        return AppRecord.WindowGeometry(x: v[0], y: v[1], width: v[2], height: v[3])
    }

    // MARK: - Running apps

    /// Which installed apps currently have a process, by resolving every
    /// `/proc/<pid>/exe` and matching it against each record's `Bins`.
    ///
    /// Process-based rather than window-based on purpose. The shell knows
    /// which apps have *windows*, but it is a different process from the App
    /// Store and there is no channel between them — and "has a window" is the
    /// weaker question anyway. An Electron app with its window closed still
    /// has a zygote holding files open; removing the package out from under it
    /// is how you get a half-uninstalled app.
    ///
    /// Matching on the exe symlink, not on command-line text: `pgrep -f`-style
    /// matching finds its own shell (the same trap that makes `pkill -f` unsafe
    /// here — see CLAUDE.md) and would match any window title or argument that
    /// happens to contain the name.
    public func runningAppIds() -> Set<String> {
        runningAppIds(given: Self.runningExecutables())
    }

    /// The matching half, split out from the /proc scan so it can be tested
    /// without spawning processes.
    func runningAppIds(given running: Set<String>) -> Set<String> {
        guard !running.isEmpty else { return [] }
        var out: Set<String> = []
        for app in apps where app.installed {
            // Both forms: /usr/bin/gimp is a symlink to gimp-3.2, and which
            // one the kernel reports depends on which the launcher exec'd.
            let hit = app.bins.contains {
                running.contains($0) || running.contains(Self.resolve($0))
            }
            if hit { out.insert(app.id) }
        }
        return out
    }

    /// A process whose binary was replaced or deleted has its exe reported as
    /// `/path/to/bin (deleted)`. It is still that app — and an app whose files
    /// just went away is exactly what must not be missed.
    static func stripDeleted(_ path: String) -> String {
        path.hasSuffix(" (deleted)")
            ? String(path.dropLast(" (deleted)".count)) : path
    }

    /// Every distinct executable behind a live process we can see. One pass
    /// over /proc, so the cost does not scale with the size of the catalog.
    ///
    /// Processes belonging to other users simply do not resolve (EACCES) and
    /// drop out, which is the right answer: the store and the apps it launches
    /// run as the same user.
    static func runningExecutables() -> Set<String> {
        #if canImport(Glibc)
        guard let pids = try? FileManager.default
            .contentsOfDirectory(atPath: "/proc") else { return [] }
        var out: Set<String> = []
        var buf = [CChar](repeating: 0, count: 4096)
        for pid in pids where UInt32(pid) != nil {
            // readlink, not realpath: a process whose binary was replaced or
            // deleted reports "/path/to/bin (deleted)", which realpath cannot
            // canonicalize because the path is gone. That process is still
            // the app — and an app whose files just went away is exactly what
            // we must not miss.
            let n = readlink("/proc/\(pid)/exe", &buf, buf.count - 1)
            guard n > 0 else { continue }
            buf[n] = 0
            out.insert(stripDeleted(String(cString: buf)))
        }
        return out
        #else
        return []
        #endif
    }

    /// A catalog `Bins` path as the kernel would report it — `/proc/<pid>/exe`
    /// is already fully resolved, so the candidate has to be too or a
    /// symlinked launcher (`/usr/bin/code`) never matches.
    static func resolve(_ path: String) -> String {
        #if canImport(Glibc)
        if let real = realpath(path, nil) {
            defer { free(real) }
            return String(cString: real)
        }
        #endif
        return path
    }

    /// "Is it on disk?" — the fallback for apps the store did not install.
    static func probe(kind: AppRecord.Kind, exec: String, bins: [String],
                      resolver: (@Sendable (String) -> String?)?) -> Bool {
        let fm = FileManager.default
        switch kind {
        case .firstParty:
            if let resolver { return resolver(exec) != nil }
            if let dir = ProcessInfo.processInfo.environment["FLUTTER_APPS_DIR"] {
                return fm.fileExists(atPath: dir + "/" + exec)
            }
            return false
        case .android:
            // One install serves every Android entry.
            return ["/usr/bin/waydroid", "/usr/local/bin/waydroid"]
                .contains { fm.isExecutableFile(atPath: $0) }
        case .host, .x11, .vm:
            // For a VM this is only "is libvirt here" (Bins=/usr/bin/virsh).
            // Whether the domain exists is the launch arm's answer, in the
            // shell, where a missing one can be said out loud — the registry
            // package must not link libvirt, because the App Store loads it
            // too.
            return bins.contains { fm.isExecutableFile(atPath: $0) }
        }
    }

    // MARK: - Change notification

    #if canImport(Glibc)
    private var watchFd: Int32 = -1
    private var watchSource: DispatchSourceRead?

    /// Watch both directories and call `onChange` (on `queue`) whenever a
    /// record appears, changes or goes away — an App Store install shows up in
    /// the launcher and dock without a relogin.
    ///
    /// The watch is on the directories, not the files: `app-install` writes a
    /// record by creating a temp file and renaming it into place (so a reader
    /// never sees half a record), and a rename is a directory event.
    public func watch(queue: DispatchQueue = .main,
                      onChange: @escaping @Sendable () -> Void) {
        guard watchSource == nil else { return }
        let fd = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
        guard fd >= 0 else { return }

        let mask = UInt32(IN_CREATE | IN_DELETE | IN_MOVED_TO | IN_MOVED_FROM
                          | IN_CLOSE_WRITE)
        // installed.d may not exist yet — nothing has been installed through
        // the store, and the shell (running as the session user) cannot create
        // it under /var/lib. Watching the nearest ancestor that DOES exist
        // means the first install is still noticed: creating the directory is
        // itself an event there, and the handler re-adds the watch.
        //
        // That ancestor can be somewhere busy like /var/lib, so this may see
        // unrelated churn for a while — harmless (a reload is 22 small files)
        // and self-correcting, since the watch narrows to installed.d on the
        // first event. The .deb ships the directory, so a packaged install
        // never takes this path at all.
        for dir in [Self.catalogDir, Self.nearestExisting(Self.installedDir)] {
            _ = inotify_add_watch(fd, dir, mask)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Drain: one setState per burst, not per event. An install
            // touches several files and we only care that something moved.
            var buf = [UInt8](repeating: 0, count: 8192)
            while read(fd, &buf, buf.count) > 0 {}
            // A directory created since the last event only becomes watchable
            // now. inotify_add_watch on a path already watched just updates
            // the existing watch, so this is safe to repeat.
            _ = inotify_add_watch(fd, Self.nearestExisting(Self.installedDir), mask)
            self.reload()
            onChange()
        }
        source.setCancelHandler { close(fd) }
        watchFd = fd
        watchSource = source
        source.resume()
    }
    #endif
}
