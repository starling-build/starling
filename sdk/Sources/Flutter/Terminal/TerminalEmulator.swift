// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import CTerminalCore
import Foundation

// MARK: - Cell

/// Character-cell attributes, bit flags.
///
/// `rawValue` is a `UInt8` and that is load bearing: it puts `attrs` at offset
/// 12 of a 16-byte `TermCell`, matching `StarlingTermCell` on the C side so the
/// grid can be copied across the boundary with no per-field marshalling. A
/// `UInt32` here would make the two disagree about the three bytes after it.
public struct CellAttrs: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let bold = CellAttrs(rawValue: 1 << 0)
    public static let dim = CellAttrs(rawValue: 1 << 1)
    public static let italic = CellAttrs(rawValue: 1 << 2)
    public static let underline = CellAttrs(rawValue: 1 << 3)
    public static let reverse = CellAttrs(rawValue: 1 << 4)
    /// A two-column character: the lead cell carries the scalar, the
    /// continuation cell carries scalar 0 and draws nothing — the lead's
    /// glyph spans both columns. Mirrors STARLING_ATTR_WIDE/_WIDE_CONT.
    public static let wideLead = CellAttrs(rawValue: 1 << 5)
    public static let wideCont = CellAttrs(rawValue: 1 << 6)
}

/// One terminal grid cell. Colors are ARGB; 0 means "default fg/bg".
///
/// Layout must stay identical to `StarlingTermCell`: size 13, stride 16,
/// align 4, offsets scalar=0 fg=4 bg=8 attrs=12.
public struct TermCell: Sendable {
    public var scalar: UInt32 = 32          // U+0020 space
    public var fg: UInt32 = 0
    public var bg: UInt32 = 0
    public var attrs: CellAttrs = []

    /// The scalar as a `Character`, for rendering and clipboard text.
    public var char: Character {
        Character(UnicodeScalar(scalar) ?? " ")
    }

    public static let blank = TermCell()
    public init() {}
}

// MARK: - Emulator

/// A VT100/xterm-flavoured terminal emulator: feed it PTY bytes, it maintains a
/// character grid (plus scrollback and an alternate screen) and emits responses
/// (DSR/DA) via `onResponse`.
///
/// The parser and grid live in C (`sdk/Sources/CTerminalCore`). The Swift version
/// this replaced spent ~47% of its time in runtime bookkeeping — dynamic
/// exclusivity checks, ARC and copy-on-write — rather than in the emulator's
/// own work, because an escape between every cell collapses the printable-run
/// fast path to length one and each cell then pays those checks individually.
/// Measured on the ten-workload suite the C core is 1.1x to 5.1x faster, with
/// the largest gains exactly where the escapes are. It is a straight port:
/// `test/bench/core/` diffs the two implementations cell-for-cell over the
/// whole benchmark corpus, a hand-written edge-case stream at six grids and
/// five chunk sizes, and 200 randomised streams — all identical.
///
/// Threading: `feed`/`resize` and grid reads must be externally synchronized
/// (the app wraps calls in a lock).
public final class TerminalEmulator {

    private let t: OpaquePointer

    /// Kept between `scrollbackLimit` and `scrollbackLimit + scrollbackSlack`
    /// lines: trimming is batched on the C side, so the limit is a floor rather
    /// than an exact count. `scrollbackCount` is the truth.
    public let scrollbackLimit = 2000
    public let scrollbackSlack = 512

    /// Terminal responses (cursor position reports etc.) to write to the PTY.
    public var onResponse: ((String) -> Void)?
    public var onBell: (() -> Void)?

    public init(cols: Int, rows: Int) {
        t = starling_term_new(Int32(cols), Int32(rows))
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        starling_term_set_response_cb(
            t,
            { ctx, s in
                guard let ctx = ctx, let s = s else { return }
                let me = Unmanaged<TerminalEmulator>.fromOpaque(ctx).takeUnretainedValue()
                me.onResponse?(String(cString: s))
            }, ctx)
        starling_term_set_bell_cb(
            t,
            { ctx in
                guard let ctx = ctx else { return }
                Unmanaged<TerminalEmulator>.fromOpaque(ctx).takeUnretainedValue().onBell?()
            }, ctx)
    }

    deinit { starling_term_free(t) }

    private var _t: OpaquePointer { t }

    // MARK: - Feeding input

