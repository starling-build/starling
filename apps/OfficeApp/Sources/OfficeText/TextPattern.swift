// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The one text matcher behind Find and Replace in Writer, Slides and Sheets (U-shared).
// Plain Swift, no Foundation (the web build has no NSRegularExpression): a small
// backtracking engine over Characters. Plain text, Word-style wildcards and a regular-
// expression subset all compile to the same node tree, so match case, whole word and
// "entire cell" behave the same in every mode.
//
// Regex subset: . [set] [^set] \d \D \w \W \s \S \b \B \n \t ^ $ ( ) (?: ) | * + ? {n} {n,} {n,m}
// and lazy forms (*? +? ??). Replacement text: $1..$9 groups, $& the whole match, $$ a dollar.
// Wildcards: ? one character, * any run, [abc] [!abc] a set, < > word start and end,
// \ makes the next character literal.

public enum FindMode: Equatable, Sendable {
    case plain, wildcards, regex
}

public struct FindOptions: Equatable, Sendable {
    public var matchCase = false
    /// The match must not touch a letter or digit on either side.
    public var wholeWord = false
    /// The match must be the whole text (a Sheets cell).
    public var entireCell = false
    public var mode: FindMode = .plain
    public init(matchCase: Bool = false, wholeWord: Bool = false, entireCell: Bool = false, mode: FindMode = .plain) {
        self.matchCase = matchCase
        self.wholeWord = wholeWord
        self.entireCell = entireCell
        self.mode = mode
    }
}

public struct FindPatternError: Error, Equatable, CustomStringConvertible {
    public let description: String
}

public struct TextMatch: Equatable {
    public let range: Range<String.Index>
    /// Group 1... (index 0 is group 1); nil for a group that did not take part.
    public let groups: [Range<String.Index>?]
}

public final class TextPattern {
    indirect enum Node {
        case char(Character)
        case any
        case set([ClosedRange<Character>], negated: Bool)
        case start, end, wordEdge, notWordEdge, wordStart, wordEnd
        case group(Int?, [[Node]])
        case rep(Node, Int, Int, lazy: Bool)
    }

    private let alternatives: [[Node]]
    private let groupCount: Int
    /// The options this pattern was made with.
    public let options: FindOptions

    public init(_ query: String, _ options: FindOptions) throws {
        guard !query.isEmpty else { throw FindPatternError(description: "Nothing to find") }
        var p = Parser(Array(query), mode: options.mode)
        let alts = try p.parseTop()
        self.alternatives = alts
        self.groupCount = p.groups
        self.options = options
    }

    /// Why `query` cannot be used as a pattern, or nil when it can.
    public static func problem(_ query: String, _ options: FindOptions) -> String? {
        do { _ = try TextPattern(query, options); return nil } catch { return "\(error)" }
    }

    // MARK: Searching

    /// Every non-empty match, left to right, not overlapping.
    public func matches(in text: String) -> [TextMatch] {
        let (chars, idx) = Self.split(text)
        var out: [TextMatch] = []
        var at = 0
        while at <= chars.count, let m = match(chars, idx, from: at) {
            out.append(m.0)
            at = max(m.1, at + 1)
        }
        return out
    }

    /// The first match starting at or after `from`, or the last one starting before `from` when `backwards`.
    public func firstMatch(in text: String, from: String.Index, backwards: Bool = false) -> TextMatch? {
        let (chars, idx) = Self.split(text)
        let f = idx.firstIndex { $0 >= from } ?? chars.count
        if !backwards { return match(chars, idx, from: f)?.0 }
        var last: TextMatch?
        for at in 0 ..< f {
            if let m = match(chars, idx, from: at, anchored: true) { last = m.0 }
        }
        return last
    }

    /// `template` with $1..$9, $& and $$ filled in (regex mode only; other modes return it unchanged).
    public func replacement(_ template: String, for m: TextMatch, in text: String) -> String {
        guard options.mode == .regex, template.contains(Character("$")) else { return template }
        var out = ""
        let t = Array(template)
        var i = 0
        while i < t.count {
            if t[i] == "$", i + 1 < t.count {
                let n = t[i + 1]
                if n == "$" { out.append("$"); i += 2; continue }
                if n == "&" { out += text[m.range]; i += 2; continue }
                if let d = n.wholeNumberValue, d >= 1, d <= 9 {
                    if d <= m.groups.count, let r = m.groups[d - 1] { out += text[r] }
                    i += 2
                    continue
                }
            }
            out.append(t[i])
            i += 1
        }
        return out
    }

    private static func split(_ text: String) -> ([Character], [String.Index]) {
        var chars: [Character] = []
        var idx: [String.Index] = []
        var i = text.startIndex
        while i < text.endIndex {
            idx.append(i)
            chars.append(text[i])
            i = text.index(after: i)
        }
        idx.append(text.endIndex)
        return (chars, idx)
    }

    // MARK: Matching

    private struct State {
        var chars: [Character]
        var caps: [(Int, Int)?]
        var steps = 0
    }
    private static let stepLimit = 400_000

