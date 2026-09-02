// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The terminal's auto-answer rules: the parser, the screen match, and the
// latch that stops one prompt being answered twice.
//
//   swiftc -O autoanswer-test.swift \
//       ../../sdk/Sources/Flutter/Terminal/TerminalAutoAnswer.swift \
//       ../../sdk/Sources/Flutter/Platform/UserHome.swift
//   ./autoanswer-test
//
// test/run.sh does exactly that. Compiled standalone because the matching half
// depends on Foundation and nothing else — no emulator, no PTY, no GPU — and
// this is the half where a mistake types a `y` into something that was not
// asking a yes/no question.
//
// The checks are grouped by the way each one could go wrong in a real session:
// a rule that fires when it should not, a rule that fires more than once, a
// rule that silently never fires because the file did not parse.

import Foundation

var failures: [String] = []

func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        print("  ok    \(name)")
    } else {
        print("  FAIL  \(name)\(detail().isEmpty ? "" : "  — " + detail())")
        failures.append(name)
    }
}

/// A matcher with the clock out of the way — every test that is not ABOUT
/// the timing wants to fire twice in a row without sleeping. `wait 0` goes in
/// front of the rules so they answer as soon as they match.
func rules(_ text: String) -> TerminalAutoAnswer {
    let a = TerminalAutoAnswer(text: "wait 0\n" + text)
    a.minimumInterval = 0
    return a
}

/// A screen the way the emulator hands one over: one string per row.
func screen(_ lines: String...) -> [String] { lines }

extension TerminalAutoAnswer {
    /// The rule fired, if one was. A screen that has never scrolled unless
    /// `from:` says otherwise — that number is what tells one question from
    /// the next, so anything testing prompt IDENTITY passes its own.
    func match(_ lines: [String], from baseLine: Int = 0) -> Rule? {
        if case .fire(let rule) = match(lines: lines, baseLine: baseLine) {
            return rule
        }
        return nil
    }

    /// Seconds still to wait, if a question was found and is being left for a
    /// human. The difference between this and "no question here" is what stops
    /// a program that is WAITING for its answer from waiting for ever, so it
    /// is worth a check of its own.
    func waiting(_ lines: [String], from baseLine: Int = 0) -> TimeInterval? {
        if case .waiting(_, let left) = match(lines: lines, baseLine: baseLine) {
            return left
        }
        return nil
    }

    /// Why a wait ended with nothing typed, if that is what just happened.
    func cancelled(_ lines: [String], from baseLine: Int = 0)
        -> TerminalAutoAnswer.Cancellation? {
        if case .cancelled(_, let why) = match(lines: lines, baseLine: baseLine) {
            return why
        }
        return nil
    }
}

