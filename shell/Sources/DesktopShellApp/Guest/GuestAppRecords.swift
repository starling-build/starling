// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import Glibc
import StarlingRegistry

/// The apps inside a guest, as registry records — M2, Phase 5
/// (`docs/plans/guest-seamless.md`).
///
/// The helper's `apps` op is the guest's own catalog: everything Start would
/// list, packaged or not. This writes one `Kind=guest-app` record per entry
/// into `AppRegistry.guestAppsDir`, exactly as `app-install` writes a host
/// app's record into `installed.d` — temp file, rename, and the registry's
/// inotify watch lights the launcher and dock up without a relogin. Icons
/// are the guest's own, as PNGs beside the records: the user's install, not
/// artwork we ship.
///
/// It also keeps the table `GuestSeamless` needs to say which record a guest
/// WINDOW belongs to. Identity follows the desktop's standing rule — never
/// the title: a packaged window carries its AppUserModelID, which is the
/// record's launch id; a classic window is matched by executable path
/// against the known-folder-expanded id. Everything else falls under the
/// VM's own record, which is where it would have been anyway.
enum GuestAppRecords {

    struct Entry {
        let id: String
        let name: String
        /// The AppsFolder id, what `shell:AppsFolder\<target>` launches.
        let target: String
        /// The executable the id resolves to, "" for a packaged app.
        let exe: String
    }

    nonisolated(unsafe) private static var byDomain: [String: [Entry]] = [:]

    /// The record a guest window belongs to, by AppUserModelID first and
    /// executable second — or nil, in which case it is the VM's.
    static func recordId(domain: String, aumid: String, exe: String) -> String? {
        guard let entries = byDomain[domain] else { return nil }
        if !aumid.isEmpty,
           let e = entries.first(where: { $0.target.caseInsensitiveCompare(aumid) == .orderedSame }) {
            return e.id
        }
        if !exe.isEmpty,
           let e = entries.first(where: { !$0.exe.isEmpty && $0.exe.caseInsensitiveCompare(exe) == .orderedSame }) {
            return e.id
        }
        return nil
    }

    /// Write (or refresh) the records for one domain from the helper's
    /// `apps` reply, and drop the ones it no longer lists. Returns how many
    /// records the domain has now. Rewrites only what changed, so a refresh
    /// that changes nothing raises no inotify storm.
    @discardableResult
    static func update(domain: String, apps: [[String: Any]], color: UInt32) -> Int {
        let dir = AppRegistry.guestAppsDir
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var entries: [Entry] = []
        var used = Set<String>()
        var kept = Set<String>()
        for app in apps {
            guard let target = app["id"] as? String, !target.isEmpty,
                  let name = app["name"] as? String, !name.isEmpty else { continue }
            let exe = app["exe"] as? String ?? ""
            var id = "guest-\(slug(domain))-\(slug(shortName(target)))"
            var n = 2
            while used.contains(id) { id = "guest-\(slug(domain))-\(slug(shortName(target)))-\(n)"; n += 1 }
            used.insert(id)
            kept.insert(id)
            entries.append(Entry(id: id, name: name, target: target, exe: exe))

            var iconLine = ""
            if let b64 = app["icon"] as? String, let png = Data(base64Encoded: b64), !png.isEmpty {
                let iconPath = dir + "/" + id + ".png"
                if (try? Data(contentsOf: URL(fileURLWithPath: iconPath))) != png {
                    try? png.write(to: URL(fileURLWithPath: iconPath), options: .atomic)
                }
                iconLine = "Icon=\(iconPath)\n"
            }
            let body = """
                [Starling App]
                Id=\(id)
                Name=\(name)
                Kind=guest-app
                Domain=\(domain)
                Exec=\(target)
                Order=900
                Glyph=externalApp
                Color=\(String(format: "%06X", color))
                Category=Windows
                Publisher=Windows
                Subtitle=Windows app
                Description=\(name), running inside the \(domain) virtual machine and shown as a window of its own.
                \(iconLine)
                """
            let path = dir + "/" + id + ".app"
            if (try? String(contentsOfFile: path, encoding: .utf8)) == body { continue }
            // Temp then rename(2): the registry watches the directory for
            // the rename, and a reader never sees half a record. POSIX
            // rename, not Foundation's replaceItemAt — that one refuses when
            // the destination does not exist yet, which is every first write.
            let tmp = dir + "/." + id + ".\(getpid())"
            do {
                try body.write(toFile: tmp, atomically: false, encoding: .utf8)
                if Glibc.rename(tmp, path) != 0 {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
            } catch {
                try? fm.removeItem(atPath: tmp)
                FileHandle.standardError.write(Data(
                    "[guest-apps] could not write \(path): \(error)\n".utf8))
            }
        }

        // Records of this domain the guest no longer lists.
        let mine = "Domain=\(domain)"
        for file in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where file.hasSuffix(".app") {
            let id = String(file.dropLast(4))
            guard !kept.contains(id),
                  let text = try? String(contentsOfFile: dir + "/" + file, encoding: .utf8),
                  text.split(separator: "\n").contains(where: { $0 == mine })
            else { continue }
            try? fm.removeItem(atPath: dir + "/" + file)
            try? fm.removeItem(atPath: dir + "/" + id + ".png")
        }

        byDomain[domain] = entries
        return entries.count
    }

    /// What a record id is made of: the packaged family and app, or the
    /// executable's base name, or the id as it is — never the display name,
    /// which is localised and free to change.
    static func shortName(_ target: String) -> String {
        if let bang = target.firstIndex(of: "!") {
            // Microsoft.WindowsNotepad_8wekyb3d8bbwe!App -> WindowsNotepad
            var family = String(target[..<bang])
            if let us = family.firstIndex(of: "_") { family = String(family[..<us]) }
            if let dot = family.lastIndex(of: ".") { family = String(family[family.index(after: dot)...]) }
            let app = String(target[target.index(after: bang)...])
            return app.caseInsensitiveCompare("App") == .orderedSame ? family : family + "-" + app
        }
        if let slash = target.lastIndex(where: { $0 == "\\" || $0 == "/" }) {
            var base = String(target[target.index(after: slash)...])
            if let dot = base.lastIndex(of: "."), dot != base.startIndex { base = String(base[..<dot]) }
            return base
        }
        return target
    }

    static func slug(_ s: String) -> String {
        var out = ""
        var dash = false
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber, ch.isASCII {
                out.append(ch)
                dash = false
            } else if !dash, !out.isEmpty {
                out.append("-")
                dash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        if out.count > 48 { out = String(out.prefix(48)) }
        return out.isEmpty ? "app" : out
    }
}
#endif
