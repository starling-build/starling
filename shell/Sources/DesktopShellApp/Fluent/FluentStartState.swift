// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What Start remembers, and where it gets what it shows: the user's pins,
// the view they picked for All apps, whether Recent and the account row are
// shown, the launch counts that order a category's apps, and the recent
// files list. Pure data and files — nothing here builds a widget — so the
// shell's Start builder is only layout, and this can be read in a test.

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - Preferences

/// How All apps is laid out. Windows offers the same three and remembers
/// the choice.
enum StartView: String {
    case category, grid, list
}

/// The panel's width class. `auto` picks by the screen: Windows' own 832
/// where it fits comfortably, a narrower panel on a laptop-class display.
enum StartSize: String {
    case auto, small, large
}

struct StartPrefs: Equatable {
    var view: StartView = .category
    var showRecent: Bool = true
    var showAccount: Bool = true
    var size: StartSize = .auto

    /// `key=value` lines, one per field; unknown keys are ignored so an
    /// older or hand-edited file still loads.
    static func parse(_ text: String) -> StartPrefs {
        var p = StartPrefs()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "view": p.view = StartView(rawValue: parts[1]) ?? p.view
            case "recent": p.showRecent = parts[1] != "off"
            case "account": p.showAccount = parts[1] != "off"
            case "size": p.size = StartSize(rawValue: parts[1]) ?? p.size
            default: break
            }
        }
        return p
    }

    var serialized: String {
        "view=\(view.rawValue)\nrecent=\(showRecent ? "on" : "off")\n"
            + "account=\(showAccount ? "on" : "off")\nsize=\(size.rawValue)\n"
    }
}

// MARK: - Recent files

/// One row of Recent: a file the user touched, from the desktop's shared
/// recently-used list.
struct RecentFile: Equatable {
    let path: String
    let modified: Date

    var name: String { (path as NSString).lastPathComponent }

    /// "Just now", "2h ago", "Yesterday", "3d ago", else the date.
    func ageLabel(now: Date = Date()) -> String {
        let s = now.timeIntervalSince(modified)
        if s < 60 { return "Just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        if s < 2 * 86400 { return "Yesterday" }
        if s < 14 * 86400 { return "\(Int(s / 86400))d ago" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: modified)
    }
}

// MARK: - The store

/// Start's files under the login user's config directory, and the two
/// system lists it reads. Every load tolerates absence: a fresh machine has
/// none of these and shows defaults.
enum StartStore {
    static var prefsFile: String { LoginUser.configDir + "/start" }
    static var pinsFile: String { LoginUser.configDir + "/start-pins" }
    static var launchesFile: String { LoginUser.configDir + "/launches" }

    static func loadPrefs() -> StartPrefs {
        guard let s = try? String(contentsOfFile: prefsFile, encoding: .utf8) else {
            return StartPrefs()
        }
        return StartPrefs.parse(s)
    }

    static func save(_ prefs: StartPrefs) {
        _write(prefs.serialized, to: prefsFile)
    }

    /// The pinned app ids in order, or nil when the user has never pinned or
    /// unpinned anything — every installed app is pinned then, in registry
    /// order, which is what a fresh Windows shows too.
    static func loadPins() -> [String]? {
        guard let s = try? String(contentsOfFile: pinsFile, encoding: .utf8) else { return nil }
        return s.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func save(pins: [String]) {
        _write(pins.joined(separator: "\n") + "\n", to: pinsFile)
    }

    /// `id count` per line.
    static func loadLaunchCounts() -> [String: Int] {
        guard let s = try? String(contentsOfFile: launchesFile, encoding: .utf8) else { return [:] }
        var counts: [String: Int] = [:]
        for line in s.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == 2, let n = Int(parts[1]) else { continue }
            counts[String(parts[0])] = n
        }
        return counts
    }

    static func save(launchCounts: [String: Int]) {
        let text = launchCounts.sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }.joined(separator: "\n") + "\n"
        _write(text, to: launchesFile)
    }

    /// Recently touched files, newest first, from the freedesktop
    /// recently-used list GTK and the portals keep. The list is XML; the two
    /// attributes needed are pulled by pattern, which is enough for a list
    /// and avoids an XML dependency for it. Files that no longer exist are
    /// dropped.
    static func recentFiles(limit: Int = 6, home: String = LoginUser.home) -> [RecentFile] {
        let path = home + "/.local/share/recently-used.xbel"
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return parseRecent(s, limit: limit)
    }

    static func parseRecent(_ xml: String, limit: Int, fileExists: (String) -> Bool = {
        FileManager.default.fileExists(atPath: $0) }) -> [RecentFile] {
        guard let re = try? NSRegularExpression(
            pattern: "<bookmark href=\"file://([^\"]+)\"[^>]*modified=\"([^\"]+)\"")
        else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        var out: [RecentFile] = []
        let ns = xml as NSString
        for m in re.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let href = ns.substring(with: m.range(at: 1)).removingPercentEncoding
                ?? ns.substring(with: m.range(at: 1))
            let stamp = ns.substring(with: m.range(at: 2))
            guard let date = iso.date(from: stamp) ?? plain.date(from: stamp) else { continue }
            guard fileExists(href) else { continue }
            out.append(RecentFile(path: href, modified: date))
        }
        return Array(out.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    /// App ids installed most recently, newest first: the install records
    /// under `installed.d` carry the moment an app arrived. First-party apps
    /// shipped with the desktop have no record and are never "recent".
    static func recentlyInstalled(limit: Int = 3,
                                  recordsDir: String = "/var/lib/starling/installed.d") -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: recordsDir) else { return [] }
        var stamped: [(String, Date)] = []
        for name in names where name.hasSuffix(".app") {
            let attrs = try? fm.attributesOfItem(atPath: recordsDir + "/" + name)
            let date = attrs?[.modificationDate] as? Date ?? .distantPast
            stamped.append((String(name.dropLast(4)), date))
        }
        return stamped.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    private static func _write(_ text: String, to path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
