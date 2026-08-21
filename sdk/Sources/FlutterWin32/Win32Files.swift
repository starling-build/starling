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
    /// False for an item with no file behind it — a Network machine, an
    /// entry inside a zip. `path` is then a shell PARSING NAME, which the
    /// shell's own machinery (SHParseDisplayName, IFileOperation) accepts
    /// but the filesystem APIs must not be handed.
    public let isFileSystem: Bool
    /// What the SHELL says this is — set only where the shell was asked
    /// (a namespace listing, which reads it per item anyway). nil means
    /// "derive it from the extension", which is what an ordinary directory
    /// listing does and what the association database is for. It exists
    /// because deriving is WRONG in the Recycle Bin: the extension route
    /// answers off `path`, and a recycled item's path is its `$R…` slot.
    public let typeName: String?

    public init(name: String, path: String, isDirectory: Bool, size: Int64,
                modified: Date?, ext: String, isFileSystem: Bool = true,
                typeName: String? = nil) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.ext = ext
        self.isFileSystem = isFileSystem
        self.typeName = typeName
    }

    public var id: String { path }
}

/// A place the sidebar offers.
public struct Win32Place: Sendable, Equatable, Identifiable {
    public let name: String
    public let path: String
    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
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

    /// The namespace locations the sidebar can offer — parsing names, not
    /// paths. The CLSIDs are the shell's own, stable since forever.
    public enum NamespacePlace {
        public static let recycleBin = "::{645FF040-5081-101B-9F08-00AA002F954E}"
        public static let network = "::{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}"
        /// Quick Access ("Home" since 22H2): the pinned + frequent set.
        /// The `shell:` spelling is LOAD-BEARING: the bare "::{GUID}" form
        /// parses for the bin and Network but NOT for this folder (probed
        /// -- SHParseDisplayName refuses it), while the shell: URI resolves.
        public static let quickAccess =
            "shell:::{679F85CB-0220-4080-B29B-5540CC05AAB6}"
    }

    /// Lists a shell NAMESPACE location — the Recycle Bin, Network, a .zip
    /// browsed as a folder — by parsing name. nil when the location does
    /// not resolve or cannot enumerate; an empty array is an honestly empty
    /// folder. Can block (Network discovery): call off the UI thread.
    public static func listNamespace(_ location: String) -> [Win32FileEntry]? {
        guard let list = flwin32_ns_list(location) else { return nil }
        defer { flwin32_ns_list_free(list) }
        let count = flwin32_ns_count(list)
        var out: [Win32FileEntry] = []
        out.reserveCapacity(Int(count))
        var buffer = [CChar](repeating: 0, count: 4096)
        func field(_ index: Int32, _ which: Int32) -> String {
            let n = buffer.withUnsafeMutableBufferPointer {
                flwin32_ns_field(list, index, which, $0.baseAddress, 4096)
            }
            return n > 0 ? String(cString: buffer) : ""
        }
        for index in 0..<count {
            var folder: Int32 = 0
            var filesystem: Int32 = 0
            var size: Int64 = 0
            var mtime: Int64 = 0
            flwin32_ns_attrs(list, index, &folder, &filesystem, &size, &mtime)
            let display = field(index, 1)
            let parsing = field(index, 0)
            guard !parsing.isEmpty else { continue }
            let isDirectory = folder != 0
            let type = field(index, 2)
            out.append(Win32FileEntry(
                name: display.isEmpty ? parsing : display,
                path: parsing,
                isDirectory: isDirectory,
                size: size,
                modified: mtime > 0
                    ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil,
                // From the PARSING name, not the display one. The display
                // name honours "hide extensions for known file types" --
                // Explorer's setting, which the shell applies for us -- so
                // "a - Copy.txt" arrives as "a - Copy" and derives an EMPTY
                // extension. That is only cosmetic in the Name column and
                // load-bearing here: `ext` is the icon cache key, so every
                // known-type file in the bin collapsed onto one key and drew
                // whichever icon warmed first (a text file wearing the zip's
                // icon). The parsing name keeps the real extension -- a
                // recycled item's `$R…` slot preserves it, and a zip member's
                // path is a plain path.
                ext: isDirectory
                    ? "" : (parsing as NSString).pathExtension.lowercased(),
                isFileSystem: filesystem != 0,
                // The shell's own Type text, already read per item on the C
                // side. Carrying it costs nothing here and is the only
                // correct answer in the bin, where the extension route
                // would ask about a `$R…` slot name.
                typeName: type.isEmpty ? nil : type))
        }
        return out
    }

