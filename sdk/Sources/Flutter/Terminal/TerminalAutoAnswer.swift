// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Typing the answer to a question nobody read.
//
// `~/.config/starling-terminal/autoanswer` pairs a pattern with the keys to
// type when that pattern is on screen:
//
//     # <pattern>                    <keys>
//     "Do you want to proceed?"      \r
//     "Overwrite? [y/N]"             y\r
//     /Continue\? \(y\/n\)/i         y\r
//
// That is the whole idea, and the honesty of the feature is in how little it
// is: a substring search over the visible grid, then a write to the child.
// Nothing here reads the question. It cannot tell "Overwrite the draft?" from
// "Delete the volume?", and it will confirm the second as cheerfully as the
// first. The user writes the patterns and owns what they confirm. Two things
// keep that from being worse than it sounds:
//
//   - Nothing is armed unless the file exists, and no rule ships with the
//     terminal. An empty install answers nothing.
//   - Every fire raises the badge in the corner of the pane that answered
//     (TerminalView's HUD). Keys typed by a machine must not be
//     indistinguishable from keys typed by a person.
//
// THE SCREEN, SETTLED. Matching runs over the visible grid only — never the
// scrollback, so a prompt that has scrolled away cannot fire again — and only
// once output has stopped for `settle` (300 ms by default). Both halves are
// load bearing. A TUI paints its prompt in pieces, and matching a half-drawn
// frame answers a question the program has not finished asking; matching the
// scrollback would make every prompt ever answered a permanent trigger.
//
// ONCE PER PROMPT, and the hard part is what "a prompt" is. Two questions that
// look identical are not the same question, and the same question redrawn
// thirty times is not thirty questions. A rule that simply fired whenever its
// pattern was on screen gets both wrong, in both directions:
//
//   - A spinner is enough to make it loop. The prompt is still up, the frame
//     changes ten times a second, and every frame is a fresh "the pattern is
//     on screen" — so it types its keys again, and again, into whatever the
//     program did next.
//   - A shell prompt answered in line mode STAYS ON SCREEN, answer and all.
//     `Overwrite? [y/N] y` still contains `Overwrite?`. Suppressing the
//     re-fire by waiting for the pattern to leave the screen means the second
//     file never gets answered, because the first question is still sitting
//     three lines up.
//
// So a prompt is identified by WHERE it is — the line it occupies, counted
// from the start of the session rather than from the top of the screen, so
// that scrolling does not rename it. A rule answers a given line once, ever.
// A prompt redrawn in place keeps its line and is answered once; the next
// question is on a different line and is answered on its own account.
//
// That leaves one case: a full-screen program that draws its second prompt in
// exactly the same box as the first, so the two share a line. The answer is
// that the set of answered lines is FORGOTTEN whenever a settled screen
// matches no rule at all — the box came down, whatever we answered is gone,
// and nothing on screen is a question we have already dealt with. In a TUI
// that happens between every pair of prompts. In line mode it never happens
// while the old prompt is still visible, which is exactly when the memory is
// the thing doing the work.
//
// The matching half deliberately depends on Foundation and nothing else: it is
// compiled standalone by test/run.sh's fast tier, the same way the workspace
// codec is, so the parser and the latch are gated on every change with no GPU
// and no terminal.

import Foundation

/// Rules that answer prompts on the visible screen, and the state that keeps
/// one prompt from being answered twice.
///
/// One instance per session — the latch is per-screen, so sharing an instance
/// between two panes would let a prompt answered in one suppress the identical
/// prompt in the other. `TerminalSession.autoAnswer` owns it; `match(_:)` is
/// called on the main queue after the settle interval and nowhere else.
public final class TerminalAutoAnswer {

    /// One line of the file: what to look for, and what to type.
    public struct Rule {
        /// As written, for the badge and the log — never re-parsed from this.
        public let pattern: String
        /// The keys, escapes already decoded. Written to the child verbatim.
        public let reply: String
        /// 1-based line in the file, so a complaint can name it.
        public let line: Int

        fileprivate let kind: Kind
    }

    fileprivate enum Kind {
        /// Whitespace-collapsed and lowercased, to be found in a screen
        /// normalized the same way.
        case literal(String)
        case regex(NSRegularExpression)
    }

    /// In file order. The first that matches wins, which is what makes a
    /// narrow rule above a broad one mean something.
    public private(set) var rules: [Rule] = []

