// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// Shapes on a grid — milestone 4 of docs/plans/ipad-ui.md.
//
// This finds regions in a terminal grid that a touch UI could put an affordance
// over: a list of numbered options waiting for a choice, a diff hunk, a
// file:line reference. It draws nothing and decides nothing. Everything here is
// a pure function of the cells, so the corpus test can replay a recorded
// session through the real emulator and assert what each frame should match.
//
// **It recognises shapes, not concepts.** Nothing below knows what Claude Code
// is, and that is the point twice over: it keeps us from quietly becoming an
// agent client (the plan's decision 7), and the same option-list detector fires
// on any program that draws one — which is most of them.
//
// Why structure and not the words on screen: the plan ranks the signals by how
// long they survive. OSC markers would be best, and a capture of a real session
// says there are none — the only OSC in a whole run sets the window title. So
// structure is the top of what is actually available: column alignment, glyph
// classes, colour runs. Anchor text ("Do you want to…") is the most precise
// signal and the most brittle, breaks under localisation, and is deliberately
// unused here. If it is ever needed it should CONFIRM a structural match rather
// than stand alone.
//
// The load-bearing rule is in `optionLists`: a run of numbered lines is not a
// prompt unless exactly one of them is marked as selected. Plain prose numbers
// its steps all the time; nothing numbers its steps AND points at one of them.
// That single requirement is what separates "a list" from "a question", and it
// is why the false-positive bar in the plan is reachable at all.

import Foundation

/// One recognised shape, and where it sits in the grid.
public struct GridRegion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A choice waiting to be made. `selected` indexes `options`.
        case optionList(selected: Int, options: [GridOption])
        /// Added and removed lines, sharing a column and distinguished by
        /// colour.
        case diffHunk
        /// A `path:line` that could open something.
        case pathReference(path: String, line: Int?)
    }

    public let kind: Kind
    /// Inclusive, in grid rows.
    public let firstRow: Int
    public let lastRow: Int

    public init(kind: Kind, firstRow: Int, lastRow: Int) {
        self.kind = kind
        self.firstRow = firstRow
        self.lastRow = lastRow
    }
}

/// One line of an option list.
///
/// `key` is what a keypress would have to send to choose it — the digit the
/// line is numbered with. Milestone 5 sends exactly this and nothing inferred:
/// the overlay must never decide what an option *means*, only which key the
/// person pointed at.
public struct GridOption: Equatable, Sendable {
    public let number: Int
    public let label: String
    public let row: Int
    public let key: Character

    public init(number: Int, label: String, row: Int, key: Character) {
        self.number = number
        self.label = label
        self.row = row
        self.key = key
    }
}

public enum GridRegions {

    /// Every shape found in `grid`, in row order.
    public static func detect(_ grid: [[TermCell]]) -> [GridRegion] {
        let lines = grid.map(Line.init)
        var found = optionLists(lines)
        found.append(contentsOf: diffHunks(lines))
        found.append(contentsOf: pathReferences(lines))
        return found.sorted { ($0.firstRow, $0.lastRow) < ($1.firstRow, $1.lastRow) }
    }

    // MARK: - One row, pre-chewed

    /// A row reduced to what detection asks about. Built once per row because
    /// every detector below wants the same three things and computing them per
    /// probe turned the scan quadratic on a tall grid.
    private struct Line {
        let chars: [Character]
        let fg: [UInt32]
        /// Column of the first non-blank cell, or nil for an empty row.
        let indent: Int?

        init(_ row: [TermCell]) {
            chars = row.map(\.char)
            fg = row.map(\.fg)
            indent = chars.firstIndex { !$0.isWhitespace }
        }

        var isBlank: Bool { indent == nil }

        func text(from: Int = 0) -> String {
            guard from < chars.count else { return "" }
            return String(chars[from...]).replacingOccurrences(
                of: " +$", with: "", options: .regularExpression)
        }
    }

    // MARK: - Option lists

