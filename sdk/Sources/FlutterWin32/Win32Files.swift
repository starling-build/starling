// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Reading a directory, and the places worth starting from.
//
// The enumeration is Foundation's — `FileManager` walks a directory perfectly
// well on Windows, and reimplementing FindFirstFileW around it would buy
// nothing. What Foundation does NOT have is the shell's view: where
// "Downloads" actually is on a machine where the user moved it, and what
// Explorer calls a file type. Those come from `flwin32_files.c`.
//
// Everything here touches the disk, so all of it belongs on a background
// task. A directory of ten thousand files is not rare and not fast.

#if os(Windows)
import FlutterWin32Bridge
import Foundation

/// One row in a listing.
public struct Win32FileEntry: Sendable, Equatable, Identifiable {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let modified: Date?
    /// Lowercased, without the dot. Empty for a directory or a file with no
    /// extension — and it is the ICON CACHE KEY, because every `.png` in a
    /// folder shares one icon and rasterizing each of them separately is how
    /// a listing takes a second to appear.
    public let ext: String

    public var id: String { path }
}

/// A place the sidebar offers.
public struct Win32Place: Sendable, Equatable, Identifiable {
    public let name: String
    public let path: String
    public var id: String { path }
}

public enum Win32Files {

    /// The user's folders, in the order a sidebar should list them. Any that
    /// the shell will not name are dropped rather than guessed at.
    public static func places() -> [Win32Place] {
        let names = ["Home", "Desktop", "Documents", "Downloads",
                     "Pictures", "Music", "Videos"]
        return names.enumerated().compactMap { index, name in
            var buffer = [CChar](repeating: 0, count: 1024)
            let n = buffer.withUnsafeMutableBufferPointer {
                flwin32_known_path(Int32(index), $0.baseAddress, 1024)
            }
            guard n > 0 else { return nil }
            return Win32Place(name: name, path: String(cString: buffer))
        }
    }

    /// Lists a directory: folders first, then files, each alphabetically —
    /// which is what every file manager does and what people expect to be
    /// able to scan down.
    ///
    /// Hidden and system entries are skipped. A file explorer that opens on
    /// `C:\` and leads with `$Recycle.Bin`, `System Volume Information` and
    /// `pagefile.sys` has buried the two folders the user came for.
    public static func list(_ directory: String) -> [Win32FileEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else {
            return []
        }
        var entries: [Win32FileEntry] = []
        entries.reserveCapacity(names.count)

        for name in names {
            if name.hasPrefix("$") { continue }
            let path = join(directory, name)
            guard let attributes = try? fm.attributesOfItem(atPath: path) else {
                continue
            }
            if let flags = attributes[.posixPermissions] as? NSNumber, flags == 0 {
                continue
            }
            let type = attributes[.type] as? FileAttributeType
            let isDirectory = type == .typeDirectory
            let ext = isDirectory
                ? "" : (name as NSString).pathExtension.lowercased()
            entries.append(Win32FileEntry(
                name: name,
                path: path,
                isDirectory: isDirectory,
                size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                modified: attributes[.modificationDate] as? Date,
                ext: ext))
        }

        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// What the user opened lately, newest first.
    ///
    /// The shell's own Recent folder — a directory of shortcuts Windows
    /// writes whenever a document is opened. This is where Start's
    /// "Recommended" list comes from, and reading it needs no hook and no
    /// telemetry: it is a folder, on disk, belonging to this user.
    ///
    /// Entries whose target has since been deleted are dropped rather than
    /// offered — a list of things that no longer open is worse than a short
    /// list.
    public static func recent(limit: Int = 6) -> [Win32FileEntry] {
        var buffer = [CChar](repeating: 0, count: 1024)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_known_path(7, $0.baseAddress, 1024)
        }
        guard n > 0 else { return [] }
        let folder = String(cString: buffer)

        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder) else { return [] }
        var found: [(entry: Win32FileEntry, used: Date)] = []
        for name in names where name.lowercased().hasSuffix(".lnk") {
            let linkPath = join(folder, name)
            guard let attributes = try? fm.attributesOfItem(atPath: linkPath),
                  let used = attributes[.modificationDate] as? Date else { continue }
            var target = [CChar](repeating: 0, count: 1024)
            var arguments = [CChar](repeating: 0, count: 8)
            var workdir = [CChar](repeating: 0, count: 8)
            _ = target.withUnsafeMutableBufferPointer { t in
                arguments.withUnsafeMutableBufferPointer { a in
                    workdir.withUnsafeMutableBufferPointer { w in
                        flwin32_shortcut_info(linkPath, t.baseAddress, 1024,
                                              a.baseAddress, 8, w.baseAddress, 8)
                    }
                }
            }
            let path = String(cString: target)
            var isDirectory: ObjCBool = false
            guard !path.isEmpty,
                  fm.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            let leaf = (path as NSString).lastPathComponent
            found.append((Win32FileEntry(
                name: leaf,
                path: path,
                isDirectory: isDirectory.boolValue,
                size: 0,
                modified: used,
                ext: isDirectory.boolValue
                    ? "" : (leaf as NSString).pathExtension.lowercased()), used))
        }
        return found.sorted { $0.used > $1.used }.prefix(limit).map { $0.entry }
    }

    /// The user's display name, for the account row.
    public static func userName() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_user_display_name($0.baseAddress, 256)
        }
        return n > 0 ? String(cString: buffer) : ""
    }

    /// The drives, as places. Reuses the Settings reader — one answer to
    /// "what drives are there", not two that can disagree.
    public static func drives() -> [Win32Place] {
        Win32SystemInfo.drives().map {
            Win32Place(name: "\($0.letter):", path: "\($0.letter):\\")
        }
    }

    /// What Explorer's Type column would say. Answers per EXTENSION, from the
    /// association database, without touching the file.
    public static func typeName(for path: String) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_file_type_name(path, $0.baseAddress, 256)
        }
        guard n > 0 else { return "" }
        return String(cString: buffer)
    }

    /// The parent, or nil at a drive root. `C:\` has no parent worth showing
    /// — "This PC" is a shell namespace, not a path, and pretending otherwise
    /// leads somewhere that does not exist.
    public static func parent(of directory: String) -> String? {
        let trimmed = directory.hasSuffix("\\") && directory.count > 3
            ? String(directory.dropLast()) : directory
        guard trimmed.count > 3 else { return nil }
        let parent = (trimmed as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != trimmed else { return nil }
        return parent.count == 2 ? parent + "\\" : parent
    }

    /// What currently opens this file — "Notepad", "Microsoft Edge" — or nil
    /// when the type has no handler at all.
    public static func defaultApp(for path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 512)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_default_app_name(path, $0.baseAddress, 512)
        }
        guard n > 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }

    /// Puts up the shell's "Open with" dialog.
    ///
    /// This is the ONLY supported way for a file association to change.
    /// Since Windows 8 an application cannot set the default handler itself:
    /// the choice lives in a `UserChoice` key protected by a hash over the
    /// extension, the user's SID and a timestamp, and writing it without that
    /// hash is ignored. Everything that still changes defaults does it by
    /// asking the user through this dialog — which offers "always use this
    /// app" — or by sending them to Windows' Settings.
    ///
    /// **Blocks** until the user answers.
    @discardableResult
    public static func openWith(_ path: String) -> Bool {
        flwin32_open_with_dialog(path) != 0
    }

    @discardableResult
    public static func openInExplorer(_ path: String) -> Bool {
        flwin32_open_in_explorer(path) != 0
    }

    public static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("\\") ? directory + name : directory + "\\" + name
    }
}

