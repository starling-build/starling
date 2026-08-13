// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The view half of the terminal widget (docs/plans/terminal-widget.md):
// renders a TerminalSession's grid and feeds it keys, mouse and clipboard.
// Extracted verbatim from TerminalApp, which proved every path in here —
// the row painter's run merging and style cache priced by the benchmark
// suite, the cell-metric discipline, wide/cluster rendering, mouse
// reporting, alternateScroll, scrollback, selection and IME caret.

import Foundation
import FlutterSwiftBridge

// MARK: - Theme

/// Colors for a TerminalView. Values are ARGB; the defaults are the
/// Starling terminal's own look.
public struct TerminalTheme: Sendable {
    /// Window background (may carry alpha — the desktop composites it).
    public var background: UInt32
    /// Foreground for cells that carry no color of their own.
    public var defaultForeground: UInt32
    /// The translucent block cursor overlay.
    public var cursorOverlay: UInt32
    /// The translucent selection highlight.
    public var selection: UInt32

    /// Reverse-video background for default-colored cells: the opaque form
    /// of `background`.
    var reverseBackground: UInt32 { background | 0xFF00_0000 }

    public init(background: UInt32 = 0xD91E2127,
                defaultForeground: UInt32 = 0xFFD4D4D4,
                cursorOverlay: UInt32 = 0x99D4D4D4,
                selection: UInt32 = 0x4066AAFF) {
        self.background = background
        self.defaultForeground = defaultForeground
        self.cursorOverlay = cursorOverlay
        self.selection = selection
    }

    public static let starlingDark = TerminalTheme()
}

/// Font for a TerminalView. The default is the bundled Roboto Mono with
/// the bundled DejaVu Sans Mono (box/block glyphs) plus, where installed,
/// the system Noto CJK and Color Emoji faces as fallbacks.
public struct TerminalFont: Sendable {
    public var family: String
    public var size: Double
    /// Families tried for glyphs the primary lacks, in order; nil means the
    /// loader's list, resolved LAZILY — registration appends the system CJK
    /// and emoji faces, and a list captured before that ran would render
    /// those cells as blank gaps. The engine has NO system font fallback of
    /// its own: a glyph missing from every listed family paints nothing.
    public var fallback: [String]?

    public init(family: String = TerminalFontLoader.family,
                size: Double = 13,
                fallback: [String]? = nil) {
        self.family = family
        self.size = size
        self.fallback = fallback
    }
}

// MARK: - Bundled font registration

public enum TerminalFontLoader {
    public static let family = "RobotoMono"
    /// Roboto Mono maps 878 codepoints and has none of U+2500 (box drawing),
    /// U+2580 (blocks), U+25A0 (shapes), U+2190 (arrows) or ✓✗ — and there is
    /// no system font fallback here, so those cells painted *nothing*: every
    /// TUI frame (Claude Code, vim, htop, mc) was invisible while its text
    /// rendered fine. DejaVu Sans Mono covers all four ranges completely and
    /// its advance is 0.6021 em against Roboto Mono's 0.6001, so a run of box
    /// characters stays on the grid to well under half a cell.
    public static let fallbackFamily = "DejaVuSansMono"
    /// Braille (U+2800–U+28FF) is in NO monospace font we can reach — not
    /// Roboto Mono, not DejaVu Sans Mono, not the Noto faces below — and TUIs
    /// spin with it: Claude Code alone ships 82 distinct braille frames, so its
    /// whole thinking indicator painted as an empty cell. DejaVu *Sans* (the
    /// proportional sibling, same family, same licence) has all 256, plus most
    /// of U+2B00 that the mono cut also lacks.
    ///
    /// It is LAST in the chain for two reasons. Anything the mono face has must
    /// resolve there — Sans is proportional, and its ✓ is 0.8379 em against the
    /// grid's 0.6001 — and the Noto faces must keep colour emoji, which Sans
    /// would otherwise answer for in monochrome. Even so a braille cell is
    /// 0.7324 em, 22% over: a spinner shifts the rest of ITS row a couple of
    /// pixels right, and softWrap:false clips the tail (see the note on the
    /// row's Text). Visible dots beat a correctly-sized blank; the tighter
    /// option, if that ever grates, is DejaVu Sans Condensed at 0.6592.
    public static let symbolFallbackFamily = "DejaVuSans"
    /// Every text style in the terminal carries this, so a glyph missing from
    /// the primary family is looked up here instead of dropping out.
    public private(set) nonisolated(unsafe) static var fallback = [fallbackFamily]
    /// On Linux the engine has NO system font fallback: a glyph missing from
    /// every loaded family paints NOTHING — `cat` of CJK or emoji text
    /// rendered as blank gaps while the cursor advanced correctly over the
    /// cells (the emulator was right; there was simply no glyph to draw).
    /// Load the system Noto CJK and Color Emoji faces as additional fallbacks
    /// when present; mappedIfSafe keeps the 20 MB TTC out of our copy of RSS.
    private static let systemFallbacks: [(path: String, family: String)] = [
        ("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", "NotoSansCJK"),
        ("/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf", "NotoColorEmoji"),
    ]
    /// macOS resolves families through CoreText, which DOES fall back on its
    /// own — that is why CJK painted here while emoji did not: CoreText finds
    /// Hiragino for 漢 but nothing reaches for Apple Color Emoji unless a
    /// family asks for it. So name the system faces rather than loading them.
    ///
    /// Naming, not loading, is the point. The paths above are `/usr/share`,
    /// which does not exist on macOS, so both registrations silently failed
    /// and the list stayed one entry long. Pointing them at the macOS faces
    /// instead would be worse than useless: `LoadFontFromList` hands the
    /// bytes to `SkMemoryStream(..., /*copy=*/true)`, so Apple Color Emoji
    /// alone would COPY 192 MB into RSS — a terminal that costs more resident
    /// memory than the rest of the desktop, to get glyphs CoreText already
    /// has. A family name in the fallback list costs nothing until a cell
    /// needs it.
    private static let systemFamilyNames = [
        "Apple Color Emoji",     // emoji; nothing else carries them
        "Hiragino Sans GB",      // Chinese
        "Hiragino Kaku Gothic ProN",  // Japanese kana
        "Apple SD Gothic Neo",   // Korean
    ]
    private nonisolated(unsafe) static var _registered = false

