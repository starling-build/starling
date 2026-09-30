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

/// `NSHomeDirectory()`. A tab has no home; "/" keeps the paths well-formed.
func homeDirectory() -> String {
    #if os(WASI)
    return "/"
    #else
    return NSHomeDirectory()
    #endif
}