/// The file operations behind Paste, Rename, Delete, Cut and Copy, through
/// the shell's own IFileOperation -- recycle bin, conflict dialogs, progress,
/// and Explorer's undo stack included. See flwin32_fileops.c.
///
/// Every operation BLOCKS for as long as the shell (and any dialog the user
/// is looking at) takes, so they all run on one serial queue and call back
/// on the main thread. Serial on purpose: two overlapping operations on the
/// same folder is a conflict dialog factory.
public enum Win32FileOps {
    private static let queue = DispatchQueue(label: "starling.fileops",
                                             qos: .userInitiated)

    /// Whether a paste has anything to paste. Cheap -- no clipboard open, no
    /// COM -- so a menu can ask at every open.
    public static func clipboardHasFiles() -> Bool {
        flwin32_clipboard_has_files() != 0
    }

    /// Copy (or cut) one item to the clipboard, the shell's way: its own
    /// data object plus the preferred drop effect that tells a paste which
    /// of the two this was.
    public static func clip(_ path: String, cut: Bool,
                            done: ((Bool) -> Void)? = nil) {
        run(done) { flwin32_fileop_clip(path, cut ? 1 : 0) != 0 }
    }

    /// Paste the clipboard's files into `directory`. A cut moves and clears
    /// the clipboard; a copy copies and leaves it.
    public static func paste(into directory: String, owner: UInt64,
                             done: ((Bool) -> Void)? = nil) {
        run(done) { flwin32_fileop_paste(directory, owner) != 0 }
    }

    /// Rename in place. `name` is a name, not a path.
    public static func rename(_ path: String, to name: String, owner: UInt64,
                              done: ((Bool) -> Void)? = nil) {
        run(done) { flwin32_fileop_rename(path, name, owner) != 0 }
    }

    /// Delete to the recycle bin, with the shell's confirmation.
    public static func delete(_ path: String, owner: UInt64,
                              done: ((Bool) -> Void)? = nil) {
        run(done) { flwin32_fileop_delete(path, owner) != 0 }
    }

    /// The property sheet, for Alt+Enter.
    public static func showProperties(_ path: String, owner: UInt64) {
        run(nil) { flwin32_fileop_properties(path, owner) != 0 }
    }

    private static func run(_ done: ((Bool) -> Void)?,
                            _ work: @escaping () -> Bool) {
        queue.async {
            let ok = work()
            if let done {
                DispatchQueue.main.async { done(ok) }
            }
        }
    }
}
#endif