    /// The folders the user has PINNED to Quick Access — Explorer's pin
    /// set, read from the shell so both explorers always agree. The Quick
    /// Access folder enumerates pinned and merely-frequent together;
    /// System.Home.IsPinned is what splits them, and only folders qualify
    /// (Windows lists recent FILES there too). Order is the shell's, which
    /// is the order Explorer's sidebar shows. Can block briefly: call off
    /// the UI thread.
    public static func quickAccessPins() -> [Win32Place] {
        guard let list = flwin32_ns_list(NamespacePlace.quickAccess) else {
            return []
        }
        defer { flwin32_ns_list_free(list) }
        var out: [Win32Place] = []
        var buffer = [CChar](repeating: 0, count: 4096)
        for index in 0..<flwin32_ns_count(list) {
            guard flwin32_ns_pinned(list, index) == 1 else { continue }
            var folder: Int32 = 0
            flwin32_ns_attrs(list, index, &folder, nil, nil, nil)
            guard folder != 0 else { continue }
            func field(_ which: Int32) -> String {
                let n = buffer.withUnsafeMutableBufferPointer {
                    flwin32_ns_field(list, index, which, $0.baseAddress, 4096)
                }
                return n > 0 ? String(cString: buffer) : ""
            }
            let path = field(0)
            let name = field(1)
            guard !path.isEmpty else { continue }
            out.append(Win32Place(name: name.isEmpty ? path : name,
                                  path: path))
        }
        return out
    }

    /// The user's OneDrive, when there is one — a row for a real folder
    /// only. Windows exports the sync root as %OneDrive% once the client is
    /// set up; the bare profile-folder spelling is the fallback. Named by
    /// the shell ("OneDrive - Personal"), like everything else here.
    public static func oneDrive() -> Win32Place? {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["OneDrive"]
                ?? env["USERPROFILE"].map({ $0 + "\\OneDrive" }) else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path,
                                             isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return Win32Place(name: displayName(for: path), path: path)
    }

    /// One entry of Explorer's New submenu: a file type whose ShellNew
    /// registration describes a file this shell can create.
    public struct ShellNewTemplate: Sendable, Equatable {
        public let ext: String      // ".txt"
        public let name: String     // "Text Document"
        let kind: String            // "null" | "file" | "data"
        let source: String          // template path, or the bytes as hex
    }

    nonisolated(unsafe) private static var shellNewCache: [ShellNewTemplate]?
    private static let shellNewLock = NSLock()