    @discardableResult
    public static func register() -> Bool {
        guard !_registered else { return true }
        var ok = false
        var symbolsLoaded = false
        for (name, family) in [("RobotoMono-Regular", family),
                               ("RobotoMono-Bold", family),
                               ("DejaVuSansMono-Regular", fallbackFamily),
                               ("DejaVuSansMono-Bold", fallbackFamily),
                               ("DejaVuSans", symbolFallbackFamily)] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf"),
                  let data = try? Data(contentsOf: url) else { continue }
            let success = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
                guard let base = buffer.baseAddress else { return false }
                let ptr = base.assumingMemoryBound(to: UInt8.self)
                return flutter.swift_bridge.LoadFontFromList(ptr, data.count, family)
            }
            ok = ok || success
            if family == symbolFallbackFamily { symbolsLoaded = success }
        }
        #if os(macOS)
        fallback.append(contentsOf: systemFamilyNames)
        #else
        for (path, family) in systemFallbacks {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path),
                                       options: .mappedIfSafe) else { continue }
            let success = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
                guard let base = buffer.baseAddress else { return false }
                let ptr = base.assumingMemoryBound(to: UInt8.self)
                return flutter.swift_bridge.LoadFontFromList(ptr, data.count, family)
            }
            if success { fallback.append(family) }
        }
        #endif
        // After the system faces, so colour emoji still wins its own
        // codepoints — on macOS those are names in `systemFamilyNames`, on
        // Linux the Noto files loaded just above.
        if symbolsLoaded { fallback.append(symbolFallbackFamily) }
        _registered = ok
        return ok
    }
}

// MARK: - TerminalView

/// A terminal, as a widget: give it a TerminalSession and it renders the
/// grid, routes keys/mouse/clipboard, and keeps the child process's window
/// size in step with its own layout.
///
///     let session = TerminalSession()
///     session.startShell()
///     // ...
///     TerminalView(session: session)
///
public final class TerminalView: StatefulWidget {
    let session: TerminalSession
    let theme: TerminalTheme
    let font: TerminalFont
    let padding: Double
    /// The box this view will be laid out in, when the parent already knows
    /// it — a pane in a workspace, a split, a tile. nil means "the whole
    /// window", which is right for a terminal that IS the app and wrong for
    /// every embedded one: the grid would be sized from the window while the
    /// view is painted into a smaller box, so the child process is told a
    /// window size it does not have. (The framework has no LayoutBuilder to
    /// discover this from below.)
    let size: Size?
    let autofocus: Bool
    /// Pressing Enter after the child exits calls `session.restart()` — the
    /// shipped Terminal's behaviour, and for a command session it repeats the
    /// command rather than dropping to a shell. Turn off to own the lifecycle
    /// via `session.onExit`.
    let restartOnEnter: Bool
    /// First refusal on every key, for the app around the terminal.
    ///
    /// A terminal claims the keyboard almost completely — that is its job —
    /// so an embedder that wants a chord of its own (an overview, a pane
    /// switcher, a command palette) has nowhere to put it: an ancestor
    /// Focus never sees a key the focused view consumed. Return true to
    /// swallow the key; the terminal then never sees it.
    let keyFilter: ((KeyData) -> Bool)?

    public init(session: TerminalSession,
                theme: TerminalTheme = .starlingDark,
                font: TerminalFont = TerminalFont(),
                padding: Double = 8,
                size: Size? = nil,
                autofocus: Bool = true,
                restartOnEnter: Bool = true,
                keyFilter: ((KeyData) -> Bool)? = nil) {
        self.session = session
        self.theme = theme
        self.font = font
        self.padding = padding
        self.size = size
        self.autofocus = autofocus
        self.restartOnEnter = restartOnEnter
        self.keyFilter = keyFilter
        super.init()
    }

    override public func createState() -> State<StatefulWidget> {
        return _TerminalViewState(session: session)
    }
}

final class _TerminalViewState: State<StatefulWidget>, @unchecked Sendable {

    /// The session is the view's identity and is captured once; everything
    /// else is read from the CURRENT widget, so a parent that rebuilds with
    /// a new size or theme is honoured without remounting the terminal.
    private let session: TerminalSession
    private var w: TerminalView { widget as! TerminalView }
    private var theme: TerminalTheme { w.theme }
    private var font: TerminalFont { w.font }
    private var padding: Double { w.padding }

    private var _fontFallback: [String] { font.fallback ?? TerminalFontLoader.fallback }
    private var _lock: NSLock { session.lock }
    private var emulator: TerminalEmulator { session.emulator }
    private var _exited: Bool { session.processExited }

    private let focusNode = FocusNode(debugLabel: "Terminal")