@main
struct AutoAnswerTest {
  static func main() {
    // MARK: - Parsing

    print("\nparsing")

    do {
        // Not the `rules` helper here: it prepends a line, and one of these
        // checks is about which line a rule came from.
        let a = TerminalAutoAnswer(text: """
            # a comment
            settle 250ms

            "Do you want to proceed?"    \\r
            overwrite?                   y\\r
            /Continue\\? \\(y\\/n\\)/i     y\\r
            """)
        check("three rules and a directive", a.rules.count == 3, "\(a.rules.count)")
        check("no complaints", a.problems.isEmpty, "\(a.problems)")
        check("settle is read", abs(a.settle - 0.25) < 1e-9, "\(a.settle)")
        check("armed", a.isArmed)
        check("\\r decodes to Enter", a.rules[0].reply == "\r", "\(Array(a.rules[0].reply.utf8))")
        check("keys after the pattern are kept whole", a.rules[1].reply == "y\r")
        check("the rule remembers its line", a.rules[2].line == 6, "\(a.rules[2].line)")
    }

    do {
        // Every one of these is a rule that would otherwise have looked fine in
        // the file and done nothing at all in the terminal.
        let a = rules("""
            "unterminated                 \\r
            "no keys after me"
            ab                            y
            /[unclosed/                    y
            /ok/z                          y
            """)
        check("a bad file yields no rules", a.rules.isEmpty, "\(a.rules.count)")
        check("and one complaint per bad line", a.problems.count == 5, "\(a.problems)")
        check("unterminated quote is named", a.problems[0].contains("unterminated"))
        check("a pattern with nothing to type is named",
              a.problems[1].contains("nothing to type"))
        check("a two-character pattern is refused", a.problems[2].contains("too short"))
        check("a broken regex is refused", a.problems[3].contains("regular expression"))
        check("an unknown regex flag is refused", a.problems[4].contains("flag"))
        check("nothing armed", !a.isArmed)
    }

    do {
        let a = rules("settle nonsense\n\"proceed?\" \\r")
        check("a bad settle is a complaint, not a crash", a.problems.count == 1)
        check("and leaves the default in place", abs(a.settle - 0.3) < 1e-9, "\(a.settle)")
        check("the rule after it still parses", a.rules.count == 1)
    }

    do {
        func d(_ s: String, _ lo: Double = 0, _ hi: Double = 3600) -> TimeInterval? {
            TerminalAutoAnswer.parseDuration(s, min: lo, max: hi)
        }
        check("settle has a floor", d("0", 0.05, 10)! >= 0.05)
        check("and a ceiling", d("600s", 0.05, 10)! <= 10)
        // A wait may be zero — that is how you ask for the old behaviour —
        // and may be much longer than a settle ever is.
        check("a wait may be zero", d("0")! == 0)
        check("and may be minutes", d("120s")! == 120)
        check("seconds parse too", d("0.5s")! == 0.5)
        check("a bare number is milliseconds", d("400")! == 0.4)
        check("a word is not a duration", d("soon") == nil)
        check("nor is a negative one", d("-5s") == nil)
    }

    print("\nescapes")

    do {
        check("\\r", TerminalAutoAnswer.decode("\\r") == "\r")
        check("\\e", TerminalAutoAnswer.decode("\\e") == "\u{1B}")
        check("\\t", TerminalAutoAnswer.decode("a\\tb") == "a\tb")
        check("\\\\ is one backslash", TerminalAutoAnswer.decode("\\\\r") == "\\r")
        check("\\x41 is A", TerminalAutoAnswer.decode("\\x41") == "A")
        check("\\C-c is Ctrl+C", TerminalAutoAnswer.decode("\\C-c") == "\u{03}")
        check("\\C-C is the same", TerminalAutoAnswer.decode("\\C-C") == "\u{03}")
        check("\\s is a space that survives trimming",
              TerminalAutoAnswer.decode("y\\s") == "y ")
        // A typo must not become a keystroke.
        check("an undefined escape is the character itself",
              TerminalAutoAnswer.decode("\\q") == "q")
        check("text with no backslash is untouched",
              TerminalAutoAnswer.decode("yes") == "yes")
    }

    // MARK: - Matching

    print("\nmatching")

    do {
        let a = rules("\"Do you want to proceed?\"   \\r")
        // The shape a real prompt arrives in: inside a box, padded to the pane.
        check("a boxed, padded prompt matches",
              a.match(screen("╭──────────────────────────────╮",
                             "│  Do you want to  proceed?    │",
                             "╰──────────────────────────────╯")) != nil)
        a.reset()
        check("case does not matter",
              a.match(screen("do you WANT to proceed?")) != nil)
        a.reset()
        check("an unrelated screen does not match",
              a.match(screen("$ ls", "Makefile  README.md")) == nil)
    }

    do {
        // A pattern matches a LINE. Two unrelated rows must not join into a
        // question that is nowhere on screen — and a match with no single row
        // to call its own has no position, which is the whole of a prompt's
        // identity here.
        let a = rules("\"proceed now\"   \\r")
        check("a literal cannot match across a line break",
              a.match(screen("...proceed", "now...")) == nil)
    }

    do {
        let a = rules("/^\\s*Continue\\? \\[Y\\/n\\]/   y\\r")
        check("a regex matches the screen as it stands",
              a.match(screen("Continue? [Y/n]")) != nil)
        a.reset()
        check("and is case-sensitive unless asked",
              a.match(screen("continue? [y/n]")) == nil)
        let b = rules("/continue\\? \\[Y\\/n\\]/i   y\\r")
        check("the i flag makes it not", b.match(screen("Continue? [Y/n]")) != nil)
    }

    do {
        let a = rules("""
            "proceed? [y/N]"    n\\r
            "proceed?"          y\\r
            """)
        let hit = a.match(screen("proceed? [y/N]"))
        check("the first matching rule in file order wins", hit?.reply == "n\r",
              "\(hit?.reply ?? "nil")")
    }

    // MARK: - Which prompt is which

    print("\nanswering each question once")

    do {
        let a = rules("\"Do you want to proceed?\"   \\r")
        let prompt = screen("Do you want to proceed?", "> 1. Yes   2. No")

        check("it fires", a.match(prompt) != nil)
        check("and not again for the same line", a.match(prompt) == nil)
        // A spinner: the frame changes, the question does not move. This is
        // the case that turns a bad rule into a machine holding down a key.
        check("nor when the frame changes but the question does not",
              a.match(screen("Do you want to proceed?", "> 1. Yes   2. No",
                             "⠹ thinking")) == nil)
        check("nor after that", a.match(prompt) == nil)
    }

    do {
        // LINE MODE, which is where the naive rule breaks: the shell echoes
        // the answer and the question stays on screen for ever. A second
        // question further down must still be answered.
        let a = rules("\"proceed?\"   y\\r")
        check("the first question is answered",
              a.match(screen("$ rm a", "proceed?")) != nil)
        // The echo lands on the same line. Same line, same question.
        check("the echo of our own answer is not a new question",
              a.match(screen("$ rm a", "proceed? y", "removed a")) == nil)
        check("and neither is it once more output has arrived",
              a.match(screen("$ rm a", "proceed? y", "removed a", "$ rm b")) == nil)
        // A different line: a different question, even though the old one is
        // still right there on screen.
        check("a second question lower down is answered",
              a.match(screen("$ rm a", "proceed? y", "removed a",
                             "$ rm b", "proceed?")) != nil)
    }

    do {
        // The same rows, scrolled. A prompt keeps its identity when the screen
        // moves under it — otherwise every scroll would re-ask everything.
        let a = rules("\"proceed?\"   y\\r")
        check("a question is answered", a.match(screen("junk", "proceed?"), from: 100) != nil)
        check("and scrolling up one row does not make it a new one",
              a.match(screen("proceed?", "waiting"), from: 101) == nil)
        check("but the same text on a genuinely new line is a new question",
              a.match(screen("proceed?", "waiting", "proceed?"), from: 101) != nil)
    }

    do {
        // A FULL-SCREEN program draws its second prompt in the same box as the
        // first: same line, same text. It is only answerable again because the
        // memory is dropped when a settled screen holds no question at all.
        let a = rules("\"proceed?\"   y\\r")
        let box = screen("┌────────────┐", "│ proceed?   │", "└────────────┘")
        check("the box is answered", a.match(box) != nil)
        check("and not twice", a.match(box) == nil)
        check("the box comes down", a.match(screen("running…")) == nil)
        check("and an identical box is a new question", a.match(box) != nil)
    }

    do {
        // Two rules, one stale question and one live one. The stale one must
        // not hide the live one — the loop has to keep looking past a rule it
        // has already dealt with.
        let a = rules("""
            "proceed?"     \\r
            "overwrite?"   y\\r
            """)
        check("the first fires", a.match(screen("proceed?"))?.reply == "\r")
        check("the second fires with the first still on screen",
              a.match(screen("proceed?", "overwrite?"))?.reply == "y\r")
        check("and then neither does", a.match(screen("proceed?", "overwrite?")) == nil)
    }

    do {
        let a = TerminalAutoAnswer(text: "wait 0\n\"proceed?\" \\r\n\"overwrite?\" y\\r")
        check("the floor is on by default",
              a.minimumInterval == TerminalAutoAnswer.defaultMinimumInterval)
        check("one answer goes through", a.match(screen("proceed?")) != nil)
        // Back to back, a different rule, inside the floor: held. Two rules
        // that paint each other's screen cannot run away.
        check("a second inside the floor does not",
              a.match(screen("proceed?", "overwrite?")) == nil)
        // And it must say it is holding, rather than reporting an empty
        // screen. The caller only comes back when more output arrives, and a
        // program waiting for an answer sends none.
        check("the floor reports as a wait, not as an empty screen",
              a.waiting(screen("proceed?", "overwrite?")) != nil)
        check("an empty screen does not", a.waiting(screen("nothing here")) == nil)
        Thread.sleep(forTimeInterval: TerminalAutoAnswer.defaultMinimumInterval + 0.05)
        check("once the floor has passed it does",
              a.match(screen("proceed?", "overwrite?")) != nil)
    }

    do {
        let a = rules("\"proceed?\"   y\\r")
        check("a question is answered", a.match(screen("proceed?")) != nil)
        a.reset()
        check("reset forgets it", a.match(screen("proceed?")) != nil)
    }

    // MARK: - The head start

    print("\nleaving it for a human first")

    do {
        let a = TerminalAutoAnswer(text: "\"proceed?\"   y\\r")
        check("ten seconds by default, not zero",
              a.rules[0].wait == TerminalAutoAnswer.defaultWait,
              "\(a.rules[0].wait)")
        // The whole safety story rests on this: a matched prompt does NOT get
        // answered on the spot.
        check("a matched question is not answered straight away",
              a.match(screen("proceed?")) == nil)
        let left = a.waiting(screen("proceed?"))
        check("it reports a wait instead", left != nil, "\(String(describing: left))")
        check("and the wait is about ten seconds",
              (left ?? 0) > 9 && (left ?? 0) <= 10, "\(left ?? -1)")
    }

    do {
        let a = TerminalAutoAnswer(text: "wait 200ms\n\"proceed?\"   y\\r")
        a.minimumInterval = 0
        check("short wait: held at first", a.waiting(screen("proceed?")) != nil)
        Thread.sleep(forTimeInterval: 0.25)
        check("and answered once it passes",
              a.match(screen("proceed?"))?.reply == "y\r")
    }

    do {
        // Someone types. The question is theirs — nothing is written, and it
        // is not offered again even though it is still on screen.
        let a = TerminalAutoAnswer(text: "wait 200ms\n\"proceed?\"   y\\r")
        a.minimumInterval = 0
        check("the wait starts", a.waiting(screen("proceed?")) != nil)
        a.noteUserActivity()
        check("a keystroke cancels it",
              a.cancelled(screen("proceed?")) == .takenOver)
        Thread.sleep(forTimeInterval: 0.25)
        check("and it does not come back after the deadline",
              a.match(screen("proceed?")) == nil)
        check("nor does it keep reporting a wait",
              a.waiting(screen("proceed?")) == nil)
    }

    do {
        // A keystroke BEFORE the question appeared is not an answer to it.
        let a = TerminalAutoAnswer(text: "wait 150ms\n\"proceed?\"   y\\r")
        a.minimumInterval = 0
        a.noteUserActivity()
        Thread.sleep(forTimeInterval: 0.02)
        check("typing before the question does not cancel it",
              a.waiting(screen("proceed?")) != nil)
        Thread.sleep(forTimeInterval: 0.2)
        check("and it is answered", a.match(screen("proceed?")) != nil)
    }

    do {
        // The human answered it themselves, or the program moved on. Either
        // way the keys must not be typed into whatever came next.
        let a = TerminalAutoAnswer(text: "wait 5s\n\"proceed?\"   y\\r")
        a.minimumInterval = 0
        check("the wait starts", a.waiting(screen("proceed?")) != nil)
        check("the question leaving cancels it",
              a.cancelled(screen("all done")) == .gone)
        check("and nothing is left waiting", a.waiting(screen("all done")) == nil)
    }

    do {
        // A prompt that redraws while the countdown runs — a spinner beside
        // it, the box moving down a line — must keep its countdown rather
        // than starting a new one each frame.
        let a = TerminalAutoAnswer(text: "wait 400ms\n\"proceed?\"   y\\r")
        a.minimumInterval = 0
        let first = a.waiting(screen("proceed?", "⠋ working"))
        Thread.sleep(forTimeInterval: 0.15)
        let second = a.waiting(screen("proceed?", "⠙ working"))
        check("a redraw does not restart the countdown",
              (second ?? 99) < (first ?? 0), "\(first ?? -1) then \(second ?? -1)")
        Thread.sleep(forTimeInterval: 0.3)
        check("and it still answers on time", a.match(screen("proceed?", "⠹ working")) != nil)
    }

    do {
        let a = rules("\"proceed?\"   y\\r")
        check("wait 0 answers as soon as it matches",
              a.match(screen("proceed?")) != nil)
    }

    do {
        // Positional: each rule takes the wait declared above it, so one file
        // can be quick about a harmless prompt and slow about a dangerous one.
        let a = TerminalAutoAnswer(text: """
            wait 2s
            "proceed?"     \\r
            wait 30s
            "delete it?"   \\r
            """)
        check("a rule takes the wait above it", a.rules[0].wait == 2, "\(a.rules[0].wait)")
        check("and the next one takes the next", a.rules[1].wait == 30, "\(a.rules[1].wait)")
    }

    do {
        // `settle`/`wait` are directives only as a bare first word. Tested as
        // a prefix, the rule below reads as a broken `wait`.
        let a = rules("waiting for you?   y\\r")
        check("a pattern that starts with a directive name still parses",
              a.rules.count == 1, "\(a.problems)")
        check("and matches", a.match(screen("waiting for you?")) != nil)
        let b = TerminalAutoAnswer(text: "wait nonsense\n\"proceed?\" \\r")
        check("a bad wait is a complaint, not a crash", b.problems.count == 1,
              "\(b.problems)")
        check("and leaves the default in place",
              b.rules[0].wait == TerminalAutoAnswer.defaultWait)
    }

    // MARK: - The file

    print("\nthe file")

    let dir = NSTemporaryDirectory() + "/starling-autoanswer-\(getpid())"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let path = dir + "/autoanswer"
    func finish(_ code: Int32) -> Never {
        try? FileManager.default.removeItem(atPath: dir)
        exit(code)
    }

    do {
        let missing = TerminalAutoAnswer(file: dir + "/does-not-exist")
        check("a missing file is not an error, just no rules", !missing.isArmed)
        check("and it answers nothing", missing.match(screen("proceed?")) == nil)
    }

    do {
        try? "wait 0\n\"proceed?\"   y\\r".write(toFile: path, atomically: true, encoding: .utf8)
        let a = TerminalAutoAnswer(file: path)
        a.minimumInterval = 0
        check("a file with a rule arms", a.isArmed)
        check("and the rule works", a.match(screen("proceed?"))?.reply == "y\r")

        // Editing the file mid-session is the iteration loop; a stamp that only
        // watched the modification time would miss an edit inside the same second.
        try? "wait 0\n\"proceed?\"   n\\r".write(toFile: path, atomically: true, encoding: .utf8)
        let after = a.match(screen("proceed?"))
        check("an edit is picked up without a restart", after?.reply == "n\r",
              "\(after?.reply ?? "nil")")

        try? "".write(toFile: path, atomically: true, encoding: .utf8)
        check("emptying the file disarms it", a.match(screen("proceed?")) == nil)
    }

    print("")
    if failures.isEmpty {
        print("all autoanswer checks passed")
        finish(0)
    } else {
        print("FAILED: \(failures.joined(separator: ", "))")
        finish(1)
    }

  }
}
