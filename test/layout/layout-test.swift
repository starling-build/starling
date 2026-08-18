// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The layout blob's codec, tested standalone — the same shape as
// test/core/conformance.c, and for the same reason: the format is stored by a
// daemon that will never validate it, so nothing else can catch a drift.
//
//   swiftc -O layout-test.swift ../../apps/TerminalApp/Sources/TerminalApp/PaneLayout.swift
//
// test/run.sh does exactly that.

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
struct LayoutTest {
  static func main() {
    // A tree with both axes, uneven ratios, nesting on both sides, and remote
    // session ids — everything the format has to carry at once.
    let tree: LayoutNode = .split(
        axis: .row, ratio: 0.35,
        first: .leaf(session: 12),
        second: .split(
            axis: .column, ratio: 0.7,
            first: .leaf(session: 13),
            second: .split(axis: .row, ratio: 0.5,
                           first: .leaf(session: 14),
                           second: .leaf(session: 0))))

    let layout = PaneLayout(root: tree, activeLeaf: 2)
    let blob = layout.encoded()

    // --- the round trip, which is the whole job -------------------------------
    check("a layout survives encode → decode", PaneLayout.decode(blob) == layout,
          String(describing: PaneLayout.decode(blob)))

    check("leaves keep tree order and their session ids",
          layout.leaves == [12, 13, 14, 0], "\(layout.leaves)")

    check("the focused pane survives", PaneLayout.decode(blob)?.activeLeaf == 2)

    // Ratios are ten-thousandths, so this is exact rather than approximate.
    if case .split(_, let r, _, _) = PaneLayout.decode(blob)!.root {
        check("a ratio round-trips exactly", r == 0.35, "\(r)")
    } else {
        check("a ratio round-trips exactly", false, "root was not a split")
    }

    // --- a single pane, the common case ---------------------------------------
    let single = PaneLayout(root: .leaf(session: 0))
    check("a single pane round-trips",
          PaneLayout.decode(single.encoded()) == single)

    // --- degrade, never fail (plan decision 5) --------------------------------
    var future = blob
    future[2] = 99
    check("a version from the future decodes to nil, not garbage",
          PaneLayout.decode(future) == nil)

    check("a foreign blob decodes to nil",
          PaneLayout.decode(Array("not a layout at all".utf8)) == nil)

    check("an empty blob decodes to nil", PaneLayout.decode([]) == nil)

    // Truncation at every length must be refused rather than half-read: the
    // daemon hands back whatever it was given, including a short write.
    var truncationsRefused = true
    for n in 0..<blob.count {
        if PaneLayout.decode(Array(blob.prefix(n))) != nil { truncationsRefused = false }
    }
    check("every truncation is refused", truncationsRefused)

    check("trailing bytes are refused", PaneLayout.decode(blob + [0x00]) == nil)

    // A ratio outside 0…1 cannot be encoded, so it cannot be decoded either.
    var badRatio = PaneLayout(root: .split(axis: .row, ratio: 9.0,
                                           first: .leaf(session: 1),
                                           second: .leaf(session: 2))).encoded()
    if case .split(_, let r, _, _)? = PaneLayout.decode(badRatio)?.root {
        check("an out-of-range ratio is clamped, not wrapped", r == 1.0, "\(r)")
    } else {
        check("an out-of-range ratio is clamped, not wrapped", false)
    }
    badRatio[4 + 3] = 0xff; badRatio[4 + 4] = 0xff   // scaled = 65535 > 10000
    check("a ratio byte pair above the scale is refused",
          PaneLayout.decode(badRatio) == nil)

    // --- deep nesting, because recursion is where a codec breaks --------------
    var deep: LayoutNode = .leaf(session: 1)
    for i in 0..<64 {
        deep = .split(axis: i % 2 == 0 ? .row : .column, ratio: 0.5,
                      first: deep, second: .leaf(session: UInt32(i + 2)))
    }
    let deepLayout = PaneLayout(root: deep, activeLeaf: 40)
    check("a 64-deep tree round-trips",
          PaneLayout.decode(deepLayout.encoded()) == deepLayout)

    print("")
    if failures.isEmpty {
        print("all layout checks passed")
        exit(0)
    } else {
        print("FAILED: \(failures.joined(separator: ", "))")
        exit(1)
    }
  }
}
