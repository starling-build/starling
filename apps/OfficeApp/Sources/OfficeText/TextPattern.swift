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
// (…) a group, {n} {n,} {n,m} @ repeat the one before, \ makes the next character literal;
// in the replacement \1..\9 put a group back.
// Word's special characters (^ codes), in Normal and Wildcards: ^p (^13) paragraph mark,
// ^t tab, ^l manual line break, ^^ caret, ^s nonbreaking space, ^~ nonbreaking hyphen,
// ^- optional hyphen, ^+ em dash, ^= en dash, ^nnn / ^unnnn a character by code; Normal
// only: ^? any character, ^# any digit, ^$ any letter, ^w white space. In the replacement
// also ^& (what was found). A paragraph mark is `TextPattern.paragraphMark` in the text.

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
    /// Word's Match prefix / Match suffix: the match must start (end) a word.
    public var matchPrefix = false
    public var matchSuffix = false
    /// Word's Ignore punctuation / white-space characters (Normal mode): the text may hold
    /// any of them between the query's characters, and the query's own are dropped.
    public var ignorePunctuation = false
    public var ignoreSpace = false
    public init(matchCase: Bool = false, wholeWord: Bool = false, entireCell: Bool = false, mode: FindMode = .plain,
                matchPrefix: Bool = false, matchSuffix: Bool = false, ignorePunctuation: Bool = false, ignoreSpace: Bool = false) {
        self.matchCase = matchCase
        self.wholeWord = wholeWord
        self.entireCell = entireCell
        self.mode = mode
        self.matchPrefix = matchPrefix
        self.matchSuffix = matchSuffix
        self.ignorePunctuation = ignorePunctuation
        self.ignoreSpace = ignoreSpace
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
        case pred(Pred)
    }
    enum Pred { case letter, digit, white, ignorable(punct: Bool, space: Bool) }

    /// The paragraph mark in the text a pattern searches (`^p`, `^13`): searching across
    /// paragraphs joins them with it.
    public static let paragraphMark: Character = "\u{2029}"
    /// The pattern can match a paragraph mark: search the paragraphs joined, not one at a time.
    public let spansParagraphs: Bool

    private let alternatives: [[Node]]
    private let groupCount: Int
    /// The options this pattern was made with.
    public let options: FindOptions

    public init(_ query: String, _ options: FindOptions) throws {
        guard !query.isEmpty else { throw FindPatternError(description: "Nothing to find") }
        var p = Parser(Array(query), mode: options.mode, options: options)
        let alts = try p.parseTop()
        self.alternatives = alts
        self.spansParagraphs = p.usesMark
        self.groupCount = p.groups
        self.options = options
    }

    /// Set on `anyText`: Find what was empty and a format was set, so what is looked for is the
    /// stretches of text that have the format (the controller finds them; this matches nothing).
    public private(set) var matchesAnyText = false

    /// The pattern for an empty Find what with a format.
    public static func anyText(_ options: FindOptions = FindOptions()) -> TextPattern {
        var o = options; o.mode = .plain
        let p = try! TextPattern("\u{0}\u{0}\u{0}", o)
        p.matchesAnyText = true
        return p
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

    /// `template` with what it refers to filled in: $1..$9, $& and $$ (regex); ^ codes, ^& the
    /// match (Normal, Wildcards); \\1..\\9 groups (Wildcards). A paragraph mark comes out as
    /// `paragraphMark`, a manual page break as U+000C.
    public func replacement(_ template: String, for m: TextMatch, in text: String) -> String {
        guard options.mode == .regex else { return wordReplacement(template, m, text) }
        guard template.contains(Character("$")) else { return template }
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

    private func wordReplacement(_ template: String, _ m: TextMatch, _ text: String) -> String {
        var out = ""
        let t = Array(template)
        var i = 0
        while i < t.count {
            let c = t[i]; i += 1
            if c == "\\", options.mode == .wildcards, i < t.count {
                let n = t[i]; i += 1
                if let d = n.wholeNumberValue, d >= 1, d <= 9 {
                    if d <= m.groups.count, let r = m.groups[d - 1] { out += text[r] }
                } else { out.append(n) }
                continue
            }
            guard c == "^", i < t.count else { out.append(c); continue }
            if t[i] == "&" { out += text[m.range]; i += 1; continue }
            if t[i] == "m" { out.append("\u{000C}"); i += 1; continue }
            var j = i
            if let ch = Parser.specialChar(t, &j) { out.append(ch); i = j } else { out.append(c) }
        }
        return out
    }

    /// Why `template` cannot be a replacement in `mode`, or nil when it can (Word refuses an
    /// unknown ^ code, and a find-only one like ^? or ^#).
    public static func replacementProblem(_ template: String, _ mode: FindMode) -> String? {
        guard mode != .regex else { return nil }
        let t = Array(template)
        var i = 0
        while i < t.count {
            let c = t[i]; i += 1
            if c == "\\", mode == .wildcards { i += 1; continue }
            guard c == "^" else { continue }
            guard i < t.count else { return "^ needs a special character after it" }
            if t[i] == "&" || t[i] == "m" { i += 1; continue }
            var j = i
            guard Parser.specialChar(t, &j) != nil else { return "^\(t[i]) is not a valid special character for the Replace With box" }
            i = j
        }
        return nil
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
                if self.options.matchPrefix, s > 0, Self.isWord(st.chars[s - 1]), s < st.chars.count, Self.isWord(st.chars[s]) { return false }
                if self.options.matchSuffix, e < st.chars.count, e > 0, Self.isWord(st.chars[e]), Self.isWord(st.chars[e - 1]) { return false }
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

    /// White space as Word's ^w and Ignore white-space take it: spaces, tabs, nonbreaking spaces (not a mark or a line break).
    static func isWhite(_ c: Character) -> Bool { c == " " || c == "\t" || c == "\u{00A0}" || c == "\u{3000}" || c == "\u{2002}" || c == "\u{2003}" }

    static func test(_ p: Pred, _ c: Character) -> Bool {
        switch p {
        case .letter: return c.isLetter
        case .digit: return c.isNumber && c.isASCII
        case .white: return isWhite(c)
        case .ignorable(let punct, let space): return (punct && c.isPunctuation) || (space && isWhite(c))
        }
    }

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
        case .pred(let p):
            guard pos < n, Self.test(p, st.chars[pos]) else { return false }
            return run(nodes, i + 1, pos + 1, &st, k)
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
        let options: FindOptions
        var i = 0
        var groups = 0
        /// The pattern names a paragraph mark.
        var usesMark = false
        init(_ s: [Character], mode: FindMode, options: FindOptions = FindOptions()) { self.s = s; self.mode = mode; self.options = options }

        mutating func parseTop() throws -> [[Node]] {
            switch mode {
            case .plain: return [try plain()]
            case .wildcards:
                let seq = try wildcards()
                if i < s.count { throw FindPatternError(description: "Unmatched )") }
                return [seq]
            case .regex:
                let alts = try alternatives()
                if i < s.count { throw FindPatternError(description: "Unmatched )") }
                return alts
            }
        }

        /// Normal mode: the characters as they are, but for ^ codes; with Ignore punctuation /
        /// white-space, the query's own such characters dropped and any run of them allowed between.
        mutating func plain() throws -> [Node] {
            var out: [Node] = []
            while i < s.count {
                let c = s[i]; i += 1
                if c == "^" { out.append(try special()) } else { out.append(.char(c)) }
            }
            let punct = options.ignorePunctuation, space = options.ignoreSpace
            guard punct || space else { return out }
            let skip = Node.pred(.ignorable(punct: punct, space: space))
            let kept = out.filter { n in
                if case .char(let c) = n { return !TextPattern.test(.ignorable(punct: punct, space: space), c) }
                return true
            }
            var spaced: [Node] = []
            for (k, n) in kept.enumerated() {
                if k > 0 { spaced.append(.rep(skip, 0, Int.max, lazy: false)) }
                spaced.append(n)
            }
            return spaced.isEmpty ? out : spaced
        }

        /// The character a ^ code names (after the ^, at `j`), moving `j` past it; nil for an
        /// unknown code. Shared by Find what and Replace with.
        static func specialChar(_ s: [Character], _ j: inout Int) -> Character? {
            guard j < s.count else { return nil }
            let c = s[j]
            if c.isNumber || (c == "u" && j + 1 < s.count && s[j + 1].isNumber) {
                var k = c == "u" ? j + 1 : j, digits = ""
                while k < s.count, s[k].isNumber, s[k].isASCII, digits.count < 5 { digits.append(s[k]); k += 1 }
                guard let v = Int(digits), v > 0 else { return nil }
                j = k
                switch v {
                case 13: return paragraphMark
                case 11: return "\n"
                default: return Unicode.Scalar(v).map { Character($0) }
                }
            }
            let map: [Character: Character] = ["p": paragraphMark, "t": "\t", "l": "\n", "^": "^", "s": "\u{00A0}",
                                               "~": "\u{2011}", "-": "\u{00AD}", "+": "\u{2014}", "=": "\u{2013}"]
            guard let ch = map[c] else { return nil }
            j += 1
            return ch
        }

        /// After "^" in Find what.
        mutating func special() throws -> Node {
            guard i < s.count else { throw FindPatternError(description: "^ needs a special character after it") }
            let c = s[i]
            let wild = mode == .wildcards
            func notHere() -> FindPatternError {
                FindPatternError(description: "^\(c) is not a valid special character for the Find What box\(wild ? " when using wildcards" : "")")
            }
            switch c {
            case "?", "#", "$", "w":
                if wild { throw notHere() }
                i += 1
                switch c {
                case "?": return .any
                case "#": return .pred(.digit)
                case "$": return .pred(.letter)
                default: return .rep(.pred(.white), 1, Int.max, lazy: false)
                }
            case "p":
                if wild { throw notHere() }
            default: break
            }
            var j = i
            guard let ch = Parser.specialChar(s, &j) else { throw notHere() }
            i = j
            if ch == TextPattern.paragraphMark { usesMark = true }
            return .char(ch)
        }

        /// Wildcards up to an unmatched ")" or the end.
        mutating func wildcards() throws -> [Node] {
            var out: [Node] = []
            while i < s.count, s[i] != ")" {
                let c = s[i]; i += 1
                var atom: Node
                switch c {
                case "?": atom = .any
                case "*": out.append(.rep(.any, 0, Int.max, lazy: true)); continue
                case "<": out.append(.wordStart); continue
                case ">": out.append(.wordEnd); continue
                case "[": atom = try bracket()
                case "(":
                    let num = groups; groups += 1
                    let inner = try wildcards()
                    guard i < s.count, s[i] == ")" else { throw FindPatternError(description: "Missing )") }
                    i += 1
                    atom = .group(num, [inner])
                case "^": atom = try special()
                case "{", "@": throw FindPatternError(description: "Nothing to repeat before \(c)")
                case "\\":
                    guard i < s.count else { throw FindPatternError(description: "Nothing after \\") }
                    atom = .char(s[i]); i += 1
                default: atom = .char(c)
                }
                // {n} {n,} {n,m} and @ (one or more) repeat what is before them.
                if i < s.count, s[i] == "@" {
                    i += 1
                    atom = .rep(atom, 1, Int.max, lazy: false)
                } else if i < s.count, s[i] == "{" {
                    var j = i + 1, a1 = "", b1 = "", comma = false
                    while j < s.count, s[j] != "}" {
                        if s[j] == "," { comma = true } else if s[j].isNumber { if comma { b1.append(s[j]) } else { a1.append(s[j]) } }
                        else { throw FindPatternError(description: "Bad repeat count") }
                        j += 1
                    }
                    guard j < s.count, let lo = Int(a1) else { throw FindPatternError(description: "Bad repeat count") }
                    let hi = comma ? (b1.isEmpty ? Int.max : Int(b1) ?? Int.max) : lo
                    guard lo <= hi else { throw FindPatternError(description: "Bad repeat count") }
                    i = j + 1
                    atom = .rep(atom, lo, hi, lazy: false)
                }
                out.append(atom)
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
