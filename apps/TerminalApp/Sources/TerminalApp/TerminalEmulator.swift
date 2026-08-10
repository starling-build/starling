// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Cell

/// Character-cell attributes, bit flags.
struct CellAttrs: OptionSet {
    let rawValue: UInt8
    static let bold = CellAttrs(rawValue: 1 << 0)
    static let dim = CellAttrs(rawValue: 1 << 1)
    static let italic = CellAttrs(rawValue: 1 << 2)
    static let underline = CellAttrs(rawValue: 1 << 3)
    static let reverse = CellAttrs(rawValue: 1 << 4)
}

/// One terminal grid cell. Colors are ARGB; 0 means "default fg/bg".
///
/// `scalar` is a Unicode scalar value, NOT a `Character`, and that is load
/// bearing: it keeps this struct trivial (POD), so `[TermCell]` destroys with
/// a dealloc instead of a per-element release. It used to hold a `Character`,
/// which is bridge-object backed and refcounted — every cell overwritten or
/// dropped from scrollback took an ARC hit, and on a bulk dump that was the
/// single biggest cost in the app: a perf profile of `seq 1 20000000` showed
/// swift_arrayDestroy 14.5%, TermCell's destroy witness 13.6% and
/// swift_bridgeObjectRelease 18%, against 2.2% for the actual parsing.
///
/// Storing one scalar per cell loses nothing today: `feed` decodes exactly one
/// scalar per UTF-8 sequence and puts it in its own cell, so a base character
/// and a following combining mark already landed in separate cells. A real
/// grapheme-cluster cell would need a side table (the way Ghostty does it) and
/// is a separate change.
struct TermCell {
    var scalar: UInt32 = 32          // U+0020 space
    var fg: UInt32 = 0
    var bg: UInt32 = 0
    var attrs: CellAttrs = []

    /// The scalar as a `Character`, for rendering and clipboard text. Only the
    /// visible grid goes through this — never the feed path.
    var char: Character {
        Character(UnicodeScalar(scalar) ?? " ")
    }

    static let blank = TermCell()
}

// MARK: - Emulator

/// A VT100/xterm-flavoured terminal emulator: feed it PTY bytes, it maintains
/// a character grid (plus scrollback and an alternate screen) and emits
/// responses (DSR/DA) via `onResponse`.
///
/// Threading: `feed`/`resize` and grid reads must be externally synchronized
/// (the app wraps calls in a lock).
final class TerminalEmulator {

    private(set) var cols: Int
    private(set) var rows: Int

    /// The active screen, `rows` lines of `cols` cells.
    private(set) var grid: [[TermCell]]

    /// Lines scrolled off the top of the primary screen (oldest first).
    ///
    /// Kept between `scrollbackLimit` and `scrollbackLimit + scrollbackSlack`
    /// lines: trimming is batched (see `_scrollUp`), so the limit is a floor
    /// rather than an exact count.
    private(set) var scrollback: [[TermCell]] = []
    let scrollbackLimit = 2000
    /// How far scrollback may overshoot `scrollbackLimit` before it is cut
    /// back. Amortises the O(n) `removeFirst` across this many lines.
    let scrollbackSlack = 512

    private(set) var cursorRow = 0
    private(set) var cursorCol = 0
    private(set) var cursorVisible = true

    /// Incremented on every visible change; the UI compares generations to
    /// know when to repaint.
    private(set) var generation: UInt64 = 0

    /// Terminal responses (cursor position reports etc.) to write to the PTY.
    var onResponse: ((String) -> Void)?
    var onBell: (() -> Void)?

    // Current SGR drawing state
    private var curFg: UInt32 = 0
    private var curBg: UInt32 = 0
    private var curAttrs: CellAttrs = []

    // Scroll region (0-based, inclusive)
    private var regionTop = 0
    private var regionBottom: Int

    // Modes
    private var autowrap = true
    private var originMode = false
    private var wrapPending = false

    /// DECCKM — application cursor keys (arrows send ESC O x instead of CSI).
    private(set) var applicationCursorKeys = false

    /// DEC private mode 2004: paste is wrapped in ESC[200~ … ESC[201~ so
    /// TUIs (Claude Code, vim) treat it as one atomic insert.
    private(set) var bracketedPaste = false

