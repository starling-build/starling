// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The few string operations the framework used to borrow from Foundation's
// NSString layer, in plain Swift. Plain Swift because that layer is the
// legacy Foundation module, and on the web that module brings ICU along —
// 40 MB for a trim (docs/plans/wasm-size.md). Same results everywhere.
//
// Public, because an app has the same problem: on the web a
// `trimmingCharacters(in:)` in app code fails to link (the legacy module is
// deliberately absent), and these are the spellings that work everywhere.

extension StringProtocol {
    /// `trimmingCharacters(in: .whitespacesAndNewlines)`, or with
    /// `newlines: false`, `trimmingCharacters(in: .whitespaces)`.
    public func trimmingWhitespace(newlines: Bool = true) -> String {
        let isBlank = { (c: Character) in c.isWhitespace && (newlines || !c.isNewline) }
        guard let first = firstIndex(where: { !isBlank($0) }) else { return "" }
        let last = lastIndex(where: { !isBlank($0) })!
        return String(self[first...last])
    }

    /// `replacingOccurrences(of:with:)`: every non-overlapping occurrence,
    /// left to right.
    public func replacingAll(_ target: String, with replacement: String) -> String {
        guard !target.isEmpty else { return String(self) }
        var result = ""
        var rest = Substring(self)
        while let range = rest.firstRange(ofSubstring: target) {
            result += rest[..<range.lowerBound]
            result += replacement
            rest = rest[range.upperBound...]
        }
        result += rest
        return result
    }
}

extension StringProtocol {
    /// `contains(_ other: String)`. Under its own name: Foundation's
    /// `contains<T: StringProtocol>` is `range(of:)` in the NS layer, and
    /// a same-named overload here did not displace it.
    public func containsSubstring(_ other: String) -> Bool {
        Substring(self).firstRange(ofSubstring: other) != nil
    }

    /// `self` with the first occurrence of `target` removed, if any.
    public func removingFirst(_ target: String) -> String {
        guard let range = Substring(self).firstRange(ofSubstring: target) else { return String(self) }
        return String(self[..<range.lowerBound]) + self[range.upperBound...]
    }
}

extension StringProtocol {
    /// `padding(toLength:withPad: " ", startingAt: 0)`: padded with spaces
    /// on the right to `length` characters, or cut to it.
    public func paddedToLength(_ length: Int) -> String {
        if count >= length { return String(prefix(length)) }
        return String(self) + String(repeating: " ", count: length - count)
    }
}

extension Substring {
    /// The first occurrence of `target`, by character comparison. Its own
    /// name, on `Substring` specifically: `range(of:)` on a `StringProtocol`
    /// (which `self[...]` is, in a generic context) resolves to the NS layer.
    fileprivate func firstRange(ofSubstring target: String) -> Range<Index>? {
        guard let firstChar = target.first else { return nil }
        var i = startIndex
        while let start = self[i...].firstIndex(of: firstChar) {
            if self[start...].hasPrefix(target) {
                return start..<index(start, offsetBy: target.count)
            }
            i = index(after: start)
        }
        return nil
    }
}