    private func match(_ chars: [Character], _ idx: [String.Index], from: Int, anchored: Bool = false) -> (TextMatch, Int)? {
        var st = State(chars: chars, caps: Array(repeating: nil, count: groupCount))
        var s = from
        while s <= chars.count {
            if options.entireCell && s > 0 { return nil }
            var endPos = -1
            let ok = run([.group(nil, alternatives)], 0, s, &st) { e, st in
                if self.options.entireCell && e != st.chars.count { return false }
                if self.options.wholeWord {
                    if s > 0, Self.isWord(st.chars[s - 1]), e > s, Self.isWord(st.chars[s]) { return false }
                    if e < st.chars.count, e > s, Self.isWord(st.chars[e]), Self.isWord(st.chars[e - 1]) { return false }
                    if s > 0, Self.isWord(st.chars[s - 1]), e == s { return false }
                }
                if e == s { return false }   // an empty match is not a hit
                endPos = e
                return true
            }
            if st.steps > Self.stepLimit { return nil }
            if ok {
                let groups = st.caps.map { c in c.map { idx[$0.0] ..< idx[$0.1] } }
                return (TextMatch(range: idx[s] ..< idx[endPos], groups: groups), endPos)
            }
            if anchored { return nil }
            s += 1
        }
        return nil
    }

    static func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    private func same(_ a: Character, _ b: Character) -> Bool {
        if a == b { return true }
        if options.matchCase { return false }
        return String(a).lowercased() == String(b).lowercased()
    }

    private func inSet(_ c: Character, _ ranges: [ClosedRange<Character>], _ neg: Bool) -> Bool {
        var hit = ranges.contains { $0.contains(c) }
        if !hit && !options.matchCase {
            let l = Character(String(c).lowercased()), u = Character(String(c).uppercased())
            hit = ranges.contains { $0.contains(l) || $0.contains(u) }
        }
        return hit != neg
    }

    /// Match `nodes[i...]` at `pos`, then `k` with the end position.
    private func run(_ nodes: [Node], _ i: Int, _ pos: Int, _ st: inout State,
                     _ k: (Int, inout State) -> Bool) -> Bool {
        st.steps += 1
        if st.steps > Self.stepLimit { return false }
        if i == nodes.count { return k(pos, &st) }
        let n = st.chars.count
        switch nodes[i] {
        case .char(let c):
            guard pos < n, same(st.chars[pos], c) else { return false }
            return run(nodes, i + 1, pos + 1, &st, k)
        case .any:
            guard pos < n, !st.chars[pos].isNewline else { return false }
            return run(nodes, i + 1, pos + 1, &st, k)
        case .set(let r, let neg):
            guard pos < n, inSet(st.chars[pos], r, neg) else { return false }
            return run(nodes, i + 1, pos + 1, &st, k)
        case .start:
            guard pos == 0 || st.chars[pos - 1].isNewline else { return false }
            return run(nodes, i + 1, pos, &st, k)
        case .end:
            guard pos == n || st.chars[pos].isNewline else { return false }
            return run(nodes, i + 1, pos, &st, k)
        case .wordEdge, .notWordEdge, .wordStart, .wordEnd:
            let before = pos > 0 && Self.isWord(st.chars[pos - 1])
            let after = pos < n && Self.isWord(st.chars[pos])
            let ok: Bool
            switch nodes[i] {
            case .wordEdge: ok = before != after
            case .notWordEdge: ok = before == after
            case .wordStart: ok = !before && after
            default: ok = before && !after
            }
            guard ok else { return false }
            return run(nodes, i + 1, pos, &st, k)
        case .group(let num, let alts):
            for alt in alts {
                let saved = num.map { st.caps[$0] }
                let hit = run(alt, 0, pos, &st) { e, st in
                    let old = num.map { st.caps[$0] }
                    if let num { st.caps[num] = (pos, e) }
                    if self.run(nodes, i + 1, e, &st, k) { return true }
                    if let num { st.caps[num] = old! }
                    return false
                }
                if hit { return true }
                if let num { st.caps[num] = saved! }
            }
            return false
        case .rep(let inner, let lo, let hi, let lazy):
            return rep(inner, lo, hi, lazy, 0, pos, nodes, i, &st, k)
        }
    }

    private func rep(_ inner: Node, _ lo: Int, _ hi: Int, _ lazy: Bool, _ count: Int, _ pos: Int,
                     _ nodes: [Node], _ i: Int, _ st: inout State, _ k: (Int, inout State) -> Bool) -> Bool {
        func more(_ st: inout State) -> Bool {
            guard count < hi else { return false }
            return run([inner], 0, pos, &st) { e, st in
                if e == pos && count >= lo { return false }   // no progress: stop looping
                return self.rep(inner, lo, hi, lazy, count + 1, e, nodes, i, &st, k)
            }
        }
        func done(_ st: inout State) -> Bool {
            count >= lo && run(nodes, i + 1, pos, &st, k)
        }
        if lazy { return done(&st) || more(&st) }
        return more(&st) || done(&st)
    }

    // MARK: Parsing