    /// DEC private modes 1000/1002/1003 — the app wants mouse events. Only
    /// the wheel is actually reported (see the UI): that is what a scroll
    /// gesture needs, and forwarding presses too would take click-drag text
    /// selection away from the user inside every full-screen app.
    private(set) var mouseTracking = false
    /// DEC private mode 1006 — SGR encoding (`ESC [ < b ; x ; y M`). The
    /// legacy X10 encoding stuffs coordinates into single bytes and breaks
    /// past column 223, so reporting is gated on this being on rather than
    /// emitting something that misreports a wide window.
    private(set) var mouseSgr = false

    // Alternate screen support.
    /// Readable because the scrollback belongs to the PRIMARY buffer: while a
    /// full-screen app owns the screen there is nothing of its own to scroll
    /// back through, and walking the primary's history would replace the app
    /// on screen with whatever the shell printed before it started.
    private(set) var altActive = false
    private var savedPrimaryGrid: [[TermCell]]?
    private var savedPrimaryCursor: (Int, Int) = (0, 0)

    // Saved cursor (DECSC)
    private var savedCursor: (row: Int, col: Int) = (0, 0)
    private var savedFg: UInt32 = 0
    private var savedBg: UInt32 = 0
    private var savedAttrs: CellAttrs = []

    // Parser state
    private enum ParseState {
        case ground
        case escape          // saw ESC
        case escapeIntermediate(Character)  // e.g. ESC ( — consume one more
        case csi             // collecting CSI params
        case osc             // collecting OSC string
        case oscEscape       // saw ESC inside OSC (expecting \)
    }
    private var state: ParseState = .ground

    // CSI parameters, accumulated as NUMBERS while the bytes arrive.
    //
    // These used to be a `String` appended one `Character` at a time and then
    // `split(separator: ";").map(Int.init)` on dispatch. That is a String
    // build, a Substring split and an Int parse for every escape sequence —
    // and colour-per-cell output is ~200 escapes per row. It showed up in a
    // perf profile of a 24-bit-colour dump as String._uncheckedFromUTF8 2.9%,
    // Collection.split 2.1% and _uncheckedIndex(after:) 2.2%, plus the ARC
    // traffic they drag along. Digits fold into an Int as they arrive instead;
    // no String is built on this path at all.
    private var csiNums: [Int] = []
    /// The number being accumulated; -1 means "no digits since the last ';'",
    /// which is what distinguishes an absent parameter from an explicit 0.
    private var csiCur: Int = -1
    /// Leading '?' — DEC private mode.
    private var csiPrivate = false

    private var oscBuffer: String = ""

    // Incremental UTF-8 decoding
    private var utf8Pending: [UInt8] = []

    init(cols: Int, rows: Int) {
        self.cols = max(2, cols)
        self.rows = max(2, rows)
        self.regionBottom = self.rows - 1
        self.grid = Array(repeating: Array(repeating: .blank, count: self.cols),
                          count: self.rows)
    }

    // MARK: - Feeding input