    /// Monospace cell metrics, measured once at startup.
    private var cellW: Double = 7.8
    private var cellH: Double = 17.0
    /// Extra per-glyph advance when STARLING_CELL_W forces the cell width
    /// away from the font's natural advance. 0 in normal operation.
    private var _cellSpacing: Double = 0

    /// Coalesces reader-thread repaint requests.
    private var _updatePending = false

    /// Scrollback view offset in lines (0 = live screen). Shift+PageUp/Down,
    /// the mouse wheel, or a touchpad pan.
    private var _viewOffset = 0
    /// Fractional lines carried between touchpad pan events.
    private var _panLines: Double = 0
    /// True while this terminal is the reported IME caret anchor.
    private var _sentImeCaret = false

    /// Shift state tracked from modifier key events (keysyms 0xFFE1/0xFFE2).
    private var _shiftDown = false
    /// Ctrl state (keysyms 0xFFE3/0xFFE4) — for Ctrl+Shift+C/V copy/paste.
    private var _ctrlDown = false

    /// Text selection, in ABSOLUTE buffer coordinates (line index into
    /// scrollback+grid, column) so it stays anchored to content while new
    /// output scrolls the screen or the view offset changes.
    private var _selAnchor: (line: Int, col: Int)? = nil
    private var _selHead: (line: Int, col: Int)? = nil
    /// True while a selection drag is in flight (primary button held).
    private var _selecting = false

    init(session: TerminalSession) {
        self.session = session
        super.init()
    }

    override func initState() {
        super.initState()
        TerminalFontLoader.register()
        _measureCell()

        // Several views over one session is out of scope (see the plan), but
        // several SESSIONS in one app is exactly the point — chain rather
        // than overwrite so a pane mounting later cannot silently take the
        // repaint signal away from the pane already running.
        session.onActivity = { [weak self] in self?._scheduleRepaint() }
        session.activityOwner = self

        let (cols, rows) = _gridSize(for: _viewLogicalSize())
        _lock.lock()
        if cols != emulator.cols || rows != emulator.rows {
            emulator.resize(cols: cols, rows: rows)
        }
        _lock.unlock()
        session.resizeProcess(cols: cols, rows: rows)

        focusNode.onKeyData = { [weak self] keyData in
            return self?._handleKey(keyData) ?? false
        }
        focusNode.onFocusChange = { [weak self] _ in
            self?.setState {}
        }
        if w.autofocus { focusNode.requestFocus() }
    }

    override func dispose() {
        // Only if this view is still the owner: a remount installs the new
        // view's hook first, and clearing it here would leave the pane
        // running but permanently unpainted (see TerminalSession.activityOwner).
        if session.activityOwner === self {
            session.onActivity = nil
            session.activityOwner = nil
        }
        #if os(Linux)
        if _sentImeCaret {
            GpuDmaBufRenderer.current?.sendCaret(
                owner: self, x: 0, y: 0, width: 0, height: 0, visible: false)
        }
        #endif
        focusNode.dispose()
        super.dispose()
    }

    /// Shortest gap between rebuilds while output is streaming (~60/s).
    ///
    /// Coalescing alone was not enough. It collapses the requests outstanding
    /// at any instant, but during a flood the main queue drains far faster
    /// than the display refreshes, so each PTY chunk still got its own full
    /// rebuild of every visible row — work thrown away before anyone saw it.
    /// A 24-bit-colour dump spent 15.5 CPU-seconds over 6.2 wall seconds,
    /// i.e. ~2.5 cores, most of it rebuilding frames nobody sees.
    private static let minRepaintInterval: Double = 1.0 / 60.0
    /// Monotonic (DispatchTime) stamp of the last rebuild, in seconds.
    private var _lastRepaint: Double = 0

    private static func _now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    /// Diagnostic only (see test/bench/core/README.md): suppress all repaints
    /// to split parse cost from render cost in live runs. Not a shipping knob.
    private static let _benchNoRepaint =
        ProcessInfo.processInfo.environment["STARLING_BENCH_NOREPAINT"] != nil