    struct Parser {
        let s: [Character]
        let mode: FindMode
        var i = 0
        var groups = 0
        init(_ s: [Character], mode: FindMode) { self.s = s; self.mode = mode }

        mutating func parseTop() throws -> [[Node]] {
            switch mode {
            case .plain: return [s.map { .char($0) }]
            case .wildcards: return [try wildcards()]
            case .regex:
                let alts = try alternatives()
                if i < s.count { throw FindPatternError(description: "Unmatched )") }
                return alts
            }
        }

        mutating func wildcards() throws -> [Node] {
            var out: [Node] = []
            while i < s.count {
                let c = s[i]; i += 1
                switch c {
                case "?": out.append(.any)
                case "*": out.append(.rep(.any, 0, Int.max, lazy: true))
                case "<": out.append(.wordStart)
                case ">": out.append(.wordEnd)
                case "[":
                    out.append(try bracket())
                case "\\":
                    guard i < s.count else { throw FindPatternError(description: "Nothing after \\") }
                    out.append(.char(s[i])); i += 1
                default: out.append(.char(c))
                }
            }
            return out
        }

        /// After "[": a set; `!` or `^` first negates.
        mutating func bracket() throws -> Node {
            var neg = false
            if i < s.count, s[i] == "^" || (mode == .wildcards && s[i] == "!") { neg = true; i += 1 }
            var ranges: [ClosedRange<Character>] = []
            var first = true
            while i < s.count, s[i] != "]" || first {
                first = false
                var c = s[i]; i += 1
                if c == "\\", i < s.count {
                    let e = s[i]; i += 1
                    if mode == .regex, let cls = Parser.classRanges(e) { ranges += cls; continue }
                    c = e
                }
                if i + 1 < s.count, s[i] == "-", s[i + 1] != "]" {
                    let hi = s[i + 1]; i += 2
                    guard c <= hi else { throw FindPatternError(description: "Backwards range in [ ]") }
                    ranges.append(c ... hi)
                } else {
                    ranges.append(c ... c)
                }
            }
            guard i < s.count else { throw FindPatternError(description: "Missing ]") }
            i += 1
            return .set(ranges, negated: neg)
        }

        static func classRanges(_ e: Character) -> [ClosedRange<Character>]? {
            switch e {
            case "d": return ["0" ... "9"]
            case "w": return ["a" ... "z", "A" ... "Z", "0" ... "9", "_" ... "_"]
            case "s": return [" " ... " ", "\t" ... "\r"]
            default: return nil
            }
        }

        mutating func alternatives() throws -> [[Node]] {
            var alts: [[Node]] = [[]]
            while i < s.count, s[i] != ")" {
                if s[i] == "|" { i += 1; alts.append([]); continue }
                var atom = try self.atom()
                atom = try quantified(atom)
                alts[alts.count - 1].append(atom)
            }
            return alts
        }

        mutating func atom() throws -> Node {
            let c = s[i]; i += 1
            switch c {
            case ".": return .any
            case "^": return .start
            case "$": return .end
            case "[": return try bracket()
            case "(":
                var num: Int? = nil
                if i + 1 < s.count, s[i] == "?", s[i + 1] == ":" { i += 2 } else { num = groups; groups += 1 }
                let alts = try alternatives()
                guard i < s.count, s[i] == ")" else { throw FindPatternError(description: "Missing )") }
                i += 1
                return .group(num, alts)
            case "*", "+", "?": throw FindPatternError(description: "Nothing to repeat before \(c)")
            case "\\":
                guard i < s.count else { throw FindPatternError(description: "Nothing after \\") }
                let e = s[i]; i += 1
                switch e {
                case "b": return .wordEdge
                case "B": return .notWordEdge
                case "n": return .char("\n")
                case "t": return .char("\t")
                case "D", "W", "S":
                    return .set(Parser.classRanges(Character(e.lowercased()))!, negated: true)
                default:
                    if let r = Parser.classRanges(e) { return .set(r, negated: false) }
                    return .char(e)
                }
            default: return .char(c)
            }
        }

        mutating func quantified(_ a: Node) throws -> Node {
            guard i < s.count else { return a }
            var lo = 0, hi = Int.max
            switch s[i] {
            case "*": i += 1
            case "+": lo = 1; i += 1
            case "?": hi = 1; i += 1
            case "{":
                var j = i + 1, a1 = "", b1 = "", comma = false
                while j < s.count, s[j] != "}" {
                    if s[j] == "," { comma = true } else if s[j].isNumber { if comma { b1.append(s[j]) } else { a1.append(s[j]) } } else { return a }
                    j += 1
                }
                guard j < s.count, let l = Int(a1) else { return a }
                lo = l
                hi = comma ? (b1.isEmpty ? Int.max : Int(b1) ?? Int.max) : l
                guard lo <= hi else { throw FindPatternError(description: "Bad repeat count") }
                i = j + 1
            default: return a
            }
            var lazy = false
            if i < s.count, s[i] == "?" { lazy = true; i += 1 }
            return .rep(a, lo, hi, lazy: lazy)
        }
    }
}