    func feed(_ bytes: [UInt8]) {
        // Only splice when a partial UTF-8 sequence is actually carried over.
        // The old code built `utf8Pending + bytes` unconditionally, copying
        // every chunk that ever arrived; pending is empty on virtually all of
        // them, and then this is a retain rather than a copy.
        let input: [UInt8]
        if utf8Pending.isEmpty {
            input = bytes
        } else {
            var joined = utf8Pending
            joined.append(contentsOf: bytes)
            input = joined
        }
        utf8Pending = []

        var i = 0
        while i < input.count {
            let byte = input[i]

            // Fast path: a run of printable ASCII into the row the cursor is
            // already on.
            //
            // Going through _putScalar per byte means `grid[r][c] = …` per
            // byte, and that is a dynamically-enforced exclusive access to a
            // class property plus a COW uniqueness check on BOTH the outer and
            // the inner array — every character. On a profile of full-width
            // output that overhead was ~45% of the app's time
            // (swift_beginAccess + swift_endAccess + AccessSet::insert + the
            // TLS lookups behind them ~35%, swift_isUniquelyReferenced ~10%)
            // against 21% for the write itself. Taking the row's buffer once
            // and filling a whole run through it pays that cost once per run
            // instead of once per cell.
            if case .ground = state, !wrapPending,
               byte >= 0x20, byte < 0x7F,
               cursorRow >= 0, cursorRow < rows, cursorCol < cols {
                // Stop at the row's end, the chunk's end, or the first byte
                // that is not plain printable ASCII — anything else has to go
                // back through the state machine.
                let limit = min(input.count, i + (cols - cursorCol))
                var end = i
                while end < limit {
                    let b = input[end]
                    if b < 0x20 || b >= 0x7F { break }
                    end += 1
                }
                let n = end - i
                if n > 0 {
                    let fg = curFg, bg = curBg, at = curAttrs
                    let start = cursorCol
                    grid[cursorRow].withUnsafeMutableBufferPointer { row in
                        for k in 0 ..< n {
                            row[start + k] = TermCell(scalar: UInt32(input[i + k]),
                                                      fg: fg, bg: bg, attrs: at)
                        }
                    }
                    // Match _putScalar's wrap bookkeeping exactly: the cursor
                    // parks on the last column and arms wrapPending rather
                    // than stepping past the edge.
                    if start + n >= cols {
                        cursorCol = cols - 1
                        wrapPending = true
                    } else {
                        cursorCol = start + n
                    }
                    i = end
                    continue
                }
            }

            // In ground state, non-ASCII lead bytes start a UTF-8 sequence.
            if case .ground = state, byte >= 0x80 {
                let len = _utf8Length(byte)
                if i + len > input.count {
                    // Partial sequence — keep for the next feed.
                    utf8Pending = Array(input[i...])
                    break
                }
                // Decode the scalar arithmetically rather than through
                // String(bytes:encoding:) — that built a String (and then a
                // Character) for every non-ASCII character on the feed path.
                var v: UInt32
                switch len {
                case 2:  v = UInt32(byte & 0x1F)
                case 3:  v = UInt32(byte & 0x0F)
                case 4:  v = UInt32(byte & 0x07)
                default: v = UInt32(byte)
                }
                var valid = len > 1
                for k in 1 ..< max(len, 1) {
                    let cont = input[i + k]
                    if cont & 0xC0 != 0x80 { valid = false; break }
                    v = (v << 6) | UInt32(cont & 0x3F)
                }
                // U+FFFD for anything malformed or not a scalar, so a bad byte
                // never silently drops a cell.
                if !valid || UnicodeScalar(v) == nil { v = 0xFFFD }
                _putScalar(v)
                i += len
                continue
            }

            _processByte(byte)
            i += 1
        }
        generation &+= 1
    }

    private func _utf8Length(_ lead: UInt8) -> Int {
        if lead & 0xE0 == 0xC0 { return 2 }
        if lead & 0xF0 == 0xE0 { return 3 }
        if lead & 0xF8 == 0xF0 { return 4 }
        return 1
    }

    private func _processByte(_ byte: UInt8) {
        switch state {
        case .ground:
            _processGround(byte)
        case .escape:
            _processEscape(byte)
        case .escapeIntermediate:
            state = .ground  // consume the charset designator etc.
        case .csi:
            _processCsi(byte)
        case .osc:
            if byte == 0x07 {  // BEL terminator
                _finishOsc()
            } else if byte == 0x1B {
                state = .oscEscape
            } else {
                oscBuffer.append(Character(UnicodeScalar(byte)))
            }
        case .oscEscape:
            // ESC \ = ST terminator; anything else aborts the OSC.
            _finishOsc()
            if byte != 0x5C /* \ */ {
                _processByte(byte)
            }
        }
    }

    private func _processGround(_ byte: UInt8) {
        switch byte {
        case 0x07: onBell?()
        case 0x08:  // BS
            if cursorCol > 0 { cursorCol -= 1 }
            wrapPending = false
        case 0x09:  // TAB — fixed stops every 8
            cursorCol = min(cols - 1, ((cursorCol / 8) + 1) * 8)
        case 0x0A, 0x0B, 0x0C:  // LF, VT, FF
            _lineFeed()
        case 0x0D:  // CR
            cursorCol = 0
            wrapPending = false
        case 0x1B:
            state = .escape
        case 0x20...:
            _putScalar(UInt32(byte))
        default:
            break  // ignore other C0 controls
        }
    }