    /// What the last parse could not use. Lines are dropped, never guessed at:
    /// a rule that half-parsed would answer prompts its author did not write.
    public private(set) var problems: [String] = []

    /// How long output must stop before the screen is read. Long enough for a
    /// TUI to finish painting, short enough not to feel like a hang.
    public private(set) var settle: TimeInterval = 0.3

    /// Cheap enough for the output path, which asks on every chunk. False
    /// means the session never even schedules a settle check.
    ///
    /// It reflects the file as of the last read, so a file that did not exist
    /// when the pane started stays unarmed until a new pane reads it. Editing
    /// a file that already has rules in it does take effect live — that is the
    /// case worth supporting, because it is the one you iterate in.
    public var isArmed: Bool { !rules.isEmpty }

    /// Where the terminal looks unless told otherwise.
    public static var defaultPath: String {
        realUserHomeDirectory() + "/.config/starling-terminal/autoanswer"
    }

    /// A shortest sane literal. Two characters can sit inside an unrelated
    /// word on a line of build output and confirm something that was never a
    /// question; three is not much better, but it is a floor rather than none,
    /// and the alternative is a rule that fires on every screen.
    static let minimumPatternLength = 3

    /// No more than one answer this often, whatever the rules say.
    ///
    /// Answering each line once already bounds any one question. This bounds a
    /// SET of rules that set each other off, where every answer paints the
    /// screen — on new lines — that matches the next rule along.
    static let defaultMinimumInterval: TimeInterval = 0.5

    /// Per-instance so the tests can take the clock out of the picture. Not
    /// public: a rules file cannot turn the floor off.
    var minimumInterval: TimeInterval = TerminalAutoAnswer.defaultMinimumInterval

    private let path: String?
    /// Modification time and size of the file as last read. Size is in there
    /// because a modification time has one-second granularity on some
    /// filesystems, and two edits inside one second is exactly what iterating
    /// on a rule looks like.
    private var stamp: (Double, Int) = (-1, -1)

    /// A question already dealt with: which rule, and which line of the
    /// session it was on. Not which line of the SCREEN — a screen that scrolls
    /// one row would otherwise rename every prompt on it.
    private struct Answered: Equatable {
        let pattern: String
        let line: Int
    }

    /// Bounded because it is only ever consulted against what is on screen;
    /// anything older than a screenful of scrolling can never come up again.
    private var answered: [Answered] = []
    private static let answeredLimit = 128

    private var lastFire: TimeInterval = -.greatestFiniteMagnitude

    /// Rules from text, for tests and for an embedder with its own storage.
    public init(text: String) {
        path = nil
        apply(Self.parse(text))
    }

    /// Rules from a file, re-read when it changes. A missing file is not an
    /// error — it is the ordinary state, and it means no rules.
    public init(file: String) {
        path = file
        refreshIfChanged()
    }

    /// What to do about this screen.
    public enum Decision {
        /// Nothing on it is a question anyone wrote a rule for. The usual
        /// answer, by a wide margin.
        case nothing
        /// Type these keys.
        case fire(Rule)
        /// A rule matched, but the floor between two answers has not passed.
        /// Ask again after this long.
        ///
        /// Not the same as `nothing`, and the difference is a deadlock: the
        /// caller is driven by output, and a program that has asked a question
        /// produces none until it is answered. Dropping the match here means
        /// waiting for a chunk that is never coming — which is exactly how
        /// this read the first time it ran against a real shell, answering
        /// the first prompt of three and then sitting there.
        case tooSoon(TimeInterval)
    }

    /// The rule to fire for this screen, or why not.
    ///
    /// `lines` is the visible grid, one string per row. `baseLine` is what the
    /// first of those rows is counted as: the session's scrollback depth, so
    /// that a row keeps its number as the screen scrolls under it. That number
    /// is the whole of a prompt's identity — see the note at the top.
    ///
    /// Main queue only. It stats the rules file (and re-reads it when that
    /// changed), which is why it belongs at the settle point and not on the
    /// path that feeds bytes to the emulator.
    public func match(lines: [String], baseLine: Int) -> Decision {
        refreshIfChanged()
        guard !rules.isEmpty else { return .nothing }

        let collapsed = lines.map { Self.collapse($0).lowercased() }
        var matchedSomething = false

        for rule in rules {
            // The LAST occurrence, not the first: what is lowest on screen is
            // the most recent thing asked, and an older copy of the same
            // question higher up has either been answered already or scrolled
            // past being answerable.
            guard let row = (0 ..< lines.count).reversed().first(where: {
                rule.matches(collapsed: collapsed[$0], raw: lines[$0])
            }) else { continue }

            matchedSomething = true
            let key = Answered(pattern: rule.pattern, line: baseLine + row)
            // Already dealt with. Try the next rule rather than stopping: a
            // stale prompt one rule answered must not hide a live one another
            // rule is waiting for.
            if answered.contains(key) { continue }

            let now = Self.now()
            let waited = now - lastFire
            guard waited >= minimumInterval else {
                return .tooSoon(minimumInterval - waited)
            }
            answered.append(key)
            if answered.count > Self.answeredLimit { answered.removeFirst() }
            lastFire = now
            return .fire(rule)
        }

        // Nothing on a settled screen is a question at all, so nothing on it
        // is a question we have already answered. This is what lets a
        // full-screen program ask twice in the same box.
        if !matchedSomething { answered.removeAll() }
        return .nothing
    }

