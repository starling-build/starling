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

    // The default background is deliberately the same value as the terminal
    // app's `TabChrome.surface`: the app paints pane chrome around this grid,
    // and any drift between the two shows as a hairline of the wrong colour
    // at every pane edge. The alpha is what lets the desktop composite a
    // wallpaper behind the window, and every colour here that sits behind
    // text must keep it.
    public init(background: UInt32 = 0xD9171922,
                defaultForeground: UInt32 = 0xFFD5D9E2,
                cursorOverlay: UInt32 = 0x99D5D9E2,
                selection: UInt32 = 0x408AA0FF) {
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
    /// when present — by path (see register()), so the ~30 MB of font data
    /// is page cache, not per-app heap.
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
    /// instead would still be wasteful — Apple Color Emoji is 192 MB that
    /// CoreText already has resident systemwide, and even mmap'd it would be
    /// re-parsed per app — while a family name in the fallback list costs
    /// nothing until a cell needs it.
    private static let systemFamilyNames = [
        "Apple Color Emoji",     // emoji; nothing else carries them
        "Hiragino Sans GB",      // Chinese
        "Hiragino Kaku Gothic ProN",  // Japanese kana
        "Apple SD Gothic Neo",   // Korean
    ]
    private nonisolated(unsafe) static var _registered = false

    /// Where the bundled fonts are, searched rather than assumed.
    ///
    /// **Deliberately not `Bundle.module`.** SwiftPM generates that accessor
    /// with exactly two candidates: `Bundle.main.bundleURL/<name>.bundle`,
    /// and an ABSOLUTE PATH INTO THE BUILD DIRECTORY THAT PRODUCED THE BINARY.
    /// Inside a macOS `.app` the first misses — `Bundle.main.bundleURL` is the
    /// `.app` itself and the resource bundle is staged under
    /// `Contents/Resources/`, where every other app resource belongs — and the
    /// second HITS on the machine that did the build, because the build
    /// directory is still sitting there. So `Bundle.module` resolves for the
    /// developer and fatals for everybody else:
    ///
    ///     Flutter/resource_bundle_accessor.swift:12
    ///     fatal error: could not load resource bundle
    ///
    /// on the first font load, which is startup. A shipped `.app` did exactly
    /// that, and no amount of testing on the build machine could have shown
    /// it — the giveaway is `strings` on the executable finding somebody
    /// else's home directory.
    ///
    /// The candidates below are every place the bundle legitimately sits:
    /// `Contents/Resources` for a macOS app, the executable's own directory
    /// for the Linux and Windows layouts (where SwiftPM's `bundleURL` guess is
    /// right), and the build directory last, so a `swift run` from a checkout
    /// still works.
    private static func _fontBundle(_ name: String) -> Bundle? {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        roots.append(Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources"))
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            roots.append(exe)
        }
        // BOTH SUFFIXES, and this is not belt-and-braces. SwiftPM names the
        // staged directory `<package>_<target>.bundle` on Darwin and
        // `<package>_<target>.resources` everywhere else; `Bundle.module`'s
        // generated accessor is `#if os(macOS)`-d for exactly that reason.
        // Searching only for `.bundle` therefore finds nothing on Linux and
        // Windows -- and because this function returns nil rather than
        // trapping, the terminal comes up drawing with the system's
        // proportional font on monospace cell metrics instead of failing. It
        // looks like a rendering bug, not a missing file. That shipped: the
        // release that replaced `Bundle.module` here fixed macOS and broke the
        // other two, and was caught by looking at a screenshot.
        for root in roots {
            for suffix in ["bundle", "resources"] {
                let candidate = root.appendingPathComponent("\(name).\(suffix)")
                if let bundle = Bundle(url: candidate) { return bundle }
            }
        }
        return nil
    }

    /// The framework's own resource bundle, or nil if this build has none
    /// beside it. Nil rather than a crash: a terminal with the system's fonts
    /// and none of ours is degraded, and a terminal that refuses to start is
    /// not usable at all.
    private static let _resources: Bundle? = _fontBundle("FlutterSwift_Flutter")

    @discardableResult
    public static func register() -> Bool {
        guard !_registered else { return true }
        var ok = false
        var symbolsLoaded = false
        // By path, not by bytes: LoadFontFromFile mmaps, so the font stays
        // file-backed — shared across every app that loads it and evictable —
        // where LoadFontFromList has to copy the buffer into the app's heap.
        // Measured on the terminal, the by-bytes path held the CJK fallback
        // resident ~2.5x over (49 MB of a 234 MB idle footprint).
        for (name, family) in [("RobotoMono-Regular", family),
                               ("RobotoMono-Bold", family),
                               ("DejaVuSansMono-Regular", fallbackFamily),
                               ("DejaVuSansMono-Bold", fallbackFamily),
                               ("DejaVuSans", symbolFallbackFamily)] {
            guard let url = _resources?.url(forResource: name, withExtension: "ttf")
            else { continue }
            let success = flutter.swift_bridge.LoadFontFromFile(url.path, family)
            ok = ok || success
            if family == symbolFallbackFamily { symbolsLoaded = success }
        }
        #if os(macOS)
        fallback.append(contentsOf: systemFamilyNames)
        #else
        for (path, family) in systemFallbacks {
            if flutter.swift_bridge.LoadFontFromFile(path, family) {
                fallback.append(family)
            }
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
    /// Size the font so exactly this many columns fit the width, instead of
    /// taking `font.size` as given. `font.size` then only sets the scale the
    /// advance is measured at, and the grid is always a whole number of
    /// columns wide with no leftover strip.
    ///
    /// This is what a terminal on a PHONE needs. A desktop picks the font and
    /// gets whatever column count the window allows, which is the right way
    /// round when the window is 1100pt wide. At 402pt it is not: the desktop's
    /// 13pt default yields **49 columns**, so every line of ordinary output —
    /// `ls -l`, a git log, anything laid out for 80 — wraps and leaves
    /// fragments stranded on the next row. Sizing from the column count
    /// inverts the dependency and 80 columns fit at ~8pt, which sounds tiny
    /// and is not: a phone is held at about half a laptop's viewing distance,
    /// so 8pt there subtends roughly what 13pt does on a laptop.
    ///
    /// It also makes rotation behave. With a fixed font size, turning the
    /// phone re-wraps every line to a new width; with a fixed column count the
    /// text simply grows, and the grid the far end is looking at never moves.
    let fitColumns: Int?
    /// Reports the column count after a pinch, so the app can remember it.
    let onFitColumnsChanged: ((Int) -> Void)?
    /// Pinch to change `fitColumns` — the touch equivalent of a font-size
    /// setting. Off by default: it costs a gesture recognizer, and a mouse
    /// has no pinch.
    let pinchToZoom: Bool

    public init(session: TerminalSession,
                theme: TerminalTheme = .starlingDark,
                font: TerminalFont = TerminalFont(),
                padding: Double = 8,
                size: Size? = nil,
                autofocus: Bool = true,
                restartOnEnter: Bool = true,
                fitColumns: Int? = nil,
                onFitColumnsChanged: ((Int) -> Void)? = nil,
                pinchToZoom: Bool = false,
                keyFilter: ((KeyData) -> Bool)? = nil) {
        self.session = session
        self.theme = theme
        self.font = font
        self.padding = padding
        self.size = size
        self.autofocus = autofocus
        self.restartOnEnter = restartOnEnter
        self.fitColumns = fitColumns
        self.onFitColumnsChanged = onFitColumnsChanged
        self.pinchToZoom = pinchToZoom
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

    /// The font glyphs are actually SHAPED with: the widget's font carries the
    /// family, the fit decides the size. `w.font.size` and `_fontSize` are the
    /// same number everywhere except a fitted grid (`fitColumns`), where the
    /// size follows the width — and there, shaping with `w.font` draws 13pt
    /// glyphs into ~8pt cells. On the Text path that was understood from the
    /// start (`_makeTextStyle` uses `_fontSize`); the painter and the atlas
    /// arrived from a tree with no fit feature, shaped with `font.size`, and
    /// on every fitted grid produced glyphs ~1.6x their cells: clipped tops in
    /// paragraph mode, and slot overflow in the atlas — each glyph spilling
    /// into its neighbour's slot, so the blit sampled fragments of both.
    private var _shapedFont: TerminalFont {
        TerminalFont(family: w.font.family, size: _fontSize, fallback: w.font.fallback)
    }

    private var _fontFallback: [String] { font.fallback ?? TerminalFontLoader.fallback }
    private var _lock: NSLock { session.lock }
    private var emulator: TerminalEmulator { session.emulator }
    private var _exited: Bool { session.processExited }

    private let focusNode = FocusNode(debugLabel: "Terminal")

    /// Monospace cell metrics, for the size in `_fontSize`.
    private var cellW: Double = 7.8
    private var cellH: Double = 17.0
    /// Extra per-glyph advance when STARLING_CELL_W forces the cell width
    /// away from the font's natural advance. 0 in normal operation.
    private var _cellSpacing: Double = 0

    /// The size the rows are actually painted at. Equal to `font.size` unless
    /// `fitColumns` is in play, when it is derived from the view's width.
    private var _fontSize: Double = 13
    /// Cell width per point of font size. The advance is exactly linear in
    /// size — measured, not assumed: 80 columns at 8pt come to 384.06pt both
    /// by multiplication and by laying out all 80 — so one measurement turns
    /// a column count into a font size by division.
    private var _advanceRatio: Double = 0.6
    /// The current column target, moved by pinch. nil when the widget did not
    /// ask to fit columns, and the font size is then the widget's own.
    private var _fitColumns: Int?
    /// The width `_fontSize` was fitted for, so a rotation or a pane resize
    /// re-fits and nothing else does.
    private var _fittedWidth: Double = 0
    /// Column count at the start of a pinch, which the gesture scales.
    private var _pinchColumns: Int?
    /// Pointers currently down. A second finger means a pinch, not a drag
    /// through the text, so the selection in flight has to be abandoned —
    /// otherwise zooming also sweeps a selection across the screen.
    private var _pointers = Set<Int>()
    /// "80 × 69", shown for a moment after the grid changes size. A pinch
    /// otherwise gives no feedback about the thing it is actually changing.
    private var _sizeHud: String?
    /// Invalidates a pending HUD dismissal when another pinch lands first.
    private var _hudGeneration = 0

    /// Coalesces reader-thread repaint requests.
    private var _updatePending = false

    /// Cursor blink phase: true = the overlay is drawn. The cursor blinks at
    /// rest, macOS Terminal style — held solid through keystrokes and output,
    /// and only ticking while the view is focused and the process alive.
    /// Main-queue only, like the rest of the view state.
    private var _blinkOn = true
    /// Invalidates pending blink ticks on focus loss, dispose, and restart.
    private var _blinkGeneration = 0
    /// Whether a tick is scheduled, so activity can revive a stopped loop.
    private var _blinkTicking = false
    /// Monotonic deadline before which the cursor stays solid: last
    /// keystroke/output plus one period.
    private var _blinkHeldSolidUntil: Double = 0
    /// macOS Terminal's cadence, near enough.
    private static let blinkPeriod: Double = 0.6

    /// Scrollback view offset in lines (0 = live screen). Shift+PageUp/Down,
    /// the mouse wheel, or a touchpad pan.
    private var _viewOffset = 0
    /// Fractional lines carried between touchpad pan events.
    private var _panLines: Double = 0

    /// A finger is not a mouse. A mouse selects from the down edge and
    /// scrolls with its wheel; a finger's drag IS the scroll — a phone has
    /// no other scroll input — so on touch the roles move: drag scrolls the
    /// scrollback, a long-press (finger held inside the slop) starts the
    /// selection, and a plain tap raises the soft keyboard. Mouse, trackpad
    /// and stylus keep the desktop behaviour above.
    private enum TouchPhase { case undecided, scrolling, selecting }
    /// The touch being tracked, nil when none — or when a second finger
    /// turned the gesture into a pinch and took it away.
    private var _touchPointer: Int?
    private var _touchPhase = TouchPhase.undecided
    /// Where the finger landed; movement past the slop decides scrolling.
    private var _touchStart = Offset.zero
    /// Last position: per-event scroll deltas, and where a fling anchors.
    private var _touchLast = Offset.zero
    /// Fractional lines carried between touch move events.
    private var _touchLines: Double = 0
    /// (monotonic seconds, y) samples inside the fling velocity window.
    private var _touchSamples: [(t: Double, y: Double)] = []
    /// Invalidates the pending long-press when the finger moves or lifts.
    private var _longPressGeneration = 0
    /// Invalidates fling ticks on a new touch, a keystroke, or dispose.
    private var _flingGeneration = 0
    /// Flutter's kTouchSlop and kLongPressTimeout.
    private static let touchSlop: Double = 18
    private static let longPressTimeout: Double = 0.5
    /// True while this terminal is the reported IME caret anchor.
    private var _sentImeCaret = false

    /// Shift state tracked from modifier key events (keysyms 0xFFE1/0xFFE2).
    private var _shiftDown = false
    /// Ctrl state (keysyms 0xFFE3/0xFFE4) — for Ctrl+Shift+C/V copy/paste.
    private var _ctrlDown = false
    /// Cmd state (Flutter logical ids 0x2_0000_0106/7, keysyms 0xFFE7/0xFFE8)
    /// — for the native Cmd+C/V/F chords on macOS.
    private var _metaDown = false

    /// Text selection, in ABSOLUTE buffer coordinates (line index into
    /// scrollback+grid, column) so it stays anchored to content while new
    /// output scrolls the screen or the view offset changes.
    private var _selAnchor: (line: Int, col: Int)? = nil
    private var _selHead: (line: Int, col: Int)? = nil
    /// True while a selection drag is in flight (primary button held).
    private var _selecting = false

    /// Find bar (Ctrl+Shift+F). Matches are in ABSOLUTE buffer coordinates —
    /// the selection's space — so they stay anchored to content while new
    /// output scrolls the screen.
    private var _searchActive = false
    private var _searchQuery = ""
    private var _searchMatches: [(line: Int, col: Int, len: Int)] = []
    private var _searchCurrent = 0

    init(session: TerminalSession) {
        self.session = session
        super.init()
    }

    override func initState() {
        super.initState()
        TerminalFontLoader.register()
        // The nominal size first: it establishes the advance ratio that turns
        // a column count into a size.
        _measureCell(size: font.size)
        _fitColumns = w.fitColumns
        _refit(width: _viewLogicalSize().width)

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
        focusNode.onFocusChange = { [weak self] focused in
            guard let self else { return }
            if focused { self._restartBlink() } else { self._stopBlink() }
            self.setState {}
        }
        if w.autofocus { focusNode.requestFocus() }
    }

    /// The cell metrics are measured, not derived, so a rebuild that changes
    /// the font has to re-measure — nothing else notices.
    ///
    /// Without this the state kept the metrics of whatever size it first saw
    /// while the rows were painted at the new one: rows spaced for 8pt with
    /// 13pt glyphs in them, so every row was clipped at the baseline and the
    /// grid ran off the right edge. It reads as a font-rendering fault rather
    /// than a stale measurement, because the text itself is perfectly formed.
    override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        guard let old = oldWidget as? TerminalView else { return }
        if old.font.size != w.font.size || old.font.family != w.font.family {
            _measureCell(size: w.font.size)
            _fittedWidth = 0
        }
        if old.fitColumns != w.fitColumns {
            _fitColumns = w.fitColumns
            _fittedWidth = 0
        }
    }

    override func dispose() {
        _stopBlink()
        _longPressGeneration += 1
        _flingGeneration += 1
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
            self._blinkActivity()
            self.setState {}
        }
        if delay <= 0 {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    // MARK: - Cursor blink

    /// A keystroke or output landed: hold the cursor solid for one period —
    /// it blinks only at rest — and revive the tick loop if it had stopped.
    /// Main queue only (key events, and _scheduleRepaint's main-queue work).
    private func _blinkActivity() {
        _blinkHeldSolidUntil = Self._now() + Self.blinkPeriod
        if !_blinkOn { _blinkOn = true; setState {} }
        if !_blinkTicking && focusNode.hasFocus { _restartBlink() }
    }

    private func _restartBlink() {
        _blinkGeneration += 1
        _blinkOn = true
        _blinkHeldSolidUntil = Self._now() + Self.blinkPeriod
        _scheduleBlinkTick(after: Self.blinkPeriod)
    }

    /// Leaves the phase solid, so whatever brings the cursor back draws it.
    private func _stopBlink() {
        _blinkGeneration += 1
        _blinkTicking = false
        _blinkOn = true
    }

    /// DispatchQueue + a generation token, never Foundation.Timer — Timer
    /// never fires on the DRM embedder.
    private func _scheduleBlinkTick(after delay: Double) {
        _blinkTicking = true
        let gen = _blinkGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, gen == self._blinkGeneration else { return }
            // No cursor on screen (unfocused, or the child exited): stop
            // rather than rebuild an idle pane every period. Focus return
            // and _blinkActivity restart the loop.
            guard self.focusNode.hasFocus, !self._exited else {
                self._blinkTicking = false
                self._blinkOn = true
                return
            }
            let now = Self._now()
            if now < self._blinkHeldSolidUntil {
                if !self._blinkOn { self._blinkOn = true; self.setState {} }
                self._scheduleBlinkTick(after: self._blinkHeldSolidUntil - now)
                return
            }
            self._blinkOn.toggle()
            self.setState {}
            self._scheduleBlinkTick(after: Self.blinkPeriod)
        }
    }

    // MARK: - Input

    private func _handleKey(_ keyData: KeyData) -> Bool {
        // The app around us gets first refusal — see TerminalView.keyFilter.
        // Before the modifier tracking, so a chord built from modifiers is
        // not half-processed on the way past.
        if let filter = w.keyFilter, filter(keyData) { return true }

        // Track Shift/Ctrl for scrollback paging, copy/paste chords, and
        // Ctrl+letter control bytes. Two id schemes, same as TerminalInput:
        // the DRM embedder sends X11 keysyms (0xFFE1…), the engine's own
        // GTK/Win32 embedders send Flutter logical ids (0x2_0000_010x).
        // Matching only the keysyms meant that on the GTK host Ctrl and
        // Shift were invisible: Ctrl+C typed a plain "c".
        if keyData.logical == 0xFFE1 || keyData.logical == 0xFFE2
            || keyData.logical == 0x2_0000_0102 || keyData.logical == 0x2_0000_0103 {
            _shiftDown = (keyData.type == .down || keyData.type == .repeat)
            return false
        }
        if keyData.logical == 0xFFE3 || keyData.logical == 0xFFE4
            || keyData.logical == 0x2_0000_0100 || keyData.logical == 0x2_0000_0101 {
            _ctrlDown = (keyData.type == .down || keyData.type == .repeat)
            return false
        }
        if keyData.logical == 0xFFE7 || keyData.logical == 0xFFE8
            || keyData.logical == 0x2_0000_0106 || keyData.logical == 0x2_0000_0107 {
            _metaDown = (keyData.type == .down || keyData.type == .repeat)
            return false
        }
        guard keyData.type == .down || keyData.type == .repeat else { return false }

        // Typing holds the cursor solid; it resumes blinking when idle.
        _blinkActivity()

        // While the find bar is open, keys edit the query and walk matches
        // instead of reaching the shell.
        if _searchActive { return _handleSearchKey(keyData) }

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
            if keyData.logical == 0x46 || keyData.logical == 0x66 {  // F/f
                _openSearch()
                return true
            }
        }

        #if os(macOS)
        // Cmd+C / Cmd+V / Cmd+F — the native macOS chords, beside the
        // Ctrl+Shift ones every platform gets.
        if _metaDown && !_ctrlDown {
            if keyData.logical == 0x43 || keyData.logical == 0x63 {  // C/c
                _copySelection()
                return true
            }
            if keyData.logical == 0x56 || keyData.logical == 0x76 {  // V/v
                _paste()
                return true
            }
            if keyData.logical == 0x46 || keyData.logical == 0x66 {  // F/f
                _openSearch()
                return true
            }
        }
        #endif

        // Shift+PageUp / Shift+PageDown page through scrollback.
        //
        // Both id schemes, and it took a while to notice this one was missing
        // the second: the DRM embedder sends X11 keysyms, everything else
        // sends Flutter logical ids, so matching only 0xFF55/0xFF56 meant
        // scrollback paging worked on the desktop and silently did nothing on
        // the Mac, GTK and Windows hosts. Note the pair is not in the same
        // ORDER in the two schemes — 0xFF55 is up, and it is 0x…0308 that is
        // up on the other side, with 0307 the down.
        let pgUp = keyData.logical == 0xFF55 || keyData.logical == 0x1_0000_0308
        let pgDown = keyData.logical == 0xFF56 || keyData.logical == 0x1_0000_0307
        if _shiftDown && (pgUp || pgDown) {
            _lock.lock()
            let page = max(1, emulator.rows - 1)
            let limit = emulator.scrollbackCount
            if pgUp {
                _viewOffset = min(_viewOffset + page, limit)
            } else {
                _viewOffset = max(_viewOffset - page, 0)
            }
            _lock.unlock()
            setState {}
            return true
        }

        // Any other key snaps the view back to the live screen and drops
        // the selection — and stops a fling mid-air, which would otherwise
        // scroll straight back out of the live screen it just snapped to.
        _flingGeneration += 1
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

        if let bytes = TerminalInput.bytes(
            for: keyData, appCursor: appCursor, shift: _shiftDown,
            ctrl: _ctrlDown) {
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

    // MARK: - Touch

    /// A finger going down decides nothing yet: inside the slop it may still
    /// become a tap (keyboard) or a long-press (selection); past it, a scroll.
    private func _touchBegan(_ event: PointerEvent) {
        _touchPointer = event.pointer
        _touchPhase = .undecided
        _touchStart = event.localPosition
        _touchLast = event.localPosition
        _touchLines = 0
        _touchSamples = [(Self._now(), event.localPosition.dy)]
        _longPressGeneration += 1
        let generation = _longPressGeneration
        let pointer = event.pointer
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.longPressTimeout
        ) { [weak self] in
            guard let self, generation == self._longPressGeneration,
                  self._touchPointer == pointer,
                  self._touchPhase == .undecided else { return }
            // The finger held still: a selection, anchored where it rests,
            // extended by whatever drag follows.
            self._touchPhase = .selecting
            let cell = self._cellAt(self._touchLast)
            self.setState {
                self._selecting = true
                self._selAnchor = cell
                self._selHead = cell
            }
        }
    }

    private func _touchMoved(_ event: PointerEvent) {
        let pos = event.localPosition
        if _touchPhase == .undecided {
            let dx = pos.dx - _touchStart.dx, dy = pos.dy - _touchStart.dy
            guard dx * dx + dy * dy > Self.touchSlop * Self.touchSlop else {
                _touchLast = pos
                return
            }
            _longPressGeneration += 1  // moved: no longer a long-press
            _touchPhase = .scrolling
            _touchLast = pos           // the slop is not scroll distance
            _touchSamples = [(Self._now(), pos.dy)]
            return
        }
        // .scrolling. Dragging DOWN pulls older lines into view: positive
        // lines walk back through history — the direct-manipulation
        // direction, opposite in sign to a trackpad's pan delta.
        let dy = pos.dy - _touchLast.dy
        _touchLast = pos
        let now = Self._now()
        _touchSamples.append((now, pos.dy))
        _touchSamples.removeAll { now - $0.t > 0.1 }
        _touchLines += dy / cellH
        let whole = _touchLines.rounded(.towardZero)
        guard whole != 0 else { return }
        _touchLines -= whole
        _scrollBy(lines: Int(whole), at: pos)
    }

    private func _touchEnded(_ event: PointerEvent) {
        _touchPointer = nil
        _longPressGeneration += 1
        let phase = _touchPhase
        _touchPhase = .undecided
        switch phase {
        case .undecided:
            // A tap: clears the selection, and asks for the keyboard.
            // Raised from the tap rather than from focus, because dismissing
            // it with the accessory bar's own button leaves this view focused
            // the whole time — keyed on focus, the tap that means "give it
            // back" would do nothing.
            if _selAnchor != nil || _selHead != nil {
                setState {
                    _selAnchor = nil
                    _selHead = nil
                }
            }
            SoftKeyboard.show()
        case .selecting:
            // The drag is over; the selection stays, for Copy.
            _selecting = false
        case .scrolling:
            _startFling(at: event.localPosition)
        }
    }

    /// Carry a released drag onward with UIScrollView's decay (0.998/ms).
    /// Scrollback only: a fling translated into arrow keys or wheel reports
    /// would hose the far application with input it never asked for.
    private func _startFling(at position: Offset) {
        _lock.lock()
        let plain = !emulator.altActive
            && !(emulator.mouseTracking && emulator.mouseSgr)
        _lock.unlock()
        guard plain, _touchSamples.count >= 2,
              let first = _touchSamples.first, let last = _touchSamples.last,
              last.t - first.t > 0.001 else { return }
        let velocity = (last.y - first.y) / (last.t - first.t)
        guard abs(velocity) > 200 else { return }
        _flingGeneration += 1
        _flingTick(_flingGeneration, velocity: velocity, carry: _touchLines,
                   position: position)
    }

    private func _flingTick(_ generation: Int, velocity: Double,
                            carry: Double, position: Offset) {
        let dt = 1.0 / 60.0
        DispatchQueue.main.asyncAfter(deadline: .now() + dt) { [weak self] in
            guard let self, generation == self._flingGeneration else { return }
            var carry = carry + velocity * dt / self.cellH
            let whole = carry.rounded(.towardZero)
            carry -= whole
            if whole != 0 {
                let before = self._viewOffset
                self._scrollBy(lines: Int(whole), at: position)
                // Pinned against an end of the scrollback: nothing further.
                if self._viewOffset == before { return }
            }
            let next = velocity * pow(0.998, dt * 1000)
            guard abs(next) > 40 else { return }
            self._flingTick(generation, velocity: next, carry: carry,
                            position: position)
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

    private func _measureCell(size: Double) {
        // Measure with the SAME style the rows are painted with — the fallback
        // list included. Measuring `family` alone means that if the primary
        // family ever fails to resolve, the painter answers with the platform's
        // default *proportional* font (an 'M' there is ~0.87em against a
        // monospace 0.60em) while the rows, which carry the fallback, still
        // render monospace. Nothing errors: the grid silently gets a cell 45%
        // too wide, so the block cursor is drawn oversized and walks further
        // right with every column.
        _fontSize = size
        // The style cache is keyed by colour and attributes only — size is not
        // part of the key because until now it could not change. It can now,
        // so a stale entry would paint the old size for every colour already
        // seen, i.e. almost everything on screen.
        _styleCache.removeAll(keepingCapacity: true)
        let painter = TextPainter(
            text: TextSpan(
                text: "MMMMMMMMMM",
                style: TextStyle(
                    fontSize: size,
                    fontFamily: font.family,
                    fontFamilyFallback: _fontFallback
                )
            ),
            textDirection: .ltr
        )
        painter.layout()
        if painter.width > 0 {
            cellW = painter.width / 10.0
            if size > 0 { _advanceRatio = cellW / size }
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
        } else if Self._useAtlas {
            _snapCellToDevicePixels()
        }
        // The height twin, for the same reason (see the side-by-side film
        // notes): ghostty quantizes its row to whole device pixels while we
        // keep the font's fractional line height, so equal fonts still drift
        // 0.33 device px per row and no window size can align the two grids.
        // Glyphs keep their natural metrics; rows just pack on the forced
        // pitch. Not a shipping knob.
        if let v = ProcessInfo.processInfo.environment["STARLING_CELL_H"],
           let forced = Double(v), forced > 0, cellH > 0 {
            cellH = forced
        }
    }

    /// Round the cell up to a whole number of DEVICE pixels.
    ///
    /// The atlas painter needs this, and it is the difference between a blit
    /// that resamples and one that does not. A slot is an integer number of
    /// device pixels; a measured cell is 7.8 logical, which at scale 2 is 15.6.
    /// So every glyph was rasterised into a 16 px slot — 2.5% larger than its
    /// natural size — and then scaled back down to 15.6, with a sub-pixel
    /// phase that differs per column. The result is soft text everywhere and,
    /// on box-drawing characters, a line whose brightness bands at every cell
    /// boundary. Snapped, `cellW * scale` is an integer, the atlas rasterises
    /// at native scale and the blit is exactly 1:1.
    ///
    /// Glyphs keep their natural advance and `_cellSpacing` makes up the
    /// difference, exactly as the bench knob above does — so the Text path
    /// stays on the grid too. This is deliberately gated on the atlas being
    /// enabled: it changes the column count for a given window (7.8 -> 8.0 is
    /// 2.5% fewer columns), which is not a change to make behind the shipping
    /// path's back.
    private func _snapCellToDevicePixels() {
        let scale = PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1
        guard scale > 0, cellW > 0 else { return }
        let snapped = (cellW * scale).rounded(.up) / scale
        guard snapped > 0, snapped != cellW else { return }
        _cellSpacing = snapped - cellW
        cellW = snapped
        // The height matters just as much — it sets the slot height and so the
        // vertical phase of every blit — but it is only ever used whole, so
        // rounding it does not need a spacing correction.
        cellH = (cellH * scale).rounded(.up) / scale
    }

    /// Re-measure so `_fitColumns` columns fill `width`, if that is not
    /// already what the current metrics do.
    ///
    /// Called from `build` rather than once at startup, because the width is
    /// not known at startup and does not stay still afterwards: on iOS the
    /// tree is mounted before the view has reported any size at all, and the
    /// device then rotates.
    @discardableResult
    private func _refit(width: Double) -> Bool {
        guard let columns = _fitColumns, width > 0 else { return false }
        _fittedWidth = width
        let usable = max(1, width - padding * 2)
        let size = (usable / Double(columns)) / _advanceRatio
        guard size > 0, abs(size - _fontSize) > 0.0001 else { return false }
        _measureCell(size: size)

        // `_measureCell` does not necessarily hand back the cell it was asked
        // for: with the atlas on it snaps the width UP to whole device pixels,
        // and `_gridSize` then lays out `columns` of them without dividing back
        // out — so the grid is wider than the width it was fitted to, by up to
        // one device pixel per column. At 80 columns on a 3x phone that is
        // ~26pt of a ~400pt screen running off the right edge: the rightmost
        // few columns are simply not on the display, which reads as the fit
        // being wrong rather than as a rounding step after it.
        //
        // Neither behaviour is wrong alone — snapping is what keeps a glyph
        // blit 1:1, and fitting is what keeps the column count fixed across a
        // rotation. They only disagree when both are on, which is now the
        // default. One correction is enough: the snap adds less than a device
        // pixel, so shrinking by the measured overflow cannot re-cross it.
        let laidOut = cellW * Double(columns)
        if laidOut > usable + 0.0001 {
            let corrected = size * (usable / laidOut)
            if corrected > 0 { _measureCell(size: corrected) }
        }
        return true
    }

    /// Clamp for a pinch. The lower bound is a grid narrower than any prompt
    /// is useful at; the upper is where a cell reaches one device pixel per
    /// stem and the text stops being text.
    private static let columnRange = 20...200

    private func _setColumns(_ columns: Int) {
        let clamped = min(max(columns, Self.columnRange.lowerBound),
                          Self.columnRange.upperBound)
        guard clamped != _fitColumns else { return }
        _fitColumns = clamped
        _refit(width: _fittedWidth)
        w.onFitColumnsChanged?(clamped)
        _showSizeHud()
        setState {}
    }

    private func _showSizeHud() {
        _lock.lock()
        let rows = emulator.rows
        _lock.unlock()
        _sizeHud = "\(_fitColumns ?? emulator.cols) × \(rows)"
        _hudGeneration += 1
        let generation = _hudGeneration
        // asyncAfter, not Timer: Foundation.Timer never fires on the DRM
        // embedder, so a Timer-based dismissal would leave the badge on screen
        // for ever on the desktop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self = self, self._hudGeneration == generation else { return }
            self.setState { self._sizeHud = nil }
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
        let rows = Int((size.height - padding * 2) / cellH)
        // A fitted font gets the column count it was fitted for, rather than
        // dividing back out: cellW came from `usable / columns`, so the
        // division is exact in real arithmetic and one ulp short of it in
        // floating point — which rounds down to 79 columns about as often as
        // 80, and silently, since both are plausible numbers.
        if let columns = _fitColumns {
            return (columns, max(2, rows))
        }
        let cols = Int((size.width - padding * 2) / cellW)
        return (max(4, cols), max(2, rows))
    }

    // MARK: - Search

    /// Keys while the find bar is open. The terminal owns the keyboard, so
    /// the bar has no focus node of its own: everything routes here and is
    /// consumed — a stray key must never leak through to the shell. Both
    /// logical-id schemes are matched, keysym and Flutter id, like
    /// TerminalInput.
    private func _handleSearchKey(_ keyData: KeyData) -> Bool {
        let logical = keyData.logical
        // Esc — or the opening chord again — closes. The view offset is
        // kept: the next ordinary keystroke snaps back to live, as always.
        let isF = logical == 0x46 || logical == 0x66
        var toggleChord = _ctrlDown && _shiftDown && isF
        #if os(macOS)
        toggleChord = toggleChord || (_metaDown && isF)  // Cmd+F, like open
        #endif
        if logical == 0xFF1B || logical == 0x1_0000_001B || toggleChord {
            _closeSearch()
            return true
        }
        if logical == 0xFF0D || logical == 0xFF8D
            || logical == 0x1_0000_000D || logical == 0x2_0000_020D {
            _stepSearch(older: !_shiftDown)  // Enter: older; Shift+Enter: newer
            return true
        }
        if logical == 0xFF52 || logical == 0x1_0000_0304 {  // Up
            _stepSearch(older: true)
            return true
        }
        if logical == 0xFF54 || logical == 0x1_0000_0301 {  // Down
            _stepSearch(older: false)
            return true
        }
        if logical == 0xFF08 || logical == 0x1_0000_0008 {  // Backspace
            if !_searchQuery.isEmpty {
                _searchQuery.removeLast()
                _runSearch()
            }
            return true
        }
        if !_ctrlDown, !_metaDown, let ch = keyData.character, !ch.isEmpty,
           let s = ch.unicodeScalars.first, s.value >= 0x20 {
            _searchQuery += ch
            _runSearch()
        }
        return true
    }

    private func _openSearch() {
        _searchActive = true
        _searchQuery = ""
        _searchMatches = []
        _searchCurrent = 0
        setState {}
    }

    private func _closeSearch() {
        _searchActive = false
        _searchMatches = []
        setState {}
    }

    /// Recompute matches for the current query, across scrollback + screen.
    private func _runSearch() {
        _searchMatches = []
        _searchCurrent = 0
        guard !_searchQuery.isEmpty else { setState {}; return }
        _lock.lock()
        let all = emulator.scrollback + emulator.grid
        _lock.unlock()
        var found: [(line: Int, col: Int, len: Int)] = []
        for (li, row) in all.enumerated() {
            // One Character per cell (blank = space), so Character distance
            // IS the cell column — the invariant _copySelection leans on.
            let text = String(row.map { $0.char })
            var from = text.startIndex
            while let r = text.range(of: _searchQuery, options: .caseInsensitive,
                                     range: from ..< text.endIndex) {
                found.append((line: li,
                              col: text.distance(from: text.startIndex, to: r.lowerBound),
                              len: text.distance(from: r.lowerBound, to: r.upperBound)))
                from = r.upperBound
            }
        }
        _searchMatches = found
        // Start at the newest match — the bottom of the buffer is where the
        // user's eyes are.
        _searchCurrent = max(0, found.count - 1)
        _jumpToCurrentMatch()
    }

    private func _stepSearch(older: Bool) {
        let n = _searchMatches.count
        guard n > 0 else { return }
        _searchCurrent = older ? (_searchCurrent + n - 1) % n
                               : (_searchCurrent + 1) % n
        _jumpToCurrentMatch()
    }

    /// Scroll so the current match is on screen: centred when it lives in
    /// scrollback, the live screen left where it is.
    private func _jumpToCurrentMatch() {
        guard _searchCurrent < _searchMatches.count else { setState {}; return }
        let m = _searchMatches[_searchCurrent]
        _lock.lock()
        let sb = emulator.scrollbackCount
        let rows = emulator.rows
        _lock.unlock()
        _viewOffset = m.line >= sb ? 0 : max(0, min(sb - m.line + rows / 2, sb))
        setState {}
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        // React to window resizes: recompute the grid from the view metrics.
        // When the font is fitted to a column count the size has to be redone
        // first — a rotation changes the width, and the whole point is that
        // the column count survives it and the glyphs grow instead.
        let logical = _viewLogicalSize()
        if logical.width != _fittedWidth { _refit(width: logical.width) }
        let (cols, rows) = _gridSize(for: logical)
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
        // Bumped once per feed by the core, so it is exactly "has anything
        // changed" for the painter's shouldRepaint. Scrollback position is
        // folded in because scrolling changes the visible rows without
        // touching the emulator.
        let gen = emulator.generation &+ UInt64(viewOffset)
        _lock.unlock()

        var layers: [Widget] = [
            Padding(
                padding: EdgeInsets(all: padding),
                child: Self._useAtlas
                    ? _gridPainterWidget(grid, cols: gridCols, generation: gen)
                    : _rowColumnWidget(grid)
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

        // Search highlights: every visible match washed translucent, the
        // current one brighter — macOS Terminal's yellow.
        if _searchActive && !_searchMatches.isEmpty {
            let base = sbCount - viewOffset
            for (i, m) in _searchMatches.enumerated() {
                let r = m.line - base
                guard r >= 0, r < grid.count else { continue }
                layers.append(Positioned(
                    left: padding + Double(m.col) * cellW,
                    top: padding + Double(r) * cellH,
                    child: SizedBox(
                        width: Double(m.len) * cellW,
                        height: cellH,
                        child: DecoratedBox(decoration: BoxDecoration(
                            color: Color(i == _searchCurrent ? 0xCCFFB300
                                                             : 0x5AFFD54A))))))
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
        // what the text shaper does with trailing spaces. The IME caret above
        // deliberately does not blink — only the drawn block does.
        if showCursor && _blinkOn {
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
        // The size badge, over everything.
        if let hud = _sizeHud {
            layers.append(Positioned(
                left: padding,
                top: padding,
                child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xCC000000)),
                    child: Padding(
                        padding: EdgeInsets(horizontal: 10, vertical: 6),
                        child: Text(hud, style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 13,
                            fontFamily: font.family,
                            fontFamilyFallback: _fontFallback))))))
        }

        // The find bar (Ctrl+Shift+F), top right like macOS Terminal's.
        // Not a focused text field — _handleSearchKey owns the keyboard
        // while it is open; "▏" is the standing caret.
        if _searchActive {
            let count = _searchMatches.isEmpty
                ? (_searchQuery.isEmpty ? "" : "  0/0")
                : "  \(_searchCurrent + 1)/\(_searchMatches.count)"
            layers.append(Positioned(
                top: padding,
                right: padding,
                child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xE6202329)),
                    child: Padding(
                        padding: EdgeInsets(horizontal: 10, vertical: 6),
                        child: Text("Find: \(_searchQuery)▏\(count)",
                                    style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 13,
                            fontFamily: font.family,
                            fontFamilyFallback: _fontFallback))))))
        }

        return Directionality(textDirection: .ltr, child: _withPinch(Listener(
            onPointerDown: { [self] event in
                focusNode.requestFocus()
                _pointers.insert(event.pointer)
                _flingGeneration += 1
                // A second finger is a pinch. Drop the selection it would
                // otherwise have been dragging out from under the first —
                // and the touch gesture in flight with it.
                if _pointers.count > 1 {
                    _longPressGeneration += 1
                    _touchPointer = nil
                    _touchPhase = .undecided
                    if _selecting || _selAnchor != nil {
                        setState {
                            _selecting = false
                            _selAnchor = nil
                            _selHead = nil
                        }
                    }
                    return
                }
                if event.kind == .touch {
                    _touchBegan(event)
                    return
                }
                guard event.buttons & 1 != 0 else { return }
                let cell = _cellAt(event.localPosition)
                setState {
                    _selecting = true
                    _selAnchor = cell
                    _selHead = cell
                }
            },
            onPointerMove: { [self] event in
                guard _pointers.count <= 1 else { return }
                if _touchPointer == event.pointer, _touchPhase != .selecting {
                    _touchMoved(event)
                    return
                }
                guard _selecting else { return }
                let cell = _cellAt(event.localPosition)
                if _selHead == nil || cell != _selHead! {
                    setState { _selHead = cell }
                }
            },
            onPointerUp: { [self] event in
                _pointers.remove(event.pointer)
                if _touchPointer == event.pointer {
                    _touchEnded(event)
                    return
                }
                guard _selecting else { return }
                _selecting = false
                // A click without a drag clears the selection.
                if let a = _selAnchor, let h = _selHead, a == h {
                    setState {
                        _selAnchor = nil
                        _selHead = nil
                    }
                    // ...and, where there is one, asks for the on-screen
                    // keyboard. Raised from the tap rather than from focus,
                    // because dismissing it with the bar's own button leaves
                    // this view focused the whole time — keyed on focus, the
                    // tap that means "give it back" would do nothing.
                    SoftKeyboard.show()
                }
            },
            onPointerCancel: { [self] event in
                _pointers.remove(event.pointer)
                _selecting = false
                if _touchPointer == event.pointer {
                    _touchPointer = nil
                    _touchPhase = .undecided
                    _longPressGeneration += 1
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
        )))
    }

    /// Wraps the grid in a pinch recognizer when the widget asked for one.
    ///
    /// Pinch moves the COLUMN COUNT, not a free-floating scale factor. That is
    /// the quantity a terminal is actually about — the far end is told it, and
    /// programs lay themselves out against it — and it keeps the grid exactly
    /// filling the width at every step, where a continuous scale leaves a
    /// ragged partial column that changes width as you pinch.
    private func _withPinch(_ child: Widget) -> Widget {
        guard w.pinchToZoom, _fitColumns != nil else { return child }
        return GestureDetector(
            onScaleStart: { [self] _ in _pinchColumns = _fitColumns },
            onScaleUpdate: { [self] details in
                guard let start = _pinchColumns, details.scale > 0 else { return }
                // Spreading the fingers magnifies, which means FEWER columns.
                _setColumns(Int((Double(start) / details.scale).rounded()))
            },
            onScaleEnd: { [self] _ in _pinchColumns = nil },
            child: child)
    }

    // MARK: - Grid rendering

    /// The per-cell atlas painter (docs/plans/terminal-perf-macos.md, Lever 2)
    /// is the DEFAULT as of 2026-08-13: measured at 44% less CPU on DOOM-Fire
    /// than the Text path at the same frame rate, and it fixes the three
    /// placement bugs a row-long paragraph cannot (wide-glyph centring, the
    /// monotonic-fallback dropout, CJK drift) plus the row-seam banding block
    /// content exposes live. The price, accepted deliberately: snapping the
    /// cell to whole device pixels costs ~2.5% of columns.
    ///
    /// `STARLING_TERM_ATLAS=0` opts back into the Text path below, which
    /// stays in-tree unchanged as the comparison baseline. "2" selects the
    /// cached-paragraph experiment (measured, and it lost — see the painter);
    /// the painter branches on `TerminalGridPainter.paragraphMode`.
    /// On everywhere, iOS included. iOS needed two fixes to get here: the
    /// engine snapshots pictures through the rasteriser in use rather than
    /// always Skia (SwiftBridgeEngineRegistry::SetSnapshotCallback — Impeller
    /// aborted otherwise), and the painter/atlas shape with `_shapedFont`, the
    /// FITTED size, not `w.font.size` (see the note on `_shapedFont`).
    private static let _useAtlas: Bool = {
        ProcessInfo.processInfo.environment["STARLING_TERM_ATLAS"] != "0"
    }()

    /// Rebuilt whenever the metrics it rasterised for move — cell size follows
    /// the font and the display, and a stale atlas would blit glyphs drawn for
    /// a different grid.
    private var _atlas: TerminalGlyphAtlas?

    private func _atlasForCurrentMetrics() -> TerminalGlyphAtlas {
        let scale = PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1
        if let a = _atlas, a.matches(cellW: cellW, cellH: cellH, scale: scale,
                                     family: font.family, fontSize: _shapedFont.size) {
            return a
        }
        let made = TerminalGlyphAtlas(
            cellW: cellW, cellH: cellH, scale: scale,
            family: font.family, fallback: _fontFallback, fontSize: _shapedFont.size)
        _atlas = made
        return made
    }

    /// Debug only: write what the painter draws to this path as raw RGBA.
    private static let _dumpPath =
        ProcessInfo.processInfo.environment["STARLING_TERM_DUMP"]

    /// The whole visible grid as one painted layer.
    private func _gridPainterWidget(_ grid: [[TermCell]], cols: Int,
                                    generation: UInt64) -> Widget {
        if let path = Self._dumpPath {
            let scale = PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1
            let size = Size(Double(cols) * cellW, Double(grid.count) * cellH)
            _makePainter(grid, cols: cols, generation: generation)
                .dumpRaw(to: path, size: size, scale: scale)
        }
        let size = Size(Double(cols) * cellW, Double(grid.count) * cellH)
        return SizedBox(
            width: size.width,
            height: size.height,
            child: CustomPaint(
                painter: _makePainter(grid, cols: cols, generation: generation),
                size: size
            )
        )
    }

    private func _makePainter(_ grid: [[TermCell]], cols: Int,
                              generation: UInt64) -> TerminalGridPainter {
        TerminalGridPainter(
            lines: grid,
            cols: cols,
            cellW: cellW,
            cellH: cellH,
            theme: theme,
            font: _shapedFont,
            fallbackFamilies: _fontFallback,
            atlas: _atlasForCurrentMetrics(),
            generation: generation,
            clusterText: { [emulator] in emulator.cellText($0) }
        )
    }

    /// The shipping path: one rich-text widget per row, stacked.
    private func _rowColumnWidget(_ grid: [[TermCell]]) -> Widget {
        var lines: [Widget] = []
        lines.reserveCapacity(grid.count)
        for line in grid {
            lines.append(_rowWidget(line))
        }
        return Column(crossAxisAlignment: .start, children: lines)
    }

    /// Renders one grid line as a single rich-text row of merged style runs.
    private func _rowWidget(_ line: [TermCell]) -> Widget {
        // Two layers, and the split is the point of this function. Cell
        // BACKGROUNDS are grid rectangles painted under the text; only glyphs
        // go through the text engine.
        //
        // They used to ride along as `TextStyle.backgroundColor`, which hands
        // the cell's paint job to the shaper — and the shaper answers with the
        // FONT's line box, not the cell. Two failures come straight out of
        // that, and `test/glyph-pixels.py` found both on its first run:
        //
        //   - a run with NO INK paints no background at all. Text layout
        //     excludes whitespace from the painted line, so a run of coloured
        //     spaces bounded by runs in other faces left a hole with the
        //     window showing through it. The ruler that gate paints — forty
        //     cells of alternating colour, every one a space — came out
        //     entirely blank, and the spaces between the runs of
        //     `日本語 ✓✗→ ⠋⠋ abcdef` were holes in the row.
        //   - the box is the FONT's line height. Measured against a 25.47 px
        //     row on this box: 19-23 px under Latin, 11 under ●, 6 under CJK.
        //     Every coloured cell was short, by an amount set by whichever
        //     family resolved the glyph in it, so a region filled in one
        //     colour showed seams wherever the script changed.
        //
        // Neither is visible to anything that compares the grid, which is why
        // both outlived every test in this tree: the cells carried the right
        // characters and the right colours throughout.
        //
        // The layer costs one widget per background RUN, and only on rows that
        // have one — every cell of an ordinary shell row carries bg 0, so the
        // hot path skips it whole. It also retires the special case this
        // function used to carry for background-colour erase (`ESC[41m` then
        // `ESC[K`), which was this same bug caught in the one place someone
        // noticed it: a coloured tail vanished at end of line and drew fine
        // with any glyph after it.
        //
        // Carried in locals and appended only where the colour changes. The
        // obvious spelling — extend `bgRuns.last` in place — puts an array
        // element write in a loop that runs once per cell of every row, and
        // the benchmark charged 8% of 03_sgr_fg for it: a row of coloured
        // FOREGROUNDS has one background run and gained a hundred writes to
        // build it. Here an ordinary row costs one comparison per cell and no
        // allocation at all, because the trailing default-coloured run is
        // never appended.
        var bgRuns: [(cells: Int, color: UInt32)] = []
        var runColor: UInt32 = 0
        var runLen = 0
        for cell in line {
            let bg = _paintedBG(cell)
            if bg == runColor {
                runLen += 1
                continue
            }
            if runLen > 0 { bgRuns.append((cells: runLen, color: runColor)) }
            runColor = bg
            runLen = 1
        }
        if runLen > 0, runColor != 0 || !bgRuns.isEmpty {
            bgRuns.append((cells: runLen, color: runColor))
        }
        while let last = bgRuns.last, last.color == 0 { bgRuns.removeLast() }

        // Trailing cells with neither ink nor an underline contribute nothing
        // to the text layer. Their colour, if they had one, is in bgRuns.
        var end = line.count
        while end > 0 {
            let cell = line[end - 1]
            guard cell.scalar == 32, !cell.attrs.contains(.underline) else { break }
            end -= 1
        }

        // Underlined spaces that END the line, drawn as a rule rather than
        // asked of the text engine.
        //
        // Keeping them in `end` above is necessary and not sufficient: text
        // layout excludes the line's trailing whitespace from what it PAINTS,
        // so a run with no ink in it draws no decoration either — `ESC[4m`
        // followed by spaces to end of line came out as nothing at all, while
        // the same run with any glyph after it drew a rule. Exactly the shape
        // of the background bug above, one attribute over, and invisible to
        // everything that reads the grid.
        //
        // Only the ink-less tail is drawn here; wherever the engine paints a
        // rule, it stays the engine's. test/glyph-pixels.py asserts the two
        // meet as one continuous rule.
        var inkEnd = end
        while inkEnd > 0, line[inkEnd - 1].scalar == 32 { inkEnd -= 1 }
        var ruleRuns: [(start: Int, cells: Int, color: UInt32)] = []
        var c = inkEnd
        while c < end {
            guard line[c].attrs.contains(.underline) else { c += 1; continue }
            let fg = line[c].fg == 0 ? theme.defaultForeground : line[c].fg
            let start = c
            while c < end, line[c].attrs.contains(.underline),
                  (line[c].fg == 0 ? theme.defaultForeground : line[c].fg) == fg {
                c += 1
            }
            ruleRuns.append((start: start, cells: c - start, color: fg))
        }

        var backdrop: Widget? = nil
        if !bgRuns.isEmpty || !ruleRuns.isEmpty {
            var layers: [Widget] = []
            if !bgRuns.isEmpty {
                var boxes: [Widget] = []
                boxes.reserveCapacity(bgRuns.count)
                for run in bgRuns {
                    boxes.append(SizedBox(
                        width: Double(run.cells) * cellW,
                        height: cellH,
                        child: run.color == 0
                            ? nil : ColoredBox(color: Color(Int(run.color)))))
                }
                layers.append(Row(mainAxisSize: .min, children: boxes))
            }
            if !ruleRuns.isEmpty {
                let rule = _underlineRect()
                // A Stack of only Positioned children has no size of its own,
                // and an underlined tail on a default-background row has no
                // background box to give it one — so state the extent.
                if bgRuns.isEmpty {
                    layers.append(SizedBox(width: Double(end) * cellW,
                                           height: cellH))
                }
                for run in ruleRuns {
                    layers.append(Positioned(
                        left: Double(run.start) * cellW,
                        top: rule.top,
                        child: SizedBox(
                            width: Double(run.cells) * cellW,
                            height: rule.height,
                            child: ColoredBox(color: Color(Int(run.color))))))
                }
            }
            backdrop = layers.count == 1 ? layers[0] : Stack(children: layers)
        }

        if end == 0 {
            guard let backdrop = backdrop else {
                return SizedBox(width: 1, height: cellH)
            }
            return SizedBox(height: cellH, child: backdrop)
        }

        var spans: [InlineSpan] = []
        var runText = ""
        var runStyle: _RunKey? = nil
        // Columns each finished run covers, and whether any cell in this row
        // needs a family other than the primary. Both feed the segmented
        // layout below; an all-ASCII row uses neither.
        var runColumns: [Int] = []
        var runCells = 0
        var needsFallback = false

        func flush() {
            guard let style = runStyle, !runText.isEmpty else { return }
            spans.append(TextSpan(text: runText, style: _textStyle(style)))
            runColumns.append(runCells)
            runText = ""
            runCells = 0
        }

        for c in 0 ..< end {
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
            // Only the foreground: the swapped background is the backdrop's
            // business, and _paintedBG resolved it there.
            if cell.attrs.contains(.reverse) {
                cell.fg = cell.bg == 0 ? theme.reverseBackground : cell.bg
                cell.attrs.remove(.reverse)
            }
            let key = _RunKey(fg: cell.fg, attrs: cell.attrs, spacing: spacing)
            if runStyle == nil {
                runStyle = key
            } else if runStyle! != key {
                flush()
                runStyle = key
            }
            if cell.scalar > 0x7F { needsFallback = true }
            runCells += columns
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
        // One paragraph per run, once the row needs a family we did not load
        // ourselves.
        //
        // Font fallback inside a paragraph is MONOTONIC: a run may resolve a
        // family at the same or a later index in `fontFamilyFallback` than
        // the run before it, never an earlier one. Measured on one row at a
        // time, same binary: `✓✗→ 日本語` (DejaVu at index 1, then Hiragino at
        // 3) draws; `日本語 ✓✗→` — the same two runs the other way round —
        // drops BOTH, and everything after them. Each family alone is fine,
        // and `日本語 안녕` (3 then 5, forward) is fine.
        //
        // **This is NOT macOS-only**, which is why the split below is not
        // platform-gated. The measurements here are from macOS, where the CJK
        // arrives through CoreText's own fallback rather than a family we
        // registered, so it looks at first like a CoreText quirk — but Linux,
        // where every fallback IS a family we loaded ourselves, shows the same
        // failure. Gating this to `#if os(macOS)` for the ~8% it costs
        // 05_unicode would put the bug straight back on Linux.
        // A colour-emoji run poisons every fallback run in its row outright.
        //
        // This is why `cat`ing the unicode benchmark corpus showed no CJK at
        // all: its line is `… αβγδ 日本語 中文 ✓✗→ ≤∞ 🎉🚀`, which walks the
        // chain backwards at ✓ and then hits emoji.
        //
        // Splitting the row into one Text per run gives each run its own
        // paragraph, so nothing walks backwards inside one. The cost is a
        // widget and a paragraph per run, so it is spent only where it buys
        // something: a row of pure ASCII — every hot benchmark row — stays a
        // single Text with all its spans, exactly as before. The engine bug
        // is upstream of us and this does not fix it, it routes around it;
        // the per-cell painter (docs/plans/terminal-perf-macos.md, Lever 2)
        // retires the whole class.
        let head: Widget
        if needsFallback && spans.count > 1 {
            var segments: [Widget] = []
            segments.reserveCapacity(spans.count)
            for (i, span) in spans.enumerated() {
                segments.append(SizedBox(
                    width: Double(runColumns[i]) * cellW,
                    height: cellH,
                    child: Text(rich: span, softWrap: false, maxLines: 1)))
            }
            head = SizedBox(height: cellH, child: Row(children: segments))
        } else {
            head = SizedBox(
                height: cellH,
                child: Text(
                    rich: TextSpan(children: spans),
                    softWrap: false,
                    maxLines: 1
                )
            )
        }
        guard let backdrop = backdrop else { return head }
        return SizedBox(height: cellH,
                        child: Stack(children: [backdrop, head]))
    }

    /// Where the text engine puts an underline, so the rule this painter draws
    /// for the runs it will not is the same rule.
    ///
    /// Measured off the primary family's own baseline — the same thing
    /// TerminalGlyphAtlas measures, and for the same reason: a constant
    /// fraction of the cell is right for one font at one size and wrong
    /// everywhere else. The offset and thickness below are proportions of the
    /// FONT, and `test/glyph-pixels.py` checks the join: a row of underlined
    /// text followed by underlined spaces has to come out as one unbroken
    /// rule, which fails the moment these drift from what the engine does.
    private func _underlineRect() -> (top: Double, height: Double) {
        if let cached = _underlineCache { return cached }
        let style = TextStyle(color: Color(0xFFFF_FFFF), fontSize: font.size,
                              fontFamily: font.family)
        let builder = ParagraphBuilders.create(
            style.getParagraphStyle(textDirection: .ltr))
        builder.pushStyle(style.getTextStyle(textScaler: TextScalers.noScaling))
        builder.addText("M")
        let p = builder.build()
        p.layout(ParagraphConstraints(width: Double.infinity))
        // At the baseline, not below it. Measured against the rule the engine
        // draws for the same font: a first attempt put the top a tenth of an
        // em lower, which came out two device pixels under the engine's and
        // showed as a step at the seam — the join row in test/glyph-pixels.py
        // is there to keep this honest.
        let made = (top: p.alphabeticBaseline,
                    height: max(1.0, (font.size / 14).rounded()))
        _underlineCache = made
        return made
    }
    private var _underlineCache: (top: Double, height: Double)?

    /// The colour a cell's background is actually painted in.
    ///
    /// Reverse video swaps the pair, and it has to be resolved here as well as
    /// in the text loop: the backdrop is built from the raw line, before that
    /// loop has touched anything.
    @inline(__always)
    private func _paintedBG(_ cell: TermCell) -> UInt32 {
        guard cell.attrs.contains(.reverse) else { return cell.bg }
        return cell.fg == 0 ? theme.defaultForeground : cell.fg
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
        // No background: it is painted by the row's backdrop now, so cells
        // that differ only in colour behind the glyph share one shaped run.
        let fg: UInt32, attrsRaw: UInt8, spacing: Double
        var attrs: CellAttrs { CellAttrs(rawValue: attrsRaw) }
        init(fg: UInt32, attrs: CellAttrs, spacing: Double) {
            self.fg = fg
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
            // No backgroundColor here: cell backgrounds are grid rects
            // painted under the text (a4543ca — the style's background takes
            // the FONT's line box, not the cell, and vanishes for ink-less
            // runs; test/glyph-pixels.py asserts the rects). The size is the
            // FITTED size, not w.font.size — see the note on `_shapedFont`.
            fontSize: _fontSize,
            fontWeight: style.attrs.contains(.bold) ? .w700 : .normal,
            fontStyle: style.attrs.contains(.italic) ? .italic : .normal,
            letterSpacing: style.spacing == 0 ? nil : style.spacing,
            decoration: style.attrs.contains(.underline) ? .underline : nil,
            fontFamily: font.family,
            fontFamilyFallback: _fontFallback
        )
    }
}