    private func _processEscape(_ byte: UInt8) {
        state = .ground
        switch byte {
        case UInt8(ascii: "["):
            csiNums.removeAll(keepingCapacity: true)
            csiCur = -1
            csiPrivate = false
            state = .csi
        case UInt8(ascii: "]"):
            oscBuffer = ""
            state = .osc
        case UInt8(ascii: "7"):  // DECSC
            _saveCursor()
        case UInt8(ascii: "8"):  // DECRC
            _restoreCursor()
        case UInt8(ascii: "D"):  // IND
            _lineFeed()
        case UInt8(ascii: "E"):  // NEL
            cursorCol = 0
            _lineFeed()
        case UInt8(ascii: "M"):  // RI — reverse index
            if cursorRow == regionTop {
                _scrollDown(1)
            } else if cursorRow > 0 {
                cursorRow -= 1
            }
        case UInt8(ascii: "c"):  // RIS — full reset
            _fullReset()
        case UInt8(ascii: "("), UInt8(ascii: ")"),
             UInt8(ascii: "*"), UInt8(ascii: "+"),
             UInt8(ascii: "#"), UInt8(ascii: "%"):
            state = .escapeIntermediate(Character(UnicodeScalar(byte)))
        case UInt8(ascii: "="), UInt8(ascii: ">"):
            break  // keypad modes — ignored
        default:
            break
        }
    }

    private func _processCsi(_ byte: UInt8) {
        // Parameter / intermediate bytes accumulate; 0x40-0x7E terminates.
        if byte >= 0x40 && byte <= 0x7E {
            state = .ground
            // Close the parameter in flight. An empty parameter list stays
            // empty: `CSI m` must give [] rather than [0], because callers
            // distinguish "no parameters" from "parameter 0".
            if csiCur >= 0 || !csiNums.isEmpty {
                csiNums.append(csiCur < 0 ? 0 : csiCur)
                csiCur = -1
            }
            _dispatchCsi(final: byte)
        } else if byte >= 0x30 && byte <= 0x39 {        // digit
            csiCur = (csiCur < 0 ? 0 : csiCur) * 10 + Int(byte - 0x30)
        } else if byte == 0x3B {                        // ';' separator
            csiNums.append(csiCur < 0 ? 0 : csiCur)
            csiCur = -1
        } else if byte == 0x3F {                        // '?' private marker
            csiPrivate = true
        } else if byte == 0x1B {
            state = .escape
        }
        // Other 0x20-0x3F bytes are intermediates (SP, '$', '"', …) and other
        // C0 bytes are ignored, as before — nothing we implement reads them.
    }

    private func _finishOsc() {
        state = .ground
        // OSC 0/2: window title — no-op for now (shell draws the title bar).
        oscBuffer = ""
    }

    // MARK: - CSI dispatch

    private func _params() -> [Int] { csiNums }

    private var _isPrivate: Bool { csiPrivate }

    private func _dispatchCsi(final: UInt8) {
        let params = _params()
        func p(_ i: Int, _ def: Int) -> Int {
            i < params.count && params[i] != 0 ? params[i] : def
        }

        switch final {
        case UInt8(ascii: "A"): _moveCursor(rowDelta: -p(0, 1), colDelta: 0)
        case UInt8(ascii: "B"): _moveCursor(rowDelta: p(0, 1), colDelta: 0)
        case UInt8(ascii: "C"): _moveCursor(rowDelta: 0, colDelta: p(0, 1))
        case UInt8(ascii: "D"): _moveCursor(rowDelta: 0, colDelta: -p(0, 1))
        case UInt8(ascii: "E"):
            cursorCol = 0
            _moveCursor(rowDelta: p(0, 1), colDelta: 0)
        case UInt8(ascii: "F"):
            cursorCol = 0
            _moveCursor(rowDelta: -p(0, 1), colDelta: 0)
        case UInt8(ascii: "G"), UInt8(ascii: "`"):
            cursorCol = max(0, min(cols - 1, p(0, 1) - 1))
            wrapPending = false
        case UInt8(ascii: "d"):
            _setCursor(row: p(0, 1) - 1, col: cursorCol)
        case UInt8(ascii: "H"), UInt8(ascii: "f"):
            _setCursor(row: p(0, 1) - 1, col: p(1, 1) - 1)
        case UInt8(ascii: "J"): _eraseDisplay(mode: params.first ?? 0)
        case UInt8(ascii: "K"): _eraseLine(mode: params.first ?? 0)
        case UInt8(ascii: "L"): _insertLines(p(0, 1))
        case UInt8(ascii: "M"): _deleteLines(p(0, 1))
        case UInt8(ascii: "P"): _deleteChars(p(0, 1))
        case UInt8(ascii: "@"): _insertChars(p(0, 1))
        case UInt8(ascii: "X"): _eraseChars(p(0, 1))
        case UInt8(ascii: "S"): _scrollUp(p(0, 1))
        case UInt8(ascii: "T"): _scrollDown(p(0, 1))
        case UInt8(ascii: "r"):
            let top = p(0, 1) - 1
            let bottom = p(1, rows) - 1
            if top < bottom && bottom < rows {
                regionTop = top
                regionBottom = bottom
            } else {
                regionTop = 0
                regionBottom = rows - 1
            }
            _setCursor(row: 0, col: 0)
        case UInt8(ascii: "m"): _sgr(params)
        case UInt8(ascii: "h"): _setMode(params, on: true)
        case UInt8(ascii: "l"): _setMode(params, on: false)
        case UInt8(ascii: "n"):
            if params.first == 5 { onResponse?("\u{1B}[0n") }
            if params.first == 6 {
                onResponse?("\u{1B}[\(cursorRow + 1);\(cursorCol + 1)R")
            }
        case UInt8(ascii: "c"):
            onResponse?("\u{1B}[?6c")  // claim VT102
        case UInt8(ascii: "s"): _saveCursor()
        case UInt8(ascii: "u"): _restoreCursor()
        case UInt8(ascii: "g"), UInt8(ascii: "t"), UInt8(ascii: "q"):
            break  // tab clear / window ops / cursor style — ignored
        default:
            break
        }
    }