    /// Forget what has been answered — for a session being restarted, or a
    /// screen reset out from under the line numbers that identify a prompt.
    public func reset() {
        answered.removeAll()
        lastFire = -.greatestFiniteMagnitude
    }

    // MARK: - The file

    private func apply(_ parsed: (rules: [Rule], settle: TimeInterval, problems: [String])) {
        rules = parsed.rules
        settle = parsed.settle
        problems = parsed.problems
        // A reparse drops what was answered: those keys name rules that may
        // not exist any more, and a rule the user has just edited is one they
        // want to see fire.
        answered.removeAll()
    }

    private func refreshIfChanged() {
        guard let path = path else { return }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let now = (((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1),
                   ((attrs?[.size] as? Int) ?? -1))
        guard now != stamp else { return }
        stamp = now
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        apply(Self.parse(text))
        if !problems.isEmpty { logProblems(path) }
    }

    private func logProblems(_ path: String) {
        for problem in problems {
            FileHandle.standardError.write(
                Data("starling-terminal: \(path): \(problem)\n".utf8))
        }
    }

    // MARK: - Parsing

    static func parse(_ text: String)
        -> (rules: [Rule], settle: TimeInterval, problems: [String]) {
        var rules: [Rule] = []
        var problems: [String] = []
        var settle: TimeInterval = 0.3

        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated() {
            let number = index + 1
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            // A `#` only starts a comment at the start of a line. Mid-line it
            // is a character like any other, and prompts are full of them.
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if trimmed.hasPrefix("settle") {
                let rest = String(trimmed.dropFirst("settle".count))
                    .trimmingCharacters(in: .whitespaces)
                if let seconds = parseDuration(rest) {
                    settle = seconds
                } else {
                    problems.append("line \(number): settle wants a duration, e.g. `settle 300ms`")
                }
                continue
            }

            switch parseRule(trimmed, line: number) {
            case .rule(let rule): rules.append(rule)
            case .problem(let why): problems.append("line \(number): \(why)")
            }
        }
        return (rules, settle, problems)
    }

    /// `300ms`, `0.5s`, or a bare number of milliseconds. Clamped: a settle of
    /// zero matches half-painted frames, and one of a minute is a hang.
    static func parseDuration(_ s: String) -> TimeInterval? {
        var text = s
        var scale = 0.001
        if text.hasSuffix("ms") { text.removeLast(2) }
        else if text.hasSuffix("s") { text.removeLast(); scale = 1 }
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)),
              value.isFinite else { return nil }
        return min(max(value * scale, 0.05), 10)
    }

    /// A line is either a rule or a complaint about a line. Never both, and
    /// never a partially-understood rule: half a pattern would answer prompts
    /// its author did not write.
    private enum Parsed {
        case rule(Rule)
        case problem(String)
    }

    private static func parseRule(_ line: String, line number: Int) -> Parsed {
        let cs = Array(line)
        var i = 0
        var pattern = ""
        var delimiter: Character?

        if cs[0] == "\"" || cs[0] == "/" {
            let quote = cs[0]
            delimiter = quote
            i = 1
            var closed = false
            while i < cs.count {
                // Backslashes are kept, not consumed: a literal still has to
                // go through the escape decoder, and a regex needs its own
                // `\?` to reach NSRegularExpression intact.
                if cs[i] == "\\", i + 1 < cs.count {
                    pattern.append(cs[i]); pattern.append(cs[i + 1]); i += 2; continue
                }
                if cs[i] == quote { closed = true; i += 1; break }
                pattern.append(cs[i]); i += 1
            }
            guard closed else { return .problem("unterminated \(quote)") }
        } else {
            while i < cs.count, !cs[i].isWhitespace { pattern.append(cs[i]); i += 1 }
        }

        var flags = ""
        if delimiter == "/" {
            while i < cs.count, !cs[i].isWhitespace { flags.append(cs[i]); i += 1 }
        }

        while i < cs.count, cs[i] == " " || cs[i] == "\t" { i += 1 }
        let keys = i < cs.count ? String(cs[i...]) : ""
        guard !keys.isEmpty else {
            return .problem("a pattern with nothing to type after it")
        }
        let reply = decode(keys)

        let kind: Kind
        if delimiter == "/" {
            var options: NSRegularExpression.Options = []
            if flags.contains("i") { options.insert(.caseInsensitive) }
            for flag in flags where flag != "i" {
                return .problem("unknown regex flag `\(flag)` (only `i` is understood)")
            }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options)
            else { return .problem("not a usable regular expression") }
            kind = .regex(regex)
        } else {
            let literal = decode(pattern)
            guard literal.count >= minimumPatternLength else {
                return .problem(
                    "`\(literal)` is too short to match on — \(minimumPatternLength) characters or more")
            }
            kind = .literal(collapse(literal).lowercased())
        }
        return .rule(Rule(pattern: pattern, reply: reply, line: number, kind: kind))
    }

    /// Escapes, in patterns and in keys alike. `\r` is the one that matters —
    /// it is Enter, and it is what most of these rules are.
    static func decode(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        let it = Array(s)
        var i = 0
        while i < it.count {
            guard it[i] == "\\", i + 1 < it.count else { out.append(it[i]); i += 1; continue }
            let c = it[i + 1]
            i += 2
            switch c {
            case "r": out.append("\r")
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "e": out.append("\u{1B}")
            case "a": out.append("\u{07}")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "0": out.append("\u{00}")
            // The one way to send a space that a trailing-whitespace trim
            // cannot eat.
            case "s": out.append(" ")
            case "\\": out.append("\\")
            case "x":
                let hex = String(it[i ..< min(i + 2, it.count)])
                if hex.count == 2, let byte = UInt8(hex, radix: 16),
                   let scalar = UnicodeScalar(UInt32(byte)) {
                    out.append(Character(scalar))
                    i += 2
                } else {
                    out.append("\\"); out.append("x")
                }
            case "C":
                // `\C-c` is Ctrl+C, spelled the way a person says it.
                if i + 1 < it.count, it[i] == "-",
                   let ascii = it[i + 1].asciiValue {
                    out.append(Character(UnicodeScalar(ascii & 0x1F)))
                    i += 2
                } else {
                    out.append("\\"); out.append("C")
                }
            default:
                // An escape nobody defined is the character itself. Guessing
                // would turn a typo into a keystroke.
                out.append(c)
            }
        }
        return out
    }

    // MARK: - Normalizing

    /// Collapse runs of spaces and tabs in one line, and trim its ends.
    ///
    /// A prompt is usually inside a box — `│  Do you want to proceed?      │`
    /// — and that padding is layout, not text. A rule should not have to count
    /// spaces to match a question a person can read at a glance.
    ///
    /// One LINE, because a pattern matches a line. Matching across rows would
    /// let a literal join the tail of one line to the head of the next and
    /// find a question that is nowhere on screen, and it would leave a match
    /// with no single row to call its position — which is the one thing a
    /// prompt's identity is built on.
    static func collapse(_ line: String) -> String {
        var out = ""
        out.reserveCapacity(line.count)
        var pendingSpace = false
        for ch in line {
            if ch == " " || ch == "\t" {
                if !out.isEmpty { pendingSpace = true }
            } else {
                if pendingSpace { out.append(" "); pendingSpace = false }
                out.append(ch)
            }
        }
        return out
    }

    static func now() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

extension TerminalAutoAnswer.Rule {
    /// One row of the screen. `collapsed` is it normalized the way literals
    /// are; `raw` is it as it stands, because a regex was written against real
    /// spacing and is the escape hatch for when that matters.
    fileprivate func matches(collapsed: String, raw: String) -> Bool {
        switch kind {
        case .literal(let needle):
            return collapsed.contains(needle)
        case .regex(let regex):
            let range = NSRange(raw.startIndex ..< raw.endIndex, in: raw)
            return regex.firstMatch(in: raw, options: [], range: range) != nil
        }
    }
}
