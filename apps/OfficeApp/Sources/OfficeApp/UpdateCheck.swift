// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// "A newer Starling Office is available": the native app asks GitHub, at most
// once a day and off the main thread, whether the repo has an office-vX.Y.Z
// release newer than the running one. Any failure is silent. The browser
// build never checks (it is always current): everything that touches the
// network or a process is compiled out on WASI.

import Flutter
import FlutterSwiftBridge
import Foundation

/// A release of Starling Office on GitHub.
struct OfficeRelease: Equatable {
    let version: String
    let url: String
}

enum OfficeVersion {
    /// "1.2.3" → [1, 2, 3]. Nil for anything that is not dotted numbers
    /// ("dev", "", "0.5.0-rc1"): such a version is never compared.
    static func parse(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var out: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let n = Int(p) else { return nil }
            out.append(n)
        }
        return out
    }

    /// Numeric, part by part ("0.10.0" > "0.9.0"); a missing part is 0.
    static func isNewer(_ a: String, than b: String) -> Bool {
        guard let x = parse(a), let y = parse(b) else { return false }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// A stamped release version is worth checking; an unstamped, "dev" or
    /// all-zero one is a development build and never nags.
    static func isCheckable(_ version: String?) -> Bool {
        guard let v = version, let p = parse(v) else { return false }
        return p.contains { $0 != 0 }
    }

    /// The running app's version, or nil for a development build. Packagers
    /// stamp it one of three ways: the macOS bundle's CFBundleShortVersionString,
    /// the STARLING_OFFICE_VERSION environment variable, or an `office-version`
    /// file beside the executable (the .deb and Flatpak).
    static var current: String? {
        #if os(WASI)
        return nil
        #else
        if let v = ProcessInfo.processInfo.environment["STARLING_OFFICE_VERSION"], isCheckable(v) { return v }
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, isCheckable(v) { return v }
        var exe = CommandLine.arguments.first ?? ""
        #if os(Linux)
        if let real = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe") { exe = real }
        #endif
        let dir = exe.deletingLastPathComponent
        for file in [dir + "/office-version", dir + "/../Resources/office-version"] {
            if let text = try? String(contentsOfFile: file, encoding: .utf8) {
                let v = text.trimmingWhitespace()
                if isCheckable(v) { return v }
            }
        }
        return nil
        #endif
    }
}

/// Where the check keeps its state. The app's settings file in practice; a
/// dictionary in tests.
protocol UpdateStore: AnyObject {
    func get(_ key: String) -> String?
    func set(_ key: String, _ value: String)
}

final class UpdateCheck {
    static let releasesURL = "https://api.github.com/repos/starling-build/starling/releases?per_page=30"
    static let interval: Double = 24 * 60 * 60
    static let lastCheckKey = "update.lastCheck"
    static let lastSeenKey = "update.lastSeen"
    static let dismissedKey = "update.dismissed"

    /// The newest published office-v release in GitHub's releases JSON:
    /// drafts and prereleases skipped, other products' tags ignored, highest
    /// by number (not by list order or date).
    static func newest(inJSON data: Data) -> OfficeRelease? {
        #if os(WASI)
        return nil
        #else
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        var best: OfficeRelease? = nil
        for r in list {
            guard let tag = r["tag_name"] as? String, tag.hasPrefix("office-v") else { continue }
            if (r["draft"] as? Bool) == true || (r["prerelease"] as? Bool) == true { continue }
            let v = String(tag.dropFirst("office-v".count))
            guard OfficeVersion.parse(v) != nil else { continue }
            let url = (r["html_url"] as? String) ?? "https://github.com/starling-build/starling/releases/tag/\(tag)"
            if best == nil || OfficeVersion.isNewer(v, than: best!.version) { best = OfficeRelease(version: v, url: url) }
        }
        return best
        #endif
    }

    /// At most one check a day. A clock that went backwards counts as due.
    static func isDue(lastCheck: Double?, now: Double) -> Bool {
        guard let last = lastCheck else { return true }
        return now < last || now - last >= interval
    }