    // MARK: - Cursor + character output

    private func _putChar(_ ch: Character) {
        _putScalar(ch.unicodeScalars.first?.value ?? 32)
    }

    /// The hot path: one Unicode scalar into the cell under the cursor.
    /// Takes a scalar rather than a `Character` so printing ASCII never builds
    /// a `Character` (which allocates) per byte — see `TermCell`.
    private func _putScalar(_ v: UInt32) {
        if wrapPending {
            wrapPending = false
            if autowrap {
                cursorCol = 0
                _lineFeed()
            }
        }
        guard cursorRow >= 0, cursorRow < rows,
              cursorCol >= 0, cursorCol < cols else { return }
        grid[cursorRow][cursorCol] = TermCell(
            scalar: v, fg: curFg, bg: curBg, attrs: curAttrs
        )
        if cursorCol == cols - 1 {
            wrapPending = true
        } else {
            cursorCol += 1
        }
    }

    private func _lineFeed() {
        wrapPending = false
        if cursorRow == regionBottom {
            _scrollUp(1)
        } else if cursorRow < rows - 1 {
            cursorRow += 1
        }
    }

    private func _moveCursor(rowDelta: Int, colDelta: Int) {
        cursorRow = max(0, min(rows - 1, cursorRow + rowDelta))
        cursorCol = max(0, min(cols - 1, cursorCol + colDelta))
        wrapPending = false
    }

    private func _setCursor(row: Int, col: Int) {
        let base = originMode ? regionTop : 0
        let limit = originMode ? regionBottom : rows - 1
        cursorRow = max(base, min(limit, base + row))
        cursorCol = max(0, min(cols - 1, col))
        wrapPending = false
    }

    private func _saveCursor() {
        savedCursor = (cursorRow, cursorCol)
        savedFg = curFg
        savedBg = curBg
        savedAttrs = curAttrs
    }

    private func _restoreCursor() {
        cursorRow = min(rows - 1, savedCursor.row)
        cursorCol = min(cols - 1, savedCursor.col)
        curFg = savedFg
        curBg = savedBg
        curAttrs = savedAttrs
        wrapPending = false
    }

    // MARK: - Erase / edit

    private var _blankCell: TermCell {
        TermCell(scalar: 32, fg: 0, bg: curBg, attrs: [])
    }

    private func _blankLine() -> [TermCell] {
        Array(repeating: _blankCell, count: cols)
    }

