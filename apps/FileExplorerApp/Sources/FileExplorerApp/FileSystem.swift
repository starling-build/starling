// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if os(Linux)
import Glibc
#endif

// MARK: - FileEntry

/// Represents a file or directory entry with metadata.
struct FileEntry {
    let name: String
    let path: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: UInt64
    let modified: Date
    let permissions: String
    let owner: String

    /// File extension (lowercase, without dot). Empty for directories.
    var fileExtension: String {
        guard !isDirectory else { return "" }
        let ext = (name as NSString).pathExtension
        return ext.lowercased()
    }

    /// Icon character based on file type.
    var icon: String {
        if isDirectory { return "\u{1F4C1}" }  // 📁
        switch fileExtension {
        case "swift", "c", "cc", "cpp", "h", "py", "js", "ts", "rs", "go", "java", "rb", "sh":
            return "\u{1F4DD}"  // 📝 source code
        case "txt", "md", "json", "xml", "yaml", "yml", "toml", "ini", "cfg", "conf", "log":
            return "\u{1F4C4}"  // 📄 text
        case "png", "jpg", "jpeg", "gif", "bmp", "svg", "ico", "webp":
            return "\u{1F5BC}"  // 🖼 image
        case "mp3", "wav", "flac", "aac", "ogg", "m4a":
            return "\u{1F3B5}"  // 🎵 audio
        case "mp4", "mkv", "avi", "mov", "webm":
            return "\u{1F3AC}"  // 🎬 video
        case "zip", "tar", "gz", "bz2", "xz", "7z", "rar", "deb", "rpm":
            return "\u{1F4E6}"  // 📦 archive
        case "pdf":
            return "\u{1F4D1}"  // 📑 pdf
        case "so", "dylib", "a", "o":
            return "\u{2699}"   // ⚙ library
        default:
            return "\u{1F4C4}"  // 📄 generic file
        }
    }
}

// MARK: - SortColumn / SortOrder

enum SortColumn {
    case name
    case size
    case modified
    case type
}

enum SortOrder {
    case ascending
    case descending

    var toggled: SortOrder {
        return self == .ascending ? .descending : .ascending
    }

    var arrow: String {
        return self == .ascending ? " \u{25B2}" : " \u{25BC}"
    }
}

// MARK: - FileSystem

/// File system operations for the file explorer.
struct FileSystem {

