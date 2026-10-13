// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Path arithmetic in plain Swift. NSString's `lastPathComponent` and friends
// are the legacy Foundation layer, which the web build does not link (it
// brings ICU, docs/plans/wasm-size.md); these do the same for the paths
// Office handles, everywhere.

import Foundation

extension String {
    /// `NSString.lastPathComponent`: "a/b/c.txt" → "c.txt", "a/b/" → "b".
    var lastPathComponent: String {
        let trimmed = self.count > 1 && hasSuffix("/") ? String(dropLast()) : self
        return trimmed.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
    }

    /// `NSString.deletingLastPathComponent`: "a/b/c.txt" → "a/b", "/c" → "/".
    var deletingLastPathComponent: String {
        let trimmed = self.count > 1 && hasSuffix("/") ? String(dropLast()) : self
        guard let slash = trimmed.lastIndex(of: "/") else { return "" }
        return slash == trimmed.startIndex ? "/" : String(trimmed[..<slash])
    }

    /// `NSString.pathExtension`: "a/b.tar.gz" → "gz", ".hidden" → "".
    var pathExtension: String {
        let name = lastPathComponent
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...])
    }

    /// `NSString.deletingPathExtension`: "a/b.txt" → "a/b".
    var deletingPathExtension: String {
        let ext = pathExtension
        return ext.isEmpty ? self : String(dropLast(ext.count + 1))
    }

    /// `NSString.appendingPathComponent`: joins with exactly one slash.
    func appendingPathComponent(_ component: String) -> String {
        if isEmpty { return component }
        if hasSuffix("/") { return self + component }
        return self + "/" + component
    }
}

extension String {
    /// A path as this file's arithmetic takes it: forward slashes only. On
    /// Windows a path arrives with backslashes (the home directory, a
    /// command-line argument, what a user types), which the functions
    /// above would read as one long name; Windows itself takes either.
    var portablePath: String {
        #if os(Windows)
        return String(map { $0 == "\\" ? "/" : $0 })
        #else
        return self
        #endif
    }

    /// A path as the platform writes it, for showing: backslashes on Windows.
    var displayPath: String {
        #if os(Windows)
        return String(map { $0 == "/" ? "\\" : $0 })
        #else
        return self
        #endif
    }

    /// Whether this names a place by itself — "/a/b", or "C:/a" on Windows
    /// — rather than something inside the current directory.
    var isAbsolutePath: Bool {
        if hasPrefix("/") { return true }
        #if os(Windows)
        let u = Array(unicodeScalars.prefix(3))
        return u.count == 3 && u[1] == ":" && u[2] == "/" && u[0].properties.isAlphabetic
        #else
        return false
        #endif
    }
}

/// `NSHomeDirectory()`. A tab has no home; "/" keeps the paths well-formed.
func homeDirectory() -> String {
    #if os(WASI)
    return "/"
    #else
    return NSHomeDirectory().portablePath
    #endif
}
