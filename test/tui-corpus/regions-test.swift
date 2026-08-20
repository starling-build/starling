// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The region detector against recorded sessions — milestone 4 of
// docs/plans/ipad-ui.md.
//
//   cc -c sdk/Sources/CTerminalCore/starling_term.c -o st.o \
//       -I sdk/Sources/CTerminalCore/include
//   cc -c sdk/Sources/CTerminalCore/st_ring.c -o ring.o \
//       -I sdk/Sources/CTerminalCore/include
//   swiftc -O -I sdk/Sources/CTerminalCore/include -o regions-test \
//       test/tui-corpus/regions-test.swift \
//       sdk/Sources/Flutter/Terminal/TerminalEmulator.swift \
//       sdk/Sources/Flutter/Terminal/GridRegions.swift st.o ring.o
//
// test/run.sh does exactly that.
//
// The recordings in corpus/ are raw pty bytes — escape sequences and all —
// captured with record-tui.py from real programs at a stated size. They are
// replayed through the REAL emulator rather than a parser written for the
// test, because a second parser is a second thing to drift; if the emulator
// changes how it lays a frame out, this suite is supposed to notice.
//
// What is actually under test is the promise the whole enhancement layer rests
// on: that a shape can be recognised confidently enough to put a button on it.
// The negatives matter more than the positives here. An overlay that misses a
// prompt costs a tap; an overlay that appears over ordinary text and sends a
// keystroke costs trust. So `.expect(none:)` cases outnumber the rest, and the
// bar the plan sets is one-directional — NO false positives on an option list,
// at any recall.

import Foundation

var failures: [String] = []
var checks = 0

func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !ok {
        let d = detail()
        failures.append("FAIL \(name)" + (d.isEmpty ? "" : " — \(d)"))
    }
}

/// Replay a recording and hand back the grid it leaves on screen.
func replay(_ path: String, cols: Int, rows: Int) -> [[TermCell]]? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    let term = TerminalEmulator(cols: cols, rows: rows)
    term.feed([UInt8](data))
    return term.grid
}

func optionLists(_ regions: [GridRegion]) -> [(Int, [GridOption])] {
    regions.compactMap {
        if case .optionList(let selected, let options) = $0.kind {
            return (selected, options)
        }
        return nil
    }
}

func diffHunks(_ regions: [GridRegion]) -> [GridRegion] {
    regions.filter { if case .diffHunk = $0.kind { return true }; return false }
}

func paths(_ regions: [GridRegion]) -> [(String, Int?)] {
    regions.compactMap {
        if case .pathReference(let p, let l) = $0.kind { return (p, l) }
        return nil
    }
}

// MARK: - Corpus

let corpusDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "test/tui-corpus/corpus"

struct Case {
    let file: String
    let cols: Int
    let rows: Int
    /// nil = "this recording must yield no option list at all".
    let expectOptions: Int?
    let note: String
}

let cases: [Case] = [
    // ── positives ────────────────────────────────────────────────────────
    // Claude Code's folder-trust prompt. Two numbered options, one pointed
    // at with ❯. Recorded at two widths because the layout is column
    // addressed and a narrow pane is the case most likely to break it.
    Case(file: "trust-100.bin", cols: 100, rows: 30, expectOptions: 2,
         note: "trust prompt, 100 cols"),
    Case(file: "trust-60.bin", cols: 60, rows: 40, expectOptions: 2,
         note: "trust prompt, 60 cols"),
    // The real tool-permission prompt — the one milestone 5 puts buttons on.
    // Three options, and the second WRAPS onto a continuation line indented
    // to the label column. A scanner that stops at the first non-option row
    // reports two options and silently loses "No", which is a sheet with no
    // way to decline. This case exists because that is exactly what the first
    // implementation did.
    Case(file: "perm-edit-100.bin", cols: 100, rows: 30, expectOptions: 3,
         note: "edit permission prompt, wrapped option"),
    // The Bash prompt: same option family, different content above it (a
    // command line, not a diff) and no wrapped option. Kept because the two
    // are laid out by different code paths in the program being watched, and
    // this suite's job is to notice when either moves.
    Case(file: "perm-bash-100.bin", cols: 100, rows: 30, expectOptions: 3,
         note: "bash permission prompt"),

    // ── negatives ────────────────────────────────────────────────────────
    // The hard one: prose that numbers its steps, at consistent columns, in
    // sequence. Everything an option list has EXCEPT a selection marker.
    // If this ever matches, the false-positive bar is gone.
    Case(file: "neg-numbered.bin", cols: 100, rows: 30, expectOptions: nil,
         note: "numbered prose steps"),
    Case(file: "neg-ls.bin", cols: 100, rows: 30, expectOptions: nil,
         note: "ls -la"),
    Case(file: "neg-git.bin", cols: 100, rows: 30, expectOptions: nil,
         note: "git log --oneline"),
]

