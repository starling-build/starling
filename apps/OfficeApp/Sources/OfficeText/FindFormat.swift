// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-ED-2: the formatting Word's Find and Replace > Format looks for, or puts on what it
// replaces. Each part is nil for "any" (Find) or "leave as it is" (Replace); a set part must
// hold on every character of a match.

import Flutter
import FlutterSwiftBridge

public struct FindFormat: Equatable, Sendable {
    public var bold: Bool? = nil
    public var italic: Bool? = nil
    public var underline: Bool? = nil
    public var strikethrough: Bool? = nil
    public var fontFamily: String? = nil
    public var fontSize: Double? = nil
    public var highlight: Bool? = nil
    /// The paragraph style (its id).
    public var paragraphStyle: String? = nil

    public init(bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil, strikethrough: Bool? = nil,
                fontFamily: String? = nil, fontSize: Double? = nil, highlight: Bool? = nil, paragraphStyle: String? = nil) {
        self.bold = bold; self.italic = italic; self.underline = underline; self.strikethrough = strikethrough
        self.fontFamily = fontFamily; self.fontSize = fontSize; self.highlight = highlight
        self.paragraphStyle = paragraphStyle
    }

    public var isEmpty: Bool { self == FindFormat() }
    /// Any of the character parts is set.
    public var hasCharacterParts: Bool {
        var c = self; c.paragraphStyle = nil
        return !c.isEmpty
    }

    /// Whether a character of `style`, in a paragraph of style `styleId`, has this formatting.
    /// `fontFamily` and `fontSize` are the run's own or, where it has none, the defaults given.
    public func matches(_ style: CharStyle, styleId: String, defaultFamily: String? = nil, defaultSize: Double? = nil) -> Bool {
        if let b = bold, style.bold != b { return false }
        if let b = italic, style.italic != b { return false }
        if let b = underline, style.underline != b { return false }
        if let b = strikethrough, style.strikethrough != b { return false }
        if let h = highlight, (style.highlight != nil) != h { return false }
        if let f = fontFamily, (style.fontFamily ?? defaultFamily)?.lowercased() != f.lowercased() { return false }
        if let s = fontSize, (style.fontSize ?? defaultSize).map({ abs($0 - s) < 0.01 }) != true { return false }
        if let p = paragraphStyle, p != styleId { return false }
        return true
    }

    /// Put the character parts on `style`. Highlight on is Word's default yellow.
    public func apply(to style: inout CharStyle) {
        if let b = bold { style.bold = b }
        if let b = italic { style.italic = b }
        if let b = underline { style.underline = b }
        if let b = strikethrough { style.strikethrough = b }
        if let h = highlight { style.highlight = h ? Color(0xFFFF_FF00) : nil }
        if let f = fontFamily { style.fontFamily = f }
        if let s = fontSize { style.fontSize = s }
    }

    /// Word's line under the box: "Font: Bold, Not Italic, 12 pt, Highlight; Style: Heading 1".
    public func describe(styleName: (String) -> String = { $0 }) -> String {
        var font: [String] = []
        if let f = fontFamily { font.append(f) }
        if let s = fontSize { font.append((s == s.rounded() ? String(Int(s)) : String(s)) + " pt") }
        func flag(_ v: Bool?, _ name: String) { if let v { font.append(v ? name : "Not " + name) } }
        flag(bold, "Bold"); flag(italic, "Italic"); flag(underline, "Underline"); flag(strikethrough, "Strikethrough")
        var parts: [String] = []
        if !font.isEmpty { parts.append("Font: " + font.joined(separator: ", ")) }
        if let h = highlight { parts.append(h ? "Highlight" : "Not Highlight") }
        if let p = paragraphStyle { parts.append("Style: " + styleName(p)) }
        return parts.joined(separator: "; ")
    }
}