    // A single blank row, shared by copy-on-write with every grid row that is
    // currently blank.
    //
    // Building a fresh one per scrolled line was, by a distance, the most
    // expensive thing the emulator did: `perf annotate` on _scrollUp showed
    // its time going almost entirely into the fill loop's `movq $0x20` /
    // `movb $0x0` stores — 16 bytes x 241 cells, for every line that scrolls
    // off. Handing out the shared row instead makes a scroll a retain. The
    // first write to that row pays one copy-on-write memcpy, which is cheaper
    // than the store-immediate fill it replaces, and a row that scrolls past
    // untouched now costs nothing at all.
    //
    // Keyed on curBg because _blankCell carries it (SGR can set the background
    // that erased cells take), and on cols because a resize changes the width.
    private var _blankRowCache: [TermCell] = []
    private var _blankRowCacheBg: UInt32 = .max
    private var _blankRowCacheCols: Int = -1

    private func _sharedBlankLine() -> [TermCell] {
        if _blankRowCacheBg != curBg || _blankRowCacheCols != cols {
            _blankRowCache = Array(repeating: _blankCell, count: cols)
            _blankRowCacheBg = curBg
            _blankRowCacheCols = cols
        }
        return _blankRowCache
    }

    private func _eraseDisplay(mode: Int) {
        switch mode {
        case 0:
            _eraseLine(mode: 0)
            for r in (cursorRow + 1) ..< rows { grid[r] = _sharedBlankLine() }
        case 1:
            _eraseLine(mode: 1)
            for r in 0 ..< cursorRow { grid[r] = _sharedBlankLine() }
        case 2:
            for r in 0 ..< rows { grid[r] = _sharedBlankLine() }
        case 3:
            for r in 0 ..< rows { grid[r] = _sharedBlankLine() }
            scrollback.removeAll()
        default:
            break
        }
    }

    private func _eraseLine(mode: Int) {
        guard cursorRow >= 0 && cursorRow < rows else { return }
        switch mode {
        case 0:
            for c in cursorCol ..< cols { grid[cursorRow][c] = _blankCell }
        case 1:
            for c in 0 ... min(cursorCol, cols - 1) { grid[cursorRow][c] = _blankCell }
        case 2:
            grid[cursorRow] = _sharedBlankLine()
        default:
            break
        }
    }

    private func _eraseChars(_ n: Int) {
        guard cursorRow >= 0 && cursorRow < rows else { return }
        for c in cursorCol ..< min(cols, cursorCol + n) {
            grid[cursorRow][c] = _blankCell
        }
    }

    private func _deleteChars(_ n: Int) {
        guard cursorRow >= 0 && cursorRow < rows else { return }
        var line = grid[cursorRow]
        let count = min(n, cols - cursorCol)
        line.removeSubrange(cursorCol ..< cursorCol + count)
        line.append(contentsOf: Array(repeating: _blankCell, count: count))
        grid[cursorRow] = line
    }

    private func _insertChars(_ n: Int) {
        guard cursorRow >= 0 && cursorRow < rows else { return }
        var line = grid[cursorRow]
        let count = min(n, cols - cursorCol)
        line.insert(contentsOf: Array(repeating: _blankCell, count: count),
                    at: cursorCol)
        line.removeLast(count)
        grid[cursorRow] = line
    }

    private func _insertLines(_ n: Int) {
        guard cursorRow >= regionTop && cursorRow <= regionBottom else { return }
        let count = min(n, regionBottom - cursorRow + 1)
        for _ in 0 ..< count {
            grid.remove(at: regionBottom)
            grid.insert(_sharedBlankLine(), at: cursorRow)
        }
        cursorCol = 0
    }

    private func _deleteLines(_ n: Int) {
        guard cursorRow >= regionTop && cursorRow <= regionBottom else { return }
        let count = min(n, regionBottom - cursorRow + 1)
        for _ in 0 ..< count {
            grid.remove(at: cursorRow)
            grid.insert(_sharedBlankLine(), at: regionBottom)
        }
        cursorCol = 0
    }

    private func _scrollUp(_ n: Int) {
        for _ in 0 ..< n {
            let removed = grid[regionTop]
            if !altActive && regionTop == 0 {
                scrollback.append(removed)
                // Trim in batches, not every line. `removeFirst` shifts the
                // whole array, so trimming the instant the limit is exceeded
                // made every scrolled line an O(scrollbackLimit) memmove —
                // 9% of the profile on a bulk dump. Letting it overshoot by
                // `scrollbackSlack` and then cutting back amortises that to
                // O(1) per line, at the cost of holding a few hundred extra
                // lines. Readers must therefore treat `scrollbackLimit` as a
                // floor, not an exact size — `scrollbackCount` is the truth.
                if scrollback.count > scrollbackLimit + scrollbackSlack {
                    scrollback.removeFirst(scrollback.count - scrollbackLimit)
                }
            }
            grid.remove(at: regionTop)
            grid.insert(_sharedBlankLine(), at: regionBottom)
        }
    }