    /// A numbered option row: where the marker, number and label sit, and the
    /// two values. Nil for any row that is not one.
    private struct OptionRow {
        /// Non-nil when a selection glyph sits left of the number.
        let markerCol: Int?
        let numberCol: Int
        let labelCol: Int
        let number: Int
        let label: String
    }

    private static func optionRow(_ line: Line) -> OptionRow? {
        guard let start = line.indent else { return nil }
        var i = start
        var markerCol: Int? = nil

        // The selected row leads with its marker, so the first non-blank cell
        // is not the digit there. Skip one short symbol token — and require it
        // to BE a symbol: a marker is punctuation (❯, ▸, >, *), never a word.
        // That distinction is what stops "Steps to reproduce: 1. …" from
        // reading its first word as a selection.
        if !line.chars[i].isNumber {
            let markerStart = i
            while i < line.chars.count, !line.chars[i].isWhitespace { i += 1 }
            let marker = line.chars[markerStart..<i]
            guard marker.count <= 2,
                  marker.allSatisfy({ !$0.isLetter && !$0.isNumber })
            else { return nil }
            while i < line.chars.count, line.chars[i] == " " { i += 1 }
            guard i < line.chars.count, line.chars[i].isNumber else { return nil }
            markerCol = markerStart
        }

        var digits = ""
        while i < line.chars.count, line.chars[i].isNumber {
            digits.append(line.chars[i])
            i += 1
        }
        // A bare number is not an option; the dot is what makes it a list.
        let numberCol = i - digits.count
        guard !digits.isEmpty, digits.count <= 3,
              i < line.chars.count, line.chars[i] == "." else { return nil }
        i += 1
        let afterDot = i
        while i < line.chars.count, line.chars[i] == " " { i += 1 }
        // "1." with nothing after it, or with the label jammed against the
        // dot, is prose rather than a menu row.
        guard i > afterDot, i < line.chars.count else { return nil }
        let label = line.text(from: i)
        guard !label.isEmpty, let number = Int(digits) else { return nil }
        return OptionRow(markerCol: markerCol, numberCol: numberCol,
                         labelCol: i, number: number, label: label)
    }

    /// Runs of numbered rows where exactly one row is pointed at.
    private static func optionLists(_ lines: [Line]) -> [GridRegion] {
        var out: [GridRegion] = []
        var row = 0

        while row < lines.count {
            guard let firstOpt = optionRow(lines[row]) else { row += 1; continue }

            // An option too long for the pane wraps, and the wrapped remainder
            // is indented to the label column rather than renumbered. Absorbing
            // it is not cosmetic: a run that stops at the first non-option line
            // ends early and drops every option after the wrap. Claude Code's
            // edit prompt wraps its second option and has three — stopping
            // there yields a sheet with "Yes" and no way to say no, which is
            // the exact failure the overlay's safety rule exists to prevent.
            var rows: [(Int, OptionRow)] = [(row, firstOpt)]
            var extra: [Int: [String]] = [:]
            var end = row
            var i = row + 1
            while i < lines.count {
                if let opt = optionRow(lines[i]) {
                    rows.append((i, opt))
                    end = i
                    i += 1
                } else if let indent = lines[i].indent, indent >= firstOpt.labelCol {
                    extra[rows.count - 1, default: []].append(lines[i].text(from: indent))
                    end = i
                    i += 1
                } else {
                    break
                }
            }
            defer { row = end + 1 }
            // A single numbered line is a sentence that happens to start with
            // a number. Two is the smallest thing that can be a choice.
            guard rows.count >= 2 else { continue }
            // A menu is laid out; prose is not. Every row's number and every
            // row's label must share a column.
            guard let first = rows.first?.1,
                  rows.allSatisfy({ $0.1.numberCol == first.numberCol
                                    && $0.1.labelCol == first.labelCol })
            else { continue }
            // 1, 2, 3 … — a list that skips or repeats is a coincidence.
            guard rows.enumerated().allSatisfy({ $0.element.1.number == $0.offset + 1 })
            else { continue }

            // The gate. Something must sit to the LEFT of the numbers on
            // exactly one row — the cursor glyph the program draws to say
            // "this one". Zero marks means it is a list nobody is choosing
            // from; two or more means the glyph is decoration on every row
            // (a bullet, a box edge) and carries no selection.
            let selectedRows = rows.filter { $0.1.markerCol != nil }.map(\.0)
            guard selectedRows.count == 1, let selectedRow = selectedRows.first
            else { continue }

            // The key is the digit as drawn. For a two-digit option the last
            // digit is what the program's own keypress handler reads, and
            // guessing anything cleverer is exactly the inference the overlay
            // is forbidden from making.
            let options = rows.enumerated().map { idx, entry -> GridOption in
                let (r, opt) = entry
                let label = ([opt.label] + (extra[idx] ?? [])).joined(separator: " ")
                return GridOption(number: opt.number, label: label, row: r,
                                  key: String(opt.number).last!)
            }
            let selected = rows.firstIndex { $0.0 == selectedRow } ?? 0
            out.append(GridRegion(
                kind: .optionList(selected: selected, options: options),
                firstRow: row, lastRow: end))
        }
        return out
    }

