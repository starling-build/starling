// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The auto-answer, end to end, through a real PTY and the real emulator.
//
//   gcc -c starling_term.c st_ring.c
//   swiftc -O autoanswer-live.swift TerminalAutoAnswer.swift TerminalSession.swift \
//       TerminalEmulator.swift Pty.swift UserHome.swift <objects> \
//       -I <CTerminalCore/include> -Xcc -I<CTerminalCore/include>
//
// test/run.sh does exactly that. The unit test beside this one proves the
// matcher on screens handed to it; this proves the parts that only exist when
// a real child is on the other end — the debounce that waits for output to
// stop, the read of the live grid, and the write actually reaching the
// program's stdin. A bug in any of those looks identical from the matcher's
// side: every rule correct, nothing ever typed.
//
// The child asks three questions and prints what it received for each, so the
// checks are made against the CHILD's account of what it got, not against our
// screen. Two of them match a rule and must be answered; the third does not
// and must be left alone, which is the half that matters — a terminal that
// answers questions nobody wrote a rule for is worse than one that answers
// none at all.

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

@main
struct AutoAnswerLive {
  static func main() {
    let dir = (ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp")
        + "/starling-aalive-\(getpid())"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    func finish(_ code: Int32) -> Never {
        try? FileManager.default.removeItem(atPath: dir)
        exit(code)
    }

    // A short settle: this is a test, and the child answers instantly.
    let rulesPath = dir + "/autoanswer"
    try? """
        settle 120ms
        "do you want to proceed?"    yes\\r
        """.write(toFile: rulesPath, atomically: true, encoding: .utf8)

    // `read -t` is bash, so the script is run by bash rather than through
    // whatever $SHELL happens to be on the machine running the suite.
    let scriptPath = dir + "/ask.sh"
    try? """
        printf 'Do you want to proceed? '
        read a
        echo "ONE:[$a]"
        printf 'And again — do you want to proceed? '
        read b
        echo "TWO:[$b]"
        printf 'What is your name? '
        read -t 1 c || c=NOANSWER
        echo "THREE:[$c]"
        echo THEEND
        """.write(toFile: scriptPath, atomically: true, encoding: .utf8)

    let session = TerminalSession(cols: 80, rows: 24)
    let rules = TerminalAutoAnswer(file: rulesPath)
    check("the rules file armed the session", rules.isArmed, "\(rules.problems)")
    session.autoAnswer = rules

    // Every fire, in order, so a wrong rule firing is visible as itself rather
    // than as a wrong answer downstream.
    let lock = NSLock()
    var fired: [String] = []
    session.onAutoAnswer = { rule in
        lock.lock(); fired.append(rule.pattern); lock.unlock()
    }

    session.onExit = {
        // The exit message is fed to the grid before this runs, so the screen
        // is final by now. Hop to the main queue: that is where the settle
        // work runs, so this cannot land in the middle of one.
        DispatchQueue.main.async {
            session.lock.lock()
            let text = session.emulator.screenText
            session.lock.unlock()
            lock.lock(); let seen = fired; lock.unlock()

            check("the child ran to the end", text.contains("THEEND"), text)
            check("the first question was answered with the keys the rule names",
                  text.contains("ONE:[yes]"), text)
            check("so was the second, on its own line",
                  text.contains("TWO:[yes]"), text)
            check("a question no rule matches is left for a human",
                  text.contains("THREE:[NOANSWER]"), text)
            check("the rule fired exactly twice", seen.count == 2, "\(seen)")

            print("")
            if failures.isEmpty {
                print("all autoanswer live checks passed")
                finish(0)
            } else {
                print("FAILED: \(failures.joined(separator: ", "))")
                finish(1)
            }
        }
    }

    guard session.startCommand("bash \(scriptPath)") else {
        print("  FAIL  could not start the child")
        finish(1)
    }

    // Nothing here should take five seconds; the child's own longest wait is
    // one. A hang is a failure, not a reason to sit in CI for ever.
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
        session.lock.lock()
        let text = session.emulator.screenText
        session.lock.unlock()
        print("  FAIL  timed out waiting for the child\n\(text)")
        finish(1)
    }
    dispatchMain()
  }
}