    private func _scrollDown(_ n: Int) {
        for _ in 0 ..< n {
            grid.remove(at: regionBottom)
            grid.insert(_sharedBlankLine(), at: regionTop)
        }
    }

    // MARK: - SGR (colors / attributes)

    private func _sgr(_ params: [Int]) {
        let params = params.isEmpty ? [0] : params
        var i = 0
        while i < params.count {
            let p = params[i]
            switch p {
            case 0:
                curFg = 0; curBg = 0; curAttrs = []
            case 1: curAttrs.insert(.bold)
            case 2: curAttrs.insert(.dim)
            case 3: curAttrs.insert(.italic)
            case 4: curAttrs.insert(.underline)
            case 7: curAttrs.insert(.reverse)
            case 22: curAttrs.remove([.bold, .dim])
            case 23: curAttrs.remove(.italic)
            case 24: curAttrs.remove(.underline)
            case 27: curAttrs.remove(.reverse)
            case 30...37: curFg = TermPalette.ansi(p - 30, bold: false)
            case 39: curFg = 0
            case 40...47: curBg = TermPalette.ansi(p - 40, bold: false)
            case 49: curBg = 0
            case 90...97: curFg = TermPalette.ansi(p - 90, bold: true)
            case 100...107: curBg = TermPalette.ansi(p - 100, bold: true)
            case 38, 48:
                // 38;5;n / 38;2;r;g;b (and 48;… for background)
                var color: UInt32? = nil
                if i + 2 < params.count && params[i + 1] == 5 {
                    color = TermPalette.color256(params[i + 2])
                    i += 2
                } else if i + 4 < params.count && params[i + 1] == 2 {
                    let r = UInt32(clamping: params[i + 2])
                    let g = UInt32(clamping: params[i + 3])
                    let b = UInt32(clamping: params[i + 4])
                    color = 0xFF00_0000 | (r << 16) | (g << 8) | b
                    i += 4
                }
                if let color = color {
                    if p == 38 { curFg = color } else { curBg = color }
                }
            default:
                break
            }
            i += 1
        }
    }

    // MARK: - Modes

    private func _setMode(_ params: [Int], on: Bool) {
        guard _isPrivate else { return }  // ANSI modes (4 insert…) ignored
        for p in params {
            switch p {
            case 1: applicationCursorKeys = on
            case 7: autowrap = on
            case 6:
                originMode = on
                _setCursor(row: 0, col: 0)
            case 25: cursorVisible = on
            case 47, 1047:
                on ? _enterAltScreen(saveCursor: false)
                   : _exitAltScreen(restoreCursor: false)
            case 1049:
                on ? _enterAltScreen(saveCursor: true)
                   : _exitAltScreen(restoreCursor: true)
            case 1048:
                on ? _saveCursor() : _restoreCursor()
            case 2004:
                bracketedPaste = on
            // Mouse tracking. We report the WHEEL only (see the UI's
            // onPointerSignal), which is what makes scrolling work inside a
            // full-screen app; the exact tracking flavour does not change how
            // a wheel event is encoded, so all three set the same flag.
            case 1000, 1002, 1003:
                mouseTracking = on
            case 1006:
                mouseSgr = on
            default:
                break  // blinking, focus reporting… ignored
            }
        }
    }

    private func _enterAltScreen(saveCursor: Bool) {
        guard !altActive else { return }
        if saveCursor { _saveCursor() }
        savedPrimaryGrid = grid
        savedPrimaryCursor = (cursorRow, cursorCol)
        altActive = true
        grid = Array(repeating: _sharedBlankLine(), count: rows)
        cursorRow = 0
        cursorCol = 0
    }