    public func feed(_ bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            starling_term_feed(_t, base, buf.count)
        }
    }

    /// Feeds bytes the caller already owns, with no intermediate `Array`.
    /// The PTY reader owns its buffers for the duration of the call, so the
    /// per-chunk allocation and copy that `feed([UInt8])` implies is pure waste
    /// on the one path that has to keep up with a flood.
    public func feed(_ bytes: UnsafePointer<UInt8>, count: Int) {
        starling_term_feed(_t, bytes, count)
    }

    public func resize(cols newCols: Int, rows newRows: Int) {
        starling_term_resize(_t, Int32(newCols), Int32(newRows))
    }

    // MARK: - State

    public var cols: Int { Int(starling_term_cols(_t)) }
    public var rows: Int { Int(starling_term_rows(_t)) }
    public var cursorRow: Int { Int(starling_term_cursor_row(_t)) }
    public var cursorCol: Int { Int(starling_term_cursor_col(_t)) }
    public var cursorVisible: Bool { starling_term_cursor_visible(_t) != 0 }
    public var applicationCursorKeys: Bool { starling_term_app_cursor_keys(_t) != 0 }
    public var bracketedPaste: Bool { starling_term_bracketed_paste(_t) != 0 }
    public var generation: UInt64 { starling_term_generation(_t) }

    /// Readable because the scrollback belongs to the PRIMARY buffer: while a
    /// full-screen app owns the screen there is nothing of its own to scroll
    /// back through, and walking the primary's history would replace the app
    /// on screen with whatever the shell printed before it started.
    public var altActive: Bool { starling_term_alt_active(_t) != 0 }

    /// DEC private modes 1000/1002/1003 — the app wants mouse events. Only
    /// the wheel is actually reported (see the UI): that is what a scroll
    /// gesture needs, and forwarding presses too would take click-drag text
    /// selection away from the user inside every full-screen app.
    public var mouseTracking: Bool { starling_term_mouse_tracking(_t) != 0 }

    /// DEC private mode 1006 — SGR encoding (`ESC [ < b ; x ; y M`). The
    /// legacy X10 encoding stuffs coordinates into single bytes and breaks
    /// past column 223, so reporting is gated on this being on rather than
    /// emitting something that misreports a wide window.
    public var mouseSgr: Bool { starling_term_mouse_sgr(_t) != 0 }

    /// Number of scrollback lines currently stored.
    public var scrollbackCount: Int { Int(starling_term_scrollback_count(_t)) }

    // MARK: - Reading the grid
    //
    // These copy out of the C grid. They are UI-path only — once per repaint
    // for `visibleLines`, on demand for selection — never on the feed path,
    // which is the one that has to be fast.

    /// The full text of a cell — for grapheme-cluster references (scalar
    /// above the Unicode range) this is the whole sequence: a ZWJ emoji
    /// family, a conjunct, a base with its combining marks.
    public func cellText(_ scalar: UInt32) -> String {
        var buf = [UInt8](repeating: 0, count: 64)
        let n = buf.withUnsafeMutableBufferPointer { p -> Int32 in
            p.baseAddress!.withMemoryRebound(to: CChar.self, capacity: 64) { cp in
                starling_term_cell_text(_t, scalar, cp, 64)
            }
        }
        guard n > 0 else { return " " }
        return String(decoding: buf[0..<Int(n)], as: UTF8.self)
    }

    /// One line by absolute index: scrollback first, then the live screen.
    private func _line(_ absIndex: Int) -> [TermCell] {
        let n = cols
        var line = [TermCell](repeating: .blank, count: n)
        line.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.withMemoryRebound(to: StarlingTermCell.self, capacity: n) { p in
                starling_term_copy_line(_t, Int32(absIndex), p)
            }
        }
        return line
    }

    /// The active screen, `rows` lines of `cols` cells.
    public var grid: [[TermCell]] {
        let sb = scrollbackCount
        return (0 ..< rows).map { _line(sb + $0) }
    }

    /// Lines scrolled off the top of the primary screen (oldest first).
    public var scrollback: [[TermCell]] {
        (0 ..< scrollbackCount).map { _line($0) }
    }

    /// The `rows` lines visible when scrolled back by `offset` lines
    /// (0 = the live screen). Clamped to the available history.
    public func visibleLines(offset: Int) -> [[TermCell]] {
        let sb = scrollbackCount
        let off = max(0, min(offset, sb))
        let base = sb - off
        return (0 ..< rows).map { _line(base + $0) }
    }
}