    private func _scheduleRepaint() {
        if Self._benchNoRepaint { return }
        _lock.lock()
        let alreadyPending = _updatePending
        _updatePending = true
        let last = _lastRepaint
        _lock.unlock()
        guard !alreadyPending else { return }

        // Always go through the queue, but not before the frame is due. The
        // pending flag guarantees the LAST chunk still gets a rebuild, so
        // output that stops mid-frame is never left undrawn — it just lands up
        // to one frame later.
        let delay = max(0, (last + Self.minRepaintInterval) - Self._now())
        let work: @Sendable () -> Void = { [weak self] in
            guard let self = self else { return }
            self._lock.lock()
            self._updatePending = false
            self._lastRepaint = Self._now()
            self._lock.unlock()
            self.setState {}
        }
        if delay <= 0 {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    // MARK: - Input

    private func _handleKey(_ keyData: KeyData) -> Bool {
        // The app around us gets first refusal — see TerminalView.keyFilter.
        // Before the modifier tracking, so a chord built from modifiers is
        // not half-processed on the way past.
        if let filter = w.keyFilter, filter(keyData) { return true }

        // Track Shift/Ctrl for scrollback paging and copy/paste chords.
        if keyData.logical == 0xFFE1 || keyData.logical == 0xFFE2 {
            _shiftDown = (keyData.type == .down || keyData.type == .repeat)
            return false
        }
        if keyData.logical == 0xFFE3 || keyData.logical == 0xFFE4 {
            _ctrlDown = (keyData.type == .down || keyData.type == .repeat)
            return false
        }
        guard keyData.type == .down || keyData.type == .repeat else { return false }

        // Ctrl+Shift+C / Ctrl+Shift+V — copy selection / paste clipboard.
        // Handled before the view-snap so copying while scrolled back works.
        if _ctrlDown && _shiftDown {
            if keyData.logical == 0x43 || keyData.logical == 0x63 {  // C/c
                _copySelection()
                return true
            }
            if keyData.logical == 0x56 || keyData.logical == 0x76 {  // V/v
                _paste()
                return true
            }
        }

        // Shift+PageUp / Shift+PageDown page through scrollback.
        if _shiftDown && (keyData.logical == 0xFF55 || keyData.logical == 0xFF56) {
            _lock.lock()
            let page = max(1, emulator.rows - 1)
            let limit = emulator.scrollbackCount
            if keyData.logical == 0xFF55 {
                _viewOffset = min(_viewOffset + page, limit)
            } else {
                _viewOffset = max(_viewOffset - page, 0)
            }
            _lock.unlock()
            setState {}
            return true
        }

        // Any other key snaps the view back to the live screen and drops
        // the selection.
        if _viewOffset != 0 || _selAnchor != nil {
            _viewOffset = 0
            _selAnchor = nil
            _selHead = nil
            setState {}
        }

        if _exited {
            if w.restartOnEnter, keyData.logical == 0xFF0D {  // Enter — restart
                _lock.lock()
                let (cols, rows) = (emulator.cols, emulator.rows)
                emulator.resize(cols: cols, rows: rows)
                _lock.unlock()
                session.restart()
                setState {}
            }
            return true
        }

        _lock.lock()
        let appCursor = emulator.applicationCursorKeys
        _lock.unlock()

        if let bytes = TerminalInput.bytes(for: keyData, appCursor: appCursor) {
            session.write(bytes)
            return true
        }
        return false
    }

    /// Scroll by whole lines, from a wheel tick or an accumulated pan.
    ///
    /// `lines` > 0 walks BACK through history.
    private func _scrollBy(lines: Int, at position: Offset) {
        _lock.lock()
        let limit = emulator.scrollbackCount
        let alt = emulator.altActive
        let appCursor = emulator.applicationCursorKeys
        let reportMouse = emulator.mouseTracking && emulator.mouseSgr
        _lock.unlock()

        // The app asked for mouse events, so give it the wheel and let it
        // decide what scrolling means. This is the only thing that scrolls
        // Claude Code: fed arrow keys it answers "scroll wheel is sending
        // arrow keys", because it is waiting for button 64 and 65 here.
        if reportMouse {
            let cell = _cellAt(position)
            _lock.lock()
            let base = emulator.scrollbackCount
                - min(_viewOffset, emulator.scrollbackCount)
            _lock.unlock()
            // SGR is 1-based and screen-relative, so undo _cellAt's scrollback
            // base — a wheel report is about where the pointer is on screen,
            // not which history line that is.
            let col = cell.col + 1
            let row = (cell.line - base) + 1
            // Positive `lines` is a wheel-up — SGR button 64. Getting this
            // backwards sends "down" to an app already pinned at the bottom,
            // which looks exactly like the wheel being ignored.
            let button = lines > 0 ? 64 : 65
            let ticks = min(abs(lines), 10)
            var out = ""
            for _ in 0..<ticks { out += "\u{1B}[<\(button);\(col);\(row)M" }
            session.write(out)
            return
        }

        // A full-screen app owns the screen, and the scrollback under it
        // belongs to the PRIMARY buffer — the shell's output from before the
        // app started. Scrolling into that replaces the app on screen with
        // stale text, which reads as "scrolling is broken" rather than "you
        // are looking at the wrong buffer".
        //
        // So do what xterm's alternateScroll does: turn the wheel into cursor
        // keys and let the application scroll itself. Three lines a tick is
        // the convention every TUI is tuned for.
        if alt {
            let up = lines > 0
            let key = appCursor ? (up ? "\u{1B}OA" : "\u{1B}OB")
                                : (up ? "\u{1B}[A" : "\u{1B}[B")
            session.write(String(repeating: key, count: min(abs(lines), 10) * 3))
            return
        }

        let target = max(0, min(_viewOffset + lines, limit))
        if target != _viewOffset {
            setState { _viewOffset = target }
        }
    }

    // MARK: - Selection & clipboard

    private func _ordered(_ a: (line: Int, col: Int), _ b: (line: Int, col: Int))
        -> (start: (line: Int, col: Int), end: (line: Int, col: Int)) {
        if a.line < b.line || (a.line == b.line && a.col <= b.col) {
            return (a, b)
        }
        return (b, a)
    }

    /// The buffer cell under a window-content position, honoring the
    /// current scrollback view offset.
    private func _cellAt(_ pos: Offset) -> (line: Int, col: Int) {
        _lock.lock()
        let base = emulator.scrollbackCount - min(_viewOffset, emulator.scrollbackCount)
        let rows = emulator.rows
        let cols = emulator.cols
        _lock.unlock()
        let row = max(0, min(rows - 1, Int((pos.dy - padding) / cellH)))
        let col = max(0, min(cols - 1, Int((pos.dx - padding) / cellW)))
        return (base + row, col)
    }

    /// Serialize the selection (linear, terminal-style) onto the system
    /// clipboard. Trailing blanks are trimmed per line.
    private func _copySelection() {
        guard let a = _selAnchor, let h = _selHead else { return }
        let (start, end) = _ordered(a, h)
        _lock.lock()
        let all = emulator.scrollback + emulator.grid
        let cols = emulator.cols
        _lock.unlock()
        var lines: [String] = []
        for line in start.line...end.line {
            guard line >= 0, line < all.count else { continue }
            let row = all[line]
            let c0 = line == start.line ? start.col : 0
            let c1 = min(line == end.line ? end.col : cols - 1, row.count - 1)
            guard c1 >= c0, c0 < row.count else {
                lines.append("")
                continue
            }
            var s = String(row[c0...c1].map { $0.char })
            while s.hasSuffix(" ") { s.removeLast() }
            lines.append(s)
        }
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else { return }
        Clipboard.setData(ClipboardData(text: text))
    }

    /// Feed the clipboard to the PTY — bracketed when the application asked
    /// for it (mode 2004), LFs normalized to CRs like every terminal.
    ///
    /// Asynchronous: the selection may be owned by another process that has to
    /// be asked to write it. The completion lands on the UI thread.
    private func _paste() {
        guard !_exited else { return }
        Clipboard.getData(Clipboard.kTextPlain) { [weak self] data in
            guard let self = self, !self._exited,
                  let text = data?.text, !text.isEmpty else { return }
            let normalized = text
                .replacingOccurrences(of: "\r\n", with: "\r")
                .replacingOccurrences(of: "\n", with: "\r")
            self._lock.lock()
            let bracketed = self.emulator.bracketedPaste
            self._lock.unlock()
            if bracketed {
                self.session.write("\u{1B}[200~" + normalized + "\u{1B}[201~")
            } else {
                self.session.write(normalized)
            }
        }
    }

    // MARK: - Geometry

    private func _measureCell() {
        // Measure with the SAME style the rows are painted with — the fallback
        // list included. Measuring `family` alone means that if the primary
        // family ever fails to resolve, the painter answers with the platform's
        // default *proportional* font (an 'M' there is ~0.87em against a
        // monospace 0.60em) while the rows, which carry the fallback, still
        // render monospace. Nothing errors: the grid silently gets a cell 45%
        // too wide, so the block cursor is drawn oversized and walks further
        // right with every column.
        let painter = TextPainter(
            text: TextSpan(
                text: "MMMMMMMMMM",
                style: TextStyle(
                    fontSize: font.size,
                    fontFamily: font.family,
                    fontFamilyFallback: _fontFallback
                )
            ),
            textDirection: .ltr
        )
        painter.layout()
        if painter.width > 0 {
            cellW = painter.width / 10.0
        }
        if painter.height > 0 {
            cellH = painter.height
        }
        // Bench knob (see test/bench/core/README.md): force the cell width.
        // Two terminals given the same font at the same size can still land
        // different grids because their font stacks round the advance
        // differently (freetype hints Roboto Mono 13px to 8.0; our shaper
        // keeps the fractional 7.8). Glyphs keep their natural advance; the
        // difference is made up with letterSpacing so runs stay on the
        // forced grid. Not a shipping knob.
        if let v = ProcessInfo.processInfo.environment["STARLING_CELL_W"],
           let forced = Double(v), forced > 0, cellW > 0 {
            _cellSpacing = forced - cellW
            cellW = forced
        }
    }

    private func _viewLogicalSize() -> Size {
        if let given = w.size { return given }
        if let view = PlatformDispatcher.instance.implicitView {
            let dpr = view.devicePixelRatio
            let phys = view.physicalSize
            if phys.width > 0 && phys.height > 0 && dpr > 0 {
                return Size(phys.width / dpr, phys.height / dpr)
            }
        }
        return Size(820, 560)
    }

    private func _gridSize(for size: Size) -> (cols: Int, rows: Int) {
        let cols = Int((size.width - padding * 2) / cellW)
        let rows = Int((size.height - padding * 2) / cellH)
        return (max(4, cols), max(2, rows))
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        // React to window resizes: recompute the grid from the view metrics.
        let (cols, rows) = _gridSize(for: _viewLogicalSize())
        _lock.lock()
        if cols != emulator.cols || rows != emulator.rows {
            emulator.resize(cols: cols, rows: rows)
            session.resizeProcess(cols: cols, rows: rows)
        }
        // Snapshot under the lock (arrays are CoW — cheap and safe).
        let viewOffset = min(_viewOffset, emulator.scrollbackCount)
        let grid = emulator.visibleLines(offset: viewOffset)
        let cursorRow = emulator.cursorRow
        let cursorCol = emulator.cursorCol
        let showCursor = emulator.cursorVisible && focusNode.hasFocus
            && !_exited && viewOffset == 0
        let sbCount = emulator.scrollbackCount
        let gridCols = emulator.cols
        _lock.unlock()

        var lines: [Widget] = []
        lines.reserveCapacity(grid.count)
        for line in grid {
            lines.append(_rowWidget(line))
        }

        var layers: [Widget] = [
            Padding(
                padding: EdgeInsets(all: padding),
                child: Column(
                    crossAxisAlignment: .start,
                    children: lines
                )
            )
        ]

        // Selection highlight: translucent rows above the text (terminal
        // style, linear range in buffer coordinates).
        if let a = _selAnchor, let h = _selHead {
            let (selStart, selEnd) = _ordered(a, h)
            let base = sbCount - viewOffset
            for r in 0 ..< grid.count {
                let abs = base + r
                guard abs >= selStart.line, abs <= selEnd.line else { continue }
                let c0 = abs == selStart.line ? selStart.col : 0
                let c1 = abs == selEnd.line ? selEnd.col : gridCols - 1
                guard c1 >= c0 else { continue }
                layers.append(Positioned(
                    left: padding + Double(c0) * cellW,
                    top: padding + Double(r) * cellH,
                    child: SizedBox(
                        width: Double(c1 - c0 + 1) * cellW,
                        height: cellH,
                        child: DecoratedBox(
                            decoration: BoxDecoration(color: Color(Int(theme.selection)))
                        )
                    )
                ))
            }
        }

        #if os(Linux)
        // Report the cursor cell to the shell — anchors the IME candidate
        // panel next to the terminal cursor. Only while the terminal owns
        // focus (one shared anchor per app); one-shot clear on focus loss.
        if focusNode.hasFocus {
            GpuDmaBufRenderer.current?.sendCaret(
                owner: self,
                x: padding + Double(cursorCol) * cellW,
                y: padding + Double(cursorRow) * cellH,
                width: cellW, height: cellH,
                visible: showCursor)
            _sentImeCaret = true
        } else if _sentImeCaret {
            _sentImeCaret = false
            GpuDmaBufRenderer.current?.sendCaret(
                owner: self, x: 0, y: 0, width: 0, height: 0, visible: false)
        }
        #endif

        // Block cursor: a translucent overlay so it is visible regardless of
        // what the text shaper does with trailing spaces.
        if showCursor {
            layers.append(
                Positioned(
                    left: padding + Double(cursorCol) * cellW,
                    top: padding + Double(cursorRow) * cellH,
                    child: SizedBox(
                        width: cellW,
                        height: cellH,
                        child: DecoratedBox(
                            decoration: BoxDecoration(color: Color(Int(theme.cursorOverlay)))
                        )
                    )
                )
            )
        }

        // Pointer: focus on click, drag-select over the grid, wheel scrolls
        // through scrollback (any key press snaps back to live).
        //
        // Directionality is supplied HERE, not required of the embedder: a
        // terminal is an LTR cell grid by construction (the painter indexes
        // columns left to right), and a bare TerminalView under a host with
        // no ambient direction otherwise dies in RenderStack._resolve — the
        // framework's oldest trap, which a reusable widget should absorb.
        return Directionality(textDirection: .ltr, child: Listener(
            onPointerDown: { [self] event in
                focusNode.requestFocus()
                guard event.buttons & 1 != 0 else { return }
                let cell = _cellAt(event.localPosition)
                setState {
                    _selecting = true
                    _selAnchor = cell
                    _selHead = cell
                }
            },
            onPointerMove: { [self] event in
                guard _selecting else { return }
                let cell = _cellAt(event.localPosition)
                if _selHead == nil || cell != _selHead! {
                    setState { _selHead = cell }
                }
            },
            onPointerUp: { [self] _ in
                guard _selecting else { return }
                _selecting = false
                // A click without a drag clears the selection.
                if let a = _selAnchor, let h = _selHead, a == h {
                    setState {
                        _selAnchor = nil
                        _selHead = nil
                    }
                }
            },
            // A touchpad does not arrive here. The GTK embedder splits the two
            // apart (fl_scrolling_manager.cc): a wheel becomes a scroll SIGNAL,
            // a touchpad becomes pan/zoom events — so a view that handles only
            // the signal scrolls for a mouse and sits there for two fingers.
            onPointerPanZoomStart: { [self] _ in _panLines = 0 },
            onPointerPanZoomUpdate: { [self] event in
                guard let pan = event as? PointerPanZoomUpdateEvent else { return }
                // Fingers deliver a few pixels per event, so whole lines have
                // to accumulate; dropping the remainder would swallow a slow
                // scroll entirely.
                _panLines += -pan.panDelta.dy / cellH
                let whole = _panLines.rounded(.towardZero)
                guard whole != 0 else { return }
                _panLines -= whole
                _scrollBy(lines: Int(whole), at: event.localPosition)
            },
            onPointerPanZoomEnd: { [self] _ in _panLines = 0 },
            onPointerSignal: { [self] event in
                guard let scroll = event as? PointerScrollEvent else { return }
                let dl = -scroll.scrollDelta.dy / cellH
                var lines = Int(dl.rounded(.towardZero))
                if lines == 0 { lines = dl > 0 ? 1 : (dl < 0 ? -1 : 0) }
                guard lines != 0 else { return }
                _scrollBy(lines: lines, at: scroll.localPosition)
            },
            child: ColoredBox(
                color: Color(Int(theme.background)),
                child: Stack(children: layers)
            )
        ))
    }

    // MARK: - Row rendering

    /// Renders one grid line as a single rich-text row of merged style runs.
    private func _rowWidget(_ line: [TermCell]) -> Widget {
        // Trim trailing blank cells (default bg, space).
        var end = line.count
        while end > 0 {
            let cell = line[end - 1]
            if cell.scalar == 32 && cell.bg == 0 { end -= 1 } else { break }
        }

        if end == 0 {
            return SizedBox(width: 1, height: cellH)
        }

        // Background-colour erase: a run of coloured spaces that ENDS the line
        // has to be drawn as a box, not as text.
        //
        // `ESC[41m` then `ESC[K` fills the rest of the row with red-background
        // spaces, and the cells are set correctly — but text layout excludes
        // trailing whitespace from the painted line, so the span's background
        // never appeared. The same run rendered fine with any glyph after it,
        // which is what gave the cause away: red showed mid-line, and vanished
        // at end of line.
        //
        // Split that tail off and paint it as a sized ColoredBox. The head Text
        // is given an explicit width too, so the boundary is pinned to the cell
        // grid rather than to whatever width the text engine decides a string
        // with trailing spaces has.
        var tailStart = end
        let tailBg = line[end - 1].bg
        if tailBg != 0 {
            var i = end
            while i > 0 {
                let cell = line[i - 1]
                // Same colour, no attributes (an underlined space still has to
                // be drawn as text so the line shows), and a space.
                guard cell.scalar == 32, cell.bg == tailBg, cell.attrs.isEmpty
                else { break }
                i -= 1
            }
            tailStart = i
        }
        let tailWidth = Double(end - tailStart) * cellW
        if tailStart == 0 {
            return SizedBox(width: tailWidth, height: cellH,
                            child: ColoredBox(color: Color(Int(tailBg))))
        }
        let headEnd = tailStart

        var spans: [InlineSpan] = []
        var runText = ""
        var runStyle: _RunKey? = nil

        func flush() {
            guard let style = runStyle, !runText.isEmpty else { return }
            spans.append(TextSpan(text: runText, style: _textStyle(style)))
            runText = ""
        }

        for c in 0 ..< headEnd {
            var cell = c < line.count ? line[c] : .blank
            // A continuation cell is the second column of a wide glyph: the
            // lead already contributed the character, and the lead's span
            // covers this column. Appending its scalar (0) would put a NUL
            // into the shaped run.
            if cell.attrs.contains(.wideCont) { continue }
            let wide = cell.attrs.contains(.wideLead)
            cell.attrs.remove(.wideLead)
            // What the glyph costs against what the grid gave it. Everything
            // outside the primary family arrives at its OWN advance, and the
            // run is placed by the shaper, so anything but an exact match
            // walks the rest of the row off its columns — see _gridSpacing.
            //
            // A cluster is the only case that needs its text up front. The
            // rest append a Character straight into the run: building a
            // `String` per cell to hand to the cache put an allocation in the
            // hottest loop the row painter has.
            let cluster: String? = cell.scalar > 0x10FFFF
                ? emulator.cellText(cell.scalar) : nil
            let bold = cell.attrs.contains(.bold)
            let columns = wide ? 2 : 1
            let spacing: Double
            if let cluster = cluster {
                spacing = _clusterSpacing(cluster, columns: columns, bold: bold)
            } else if wide || cell.scalar > 0x7F {
                spacing = _gridSpacing(cell.scalar, columns: columns, bold: bold)
            } else {
                spacing = _cellSpacing
            }
            if cell.attrs.contains(.reverse) {
                let fg = cell.bg == 0 ? theme.reverseBackground : cell.bg
                let bg = cell.fg == 0 ? theme.defaultForeground : cell.fg
                cell.fg = fg
                cell.bg = bg
                cell.attrs.remove(.reverse)
            }
            let key = _RunKey(fg: cell.fg, bg: cell.bg, attrs: cell.attrs,
                              spacing: spacing)
            if runStyle == nil {
                runStyle = key
            } else if runStyle! != key {
                flush()
                runStyle = key
            }
            if let cluster = cluster { runText += cluster }
            else { runText.append(cell.char) }
        }
        flush()

        // `softWrap: false` is load bearing, not a tidy-up. With soft wrap on,
        // the row is laid out against the width it is given — and the coloured
        // tail below pins that to exactly `headEnd * cellW`. A shaped run is
        // not bit-for-bit `n * cellW`: cellW is one tenth of a measured
        // "MMMMMMMMMM", and any character that resolves through the fallback
        // family (DejaVu's advance is 0.6021 em against Roboto Mono's 0.6001 —
        // Claude Code's ❯ prompt is one) makes the line a fraction of a pixel
        // wider than its box. `maxLines: 1` then breaks at the last soft break
        // that fits and drops everything after it, so a sub-pixel overflow eats
        // the row's LAST WORD — silently, with no overflow stripe, and only on
        // rows that have a background-coloured tail, because those are the only
        // ones pinned to cell width. That is exactly Claude Code's own
        // full-width prompt echo, which lost a word per line.
        //
        // With soft wrap off the paragraph lays out against infinite width, so
        // it never breaks, and RenderParagraph clips it to the box — which is
        // what a terminal does with a cell that does not fit.
        let head = SizedBox(
            height: cellH,
            child: Text(
                rich: TextSpan(children: spans),
                softWrap: false,
                maxLines: 1
            )
        )
        guard tailWidth > 0 else { return head }
        // The head is pinned to its cell width so the coloured tail starts
        // exactly on the grid, whatever the text engine makes of a run that
        // ends in spaces.
        return SizedBox(height: cellH, child: Row(children: [
            SizedBox(width: Double(headEnd) * cellW, height: cellH, child: head),
            SizedBox(width: tailWidth, height: cellH,
                     child: ColoredBox(color: Color(Int(tailBg)))),
        ]))
    }

    /// One run of cells that can share a single shaped span: same colours,
    /// same attributes, and the same grid correction.
    ///
    /// Doubles as the style cache's key. `TextStyle` construction and copy
    /// showed up in a profile of colour-heavy output (its value-witness copy
    /// alone was 2.4%), and a row of per-cell colours asks for one style per
    /// cell — but the same handful of styles repeat endlessly for any content
    /// using a palette rather than 24-bit colour.
    private struct _RunKey: Hashable {
        let fg: UInt32, bg: UInt32, attrsRaw: UInt8, spacing: Double
        var attrs: CellAttrs { CellAttrs(rawValue: attrsRaw) }
        init(fg: UInt32, bg: UInt32, attrs: CellAttrs, spacing: Double) {
            self.fg = fg
            self.bg = bg
            self.attrsRaw = attrs.rawValue
            self.spacing = spacing
        }
    }
    private var _styleCache: [_RunKey: TextStyle] = [:]

    private func _textStyle(_ key: _RunKey) -> TextStyle {
        if let hit = _styleCache[key] { return hit }
        let made = _makeTextStyle(key)
        // Truecolor content can mint a distinct style per cell, so the cache
        // must not grow without bound. Drop it wholesale rather than tracking
        // ages — the working set for palette content is tiny, so it refills at
        // once, and for truecolor the cache was not paying anyway.
        if _styleCache.count > 4096 { _styleCache.removeAll(keepingCapacity: true) }
        _styleCache[key] = made
        return made
    }

    /// The advance a glyph needs ON TOP of its own so the cell after it starts
    /// on its column — `letterSpacing`, measured rather than assumed.
    ///
    /// The row is one shaped paragraph, so the shaper places every glyph by
    /// the advance of whatever font it resolved in, and only the primary
    /// family is on our grid. A CJK glyph comes back from CoreText's Hiragino
    /// at 1 em, which is 1.63 cells at 13 pt — not the 2 the emulator
    /// reserved — so `你好世界|` put its pipe in column 6.5 and every column
    /// after a CJK character was wrong. The same is true, in miniature, of
    /// every fallback glyph: DejaVu's 0.6021 em against Roboto Mono's 0.6001
    /// is a third of a pixel per box-drawing character.
    ///
    /// Measured once per (glyph, weight) and cached — the working set of a
    /// session is small, and the correction lands in the run key, so cells
    /// needing different corrections simply do not share a span.
    /// Keyed by scalar, not by the string: this is looked up for EVERY
    /// non-ASCII cell, and hashing a `String` there cost 05_unicode 12%
    /// (0.331 -> 0.371 s). Clusters, which have no single scalar, keep the
    /// string key — they are rare enough to pay for it.
    private struct _MetricKey: Hashable { let scalar: UInt32, bold: Bool }
    private var _spacingCache: [_MetricKey: Double] = [:]
    private struct _ClusterKey: Hashable { let text: String, bold: Bool }
    private var _clusterSpacingCache: [_ClusterKey: Double] = [:]
    /// Diagnostic: dump every glyph measurement, which is how a glyph that
    /// resolves to a font but paints nothing is told apart from one no font
    /// carries at all (the first measures its advance, the second measures 0).
    private static let _debugMetrics =
        ProcessInfo.processInfo.environment["STARLING_TERM_METRICS"] != nil

    /// The correction for a single scalar. The string it measures is built on
    /// a cache MISS only — this is called for every non-ASCII cell.
    private func _gridSpacing(_ scalar: UInt32, columns: Int, bold: Bool) -> Double {
        let key = _MetricKey(scalar: scalar, bold: bold)
        if let hit = _spacingCache[key] { return hit }
        let text = String(Character(UnicodeScalar(scalar) ?? " "))
        let spacing = _measureSpacing(text, columns: columns, bold: bold)
        if _spacingCache.count > 8192 { _spacingCache.removeAll(keepingCapacity: true) }
        _spacingCache[key] = spacing
        return spacing
    }

    /// The correction for a grapheme cluster, which has no single scalar to
    /// key on. Rare enough to pay for hashing the string.
    private func _clusterSpacing(_ text: String, columns: Int, bold: Bool) -> Double {
        let key = _ClusterKey(text: text, bold: bold)
        if let hit = _clusterSpacingCache[key] { return hit }
        let spacing = _measureSpacing(text, columns: columns, bold: bold)
        if _clusterSpacingCache.count > 1024 {
            _clusterSpacingCache.removeAll(keepingCapacity: true)
        }
        _clusterSpacingCache[key] = spacing
        return spacing
    }

    private func _measureSpacing(_ text: String, columns: Int, bold: Bool) -> Double {
        let painter = TextPainter(
            text: TextSpan(
                text: text,
                style: TextStyle(
                    fontSize: font.size,
                    fontWeight: bold ? .w700 : .normal,
                    fontFamily: font.family,
                    fontFamilyFallback: _fontFallback
                )
            ),
            textDirection: .ltr
        )
        painter.layout()
        // A glyph no loaded family carries measures zero: leave the cell alone
        // rather than inventing a correction for something that will not paint.
        let spacing = painter.width > 0
            ? Double(columns) * cellW - painter.width
            : _cellSpacing
        if Self._debugMetrics {
            let scalars = text.unicodeScalars.map { String($0.value, radix: 16) }
                .joined(separator: "+")
            let line = "[term] metric U+\(scalars) cols=\(columns)"
                + " measured=\(painter.width) cell=\(cellW) spacing=\(spacing)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
        return spacing
    }

    private func _makeTextStyle(_ style: _RunKey) -> TextStyle {
        var fg = style.fg == 0 ? theme.defaultForeground : style.fg
        if style.attrs.contains(.dim) {
            // Halve the brightness for dim text.
            let r = ((fg >> 16) & 0xFF) / 2
            let g = ((fg >> 8) & 0xFF) / 2
            let b = (fg & 0xFF) / 2
            fg = 0xFF00_0000 | (r << 16) | (g << 8) | b
        }
        return TextStyle(
            color: Color(Int(fg)),
            backgroundColor: style.bg == 0 ? nil : Color(Int(style.bg)),
            fontSize: font.size,
            fontWeight: style.attrs.contains(.bold) ? .w700 : .normal,
            fontStyle: style.attrs.contains(.italic) ? .italic : .normal,
            letterSpacing: style.spacing == 0 ? nil : style.spacing,
            decoration: style.attrs.contains(.underline) ? .underline : nil,
            fontFamily: font.family,
            fontFamilyFallback: _fontFallback
        )
    }
}
