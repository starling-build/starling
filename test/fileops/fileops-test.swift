// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The file manager's copy and move, tested standalone — the same shape as
// test/layout/layout-test.swift, and for the same reason: these functions
// write to the user's disk, so the cases that must never happen (a folder
// copied into itself, a replace that removes the wrong side, a skip that
// still overwrites) are worth pinning where they run in a second.
//
//   swiftc -O fileops-test.swift ../../apps/FileExplorerApp/Sources/FileExplorerApp/FileSystem.swift
//
// test/run.sh does exactly that.

import Foundation

var failures: [String] = []

func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        print("  ok    \(name)")
    } else {
        let d = detail()
        print("  FAIL  \(name)\(d.isEmpty ? "" : " — \(d)")")
        failures.append(name)
    }
}

@main
struct FileOpsTest {
  static func main() {
    let fm = FileManager.default
    let root = NSTemporaryDirectory() + "/starling-fileops-\(getpid())"
    try? fm.removeItem(atPath: root)
    try! fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(atPath: root) }

    /// A fresh source and destination pair for one case.
    func scratch(_ name: String) -> (src: String, dst: String) {
        let src = root + "/\(name)/src"
        let dst = root + "/\(name)/dst"
        try! fm.createDirectory(atPath: src, withIntermediateDirectories: true)
        try! fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        return (src, dst)
    }

    func write(_ text: String, _ path: String) {
        try! text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func read(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    // MARK: - Copy

    do {
        let (src, dst) = scratch("plain")
        write("hello", src + "/note.txt")
        let error = FileSystem.copy(src + "/note.txt", into: dst, policy: .keepBoth)
        check("copy: a file lands with its contents", error == nil && read(dst + "/note.txt") == "hello",
              error ?? String(describing: read(dst + "/note.txt")))
        check("copy: the source stays where it was", read(src + "/note.txt") == "hello")
    }

    do {
        let (src, dst) = scratch("keepboth")
        write("new", src + "/note.txt")
        write("old", dst + "/note.txt")
        let error = FileSystem.copy(src + "/note.txt", into: dst, policy: .keepBoth)
        check("keep both: the new file is renamed",
              error == nil && read(dst + "/note (2).txt") == "new", error ?? "")
        check("keep both: the old file is untouched", read(dst + "/note.txt") == "old")
    }

    do {
        let (src, dst) = scratch("replace")
        write("new", src + "/note.txt")
        write("old", dst + "/note.txt")
        let error = FileSystem.copy(src + "/note.txt", into: dst, policy: .replace)
        check("replace: the destination takes the new contents",
              error == nil && read(dst + "/note.txt") == "new", error ?? "")
        check("replace: nothing is left beside it",
              (try? fm.contentsOfDirectory(atPath: dst))?.count == 1)
    }

    do {
        let (src, dst) = scratch("skip")
        write("new", src + "/note.txt")
        write("old", dst + "/note.txt")
        let error = FileSystem.copy(src + "/note.txt", into: dst, policy: .skip)
        check("skip: the destination is left alone",
              error == nil && read(dst + "/note.txt") == "old", error ?? "")
        check("skip: and nothing else appears",
              (try? fm.contentsOfDirectory(atPath: dst))?.count == 1)
    }

    do {
        let (src, dst) = scratch("tree")
        try! fm.createDirectory(atPath: src + "/folder/deeper", withIntermediateDirectories: true)
        write("inner", src + "/folder/deeper/inner.txt")
        let error = FileSystem.copy(src + "/folder", into: dst, policy: .keepBoth)
        check("copy: a folder brings its whole tree",
              error == nil && read(dst + "/folder/deeper/inner.txt") == "inner", error ?? "")
    }

    do {
        let (src, _) = scratch("self")
        try! fm.createDirectory(atPath: src + "/folder", withIntermediateDirectories: true)
        write("x", src + "/folder/x.txt")
        // Into itself, and into its own subtree: both must be refused, or the
        // copy walks into what it is writing and never ends.
        let intoSelf = FileSystem.copy(src + "/folder", into: src + "/folder", policy: .keepBoth)
        let intoChild = FileSystem.copy(src + "/folder", into: src + "/folder/deeper", policy: .keepBoth)
        check("copy: a folder cannot be copied into itself", intoSelf != nil)
        check("copy: nor into its own subtree", intoChild != nil)
    }

    do {
        let (src, _) = scratch("beside")
        write("hello", src + "/note.txt")
        // Copy and paste in the same folder: the everyday "give me another one".
        let error = FileSystem.copy(src + "/note.txt", into: src, policy: .keepBoth)
        check("copy: pasting into the source folder makes a second copy",
              error == nil && read(src + "/note (2).txt") == "hello", error ?? "")
    }

    // MARK: - Move

    do {
        let (src, dst) = scratch("move")
        write("hello", src + "/note.txt")
        let error = FileSystem.move(src + "/note.txt", into: dst, policy: .keepBoth)
        check("move: the file arrives", error == nil && read(dst + "/note.txt") == "hello", error ?? "")
        check("move: and leaves the source", !fm.fileExists(atPath: src + "/note.txt"))
    }

    do {
        let (src, _) = scratch("movesame")
        write("hello", src + "/note.txt")
        // Cut and paste in the same folder is a no-op, not a second copy.
        let error = FileSystem.move(src + "/note.txt", into: src, policy: .keepBoth)
        check("move: into the same folder does nothing, quietly",
              error == nil && (try? fm.contentsOfDirectory(atPath: src))?.count == 1, error ?? "")
    }

    do {
        let (src, dst) = scratch("movemissing")
        let error = FileSystem.move(src + "/gone.txt", into: dst, policy: .keepBoth)
        check("move: a file that has since vanished reports it", error != nil)
    }

    // MARK: - Names and conflicts

    do {
        let (src, _) = scratch("names")
        write("a", src + "/a.txt")
        write("b", src + "/a (2).txt")
        check("unique name: counts past what is already taken",
              FileSystem.uniqueName(for: "a.txt", in: src) == "a (3).txt",
              FileSystem.uniqueName(for: "a.txt", in: src))
        write("c", src + "/.hidden")
        check("unique name: a dotfile keeps its whole name",
              FileSystem.uniqueName(for: ".hidden", in: src) == ".hidden (2)",
              FileSystem.uniqueName(for: ".hidden", in: src))
        check("unique name: no extension, no dot",
              FileSystem.uniqueName(for: "README", in: src) == "README (2)",
              FileSystem.uniqueName(for: "README", in: src))
    }

    do {
        let (src, dst) = scratch("conflicts")
        write("a", src + "/taken.txt")
        write("b", src + "/free.txt")
        write("c", dst + "/taken.txt")
        let names = FileSystem.conflicts([src + "/taken.txt", src + "/free.txt"], in: dst)
        check("conflicts: only the taken name is reported", names == ["taken.txt"], "\(names)")
        let sameFolder = FileSystem.conflicts([src + "/taken.txt"], in: src)
        check("conflicts: a file is not in conflict with itself", sameFolder.isEmpty, "\(sameFolder)")
    }

    print(failures.isEmpty
        ? "all file operation checks passed"
        : "\(failures.count) file operation check(s) failed")
    exit(failures.isEmpty ? 0 : 1)
  }
}