    /// The release to announce, if any: newer than `current`, and not the
    /// one the user dismissed (or an older one).
    static func announced(_ release: OfficeRelease?, current: String?, dismissed: String?) -> OfficeRelease? {
        guard let r = release, OfficeVersion.isCheckable(current),
              OfficeVersion.isNewer(r.version, than: current!) else { return nil }
        if let d = dismissed, !OfficeVersion.isNewer(r.version, than: d) { return nil }
        return r
    }

    /// One pass, synchronously: the stored sighting is announced at once; if a
    /// check is due, `fetch` runs, and its answer is stored and announced.
    /// `fetch` throws on any failure, which only skips today's check. Not
    /// called on the main thread by the app (see `start`).
    static func run(current: String?, store: UpdateStore, now: () -> Double,
                    fetch: () throws -> Data, log: (String) -> Void = { _ in }) -> OfficeRelease? {
        guard OfficeVersion.isCheckable(current) else { return nil }
        let dismissed = store.get(dismissedKey)
        let last = store.get(lastCheckKey).flatMap { Double($0) }
        var seen = store.get(lastSeenKey).map { OfficeRelease(version: $0, url: store.get(lastSeenKey + ".url") ?? "") }
        if isDue(lastCheck: last, now: now()) {
            do {
                let data = try fetch()
                store.set(lastCheckKey, String(Int(now())))
                if let r = newest(inJSON: data) {
                    store.set(lastSeenKey, r.version)
                    store.set(lastSeenKey + ".url", r.url)
                    seen = r
                }
            } catch {
                log("update check failed: \(error)")
            }
        }
        return announced(seen, current: current, dismissed: dismissed)
    }

    static func dismiss(_ release: OfficeRelease, store: UpdateStore) {
        store.set(dismissedKey, release.version)
    }

    /// The app's entry: runs the check on a background thread and calls
    /// `found` on the main queue only when there is something to announce.
    /// Nothing happens in the browser build or a development build.
    static func start(found: @escaping (OfficeRelease) -> Void) {
        #if !os(WASI)
        guard OfficeVersion.isCheckable(OfficeVersion.current) else { return }
        let current = OfficeVersion.current
        DispatchQueue.global(qos: .utility).async {
            let r = run(current: current, store: SettingsUpdateStore(),
                        now: { Date().timeIntervalSince1970 }, fetch: curlFetch,
                        log: { fputs("[office] " + $0 + "\n", stderr) })
            if let r { DispatchQueue.main.async { found(r) } }
        }
        #endif
    }

    #if !os(WASI)
    struct FetchError: Error { let reason: String }

    /// GET the releases list with curl (on macOS, Linux and Windows 10+),
    /// with a short timeout. Throws on any failure.
    static func curlFetch() throws -> Data {
        let tool = ["/usr/bin/curl", "/bin/curl", "/usr/local/bin/curl", "/opt/homebrew/bin/curl",
                    "C:\\Windows\\System32\\curl.exe"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let tool else { throw FetchError(reason: "no curl") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["-fsSL", "--max-time", "15", "-H", "Accept: application/vnd.github+json",
                       "-H", "User-Agent: starling-office", releasesURL]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw FetchError(reason: "curl exit \(p.terminationStatus)") }
        return data
    }

    /// Opens the page in the system browser.
    static func openInBrowser(_ url: String) {
        guard url.hasPrefix("https://") else { return }
        let p = Process()
        #if os(macOS)
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [url]
        #elseif os(Windows)
        p.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\rundll32.exe")
        p.arguments = ["url.dll,FileProtocolHandler", url]
        #else
        guard let tool = ["/usr/bin/xdg-open", "/bin/xdg-open"].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return }
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = [url]
        #endif
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
    #endif
}

/// The notice itself: a slim, dismissible bar at the top of the window.
final class UpdateNoticeBar: StatelessWidget {
    let release: OfficeRelease
    let onDismiss: () -> Void
    init(release: OfficeRelease, onDismiss: @escaping () -> Void) {
        self.release = release
        self.onDismiss = onDismiss
        super.init()
    }
    override func build(_ context: any BuildContext) -> Widget {
        InfoBar(
            title: Text("Starling Office \(release.version) is available"),
            action: HyperlinkButton(
                onPressed: { [release] in
                    #if !os(WASI)
                    UpdateCheck.openInBrowser(release.url)
                    #endif
                },
                child: Text("Download")),
            onClose: onDismiss)
    }
}