@main
struct RegionsTest {
    static func main() {
        for c in cases {
            let path = "\(corpusDir)/\(c.file)"
            guard let grid = replay(path, cols: c.cols, rows: c.rows) else {
                check(c.note, false, "could not read \(path)")
                continue
            }
            let regions = GridRegions.detect(grid)
            let lists = optionLists(regions)

            if let want = c.expectOptions {
                check("\(c.note): one option list", lists.count == 1,
                      "got \(lists.count)")
                if let (selected, options) = lists.first {
                    check("\(c.note): \(want) options", options.count == want,
                          "got \(options.count): \(options.map(\.label))")
                    check("\(c.note): a selection inside the list",
                          selected >= 0 && selected < options.count, "selected=\(selected)")
                    check("\(c.note): options numbered from 1",
                          options.map(\.number) == Array(1...options.count),
                          "\(options.map(\.number))")
                    // The key must be the digit as drawn. Milestone 5 sends this
                    // byte and nothing derived from the label.
                    check("\(c.note): key is the drawn digit",
                          options.allSatisfy { $0.key == String($0.number).last! },
                          "\(options.map(\.key))")
                    check("\(c.note): labels non-empty",
                          options.allSatisfy { !$0.label.isEmpty })
                }
            } else {
                check("\(c.note): NO option list", lists.isEmpty,
                      "matched \(lists.count): \(lists.map { $0.1.map(\.label) })")
            }

            // The decision layer, on the same frames. A recording that yields
            // no option list must yield nothing actionable either — that is
            // the property the overlay's safety rests on, so assert it here
            // rather than trusting that one follows from the other.
            let choice = PromptDetector.actionable(grid)
            if c.expectOptions == nil {
                check("\(c.note): nothing actionable", choice == nil,
                      "offered \(choice?.options.map(\.label) ?? [])")
            } else {
                check("\(c.note): actionable", choice != nil)
                if let ch = choice {
                    // The keystroke is the drawn digit, never an index and
                    // never anything read out of the label.
                    for (i, o) in ch.options.enumerated() {
                        check("\(c.note): option \(i) sends its own digit",
                              ch.keystroke(for: o) == String(o.number).last.map(String.init),
                              "sent \(ch.keystroke(for: o)) for #\(o.number)")
                    }
                }
            }
        }

        // MARK: - Synthetic edges
        //
        // Recordings cover what the programs actually drew; these cover what they
        // could draw next. Written as escape sequences rather than captured because
        // the point is to pin the RULE, not a program's current output.

        func gridFrom(_ ansi: String, cols: Int = 60, rows: Int = 12) -> [[TermCell]] {
            let term = TerminalEmulator(cols: cols, rows: rows)
            term.feed([UInt8](ansi.utf8))
            return term.grid
        }

        // A marker on every row is decoration, not a selection.
        check("every row marked is not a selection",
              optionLists(GridRegions.detect(gridFrom(
                "  \u{1B}[2G• 1. one\r\n• 2. two\r\n• 3. three\r\n"))).isEmpty)

        // No marker anywhere: a list nobody is choosing from.
        check("no marker is not a selection",
              optionLists(GridRegions.detect(gridFrom(
                "  1. one\r\n  2. two\r\n"))).isEmpty)

        // A single numbered line is a sentence.
        check("one numbered line is not a list",
              optionLists(GridRegions.detect(gridFrom("❯ 1. only one\r\n"))).isEmpty)

        // Numbers that skip are a coincidence, not a menu.
        check("non-sequential numbers rejected",
              optionLists(GridRegions.detect(gridFrom(
                "❯ 1. one\r\n  3. three\r\n"))).isEmpty)

        // Labels that do not share a column are prose that happens to be numbered.
        check("ragged label columns rejected",
              optionLists(GridRegions.detect(gridFrom(
                "❯ 1. one\r\n  2.    two\r\n"))).isEmpty)

        // And the shape that must still work.
        do {
            let lists = optionLists(GridRegions.detect(gridFrom(
                "❯ 1. Yes\r\n  2. No\r\n")))
            check("minimal well-formed list matches", lists.count == 1)
            check("minimal list selects row 0", lists.first?.0 == 0)
        }

        // Diff hunks need the two signs coloured apart; a hyphen list is not a diff.
        check("hyphen bullets are not a diff",
              diffHunks(GridRegions.detect(gridFrom(
                "- one\r\n- two\r\n- three\r\n"))).isEmpty)
        check("coloured +/- is a diff",
              diffHunks(GridRegions.detect(gridFrom(
                "\u{1B}[32m+ added\u{1B}[39m\r\n\u{1B}[31m- removed\u{1B}[39m\r\n"))).count == 1)

        // Path references need a separator, so prose colons cannot match.
        check("prose colon is not a path",
              paths(GridRegions.detect(gridFrom("note: this is fine\r\n"))).isEmpty)
        do {
            let found = paths(GridRegions.detect(gridFrom("see src/Term.swift:42 for it\r\n")))
            check("path:line matches", found.count == 1, "\(found)")
            check("path parsed", found.first?.0 == "src/Term.swift", "\(found)")
            check("line parsed", found.first?.1 == 42, "\(found)")
        }

        // MARK: - Report

        if failures.isEmpty {
            print("\(checks) checks — all region checks passed")
        } else {
            for f in failures { print(f) }
            print("\(failures.count)/\(checks) failed")
            exit(1)
        }
    }
}