    /// The ShellNew templates, the way Explorer's New submenu gets them.
    /// The first call walks all of HKCR (call it off the UI thread); the
    /// answer is kept, because it changes only when software is installed.
    public static func shellNewTemplates() -> [ShellNewTemplate] {
        shellNewLock.lock()
        defer { shellNewLock.unlock() }
        if let cached = shellNewCache { return cached }
        var buffer = [CChar](repeating: 0, count: 65536)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_shellnew_templates($0.baseAddress, 65536)
        }
        var out: [ShellNewTemplate] = []
        var seen = Set<String>()
        if n > 0 {
            for line in String(cString: buffer).split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 3,
                                       omittingEmptySubsequences: false)
                guard parts.count == 4 else { continue }
                let name = String(parts[1])
                // Two extensions naming the same type would put the same
                // row in the menu twice; the first registration wins.
                guard seen.insert(name).inserted else { continue }
                out.append(ShellNewTemplate(ext: String(parts[0]),
                                            name: name,
                                            kind: String(parts[2]),
                                            source: String(parts[3])))
            }
        }
        out.sort { $0.name.localizedCaseInsensitiveCompare($1.name)
                       == .orderedAscending }
        shellNewCache = out
        return out
    }

    /// Creates a new file in `directory` from `template`, Explorer-named --
    /// "New Text Document.txt", then "New Text Document (2).txt" -- and
    /// returns the created path, or nil.
    public static func shellNewCreate(in directory: String,
                                      template: ShellNewTemplate) -> String? {
        var name = "New \(template.name)\(template.ext)"
        var counter = 2
        while FileManager.default.fileExists(atPath: join(directory, name)) {
            name = "New \(template.name) (\(counter))\(template.ext)"
            counter += 1
        }
        let path = join(directory, name)
        switch template.kind {
        case "null":
            guard FileManager.default.createFile(atPath: path,
                                                 contents: nil) else {
                return nil
            }
        case "file":
            do {
                try FileManager.default.copyItem(atPath: template.source,
                                                 toPath: path)
            } catch { return nil }
        case "data":
            var bytes = Data()
            var index = template.source.startIndex
            while index < template.source.endIndex,
                  let next = template.source.index(index, offsetBy: 2,
                      limitedBy: template.source.endIndex),
                  let byte = UInt8(template.source[index..<next], radix: 16) {
                bytes.append(byte)
                index = next
            }
            guard FileManager.default.createFile(atPath: path,
                                                 contents: bytes) else {
                return nil
            }
        default:
            return nil
        }
        return path
    }

    /// The drives, as places. Reuses the Settings reader — one answer to
    /// "what drives are there", not two that can disagree.
    public static func drives() -> [Win32Place] {
        Win32SystemInfo.drives().map {
            Win32Place(name: "\($0.letter):", path: "\($0.letter):\\")
        }
    }

    nonisolated(unsafe) private static var displayNameCache: [String: String] = [:]
    private static let displayNameLock = NSLock()

    /// The shell's display name -- "Local Disk (C:)" for a drive root, the
    /// localized "Documents" for a known folder. Falls back to the file
    /// system's own last component.
    ///
    /// MEMOIZED: the sidebar's drive rows and the breadcrumb ask on every
    /// window rebuild, and a rebuild can run per pointer move (a column
    /// drag). The answer is a shell call measured at ~0.1ms -- pennies
    /// once, a tax per frame -- and it changes only when a volume is
    /// relabeled, which a relaunch is allowed to notice.
    public static func displayName(for path: String) -> String {
        displayNameLock.lock()
        if let cached = displayNameCache[path] {
            displayNameLock.unlock()
            return cached
        }
        displayNameLock.unlock()
        var buffer = [CChar](repeating: 0, count: 256)
        // A "::" location is a parsing name, not a path: SHGetFileInfoW
        // cannot name it and the namespace resolver can. Same cache either
        // way -- the callers (crumbs, tab captions, the sidebar) do not know
        // or care which kind of name they are holding.
        let n = buffer.withUnsafeMutableBufferPointer {
            path.hasPrefix("::")
                ? flwin32_ns_display_name(path, $0.baseAddress, 256)
                : flwin32_file_display_name(path, $0.baseAddress, 256)
        }
        let name: String
        if n > 0 {
            name = String(cString: buffer)
        } else {
            let last = (path as NSString).lastPathComponent
            name = last.isEmpty ? path : last
        }
        displayNameLock.lock()
        displayNameCache[path] = name
        displayNameLock.unlock()
        return name
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
        // A namespace root has no parent we can name. The Recycle Bin's real
        // one is the Desktop, which this window has no view for, and "This
        // PC" would be a lie -- so Up disables itself there. (Explicit,
        // because the path arithmetic below would fall to nil anyway: a
        // ::{CLSID} has no separator to delete. Depending on that by accident
        // is how it comes back the day a location has one.)
        guard !directory.hasPrefix("::") else { return nil }
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

    /// One thing an operation did to one item, in the names the shell
    /// SETTLED ON (" - Copy", "(2)") rather than the names that were asked
    /// for. The raw material of undo: the shell's own undo stack
    /// (FOFX_ADDUNDORECORD) has no replay API -- it is Explorer's private
    /// property -- so a caller that wants Ctrl+Z keeps these and applies
    /// the inverse itself.
    public struct OpRecord: Sendable {
        public enum Kind: Int32, Sendable {
            case copy = 1, move = 2, rename = 3, delete = 4, new = 5
        }
        public let kind: Kind
        /// The item as it was BEFORE. Empty for `.new`.
        public let src: String
        /// The item as it is NOW. For `.delete`, its `$R…` slot in the
        /// recycle bin -- what a restore takes -- or empty when the delete
        /// was permanent and there is nothing to undo.
        public let dst: String

        public init(kind: Kind, src: String, dst: String) {
            self.kind = kind
            self.src = src
            self.dst = dst
        }
    }

    /// Reads the C journal for the operation that just ran. Queue-private:
    /// the journal is reset by the NEXT operation, so it is read on the
    /// same serial queue, immediately.
    private static func journal() -> [OpRecord] {
        let count = flwin32_fileop_journal_count()
        var out: [OpRecord] = []
        out.reserveCapacity(Int(count))
        var src = [CChar](repeating: 0, count: 1024)
        var dst = [CChar](repeating: 0, count: 1024)
        for index in 0..<count {
            var kind: Int32 = 0
            let ok = src.withUnsafeMutableBufferPointer { s in
                dst.withUnsafeMutableBufferPointer { d in
                    flwin32_fileop_journal_get(index, &kind, s.baseAddress,
                                               1024, d.baseAddress, 1024)
                }
            }
            guard ok != 0, let k = OpRecord.Kind(rawValue: kind) else {
                continue
            }
            out.append(OpRecord(kind: k, src: String(cString: src),
                                dst: String(cString: dst)))
        }
        return out
    }

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
    /// the clipboard; a copy copies and leaves it. `done` carries the
    /// journal -- what actually landed, under the names the shell chose --
    /// which is what an undo stack is built from.
    public static func paste(into directory: String, owner: UInt64,
                             done: ((Bool, [OpRecord]) -> Void)? = nil) {
        runJournaled(done) { flwin32_fileop_paste(directory, owner) != 0 }
    }

    /// Rename in place. `name` is a name, not a path.
    public static func rename(_ path: String, to name: String, owner: UInt64,
                              done: ((Bool, [OpRecord]) -> Void)? = nil) {
        runJournaled(done) { flwin32_fileop_rename(path, name, owner) != 0 }
    }

    /// Delete to the recycle bin, with the shell's confirmation.
    public static func delete(_ path: String, owner: UInt64,
                              done: ((Bool, [OpRecord]) -> Void)? = nil) {
        runJournaled(done) { flwin32_fileop_delete(path, owner) != 0 }
    }

    /// Delete a SELECTION: one operation over the set, so one progress
    /// dialog and one undo entry -- what Explorer does, and what N separate
    /// deletes would not be.
    public static func deleteMany(_ paths: [String], owner: UInt64,
                                  done: ((Bool, [OpRecord]) -> Void)? = nil) {
        let joined = paths.joined(separator: "\n")
        runJournaled(done) { flwin32_fileop_delete_multi(joined, owner) != 0 }
    }

    /// Copy (or cut) a selection to the clipboard as one data object; a
    /// paste lands the whole set.
    public static func clipMany(_ paths: [String], cut: Bool,
                                done: ((Bool) -> Void)? = nil) {
        let joined = paths.joined(separator: "\n")
        run(done) { flwin32_fileop_clip_multi(joined, cut ? 1 : 0) != 0 }
    }

    /// The property sheet, for Alt+Enter.
    public static func showProperties(_ path: String, owner: UInt64) {
        run(nil) { flwin32_fileop_properties(path, owner) != 0 }
    }

    /// Create a folder in `directory`, Explorer-named: "New folder", then
    /// "New folder (2)" and so on. Calls back with the created PATH -- the
    /// caller needs it, because the Explorer gesture is create-then-rename
    /// and a rename starts from a path.
    public static func newFolder(in directory: String, owner: UInt64,
                                 done: @escaping (String?) -> Void) {
        queue.async {
            var name = "New folder"
            var counter = 2
            while FileManager.default.fileExists(
                    atPath: Win32Files.join(directory, name)) {
                name = "New folder (\(counter))"
                counter += 1
            }
            let path = Win32Files.join(directory, name)
            let ok = flwin32_fileop_new_folder(directory, name, owner) != 0
            DispatchQueue.main.async { done(ok ? path : nil) }
        }
    }

    /// Compress one item to a .zip beside it, named the way Explorer names
    /// them: the item's stem plus .zip, uniqued when taken.
    ///
    /// Windows offers no API to its own "Compress to" handler -- it is not
    /// among the verbs a menu host is given -- but it has shipped bsdtar as
    /// System32\tar.exe since 2018, and `-a` picks the zip format from the
    /// output name. Shelling out is the honest version of this: the
    /// alternative is reimplementing an archiver.
    public static func compressToZip(_ path: String,
                                     done: ((String?) -> Void)? = nil) {
        queue.async {
            let source = URL(fileURLWithPath: path)
            let parent = source.deletingLastPathComponent().path
            let stem = source.deletingPathExtension().lastPathComponent
            var zipName = stem + ".zip"
            var counter = 2
            while FileManager.default.fileExists(
                    atPath: Win32Files.join(parent, zipName)) {
                zipName = "\(stem) (\(counter)).zip"
                counter += 1
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath:
                "C:\\Windows\\System32\\tar.exe")
            // -C first: the archive holds the item by NAME, not by its
            // absolute path -- an unzip should produce "sub/", not
            // "Users/starling/.../sub/".
            process.arguments = ["-a", "-c", "-f", zipName,
                                 source.lastPathComponent]
            process.currentDirectoryURL = URL(fileURLWithPath: parent)
            let ok = (try? process.run()) != nil
            if ok { process.waitUntilExit() }
            let made = ok && process.terminationStatus == 0
            if let done {
                DispatchQueue.main.async {
                    done(made ? Win32Files.join(parent, zipName) : nil)
                }
            }
        }
    }

    /// Copy or move a set of files into a directory -- what a drop resolves
    /// to. One IFileOperation over the whole set, like `deleteMany`.
    public static func transfer(_ paths: [String], into dir: String,
                                move: Bool, owner: UInt64,
                                done: ((Bool, [OpRecord]) -> Void)? = nil) {
        let joined = paths.joined(separator: "\n")
        runJournaled(done) {
            flwin32_fileop_transfer(joined, dir, move ? 1 : 0, owner) != 0
        }
    }

    /// Undo of a MOVE: every item back to its own folder under its own
    /// name, one IFileOperation over the set. Each entry is (where the item
    /// is now, the directory it came from, the name it had there).
    public static func undoMoves(
        _ moves: [(current: String, dir: String, name: String)],
        owner: UInt64, done: ((Bool) -> Void)? = nil
    ) {
        let lines = moves.map { "\($0.current)\t\($0.dir)\t\($0.name)" }
            .joined(separator: "\n")
        run(done) { flwin32_fileop_undo_moves(lines, owner) != 0 }
    }

    /// Undo of a DELETE: restore recycled items by their `$R…` slot paths
    /// (a delete record's `dst`), through the bin's own restore verb -- the
    /// only whole restore; moving a slot back by hand orphans its `$I`
    /// record.
    public static func restoreFromBin(_ slots: [String], owner: UInt64,
                                      done: ((Bool) -> Void)? = nil) {
        let joined = slots.joined(separator: "\n")
        run(done) { flwin32_fileop_bin_restore(joined, owner) != 0 }
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

    /// `run`, delivering the operation's journal with its result. The read
    /// happens HERE, on the serial queue, because the next operation resets
    /// the C-side journal -- by the time a main-thread callback runs,
    /// another op may already be in flight.
    private static func runJournaled(_ done: ((Bool, [OpRecord]) -> Void)?,
                                     _ work: @escaping () -> Bool) {
        queue.async {
            let ok = work()
            let records = journal()
            if let done {
                DispatchQueue.main.async { done(ok, records) }
            }
        }
    }
}

/// The window as an OLE drop target -- the Swift face of flwin32_dragdrop.c.
///
/// A static surface rather than an instance, because C function pointers
/// cannot capture context and the process has exactly one host window. The
/// closures run on the UI thread (the drop target's callbacks arrive through
/// its message pump), so they may touch widget state directly. Set them
/// BEFORE calling `register`; a drag that arrives between the two would
/// otherwise be refused, which is at least honest.
public enum Win32DropTarget {
    /// A drag carrying files entered the window: the paths, the pointer in
    /// logical client coordinates, and the modifier keys. Return the effect
    /// to show the source: 0 none, 1 copy, 2 move.
    public static var onEnter: (([String], Double, Double, UInt32) -> Int32)?
    public static var onOver: ((Double, Double, UInt32) -> Int32)?
    public static var onLeave: (() -> Void)?
    /// The drop happened. `move` is the effect the UI last chose.
    public static var onDrop: (([String], Double, Double, Bool) -> Void)?

    private static func split(_ joined: UnsafePointer<CChar>?) -> [String] {
        guard let joined else { return [] }
        return String(cString: joined).split(separator: "\n").map(String.init)
    }

    /// A full OLE drag of `paths` out of this process. Blocks on the UI
    /// thread (DoDragDrop pumps its own loop) until drop or cancel -- call
    /// it from a deferred hop, never mid pointer dispatch. Returns 0
    /// cancelled, 1 copied, 2 moved; a move onto Explorer reports 0 by the
    /// shell's optimized-move handshake, so refresh regardless.
    @discardableResult
    public static func beginDrag(_ paths: [String]) -> Int32 {
        flwin32_dragdrop_begin(paths.joined(separator: "\n"))
    }

    /// Call once from the UI thread after the host window exists.
    @discardableResult
    public static func register(window: UInt64) -> Bool {
        flwin32_dragdrop_register(
            window,
            { paths, x, y, keys, _ in
                Win32DropTarget.onEnter?(Win32DropTarget.split(paths), x, y, keys) ?? 0
            },
            { x, y, keys, _ in
                Win32DropTarget.onOver?(x, y, keys) ?? 0
            },
            { _ in
                Win32DropTarget.onLeave?()
            },
            { paths, x, y, _, isMove, _ in
                Win32DropTarget.onDrop?(Win32DropTarget.split(paths), x, y, isMove != 0)
            },
            nil) != 0
    }
}
#endif