    // MARK: - Diff hunks

    /// Runs of `+`/`-` rows sharing a column, with the two signs coloured
    /// differently.
    ///
    /// The colour check is what keeps a quoted diff in prose, or a bulleted
    /// list using hyphens, from matching: a real diff paints its additions and
    /// removals apart, and something merely starting lines with `-` does not.
    private static func diffHunks(_ lines: [Line]) -> [GridRegion] {
        var out: [GridRegion] = []
        var row = 0

        func sign(_ line: Line) -> (col: Int, ch: Character, fg: UInt32)? {
            guard let i = line.indent, i < line.chars.count else { return nil }
            let c = line.chars[i]
            guard c == "+" || c == "-" else { return nil }
            return (i, c, line.fg[i])
        }

        while row < lines.count {
            guard sign(lines[row]) != nil else { row += 1; continue }
            var end = row
            while end + 1 < lines.count, sign(lines[end + 1]) != nil { end += 1 }
            defer { row = end + 1 }

            let signs = (row...end).compactMap { sign(lines[$0]) }
            guard signs.count >= 2,
                  let col = signs.first?.col,
                  signs.allSatisfy({ $0.col == col }) else { continue }
            let plus = Set(signs.filter { $0.ch == "+" }.map(\.fg))
            let minus = Set(signs.filter { $0.ch == "-" }.map(\.fg))
            guard !plus.isEmpty, !minus.isEmpty, plus.isDisjoint(with: minus)
            else { continue }

            out.append(GridRegion(kind: .diffHunk, firstRow: row, lastRow: end))
        }
        return out
    }

    // MARK: - Path references

    /// `something/with/slashes.swift:42`, or the same without the line.
    ///
    /// Requires a separator (`/` or `.`) so a bare word before a colon — every
    /// prose colon, every `key: value` — cannot match.
    private static func pathReferences(_ lines: [Line]) -> [GridRegion] {
        var out: [GridRegion] = []
        for (r, line) in lines.enumerated() where !line.isBlank {
            for token in line.text().split(whereSeparator: { $0 == " " }) {
                let parts = token.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 2 || parts.count == 1 else { continue }
                let path = String(parts[0])
                guard path.contains("/") || path.contains(".") else { continue }
                guard path.count >= 3,
                      path.allSatisfy({ !$0.isWhitespace && $0 != "\"" && $0 != "'" })
                else { continue }
                // A bare path with no colon is not interesting enough to
                // overlay — too much prose contains one.
                guard parts.count == 2, let lineNo = Int(parts[1]) else { continue }
                out.append(GridRegion(
                    kind: .pathReference(path: path, line: lineNo),
                    firstRow: r, lastRow: r))
            }
        }
        return out
    }
}