    private func _exitAltScreen(restoreCursor: Bool) {
        guard altActive else { return }
        altActive = false
        if let saved = savedPrimaryGrid {
            grid = saved
            // Re-normalize in case a resize happened while in the alt screen.
            _normalizeGrid()
        }
        (cursorRow, cursorCol) = savedPrimaryCursor
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, cols - 1)
        savedPrimaryGrid = nil
        if restoreCursor { _restoreCursor() }
    }

    private func _fullReset() {
        grid = Array(repeating: Array(repeating: .blank, count: cols), count: rows)
        scrollback.removeAll()
        cursorRow = 0
        cursorCol = 0
        curFg = 0
        curBg = 0
        curAttrs = []
        regionTop = 0
        regionBottom = rows - 1
        autowrap = true
        originMode = false
        wrapPending = false
        cursorVisible = true
        altActive = false
        savedPrimaryGrid = nil
    }

    // MARK: - Scrollback view

    /// Number of scrollback lines currently stored.
    var scrollbackCount: Int { scrollback.count }

    /// The `rows` lines visible when scrolled back by `offset` lines
    /// (0 = the live screen). Clamped to the available history.
    func visibleLines(offset: Int) -> [[TermCell]] {
        let off = max(0, min(offset, scrollback.count))
        if off == 0 { return grid }
        let base = scrollback.count - off
        var lines: [[TermCell]] = []
        lines.reserveCapacity(rows)
        for i in 0 ..< rows {
            let idx = base + i
            if idx < scrollback.count {
                // Scrollback lines may predate a resize — normalize width.
                lines.append(_fitLine(scrollback[idx]))
            } else {
                lines.append(grid[idx - scrollback.count])
            }
        }
        return lines
    }

    // MARK: - Resize

    func resize(cols newCols: Int, rows newRows: Int) {
        let newCols = max(2, newCols)
        let newRows = max(2, newRows)
        guard newCols != cols || newRows != rows else { return }
        cols = newCols
        rows = newRows
        regionTop = 0
        regionBottom = rows - 1
        _normalizeGrid()
        if var saved = savedPrimaryGrid {
            for i in 0 ..< saved.count { saved[i] = _fitLine(saved[i]) }
            while saved.count < rows { saved.append(_blankLine()) }
            while saved.count > rows { saved.removeFirst() }
            savedPrimaryGrid = saved
        }
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, cols - 1)
        wrapPending = false
        generation &+= 1
    }

    private func _fitLine(_ line: [TermCell]) -> [TermCell] {
        if line.count == cols { return line }
        if line.count > cols { return Array(line[0 ..< cols]) }
        return line + Array(repeating: .blank, count: cols - line.count)
    }

    private func _normalizeGrid() {
        for i in 0 ..< grid.count { grid[i] = _fitLine(grid[i]) }
        while grid.count < rows { grid.append(_blankLine()) }
        while grid.count > rows {
            // Push overflow into scrollback (primary screen only)
            let removed = grid.removeFirst()
            if !altActive {
                scrollback.append(removed)
                if scrollback.count > scrollbackLimit {
                    scrollback.removeFirst(scrollback.count - scrollbackLimit)
                }
            }
            if cursorRow > 0 { cursorRow -= 1 }
        }
    }
}

// MARK: - Palette

/// xterm-256 color palette (ARGB).
enum TermPalette {
    /// The standard 16 ANSI colors (macOS Terminal-ish values, dark theme).
    static let ansi16: [UInt32] = [
        0xFF000000, 0xFFC23621, 0xFF25BC24, 0xFFADAD27,
        0xFF4C7BD4, 0xFFD338D3, 0xFF33BBC8, 0xFFCBCCCD,
        0xFF818383, 0xFFFC391F, 0xFF31E722, 0xFFEAEC23,
        0xFF6A9BF5, 0xFFF935F8, 0xFF14F0F0, 0xFFFFFFFF,
    ]

    static func ansi(_ index: Int, bold: Bool) -> UInt32 {
        let i = max(0, min(7, index)) + (bold ? 8 : 0)
        return ansi16[i]
    }

    static func color256(_ index: Int) -> UInt32 {
        let i = max(0, min(255, index))
        if i < 16 { return ansi16[i] }
        if i < 232 {
            // 6x6x6 color cube
            let v = i - 16
            let steps: [UInt32] = [0, 95, 135, 175, 215, 255]
            let r = steps[(v / 36) % 6]
            let g = steps[(v / 6) % 6]
            let b = steps[v % 6]
            return 0xFF00_0000 | (r << 16) | (g << 8) | b
        }
        // Grayscale ramp
        let gray = UInt32(8 + (i - 232) * 10)
        return 0xFF00_0000 | (gray << 16) | (gray << 8) | gray
    }
}