    /// List contents of a directory.
    static func listDirectory(_ path: String, showHidden: Bool = false) -> [FileEntry] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            return []
        }

        var entries: [FileEntry] = []
        for name in contents {
            if !showHidden && name.hasPrefix(".") { continue }

            let fullPath = (path as NSString).appendingPathComponent(name)

            // Check symlink before resolving
            var isSymlink = false
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let type = attrs[.type] as? FileAttributeType {
                isSymlink = (type == .typeSymbolicLink)
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            var size: UInt64 = 0
            var modified = Date()
            var perms = ""
            var owner = ""

            if let attrs = try? fm.attributesOfItem(atPath: fullPath) {
                size = attrs[.size] as? UInt64 ?? 0
                modified = attrs[.modificationDate] as? Date ?? Date()
                if let posix = attrs[.posixPermissions] as? Int {
                    perms = _formatPermissions(posix, isDir: isDir.boolValue)
                }
                owner = attrs[.ownerAccountName] as? String ?? ""
            }

            entries.append(FileEntry(
                name: name,
                path: fullPath,
                isDirectory: isDir.boolValue,
                isSymlink: isSymlink,
                size: size,
                modified: modified,
                permissions: perms,
                owner: owner
            ))
        }

        return entries
    }

    /// Sort entries: directories first, then by given column and order.
    static func sort(_ entries: [FileEntry], by column: SortColumn, order: SortOrder) -> [FileEntry] {
        return entries.sorted { a, b in
            // Directories always come first
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }

            let result: Bool
            switch column {
            case .name:
                result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .size:
                result = a.size < b.size
            case .modified:
                result = a.modified < b.modified
            case .type:
                let extA = a.fileExtension
                let extB = b.fileExtension
                if extA == extB {
                    result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                } else {
                    result = extA < extB
                }
            }

            return order == .ascending ? result : !result
        }
    }

    /// Filter entries by search query (case-insensitive name match).
    static func filter(_ entries: [FileEntry], query: String) -> [FileEntry] {
        guard !query.isEmpty else { return entries }
        let lower = query.lowercased()
        return entries.filter { $0.name.lowercased().contains(lower) }
    }

    // MARK: - File Operations

    /// Create a new directory. Returns nil on success, error message on failure.
    static func createDirectory(at path: String, name: String) -> String? {
        let fullPath = (path as NSString).appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(atPath: fullPath, withIntermediateDirectories: false)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Rename a file or directory. Returns nil on success, error message on failure.
    static func rename(at path: String, to newName: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        let newPath = (parent as NSString).appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(atPath: path, toPath: newPath)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Delete a file or directory. Returns nil on success, error message on failure.
    static func delete(at path: String) -> String? {
        do {
            try FileManager.default.removeItem(atPath: path)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Copy, move and their conflicts
    //
    // Windows does all of this through one shell interface (IFileOperation),
    // which brings the progress window, the replace/skip/keep-both dialog,
    // the recycle bin and an undo stack with it. Linux has no such shared
    // engine — every file manager writes its own — so this is ours, and it
    // is deliberately the small honest subset: copy, move, and the three
    // answers Windows offers when a name is already taken.

    /// What to do when the destination already holds that name. Windows'
    /// own three, in its words.
    enum ConflictPolicy {
        /// Overwrite what is there.
        case replace
        /// Keep both, the new one renamed "report (2).txt".
        case keepBoth
        /// Leave the destination alone and move on.
        case skip
    }

    /// The names among `paths` that already exist in `directory` — what the
    /// conflict dialog asks about, computed before anything is written.
    static func conflicts(_ paths: [String], in directory: String) -> [String] {
        let fm = FileManager.default
        return paths.compactMap { path in
            let name = (path as NSString).lastPathComponent
            let dest = (directory as NSString).appendingPathComponent(name)
            // Pasting a copy back into the same folder is not a conflict with
            // itself; it is the ordinary "make me a second copy" case.
            if dest == path { return nil }
            return fm.fileExists(atPath: dest) ? name : nil
        }
    }

    /// Explorer's keep-both name: "report.txt" becomes "report (2).txt", and
    /// keeps counting while the name is taken. A dotfile has no extension to
    /// preserve, so the number goes on the end.
    static func uniqueName(for name: String, in directory: String) -> String {
        let fm = FileManager.default
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ext.isEmpty || name.hasPrefix(".") ? name : ns.deletingPathExtension
        let suffix = ext.isEmpty || name.hasPrefix(".") ? "" : ".\(ext)"
        var n = 2
        while true {
            let candidate = "\(stem) (\(n))\(suffix)"
            let path = (directory as NSString).appendingPathComponent(candidate)
            if !fm.fileExists(atPath: path) { return candidate }
            n += 1
            // A folder with two thousand "(n)" copies in it is a bug
            // somewhere else; stop rather than spin.
            if n > 2000 { return candidate }
        }
    }

    /// Whether new files can be created in `directory`.
    static func isWritable(_ path: String) -> Bool {
        FileManager.default.isWritableFile(atPath: path)
    }

    /// Where `path` lands in `directory` under `policy`, or nil to skip.
    /// Removes what is in the way for `.replace`.
    private static func _destination(_ path: String, in directory: String,
                                     policy: ConflictPolicy) throws -> String? {
        let fm = FileManager.default
        let name = (path as NSString).lastPathComponent
        var dest = (directory as NSString).appendingPathComponent(name)
        // Copying something back into the folder it is already in always
        // keeps both — there is nothing else it could mean.
        if dest == path {
            return (directory as NSString)
                .appendingPathComponent(uniqueName(for: name, in: directory))
        }
        guard fm.fileExists(atPath: dest) else { return dest }
        switch policy {
        case .skip:
            return nil
        case .keepBoth:
            dest = (directory as NSString)
                .appendingPathComponent(uniqueName(for: name, in: directory))
        case .replace:
            try fm.removeItem(atPath: dest)
        }
        return dest
    }

    /// A folder cannot be copied into itself or into its own subtree —
    /// Windows refuses this too, and without the check the copy walks into
    /// what it is writing and never finishes.
    private static func _isInside(_ directory: String, _ path: String) -> Bool {
        directory == path || directory.hasPrefix(path.hasSuffix("/") ? path : path + "/")
    }

    /// Copy `path` into `directory`. nil on success, a message on failure.
    static func copy(_ path: String, into directory: String,
                     policy: ConflictPolicy) -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            return "\((path as NSString).lastPathComponent) no longer exists"
        }
        if isDir.boolValue, _isInside(directory, path) {
            return "A folder cannot be copied into itself"
        }
        do {
            guard let dest = try _destination(path, in: directory, policy: policy) else {
                return nil  // skipped
            }
            try FileManager.default.copyItem(atPath: path, toPath: dest)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Move `path` into `directory` — a cut, pasted. nil on success.
    ///
    /// `moveItem` is a rename within one filesystem and a copy across two,
    /// which is what makes a cut from an SD card work at all.
    static func move(_ path: String, into directory: String,
                     policy: ConflictPolicy) -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            return "\((path as NSString).lastPathComponent) no longer exists"
        }
        if isDir.boolValue, _isInside(directory, path) {
            return "A folder cannot be moved into itself"
        }
        // Cutting and pasting into the same folder is a no-op, not a copy.
        if (path as NSString).deletingLastPathComponent == directory { return nil }
        do {
            guard let dest = try _destination(path, in: directory, policy: policy) else {
                return nil
            }
            try FileManager.default.moveItem(atPath: path, toPath: dest)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Check if path is readable.
    static func isReadable(_ path: String) -> Bool {
        return FileManager.default.isReadableFile(atPath: path)
    }

    /// Free space (bytes) on the filesystem containing `path`, or nil if unavailable.
    static func freeSpace(at path: String) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let free = attrs[.systemFreeSize] as? NSNumber else {
            return nil
        }
        return free.uint64Value
    }

    // MARK: - Formatting

    static func formatSize(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024.0
        return String(format: "%.1f GB", gb)
    }

    /// Finder-style date: "Today at 14:32", "Yesterday at 09:15", "6 Jul 2026 at 14:32".
    static func formatDate(_ date: Date) -> String {
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today at " + time.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday at " + time.string(from: date)
        }
        let df = DateFormatter()
        df.dateFormat = "d MMM yyyy 'at' HH:mm"
        return df.string(from: date)
    }

    static func parentPath(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    static func pathComponents(_ path: String) -> [(name: String, path: String)] {
        var components: [(name: String, path: String)] = []
        var current = path
        while current != "/" && !current.isEmpty {
            let name = (current as NSString).lastPathComponent
            components.insert((name: name, path: current), at: 0)
            current = (current as NSString).deletingLastPathComponent
        }
        components.insert((name: "/", path: "/"), at: 0)
        return components
    }

    // MARK: - Private

    private static func _formatPermissions(_ mode: Int, isDir: Bool) -> String {
        var s = isDir ? "d" : "-"
        let flags = ["r", "w", "x"]
        for i in (0..<3).reversed() {
            let shift = i * 3
            for j in 0..<3 {
                s += (mode >> (shift + 2 - j)) & 1 != 0 ? flags[j] : "-"
            }
        }
        return s
    }
}
