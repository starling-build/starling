// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The layout blob — milestone 3 of docs/plans/remote-workspace.md.
//
// termd stores this and never looks inside it (decision 1 of the plan), so
// the format is ours alone and adding a field to it is a client change. What
// it has to carry is the arrangement a workspace is reattached INTO: the tree,
// the ratios, which remote session each pane holds, and which pane had focus.
//
// Two things this file deliberately is NOT:
//
//   - It does not import Flutter, or anything else. That is what lets
//     test/layout/layout-test.swift compile it standalone with swiftc, the
//     same way test/core/conformance.c compiles the terminal core. A codec
//     with no test is a format that drifts.
//   - It does not know about PaneNode. The app converts to and from
//     `LayoutNode` at the boundary, so the tree the UI uses can grow fields
//     (titles, zoom, colours) without the wire format noticing.
//
// Versioned inside itself, per the plan's decision 5: an older client reading
// a blob from a newer one must degrade to "here are the sessions, arranged by
// default" rather than fail. `decode` therefore returns nil for anything it
// does not fully understand, and nil means "lay them out however you like".

import Foundation

/// A tree, as the wire sees it. Leaves carry the far-side session id — 0 for
/// a pane that is local and has no remote session behind it.
enum LayoutNode: Equatable {
    case leaf(session: UInt32)
    indirect case split(axis: LayoutAxis, ratio: Double,
                        first: LayoutNode, second: LayoutNode)
}

enum LayoutAxis: UInt8, Equatable {
    case row = 0      // children side by side
    case column = 1   // children stacked
}

struct PaneLayout: Equatable {
    var root: LayoutNode
    /// Which pane had the keyboard, as an index into leaves in tree order.
    /// An index rather than a session id because a local pane has no id, and
    /// tree order is stable across a round trip by construction.
    var activeLeaf: Int

    init(root: LayoutNode, activeLeaf: Int = 0) {
        self.root = root
        self.activeLeaf = activeLeaf
    }
}

extension PaneLayout {

    /// "SP" then a version byte. Two bytes of magic is enough to reject a
    /// blob written by something else entirely, which matters because the
    /// daemon will hand back whatever it was given.
    static let magic0: UInt8 = 0x53  // 'S'
    static let magic1: UInt8 = 0x50  // 'P'
    static let version: UInt8 = 1

    /// Ratios are stored as ten-thousandths rather than a float: two bytes,
    /// no endianness question, no NaN to decode, and 0.0001 is far finer than
    /// a seam can be dragged.
    static let ratioScale: Double = 10_000

    // MARK: - Encode

    func encoded() -> [UInt8] {
        var out: [UInt8] = [Self.magic0, Self.magic1, Self.version]
        let active = UInt16(clamping: max(0, activeLeaf))
        out.append(UInt8(active & 0xff))
        out.append(UInt8(active >> 8))
        Self.write(root, into: &out)
        return out
    }

    private static func write(_ node: LayoutNode, into out: inout [UInt8]) {
        switch node {
        case .leaf(let session):
            out.append(0x00)
            for i in 0..<4 { out.append(UInt8((session >> (8 * UInt32(i))) & 0xff)) }
        case .split(let axis, let ratio, let first, let second):
            out.append(0x01)
            out.append(axis.rawValue)
            // Clamped before scaling: a ratio outside 0...1 is not a layout
            // this format can mean, and wrapping it into a UInt16 would
            // decode as some other perfectly plausible split.
            let clamped = min(max(ratio, 0), 1)
            let scaled = UInt16(clamping: Int((clamped * ratioScale).rounded()))
            out.append(UInt8(scaled & 0xff))
            out.append(UInt8(scaled >> 8))
            write(first, into: &out)
            write(second, into: &out)
        }
    }

    // MARK: - Decode

    /// nil for anything not fully understood — bad magic, a version from the
    /// future, a truncated or malformed tree. The caller falls back to a
    /// default arrangement, which is the plan's degrade-not-fail rule.
    static func decode(_ bytes: [UInt8]) -> PaneLayout? {
        guard bytes.count >= 5,
              bytes[0] == magic0, bytes[1] == magic1, bytes[2] == version
        else { return nil }
        let active = Int(UInt16(bytes[3]) | (UInt16(bytes[4]) << 8))
        var off = 5
        guard let root = read(bytes, &off) else { return nil }
        // Trailing bytes mean the writer and this reader disagree about the
        // tree, even though the prefix parsed. Refusing is the honest answer.
        guard off == bytes.count else { return nil }
        return PaneLayout(root: root, activeLeaf: active)
    }

    private static func read(_ b: [UInt8], _ off: inout Int) -> LayoutNode? {
        guard off < b.count else { return nil }
        let tag = b[off]; off += 1
        switch tag {
        case 0x00:
            guard off + 4 <= b.count else { return nil }
            var session: UInt32 = 0
            for i in 0..<4 { session |= UInt32(b[off + i]) << (8 * UInt32(i)) }
            off += 4
            return .leaf(session: session)
        case 0x01:
            guard off + 3 <= b.count, let axis = LayoutAxis(rawValue: b[off])
            else { return nil }
            off += 1
            let scaled = UInt16(b[off]) | (UInt16(b[off + 1]) << 8)
            off += 2
            guard Double(scaled) <= ratioScale else { return nil }
            guard let first = read(b, &off), let second = read(b, &off)
            else { return nil }
            return .split(axis: axis, ratio: Double(scaled) / ratioScale,
                          first: first, second: second)
        default:
            return nil
        }
    }

    /// Leaves in tree order — the order `activeLeaf` indexes and the order a
    /// caller should hand sessions back in.
    var leaves: [UInt32] {
        var out: [UInt32] = []
        func walk(_ n: LayoutNode) {
            switch n {
            case .leaf(let s): out.append(s)
            case .split(_, _, let a, let b): walk(a); walk(b)
            }
        }
        walk(root)
        return out
    }
}
